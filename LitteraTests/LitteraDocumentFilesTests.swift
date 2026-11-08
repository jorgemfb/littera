import Foundation
import XCTest
@testable import Littera

/// Respuestas fijas para las preguntas del almacén de documentos.
@MainActor
final class LitteraStubPrompts: LitteraDocumentPrompts {
    var unsavedChoice: LitteraUnsavedChoice = .cancel
    /// Respuestas sucesivas a «cambios sin guardar»; agotadas, `unsavedChoice`.
    var unsavedChoices: [LitteraUnsavedChoice] = []
    var externalChoice: LitteraExternalChangeChoice = .keepMine
    var overwrite = false
    var conflictChoice: LitteraConflictChoice = .keepBoth
    var recoveryChoice: LitteraRecoveryChoice = .later
    private(set) var questions: [String] = []
    private(set) var errors: [String] = []

    func unsavedChanges(fileName: String, locale: Locale) -> LitteraUnsavedChoice {
        questions.append("unsaved:\(fileName)")
        return unsavedChoices.isEmpty ? unsavedChoice : unsavedChoices.removeFirst()
    }

    func externalChange(fileName: String, locale: Locale) -> LitteraExternalChangeChoice {
        questions.append("external:\(fileName)")
        return externalChoice
    }

    func confirmOverwrite(fileName: String, locale: Locale) -> Bool {
        questions.append("overwrite:\(fileName)")
        return overwrite
    }

    func conflict(fileName: String, deviceName: String?, date: Date?, locale: Locale) -> LitteraConflictChoice {
        questions.append("conflict:\(fileName):\(deviceName ?? "-")")
        return conflictChoice
    }

    func showError(titleKey: String, detail: String, locale: Locale) {
        errors.append(titleKey)
    }

    func recovery(fileNames: [String], locale: Locale) -> LitteraRecoveryChoice {
        questions.append("recovery:\(fileNames.joined(separator: "|"))")
        return recoveryChoice
    }
}

extension LitteraDocumentStore {
    /// Almacén con Preferencias propias: las pruebas nunca tocan la sesión real.
    static func isolated(
        prompts: LitteraDocumentPrompts? = nil,
        defaults: UserDefaults? = nil,
        restoresSession: Bool = false,
        cloud: LitteraCloudFileService? = nil,
        observesFiles: Bool = false,
        recovery: LitteraRecoveryStore? = nil
    ) -> LitteraDocumentStore {
        LitteraDocumentStore(
            defaults: defaults ?? LitteraTestDefaults.make(),
            prompts: prompts ?? LitteraStubPrompts(),
            restoresSession: restoresSession,
            cloud: cloud ?? LitteraFakeCloud(),
            observesFiles: observesFiles,
            recovery: recovery
        )
    }
}

