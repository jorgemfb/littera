import Foundation
import XCTest
@testable import Littera

@MainActor
final class LitteraMarkdownSourceIndexTests: XCTestCase {
    func testConvertsLineAndColumnToUTF8Offsets() {
        let index = LitteraMarkdownSourceIndex("ab\n🙂c\n\nfin")

        XCTAssertEqual(index.utf8Offset(line: 1, column: 1), 0)
        XCTAssertEqual(index.utf8Offset(line: 2, column: 1), 3)
        // La columna 6 está tras 🙂 (4 bytes) y "c".
        XCTAssertEqual(index.utf8Offset(line: 2, column: 6), 8)
        // Columnas más allá del final se limitan al final de la línea.
        XCTAssertEqual(index.utf8Offset(line: 2, column: 99), 8)
        XCTAssertEqual(index.utf8Offset(line: 4, column: 4), 13)
        XCTAssertNil(index.utf8Offset(line: 5, column: 1))
    }

    func testConvertsUTF8OffsetsToUTF16WithRounding() {
        let source = "a🙂e\u{301}\nz"
        let index = LitteraMarkdownSourceIndex(source)

        XCTAssertEqual(index.utf16Offset(forUTF8Offset: 0, rounding: .down), 0)
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: 1, rounding: .down), 1)
        // Dentro del emoji (bytes 1..<5).
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: 3, rounding: .down), 1)
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: 3, rounding: .up), 3)
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: 5, rounding: .down), 3)
        // Final del documento y valores fuera de rango.
        let utf8Count = source.utf8.count
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: utf8Count, rounding: .up), (source as NSString).length)
        XCTAssertEqual(index.utf16Offset(forUTF8Offset: utf8Count + 10, rounding: .up), (source as NSString).length)
    }

    func testRendererRangesMatchSourceInLargeUnicodeDocument() {
        var parts: [String] = []
        for section in 0..<300 {
            parts.append("## Sección 😺 \(section)\n\nPárrafo con e\u{301} y `código` número \(section).\n")
        }
        let source = parts.joined(separator: "\n")
        let rendered = LitteraMarkdownRenderer().render(LitteraMarkdownParser().parse(source))
        let nsSource = source as NSString

        XCTAssertEqual(rendered.blocks.count, 600)
        for (offset, block) in rendered.blocks.enumerated() where offset.isMultiple(of: 2) {
            let section = offset / 2
            XCTAssertEqual(nsSource.substring(with: block.sourceRange!.utf16Range), "## Sección 😺 \(section)")
        }
    }

    func testDerivedDocumentIsReusedUntilMarkdownChanges() async throws {
        let store = LitteraDocumentStore.isolated()
        let documentID = store.activeDocumentID
        try await waitUntil { store.derivedDocuments[documentID] != nil }
        let first = store.derivedDocuments[documentID]
        XCTAssertNotNil(first, "El análisis inicial debe estar disponible antes de reutilizarlo")
        let countBefore = store.derivationCount

        store.updateMarkdown(for: documentID, text: store.activeDocument!.markdown)
        XCTAssertTrue(store.derivedDocuments[documentID] === first)
        XCTAssertEqual(store.derivationCount, countBefore)

        let edited = "# Nuevo\n\nUna dos tres"
        store.updateMarkdown(for: documentID, text: edited)
        // Editar no espera al parser: la versión anterior sigue disponible.
        XCTAssertTrue(store.derivedDocuments[documentID] === first)

        try await waitUntil { store.derivedDocuments[documentID]?.source == edited }
        XCTAssertEqual(store.derivedDocuments[documentID]?.wordCount, 5)
        XCTAssertEqual(store.derivationCount, countBefore + 1)
        XCTAssertGreaterThan(store.derivedDocuments[documentID]!.revision, first!.revision)
    }

    func testRapidEditsEndWithLatestVersion() async throws {
        let store = LitteraDocumentStore.isolated()
        let documentID = store.activeDocumentID
        var text = "# Inicio\n"
        for index in 0..<50 {
            text += "\n\nPárrafo \(index) con **negrita**."
            store.updateMarkdown(for: documentID, text: text)
        }

        try await waitUntil { store.derivedDocuments[documentID]?.source == text }
        // No se analiza cada pulsación: como mucho una tarea en curso por documento.
        XCTAssertLessThan(store.derivationCount, 50)
        XCTAssertEqual(store.derivedDocuments[documentID]?.rendered.blocks.count, 51)
    }

    func testTaskListItemsKeepCheckboxState() {
        let source = "- [x] hecha\n- [ ] pendiente\n- normal\n"
        let rendered = LitteraMarkdownRenderer().render(LitteraMarkdownParser().parse(source))
        guard case let .unorderedList(items) = rendered.blocks.first?.kind else {
            return XCTFail("Se esperaba una lista")
        }
        XCTAssertEqual(items.map(\.checkbox), [true, false, nil])
    }

    func testFencedCodeBlockWithLanguage() {
        let source = "Texto\n\n```php\necho $print\n```\n"
        let rendered = LitteraMarkdownRenderer().render(LitteraMarkdownParser().parse(source))
        XCTAssertEqual(rendered.blocks.count, 2)
        guard case let .codeBlock(language, code, highlights) = rendered.blocks.last?.kind else {
            return XCTFail("Se esperaba un bloque de código")
        }
        XCTAssertEqual(language, "php")
        XCTAssertEqual(code, "echo $print\n")
        XCTAssertEqual(highlights.map(\.kind), [.keyword, .variable])
    }

    func testHighlightsJSONLikeReference() {
        let code = "{\n  \"page\": 14,\n  \"tags\": [\"seguro\"],\n  \"ok\": true\n}"
        let tokens = LitteraSyntaxHighlighter.tokens(for: code, language: "json")
        let text = code as NSString
        func kind(of fragment: String) -> LitteraSyntaxTokenKind? {
            let range = text.range(of: fragment)
            return tokens.first { $0.range == range }?.kind
        }
        XCTAssertEqual(kind(of: "\"page\""), .key)
        XCTAssertEqual(kind(of: "14"), .number)
        XCTAssertEqual(kind(of: "\"seguro\""), .string)
        XCTAssertEqual(kind(of: "true"), .keyword)
        XCTAssertEqual(kind(of: "{"), .punctuation)
        XCTAssertTrue(LitteraSyntaxHighlighter.tokens(for: code, language: "desconocido").isEmpty)
    }

    func testHighlighterHandlesUnterminatedInputAndUnicode() {
        // Entradas incompletas no deben colgar ni salirse de rango.
        for language in ["swift", "php", "json", "html", "python", "sql", "yaml", "bash", "css"] {
            for code in ["\"sin cerrar", "/* abierto", "<div class=\"x", "😺 = \"ñ\" // é", "$", "'''", ""] {
                let length = (code as NSString).length
                for token in LitteraSyntaxHighlighter.tokens(for: code, language: language) {
                    XCTAssertLessThanOrEqual(NSMaxRange(token.range), length, "\(language): \(code)")
                }
            }
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                return XCTFail("La condición no se cumplió en \(timeout) s")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
