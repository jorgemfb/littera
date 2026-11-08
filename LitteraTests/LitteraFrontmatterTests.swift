import Foundation
import XCTest
@testable import Littera

@MainActor
final class LitteraFrontmatterTests: XCTestCase {
    private let sample = "---\ntitle: Mi texto\ntags: [a, b]\n---\n# Título\n\nTexto.\n"

    func testDetectsFrontmatterAndEntries() throws {
        let frontmatter = try XCTUnwrap(LitteraFrontmatter.detect(in: sample))
        XCTAssertEqual(frontmatter.range, NSRange(location: 0, length: 37))
        XCTAssertEqual(frontmatter.yaml, "title: Mi texto\ntags: [a, b]")
        XCTAssertEqual(frontmatter.entries.map(\.key), ["title", "tags"])
        XCTAssertEqual(frontmatter.entries.map(\.value), ["Mi texto", "[a, b]"])
    }

    func testRequiresOpeningOnFirstLineAndClosingDelimiter() {
        XCTAssertNil(LitteraFrontmatter.detect(in: "\n---\na: b\n---\n"))
        XCTAssertNil(LitteraFrontmatter.detect(in: "---\na: b\nsin cierre\n"))
        XCTAssertNil(LitteraFrontmatter.detect(in: "---"))
        XCTAssertNotNil(LitteraFrontmatter.detect(in: "---\na: b\n...\nTexto"))
        XCTAssertNotNil(LitteraFrontmatter.detect(in: "---\n---\n"), "Frontmatter vacío")
    }

    func testFrontmatterIsNotRenderedAsMarkdown() {
        let derived = LitteraMarkdownDerivedDocument(source: sample, revision: 1)
        XCTAssertEqual(derived.rendered.blocks.count, 2, "Solo el encabezado y el párrafo")
        if case let .heading(level, _) = derived.rendered.blocks.first?.kind {
            XCTAssertEqual(level, 1)
        } else {
            XCTFail("El primer bloque debe ser el título del documento")
        }
        XCTAssertEqual(derived.wordCount, 3, "El frontmatter no cuenta como palabras")
        XCTAssertNotNil(derived.frontmatter)
    }

    func testBlockRangesAfterFrontmatterPointToOriginalText() throws {
        let derived = LitteraMarkdownDerivedDocument(source: sample, revision: 1)
        let heading = try XCTUnwrap(derived.rendered.blocks.first?.sourceRange?.utf16Range)
        XCTAssertEqual((sample as NSString).substring(with: heading), "# Título")
    }

    func testVisualRunsIncludeFrontmatter() {
        let derived = LitteraMarkdownDerivedDocument(source: sample, revision: 1)
        XCTAssertTrue(derived.visualRuns.contains(LitteraVisualRun(range: NSRange(location: 0, length: 37), kind: .frontmatter)))
    }

    func testThematicBreakDocumentWithoutFrontmatterIsUnchanged() {
        let source = "Texto\n\n---\n\nMás texto\n"
        XCTAssertNil(LitteraFrontmatter.detect(in: source))
        XCTAssertNil(LitteraMarkdownDerivedDocument(source: source, revision: 1).frontmatter)
    }
}
