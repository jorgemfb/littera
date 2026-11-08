import Foundation
import XCTest
@testable import Littera

/// iCloud Drive simulado: qué archivos están «en la nube», su estado de
/// descarga y sus versiones en conflicto.
@MainActor
final class LitteraFakeCloud: LitteraCloudFileService {
    var iCloudPaths: Set<String> = []
    var status: [String: LitteraDownloadStatus] = [:]
    var conflictsByPath: [String: [LitteraConflictVersion]] = [:]
    var versionContents: [String: String] = [:]
    var startDownloadError: Error?
    private(set) var downloadsStarted: [String] = []
    private(set) var resolutions: [(path: String, versionID: String?)] = []

    private func key(_ url: URL) -> String { LitteraDocumentFile.normalized(url).path }

    func markInICloud(_ url: URL, status value: LitteraDownloadStatus = .available) {
        iCloudPaths.insert(key(url))
        status[key(url)] = value
    }

    func setStatus(_ url: URL, _ value: LitteraDownloadStatus) { status[key(url)] = value }

    func addConflict(_ url: URL, id: String, device: String, text: String, date: Date = Date()) {
        conflictsByPath[key(url), default: []].append(
            LitteraConflictVersion(id: id, deviceName: device, modificationDate: date)
        )
        versionContents[id] = text
    }

    func isInICloud(_ url: URL) -> Bool { iCloudPaths.contains(key(url)) }

    func downloadStatus(_ url: URL) -> LitteraDownloadStatus { status[key(url)] ?? .available }

    func startDownloading(_ url: URL) throws {
        if let startDownloadError { throw startDownloadError }
        downloadsStarted.append(key(url))
    }

    func conflicts(at url: URL) -> [LitteraConflictVersion] { conflictsByPath[key(url)] ?? [] }

    func contents(of version: LitteraConflictVersion, at url: URL) throws -> String {
        guard let text = versionContents[version.id] else { throw CocoaError(.fileReadUnknown) }
        return text
    }

    func resolveConflicts(at url: URL, using version: LitteraConflictVersion?) throws {
        if let version {
            // Como NSFileVersion.replaceItem: la otra versión pasa a ser el archivo.
            try Data((versionContents[version.id] ?? "").utf8).write(to: url, options: .atomic)
        }
        resolutions.append((key(url), version?.id))
        conflictsByPath[key(url)] = []
    }
}