@MainActor
final class LitteraDocumentFilesTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LitteraTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        try setDate(url, Date(timeIntervalSinceNow: -60))
        return url
    }

    /// Escritura "externa" con una fecha posterior, como haría otra app.
    private func writeExternally(_ url: URL, _ text: String) throws {
        try Data(text.utf8).write(to: url)
        try setDate(url, Date())
    }

    private func setDate(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: Abrir y cerrar

    func testOpeningReplacesPristineUntitledAndReopeningActivates() throws {
        let store = LitteraDocumentStore.isolated()
        let url = try makeFile("a.md", "# A")
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(store.activeDocument?.markdown, "# A")

        store.newDocument(locale: locale)
        XCTAssertEqual(store.documents.count, 2)
        store.updateMarkdown(for: store.activeDocumentID, text: "borrador")
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        XCTAssertEqual(store.documents.count, 2, "Abrir un archivo ya abierto solo lo activa")
        XCTAssertEqual(store.activeDocument?.fileURL, url)
    }

    func testOpeningNonUTF8FileShowsError() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        let url = directory.appendingPathComponent("latin1.md")
        try Data([0x66, 0xF1, 0xFF]).write(to: url)
        XCTAssertFalse(store.openDocument(at: url, locale: locale))
        XCTAssertEqual(prompts.errors, ["ui.error.al.abrir"])
    }

    func testClosingLastDocumentLeavesAnEmptyDocument() throws {
        let store = LitteraDocumentStore.isolated()
        let url = try makeFile("a.md", "texto")
        store.openDocument(at: url, locale: locale)
        XCTAssertTrue(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertTrue(store.activeDocument?.isPristineUntitled == true)
    }

    func testClosingActivatesNeighbour() throws {
        let store = LitteraDocumentStore.isolated()
        store.openDocument(at: try makeFile("a.md", "a"), locale: locale)
        store.openDocument(at: try makeFile("b.md", "b"), locale: locale)
        store.openDocument(at: try makeFile("c.md", "c"), locale: locale)
        store.activeDocumentID = store.documents[1].id
        store.closeDocument(id: store.activeDocumentID, locale: locale)
        XCTAssertEqual(store.documents.map(\.fileName), ["a.md", "c.md"])
        XCTAssertEqual(store.activeDocument?.fileName, "c.md")
    }

    func testClosingDirtyDocumentAsksAndRespectsCancelAndDiscard() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        store.openDocument(at: try makeFile("a.md", "a"), locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "a cambiado")

        prompts.unsavedChoice = .cancel
        XCTAssertFalse(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertEqual(store.activeDocument?.markdown, "a cambiado")

        prompts.unsavedChoice = .discard
        XCTAssertTrue(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertTrue(store.activeDocument?.isPristineUntitled == true)
        XCTAssertEqual(prompts.questions, ["unsaved:a.md", "unsaved:a.md"])
    }

    /// Al salir: «No guardar» en el primero y «Cancelar» en el segundo no
    /// puede descartar las ediciones del primero.
    func testCancellingQuitKeepsEditsOfDocumentsAlreadyAnsweredDiscard() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        store.openDocument(at: try makeFile("a.md", "a"), locale: locale)
        let first = store.activeDocumentID
        store.updateMarkdown(for: first, text: "a valioso")
        store.openDocument(at: try makeFile("b.md", "b"), locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "b valioso")

        prompts.unsavedChoices = [.discard, .cancel]
        XCTAssertFalse(store.protectUnsavedDocuments(locale: locale))
        let document = try XCTUnwrap(store.documents.first { $0.id == first })
        XCTAssertEqual(document.markdown, "a valioso")
        XCTAssertTrue(document.isDirty)

        prompts.unsavedChoices = [.discard, .discard]
        XCTAssertTrue(store.protectUnsavedDocuments(locale: locale))
        XCTAssertEqual(store.documents.map(\.markdown), ["a", "b"])
        XCTAssertFalse(store.documents.contains(where: \.isDirty))
    }

    // MARK: Cambios externos

    func testExternalChangeReloadsCleanDocumentSilently() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        try writeExternally(url, "dos")
        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "dos")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
        XCTAssertTrue(prompts.questions.isEmpty)
    }

    func testExternalChangeWithLocalEditsAsks() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "mío")
        try writeExternally(url, "suyo")

        prompts.externalChoice = .keepMine
        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "mío")
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
        XCTAssertEqual(prompts.questions, ["external:a.md"])

        // Tras elegir «Mantener mi versión», guardar no vuelve a preguntar.
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mío")
        XCTAssertEqual(prompts.questions, ["external:a.md"])
    }

    func testExternalChangeReloadChoice() throws {
        let prompts = LitteraStubPrompts()
        prompts.externalChoice = .reload
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "mío")
        try writeExternally(url, "suyo")
        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "suyo")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    func testDeletedFileKeepsTextAndMarksItUnsaved() throws {
        let store = LitteraDocumentStore.isolated()
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        try FileManager.default.removeItem(at: url)
        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "uno")
        XCTAssertTrue(store.activeDocument?.isMissingOnDisk ?? false)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)

        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertFalse(store.activeDocument?.isMissingOnDisk ?? true)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "uno")
    }

    func testSavingOverExternalChangeRequiresConfirmation() throws {
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        let url = try makeFile("a.md", "uno")
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "mío")
        try writeExternally(url, "suyo")

        prompts.overwrite = false
        XCTAssertFalse(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "suyo")

        prompts.overwrite = true
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mío")
    }

    // MARK: Recientes y sesión

    func testRecentsAreMostRecentFirstWithoutDuplicatesAndCapped() {
        var recents: [LitteraRecentDocument] = []
        for index in 0..<12 {
            recents = LitteraDocumentPersistence.adding(.init(path: "/d/\(index).md", bookmark: Data([1])), to: recents)
        }
        recents = LitteraDocumentPersistence.adding(.init(path: "/d/5.md", bookmark: Data([2])), to: recents)
        XCTAssertEqual(recents.count, LitteraDocumentPersistence.maximumRecents)
        XCTAssertEqual(recents.first?.path, "/d/5.md")
        XCTAssertEqual(recents.filter { $0.path == "/d/5.md" }.count, 1)
    }

    func testOpeningAddsRecentAndSessionIsRestored() throws {
        let defaults = LitteraTestDefaults.make()
        let store = LitteraDocumentStore.isolated(defaults: defaults)
        let first = try makeFile("a.md", "a")
        let second = try makeFile("b.md", "b")
        store.openDocument(at: first, locale: locale)
        store.openDocument(at: second, locale: locale)
        store.newDocument(locale: locale)
        store.activeDocumentID = store.documents[0].id
        XCTAssertEqual(store.recentDocuments.map(\.fileName), ["b.md", "a.md"])

        let restored = LitteraDocumentStore.isolated(defaults: defaults, restoresSession: true)
        XCTAssertEqual(restored.documents.map(\.fileName), ["a.md", "b.md"], "Los documentos sin guardar no se restauran")
        XCTAssertEqual(restored.activeDocument?.fileName, "a.md")
        XCTAssertEqual(restored.recentDocuments.map(\.fileName), ["b.md", "a.md"])

        let disabled = LitteraDocumentStore.isolated(defaults: defaults, restoresSession: false)
        XCTAssertTrue(disabled.activeDocument?.isPristineUntitled == true)
    }

    /// Un archivo que no se puede leer en un arranque (permisos, volumen sin
    /// montar) no desaparece de la sesión; uno borrado, sí.
    func testSessionKeepsEntriesThatFailTransientlyAndForgetsDeletedFiles() throws {
        let defaults = LitteraTestDefaults.make()
        let locked = try makeFile("bloqueado.md", "uno")
        let deleted = try makeFile("borrado.md", "dos")
        let first = LitteraDocumentStore.isolated(defaults: defaults)
        first.openDocument(at: locked, locale: locale)
        first.openDocument(at: deleted, locale: locale)
        XCTAssertEqual(LitteraDocumentPersistence.loadSession(defaults)?.entries.count, 2)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        try FileManager.default.removeItem(at: deleted)
        let second = LitteraDocumentStore.isolated(defaults: defaults, restoresSession: true)
        XCTAssertTrue(second.activeDocument?.isPristineUntitled == true)
        let kept = LitteraDocumentPersistence.loadSession(defaults)?.entries.map { ($0.path as NSString).lastPathComponent }
        XCTAssertEqual(kept, ["bloqueado.md"])

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        let third = LitteraDocumentStore.isolated(defaults: defaults, restoresSession: true)
        XCTAssertEqual(third.documents.compactMap(\.fileURL?.lastPathComponent), ["bloqueado.md"])
        XCTAssertEqual(LitteraDocumentPersistence.loadSession(defaults)?.entries.count, 1, "Sin duplicados al volver a abrirse")
    }

    func testDiskStateComparison() {
        let date = Date()
        XCTAssertEqual(LitteraDiskState.compare(known: date, current: date, fileExists: true), .unchanged)
        XCTAssertEqual(LitteraDiskState.compare(known: date, current: date.addingTimeInterval(1), fileExists: true), .modified)
        XCTAssertEqual(LitteraDiskState.compare(known: date, current: nil, fileExists: false), .deleted)
    }
}

