import Foundation
import XCTest
@testable import Littera

/// Comandos y escritura asistida de la 1.1.0 (D52). Notación: `|` es el
/// cursor y `[[…]]` la selección.
final class LitteraTextCommandsTests: XCTestCase {
    private func parse(_ marked: String) -> (String, NSRange) {
        var text = marked
        if let open = text.range(of: "[["), let close = text.range(of: "]]") {
            let start = text.distance(from: text.startIndex, to: open.lowerBound)
            let length = text.distance(from: open.upperBound, to: close.lowerBound)
            text.removeSubrange(close)
            text.removeSubrange(open)
            let prefix = String(text.prefix(start))
            let selected = String(text.dropFirst(start).prefix(length))
            return (text, NSRange(location: prefix.utf16.count, length: selected.utf16.count))
        }
        let caret = text.range(of: "|")!
        let prefix = String(text[..<caret.lowerBound])
        text.removeSubrange(caret)
        return (text, NSRange(location: prefix.utf16.count, length: 0))
    }

    private func render(_ text: String, _ edit: LitteraTextEdit?) -> String? {
        guard let edit else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        if edit.selection.length == 0 {
            return result.replacingCharacters(in: edit.selection, with: "|")
        }
        return result.substring(to: edit.selection.location) + "[[" + result.substring(with: edit.selection) + "]]"
            + result.substring(from: NSMaxRange(edit.selection))
    }

    private var context: LitteraTextCommands.Context {
        var context = LitteraTextCommands.Context()
        context.date = Date(timeIntervalSince1970: 1_792_800_000) // 2026-10-24 (UTC)
        context.timeZone = TimeZone(identifier: "UTC")!
        context.locale = Locale(identifier: "es_ES")
        return context
    }

    private func apply(_ command: LitteraEditingCommand, _ marked: String, format: LitteraDateFormat = .iso) -> String? {
        let (text, selection) = parse(marked)
        var context = context
        context.dateFormat = format
        return render(text, LitteraTextCommands.edit(for: command, in: text, selection: selection, context: context))
    }

    private func enter(_ marked: String) -> String? {
        let (text, selection) = parse(marked)
        return render(text, LitteraTextCommands.continueList(in: text, selection: selection))
    }

    // MARK: Continuar listas

    func testListContinuation() {
        XCTAssertEqual(enter("- uno|"), "- uno\n- |")
        XCTAssertEqual(enter("* uno|\n"), "* uno\n* |\n")
        XCTAssertEqual(enter("  + anidado|"), "  + anidado\n  + |")
        XCTAssertEqual(enter("1. uno|"), "1. uno\n2. |")
        XCTAssertEqual(enter("9) nueve|"), "9) nueve\n10) |")
        XCTAssertEqual(enter("- [x] hecha|"), "- [x] hecha\n- [ ] |", "Una tarea nueva empieza pendiente")
        XCTAssertEqual(enter("- dos| partes"), "- dos\n- | partes", "Divide el elemento")
    }

    func testEmptyItemEndsTheList() {
        XCTAssertEqual(enter("- uno\n- |"), "- uno\n|")
        XCTAssertEqual(enter("1. uno\n2. |"), "1. uno\n|")
        XCTAssertEqual(enter("- [ ] |"), "|")
    }

    func testNoContinuationOutsideLists() {
        XCTAssertNil(enter("Texto normal|"))
        XCTAssertNil(enter("---|"), "Separador, no lista")
        XCTAssertNil(enter("**negrita**|"))
        XCTAssertNil(enter("-|"), "Guion sin espacio")
        XCTAssertNil(enter("|- uno"), "Cursor antes del marcador")
        XCTAssertNil(enter("```\n- dentro de código|"), "Dentro de un bloque de código")
        XCTAssertEqual(enter("```\ncódigo\n```\n- fuera|"), "```\ncódigo\n```\n- fuera\n- |")
    }

    // MARK: Cierre de símbolos

    private func typed(_ character: Character, _ marked: String) -> String? {
        // El carácter ya está insertado antes del cursor.
        let (text, selection) = parse(marked)
        return render(text, LitteraTextCommands.completePair(typed: character, in: text, caret: selection.location))
    }