@MainActor
final class LitteraCloudTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")
    private var directory: URL!
    private var cloud: LitteraFakeCloud!
    private var prompts: LitteraStubPrompts!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LitteraCloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cloud = LitteraFakeCloud()
        prompts = LitteraStubPrompts()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: url.path)
        return url
    }

    private func makeStore(defaults: UserDefaults? = nil, restoresSession: Bool = false, observesFiles: Bool = false) -> LitteraDocumentStore {
        let store = LitteraDocumentStore.isolated(
            prompts: prompts, defaults: defaults, restoresSession: restoresSession,
            cloud: cloud, observesFiles: observesFiles
        )
        store.downloadPollInterval = 0.02
        return store
    }

    private func spin(_ seconds: TimeInterval) {
        let done = expectation(description: "espera")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    // MARK: Ubicación

    func testICloudPathDetection() {
        XCTAssertTrue(LitteraStorageLocation.isICloudPath(URL(fileURLWithPath: "/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Notas/a.md")))
        XCTAssertFalse(LitteraStorageLocation.isICloudPath(URL(fileURLWithPath: "/Users/a/Documents/a.md")))
    }

    // MARK: Lectura y escritura coordinadas

    func testCoordinatedWriteAndReadRoundTrip() throws {
        let url = directory.appendingPathComponent("c.md")
        try LitteraDocumentFile.write("# Hola\n", to: url)
        XCTAssertEqual(try LitteraDocumentFile.read(url).markdown, "# Hola\n")
        try Data([0xFF, 0xFE, 0x00]).write(to: url)
        XCTAssertThrowsError(try LitteraDocumentFile.read(url)) { error in
            guard case LitteraDocumentFile.ReadError.notUTF8 = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: Descargas

    func testOpeningUndownloadedFileWaitsForDownload() throws {
        let url = try makeFile("nube.md", "desde iCloud")
        cloud.markInICloud(url, status: .needsDownload)
        let store = makeStore()
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        XCTAssertNil(store.documents.first { $0.fileURL != nil }, "No se lee antes de descargar")
        XCTAssertEqual(cloud.downloadsStarted.count, 1)

        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        XCTAssertEqual(cloud.downloadsStarted.count, 1, "No se pide dos veces")

        cloud.setStatus(url, .available)
        spin(0.2)
        XCTAssertEqual(store.activeDocument?.markdown, "desde iCloud")
        XCTAssertTrue(prompts.errors.isEmpty)
    }

    func testDownloadErrorIsReported() throws {
        let url = try makeFile("nube.md", "x")
        cloud.markInICloud(url, status: .needsDownload)
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        cloud.setStatus(url, .failed("Sin conexión"))
        spin(0.2)
        XCTAssertEqual(prompts.errors, ["ui.error.icloud"])
        XCTAssertNil(store.documents.first { $0.fileURL != nil })
    }

    func testDownloadTimeoutIsReported() throws {
        let url = try makeFile("nube.md", "x")
        cloud.markInICloud(url, status: .needsDownload)
        let store = makeStore()
        store.downloadTimeout = 0.1
        store.openDocument(at: url, locale: locale)
        spin(0.4)
        XCTAssertEqual(prompts.errors, ["ui.error.icloud"])
    }

    func testRestoringSessionDefersUndownloadedFiles() throws {
        let defaults = LitteraTestDefaults.make()
        let local = try makeFile("local.md", "local")
        let remote = try makeFile("remota.md", "remota")
        let first = makeStore(defaults: defaults)
        first.openDocument(at: local, locale: locale)
        first.openDocument(at: remote, locale: locale)

        cloud.markInICloud(remote, status: .needsDownload)
        let restored = makeStore(defaults: defaults, restoresSession: true)
        XCTAssertEqual(restored.documents.compactMap(\.fileURL?.lastPathComponent), ["local.md"])
        cloud.setStatus(remote, .available)
        spin(0.3)
        XCTAssertEqual(Set(restored.documents.compactMap(\.fileURL?.lastPathComponent)), ["local.md", "remota.md"])
    }

    // MARK: Conflictos

    func testConflictKeepBothOpensOtherVersionUnsaved() throws {
        let url = try makeFile("diario.md", "versión del Mac")
        cloud.markInICloud(url)
        cloud.addConflict(url, id: "v1", device: "iPhone de Jorge", text: "versión del iPhone")
        prompts.conflictChoice = .keepBoth
        let store = makeStore()
        store.openDocument(at: url, locale: locale)

        XCTAssertEqual(prompts.questions, ["conflict:diario.md:iPhone de Jorge"])
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "versión del Mac", "El archivo no cambia")
        let copy = try XCTUnwrap(store.documents.first { $0.fileURL == nil && $0.markdown == "versión del iPhone" })
        XCTAssertTrue(copy.isDirty)
        XCTAssertEqual(copy.fileName, "diario (versión de iPhone de Jorge).md")
        XCTAssertEqual(cloud.resolutions.map(\.versionID), [nil])
    }

    /// D50: un conflicto que llega en vivo no pregunta con Littera en segundo
    /// plano; pregunta al volver a la app.
    func testLiveConflictWaitsUntilTheAppIsActive() throws {
        let url = try makeFile("diario.md", "versión del Mac")
        cloud.markInICloud(url)
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        XCTAssertTrue(prompts.questions.isEmpty)

        cloud.addConflict(url, id: "v1", device: "iPad", text: "versión del iPad")
        store.isApplicationActive = { false }
        store.handlePresenterEvent(store.activeDocumentID, .newVersion)
        XCTAssertTrue(prompts.questions.isEmpty, "Sin preguntas en segundo plano")

        store.isApplicationActive = { true }
        store.checkConflicts(locale: locale)
        XCTAssertEqual(prompts.questions, ["conflict:diario.md:iPad"])
    }

    func testConflictKeepMine() throws {
        let url = try makeFile("diario.md", "mío")
        cloud.markInICloud(url)
        cloud.addConflict(url, id: "v1", device: "iPad", text: "suyo")
        prompts.conflictChoice = .keepMine
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "mío")
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(cloud.resolutions.map(\.versionID), [nil])
    }

    func testConflictUseOtherReplacesFileAndReloads() throws {
        let url = try makeFile("diario.md", "mío")
        cloud.markInICloud(url)
        cloud.addConflict(url, id: "viejo", device: "iPad", text: "antigua", date: Date(timeIntervalSinceNow: -100))
        cloud.addConflict(url, id: "nuevo", device: "iPhone", text: "reciente")
        prompts.conflictChoice = .useOther
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        XCTAssertEqual(cloud.resolutions.map(\.versionID), ["nuevo"], "Se usa la versión más reciente")
        XCTAssertEqual(store.activeDocument?.markdown, "reciente")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    func testUnreadableConflictLeavesEverythingUntouched() throws {
        let url = try makeFile("diario.md", "mío")
        cloud.markInICloud(url)
        cloud.addConflict(url, id: "v1", device: "iPad", text: "suyo")
        cloud.versionContents["v1"] = nil
        prompts.conflictChoice = .keepBoth
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        XCTAssertTrue(cloud.resolutions.isEmpty)
        XCTAssertEqual(prompts.errors, ["ui.error.icloud"])
        XCTAssertEqual(store.documents.count, 1)
    }

    func testLocalFilesAreNeverCheckedForConflicts() throws {
        let url = try makeFile("local.md", "texto")
        cloud.addConflict(url, id: "v1", device: "iPad", text: "otra")
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        store.checkConflicts(locale: locale)
        XCTAssertTrue(prompts.questions.isEmpty)
    }

    // MARK: Cambios en vivo (NSFilePresenter real)

    func testPresenterReloadsCleanDocumentOnCoordinatedChange() throws {
        let url = try makeFile("vivo.md", "uno")
        let store = makeStore(observesFiles: true)
        defer { store.stopObservingFiles() }
        store.openDocument(at: url, locale: locale)
        spin(0.2)

        // Otro proceso (iCloud Drive, otra app) escribe de forma coordinada.
        try LitteraDocumentFile.write("dos", to: url)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        let reloaded = expectation(description: "recarga")
        func check(_ attempts: Int) {
            if store.activeDocument?.markdown == "dos" { reloaded.fulfill(); return }
            guard attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { check(attempts - 1) }
        }
        check(40)
        wait(for: [reloaded], timeout: 6)
        XCTAssertTrue(prompts.questions.isEmpty)
    }

    func testLiveChangeWithLocalEditsWaitsToAsk() throws {
        let url = try makeFile("vivo.md", "uno")
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "mío")
        try Data("suyo".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        store.checkExternalChanges(locale: locale, interactive: false)
        XCTAssertTrue(prompts.questions.isEmpty, "Un aviso en vivo no interrumpe con preguntas")
        XCTAssertEqual(store.activeDocument?.markdown, "mío")

        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(prompts.questions, ["external:vivo.md"], "Al volver a la app sí se pregunta")
    }
}
