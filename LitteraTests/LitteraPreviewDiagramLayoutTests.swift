import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Los diagramas Mermaid de la Vista previa ocupan su altura real al
/// maquetarse (no solo su `bounds`). Regresión 2026-11-08: tras ajustarlos a
/// la columna, TextKit conservaba el tamaño de 1 punto que tenían antes de que
/// la vista tuviera ancho, y no se veían ni en Vista previa ni en Dividido.
@MainActor
final class LitteraPreviewDiagramLayoutTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found = (view as? T).map { [$0] } ?? []
        for subview in view.subviews { found += views(type, in: subview) }
        return found
    }

    private static let document = """
    # Árbol de prueba

    ## Rama A

    ```mermaid
    flowchart BT
        A["Persona A<br/>n. 2000"]
        B["Madre de A"]
        C["Padre de A"]
        D["Abuela"]
        A --> B
        A --> C
        B --> D
    ```

    ### Después del diagrama

    Texto.
    """

    /// Alto con el que TextKit maqueta cada adjunto de la Vista previa visible.
    private func laidOutAttachmentHeights(in window: NSWindow) throws -> [CGFloat] {
        let textView = try XCTUnwrap(views(LitteraPreviewTextView.self, in: try XCTUnwrap(window.contentView))
            .first { $0.enclosingScrollView?.alphaValue == 1 })
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        let storage = try XCTUnwrap(textView.textStorage)
        layoutManager.ensureLayout(for: container)
        var heights: [CGFloat] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value is NSTextAttachment else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            heights.append(layoutManager.boundingRect(forGlyphRange: glyphs, in: container).height)
        }
        return heights
    }

    func testDiagramsTakeTheirHeightInPreviewAndSplit() throws {
        for mode in [LitteraEditorMode.preview, .split] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagrama-\(UUID().uuidString).md")
            try Data(Self.document.utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let store = LitteraDocumentStore.isolated()
            XCTAssertTrue(store.openDocument(at: url, locale: Locale(identifier: "es")))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LitteraMainWindow(documentStore: store, applicationDelegate: LitteraApplicationDelegate()))
            window.orderFront(nil)
            self.window = window
            NotificationCenter.default.post(name: .litteraSetMode, object: mode.rawValue)
            RunLoop.main.run(until: Date().addingTimeInterval(2.5))

            let heights = try laidOutAttachmentHeights(in: window)
            XCTAssertEqual(heights.count, 1, "\(mode.rawValue): un diagrama")
            XCTAssertGreaterThan(heights.first ?? 0, 60, "\(mode.rawValue): el diagrama ocupa su altura al maquetarse")

            window.contentView = nil
            window.close()
            self.window = nil
        }
    }
}