    func testOpeningCharactersAreClosed() {
        XCTAssertEqual(typed("(", "(|"), "(|)")
        XCTAssertEqual(typed("[", "- [|"), "- [|]")
        XCTAssertEqual(typed("{", "{| texto"), "{|} texto")
        XCTAssertEqual(typed("\"", "di \"|"), "di \"|\"")
        XCTAssertEqual(typed("`", "`|"), "`|`")
    }

    func testNoClosingWhenItWouldGetInTheWay() {
        XCTAssertNil(typed("(", "(|texto"), "Antes de una palabra")
        XCTAssertNil(typed("\"", "palabra\"|"), "Comilla tras una letra")
        XCTAssertNil(typed("`", "``|"), "Tercer acento grave: bloque de código")
    }

    func testTypingTheCloserSkipsOverIt() {
        XCTAssertEqual(typed(")", "(a)|)"), "(a)|")
        XCTAssertEqual(typed("`", "``|`"), "``|", "Segundo acento grave pasa por encima")
        XCTAssertEqual(typed("\"", "\"x\"|\""), "\"x\"|")
    }

    func testThreeBackticksMakeAFence() {
        var text = ""
        var caret = 0
        for _ in 0..<3 {
            text = (text as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: "`")
            caret += 1
            if let edit = LitteraTextCommands.completePair(typed: "`", in: text, caret: caret) {
                text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                caret = edit.selection.location
            }
        }
        XCTAssertEqual(text, "```")
        XCTAssertEqual(caret, 3)
    }

    func testSelectionIsWrapped() {
        let (text, selection) = parse("un [[texto]] aquí")
        XCTAssertEqual(render(text, LitteraTextCommands.autoPair(typing: "(", in: text, selection: selection)), "un ([[texto]]) aquí")
        XCTAssertEqual(render(text, LitteraTextCommands.autoPair(typing: "`", in: text, selection: selection)), "un `[[texto]]` aquí")
        XCTAssertNil(LitteraTextCommands.autoPair(typing: "a", in: text, selection: selection))
    }

    func testBackspaceRemovesEmptyPair() {
        let (text, selection) = parse("x(|)y")
        XCTAssertEqual(render(text, LitteraTextCommands.deletePair(in: text, selection: selection)), "x|y")
        let (other, otherSelection) = parse("x(|a)")
        XCTAssertNil(LitteraTextCommands.deletePair(in: other, selection: otherSelection))
    }

    // MARK: Pegar URL

    func testPastingURLOverSelectionMakesLink() {
        let (text, selection) = parse("Lee [[la guía]] hoy")
        XCTAssertEqual(
            render(text, LitteraTextCommands.linkFromPaste("https://example.com/guia\n", in: text, selection: selection)),
            "Lee [la guía](https://example.com/guia)| hoy"
        )
        XCTAssertEqual(
            render(text, LitteraTextCommands.linkFromPaste("https://es.wikipedia.org/wiki/Swift_(lenguaje)", in: text, selection: selection)),
            "Lee [la guía](<https://es.wikipedia.org/wiki/Swift_(lenguaje)>)| hoy"
        )
        XCTAssertNil(LitteraTextCommands.linkFromPaste("no es una url", in: text, selection: selection))
        XCTAssertNil(LitteraTextCommands.linkFromPaste("javascript:alert(1)", in: text, selection: selection))
        let (plain, caret) = parse("Sin |selección")
        XCTAssertNil(LitteraTextCommands.linkFromPaste("https://a.es", in: plain, selection: caret))
        let (url, urlSelection) = parse("[[https://a.es]]")
        XCTAssertNil(LitteraTextCommands.linkFromPaste("https://b.es", in: url, selection: urlSelection), "URL sobre URL se pega normal")
    }

    // MARK: Mover y duplicar

