import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Cambio de modo con el `LitteraEditorView` real (LIT-101): el editor no se
/// recrea y conserva texto, foco y posición de lectura. Los tiempos se
/// escriben en el registro de la prueba y no se comparan con ningún umbral.
@MainActor
final class LitteraModeSwitchTests: XCTestCase {
    private var window: NSWindow?
    private let applicationDelegate = LitteraApplicationDelegate()

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    private static let largeDocument: String = (1...220).map { section in
        """
        ## Sección \(section)

        Texto de prueba con **negrita**, *cursiva* y `código` para que el documento \
        tenga un tamaño parecido al de un manuscrito real. Cada párrafo ocupa varias \
        líneas en la columna de escritura del editor.

        - Primer elemento de la lista
        - Segundo elemento de la lista

        > Una cita breve dentro de la sección \(section).

        """
    }.joined(separator: "\n")

    private func spin(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 15) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            spin(for: 0.01)
        }
        return true
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var found = (view as? NSScrollView).map { [$0] } ?? []
        for subview in view.subviews { found += scrollViews(in: subview) }
        return found
    }

    private var editorScrollView: NSScrollView? {
        window?.contentView.flatMap { content in
            scrollViews(in: content).first { $0.documentView is LitteraEditorTextView }
        }
    }

    /// Vistas previas construidas, visibles u ocultas.
    private var builtPreviews: [NSScrollView] {
        window?.contentView.map { content in
            scrollViews(in: content).filter {
                !($0.documentView is LitteraEditorTextView) && ($0.documentView?.bounds.height ?? 0) > 2000
            }
        } ?? []
    }

    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.alphaValue == 0 || candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    private var previewScrollView: NSScrollView? {
        builtPreviews.first(where: isShown)
    }

    private var activeTextView: NSTextView? {
        editorScrollView?.documentView as? NSTextView
    }

    private func fraction(of scrollView: NSScrollView?) -> CGFloat {
        guard let scrollView, let height = scrollView.documentView?.bounds.height, height > 0 else { return -1 }
        return scrollView.documentVisibleRect.minY / height
    }

    private func host(startMode: LitteraEditorMode) throws -> LitteraDocumentStore {
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        store.updateMarkdown(for: id, text: Self.largeDocument)
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == Self.largeDocument })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LitteraEditorView(
            documentStore: store,
            applicationDelegate: applicationDelegate,
            chromeless: true,
            startMode: startMode
        ))
        window.orderFront(nil)
        self.window = window
        XCTAssertTrue(wait { self.activeTextView != nil })
        // Margen para que la Vista previa oculta se construya.
        spin(for: 5)
        return store
    }

    /// Cambia de modo y devuelve los milisegundos hasta el último tramo en que
    /// el hilo principal estuvo ocupado.
    @discardableResult
    private func switchMode(to mode: LitteraEditorMode) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        var lastBusy = start
        NotificationCenter.default.post(name: .litteraSetMode, object: mode.rawValue)
        while CFAbsoluteTimeGetCurrent() - lastBusy < 0.3 {
            let before = CFAbsoluteTimeGetCurrent()
            CFRunLoopRunInMode(.defaultMode, 0.004, true)
            let after = CFAbsoluteTimeGetCurrent()
            if after - before > 0.007 { lastBusy = after }
        }
        return (lastBusy - start) * 1000
    }

    private func scrollEditor(to fraction: CGFloat) throws {
        let scrollView = try XCTUnwrap(editorScrollView)
        let height = try XCTUnwrap(scrollView.documentView?.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: height * fraction))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        spin(for: 0.4)
    }

    func testEditorIsNotRecreatedAcrossModes() throws {
        _ = try host(startMode: .source)
        let editor = try XCTUnwrap(editorScrollView)
        let sequence: [LitteraEditorMode] = [
            .split, .source, .preview, .source,
            .split, .preview, .split, .source
        ]
        var previous = LitteraEditorMode.source
        for mode in sequence {
            let elapsed = switchMode(to: mode)
            print("LIT101M \(previous.rawValue) -> \(mode.rawValue): \(Int(elapsed)) ms")
            XCTAssertTrue(editorScrollView === editor, "El editor se recreó al pasar a \(mode.rawValue)")
            previous = mode
        }
    }

    func testEditsSurviveModeSwitchesInTheSameEditor() throws {
        let store = try host(startMode: .source)
        let source = try XCTUnwrap(activeTextView)
        source.setSelectedRange(NSRange(location: 0, length: 0))
        source.insertText("ñ😀", replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(for: 0.1)

        switchMode(to: .split)
        XCTAssertTrue(activeTextView === source, "Dividido usa la misma vista de texto")
        XCTAssertEqual(store.activeDocument?.markdown, "ñ😀" + Self.largeDocument)

        source.setSelectedRange(NSRange(location: 0, length: 0))
        source.insertText("X", replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(for: 0.1)
        switchMode(to: .preview)
        switchMode(to: .source)
        XCTAssertTrue(activeTextView === source)
        XCTAssertEqual(activeTextView?.string, "Xñ😀" + Self.largeDocument)
        XCTAssertEqual(store.activeDocument?.markdown, activeTextView?.string)
    }

    func testDeletionsAndExternalChangesReachTheOtherView() throws {
        let store = try host(startMode: .source)
        let source = try XCTUnwrap(activeTextView)
        window?.makeFirstResponder(source)
        source.setSelectedRange(NSRange(location: 3, length: 5))
        source.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        source.setSelectedRange(NSRange(location: 40, length: 10))
        source.insertText("sustituido", replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(for: 0.1)
        switchMode(to: .split)
        XCTAssertEqual(activeTextView?.string, store.activeDocument?.markdown)

        switchMode(to: .preview)
        store.updateMarkdown(for: store.activeDocumentID, text: "# Texto externo\n\nNuevo")
        spin(for: 0.2)
        switchMode(to: .source)
        XCTAssertEqual(activeTextView?.string, "# Texto externo\n\nNuevo")
    }

    func testFocusFollowsTheEditorAndLeavesItInPreview() throws {
        _ = try host(startMode: .source)
        let window = try XCTUnwrap(window)
        let source = try XCTUnwrap(activeTextView)
        window.makeFirstResponder(source)

        switchMode(to: .split)
        XCTAssertTrue(window.firstResponder === activeTextView, "Dividido conserva el foco")

        switchMode(to: .preview)
        XCTAssertFalse(window.firstResponder is NSTextView, "El teclado no llega al editor oculto")
        XCTAssertEqual(editorScrollView?.isHidden, true)

        switchMode(to: .source)
        XCTAssertEqual(editorScrollView?.isHidden, false)
        XCTAssertTrue(window.firstResponder === activeTextView, "El foco vuelve al salir de Vista previa")
    }

    /// Con una sola vista de texto (D77), cambiar de modo ya no vacía Deshacer.
    func testUndoSurvivesModeSwitches() throws {
        let store = try host(startMode: .source)
        let source = try XCTUnwrap(activeTextView)
        window?.makeFirstResponder(source)
        let original = store.activeDocument?.markdown
        source.breakUndoCoalescing()
        source.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        spin(for: 0.1)
        XCTAssertEqual(source.undoManager?.canUndo, true)

        switchMode(to: .split)
        switchMode(to: .preview)
        switchMode(to: .source)
        XCTAssertEqual(activeTextView?.undoManager?.canUndo, true)

        activeTextView?.undoManager?.undo()
        spin(for: 0.1)
        XCTAssertEqual(source.string, original)
        XCTAssertEqual(store.activeDocument?.markdown, original)
    }

    func testHiddenPreviewDoesNotCaptureClicks() throws {
        _ = try host(startMode: .source)
        XCTAssertEqual(builtPreviews.count, 2, "Las dos Vistas previas ocultas ya están construidas")
        XCTAssertNil(previewScrollView, "Ninguna se ve en Fuente")
        let content = try XCTUnwrap(window?.contentView)
        let center = NSPoint(x: content.bounds.midX, y: content.bounds.midY)
        let hit = try XCTUnwrap(content.hitTest(center))
        XCTAssertTrue(hit.isDescendant(of: try XCTUnwrap(editorScrollView)), "El clic llega a \(hit)")
    }

    func testHiddenPreviewCatchesUpWhenShown() throws {
        let store = try host(startMode: .source)
        let id = store.activeDocumentID
        let edited = "# Título añadido\n\n" + Self.largeDocument
        store.updateMarkdown(for: id, text: edited)
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == edited })
        spin(for: 0.2)
        let hiddenHeight = builtPreviews.first?.documentView?.bounds.height

        switchMode(to: .preview)
        XCTAssertNotEqual(previewScrollView?.documentView?.bounds.height, hiddenHeight, "Muestra la versión actual")
    }

    func testTypingLatency() throws {
        let store = try host(startMode: .source)
        let textView = try XCTUnwrap(activeTextView)
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 200, length: 0))
        let id = store.activeDocumentID
        var total = 0.0
        var worst = 0.0
        for _ in 0..<60 {
            let start = CFAbsoluteTimeGetCurrent()
            textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
            for _ in 0..<3 { CFRunLoopRunInMode(.defaultMode, 0, true) }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            total += elapsed
            worst = max(worst, elapsed)
            spin(for: 0.03)
        }
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == store.activeDocument?.markdown })
        print("LIT101M pulsacion media \(String(format: "%.1f", total / 60)) ms, peor \(String(format: "%.1f", worst)) ms")
    }

    func testReadingPositionSurvivesPreviewAndSplit() throws {
        _ = try host(startMode: .source)
        try scrollEditor(to: 0.5)
        let start = fraction(of: editorScrollView)
        XCTAssertGreaterThan(start, 0.4)

        switchMode(to: .preview)
        XCTAssertEqual(fraction(of: previewScrollView), start, accuracy: 0.03, "Fuente → Vista previa")

        switchMode(to: .source)
        XCTAssertEqual(fraction(of: editorScrollView), start, accuracy: 0.03, "Vista previa → Fuente")

        switchMode(to: .split)
        spin(for: 0.5)
        XCTAssertEqual(fraction(of: editorScrollView), start, accuracy: 0.03, "Fuente → Dividido")
        XCTAssertEqual(fraction(of: previewScrollView), fraction(of: editorScrollView), accuracy: 0.03, "Paneles de Dividido")

        try scrollEditor(to: 0.25)
        spin(for: 0.3)
        XCTAssertEqual(fraction(of: previewScrollView), fraction(of: editorScrollView), accuracy: 0.03, "Dividido sigue sincronizado")
    }

    /// Al salir de Dividido, el editor oculto se ensancha y su texto refluye:
    /// eso no debe registrarse como posición de lectura (antes la posición
    /// retrocedía al volver a Fuente).
    func testReadingPositionSurvivesLeavingSplit() throws {
        _ = try host(startMode: .split)
        try scrollEditor(to: 0.5)
        spin(for: 0.5)
        let start = fraction(of: editorScrollView)
        XCTAssertGreaterThan(start, 0.4)

        switchMode(to: .preview)
        let preview = fraction(of: previewScrollView)
        XCTAssertEqual(preview, start, accuracy: 0.03, "Dividido → Vista previa")

        switchMode(to: .source)
        XCTAssertEqual(fraction(of: editorScrollView), start, accuracy: 0.03, "Vista previa → Fuente")

        switchMode(to: .preview)
        XCTAssertEqual(fraction(of: previewScrollView), preview, accuracy: 0.03, "Fuente → Vista previa")
    }

    func testOnlyOnePreviewIsShownAndKeepsThePositionBetweenWidths() throws {
        _ = try host(startMode: .split)
        try scrollEditor(to: 0.5)
        spin(for: 0.3)
        let split = try XCTUnwrap(previewScrollView)
        let start = fraction(of: split)
        XCTAssertGreaterThan(start, 0.4)

        switchMode(to: .preview)
        spin(for: 0.3)
        let full = try XCTUnwrap(previewScrollView)
        XCTAssertFalse(full === split, "Cada anchura tiene su instancia")
        XCTAssertEqual(builtPreviews.filter(isShown).count, 1)
        XCTAssertEqual(fraction(of: full), start, accuracy: 0.03, "Dividido → Vista previa")

        // Lo que se mueve en Vista previa debe llegar al volver a Dividido.
        let height = try XCTUnwrap(full.documentView?.bounds.height)
        full.contentView.scroll(to: NSPoint(x: 0, y: height * 0.25))
        full.reflectScrolledClipView(full.contentView)
        spin(for: 0.4)

        switchMode(to: .split)
        spin(for: 0.5)
        XCTAssertTrue(previewScrollView === split)
        XCTAssertEqual(builtPreviews.filter(isShown).count, 1)
        XCTAssertEqual(fraction(of: split), 0.25, accuracy: 0.03, "Vista previa → Dividido")
        XCTAssertEqual(fraction(of: editorScrollView), 0.25, accuracy: 0.03, "El editor sigue a la Vista previa")

        try scrollEditor(to: 0.6)
        spin(for: 0.3)
        XCTAssertEqual(fraction(of: split), fraction(of: editorScrollView), accuracy: 0.03, "Dividido sigue sincronizado")
    }
}
