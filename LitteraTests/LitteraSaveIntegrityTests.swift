import Darwin
import Foundation
import XCTest
@testable import Littera

/// LIT-012: qué conserva el guardado atómico. Todo ocurre en un directorio
/// temporal propio; nunca se usan documentos del usuario.
@MainActor
final class LitteraSaveIntegrityTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")
    private let fileManager = FileManager.default
    private var directory: URL!

    override func setUpWithError() throws {
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("LitteraSaveIntegrity-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: directory)
    }

    private func makeFile(_ name: String, _ text: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func isSymbolicLink(_ url: URL) throws -> Bool {
        try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeSymbolicLink
    }

    // MARK: Enlaces simbólicos (corregido)

    func testWritingThroughSymbolicLinkKeepsLinkAndUpdatesTarget() throws {
        let target = try makeFile("destino.md", "uno")
        let link = directory.appendingPathComponent("enlace.md")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        try LitteraDocumentFile.write("dos", to: link)

        XCTAssertTrue(try isSymbolicLink(link), "El enlace no debe sustituirse por un archivo")
        XCTAssertEqual(try read(target), "dos")
        XCTAssertEqual(try read(link), "dos")
    }

    func testSavingDocumentOpenedThroughSymbolicLinkKeepsLink() throws {
        let target = try makeFile("destino.md", "# Uno")
        let link = directory.appendingPathComponent("enlace.md")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        let store = LitteraDocumentStore.isolated()

        XCTAssertTrue(store.openDocument(at: link, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: "# Dos")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))

        XCTAssertTrue(try isSymbolicLink(link))
        XCTAssertEqual(try read(target), "# Dos")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    /// El enlace y su destino con fechas distintas: antes se comparaba la del
    /// enlace con la del destino y todo guardado parecía un conflicto.
    func testSymbolicLinkUsesTheTargetDateForSavesAndExternalChanges() throws {
        let target = try makeFile("destino.md", "uno")
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: target.path)
        let link = directory.appendingPathComponent("enlace.md")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(LitteraDocumentFile.modificationDate(of: link), LitteraDocumentFile.modificationDate(of: target))

        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        XCTAssertTrue(store.openDocument(at: link, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try read(target), "dos")
        XCTAssertTrue(try isSymbolicLink(link))
        XCTAssertTrue(prompts.questions.isEmpty)
        XCTAssertTrue(prompts.errors.isEmpty)

        try Data("tres".utf8).write(to: target)
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: target.path)
        store.checkExternalChanges(locale: locale)
        XCTAssertEqual(store.activeDocument?.markdown, "tres", "Un cambio en el destino se recarga")
    }

    func testWritingRegularFileStillWorksAndKeepsContentExact() throws {
        let url = try makeFile("a.md", "uno")
        let markdown = "---\ntitle: hola\n---\n\"texto\" --x (c) ñ 😀\n"
        try LitteraDocumentFile.write(markdown, to: url)
        XCTAssertEqual(try read(url), markdown)
        XCTAssertFalse(try isSymbolicLink(url))
    }

    func testWritingNewFileCreatesIt() throws {
        let url = directory.appendingPathComponent("nuevo.md")
        try LitteraDocumentFile.write("hola", to: url)
        XCTAssertEqual(try read(url), "hola")
    }

    func testVerifiedWriteDoesNotRecreateAFileDeletedBeforeCoordination() throws {
        let url = try makeFile("eliminado.md", "uno")
        let knownDate = try XCTUnwrap(LitteraDocumentFile.modificationDate(of: url))
        try fileManager.removeItem(at: url)

        XCTAssertThrowsError(try LitteraDocumentFile.writeVerified("dos", to: url, knownDate: knownDate)) { error in
            guard case LitteraDocumentFile.WriteConflictError.externallyModified = error else {
                return XCTFail("Se esperaba un conflicto de escritura, llegó: \(error)")
            }
        }
        XCTAssertFalse(fileManager.fileExists(atPath: url.path), "Un autosave no debe recrear un archivo eliminado")
    }

    func testPermissionsArePreserved() throws {
        let url = try makeFile("a.md", "uno")
        try fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        try LitteraDocumentFile.write("dos", to: url)
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o640)
    }

    /// El reemplazo atómico renombraba sobre un archivo 0444 y lo sobrescribía.
    func testReadOnlyFileIsNeverOverwritten() throws {
        let url = try makeFile("solo-lectura.md", "uno")
        try fileManager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)

        XCTAssertThrowsError(try LitteraDocumentFile.write("dos", to: url)) { error in
            guard case LitteraDocumentFile.WriteError.readOnly = error else {
                return XCTFail("Se esperaba solo lectura, llegó: \(error)")
            }
        }
        XCTAssertEqual(try read(url), "uno")

        let prompts = LitteraStubPrompts()
        let defaults = LitteraTestDefaults.make()
        defaults.set(true, forKey: LitteraPreferenceKeys.autosave)
        let store = LitteraDocumentStore.isolated(prompts: prompts, defaults: defaults)
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: "tres")
        XCTAssertFalse(store.autosave(documentID: store.activeDocumentID))
        XCTAssertFalse(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(prompts.errors, ["ui.error.al.guardar"])
        XCTAssertEqual(try read(url), "uno")
        XCTAssertTrue(store.activeDocument?.isDirty ?? false, "El texto sigue en el editor, sin guardar")
        XCTAssertEqual(try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o444)
    }

    /// H18: un archivo con marca de orden de bytes UTF-8 la conserva al
    /// guardarse; uno sin ella no la gana.
    func testByteOrderMarkIsPreservedOnlyWhenPresent() throws {
        let marked = directory.appendingPathComponent("bom.md")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("# Título\r\nTexto".utf8)).write(to: marked)
        let plain = try makeFile("plano.md", "# Título")
        let store = LitteraDocumentStore.isolated()
        let locale = Locale(identifier: "es_ES")

        XCTAssertTrue(store.openDocument(at: marked, locale: locale))
        XCTAssertEqual(store.activeDocument?.markdown, "# Título\r\nTexto", "El texto no incluye la marca")
        store.updateMarkdown(for: store.activeDocumentID, text: "# Título\r\nTexto nuevo")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try Data(contentsOf: marked), Data([0xEF, 0xBB, 0xBF]) + Data("# Título\r\nTexto nuevo".utf8))

        XCTAssertTrue(store.openDocument(at: plain, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: "# Otro")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try Data(contentsOf: plain), Data("# Otro".utf8))
    }

    // MARK: Metadatos del archivo

    func testExtendedAttributesArePreserved() throws {
        let url = try makeFile("a.md", "uno")
        let value = "valor"
        let set = url.withUnsafeFileSystemRepresentation { setxattr($0!, "com.littera.prueba", value, value.utf8.count, 0, 0) }
        XCTAssertEqual(set, 0)
        try LitteraDocumentFile.write("dos", to: url)
        let length = url.withUnsafeFileSystemRepresentation { getxattr($0!, "com.littera.prueba", nil, 0, 0, 0) }
        XCTAssertEqual(length, value.utf8.count)
    }

    /// En el sandbox todo archivo nuevo lleva `com.apple.quarantine`, que no se
    /// puede reescribir: antes el contenido se guardaba y aun así se informaba
    /// de un error, y el documento seguía «sin guardar».
    func testQuarantinedFileSavesThroughTheStoreAndKeepsOtherAttributes() throws {
        let url = try makeFile("cuarentena.md", "uno")
        let value = "valor"
        XCTAssertEqual(url.withUnsafeFileSystemRepresentation { setxattr($0!, "com.littera.prueba", value, value.utf8.count, 0, 0) }, 0)
        let hasQuarantine = url.withUnsafeFileSystemRepresentation { getxattr($0!, "com.apple.quarantine", nil, 0, 0, 0) } >= 0
        let prompts = LitteraStubPrompts()
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        XCTAssertTrue(store.openDocument(at: url, locale: locale))

        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: "tres")
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))

        XCTAssertEqual(try read(url), "tres")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
        XCTAssertTrue(prompts.questions.isEmpty, "El segundo guardado no debe preguntar por un cambio externo")
        XCTAssertTrue(prompts.errors.isEmpty)
        let length = url.withUnsafeFileSystemRepresentation { getxattr($0!, "com.littera.prueba", nil, 0, 0, 0) }
        XCTAssertEqual(length, value.utf8.count)
        if !hasQuarantine { print("Aviso: el archivo de prueba no tenía cuarentena en este entorno") }
    }

    func testFinderTagsArePreserved() throws {
        var url = try makeFile("a.md", "uno")
        var values = URLResourceValues()
        values.tagNames = ["Littera"]
        try url.setResourceValues(values)
        try LitteraDocumentFile.write("dos", to: url)
        url.removeAllCachedResourceValues()
        let tags = try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        XCTAssertEqual(tags, ["Littera"])
    }

    func testCreationDateIsPreserved() throws {
        let url = try makeFile("a.md", "uno")
        let created = Date(timeIntervalSince1970: 1_000_000_000)
        try fileManager.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        try LitteraDocumentFile.write("dos", to: url)
        let after = try fileManager.attributesOfItem(atPath: url.path)[.creationDate] as? Date
        XCTAssertEqual(after, created)
    }

    func testHardLinksRemainSeparatedToKeepAtomicReplacement() throws {
        let first = try makeFile("h1.md", "uno")
        let second = directory.appendingPathComponent("h2.md")
        try fileManager.linkItem(at: first, to: second)
        try LitteraDocumentFile.write("dos", to: first)
        XCTAssertEqual(try read(first), "dos")
        XCTAssertEqual(try read(second), "uno", "El otro enlace conserva el inode anterior")
    }
}
