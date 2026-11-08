import XCTest
@testable import Littera

final class LitteraDocumentPropertiesTests: XCTestCase {
    private let sample = """
    ---
    title: "Mejoras: Littera"
    status: in-progress
    tags: [littera, markdown, "a, b"]
    created: 2026-10-23
    toc: true
    author: Jorge
    aliases:
      - uno
      - dos
    ---

    # Texto
    """

    func testReadsKnownAndExtraProperties() {
        let properties = LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: sample))
        XCTAssertEqual(properties.title, "Mejoras: Littera")
        XCTAssertEqual(properties.knownStatus, .inProgress)
        XCTAssertEqual(properties.tags, ["littera", "markdown", "a, b"])
        XCTAssertEqual(properties.created, "2026-10-23")
        XCTAssertNotNil(properties.createdDate)
        XCTAssertTrue(properties.toc)
        XCTAssertEqual(properties.extras.map(\.key), ["author", "aliases"])
        XCTAssertEqual(properties.extras[0].kind, .scalar(text: "Jorge", quoted: false))
        XCTAssertEqual(properties.extras[1].kind, .list(items: ["uno", "dos"], block: true))
    }

    func testEveryExtraKeyIsEditableKeepingItsStyle() throws {
        let yaml = """
        author: "Jorge Raúl"
        revision: 1
        translation_of: null
        contributors: []
        keywords:
          - Swift
          - macOS
        custom:
          platform: "macOS"
          frameworks:
            - SwiftUI
        notes: |
          línea uno
          línea dos
        """
        let extras = LitteraDocumentProperties(yaml: yaml).extras
        XCTAssertEqual(extras.map(\.key), ["author", "revision", "translation_of", "contributors", "keywords", "custom", "notes"])
        XCTAssertEqual(extras[0].kind, .scalar(text: "Jorge Raúl", quoted: true), "Se muestra sin comillas")
        XCTAssertEqual(extras[0].yamlValue(scalar: "Ana"), "\"Ana\"", "Conserva las comillas")
        XCTAssertEqual(extras[1].yamlValue(scalar: "2"), "2", "Un número sigue siendo número")
        XCTAssertEqual(extras[1].yamlValue(scalar: "a: b"), "\"a: b\"", "Sin romper el YAML")
        XCTAssertEqual(extras[2].kind, .scalar(text: "null", quoted: false))
        XCTAssertEqual(extras[3].kind, .list(items: [], block: false))
        XCTAssertEqual(extras[3].yamlValue(list: ["Ana"]), "[Ana]")
        XCTAssertEqual(extras[4].kind, .list(items: ["Swift", "macOS"], block: true))
        guard case let .block(text, header, indent) = extras[5].kind else { return XCTFail("custom es un objeto") }
        XCTAssertEqual(text, "platform: \"macOS\"\nframeworks:\n  - SwiftUI")
        XCTAssertEqual(header, "")
        XCTAssertEqual(indent, "  ")
        guard case let .block(notes, notesHeader, _) = extras[6].kind else { return XCTFail("notes es un texto") }
        XCTAssertEqual(notes, "línea uno\nlínea dos")
        XCTAssertEqual(notesHeader, "|")

        // Escribir cada tipo y volver a leerlo.
        var updated = LitteraDocumentProperties.yaml(yaml, setting: "keywords", to: extras[4].yamlValue(list: ["Swift", "macOS", "AppKit"]))
        updated = LitteraDocumentProperties.yaml(updated, setting: "custom", to: extras[5].yamlValue(block: "platform: \"iOS\"\nframeworks:\n  - UIKit"))
        updated = LitteraDocumentProperties.yaml(updated, setting: "notes", to: extras[6].yamlValue(block: "otra"))
        XCTAssertTrue(updated.contains("keywords:\n  - Swift\n  - macOS\n  - AppKit\ncustom:\n  platform: \"iOS\"\n  frameworks:\n    - UIKit\nnotes: |\n  otra"))
        let reread = LitteraDocumentProperties(yaml: updated).extras
        XCTAssertEqual(reread.first { $0.key == "keywords" }?.kind, .list(items: ["Swift", "macOS", "AppKit"], block: true))
        XCTAssertEqual(reread.first { $0.key == "author" }?.kind, extras[0].kind, "El resto no cambia")
    }

    func testBlockStyleTagsStayBlock() {
        let properties = LitteraDocumentProperties(yaml: "tags:\n  - a\n  - b")
        XCTAssertTrue(properties.tagsUseBlockStyle)
        XCTAssertEqual(properties.tagsYAMLValue(["a", "b", "c"]), "\n  - a\n  - b\n  - c")
        XCTAssertEqual(LitteraDocumentProperties.yaml("tags:\n  - a\n  - b\nx: 1", setting: "tags", to: properties.tagsYAMLValue(["a"])), "tags:\n  - a\nx: 1")
    }

    func testReadsBlockListTagsAndVariants() {
        let properties = LitteraDocumentProperties(yaml: "tags:\n  - uno\n  - 'dos'\nstatus: In Progress\ntoc: yes")
        XCTAssertEqual(properties.tags, ["uno", "dos"])
        XCTAssertEqual(properties.knownStatus, .inProgress)
        XCTAssertTrue(properties.toc)
    }

    func testSettingAKeyKeepsTheRestUntouched() {
        let yaml = "title: A\n# comentario\ntags:\n  - x\n  - y\nauthor: J"
        let updated = LitteraDocumentProperties.yaml(yaml, setting: "tags", to: "[x, y, z]")
        XCTAssertEqual(updated, "title: A\n# comentario\ntags: [x, y, z]\nauthor: J")
        XCTAssertEqual(LitteraDocumentProperties.yaml(updated, setting: "status", to: "done"), updated + "\nstatus: done")
        XCTAssertEqual(LitteraDocumentProperties.yaml(updated, setting: "title", to: nil), "# comentario\ntags: [x, y, z]\nauthor: J")
    }

    private func apply(_ edit: LitteraTextEdit, to source: String) -> String {
        (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    private func frontmatterYAML(_ text: String) -> String {
        LitteraFrontmatter.detect(in: text)?.yaml ?? ""
    }

    func testEditShiftsSelectionAfterFrontmatter() throws {
        let source = "---\ntitle: A\n---\n\nHola"
        let caret = (source as NSString).length
        let edit = try XCTUnwrap(LitteraDocumentProperties.edit(
            setting: "title", to: "Más largo", in: source, selection: NSRange(location: caret, length: 0)
        ))
        let result = apply(edit, to: source)
        XCTAssertTrue(result.hasSuffix("\n---\n\nHola"), "El cuerpo no cambia")
        XCTAssertEqual(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: result)).title, "Más largo")
        XCTAssertEqual(frontmatterYAML(result), "title: Más largo", "Solo cambia la línea editada, sin completar el frontmatter")
        XCTAssertEqual(edit.selection.location, (result as NSString).length, "El cursor sigue al final")
    }

    func testEditFillsEmptyFrontmatterAndCreatesMissingOne() throws {
        let empty = "---\n\n---\n\nTexto"
        let first = try XCTUnwrap(LitteraDocumentProperties.edit(setting: "toc", to: "true", in: empty, selection: NSRange()))
        let filled = apply(first, to: empty)
        XCTAssertTrue(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: filled)).toc)
        XCTAssertTrue(filled.hasSuffix("toc: true\n\n---\n\nTexto") || filled.hasSuffix("toc: true\n---\n\nTexto"))

        let none = "Texto"
        let second = try XCTUnwrap(LitteraDocumentProperties.edit(setting: "title", to: "T", in: none, selection: NSRange(location: 5, length: 0)))
        let created = apply(second, to: none)
        XCTAssertEqual(created, "---\ntitle: T\n---\n\nTexto", "Solo la clave añadida: ninguna otra inventada")
        XCTAssertEqual(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: created)).title, "T")
        XCTAssertEqual(second.selection.location, (created as NSString).length)

        // La plantilla de documento nuevo: solo cambia la línea editada.
        let normalized = LitteraDocumentProperties.newDocumentTemplate()
        let third = try XCTUnwrap(LitteraDocumentProperties.edit(setting: "status", to: "done", in: normalized, selection: NSRange()))
        XCTAssertEqual(third.replacement, "status: done\n")
        XCTAssertEqual((normalized as NSString).substring(with: third.range), "status: draft\n")
    }

    // MARK: - Normalización (solo genera y reconoce la plantilla de documento nuevo)

    /// Frontmatter mínimo creado desde el panel en 1.2.x (captura 5).
    private let minimal = "status: review\ntitle: LITTERA_FASE_2_RESULTADOS\ncreated: 2026-10-24"

    func testNormalizationAddsEveryPropertyInSchemaOrder() {
        let yaml = LitteraDocumentProperties.normalizedYAML(minimal)
        let keys = LitteraDocumentProperties.topLevelEntries(in: yaml).map(\.key)
        XCTAssertEqual(keys, [
            "title", "subtitle", "description", "slug", "aliases",
            "author", "contributors", "copyright", "license",
            "date", "created", "modified",
            "tags", "categories", "keywords",
            "lang", "translation_of",
            "status", "version", "revision", "priority", "progress",
            "project", "type", "folder", "collection", "series", "order",
            "parent", "related",
            "custom", "toc",
        ])
        XCTAssertTrue(yaml.hasPrefix("# IDENTIFICACIÓN\ntitle: LITTERA_FASE_2_RESULTADOS\nsubtitle: \"\"\n"))
        XCTAssertTrue(yaml.contains("\n\n# AUTORÍA\nauthor: \"\"\ncontributors: []\n"))
        XCTAssertTrue(yaml.contains("\n# FECHAS\ndate: null\ncreated: 2026-10-24\nmodified: null\n"))
        XCTAssertTrue(yaml.contains("\n# ESTADO DEL DOCUMENTO\nstatus: review\n"))
        XCTAssertTrue(yaml.hasSuffix("# CAMPOS PERSONALIZADOS\ncustom: {}\ntoc: false"))
        // Las mismas propiedades que el documento completo de ejemplo.
        XCTAssertEqual(
            LitteraDocumentProperties(yaml: yaml).panelExtras.count,
            LitteraDocumentProperties(yaml: LitteraDocumentProperties.normalizedYAML(sample)).panelExtras.count
        )
    }

    func testNormalizationKeepsValuesStylesUnknownKeysAndComments() {
        let yaml = """
        # AUTORÍA
        author: "Jorge Raúl"
        tags:
          - uno
          - dos
        # nota sobre el título
        title: 'Hola'
        mi_campo: 42
        custom:
          platform: "macOS"
        toc: true
        # comentario suelto
        """
        let normalized = LitteraDocumentProperties.normalizedYAML(yaml)
        XCTAssertTrue(normalized.contains("# nota sobre el título\ntitle: 'Hola'\n"), "El comentario viaja con su clave")
        XCTAssertTrue(normalized.contains("author: \"Jorge Raúl\"\n"))
        XCTAssertTrue(normalized.contains("tags:\n  - uno\n  - dos\n"))
        XCTAssertTrue(normalized.contains("custom:\n  platform: \"macOS\"\nmi_campo: 42\n# comentario suelto\ntoc: true"))
        XCTAssertEqual(normalized.components(separatedBy: "# AUTORÍA").count, 2, "Sin títulos duplicados")
        XCTAssertEqual(LitteraDocumentProperties.normalizedYAML(normalized), normalized, "Idempotente")
        XCTAssertTrue(LitteraDocumentProperties.isNormalized(normalized))
    }

    func testFullExampleIsAlreadyNormalized() {
        // El orden de las capturas 1–4.
        let yaml = LitteraDocumentProperties.normalizedYAML(sample.components(separatedBy: "\n").dropFirst().prefix { $0 != "---" }.joined(separator: "\n"))
        XCTAssertEqual(LitteraDocumentProperties.normalizedYAML(yaml), yaml)
        let properties = LitteraDocumentProperties(yaml: yaml)
        XCTAssertEqual(properties.title, "Mejoras: Littera")
        XCTAssertEqual(properties.tags, ["littera", "markdown", "a, b"])
        XCTAssertEqual(properties.extras.first { $0.key == "aliases" }?.kind, .list(items: ["uno", "dos"], block: true))
    }

    func testSectionTitlesFollowTheDocumentOrTheInterface() {
        XCTAssertTrue(LitteraDocumentProperties.normalizedYAML(minimal, language: "en").hasPrefix("# IDENTIFICATION\n"))
        let english = LitteraDocumentProperties.normalizedYAML(minimal, language: "en")
        XCTAssertEqual(LitteraDocumentProperties.normalizedYAML(english, language: "es"), english, "Conserva el idioma del documento")
    }

    /// El panel ofrece siempre las propiedades gestionadas (vacías si faltan,
    /// sin escribir nada) y, del resto, solo las que tiene el documento.
    func testPanelShowsManagedPropertiesAndOnlyThePresentOthers() {
        let partial = LitteraDocumentProperties(yaml: minimal + "\nmi_campo: 42")
        XCTAssertEqual(partial.panelExtras.map(\.key), ["description", "author", "version", "project", "requirements", "mi_campo"])
        XCTAssertTrue(partial.managedExtra("author").isMissing)
        XCTAssertEqual(partial.managedExtra("requirements").yamlValue(list: ["Ana"]), "\n  - Ana", "Lista nueva en bloque")
        XCTAssertEqual(partial.managedExtra("version").yamlValue(scalar: "2.10"), "\"2.10\"", "Una versión nueva sigue siendo texto")
        XCTAssertEqual(partial.managedExtra("author").yamlValue(scalar: "Ana"), "Ana")
    }

    /// Quitar una clave (p. ej. «Sin estado») quita solo sus líneas.
    func testRemovingAKeyRemovesOnlyItsLines() throws {
        let source = LitteraDocumentProperties.newDocumentTemplate()
        let edit = try XCTUnwrap(LitteraDocumentProperties.edit(setting: "status", to: nil, in: source, selection: NSRange()))
        let result = apply(edit, to: source)
        XCTAssertEqual(result, source.replacingOccurrences(of: "status: draft\n", with: ""))
        XCTAssertNil(LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: result)).status)
    }

    func testScalarsAreQuotedOnlyWhenNeeded() {
        XCTAssertEqual(LitteraDocumentProperties.scalar("Mejoras de Littera"), "Mejoras de Littera")
        XCTAssertEqual(LitteraDocumentProperties.scalar(""), "\"\"")
        XCTAssertEqual(LitteraDocumentProperties.scalar("Uno: dos"), "\"Uno: dos\"")
        XCTAssertEqual(LitteraDocumentProperties.scalar("true"), "\"true\"")
        XCTAssertEqual(LitteraDocumentProperties.scalar("2026"), "\"2026\"")
        XCTAssertEqual(LitteraDocumentProperties.scalar("Dice \"hola\""), "Dice \"hola\"")
        XCTAssertEqual(LitteraDocumentProperties.scalar("\"cita\""), "\"\\\"cita\\\"\"")
        XCTAssertEqual(LitteraDocumentProperties.unquote("\"\\\"cita\\\"\""), "\"cita\"")
        XCTAssertEqual(LitteraDocumentProperties.flowList(["a", "b, c"]), "[a, \"b, c\"]")
        XCTAssertEqual(LitteraDocumentProperties.flowList([]), "[]")
    }

    func testNewDocumentTemplate() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_792_800_000) // 2026-10-24 UTC
        let template = LitteraDocumentProperties.newDocumentTemplate(date: date, timeZone: utc)
        XCTAssertTrue(template.hasPrefix("---\n# IDENTIFICACIÓN\ntitle: \"\"\n"))
        XCTAssertTrue(template.contains("\n# FECHAS\ndate: 2026-10-24\ncreated: 2026-10-24\nmodified: 2026-10-24\n"))
        XCTAssertTrue(template.contains("\nstatus: draft\n"))
        XCTAssertTrue(template.hasSuffix("custom: {}\ntoc: false\n---\n\n"))
        XCTAssertTrue(LitteraDocumentProperties.isNormalized(LitteraFrontmatter.detect(in: template)?.yaml ?? ""))
        let properties = LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: template))
        XCTAssertEqual(properties.title, "")
        XCTAssertEqual(properties.knownStatus, .draft)
        XCTAssertEqual(properties.tags, [])
        XCTAssertFalse(properties.toc)
        // Plantilla vigente sin cambios: no incluye `updated` ni `requirements`.
        XCTAssertFalse(template.contains("updated:") || template.contains("requirements:"))
        XCTAssertNil(properties.updated)
        XCTAssertTrue(properties.managedExtra("requirements").isMissing)
        XCTAssertTrue(LitteraDocumentProperties.isNewDocumentTemplate(template))
        XCTAssertTrue(LitteraDocumentProperties.isNewDocumentTemplate(
            LitteraDocumentProperties.newDocumentTemplate(date: date, timeZone: utc, language: "en")
        ))
        XCTAssertTrue(LitteraDocumentProperties.isNewDocumentTemplate("---\n\n---\n\n"), "Plantilla de 1.1.0")
        XCTAssertTrue(LitteraDocumentProperties.isNewDocumentTemplate(
            "---\ntitle: \"\"\nstatus: draft\ntags: []\ncreated: 2026-10-24\ntoc: false\n---\n\n"
        ), "Plantilla de 1.2.x")
        XCTAssertFalse(LitteraDocumentProperties.isNewDocumentTemplate(template + "x"))
        let derived = LitteraMarkdownDerivedDocument(source: template, revision: 1)
        XCTAssertEqual(derived.wordCount, 0)
        XCTAssertTrue(derived.rendered.blocks.isEmpty)
    }

    func testTableOfContentsBlockInPreview() {
        let source = "---\ntoc: true\n---\n\n# Uno\n\nTexto\n\n## Dos\n\n#### Cuatro\n\n> # En cita\n"
        let blocks = LitteraMarkdownDerivedDocument(source: source, revision: 1).rendered.blocks
        guard case let .tableOfContents(entries) = blocks.first?.kind else {
            return XCTFail("El índice va primero")
        }
        XCTAssertEqual(entries.map(\.title), ["Uno", "Dos"], "H1–H3 del nivel superior")
        XCTAssertEqual(entries.map(\.level), [1, 2])
        XCTAssertEqual(entries.first?.blockID, blocks[1].id)

        let without = LitteraMarkdownDerivedDocument(source: "---\ntoc: false\n---\n\n# Uno\n", revision: 1).rendered.blocks
        XCTAssertFalse(without.contains { if case .tableOfContents = $0.kind { true } else { false } })
    }

    func testTableOfContentsInHTML() {
        let html = LitteraExporter.html(
            for: "---\ntoc: true\n---\n\n# Introducción\n\n## Uso <b>\n\n# Introducción\n",
            title: "t",
            tableOfContentsTitle: "Índice"
        )
        XCTAssertTrue(html.contains("<nav class=\"toc\">"))
        XCTAssertTrue(html.contains("<a href=\"#introducción\">Introducción</a>"))
        XCTAssertTrue(html.contains("<a href=\"#introducción-2\">"), "Identificadores únicos")
        XCTAssertTrue(html.contains("<h1 id=\"introducción\">"))
        XCTAssertTrue(html.contains("<h2 id=\"uso-b\">"))
        XCTAssertTrue(html.contains("Uso &lt;b&gt;"), "Texto escapado")
        XCTAssertFalse(LitteraExporter.html(for: "# Uno\n", title: "t").contains("<nav class=\"toc\">"))
    }

    @MainActor
    func testKnownKeysHaveLocalizedLabels() {
        let spanish = Locale(identifier: "es_ES")
        XCTAssertEqual(LitteraPropertyLabels.label(for: "subtitle", locale: spanish), "Subtítulo")
        XCTAssertEqual(LitteraPropertyLabels.label(for: "Author", locale: spanish), "Autor")
        XCTAssertEqual(LitteraPropertyLabels.label(for: "translation-of", locale: spanish), "Traducción de")
        XCTAssertEqual(LitteraPropertyLabels.label(for: "keywords", locale: Locale(identifier: "en")), "Keywords")
        XCTAssertEqual(LitteraPropertyLabels.label(for: "mi_campo", locale: spanish), "Mi campo", "Clave desconocida legible")
        for (yamlKey, key) in LitteraPropertyLabels.localizationKeys {
            XCTAssertNotEqual(L10n.tr(key, locale: spanish), key, "Falta la traducción de \(yamlKey)")
            XCTAssertNotEqual(L10n.tr(key, locale: Locale(identifier: "en")), key, "Missing translation for \(yamlKey)")
        }
    }
}
