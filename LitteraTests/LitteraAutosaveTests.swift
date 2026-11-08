import Foundation
import XCTest
@testable import Littera

/// Guardado automático y carpeta predeterminada (D49).
@MainActor
final class LitteraAutosaveTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")
    private var directory: URL!
    private var defaults: UserDefaults!
    private var prompts: LitteraStubPrompts!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LitteraAutosave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = LitteraTestDefaults.make()
        prompts = LitteraStubPrompts()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(autosave: Bool) -> LitteraDocumentStore {
        defaults.set(autosave, forKey: LitteraPreferenceKeys.autosave)
        return LitteraDocumentStore.isolated(prompts: prompts, defaults: defaults)
    }

    private func makeFile(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: url.path)
        return url
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testDisabledByDefault() {
        let store = LitteraDocumentStore.isolated(prompts: prompts, defaults: defaults)
        XCTAssertFalse(store.autosaveEnabled)
    }

    func testAutosaveWritesFileBackedDocumentAfterPause() throws {
        let store = makeStore(autosave: true)
        store.autosaveDelay = 0.05
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "uno dos")
        XCTAssertEqual(try contents(url), "uno", "No se guarda en cada pulsación")

        let saved = expectation(description: "guardado automático")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { saved.fulfill() }
        wait(for: [saved], timeout: 2)

        XCTAssertEqual(try contents(url), "uno dos")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
        XCTAssertTrue(prompts.questions.isEmpty)
    }

    func testTypingKeepsPostponingTheSave() throws {
        let store = makeStore(autosave: true)
        store.autosaveDelay = 0.2
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "u")
        let midway = expectation(description: "a mitad")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            store.updateMarkdown(for: store.activeDocumentID, text: "uv")
            midway.fulfill()
        }
        wait(for: [midway], timeout: 1)
        let early = expectation(description: "antes de la nueva pausa")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { early.fulfill() }
        wait(for: [early], timeout: 1)
        XCTAssertEqual(try contents(url), "uno", "La pausa vuelve a empezar con cada edición")
        store.flushPendingAutosaves()
        XCTAssertEqual(try contents(url), "uv")
    }

    func testDisabledAutosaveNeverWrites() throws {
        let store = makeStore(autosave: false)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        XCTAssertFalse(store.autosave(documentID: store.activeDocumentID))
        store.flushPendingAutosaves()
        XCTAssertEqual(try contents(url), "uno")
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
    }

    func testUntitledDocumentsAreNotAutosaved() {
        let store = makeStore(autosave: true)
        store.updateMarkdown(for: store.activeDocumentID, text: "nuevo")
        XCTAssertFalse(store.autosave(documentID: store.activeDocumentID))
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
    }

    func testAutosaveNeverOverwritesExternalChanges() throws {
        let store = makeStore(autosave: true)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "mío")
        try Data("suyo".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)

        XCTAssertFalse(store.autosave(documentID: store.activeDocumentID))
        XCTAssertEqual(try contents(url), "suyo")
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
    }

    func testClosingWithAutosaveSavesWithoutAsking() throws {
        let store = makeStore(autosave: true)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "final")
        XCTAssertTrue(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertEqual(try contents(url), "final")
        XCTAssertTrue(prompts.questions.isEmpty)
    }

    func testQuittingWithAutosaveOnlyAsksForUntitledDocuments() throws {
        let store = makeStore(autosave: true)
        store.updateMarkdown(for: store.activeDocumentID, text: "sin archivo")
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "con archivo")

        prompts.unsavedChoice = .discard
        XCTAssertTrue(store.protectUnsavedDocuments(locale: locale))
        XCTAssertEqual(try contents(url), "con archivo")
        XCTAssertEqual(prompts.questions.count, 1, "Solo se pregunta por el documento sin archivo")
    }

    func testDefaultFolderRoundTrip() throws {
        XCTAssertNil(LitteraDefaultFolder.url(defaults))
        XCTAssertTrue(LitteraDefaultFolder.set(directory, defaults))
        XCTAssertEqual(
            LitteraDefaultFolder.url(defaults)?.standardizedFileURL.resolvingSymlinksInPath(),
            directory.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            LitteraDefaultFolder.displayName(for: defaults.data(forKey: LitteraPreferenceKeys.defaultFolderBookmark)),
            FileManager.default.displayName(atPath: directory.path)
        )
        LitteraDefaultFolder.set(nil, defaults)
        XCTAssertNil(LitteraDefaultFolder.url(defaults))
        XCTAssertNil(LitteraDefaultFolder.displayName(for: nil))
    }

    func testDeletedDefaultFolderIsIgnored() throws {
        let folder = directory.appendingPathComponent("borrada", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        LitteraDefaultFolder.set(folder, defaults)
        try FileManager.default.removeItem(at: folder)
        XCTAssertNil(LitteraDefaultFolder.url(defaults))
    }
}
