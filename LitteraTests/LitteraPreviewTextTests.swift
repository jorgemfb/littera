import AppKit
import XCTest
@testable import Littera

/// Vista previa con TextKit: el documento analizado se convierte en un texto
/// con atributos fiel a lo escrito, sin marcas de Markdown.
@MainActor
final class LitteraPreviewTextTests: XCTestCase {
    private let style = LitteraPreviewTextStyle(scheme: .light, bodyLineSpacing: 9, locale: Locale(identifier: "es"))

    private func build(_ markdown: String) -> LitteraPreviewTextBuilder.Result {
        let derived = LitteraMarkdownDerivedDocument(source: markdown, revision: 1)
        return LitteraPreviewTextBuilder.build(derived.rendered, style: style)
    }

    func testInlineFormattingWithoutMarkdownMarkers() throws {
        let result = build("# Título\n\nTexto con **negrita**, *cursiva*, `código` y [enlace](https://example.com).\n")
        let text = result.text.string
        XCTAssertTrue(text.hasPrefix("Título\n"))
        XCTAssertTrue(text.contains("Texto con negrita, cursiva, código y enlace."))
        XCTAssertFalse(text.contains("**") || text.contains("`") || text.contains("]("))

        let ns = text as NSString
        let bold = try XCTUnwrap(result.text.attribute(.font, at: ns.range(of: "negrita").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        let italic = try XCTUnwrap(result.text.attribute(.font, at: ns.range(of: "cursiva").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.italic))
        let code = try XCTUnwrap(result.text.attribute(.font, at: ns.range(of: "código").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(code.isFixedPitch)
        XCTAssertEqual(result.text.attribute(.link, at: ns.range(of: "enlace").location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
    }

    func testUnsafeLinksStayPlainText() {
        let result = build("[peligro](javascript:alert(1))\n")
        XCTAssertNil(result.text.attribute(.link, at: 0, effectiveRange: nil))
    }

    func testBlockRangesCoverTheTextInOrder() {
        let markdown = "# Uno\n\nPárrafo.\n\n- a\n- b\n\n> Cita\n\n```swift\nlet x = 1\n```\n\n---\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"
        let derived = LitteraMarkdownDerivedDocument(source: markdown, revision: 1)
        let result = LitteraPreviewTextBuilder.build(derived.rendered, style: style)
        XCTAssertEqual(result.blockRanges.map(\.id), derived.rendered.blocks.map(\.id))
        var end = 0
        for (_, range) in result.blockRanges {
            XCTAssertEqual(range.location, end, "Sin huecos ni solapes")
            XCTAssertGreaterThan(range.length, 0)
            end = NSMaxRange(range)
        }
        XCTAssertEqual(end, result.text.length)
    }

    func testCodeBlockKeepsCodeAndIsDecorated() throws {
        let result = build("```swift\nlet x = 1\nlet y = 2\n```\n")
        XCTAssertEqual(result.codeBlocks.map(\.code), ["let x = 1\nlet y = 2"])
        let range = try XCTUnwrap(result.codeBlocks.first?.range)
        let decoration = result.text.attribute(.litteraPreviewDecoration, at: range.location, effectiveRange: nil) as? LitteraPreviewDecoration
        XCTAssertEqual(decoration?.kind, .card)
        let font = try XCTUnwrap(result.text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
    }

    func testQuoteListsTasksAndRule() {
        let result = build("> Una cita\n\n- [x] hecha\n- [ ] pendiente\n\n1. uno\n2. dos\n\n---\n")
        let text = result.text
        let ns = text.string as NSString
        let quote = text.attribute(.litteraPreviewDecoration, at: ns.range(of: "Una cita").location, effectiveRange: nil) as? LitteraPreviewDecoration
        XCTAssertEqual(quote?.kind, .quote)
        XCTAssertNotNil(text.attribute(.strikethroughStyle, at: ns.range(of: "hecha").location, effectiveRange: nil), "Tarea completada tachada")
        XCTAssertNil(text.attribute(.strikethroughStyle, at: ns.range(of: "pendiente").location, effectiveRange: nil))
        XCTAssertTrue(ns.contains("1.\tuno") && ns.contains("2.\tdos"))
        var attachments = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 2, "Una casilla por tarea")
        var rules = 0
        text.enumerateAttribute(.litteraPreviewDecoration, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if (value as? LitteraPreviewDecoration)?.kind == .rule { rules += 1 }
        }
        XCTAssertEqual(rules, 1)
    }

    func testTableUsesNativeTextTable() throws {
        let result = build("| Nombre | Valor |\n|:---|---:|\n| a | 1 |\n")
        let ns = result.text.string as NSString
        let style = try XCTUnwrap(result.text.attribute(.paragraphStyle, at: ns.range(of: "Valor").location, effectiveRange: nil) as? NSParagraphStyle)
        let block = try XCTUnwrap(style.textBlocks.first as? NSTextTableBlock)
        XCTAssertEqual(block.table.numberOfColumns, 2)
        XCTAssertEqual(style.alignment, .right)
    }

    func testTableOfContentsLinksToHeadings() throws {
        let markdown = "---\ntoc: true\n---\n# Uno\n\n## Dos\n"
        let derived = LitteraMarkdownDerivedDocument(source: markdown, revision: 1)
        let result = LitteraPreviewTextBuilder.build(derived.rendered, style: style)
        let ns = result.text.string as NSString
        let link = try XCTUnwrap(result.text.attribute(.link, at: ns.range(of: "Dos").location, effectiveRange: nil) as? URL)
        XCTAssertEqual(link.scheme, LitteraPreviewTextBuilder.blockLinkScheme)
        let headingID = link.absoluteString.replacingOccurrences(of: "\(LitteraPreviewTextBuilder.blockLinkScheme):", with: "")
        XCTAssertTrue(result.blockRanges.contains { $0.id == headingID })
    }

    func testMissingImageShowsItsAltText() {
        let result = build("![Un gráfico](no-existe.png)\n")
        XCTAssertTrue(result.text.string.contains("Un gráfico"))
    }

    func testLargeDocumentBuildsQuickly() {
        let section = "## Sección\n\nTexto con **negrita** y `código`.\n\n- uno\n- dos\n\n> Cita\n\n```swift\nlet x = 1\n```\n\n"
        let markdown = String(repeating: section, count: 400)
        let derived = LitteraMarkdownDerivedDocument(source: markdown, revision: 1)
        let start = CFAbsoluteTimeGetCurrent()
        let result = LitteraPreviewTextBuilder.build(derived.rendered, style: style)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("PREVIEWTEXT \(markdown.utf8.count / 1024) KB en \(Int(elapsed * 1000)) ms, \(result.text.length) caracteres")
        XCTAssertEqual(result.blockRanges.count, derived.rendered.blocks.count)
    }
}
