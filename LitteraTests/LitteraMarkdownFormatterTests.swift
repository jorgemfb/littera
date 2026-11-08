import Foundation
import XCTest
@testable import Littera

@MainActor
final class LitteraMarkdownFormatterTests: XCTestCase {
    /// Aplica la acción y devuelve el texto resultante con la selección
    /// marcada como `[`…`]` (o `|` para el cursor).
    private func apply(_ action: LitteraFormattingAction, to marked: String) -> String {
        let (text, selection) = unmark(marked)
        let edit = LitteraMarkdownFormatter.edit(for: action, in: text, selection: selection)
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return mark(result, edit.selection)
    }

    private func unmark(_ marked: String) -> (String, NSRange) {
        let ns = marked as NSString
        let cursor = ns.range(of: "|")
        if cursor.location != NSNotFound {
            return (ns.replacingCharacters(in: cursor, with: ""), NSRange(location: cursor.location, length: 0))
        }
        let open = ns.range(of: "[[")
        let withoutOpen = ns.replacingCharacters(in: open, with: "") as NSString
        let close = withoutOpen.range(of: "]]")
        let text = withoutOpen.replacingCharacters(in: close, with: "")
        return (text, NSRange(location: open.location, length: close.location - open.location))
    }

    private func mark(_ text: String, _ selection: NSRange) -> String {
        let ns = text as NSString
        if selection.length == 0 {
            return ns.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "|")
        }
        let end = ns.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "]]") as NSString
        return end.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "[[")
    }

    // MARK: - En línea

    func testBoldWrapsAndUnwrapsSelection() {
        XCTAssertEqual(apply(.bold, to: "Hola [[mundo]] y más"), "Hola **[[mundo]]** y más")
        XCTAssertEqual(apply(.bold, to: "Hola **[[mundo]]** y más"), "Hola [[mundo]] y más")
        XCTAssertEqual(apply(.bold, to: "Hola [[**mundo**]] y más"), "Hola [[mundo]] y más")
    }

    func testEmptySelectionInsertsMarkersAndTogglesBack() {
        XCTAssertEqual(apply(.bold, to: "a | b"), "a **|** b")
        XCTAssertEqual(apply(.bold, to: "a **|** b"), "a | b")
        XCTAssertEqual(apply(.italic, to: "a *|* b"), "a | b")
    }

    func testSelectionWhitespaceStaysOutsideMarkers() {
        XCTAssertEqual(apply(.italic, to: "[[palabra ]]final"), "*[[palabra]]* final")
    }

    func testItalicInsideBoldDoesNotRemoveBold() {
        XCTAssertEqual(apply(.italic, to: "**[[texto]]**"), "***[[texto]]***")
        XCTAssertEqual(apply(.italic, to: "***[[texto]]***"), "**[[texto]]**")
        XCTAssertEqual(apply(.bold, to: "***[[texto]]***"), "*[[texto]]*")
    }

    func testStrikethroughAndInlineCode() {
        XCTAssertEqual(apply(.strikethrough, to: "[[viejo]]"), "~~[[viejo]]~~")
        XCTAssertEqual(apply(.inlineCode, to: "usa [[let x]] aquí"), "usa `[[let x]]` aquí")
        XCTAssertEqual(apply(.inlineCode, to: "[[a`b]]"), "`` [[a`b]] ``")
    }

    func testLinkAndImage() {
        XCTAssertEqual(apply(.link, to: "ver [[Littera]]"), "ver [Littera]([[url]])")
        XCTAssertEqual(apply(.link, to: "ver |"), "ver [|](url)")
        XCTAssertEqual(apply(.image, to: "[[logo]]"), "![logo]([[url]])")
    }

    func testUnicodeSelection() {
        XCTAssertEqual(apply(.bold, to: "😺 [[año ñ]] 🚀"), "😺 **[[año ñ]]** 🚀")
    }

    // MARK: - Por líneas

    func testHeadingsReplaceAndToggle() {
        XCTAssertEqual(apply(.heading2, to: "Títu|lo"), "## Título|")
        XCTAssertEqual(apply(.heading2, to: "## Títu|lo"), "Título|")
        XCTAssertEqual(apply(.heading1, to: "### Títu|lo"), "# Título|")
        XCTAssertEqual(apply(.heading3, to: "- elem|ento"), "### elemento|")
    }

    func testParagraphRemovesBlockMarkers() {
        XCTAssertEqual(apply(.paragraph, to: "## Tít|ulo"), "Título|")
        XCTAssertEqual(apply(.paragraph, to: "1. uno|"), "uno|")
    }

    func testListsOverMultipleLines() {
        XCTAssertEqual(apply(.bulletList, to: "[[uno\ndos]]"), "[[- uno\n- dos]]")
        XCTAssertEqual(apply(.bulletList, to: "[[- uno\n- dos]]"), "[[uno\ndos]]")
        XCTAssertEqual(apply(.numberedList, to: "[[uno\n\ndos\ntres]]"), "[[1. uno\n\n2. dos\n3. tres]]")
        XCTAssertEqual(apply(.taskList, to: "[[- uno\n2. dos]]"), "[[- [ ] uno\n- [ ] dos]]")
        XCTAssertEqual(apply(.bulletList, to: "[[- [x] hecho]]"), "[[- hecho]]")
    }

    func testQuoteAddsAndRemovesPrefix() {
        XCTAssertEqual(apply(.quote, to: "[[uno\n\ndos]]"), "[[> uno\n>\n> dos]]")
        XCTAssertEqual(apply(.quote, to: "[[> uno\n> dos]]"), "[[uno\ndos]]")
    }

    func testOnlyTouchedLinesChange() {
        XCTAssertEqual(apply(.heading1, to: "antes\nmed|io\ndespués"), "antes\n# medio|\ndespués")
    }

    // MARK: - Bloques

    func testCodeBlockWrapsSelectedLines() {
        XCTAssertEqual(apply(.codeBlock, to: "[[let a = 1\nlet b = 2]]\n"), "```|\nlet a = 1\nlet b = 2\n```\n")
    }

    func testCodeBlockInsertsOnItsOwnLines() {
        XCTAssertEqual(apply(.codeBlock, to: "texto|"), "texto\n\n```\n|\n```")
        XCTAssertEqual(apply(.codeBlock, to: "|"), "```\n|\n```")
    }

    func testSeparatorAndTable() {
        XCTAssertEqual(apply(.separator, to: "uno\n|\ndos"), "uno\n\n---|\n\ndos")
        XCTAssertEqual(apply(.table, to: "|"), "| | |  |\n| --- | --- |\n|  |  |")
    }
}
