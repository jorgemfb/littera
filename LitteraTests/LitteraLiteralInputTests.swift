import AppKit
import XCTest
@testable import Littera

/// LIT-002: el editor no reescribe el Markdown con las sustituciones
/// automáticas de macOS (mayúscula inicial, corrección, sustituciones de
/// texto, comillas y rayas tipográficas, inserción inteligente).
@MainActor
final class LitteraLiteralInputTests: XCTestCase {
    private let orthography = NSOrthography.defaultOrthography(forLanguage: "es")

    private func makeEditor(_ text: String = "") -> LitteraEditorTextView {
        let view = LitteraEditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        view.applyLiteralInputSettings()
        view.string = text
        view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return view
    }

    private func type(_ text: String, into view: NSTextView) {
        for character in text {
            view.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }

    private func full(_ text: String) -> NSRange { NSRange(location: 0, length: (text as NSString).length) }

    /// Muestras del enunciado con el resultado que macOS aplicaría.
    private var rewritingSamples: [(text: String, result: NSTextCheckingResult)] {
        [
            ("title: hola", .correctionCheckingResult(range: NSRange(location: 0, length: 5), replacementString: "Title")),
            ("(c) 2026", .replacementCheckingResult(range: NSRange(location: 0, length: 3), replacementString: "©")),
            ("\"texto\"", .quoteCheckingResult(range: NSRange(location: 0, length: 7), replacementString: "“texto”")),
            ("'texto'", .quoteCheckingResult(range: NSRange(location: 0, length: 7), replacementString: "‘texto’")),
            ("--texto", .dashCheckingResult(range: NSRange(location: 0, length: 2), replacementString: "—")),
            ("---\ntags: [a, b]\n---", .correctionCheckingResult(range: NSRange(location: 4, length: 4), replacementString: "Tags")),
            ("```\nlet a = \"x\" -- 'y'\n```", .quoteCheckingResult(range: NSRange(location: 12, length: 3), replacementString: "“x”")),
            ("ñandú — 😀 ﬁn", .correctionCheckingResult(range: NSRange(location: 0, length: 5), replacementString: "Ñandú")),
        ]
    }

    func testSettingsDisableRewritingSubstitutions() {
        let view = LitteraEditorTextView()
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.isAutomaticTextReplacementEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true
        view.isAutomaticTextCompletionEnabled = true
        view.smartInsertDeleteEnabled = true
        view.isContinuousSpellCheckingEnabled = true

        view.applyLiteralInputSettings()

        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(view.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(view.smartInsertDeleteEnabled)
        XCTAssertEqual(view.inlinePredictionType, .no)
        XCTAssertEqual(view.mathExpressionCompletionType, .no)
        // La corrección ortográfica visual se conserva.
        XCTAssertTrue(view.isContinuousSpellCheckingEnabled)
    }

    func testFilterKeepsMarksAndDropsRewrites() {
        let range = NSRange(location: 0, length: 4)
        let results: [NSTextCheckingResult] = [
            .spellCheckingResult(range: range),
            .grammarCheckingResult(range: range, details: []),
            .correctionCheckingResult(range: range, replacementString: "Hola"),
            .replacementCheckingResult(range: range, replacementString: "©"),
            .quoteCheckingResult(range: range, replacementString: "“”"),
            .dashCheckingResult(range: range, replacementString: "—"),
        ]
        let kept = LitteraEditorTextView.literalResults(results).map(\.resultType)
        XCTAssertEqual(kept, [.spelling, .grammar])
    }

    func testRewritingResultsLeaveMarkdownUntouched() {
        for sample in rewritingSamples {
            let view = makeEditor(sample.text)
            view.handleTextCheckingResults(
                [sample.result],
                forRange: full(sample.text),
                types: NSTextCheckingAllTypes,
                options: [:],
                orthography: orthography,
                wordCount: 2
            )
            XCTAssertEqual(view.string, sample.text, "Se reescribió: \(sample.text)")
        }
    }

    /// Escribe en una ventana real y deja correr el bucle de eventos para que
    /// AppKit lance sus comprobaciones automáticas diferidas.
    private func typeInWindow(_ view: NSTextView, _ text: String) -> String {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        type(text, into: view)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let result = view.string
        window.contentView = nil
        window.close()
        return result
    }

    private let windowSample = "\"texto\" 'texto' --texto (c) title: hola "

    /// Control: un `NSTextView` con las sustituciones activas sí reescribe la
    /// muestra. Garantiza que la prueba siguiente detectaría una regresión.
    func testControlPlainTextViewRewritesWhileTyping() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        let typed = typeInWindow(view, windowSample)
        guard typed != windowSample else {
            throw XCTSkip("AppKit no aplicó sustituciones en este entorno; el control no es concluyente.")
        }
        XCTAssertTrue(typed.contains("“") || typed.contains("—"), typed)
    }

    func testEditorKeepsMarkdownLiteralWhileTyping() {
        let view = makeEditor()
        view.isContinuousSpellCheckingEnabled = true
        XCTAssertEqual(typeInWindow(view, windowSample), windowSample)
    }

    /// Aunque el usuario reactive las opciones desde Edición › Sustituciones,
    /// el filtro impide que se reescriba el texto.
    func testEditorStaysLiteralWhenSubstitutionsAreReenabled() {
        let view = makeEditor()
        view.isAutomaticQuoteSubstitutionEnabled = true
        view.isAutomaticDashSubstitutionEnabled = true
        view.isAutomaticTextReplacementEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true
        XCTAssertEqual(typeInWindow(view, windowSample), windowSample)
    }

    func testSystemCheckingKeepsMarkdownLiteral() {
        let text = "title: hola\n\"texto\" y 'texto' --texto (c) teh\n---\ntags: [a, b]\n---\n```\nlet a = \"x\"\n```\nñandú 😀"
        let view = makeEditor(text)
        view.isContinuousSpellCheckingEnabled = true
        view.checkText(in: full(text), types: NSTextCheckingAllTypes, options: [:])
        XCTAssertEqual(view.string, text)
    }

    func testTypingKeepsLiteralCharacters() {
        for sample in ["title: hola", "(c)", "\"texto\"", "'texto'", "--texto", "ñandú 😀 ﬁn"] {
            let view = makeEditor()
            type(sample, into: view)
            XCTAssertEqual(view.string, sample, "Escritura alterada: \(sample)")
        }
    }

    func testFrontmatterAndCodeBlockLinesStayLiteral() {
        let view = makeEditor()
        let lines = ["---", "title: hola", "tags: [a, b]", "---", "```swift", "let a = \"x\" -- 'y'", "```"]
        for (index, line) in lines.enumerated() {
            view.insertText(line, replacementRange: NSRange(location: NSNotFound, length: 0))
            if index < lines.count - 1 { view.insertNewline(nil) }
        }
        XCTAssertEqual(view.string, lines.joined(separator: "\n"))
    }

    func testDeadKeysAndInputMethodsCompose() {
        let view = makeEditor("caf")
        let noReplacement = NSRange(location: NSNotFound, length: 0)
        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
        XCTAssertTrue(view.hasMarkedText())
        view.insertText("é", replacementRange: noReplacement)
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.string, "café")

        view.insertText(" ", replacementRange: noReplacement)
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: noReplacement)
        view.insertText("日本", replacementRange: noReplacement)
        XCTAssertEqual(view.string, "café 日本")
    }

    func testUndoRedoKeepLiteralText() {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let provider = UndoProvider(undo)
        let view = makeEditor()
        view.delegate = provider
        let noReplacement = NSRange(location: NSNotFound, length: 0)

        for chunk in ["title: ", "\"texto\" --x"] {
            view.breakUndoCoalescing()
            undo.beginUndoGrouping()
            view.insertText(chunk, replacementRange: noReplacement)
            undo.endUndoGrouping()
        }
        XCTAssertEqual(view.string, "title: \"texto\" --x")
        undo.undo()
        XCTAssertEqual(view.string, "title: ")
        undo.redo()
        XCTAssertEqual(view.string, "title: \"texto\" --x")
        withExtendedLifetime(provider) {}
    }
}

private final class UndoProvider: NSObject, NSTextViewDelegate {
    let manager: UndoManager
    init(_ manager: UndoManager) { self.manager = manager }
    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}
