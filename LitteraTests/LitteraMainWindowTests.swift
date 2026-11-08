import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Ventana v1 (D76): arranca en el editor, sin biblioteca delante, y las
/// paletas y los comandos de documento siguen llegando.
@MainActor
final class LitteraMainWindowTests: XCTestCase {
    private var window: NSWindow?
    private let applicationDelegate = LitteraApplicationDelegate()

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found = (view as? T).map { [$0] } ?? []
        for subview in view.subviews { found += views(type, in: subview) }
        return found
    }

    private func host() throws -> (LitteraDocumentStore, NSView) {
        let store = LitteraDocumentStore.isolated()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LitteraMainWindow(
            documentStore: store,
            applicationDelegate: applicationDelegate
        ))
        window.orderFront(nil)
        self.window = window
        spin(1)
        return (store, try XCTUnwrap(window.contentView))
    }

    func testOpensOnTheEditorFillingTheWindow() throws {
        let (_, content) = try host()
        let editor = try XCTUnwrap(
            views(NSScrollView.self, in: content).first { $0.documentView is LitteraEditorTextView },
            "La ventana arranca en el editor"
        )
        XCTAssertGreaterThan(editor.frame.width, content.bounds.width * 0.9, "El editor ocupa todo el ancho: sin barra lateral ni inspector")
    }

    func testPaletteAndDocumentCommandsStillReachTheWindow() throws {
        let (store, content) = try host()
        let fieldsBefore = views(NSTextField.self, in: content).filter(\.isEditable).count

        NotificationCenter.default.post(name: .litteraShowPalette, object: nil)
        spin(0.5)
        XCTAssertGreaterThan(views(NSTextField.self, in: content).filter(\.isEditable).count, fieldsBefore, "⌘K abre la paleta")

        let count = store.documents.count
        NotificationCenter.default.post(name: .litteraNewDocument, object: nil)
        spin(0.3)
        XCTAssertEqual(store.documents.count, count + 1, "⌘N llega al centro de mando")
    }
}

/// H14: con una sola ventana, cerrarla sale de la app (D82).
@MainActor
final class LitteraLastWindowTests: XCTestCase {
    func testClosingTheLastWindowQuitsTheApp() {
        let delegate = LitteraApplicationDelegate()
        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testQuittingAfterDiscardingInTheWindowDoesNotAskAgain() throws {
        let prompts = LitteraStubPrompts()
        prompts.unsavedChoice = .discard
        let store = LitteraDocumentStore.isolated(prompts: prompts)
        store.updateMarkdown(for: store.activeDocumentID, text: "borrador")
        let delegate = LitteraApplicationDelegate()
        delegate.documentStore = store
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        XCTAssertTrue(delegate.windowShouldClose(window))
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertEqual(prompts.questions.count, 1, "Una sola pregunta: al cerrar la ventana")
    }
}
