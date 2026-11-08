import AppKit
import SwiftUI

/// Desplazamiento de la lista de una paleta.
///
/// Mantiene separados la selección (la guarda la paleta), la posición de
/// desplazamiento (la del `NSScrollView` nativo, que el trackpad mueve con su
/// inercia y su barra habituales) y la geometría de las filas. Solo desplaza
/// la lista cuando la selección de teclado sale del área visible, y lo hace
/// la distancia mínima. El puntero y el trackpad nunca la mueven por sí solos.
final class LitteraPaletteListScroller {
    static let coordinateSpace = "littera.palette.list"

    private weak var scrollView: NSScrollView?
    /// Marco de cada fila en coordenadas del contenido de la lista. Solo
    /// cambia con el layout (búsqueda), no durante el desplazamiento.
    private var rowFrames: [String: CGRect] = [:]
    private var pendingReveal: (id: String, toTop: Bool)?

    func attach(_ scrollView: NSScrollView) {
        self.scrollView = scrollView
        flushPendingReveal()
    }

    func updateRowFrames(_ frames: [String: CGRect]) {
        rowFrames = frames
        flushPendingReveal()
    }

    /// Hace visible la fila. `toTop` lleva la lista al principio (por ejemplo,
    /// al seleccionar el primer resultado, para mostrar también su grupo).
    func reveal(_ id: String, toTop: Bool = false) {
        pendingReveal = (id, toTop)
        flushPendingReveal()
    }

    private func flushPendingReveal() {
        guard let pendingReveal, let scrollView else { return }
        if pendingReveal.toTop {
            self.pendingReveal = nil
            scroll(scrollView, toY: 0)
            return
        }
        // La fila puede no tener todavía geometría (resultados recién filtrados).
        guard let frame = rowFrames[pendingReveal.id] else { return }
        self.pendingReveal = nil

        let margin: CGFloat = 6
        let insets = scrollView.contentInsets
        let clipBounds = scrollView.contentView.bounds
        let visibleTop = clipBounds.minY + insets.top
        let visibleHeight = clipBounds.height - insets.top - insets.bottom
        let visibleBottom = visibleTop + visibleHeight

        if frame.minY - margin < visibleTop {
            scroll(scrollView, toY: frame.minY - margin)
        } else if frame.maxY + margin > visibleBottom {
            scroll(scrollView, toY: frame.maxY + margin - visibleHeight)
        }
    }

    private func scroll(_ scrollView: NSScrollView, toY top: CGFloat) {
        let clipView = scrollView.contentView
        let insets = scrollView.contentInsets
        let visibleHeight = clipView.bounds.height - insets.top - insets.bottom
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let clamped = min(max(0, top), max(0, documentHeight - visibleHeight))
        let target = NSPoint(x: clipView.bounds.minX, y: clamped - insets.top)
        guard abs(clipView.bounds.minY - target.y) >= 0.5 else { return }
        clipView.scroll(to: target)
        scrollView.reflectScrolledClipView(clipView)
    }
}

struct LitteraPaletteRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Publica el marco de una fila de la paleta para `LitteraPaletteListScroller`.
    func litteraPaletteRow(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LitteraPaletteRowFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(LitteraPaletteListScroller.coordinateSpace))]
                )
            }
        }
    }

    /// Conecta el `ScrollView` de una lista de paleta con su desplazador.
    func litteraPaletteList(_ scroller: LitteraPaletteListScroller) -> some View {
        coordinateSpace(name: LitteraPaletteListScroller.coordinateSpace)
            .background {
                LitteraEnclosingScrollViewReader { scrollView in
                    scroller.attach(scrollView)
                }
            }
            .onPreferenceChange(LitteraPaletteRowFramePreferenceKey.self) { frames in
                scroller.updateRowFrames(frames)
            }
    }
}
