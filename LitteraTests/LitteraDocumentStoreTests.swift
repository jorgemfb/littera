import Combine
import XCTest
@testable import Littera

@MainActor
final class LitteraDocumentStoreTests: XCTestCase {
    func testOnlyLatestDerivationIsPublishedAfterRapidEdits() {
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        let initialDeadline = Date().addingTimeInterval(15)
        while store.derivedDocuments[id] == nil && Date() < initialDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(store.derivedDocuments[id])
        // Sin agrupación, esta prueba reproduce la ventana que 0381e41 podía
        // publicar: el análisis ya iniciado termina después de una edición.
        store.derivationDebounce = 0
        store.maximumDerivationWait = 0
        let intermediate = String(repeating: "## Primera versión\n\nTexto de prueba.\n\n", count: 1000)
        let latest = "# Última versión\n\nContenido actualizado."
        var published: [String] = []
        let subscription = store.$derivedDocuments.dropFirst().sink { documents in
            if let source = documents[id]?.source { published.append(source) }
        }

        // Ambas ediciones ocurren en el mismo turno del hilo principal, antes
        // de que pueda publicarse la derivación lanzada por la primera.
        store.updateMarkdown(for: id, text: intermediate)
        store.updateMarkdown(for: id, text: latest)
        let deadline = Date().addingTimeInterval(15)
        while store.derivedDocuments[id]?.source != latest && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(store.derivedDocuments[id]?.source, latest)
        XCTAssertFalse(published.contains(intermediate))
        withExtendedLifetime(subscription) {}
    }

    func testStaleDerivationIsNeverPublishedAfterItsDebounceInterval() {
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        let initialDeadline = Date().addingTimeInterval(15)
        while store.derivedDocuments[id] == nil && Date() < initialDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(store.derivedDocuments[id])

        store.derivationDebounce = 0
        store.maximumDerivationWait = 0
        let intermediate = String(repeating: "## Versión intermedia\n\nTexto de prueba.\n\n", count: 10_000)
        let latest = "# Última versión\n\nContenido definitivo."
        var published: [String] = []
        let subscription = store.$derivedDocuments.dropFirst().sink { documents in
            if let source = documents[id]?.source { published.append(source) }
        }

        store.updateMarkdown(for: id, text: intermediate)
        // Cede el turno para que se inicie el análisis de la instantánea; la
        // segunda edición la convierte en obsoleta antes de que pueda acabar.
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        store.updateMarkdown(for: id, text: latest)

        let deadline = Date().addingTimeInterval(20)
        while store.derivedDocuments[id]?.source != latest && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(store.derivedDocuments[id]?.source, latest)
        XCTAssertFalse(published.contains(intermediate), "Nunca se publica una derivación obsoleta")
        withExtendedLifetime(subscription) {}
    }

    func testSwitchingDocumentsPreservesEachMarkdownValue() {
        let store = LitteraDocumentStore.isolated()
        let firstDocumentID = store.activeDocumentID
        let firstMarkdown = "# Documento uno\n\nContenido Unicode: ñ 😺"
        store.updateMarkdown(for: firstDocumentID, text: firstMarkdown)

        let second = LitteraDocumentSession.newMarkdownDocument(
            fileName: "Documento dos.md",
            folderDescription: "Sin guardar"
        )
        store.documents.append(second)
        store.updateMarkdown(for: second.id, text: "## Documento dos\n")

        store.activeDocumentID = second.id
        XCTAssertEqual(store.activeDocument?.markdown, "## Documento dos\n")

        store.activeDocumentID = firstDocumentID
        XCTAssertEqual(store.activeDocument?.markdown, firstMarkdown)
        XCTAssertEqual(store.documents.first(where: { $0.id == firstDocumentID })?.savedMarkdown, LitteraDocumentSession.newDocumentTemplate)
        XCTAssertTrue(store.documents.first(where: { $0.id == firstDocumentID })?.isDirty == true)
    }

    func testStartsWithASingleEmptyUntitledDocument() {
        let store = LitteraDocumentStore.isolated()
        XCTAssertEqual(store.documents.count, 1)
        let document = store.activeDocument
        XCTAssertEqual(document?.markdown, LitteraDocumentSession.newDocumentTemplate, "Plantilla de propiedades (D53)")
        XCTAssertTrue(document?.isPristineUntitled ?? false)
        XCTAssertNil(document?.fileURL)
        XCTAssertFalse(document?.isDirty ?? true)
        XCTAssertEqual(LitteraDocumentStatus(document), .unsaved)
        // La derivación se calcula fuera del hilo principal desde el arranque;
        // comprobarla de forma inmediata hacía esta aserción dependiente de la
        // planificación del sistema.
        let deadline = Date().addingTimeInterval(5)
        while store.derivedDocuments[store.activeDocumentID] == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(store.derivedDocuments[store.activeDocumentID], "El documento vacío también tiene análisis")
    }

    func testDocumentStatusReflectsSaveState() {
        var document = LitteraDocumentSession.untitled(locale: Locale(identifier: "es"))
        XCTAssertEqual(LitteraDocumentStatus(document), .unsaved)
        document.isDirty = true
        XCTAssertEqual(LitteraDocumentStatus(document), .modified)
        document.isDirty = false
        document.fileURL = URL(fileURLWithPath: "/tmp/a.md")
        XCTAssertEqual(LitteraDocumentStatus(document), .saved)
    }

    func testPreviewRelatedStateDoesNotChangeSavedMarkdownOrDirtyState() {
        let store = LitteraDocumentStore.isolated()
        let documentID = store.activeDocumentID
        store.documents[0].markdown = "# Título\n\nTexto"
        store.documents[0].savedMarkdown = "# Título\n\nTexto"
        let originalSavedMarkdown = store.documents[0].savedMarkdown

        let rendered = LitteraMarkdownRenderer().render(
            LitteraMarkdownParser().parse(store.documents[0].markdown)
        )

        XCTAssertFalse(rendered.blocks.isEmpty)
        XCTAssertEqual(store.documents[0].savedMarkdown, originalSavedMarkdown)
        XCTAssertFalse(store.documents[0].isDirty)
        XCTAssertEqual(store.activeDocumentID, documentID)
    }
}
