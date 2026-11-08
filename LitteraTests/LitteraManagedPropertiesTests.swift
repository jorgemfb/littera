import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Propiedades gestionadas del frontmatter (2026-11-07): title, description,
/// tags, author, created, updated, version, status, project y requirements.
/// Los valores son de prueba; nunca se usan documentos del usuario.
final class LitteraManagedPropertiesTests: XCTestCase {
    /// Estructura del ejemplo de la petición, con valores de prueba.
    private let full = """
    ---
    title: Guía de prueba
    description: Descripción de prueba
    tags: [uno, dos]
    author: Autor de prueba
    created: 2026-01-02
    updated: 2026-01-03
    version: "2.1"
    status: draft
    project: PROYECTO
    requirements:
      - Requisito A
      - Requisito B
    ---

    Cuerpo
    """

    private func apply(_ edit: LitteraTextEdit, to source: String) -> String {
        (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    private func set(_ key: String, _ value: String?, in source: String) throws -> String {
        apply(try XCTUnwrap(LitteraDocumentProperties.edit(setting: key, to: value, in: source, selection: NSRange())), to: source)
    }

    private func properties(_ source: String) -> LitteraDocumentProperties {
        LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: source))
    }

    func testReadsEveryManagedKeyOfTheExample() {
        let p = properties(full)
        XCTAssertEqual(p.title, "Guía de prueba")
        XCTAssertEqual(p.managedExtra("description").kind, .scalar(text: "Descripción de prueba", quoted: false))
        XCTAssertEqual(p.tags, ["uno", "dos"])
        XCTAssertEqual(p.managedExtra("author").kind, .scalar(text: "Autor de prueba", quoted: false))
        XCTAssertEqual(p.created, "2026-01-02")
        XCTAssertEqual(p.updated, "2026-01-03")
        XCTAssertNotNil(p.updatedDate)
        XCTAssertEqual(p.managedExtra("version").kind, .scalar(text: "2.1", quoted: true))
        XCTAssertEqual(p.knownStatus, .draft)
        XCTAssertEqual(p.managedExtra("project").kind, .scalar(text: "PROYECTO", quoted: false))
        XCTAssertEqual(p.managedExtra("requirements").kind, .list(items: ["Requisito A", "Requisito B"], block: true))
        XCTAssertTrue(LitteraDocumentProperties.managedExtraKeys.allSatisfy { !p.managedExtra($0).isMissing })
        XCTAssertNil(LitteraDocumentProperties.editingLimitation(in: full))
    }

    /// Editar una clave cambia solo su línea; `created` y `updated` no se tocan.
    func testEditingOneKeyChangesOnlyItsLine() throws {
        let result = try set("title", "Otra guía", in: full)
        XCTAssertEqual(result, full.replacingOccurrences(of: "title: Guía de prueba", with: "title: Otra guía"))
        XCTAssertTrue(result.contains("created: 2026-01-02\nupdated: 2026-01-03\n"), "Las fechas no cambian solas")
    }

    func testVersionKeepsItsTextAndQuotes() throws {
        let quoted = "---\nversion: \"2.10\"\n---\n"
        let p = properties(quoted)
        XCTAssertEqual(p.managedExtra("version").kind, .scalar(text: "2.10", quoted: true))
        let edited = try set("version", p.managedExtra("version").yamlValue(scalar: "2.11"), in: quoted)
        XCTAssertEqual(edited, "---\nversion: \"2.11\"\n---\n")

        // Sin comillas en el documento: se lee como texto, nunca como 2.1.
        XCTAssertEqual(properties("---\nversion: 2.10\n---\n").managedExtra("version").kind, .scalar(text: "2.10", quoted: false))

        // Añadida desde el panel: comillas para que siga siendo texto.
        let added = try set("version", properties("---\ntitle: T\n---\n").managedExtra("version").yamlValue(scalar: "2.10"), in: "---\ntitle: T\n---\n")
        XCTAssertEqual(added, "---\ntitle: T\nversion: \"2.10\"\n---\n")
    }

