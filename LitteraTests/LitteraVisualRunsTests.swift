import Foundation
import XCTest
@testable import Littera

@MainActor
final class LitteraVisualRunsTests: XCTestCase {
    private func runs(_ source: String) -> [LitteraVisualRun] {
        LitteraVisualRunBuilder.runs(for: LitteraMarkdownParser().parse(source))
    }

    private func substrings(_ source: String, _ kind: LitteraVisualRun.Kind) -> [String] {
        let text = source as NSString
        return runs(source).filter { $0.kind == kind }.map { text.substring(with: $0.range) }
    }

    func testInlineMarkersAreDimmedAndContentStyled() {
        let source = "Texto **negrita** y *cursiva* con `código` y [enlace](https://example.com)."
        XCTAssertEqual(substrings(source, .strong), ["**negrita**"])
        XCTAssertEqual(substrings(source, .emphasis), ["*cursiva*"])
        XCTAssertEqual(substrings(source, .inlineCode), ["`código`"])
        XCTAssertEqual(substrings(source, .link), ["enlace"])
        XCTAssertEqual(
            substrings(source, .marker),
            ["**", "**", "*", "*", "`", "`", "[", "](https://example.com)"]
        )
    }

    func testHeadingMarkerAndLevel() {
        let source = "## Título 😺\n\nPárrafo"
        XCTAssertEqual(substrings(source, .heading(level: 2)), ["## Título 😺"])
        XCTAssertEqual(substrings(source, .marker), ["## "])
    }

    func testTaskListMarkerIncludesCheckbox() {
        let source = "- [x] hecha\n- [ ] pendiente\n- normal\n"
        let all = runs(source)
        let items = all.compactMap { run -> Int? in
            if case let .listItem(_, markerLength) = run.kind { return markerLength }
            return nil
        }
        XCTAssertEqual(items, [6, 6, 2])
        XCTAssertEqual(substrings(source, .completedTask), ["hecha"])
    }

    func testFencedCodeBlockKeepsFencesDimmedAndHighlightsContent() {
        let source = "```json\n{\"a\": 1}\n```\n"
        XCTAssertEqual(substrings(source, .codeBlock).count, 1)
        XCTAssertEqual(substrings(source, .marker), ["```json\n", "```"])
        XCTAssertEqual(substrings(source, .codeToken(.key)), ["\"a\""])
        XCTAssertEqual(substrings(source, .codeToken(.number)), ["1"])
    }

    func testBlockQuoteMarkers() {
        let source = "> primera\n> segunda\n"
        XCTAssertEqual(substrings(source, .blockQuote(depth: 1)).count, 1)
        XCTAssertEqual(substrings(source, .marker), ["> ", "> "])
    }

    func testChangedRangeIsLimitedToTheEdit() {
        let before = "# Uno\n\nTexto **a**.\n\n## Dos\n\nFinal *b*.\n"
        let after = "# Uno\n\nTexto **a** más.\n\n## Dos\n\nFinal *b*.\n"
        let old = runs(before)
        let new = runs(after)
        XCTAssertNil(LitteraVisualRun.changedRange(old: old, oldLength: (before as NSString).length, new: old, newLength: (before as NSString).length))
        let changed = LitteraVisualRun.changedRange(
            old: old, oldLength: (before as NSString).length,
            new: new, newLength: (after as NSString).length
        )
        let edited = (after as NSString).range(of: " más")
        XCTAssertNotNil(changed)
        XCTAssertTrue(NSIntersectionRange(changed!, edited).length > 0)
        // El encabezado final no forma parte de la zona modificada.
        let tail = (after as NSString).range(of: "## Dos")
        XCTAssertLessThanOrEqual(NSMaxRange(changed!), tail.location)
    }
}

extension LitteraVisualRunsTests {
    func testTablePipesAndDelimiterRowAreDimmed() {
        let source = "| A | **B** |\n|---|---|\n| 1 | 2 |\n"
        let markers = substrings(source, .marker)
        XCTAssertTrue(markers.contains("|---|---|\n") || markers.contains("|---|---|"))
        XCTAssertEqual(markers.filter { $0 == "|" }.count, 6)
        XCTAssertEqual(substrings(source, .strong), ["**B**"])
    }
}

extension LitteraVisualRunsTests {
    func testImagesKeepSourceAndAltText() {
        let rendered = LitteraMarkdownRenderer().render(
            LitteraMarkdownParser().parse("Antes ![Logo **Littera**](img/logo.png \"t\") después\n")
        )
        guard case let .paragraph(content) = rendered.blocks.first?.kind,
              let image = content.first(where: \.isImage),
              case let .image(source, alt) = image.kind else {
            return XCTFail("Se esperaba una imagen en el párrafo")
        }
        XCTAssertEqual(source, "img/logo.png")
        XCTAssertEqual(LitteraMarkdownRenderInline.plainText(alt), "Logo Littera")
        XCTAssertEqual(substrings("![a](b.png)", .marker), ["![a](b.png)"])
    }
}