    func testMoveLines() {
        XCTAssertEqual(apply(.moveLinesUp, "uno\ndos|\ntres"), "dos|\nuno\ntres")
        XCTAssertEqual(apply(.moveLinesDown, "u|no\ndos\ntres"), "dos\nu|no\ntres")
        XCTAssertEqual(apply(.moveLinesDown, "uno\nd|os\ntres"), "uno\ntres\nd|os", "Hasta la última línea sin salto")
        XCTAssertEqual(apply(.moveLinesUp, "uno\ndos\ntr|es"), "uno\ntr|es\ndos")
        XCTAssertEqual(apply(.moveLinesUp, "a\n[[b\nc]]\nd"), "[[b\nc]]\na\nd", "Varias líneas")
        XCTAssertNil(apply(.moveLinesUp, "pri|mera\nsegunda"))
        XCTAssertNil(apply(.moveLinesDown, "primera\nú|ltima"))
    }

    func testDuplicateLines() {
        XCTAssertEqual(apply(.duplicateLines, "uno|\ndos"), "uno\nuno|\ndos")
        XCTAssertEqual(apply(.duplicateLines, "uno\nd|os"), "uno\ndos\nd|os", "Última línea sin salto")
        XCTAssertEqual(apply(.duplicateLines, "[[a\nb]]\nc"), "a\nb\n[[a\nb]]\nc")
    }

    // MARK: Tareas

    func testToggleTask() {
        XCTAssertEqual(apply(.toggleTask, "- [ ] comprar|"), "- [x] comprar|")
        XCTAssertEqual(apply(.toggleTask, "- [x] comprar|"), "- [ ] comprar|")
        XCTAssertEqual(apply(.toggleTask, "- [X] mayúscula|"), "- [ ] mayúscula|")
        XCTAssertEqual(apply(.toggleTask, "  1. [ ] numerada|"), "  1. [x] numerada|")
        XCTAssertEqual(apply(.toggleTask, "- elemento|"), "- [ ] elemento|", "Elemento de lista pasa a tarea")
        XCTAssertEqual(apply(.toggleTask, "texto|"), "- [ ] texto|", "Línea normal pasa a tarea")
        XCTAssertEqual(apply(.toggleTask, "[[- [x] a\n- [ ] b]]"), "[[- [x] a\n- [x] b]]", "Mezcla: se marcan todas")
        XCTAssertEqual(apply(.toggleTask, "[[- [x] a\n- [x] b]]"), "[[- [ ] a\n- [ ] b]]")
    }

    // MARK: Fecha

    func testInsertDateFormats() {
        XCTAssertEqual(apply(.insertDate, "Hoy: |"), "Hoy: 2026-10-24|")
        XCTAssertEqual(apply(.insertDate, "[[x]]", format: .isoWithTime), "2026-10-24 00:00|")
        XCTAssertEqual(apply(.insertDate, "|", format: .long), "24 de octubre de 2026|")
        XCTAssertEqual(apply(.insertDate, "|", format: .short), "24/10/26|")
    }

    // MARK: Espacios al final

    func testTrimTrailingWhitespace() {
        XCTAssertEqual(apply(.trimTrailingWhitespace, "uno   \ndos\t\n   \ntres|"), "uno  \ndos\n\ntres|", "Salto forzado a dos espacios; tabulador y línea en blanco, fuera")
        XCTAssertEqual(
            apply(.trimTrailingWhitespace, "salto  \nforzado|"), nil,
            "Dos espacios antes de una línea que sigue: salto de línea Markdown, se respeta"
        )
        XCTAssertEqual(apply(.trimTrailingWhitespace, "salto     \nforzado|"), "salto  \nforzado|", "Se deja en dos")
        XCTAssertEqual(apply(.trimTrailingWhitespace, "fin de párrafo  \n\notro|"), "fin de párrafo\n\notro|")
        XCTAssertEqual(apply(.trimTrailingWhitespace, "```\ncódigo   \n```\nfuera   |"), "```\ncódigo   \n```\nfuera|", "El código no se toca")
        XCTAssertEqual(apply(.trimTrailingWhitespace, "a   \nb|"), "a  \nb|")
    }

    // MARK: Ordenar

