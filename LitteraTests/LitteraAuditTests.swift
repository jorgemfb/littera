import Foundation
import XCTest
@testable import Littera

/// Correcciones de la auditoría de la versión 1.0.4.
@MainActor
final class LitteraHTMLExportSafetyTests: XCTestCase {
    private func body(_ markdown: String) -> String {
        let html = LitteraExporter.html(for: markdown, title: "t")
        let start = html.range(of: "<main>")!.upperBound
        let end = html.range(of: "</main>")!.lowerBound
        return String(html[start..<end])
    }

    func testTextIsEscaped() {
        let html = body("Si a < b & c > d, entonces \"x\".\n")
        XCTAssertTrue(html.contains("a &lt; b &amp; c &gt; d"), html)
        XCTAssertFalse(html.contains("a < b"))
    }

    func testCodeIsEscapedAndNeverExecuted() {
        let html = body("```html\n<script>alert(1)</script>\n```\n\nEn línea: `<b>no</b>`\n")
        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertTrue(html.contains("<pre><code class=\"language-html\">&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("<code>&lt;b&gt;no&lt;/b&gt;</code>"))
    }

    func testLinksFollowThePreviewRules() {
        let html = body("[web](https://example.com/?a=1&b=2) [peligro](javascript:alert(1)) [ancla](#seccion) [relativo](otra.md)\n")
        XCTAssertTrue(html.contains("<a href=\"https://example.com/?a=1&amp;b=2\">web</a>"), html)
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertTrue(html.contains("peligro"), "El texto del enlace inseguro se conserva")
        XCTAssertTrue(html.contains("<a href=\"#seccion\">ancla</a>"))
        XCTAssertTrue(html.contains("<a href=\"otra.md\">relativo</a>"))
    }

    func testImagesHaveAltText() {
        let html = body("![Un gato \"feliz\"](gato.png \"Título\")\n")
        XCTAssertTrue(html.contains("<img src=\"gato.png\" alt=\"Un gato &quot;feliz&quot;\" title=\"Título\" />"), html)
    }

    func testHeadingsKeepInlineFormatting() {
        let html = body("## Hola **mundo** y `x < y`\n")
        XCTAssertTrue(html.contains("<h2>Hola <strong>mundo</strong> y <code>x &lt; y</code></h2>"), html)
    }

    func testPunctuationIsNotChanged() {
        let html = body("Usa --force, \"comillas\" y puntos... --- fin\n")
        XCTAssertTrue(html.contains("Usa --force, &quot;comillas&quot; y puntos... --- fin"), html)
        let rendered = LitteraMarkdownDerivedDocument(source: "\"a\" -- b...\n", revision: 1).rendered
        guard case let .paragraph(content) = rendered.blocks.first?.kind else { return XCTFail() }
        XCTAssertEqual(LitteraMarkdownRenderInline.plainText(content), "\"a\" -- b...")
    }

    func testRawHTMLWrittenByTheUserIsKept() {
        let html = body("<div class=\"nota\">hola</div>\n")
        XCTAssertTrue(html.contains("<div class=\"nota\">hola</div>"), html)
    }
}

@MainActor
final class LitteraAuditTests: XCTestCase {
    private let locale = Locale(identifier: "es_ES")

    func testEnablingAutosaveSavesPendingChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LitteraAudit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a.md")
        try Data("uno".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: url.path)

        let defaults = LitteraTestDefaults.make()
        let store = LitteraDocumentStore.isolated(defaults: defaults)
        store.openDocument(at: url, locale: locale)
        store.updateMarkdown(for: store.activeDocumentID, text: "dos")
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)

        defaults.set(true, forKey: LitteraPreferenceKeys.autosave)
        store.autosaveDirtyDocuments()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "dos")
        XCTAssertFalse(store.activeDocument?.isDirty ?? true)
    }

    func testDefaultFolderIsResolvedOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LitteraAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = LitteraTestDefaults.make()

        LitteraDefaultFolder.set(directory, defaults)
        let first = try XCTUnwrap(LitteraDefaultFolder.url(defaults))
        let second = try XCTUnwrap(LitteraDefaultFolder.url(defaults))
        XCTAssertTrue(first == second)
        LitteraDefaultFolder.set(nil, defaults)
        XCTAssertNil(LitteraDefaultFolder.url(defaults))
    }

    func testSafeDestinations() {
        XCTAssertEqual(LitteraHTMLExportRewriter.safeDestination("https://a.es"), "https://a.es")
        XCTAssertEqual(LitteraHTMLExportRewriter.safeDestination("mailto:yo@a.es"), "mailto:yo@a.es")
        XCTAssertEqual(LitteraHTMLExportRewriter.safeDestination("notas/b.md"), "notas/b.md")
        XCTAssertNil(LitteraHTMLExportRewriter.safeDestination("javascript:alert(1)"))
        XCTAssertNil(LitteraHTMLExportRewriter.safeDestination("JavaScript:alert(1)"))
        XCTAssertNil(LitteraHTMLExportRewriter.safeDestination("data:text/html,hola"))
        XCTAssertNil(LitteraHTMLExportRewriter.safeDestination(""))
    }
}