    func testListsKeepBlockOrInlineStyle() throws {
        // requirements en línea sigue en línea; tags en bloque sigue en bloque.
        let source = "---\ntags:\n  - a\n  - b\nrequirements: [x, \"y, z\"]\n---\n"
        let p = properties(source)
        XCTAssertEqual(p.tags, ["a", "b"])
        XCTAssertEqual(p.managedExtra("requirements").kind, .list(items: ["x", "y, z"], block: false))

        var result = try set("tags", p.tagsYAMLValue(["a", "b", "c"]), in: source)
        result = try set("requirements", p.managedExtra("requirements").yamlValue(list: ["x", "y, z", "w"]), in: result)
        XCTAssertEqual(result, "---\ntags:\n  - a\n  - b\n  - c\nrequirements: [x, \"y, z\", w]\n---\n")

        // Bloque en requirements y en línea en tags, al revés.
        let other = "---\ntags: [a]\nrequirements:\n  - R1\n---\n"
        let q = properties(other)
        let edited = try set("requirements", q.managedExtra("requirements").yamlValue(list: ["R1", "R2"]), in: other)
        XCTAssertEqual(edited, "---\ntags: [a]\nrequirements:\n  - R1\n  - R2\n---\n")
    }

    func testUnknownKeysCommentsOrderAndQuotesSurvive() throws {
        let source = """
        ---
        # Comentario de cabecera
        zeta: 'primera'
        title: "Título"   # comentario en línea
        extra:
          anidado: true
          lista:
            - 1
        status: mi-estado-propio
        notas: |
          línea uno
          línea dos
        ---
        Texto
        """
        let p = properties(source)
        XCTAssertEqual(p.status, "mi-estado-propio", "Un estado propio se respeta")
        XCTAssertNil(p.knownStatus)
        XCTAssertEqual(p.otherExtras.map(\.key), ["zeta", "extra", "notas"])

        let result = try set("author", properties(source).managedExtra("author").yamlValue(scalar: "Ana"), in: source)
        // La gestionada nueva entra tras la que la precede en el orden del panel
        // (title); las otras claves y los comentarios no se mueven.
        let expected = source.replacingOccurrences(of: "# comentario en línea\n", with: "# comentario en línea\nauthor: Ana\n")
        XCTAssertEqual(result, expected)
        XCTAssertNil(LitteraDocumentProperties.editingLimitation(in: source), "YAML seguro aunque tenga anidados y textos de bloque")
    }

