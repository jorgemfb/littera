import AppKit
import SwiftUI

/// Dibuja detrás del texto las tarjetas de código, índice e imágenes, las
/// citas con su barra y los separadores (`LitteraPreviewDecoration`).
final class LitteraPreviewLayoutManager: NSLayoutManager {
    var colors = LitteraPalette(.light)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for (range, decoration) in Self.decorations(in: storage, touching: characters) {
            guard var rect = usedRect(for: range) else { continue }
            rect.origin.x = 0
            rect.size.width = container.size.width
            rect = rect.offsetBy(dx: origin.x, dy: origin.y)
            let secondary = NSColor(colors.secondary)
            switch decoration.kind {
            case .card:
                let card = rect.insetBy(dx: 0, dy: -decoration.padding)
                let path = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
                secondary.setFill()
                path.fill()
                NSColor(colors.line).setStroke()
                path.lineWidth = 1
                path.stroke()
            case .quote:
                let card = rect.insetBy(dx: 0, dy: -decoration.padding + 10)
                secondary.setFill()
                NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()
                NSColor(colors.accent).setFill()
                NSRect(x: card.minX + 17, y: card.minY + 12, width: 3, height: max(0, card.height - 24)).fill()
            case .rule:
                NSColor(colors.line).setFill()
                NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: 1).fill()
            }
        }
    }

    /// Rectángulo que ocupa el texto de un rango, sin el espaciado de párrafo.
    func usedRect(for range: NSRange) -> NSRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            rect = rect.union(used)
        }
        return rect.isNull ? nil : rect
    }

    static func decorations(in storage: NSTextStorage, touching characters: NSRange) -> [(NSRange, LitteraPreviewDecoration)] {
        var found: [(NSRange, LitteraPreviewDecoration)] = []
        storage.enumerateAttribute(.litteraPreviewDecoration, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard let decoration = value as? LitteraPreviewDecoration else { return }
            if NSMaxRange(range) < characters.location { return }
            if range.location > NSMaxRange(characters) {
                stop.pointee = true
                return
            }
            found.append((range, decoration))
        }
        return found
    }
}

/// Texto de la Vista previa: de solo lectura y seleccionable, en una columna
/// centrada con la anchura de lectura.
final class LitteraPreviewTextView: NSTextView {
    var writingWidth: CGFloat = 760 {
        didSet { if oldValue != writingWidth { updateInsets() } }
    }
    /// Se llama cuando cambia la anchura (el diseño de las líneas cambia).
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    /// Como `documentView` de un `NSScrollView`, el origen es siempre (0, 0).
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(.zero)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
        if abs(newSize.width - lastWidth) > 0.5 {
            lastWidth = newSize.width
            onWidthChange?()
        }
    }

    /// Anchura disponible para el texto.
    var columnWidth: CGFloat {
        max(1, bounds.width - textContainerInset.width * 2)
    }

    private func updateInsets() {
        let horizontal = max(LitteraDesign.Editor.previewHorizontalPadding, (bounds.width - writingWidth) / 2)
        let inset = NSSize(width: horizontal, height: LitteraDesign.Editor.previewTopPadding)
        guard textContainerInset != inset else { return }
        textContainerInset = inset
    }
}

/// Barra de desplazamiento de la Vista previa. Oculta se mantiene maquetada
/// para mostrarse al instante, sin recibir clics.
final class LitteraPreviewScrollView: NSScrollView {
    var isInteractive = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? super.hitTest(point) : nil
    }
}

/// Lo que determina el contenido de la Vista previa: si no cambia, no se
/// reconstruye el texto.
struct LitteraPreviewContent: Equatable {
    let documentID: String
    let document: LitteraMarkdownDerivedDocument?
    let documentURL: URL?
    let writingWidth: CGFloat
    let bodyLineSpacing: CGFloat
    let colorScheme: ColorScheme
    let locale: Locale

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.documentID == rhs.documentID
            && lhs.document === rhs.document
            && lhs.documentURL == rhs.documentURL
            && lhs.writingWidth == rhs.writingWidth
            && lhs.bodyLineSpacing == rhs.bodyLineSpacing
            && lhs.colorScheme == rhs.colorScheme
            && lhs.locale == rhs.locale
    }
}

/// Vista previa con TextKit en una NSScrollView, conectada al coordinador de
/// desplazamiento a través de su `LitteraPreviewSlot`.
struct LitteraPreviewTextHost: NSViewRepresentable {
    let content: LitteraPreviewContent
    let scrollCoordinator: LitteraScrollCoordinator
    let slot: LitteraPreviewSlot
    let isVisible: Bool
    let isOnScreen: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LitteraPreviewScrollView {
        let scrollView = LitteraPreviewScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let storage = NSTextStorage()
        let layoutManager = LitteraPreviewLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let textView = LitteraPreviewTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.connect(textView: textView, layoutManager: layoutManager, scrollView: scrollView)
        context.coordinator.parent = self
        return scrollView
    }

