import XCTest
@testable import Littera

/// Registro de comandos y búsqueda de la paleta del rediseño (D72).
@MainActor
final class LitteraPaletteTests: XCTestCase {
    private let es = Locale(identifier: "es")
    private let en = Locale(identifier: "en")

    func testRegistryIDsAreUniqueAndLocalized() {
        let all = LitteraCommandRegistry.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "Ids repetidos")
        for command in all {
            for locale in [es, en] {
                XCTAssertNotEqual(L10n.tr(command.title, locale: locale), command.title, "\(command.id) sin título en \(locale.identifier)")
                XCTAssertNotEqual(L10n.tr(command.group, locale: locale), command.group, "\(command.id) sin grupo en \(locale.identifier)")
            }
            XCTAssertNotNil(LitteraCommandRegistry.command(command.id))
        }
    }

    func testEditingCommandsRequireEditor() {
        let preview = LitteraCommandRegistry.commands(canEdit: false)
        XCTAssertFalse(preview.first { $0.id == "format.bold" }?.enabled ?? true)
        XCTAssertTrue(preview.first { $0.id == "new" }?.enabled ?? false)
        XCTAssertTrue(LitteraCommandRegistry.command("format.bold")?.showsEditor ?? false)
    }

    func testModeCommandPostsSetMode() {
        let expectation = expectation(forNotification: .litteraSetMode, object: nil) { note in
            (note.object as? String) == LitteraEditorMode.split.rawValue
        }
        LitteraCommandRegistry.command("split")?.perform()
        wait(for: [expectation], timeout: 1)
    }

    /// Zen y atrás/adelante se retiraron con la biblioteca (D76).
    func testRetiredCommandsAreGone() {
        for id in ["zen", "nav.back", "nav.forward"] {
            XCTAssertNil(LitteraCommandRegistry.command(id), id)
            XCTAssertNil(LitteraShortcuts.definition(id), id)
        }
    }


    // MARK: Búsqueda (D80: dos alcances, sin pestañas ni etiquetas)

    private func doc(_ id: String, _ title: String, open: Bool = false, active: Bool = false, age: TimeInterval = 0) -> LitteraUIPaletteEntry {
        LitteraUIPaletteEntry(id: id, kind: .document, title: title, detail: "\(id).md", symbol: "doc.text",
                              date: Date(timeIntervalSince1970: 1_000_000 - age), isOpen: open, isActive: active)
    }

    private func cmd(_ id: String, _ title: String, _ group: String) -> LitteraUIPaletteEntry {
        LitteraUIPaletteEntry(id: id, kind: .command, title: title, symbol: "circle", group: group)
    }

    private lazy var docs = [
        doc("a", "Plan de viaje", age: 50),
        doc("b", "Guía de Metal", open: true, age: 100),
        doc("c", "Notas de metal", active: true, age: 200),
        doc("d", "Recetas", age: 10)
    ]
    private lazy var cmds = [
        cmd("new", "Nuevo documento", "Documentos"),
        cmd("export.pdf", "Exportar como PDF", "Exportación"),
        cmd("split", "Cambiar a Dividido", "Vistas")
    ]

    func testEmptyQueryShowsRecentThenCommands() {
        let s = LitteraUIPaletteSearch.sections(scope: .all, query: "", documents: docs, commands: cmds)
        XCTAssertEqual(s.first?.header, .recent)
        XCTAssertEqual(s.first?.entries.map(\.id), ["c", "b", "d", "a"], "Activo, abiertos, recientes")
        XCTAssertEqual(s.dropFirst().map(\.header), [.group("Documentos"), .group("Exportación"), .group("Vistas")])
    }

    func testQueryRanksTitlePrefixFirstAndIgnoresAccents() {
        let s = LitteraUIPaletteSearch.sections(scope: .documents, query: "guia", documents: docs, commands: cmds)
        XCTAssertEqual(s.first?.entries.map(\.id), ["b"])
        let metal = LitteraUIPaletteSearch.sections(scope: .documents, query: "metal", documents: docs, commands: cmds)
        XCTAssertEqual(metal.first?.entries.map(\.id), ["b", "c"], "Mismo rango: orden original")
    }

    func testDocumentsScopeNeverShowsCommandsAndEmptyResult() {
        let s = LitteraUIPaletteSearch.sections(scope: .documents, query: "", documents: docs, commands: cmds)
        XCTAssertEqual(s.map(\.header), [.documents(4)])
        let pdf = LitteraUIPaletteSearch.sections(scope: .all, query: "pdf", documents: docs, commands: cmds)
        XCTAssertEqual(pdf.map(\.header), [.group("Exportación")])
        XCTAssertTrue(LitteraUIPaletteSearch.sections(scope: .all, query: "zzz", documents: docs, commands: cmds).isEmpty)
    }

    func testOpenDocumentsComeFirstAndRecentsAreNotDuplicated() {
        let open = LitteraDocumentSession.file(
            at: URL(fileURLWithPath: "/tmp/abierto.md"),
            contents: .init(markdown: "", modificationDate: nil)
        )
        let recents = [
            LitteraRecentDocument(path: "/tmp/abierto.md", bookmark: Data([1])),
            LitteraRecentDocument(path: "/tmp/cerrado.md", bookmark: Data([2]))
        ]
        let entries = LitteraCommandHostPalette.documentEntries(documents: [open], activeID: open.id, recents: recents)
        XCTAssertEqual(entries.map(\.title), ["abierto.md", "cerrado.md"])
        XCTAssertTrue(entries[0].isActive)
        XCTAssertFalse(entries[1].isOpen)
        XCTAssertEqual(LitteraCommandHostPalette.recentPath(fromID: entries[1].id), "/tmp/cerrado.md")
        XCTAssertNil(LitteraCommandHostPalette.recentPath(fromID: open.id))
    }
}