    /// Orden de la captura del propietario: al editar, las gestionadas pasan
    /// al orden del panel aunque se añadieran en otro; `toc` y las claves
    /// desconocidas se quedan donde estaban.
    func testManagedKeysFollowThePanelOrderWhenEditing() throws {
        let source = "---\nupdated: 2026-01-03\ntitle: T\nauthor: A\ncreated: 2026-01-02\nstatus: done\nversion: \"2.1\"\ntoc: true\nmi_clave: x\n---\n\nCuerpo"
        XCTAssertEqual(LitteraDocumentProperties.editingLimitation(in: source), nil)
        let result = try set("project", "Proyecto", in: source)
        XCTAssertEqual(result, "---\ntitle: T\nauthor: A\ncreated: 2026-01-02\nupdated: 2026-01-03\nversion: \"2.1\"\nstatus: done\nproject: Proyecto\ntoc: true\nmi_clave: x\n---\n\nCuerpo")
        // Ya ordenado: editar otra vez solo cambia su línea.
        XCTAssertEqual(try set("status", "review", in: result), result.replacingOccurrences(of: "status: done", with: "status: review"))
        // Un comentario pegado a una clave viaja con ella.
        let commented = "---\n# cuándo se revisó\nupdated: 2026-01-03\ntitle: T\n---\n"
        XCTAssertEqual(try set("title", "U", in: commented), "---\ntitle: U\n# cuándo se revisó\nupdated: 2026-01-03\n---\n")
        // Abrir no reordena nada: solo una edición.
        XCTAssertEqual(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: source)).title, "T")
    }

    /// Documento creado con la plantilla (secciones `# FECHAS`…): conserva el
    /// orden de sus secciones; una propiedad nueva entra junto a la anterior.
    func testTemplateSectionsKeepTheirOrder() throws {
        let template = LitteraDocumentProperties.newDocumentTemplate()
        let withUpdated = try set("updated", "2026-01-03", in: template)
        let created = try XCTUnwrap(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: template)).created)
        XCTAssertEqual(withUpdated, template.replacingOccurrences(of: "created: \(created)\n", with: "created: \(created)\nupdated: 2026-01-03\n"))
        let withRequirements = try set("requirements", "\n  - R1", in: withUpdated)
        XCTAssertTrue(withRequirements.contains("project: \"\"\nrequirements:\n  - R1\n"), withRequirements)
        XCTAssertEqual(try set("status", "done", in: template), template.replacingOccurrences(of: "status: draft", with: "status: done"))
    }

    func testUnicodeValuesRoundTrip() throws {
        let source = "---\ntitle: Ñandú 🦤\n---\n"
        XCTAssertEqual(properties(source).title, "Ñandú 🦤")
        var result = try set("title", LitteraDocumentProperties.scalar("Guía: café ☕️ «α»"), in: source)
        result = try set("tags", LitteraDocumentProperties.flowList(["médico", "日本語"]), in: result)
        let p = properties(result)
        XCTAssertEqual(p.title, "Guía: café ☕️ «α»")
        XCTAssertEqual(p.tags, ["médico", "日本語"])
    }

    func testEmptyAndMissingPropertiesInventNothing() throws {
        let source = "---\nauthor:\ntags: []\ncreated:\n---\n"
        let p = properties(source)
        XCTAssertEqual(p.managedExtra("author").kind, .scalar(text: "", quoted: false))
        XCTAssertFalse(p.managedExtra("author").isMissing, "Vacía pero presente")
        XCTAssertTrue(p.managedExtra("project").isMissing)
        XCTAssertEqual(p.tags, [])
        XCTAssertNil(p.created)
        let edited = try set("author", p.managedExtra("author").yamlValue(scalar: "Ana"), in: source)
        XCTAssertEqual(edited, "---\ntags: []\nauthor: Ana\ncreated:\n---\n", "En el orden del panel: tags antes que author")
    }

    func testDocumentWithoutFrontmatterGetsOneOnlyWhenAPropertyIsSet() throws {
        let source = "# Hola\n\nTexto"
        XCTAssertNil(LitteraDocumentProperties.edit(setting: "title", to: nil, in: source, selection: NSRange()), "Quitar sin frontmatter no crea nada")
        XCTAssertEqual(try set("created", "2026-01-02", in: source), "---\ncreated: 2026-01-02\n---\n\n# Hola\n\nTexto")
        XCTAssertEqual(try set("title", "T", in: ""), "---\ntitle: T\n---\n")
    }

    func testUnsafeYAMLIsNeverRewritten() {
        let cases: [(String, LitteraDocumentProperties.EditingLimitation)] = [
            ("---\ntitle: A\n\nTexto sin cierre", .unclosedFrontmatter),
            ("---\ntitle: A\n\tsub: tab\n---\n", .unsupportedYAML(line: 2)),
            ("---\nbase: &b valor\nalias: *b\n---\n", .unsupportedYAML(line: 1)),
            ("---\ntitle: A\ntitle: B\n---\n", .unsupportedYAML(line: 2)),
            ("---\ntags: [a,\n  b]\n---\n", .unsupportedYAML(line: 1)),
            ("---\ntitle: \"sin cerrar\n  sigue\"\n---\n", .unsupportedYAML(line: 1)),
            ("---\n- uno\n- dos\n---\n", .unsupportedYAML(line: 1)),
            ("---\n{title: A}\n---\n", .unsupportedYAML(line: 1)),
            ("---\nmapa:\n  <<: *base\n---\n", .unsupportedYAML(line: 2)),
        ]
        for (source, limitation) in cases {
            XCTAssertEqual(LitteraDocumentProperties.editingLimitation(in: source), limitation, source)
            XCTAssertNil(LitteraDocumentProperties.edit(setting: "author", to: "Ana", in: source, selection: NSRange()), "No se toca: \(source)")
        }
        // Lo que sí es seguro.
        XCTAssertNil(LitteraDocumentProperties.editingLimitation(in: "---\ntitle: \"Uno: dos\" # nota\ntags: [a, b] # c\n---\n"))
        XCTAssertNil(LitteraDocumentProperties.editingLimitation(in: "Sin frontmatter"))
        XCTAssertNil(LitteraDocumentProperties.editingLimitation(in: "---\n\n---\n"))
    }

    func testStatusAcceptsKnownAndCustomValues() throws {
        let source = "---\nstatus: En Revisión Final\n---\n"
        XCTAssertEqual(properties(source).status, "En Revisión Final")
        XCTAssertEqual(try set("status", LitteraPropertyStatus.review.rawValue, in: source), "---\nstatus: review\n---\n")
    }
}