    func updateNSView(_ scrollView: LitteraPreviewScrollView, context: Context) {
        context.coordinator.parent = self
        slot.setActive(isVisible, coordinator: scrollCoordinator)
        scrollView.isInteractive = isVisible
        scrollView.alphaValue = isVisible ? 1 : 0
        scrollView.isHidden = !isOnScreen
        scrollView.backgroundColor = NSColor(LitteraPalette(content.colorScheme).canvas)
        context.coordinator.update(content: content, isVisible: isVisible)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LitteraPreviewTextHost?
        private weak var textView: LitteraPreviewTextView?
        private weak var layoutManager: LitteraPreviewLayoutManager?
        private weak var scrollView: NSScrollView?
        /// Contenido mostrado y, si la vista estaba oculta, el pendiente.
        private var rendered: LitteraPreviewContent?
        private var renderedGrants = -1
        private var blockRanges: [(id: String, range: NSRange)] = []
        private var codeBlocks: [(range: NSRange, code: String)] = []
        private var copyButtons: [NSButton] = []
        /// Un cambio de anchura no se maqueta en el acto: rehacer el diseño de
        /// todo el documento en cada paso era casi todo el coste de redimensionar
        /// la ventana (H8). Se maqueta al asentarse la anchura o, si está oculta
        /// y se muestra antes, al mostrarse.
        private var isVisible = false
        private var layoutRefreshPending = false
        private var pendingRefresh: DispatchWorkItem?
        static let hiddenRefreshDelay: TimeInterval = 0.5

        func connect(textView: LitteraPreviewTextView, layoutManager: LitteraPreviewLayoutManager, scrollView: NSScrollView) {
            self.textView = textView
            self.layoutManager = layoutManager
            self.scrollView = scrollView
            textView.onWidthChange = { [weak self] in self?.scheduleLayoutRefresh() }
        }

        /// Reconstruye el texto si cambió el contenido. Oculta, solo la
        /// primera vez: el resto espera a mostrarse, para no cargar la escritura.
        func update(content: LitteraPreviewContent, isVisible: Bool) {
            guard let textView, let parent else { return }
            self.isVisible = isVisible
            textView.writingWidth = content.writingWidth
            let grants = LitteraLocalImageAccess.shared.grantsVersion
            let needsBuild = rendered != content || renderedGrants != grants
            guard needsBuild, isVisible || rendered == nil || rendered?.documentID != content.documentID else {
                if let rendered, let scrollView {
                    parent.slot.resolve(scrollView, documentID: rendered.documentID, coordinator: parent.scrollCoordinator)
                }
                if isVisible, layoutRefreshPending { refreshLayout() }
                return
            }
            build(content)
        }

        private func build(_ content: LitteraPreviewContent) {
            guard let textView, let layoutManager, let scrollView, let parent, let storage = textView.textStorage else { return }
            layoutManager.colors = LitteraPalette(content.colorScheme)
            let style = LitteraPreviewTextStyle(scheme: content.colorScheme, bodyLineSpacing: content.bodyLineSpacing, locale: content.locale)
            let documentURL = content.documentURL
            let result = LitteraPreviewTextBuilder.build(content.document?.rendered ?? .empty, style: style) { source in
                Self.imageState(for: source, documentURL: documentURL)
            }
            storage.setAttributedString(result.text)
            blockRanges = result.blockRanges
            codeBlocks = result.codeBlocks
            rendered = content
            renderedGrants = LitteraLocalImageAccess.shared.grantsVersion
            textView.selectedTextAttributes = [.backgroundColor: NSColor(LitteraPalette(content.colorScheme).selected)]
            parent.slot.resolve(scrollView, documentID: content.documentID, coordinator: parent.scrollCoordinator)
            refreshLayout()
        }

        /// Un cambio de anchura se maqueta cuando la anchura se asienta:
        /// visible, enseguida (`widthSettleDelay`); oculta, más tarde.
        private func scheduleLayoutRefresh() {
            layoutRefreshPending = true
            pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.layoutRefreshPending else { return }
                self.refreshLayout()
            }
            pendingRefresh = work
            let delay = isVisible ? LitteraScrollCoordinator.widthSettleDelay : Self.hiddenRefreshDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        /// Ajusta las imágenes a la columna, coloca los botones Copiar y
        /// entrega al coordinador la posición de cada bloque.
        private func refreshLayout() {
            guard let textView, let layoutManager, let container = textView.textContainer,
                  let storage = textView.textStorage, let parent, let rendered else { return }
            layoutRefreshPending = false
            pendingRefresh?.cancel()
            pendingRefresh = nil
            fitAttachments(in: storage, maxWidth: textView.columnWidth)
            layoutManager.ensureLayout(for: container)
            let origin = textView.textContainerOrigin
            var offsets: [String: CGFloat] = [:]
            for (id, range) in blockRanges {
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
                offsets[id] = rect.minY + origin.y
            }
            placeCopyButtons(origin: origin)
            parent.slot.update(offsets, documentID: rendered.documentID, coordinator: parent.scrollCoordinator)
        }

        /// Las imágenes y los diagramas nunca más anchos que la columna.
        ///
        /// TextKit no se entera de que cambia el tamaño de un adjunto: sin
        /// invalidar su línea conservaba el que tenía al maquetarse. Y antes
        /// de que la vista tenga su ancho real la columna mide 1 punto: los
        /// diagramas quedaban maquetados con 1 punto de alto (invisibles).
        private func fitAttachments(in storage: NSTextStorage, maxWidth: CGFloat) {
            guard maxWidth > 40, let layoutManager else { return }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let attachment = value as? NSTextAttachment, let image = attachment.image,
                      image.size.width > 40 else { return }
                let width = min(image.size.width, maxWidth)
                let size = NSSize(width: width, height: image.size.height * width / image.size.width)
                guard attachment.bounds.size != size else { return }
                attachment.bounds = NSRect(origin: .zero, size: size)
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: range)
            }
        }

        private func placeCopyButtons(origin: NSPoint) {
            guard let textView, let layoutManager, let container = textView.textContainer else { return }
            while copyButtons.count < codeBlocks.count {
                let button = NSButton(title: "", target: self, action: #selector(copyCode(_:)))
                button.bezelStyle = .accessoryBarAction
                button.controlSize = .small
                button.font = .systemFont(ofSize: 12)
                textView.addSubview(button)
                copyButtons.append(button)
            }
            while copyButtons.count > codeBlocks.count {
                copyButtons.removeLast().removeFromSuperview()
            }
            let locale = rendered?.locale ?? .current
            for (index, block) in codeBlocks.enumerated() {
                let button = copyButtons[index]
                button.tag = index
                if button.title != L10n.tr("ui.copiado", locale: locale) {
                    button.title = L10n.tr("ui.copiar", locale: locale)
                }
                button.toolTip = L10n.tr("ui.copiar.codigo", locale: locale)
                button.sizeToFit()
                guard let used = layoutManager.usedRect(for: block.range) else { continue }
                let padding = (textView.textStorage?.attribute(.litteraPreviewDecoration, at: block.range.location, effectiveRange: nil)
                    as? LitteraPreviewDecoration)?.padding ?? 16
                let right = origin.x + container.size.width - 8
                button.frame.origin = NSPoint(x: right - button.frame.width, y: origin.y + used.minY - padding + 8)
            }
        }

        @objc private func copyCode(_ sender: NSButton) {
            guard sender.tag < codeBlocks.count else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(codeBlocks[sender.tag].code, forType: .string)
            let locale = rendered?.locale ?? .current
            sender.title = L10n.tr("ui.copiado", locale: locale)
            sender.sizeToFit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak sender] in
                sender?.title = L10n.tr("ui.copiar", locale: locale)
            }
        }

        // MARK: Enlaces

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            switch url.scheme {
            case LitteraPreviewTextBuilder.blockLinkScheme:
                let id = url.absoluteString.replacingOccurrences(of: "\(LitteraPreviewTextBuilder.blockLinkScheme):", with: "")
                parent?.scrollCoordinator.scrollPreview(toBlockID: id)
                return true
            case LitteraPreviewTextBuilder.imageAccessScheme:
                let path = url.absoluteString.replacingOccurrences(of: "\(LitteraPreviewTextBuilder.imageAccessScheme):", with: "")
                let file = URL(fileURLWithPath: path.removingPercentEncoding ?? path)
                if LitteraLocalImageAccess.shared.requestAccess(for: file, locale: rendered?.locale ?? .current), let rendered {
                    build(rendered)
                }
                return true
            default:
                return false
            }
        }

        // MARK: Imágenes

        static func imageState(for source: String?, documentURL: URL?) -> LitteraPreviewImageState {
            guard let source = source?.trimmingCharacters(in: .whitespaces), !source.isEmpty else { return .notFound }
            if let scheme = URL(string: source)?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return .remote
            }
            guard let file = LitteraMarkdownImageView.localFile(for: source, documentURL: documentURL) else {
                return documentURL == nil ? .unsavedDocument : .notFound
            }
            switch LitteraLocalImageAccess.shared.loadNow(file) {
            case let .image(image): return .image(image)
            case .needsAccess: return .needsAccess(file)
            case .notFound: return .notFound
            }
        }
    }
}
