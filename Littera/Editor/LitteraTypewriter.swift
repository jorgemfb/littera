import AppKit

/// Modo máquina de escribir: la línea activa se mantiene en el centro
/// vertical de la ventana y el resto del texto se atenúa.
///
/// La atenuación usa atributos temporales del layout manager: no toca el
/// texto, sus atributos ni Deshacer, y desaparece al desactivar el modo.
@MainActor
final class LitteraTypewriter {
    private(set) var isEnabled = false
    private var dimColor: NSColor = .secondaryLabelColor

    func configure(enabled: Bool, dimColor: NSColor, textView: NSTextView, scrollView: NSScrollView) {
        let changed = enabled != isEnabled || dimColor != self.dimColor
        isEnabled = enabled
        self.dimColor = dimColor
        guard changed else { return }
        if enabled {
            update(textView: textView, scrollView: scrollView)
        } else {
            textView.layoutManager?.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length)
            )
            scrollView.contentInsets = NSEdgeInsets()
        }
    }

    /// Atenúa todo salvo el párrafo activo y lo centra en la ventana.
    func update(textView: NSTextView, scrollView: NSScrollView) {
        guard isEnabled,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let length = text.length
        let selection = textView.selectedRange()

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
        let active = text.paragraphRange(for: NSRange(location: min(selection.location, length), length: 0))
        if active.location > 0 {
            layoutManager.addTemporaryAttribute(
                .foregroundColor, value: dimColor,
                forCharacterRange: NSRange(location: 0, length: active.location)
            )
        }
        if NSMaxRange(active) < length {
            layoutManager.addTemporaryAttribute(
                .foregroundColor, value: dimColor,
                forCharacterRange: NSRange(location: NSMaxRange(active), length: length - NSMaxRange(active))
            )
        }

        // Margen de media ventana arriba y abajo: la primera y la última
        // línea también pueden quedar en el centro.
        let half = (scrollView.contentView.bounds.height / 2).rounded()
        scrollView.automaticallyAdjustsContentInsets = false
        if scrollView.contentInsets.top != half || scrollView.contentInsets.bottom != half {
            scrollView.contentInsets = NSEdgeInsets(top: half, left: 0, bottom: half, right: 0)
        }

        layoutManager.ensureLayout(for: container)
        var caret: NSRect
        if selection.location >= length, !layoutManager.extraLineFragmentRect.isEmpty {
            caret = layoutManager.extraLineFragmentRect
        } else {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(selection.location, max(length - 1, 0)))
            caret = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        caret.origin.y += textView.textContainerOrigin.y
        let target = NSPoint(x: scrollView.contentView.bounds.origin.x, y: caret.midY - half)
        if abs(scrollView.contentView.bounds.origin.y - target.y) > 0.5 {
            scrollView.contentView.scroll(to: target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