    func testSortLines() {
        XCTAssertEqual(apply(.sortLinesAscending, "[[pera\nÁrbol\nmanzana\nitem 10\nitem 2]]\nfin"), "[[Árbol\nitem 2\nitem 10\nmanzana\npera]]\nfin")
        XCTAssertEqual(apply(.sortLinesDescending, "[[b\nc\na]]"), "[[c\nb\na]]")
        XCTAssertNil(apply(.sortLinesAscending, "una sola| línea"))
        XCTAssertNil(apply(.sortLinesAscending, "[[a\nb]]"), "Ya ordenado")
    }

    // MARK: Mayúsculas

    func testConvertCase() {
        XCTAssertEqual(apply(.uppercase, "hola [[mundo ñandú]]!"), "hola [[MUNDO ÑANDÚ]]!")
        XCTAssertEqual(apply(.lowercase, "[[ÉPICO Texto]]"), "[[épico texto]]")
        XCTAssertEqual(apply(.capitalize, "[[el señor de los anillos]]"), "[[El Señor De Los Anillos]]")
        XCTAssertNil(apply(.uppercase, "sin| selección"))
    }

    // MARK: Marcadores

    func testListMarkerParser() {
        XCTAssertEqual(LitteraTextCommands.listMarker(in: "- [x] hecho")?.taskChecked, true)
        XCTAssertEqual(LitteraTextCommands.listMarker(in: "12. doce")?.number, 12)
        XCTAssertNil(LitteraTextCommands.listMarker(in: "1234567890. demasiados dígitos"))
        XCTAssertNil(LitteraTextCommands.listMarker(in: "-sin espacio"))
        XCTAssertNil(LitteraTextCommands.listMarker(in: "- [x]pegado")?.taskChecked)
    }
}

@MainActor
final class LitteraNewDocumentTests: XCTestCase {
    func testNewDocumentStartsWithEmptyFrontmatter() {
        let store = LitteraDocumentStore.isolated()
        store.newDocument(locale: Locale(identifier: "es_ES"))
        let document = try? XCTUnwrap(store.activeDocument)
        XCTAssertEqual(document?.markdown, LitteraDocumentProperties.newDocumentTemplate(), "Propiedades prerrellenadas (D53)")
        XCTAssertFalse(document?.isDirty ?? true, "La plantilla no cuenta como cambio")
        XCTAssertNotNil(LitteraFrontmatter.detect(in: LitteraDocumentSession.newDocumentTemplate), "Es un frontmatter válido")
        let derived = LitteraMarkdownDerivedDocument(source: LitteraDocumentSession.newDocumentTemplate, revision: 1)
        XCTAssertEqual(derived.wordCount, 0)
        XCTAssertTrue(derived.rendered.blocks.isEmpty, "La Vista previa no muestra nada")
    }

    func testEditingCommandsAreInPaletteAndShortcuts() {
        let commands = LitteraCommandRegistry.commands(canEdit: true)
        for command in LitteraEditingCommand.allCases {
            XCTAssertTrue(commands.contains { $0.id == command.commandID }, command.rawValue)
            XCTAssertNotNil(LitteraShortcuts.definition(command.commandID), command.rawValue)
            XCTAssertEqual(LitteraCommandRegistry.editingCommand(for: command.commandID), command)
        }
        let disabled = LitteraCommandRegistry.commands(canEdit: false)
        XCTAssertFalse(disabled.first { $0.id == "edit.duplicateLines" }?.enabled ?? true, "Deshabilitados en Vista previa")
        XCTAssertEqual(LitteraShortcuts.definition("edit.duplicateLines")?.defaultCombo?.display, "⌘D")
        XCTAssertEqual(LitteraShortcuts.definition("edit.moveLinesUp")?.defaultCombo?.display, "⌥⌘↑")
        XCTAssertEqual(LitteraShortcuts.definition("edit.toggleTask")?.defaultCombo?.display, "⌘↩")
        XCTAssertEqual(LitteraShortcuts.definition("edit.insertDate")?.defaultCombo?.display, "⇧⌘D")
    }
}
