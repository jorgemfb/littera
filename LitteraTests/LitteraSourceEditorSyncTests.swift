import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Sincronización entre el editor (`LitteraSourceTextView`) y el almacén:
/// eco de lo escrito, cambios externos, composición, Deshacer y resaltado.
/// Protege LIT-004 (Fase 2): las comparaciones de texto se optimizan sin
/// cambiar este comportamiento.
@MainActor
final class LitteraSourceEditorSyncTests: XCTestCase {
    private struct Host: View {
        @ObservedObject var store: LitteraDocumentStore
        @State private var selection: [NSRange] = []
        @State private var offset: CGPoint = .zero

        var body: some View {
            let id = store.activeDocumentID
            LitteraSourceTextView(
                text: Binding(
                    get: { store.activeDocument?.markdown ?? "" },
                    set: { store.updateMarkdown(for: id, text: $0) }
                ),
                selectedRanges: $selection,
                scrollOffset: $offset,
                documentID: id,
                fontSize: 13,
                textColor: .textColor,
                scrollCoordinator: nil,
                mode: .source,
                sourceHighlight: LitteraSourceHighlight(document: store.derivedDocuments[id], colorScheme: .light)
            )
            .id(id)
        }
    }

    private var window: NSWindow?

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    private func drain(_ passes: Int = 5) {
        for _ in 0..<passes { CFRunLoopRunInMode(.defaultMode, 0, true) }
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return true
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    private func host(_ text: String) throws -> (LitteraDocumentStore, NSTextView) {
        let store = LitteraDocumentStore.isolated()
        store.updateMarkdown(for: store.activeDocumentID, text: text)
        let id = store.activeDocumentID
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == text })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(store: store))
        window.orderFront(nil)
        self.window = window
        drain(10)
        let content = try XCTUnwrap(window.contentView)
        // SwiftUI crea el editor en un ciclo posterior: esperar a que exista.
        XCTAssertTrue(wait { findTextView(in: content) != nil })
        let textView = try XCTUnwrap(findTextView(in: content))
        window.makeFirstResponder(textView)
        return (store, textView)
    }

    private let noReplacement = NSRange(location: NSNotFound, length: 0)

    func testTypingReachesTheStoreCharacterByCharacter() throws {
        let (store, textView) = try host("# Título\n\nTexto ")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        for character in ["ñ", "é", "😀", "a"] {
            textView.insertText(character, replacementRange: noReplacement)
            drain()
            XCTAssertEqual(store.activeDocument?.markdown, textView.string)
        }
        XCTAssertEqual(store.activeDocument?.markdown, "# Título\n\nTexto ñé😀a")
    }

    func testEchoKeepsUndoAndSelection() throws {
        let (store, textView) = try host("uno dos")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("X", replacementRange: noReplacement)
        drain()
        let id = store.activeDocumentID
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == "unoX dos" })
        drain()
        XCTAssertEqual(textView.string, "unoX dos")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0), "El eco no mueve el cursor")
        XCTAssertTrue(textView.undoManager?.canUndo ?? false, "El eco no vacía Deshacer")
    }

    func testExternalChangeReplacesEditorText() throws {
        let (store, textView) = try host("uno")
        store.updateMarkdown(for: store.activeDocumentID, text: "otro texto")
        drain()
        XCTAssertEqual(textView.string, "otro texto")
    }

    func testCompositionIsNotInterruptedByUpdates() throws {
        let (store, textView) = try host("caf")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: noReplacement)
        drain()
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(store.activeDocument?.markdown, "caf", "Lo provisional no se envía")
        textView.insertText("é", replacementRange: noReplacement)
        drain()
        XCTAssertEqual(store.activeDocument?.markdown, "café")
        XCTAssertEqual(textView.string, "café")
    }

    func testUndoAfterTypingRestoresStore() throws {
        let (store, textView) = try host("base")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.breakUndoCoalescing()
        textView.insertText(" más", replacementRange: noReplacement)
        drain()
        XCTAssertEqual(store.activeDocument?.markdown, "base más")
        textView.undoManager?.undo()
        drain()
        XCTAssertEqual(textView.string, "base")
        XCTAssertEqual(store.activeDocument?.markdown, "base")
    }

    func testHighlightIsAppliedOnceTheAnalysisMatches() throws {
        let text = "# Título\n\nTexto normal y **negrita**.\n"
        let (store, textView) = try host(text)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.insertText("Más", replacementRange: noReplacement)
        drain()
        let id = store.activeDocumentID
        let expected = textView.string
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == expected })
        drain()
        let storage = try XCTUnwrap(textView.textStorage)
        let marker = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let body = storage.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(marker)
        XCTAssertNotEqual(marker, body, "El marcador del encabezado tiene su propio color")
        XCTAssertEqual(textView.string, expected, "El resaltado no cambia el texto")
    }

    func testProgrammaticEditThroughEditingTargetReachesTheStore() throws {
        let (store, textView) = try host("hola")
        LitteraEditingTarget.perform(
            LitteraTextEdit(range: NSRange(location: 0, length: 4), replacement: "adiós", selection: NSRange(location: 5, length: 0)),
            on: textView
        )
        drain()
        XCTAssertEqual(store.activeDocument?.markdown, "adiós")
    }
}