/// H12: un documento que Finder mueve a la Papelera no sigue guardándose allí.
@MainActor
final class LitteraTrashMoveTests: XCTestCase {
    func testMovingToTrashKeepsTextUnsavedAndSaveRecreatesTheOriginal() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Trash-\(UUID().uuidString)", isDirectory: true)
        let trash = directory.appendingPathComponent(".Trash", isDirectory: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nota.md")
        try Data("uno".utf8).write(to: url)
        let locale = Locale(identifier: "es_ES")
        let store = LitteraDocumentStore.isolated()
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        let trashed = trash.appendingPathComponent("nota.md")
        try fm.moveItem(at: url, to: trashed)

        store.handlePresenterEvent(store.activeDocumentID, .moved(trashed))
        XCTAssertEqual(store.activeDocument?.fileURL, url, "No adopta la ruta de la Papelera")
        XCTAssertTrue(store.activeDocument?.isMissingOnDisk ?? false)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)

        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "dos")
        XCTAssertEqual(try String(contentsOf: trashed, encoding: .utf8), "uno", "La copia de la Papelera no se toca")
    }

    func testMovingElsewhereFollowsTheFile() throws {
        XCTAssertFalse(LitteraDocumentStore.isInTrash(URL(fileURLWithPath: "/Users/a/Documents/Proyecto/nota.md")))
        XCTAssertTrue(LitteraDocumentStore.isInTrash(URL(fileURLWithPath: "/Users/a/.Trash/nota.md")))
        XCTAssertTrue(LitteraDocumentStore.isInTrash(URL(fileURLWithPath: "/Volumes/Disco/.Trashes/501/nota.md")))
    }
}

/// H13: los accesos de seguridad que abre un marcador se cierran al cerrar
/// el documento.
@MainActor
final class LitteraSecurityScopeTests: XCTestCase {
    func testClosingADocumentOpenedFromABookmarkEndsItsAccess() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Scope-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a.md")
        try Data("uno".utf8).write(to: url)
        let bookmark = try XCTUnwrap(LitteraDocumentFile.bookmark(for: url))
        let resolved = try XCTUnwrap(LitteraDocumentFile.resolve(bookmark))
        guard LitteraDocumentFile.hasOpenAccess(to: resolved) else {
            throw XCTSkip("En este entorno el marcador no abre un acceso de seguridad")
        }
        _ = LitteraDocumentFile.resolve(bookmark)

        let store = LitteraDocumentStore.isolated()
        let locale = Locale(identifier: "es_ES")
        XCTAssertTrue(store.openDocument(at: resolved, locale: locale))
        XCTAssertTrue(store.closeDocument(id: store.activeDocumentID, locale: locale))
        XCTAssertFalse(LitteraDocumentFile.hasOpenAccess(to: resolved), "Cerrar el documento cierra el acceso")
    }
}
