import Foundation
import XCTest
@testable import Littera

/// LIT-001: copias de recuperación. Todo ocurre en directorios temporales
/// propios; nunca se usan documentos ni preferencias reales.
@MainActor
final class LitteraRecoveryTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")
    private let fileManager = FileManager.default
    private var directory: URL!
    private var recoveryDirectory: URL!

    override func setUpWithError() throws {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("LitteraRecovery-\(UUID().uuidString)", isDirectory: true)
        directory = root.appendingPathComponent("Documentos", isDirectory: true)
        recoveryDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? fileManager.removeItem(at: directory.deletingLastPathComponent())
    }

    // MARK: Utilidades

    private func makeRecovery() -> LitteraRecoveryStore {
        LitteraRecoveryStore(directory: recoveryDirectory)
    }

    private func makeStore(_ prompts: LitteraStubPrompts? = nil) -> LitteraDocumentStore {
        let store = LitteraDocumentStore.isolated(prompts: prompts ?? LitteraStubPrompts(), recovery: makeRecovery())
        store.recoveryDelay = 60
        store.autosaveDelay = 60
        return store
    }

    private func makeFile(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: url.path)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func snapshots() -> [LitteraRecoverySnapshot] {
        makeRecovery().load().snapshots
    }

    private func snapshot(_ documentID: String, revision: UInt64, _ markdown: String) -> LitteraRecoverySnapshot {
        LitteraRecoverySnapshot(
            documentID: documentID, revision: revision, savedAt: Date(), fileName: "a.md",
            filePath: nil, bookmark: nil, baseContentHash: nil, markdown: markdown
        )
    }

    /// Sesión anterior que terminó con `text` sin guardar en `url` (o en un
    /// documento nuevo si `url` es `nil`) y sin pasar por ningún cierre.
    private func leaveUnsavedSession(file url: URL?, text: String) {
        var store: LitteraDocumentStore? = makeStore()
        if let url {
            XCTAssertTrue(store!.openDocument(at: url, locale: locale))
        }
        store!.updateMarkdown(for: store!.activeDocumentID, text: text)
        store!.flushRecovery()
        store = nil
    }

    // MARK: 1. Documento nuevo sin guardar

    func testNewUnsavedDocumentGetsACopy() {
        let store = makeStore()
        store.updateMarkdown(for: store.activeDocumentID, text: "# Borrador\n")
        store.flushRecovery()

        let copies = snapshots()
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.markdown, "# Borrador\n")
        XCTAssertEqual(copies.first?.documentID, store.activeDocumentID)
        XCTAssertNil(copies.first?.filePath)
    }

    // MARK: 2. Documento existente modificado

    func testModifiedFileGetsACopyWithItsOrigin() throws {
        let url = try makeFile("a.md", "uno")
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        store.flushRecovery()

        let copy = try XCTUnwrap(snapshots().first)
        XCTAssertEqual(copy.markdown, "dos")
        XCTAssertEqual(copy.fileName, "a.md")
        XCTAssertEqual(copy.filePath, url.path)
        XCTAssertEqual(copy.baseContentHash, LitteraRecoverySnapshot.contentHash("uno"))
        XCTAssertEqual(try read(url), "uno", "La copia nunca escribe en el original")
    }

    func testCopyWaitsForThePauseAndKeepsTheLatestText() {
        let store = makeStore()
        store.recoveryDelay = 0.2
        store.updateMarkdown(for: store.activeDocumentID, text: "a")
        store.updateMarkdown(for: store.activeDocumentID, text: "ab")
        XCTAssertTrue(snapshots().isEmpty, "Sin copia antes de la pausa")
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(snapshots().map(\.markdown), ["ab"])
    }

    func testCopiesArePrivate() throws {
        let store = makeStore()
        store.updateMarkdown(for: store.activeDocumentID, text: "privado")
        store.flushRecovery()
        let copy = makeRecovery().fileURL(for: store.activeDocumentID)
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: recoveryDirectory.path)[.posixPermissions] as? Int, 0o700)
    }

    // MARK: 3. Cierre inesperado

    func testUnexpectedTerminationLeavesCopyAndOriginalUntouched() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "dos")
        XCTAssertEqual(snapshots().map(\.markdown), ["dos"])
        XCTAssertEqual(try read(url), "uno")
    }

    // MARK: 4. Recuperación tras reiniciar

    func testRecoveryAfterRestartReopensChangesWithoutSaving() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "dos")

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .recover
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)

        XCTAssertEqual(prompts.questions, ["recovery:a.md"])
        XCTAssertEqual(store.documents.count, 1, "Sustituye al documento vacío inicial")
        let document = try XCTUnwrap(store.activeDocument)
        XCTAssertEqual(document.markdown, "dos")
        XCTAssertEqual(document.savedMarkdown, "uno")
        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.fileURL.map(LitteraDocumentFile.normalized), LitteraDocumentFile.normalized(url))
        XCTAssertEqual(try read(url), "uno", "Nunca se sobrescribe el original automáticamente")
        // La copia pasa al documento recuperado: sigue protegida.
        XCTAssertEqual(snapshots().map(\.documentID), [document.id])
        XCTAssertEqual(snapshots().map(\.markdown), ["dos"])
    }

    // MARK: 5. Descartar

    func testDiscardRemovesCopiesAndKeepsOriginal() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "dos")

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .discard
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)
        store.flushRecovery()

        XCTAssertTrue(snapshots().isEmpty)
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertTrue(store.activeDocument?.isPristineUntitled ?? false)
        XCTAssertEqual(try read(url), "uno")
    }

    // MARK: 6. Posponer

    func testLaterKeepsCopiesForTheNextLaunch() {
        leaveUnsavedSession(file: nil, text: "borrador")

        let first = LitteraStubPrompts()
        first.recoveryChoice = .later
        let store = makeStore(first)
        store.offerRecovery(locale: locale)
        XCTAssertEqual(first.questions.count, 1)
        XCTAssertTrue(store.activeDocument?.isPristineUntitled ?? false)
        XCTAssertEqual(snapshots().map(\.markdown), ["borrador"])

        let second = LitteraStubPrompts()
        makeStore(second).offerRecovery(locale: locale)
        XCTAssertEqual(second.questions.count, 1, "Se vuelve a ofrecer en el siguiente arranque")
    }

    // MARK: 7. Guardado correcto

    func testSavingRemovesTheCopy() throws {
        let url = try makeFile("a.md", "uno")
        let store = makeStore()
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        store.flushRecovery()
        XCTAssertEqual(snapshots().count, 1)

        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        store.flushRecovery()
        XCTAssertTrue(snapshots().isEmpty)
        XCTAssertEqual(try read(url), "dos")
    }

    func testDiscardingAndClosingRemoveTheCopy() {
        let prompts = LitteraStubPrompts()
        prompts.unsavedChoice = .discard
        let store = makeStore(prompts)
        store.updateMarkdown(for: store.activeDocumentID, text: "uno")
        store.newDocument(locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        store.flushRecovery()
        XCTAssertEqual(snapshots().count, 2)

        store.discardChanges(for: store.documents[0].id)
        XCTAssertTrue(store.closeDocument(id: store.activeDocumentID, locale: locale))
        store.flushRecovery()
        XCTAssertTrue(snapshots().isEmpty)
    }

    func testCancelledCloseKeepsTheCopy() {
        let prompts = LitteraStubPrompts()
        prompts.unsavedChoice = .cancel
        let store = makeStore(prompts)
        store.updateMarkdown(for: store.activeDocumentID, text: "uno")
        store.flushRecovery()
        XCTAssertFalse(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertFalse(store.protectUnsavedDocuments(locale: locale))
        store.flushRecovery()
        XCTAssertEqual(snapshots().map(\.markdown), ["uno"])
    }

    // MARK: 8. Error al guardar

    func testSaveErrorKeepsTheCopy() throws {
        let url = try makeFile("a.md", "uno")
        let prompts = LitteraStubPrompts()
        let store = makeStore(prompts)
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        store.flushRecovery()

        // Carpeta de solo lectura: el guardado atómico no puede crear el temporal.
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        XCTAssertFalse(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        store.flushRecovery()

        XCTAssertEqual(prompts.errors, ["ui.error.al.guardar"])
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
        XCTAssertEqual(snapshots().map(\.markdown), ["dos"])
        XCTAssertEqual(try read(url), "uno")
    }

    // MARK: 9. Cambio externo

    func testExternalChangeKeepsBothVersions() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "mío")
        try Data("suyo".utf8).write(to: url)

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .recover
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)

        XCTAssertEqual(store.documents.count, 2)
        let original = try XCTUnwrap(store.documents.first { $0.fileURL != nil })
        XCTAssertEqual(original.markdown, "suyo")
        XCTAssertFalse(original.isDirty)
        let copy = try XCTUnwrap(store.documents.first { $0.fileURL == nil })
        XCTAssertEqual(copy.markdown, "mío")
        XCTAssertEqual(copy.fileName, "a (recuperado).md")
        XCTAssertTrue(copy.isDirty)
        XCTAssertEqual(try read(url), "suyo", "El cambio externo se conserva")
    }

    func testRecoveryAlreadySavedOnDiskIsNotOffered() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "dos")
        try Data("dos".utf8).write(to: url)

        let prompts = LitteraStubPrompts()
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)
        store.flushRecovery()
        XCTAssertTrue(prompts.questions.isEmpty)
        XCTAssertTrue(snapshots().isEmpty)
    }

    func testMissingOriginalIsRecoveredAsCopy() throws {
        let url = try makeFile("a.md", "uno")
        leaveUnsavedSession(file: url, text: "dos")
        try fileManager.removeItem(at: url)

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .recover
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)

        XCTAssertEqual(store.documents.map(\.markdown), ["dos"])
        XCTAssertNil(store.activeDocument?.fileURL)
        XCTAssertFalse(fileManager.fileExists(atPath: url.path), "No se recrea el archivo sin Guardar")
    }

    // MARK: 10. Varios documentos

    func testMultipleDocumentsAreRecovered() throws {
        let url = try makeFile("a.md", "uno")
        var previous: LitteraDocumentStore? = makeStore()
        previous!.updateMarkdown(for: previous!.activeDocumentID, text: "nuevo")
        previous!.openDocument(at: url, locale: locale)
        previous!.updateMarkdown(for: previous!.activeDocumentID, text: "dos")
        previous!.flushRecovery()
        let untitledName = previous!.documents[0].fileName
        previous = nil

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .recover
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)

        XCTAssertEqual(prompts.questions.count, 1)
        XCTAssertTrue(prompts.questions[0].contains(untitledName))
        XCTAssertTrue(prompts.questions[0].contains("a.md"))
        XCTAssertEqual(Set(store.documents.map(\.markdown)), ["nuevo", "dos"])
        XCTAssertTrue(store.documents.allSatisfy(\.isDirty))
        XCTAssertEqual(snapshots().count, 2)
    }

    // MARK: 11. Copia dañada

    func testCorruptCopyIsIgnoredAndKept() throws {
        leaveUnsavedSession(file: nil, text: "válido")
        let corrupt = recoveryDirectory.appendingPathComponent("dañada").appendingPathExtension(LitteraRecoveryStore.fileExtension)
        try Data("{ no es json".utf8).write(to: corrupt)

        let contents = makeRecovery().load()
        XCTAssertEqual(contents.snapshots.map(\.markdown), ["válido"])
        XCTAssertEqual(contents.unreadable.map(\.lastPathComponent), [corrupt.lastPathComponent])

        let prompts = LitteraStubPrompts()
        prompts.recoveryChoice = .recover
        let store = makeStore(prompts)
        store.offerRecovery(locale: locale)
        XCTAssertEqual(store.documents.map(\.markdown), ["válido"])
        XCTAssertTrue(fileManager.fileExists(atPath: corrupt.path), "La copia dañada no se borra")
    }

    // MARK: 12. Escrituras simultáneas

    func testConcurrentWritesKeepTheNewestRevision() {
        let recovery = makeRecovery()
        let revisions = Array(1...60).shuffled()
        DispatchQueue.concurrentPerform(iterations: revisions.count) { index in
            let revision = UInt64(revisions[index])
            recovery.save(LitteraRecoverySnapshot(
                documentID: "doc", revision: revision, savedAt: Date(), fileName: "a.md",
                filePath: nil, bookmark: nil, baseContentHash: nil, markdown: "v\(revision)"
            ))
        }
        recovery.flush()
        XCTAssertEqual(recovery.load().snapshots.map(\.markdown), ["v60"])
    }

    func testOlderTaskNeverOverwritesNewerOrResurrectsRemovedCopy() {
        let recovery = makeRecovery()
        recovery.save(snapshot("doc", revision: 5, "nuevo"))
        recovery.save(snapshot("doc", revision: 3, "viejo"))
        recovery.flush()
        XCTAssertEqual(recovery.load().snapshots.map(\.markdown), ["nuevo"])

        recovery.remove(documentID: "doc", revision: 6)
        recovery.save(snapshot("doc", revision: 4, "tardío"))
        recovery.flush()
        XCTAssertTrue(recovery.load().snapshots.isEmpty)
    }

    func testStoresWithoutRecoveryWriteNothing() {
        let store = LitteraDocumentStore.isolated()
        store.updateMarkdown(for: store.activeDocumentID, text: "x")
        store.flushRecovery()
        XCTAssertFalse(fileManager.fileExists(atPath: recoveryDirectory.path))
    }
}