/// Edición desde el panel con el editor real: sin guardar, deshacer y
/// rehacer, Vista previa, guardar y volver a abrir (archivos temporales).
@MainActor
final class LitteraManagedPropertiesEditorTests: XCTestCase {
    private var window: NSWindow?
    private let delegate = LitteraApplicationDelegate()
    private var directory: URL?

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found = (view as? T).map { [$0] } ?? []
        for subview in view.subviews { found += views(type, in: subview) }
        return found
    }

    private func temporaryFile(_ text: String) throws -> URL {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("props-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        let url = directory.appendingPathComponent("prueba.md")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func host(_ store: LitteraDocumentStore) throws -> NSTextView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LitteraEditorView(documentStore: store, applicationDelegate: delegate, chromeless: true, startMode: .source))
        window.orderFront(nil)
        self.window = window
        spin(1)
        return try XCTUnwrap(views(LitteraEditorTextView.self, in: try XCTUnwrap(window.contentView)).first)
    }

    func testEditMarksDirtyUndoRedoSaveAndReopen() throws {
        let original = "---\ntitle: Inicial\n# nota\nmi_clave: 1\n---\n\nCuerpo ñ\n"
        let url = try temporaryFile(original)
        let locale = Locale(identifier: "es_ES")
        let store = LitteraDocumentStore.isolated()
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        let textView = try host(store)
        let target = LitteraEditingTarget()
        target.register(textView)

        let document = try XCTUnwrap(store.activeDocument)
        XCTAssertTrue(target.setDocumentProperty("version", to: "\"2.10\"", documentText: document.markdown))
        spin(0.2)
        let edited = "---\ntitle: Inicial\nversion: \"2.10\"\n# nota\nmi_clave: 1\n---\n\nCuerpo ñ\n"
        XCTAssertEqual(store.activeDocument?.markdown, edited)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false, "Marcado como modificado")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), original, "Nada se escribe sin Guardar")

        textView.undoManager?.undo()
        spin(0.2)
        XCTAssertEqual(store.activeDocument?.markdown, original, "Deshacer")
        textView.undoManager?.redo()
        spin(0.2)
        XCTAssertEqual(store.activeDocument?.markdown, edited, "Rehacer")

        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), edited, "Guardar escribe el Markdown real")

        let reopened = LitteraDocumentStore.isolated()
        XCTAssertTrue(reopened.openDocument(at: url, locale: locale))
        let p = LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: reopened.activeDocument?.markdown ?? ""))
        XCTAssertEqual(p.managedExtra("version").kind, .scalar(text: "2.10", quoted: true))
        XCTAssertEqual(p.otherExtras.map(\.key), ["mi_clave"])
    }

    /// En Vista previa el editor está oculto y sin registrar: el cambio pasa
    /// por él y se puede deshacer al volver a Fuente.
    func testEditInPreviewCanBeUndoneBackInSource() throws {
        let store = LitteraDocumentStore.isolated()
        store.updateMarkdown(for: store.activeDocumentID, text: "---\ntitle: A\n---\n\nTexto\n")
        let textView = try host(store)
        let target = LitteraEditingTarget()
        target.register(textView)
        NotificationCenter.default.post(name: .litteraSetMode, object: LitteraEditorMode.preview.rawValue)
        spin(0.5)
        target.unregister(textView) // Lo que hace el editor al pasar a Vista previa.

        let before = try XCTUnwrap(store.activeDocument?.markdown)
        XCTAssertTrue(target.setDocumentProperty("title", to: "B", documentText: before))
        spin(0.2)
        XCTAssertEqual(store.activeDocument?.markdown, "---\ntitle: B\n---\n\nTexto\n")

        NotificationCenter.default.post(name: .litteraSetMode, object: LitteraEditorMode.source.rawValue)
        spin(0.5)
        XCTAssertTrue(textView.undoManager?.canUndo ?? false, "Volver a Fuente conserva el paso de deshacer")
        textView.undoManager?.undo()
        spin(0.2)
        XCTAssertEqual(store.activeDocument?.markdown, before)
    }

    /// Si el editor no tiene el texto del documento, no se usa.
    func testEditorWithOtherTextIsNotUsed() throws {
        let store = LitteraDocumentStore.isolated()
        store.updateMarkdown(for: store.activeDocumentID, text: "---\ntitle: A\n---\n")
        let textView = try host(store)
        let target = LitteraEditingTarget()
        target.register(textView)
        XCTAssertFalse(target.setDocumentProperty("title", to: "B", documentText: "otro texto"))
        XCTAssertEqual(store.activeDocument?.markdown, "---\ntitle: A\n---\n")
    }
}
