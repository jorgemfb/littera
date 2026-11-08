import XCTest
@testable import Littera

@MainActor
final class LitteraExporterTests: XCTestCase {
    func testHTMLExportIsCompletePageWithoutFrontmatter() {
        let html = LitteraExporter.html(
            for: "---\ntitle: Secreto\n---\n# Título <1>\n\nTexto **fuerte**.\n",
            title: "Mi \"documento\""
        )
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<meta charset=\"utf-8\">"))
        XCTAssertTrue(html.contains("<title>Mi &quot;documento&quot;</title>"))
        XCTAssertTrue(html.contains("<h1>"))
        XCTAssertTrue(html.contains("<strong>fuerte</strong>"))
        XCTAssertFalse(html.contains("Secreto"), "El frontmatter no se exporta")
    }

    func testPDFExportProducesPages() throws {
        let paragraphs = (1...60).map { "Párrafo \($0) con texto suficiente para ocupar espacio en la página." }
        let source = "# Documento\n\n" + paragraphs.joined(separator: "\n\n")
        let derived = LitteraMarkdownDerivedDocument(source: source, revision: 1)
        let data = try LitteraExporter.pdf(for: derived, documentURL: nil)
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertGreaterThan(document.numberOfPages, 1)
    }
}

@MainActor
final class LitteraDocumentStatisticsTests: XCTestCase {
    func testCountsProseWithoutFrontmatter() {
        let source = "---\ntitle: X\n---\n# Título\n\nUna línea\notra línea\n\nFin.\n"
        let statistics = LitteraDocumentStatistics(LitteraMarkdownDerivedDocument(source: source, revision: 1))
        XCTAssertEqual(statistics.words, 7)
        XCTAssertEqual(statistics.paragraphs, 3)
        XCTAssertEqual(statistics.lines, 4)
        XCTAssertEqual(statistics.readingMinutes, 1)
        XCTAssertEqual(statistics.charactersWithoutSpaces, "#Título\nUnalínea\notralínea\nFin.".filter { !$0.isWhitespace }.count)
    }
}
