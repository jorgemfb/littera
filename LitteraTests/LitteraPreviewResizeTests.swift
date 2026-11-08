import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// H8: redimensionar la ventana no rehace el diseño de las Vistas previas
/// ocultas en cada paso; se maquetan al dejar de cambiar la anchura o al
/// mostrarse.
@MainActor
final class LitteraPreviewResizeTests: XCTestCase {
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

    private static let document = (1...400).map { "## Sección \($0)\n\nPárrafo \($0) con texto suficiente para ocupar varias líneas al estrechar la columna de la Vista previa, una y otra vez.\n" }
        .joined(separator: "\n")

    private func host(startMode: LitteraEditorMode = .source) throws -> NSWindow {
        let store = LitteraDocumentStore.isolated()
        store.updateMarkdown(for: store.activeDocumentID, text: Self.document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
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
        // Margen para que se construyan las Vistas previas ocultas.
        spin(3)
        return window
    }

    private func previews(in window: NSWindow) throws -> [LitteraPreviewTextView] {
        let found = views(LitteraPreviewTextView.self, in: try XCTUnwrap(window.contentView))
        XCTAssertFalse(found.isEmpty, "Las Vistas previas ocultas existen en Fuente")
        return found
    }

    private func isFullyLaidOut(_ textView: LitteraPreviewTextView) -> Bool {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return false }
        return layoutManager.firstUnlaidCharacterIndex() >= storage.length
    }

    private func resize(_ window: NSWindow, by delta: CGFloat) {
        var frame = window.frame
        frame.size.width += delta
        window.setFrame(frame, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        // Lo que se ejecute en la siguiente vuelta del bucle, sin llegar al aplazado.
        spin(0.05)
    }

    func testHiddenPreviewsAreLaidOutOnlyAfterTheResizeStops() throws {
        let window = try host()
        let hidden = try previews(in: window)
        XCTAssertTrue(hidden.allSatisfy(isFullyLaidOut), "Construidas y maquetadas en segundo plano")

        resize(window, by: -160)
        XCTAssertFalse(hidden.allSatisfy(isFullyLaidOut), "Durante el redimensionado no se rehace el diseño entero")

        spin(LitteraPreviewTextHost.Coordinator.hiddenRefreshDelay + 0.5)
        XCTAssertTrue(hidden.allSatisfy(isFullyLaidOut), "Al parar, quedan maquetadas para mostrarse al instante")
    }

    /// En Dividido, la Vista previa visible se maqueta entera al asentarse la
    /// anchura, no en cada paso, y queda con la anchura nueva.
    func testVisibleSplitPreviewIsLaidOutWhenTheWidthSettles() throws {
        let window = try host(startMode: .split)
        let visible = try XCTUnwrap(try previews(in: window).first { $0.enclosingScrollView?.alphaValue == 1 })
        XCTAssertTrue(isFullyLaidOut(visible))

        resize(window, by: -160)
        XCTAssertFalse(isFullyLaidOut(visible), "Durante el redimensionado solo se maqueta lo que se ve")

        spin(LitteraScrollCoordinator.widthSettleDelay + 0.3)
        XCTAssertTrue(isFullyLaidOut(visible), "Al asentarse la anchura, posiciones de bloque y botones al día")
        XCTAssertEqual(visible.textContainer?.size.width ?? 0, visible.bounds.width - visible.textContainerInset.width * 2, accuracy: 1)
    }

    func testShowingThePreviewLaysItOutAtOnce() throws {
        let window = try host()
        resize(window, by: -160)
        NotificationCenter.default.post(name: .litteraSetMode, object: LitteraEditorMode.preview.rawValue)
        spin(0.1)
        let visible = try XCTUnwrap(try previews(in: window).first { $0.enclosingScrollView?.alphaValue == 1 })
        XCTAssertTrue(isFullyLaidOut(visible), "Al mostrarse antes del aplazado, se maqueta en el acto")
        XCTAssertEqual(visible.textContainer?.size.width ?? 0, visible.bounds.width - visible.textContainerInset.width * 2, accuracy: 1)
    }
}
