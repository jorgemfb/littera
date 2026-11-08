import AppKit
import SwiftUI

/// Editor de Littera (D77): una sola `NSTextView` con el resaltado de
/// Fuente. Sirve a Fuente y a Dividido; en Vista previa sigue viva, oculta y
/// desconectada, así que volver al editor no recrea nada.
struct LitteraSourceTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRanges: [NSRange]
    @Binding var scrollOffset: CGPoint

    let documentID: String
    let fontSize: CGFloat
    let textColor: NSColor
    /// Coordinador del modo Dividido. Recibe cada desplazamiento de forma
    /// síncrona, sin pasar por el estado de SwiftUI.
    let scrollCoordinator: LitteraScrollCoordinator?
    /// En Vista previa el editor se oculta.
    var mode: LitteraEditorMode = .source
    /// Resaltado Markdown del modo Fuente.
    var sourceHighlight: LitteraSourceHighlight? = nil
    /// Destino de los comandos de formato de la paleta.
    var editingTarget: LitteraEditingTarget? = nil
    var lineSpacing: LitteraLineSpacing = .normal
    var typewriter = false
    var spellChecking = false
    /// Anchura de la columna en Fuente; `nil` usa todo el ancho (Disponible).
    var sourceColumnWidth: CGFloat? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = LitteraSourceColumnTextView()
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.columnWidth = sourceColumnWidth
        Self.configureTextView(textView, delegate: context.coordinator)
        textView.string = text

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.connect(textView: textView, scrollView: scrollView, mode: mode)
        context.coordinator.observeScrollChanges()
        if mode != .preview {
            scrollCoordinator?.attachSource(scrollView: scrollView, textView: textView, documentID: documentID)
        }
        context.coordinator.applyAppearance(fontSize: fontSize, textColor: textColor)
        context.coordinator.applySourceStyle(fontSize: fontSize)
        context.coordinator.scheduleViewportRestore()
        if mode != .preview {
            editingTarget?.register(textView)
        }
        return scrollView
    }

    private static func configureTextView(_ textView: LitteraEditorTextView, delegate: NSTextViewDelegate) {
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        // Markdown es texto literal: `---` no debe convertirse en raya, las
        // comillas rectas en tipográficas ni `title:` en `Title:` (LIT-002).
        textView.applyLiteralInputSettings()
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = delegate
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            parent: self,
            scrollView: scrollView,
            documentID: documentID,
            text: text,
            selectedRanges: selectedRanges,
            fontSize: fontSize,
            textColor: textColor
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingScrollChanges()
        coordinator.cancelPendingScrollPersistence()
        if let textView = coordinator.textView, !coordinator.isPreviewActive {
            coordinator.parent.editingTarget?.unregister(textView)
            coordinator.parent.scrollCoordinator?.detachSource(
                scrollView: scrollView,
                textView: textView,
                documentID: coordinator.documentIDForDetach
            )
        }
        coordinator.disconnectStorage()
        coordinator.textView?.delegate = nil
        coordinator.textView = nil
        coordinator.scrollView = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LitteraSourceTextView

        var textView: LitteraSourceColumnTextView?
        /// En Vista previa el editor sigue vivo, pero oculto y desconectado.
        private(set) var isPreviewActive = false
        private var restoresFocusAfterPreview = false
        weak var scrollView: NSScrollView?

        private var observedScrollToken: NSObjectProtocol?
        private var currentDocumentID: String?
        private var isApplyingScroll = false
        private var suppressScrollUpdates = false
        private var viewportRestoreScheduled = false
        private var pendingScrollPersistence: DispatchWorkItem?
        private var lastSentText: String?
        private var lastSentDocumentID: String?
        private var textCache: (version: Int, text: String)?
        private var storageVersion = 0
        private var storageObserver: NSObjectProtocol?
        private var lastFontSize: CGFloat?
        private var lastTextColor: NSColor?
        private var lastPaletteKey: (scheme: ColorScheme, style: LitteraSourceHighlightStyle)?
        private let sourceStyler = LitteraSourceStyler()
        private let typewriterMode = LitteraTypewriter()

        var documentIDForDetach: String { currentDocumentID ?? parent.documentID }

        init(parent: LitteraSourceTextView) {
            self.parent = parent
        }

        func connect(textView: LitteraSourceColumnTextView, scrollView: NSScrollView, mode: LitteraEditorMode) {
            self.textView = textView
            self.scrollView = scrollView
            isPreviewActive = mode == .preview
            scrollView.isHidden = isPreviewActive
            currentDocumentID = parent.documentID

            if let storage = textView.textStorage {
                storageObserver = NotificationCenter.default.addObserver(
                    forName: NSTextStorage.didProcessEditingNotification,
                    object: storage,
                    queue: nil
                ) { [weak self] notification in
                    guard let storage = notification.object as? NSTextStorage,
                          storage.editedMask.contains(.editedCharacters) else { return }
                    MainActor.assumeIsolated { self?.storageVersion += 1 }
                }
            }
        }

        func disconnectStorage() {
            if let storageObserver {
                NotificationCenter.default.removeObserver(storageObserver)
                self.storageObserver = nil
            }
            textCache = nil
        }

        /// Texto actual del editor como cadena nativa.
        func editorText() -> String {
            textView.map(nativeText(of:)) ?? ""
        }

        /// Comparar la cadena puenteada de `NSTextView` normaliza Unicode en cada
        /// carácter y es muy lento con documentos grandes (LIT-004).
        private func nativeText(of textView: NSTextView) -> String {
            if let textCache, textCache.version == storageVersion {
                return textCache.text
            }
            var text = textView.string
            text.makeContiguousUTF8()
            textCache = (storageVersion, text)
            return text
        }

        // MARK: Actualización principal

        func update(
            parent: LitteraSourceTextView,
            scrollView: NSScrollView,
            documentID: String,
            text: String,
            selectedRanges: [NSRange],
            fontSize: CGFloat,
            textColor: NSColor
        ) {
            guard let textView else { return }
            let documentChanged = currentDocumentID != documentID

            self.parent = parent
            currentDocumentID = documentID
            if documentChanged { cancelPendingScrollPersistence() }

            let wantsPreview = parent.mode == .preview
            if wantsPreview && !isPreviewActive {
                suspendForPreview(scrollView: scrollView, documentID: documentID)
                return
            }
            if !wantsPreview && isPreviewActive {
                resumeFromPreview(
                    scrollView: scrollView,
                    documentID: documentID,
                    text: text,
                    selectedRanges: selectedRanges,
                    fontSize: fontSize,
                    textColor: textColor
                )
                return
            }

            applyAppearance(fontSize: fontSize, textColor: textColor)
            textView.columnWidth = parent.sourceColumnWidth

            let isEcho = lastSentText.map { text.isIdentical(to: $0) } == true && documentID == lastSentDocumentID
            let textChanged = (!isEcho || documentChanged)
                && !textView.hasMarkedText()
                && !editorText().isIdentical(to: text)
            if textChanged {
                suppressScrollUpdates = true
                sourceStyler.reset()
                textView.string = text
                textView.undoManager?.removeAllActions()
                applySelection(selectedRanges, to: textView)
            } else if documentChanged {
                suppressScrollUpdates = true
                applySelection(selectedRanges, to: textView)
            }

            applySourceStyle(fontSize: fontSize)
            applyEditorPreferences()
            if documentChanged || textChanged {
                scheduleViewportRestore()
            }
        }

        // MARK: Vista previa

        private func suspendForPreview(scrollView: NSScrollView, documentID: String) {
            guard let textView else { return }
            cancelPendingScrollPersistence()
            restoresFocusAfterPreview = textView.window?.firstResponder === textView
            if restoresFocusAfterPreview {
                textView.window?.makeFirstResponder(nil)
            }
            parent.editingTarget?.unregister(textView)
            parent.scrollCoordinator?.detachSource(scrollView: scrollView, textView: textView, documentID: documentID)
            isPreviewActive = true
            scrollView.isHidden = true
            parent.scrollCoordinator?.showPreviewAtReadingPosition()
        }

        /// Con una sola vista de texto, volver de Vista previa conserva el
        /// historial de deshacer y la selección.
        private func resumeFromPreview(
            scrollView: NSScrollView,
            documentID: String,
            text: String,
            selectedRanges: [NSRange],
            fontSize: CGFloat,
            textColor: NSColor
        ) {
            guard let textView else { return }
            let currentSelection = textView.selectedRanges.compactMap { $0.rangeValue }
            isPreviewActive = false
            scrollView.isHidden = false

            if !textView.hasMarkedText(), !editorText().isIdentical(to: text) {
                sourceStyler.reset()
                textView.string = text
                textView.undoManager?.removeAllActions()
            }
            if restoresFocusAfterPreview {
                textView.window?.makeFirstResponder(textView)
            }

            parent.editingTarget?.register(textView)
            parent.scrollCoordinator?.attachSource(scrollView: scrollView, textView: textView, documentID: documentID)

            applyAppearance(fontSize: fontSize, textColor: textColor)
            textView.columnWidth = parent.sourceColumnWidth
            applySourceStyle(fontSize: fontSize)
            applyEditorPreferences()

            suppressScrollUpdates = true
            applySelection(currentSelection.isEmpty ? selectedRanges : currentSelection, to: textView)
            scheduleViewportRestore()
        }

        // MARK: Estilado

        /// Resaltado Fuente, solo cuando el análisis coincide con el texto.
        func applySourceStyle(fontSize: CGFloat) {
            guard let highlight = parent.sourceHighlight,
                  let textView,
                  let storage = textView.textStorage else { return }
            if lastPaletteKey?.scheme != highlight.colorScheme || lastPaletteKey?.style != highlight.style {
                let palette = LitteraSourcePalette(style: highlight.style, scheme: highlight.colorScheme)
                textView.insertionPointColor = palette.insertionPoint
                textView.selectedTextAttributes = [.backgroundColor: palette.selection]
                lastPaletteKey = (highlight.colorScheme, highlight.style)
            }
            guard let document = highlight.document,
                  !textView.hasMarkedText(),
                  document.source.isIdentical(to: nativeText(of: textView)) else { return }
            sourceStyler.apply(
                runs: document.visualRuns,
                to: storage,
                scheme: highlight.colorScheme,
                style: highlight.style,
                fontSize: fontSize,
                lineSpacing: parent.lineSpacing.sourceSpacing
            )
        }

        /// Tipografía y color base.
        func applyAppearance(fontSize: CGFloat, textColor: NSColor) {
            guard let textView else { return }
            let font = LitteraSourceFont.regular(fontSize)

            if lastFontSize != fontSize {
                textView.font = font
                textView.typingAttributes[.font] = font
                lastFontSize = fontSize
            }

            if lastTextColor != textColor {
                textView.textColor = textColor
                textView.typingAttributes[.foregroundColor] = textColor
                lastTextColor = textColor
            }
        }

        /// Ortografía y máquina de escribir (Ajustes → Editor).
        func applyEditorPreferences() {
            guard let textView, let scrollView else { return }
            if textView.isContinuousSpellCheckingEnabled != parent.spellChecking {
                textView.isContinuousSpellCheckingEnabled = parent.spellChecking
            }
            let scheme = parent.sourceHighlight?.colorScheme ?? .light
            typewriterMode.configure(
                enabled: parent.typewriter,
                dimColor: NSColor(LitteraPalette(scheme).secondaryText),
                textView: textView,
                scrollView: scrollView
            )
        }

        // MARK: Scroll

        func observeScrollChanges() {
            guard observedScrollToken == nil, let scrollView else { return }
            observedScrollToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrollViewDidChangeBounds() }
            }
        }

        func stopObservingScrollChanges() {
            if let observedScrollToken {
                NotificationCenter.default.removeObserver(observedScrollToken)
                self.observedScrollToken = nil
            }
        }

        func scheduleViewportRestore() {
            guard !viewportRestoreScheduled else { return }
            viewportRestoreScheduled = true
            suppressScrollUpdates = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewportRestoreScheduled = false
                guard let scrollView = self.scrollView, let textView = self.textView else {
                    self.suppressScrollUpdates = false
                    return
                }
                scrollView.layoutSubtreeIfNeeded()
                textView.layoutSubtreeIfNeeded()
                self.applySelection(self.parent.selectedRanges, to: textView)
                self.isApplyingScroll = true
                let restored = self.parent.scrollCoordinator?.restoreSource(
                    scrollView: scrollView,
                    documentID: self.currentDocumentID ?? self.parent.documentID
                ) ?? false
                if !restored {
                    self.applyScrollOffset(self.parent.scrollOffset)
                }
                self.isApplyingScroll = false
                self.suppressScrollUpdates = false
                self.parent.scrollCoordinator?.sourceDidRestore(scrollView: scrollView)
            }
        }

        private func scrollViewDidChangeBounds() {
            // Oculto en Vista previa, SwiftUI lo ensancha y el texto refluye:
            // eso no es un desplazamiento. Registrarlo maquetaba el documento
            // entero y pisaba la posición de lectura recién guardada.
            guard !isApplyingScroll, !isPreviewActive else { return }
            parent.scrollCoordinator?.sourceDidScroll()
            guard !suppressScrollUpdates else { return }
            schedulePersistScrollOffset()
        }

        private func schedulePersistScrollOffset() {
            pendingScrollPersistence?.cancel()
            let documentID = currentDocumentID
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.currentDocumentID == documentID,
                      !self.suppressScrollUpdates else { return }
                let offset = self.currentScrollOffset
                if let scrollView = self.scrollView, let textView = self.textView, let documentID {
                    self.parent.scrollCoordinator?.recordSourcePosition(
                        scrollView: scrollView,
                        textView: textView,
                        documentID: documentID
                    )
                }
                if !self.approximatelyEqual(self.parent.scrollOffset, offset) {
                    self.parent.scrollOffset = offset
                }
            }
            pendingScrollPersistence = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }

        func cancelPendingScrollPersistence() {
            pendingScrollPersistence?.cancel()
            pendingScrollPersistence = nil
        }

        private var currentScrollOffset: CGPoint {
            scrollView?.contentView.bounds.origin ?? .zero
        }

        private func applyScrollOffset(_ offset: CGPoint) {
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            let maxX = max(0, (scrollView.documentView?.bounds.width ?? 0) - clipView.bounds.width)
            let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clipView.bounds.height)
            let target = CGPoint(
                x: min(max(0, offset.x), maxX),
                y: min(max(0, offset.y), maxY)
            )

            guard !approximatelyEqual(clipView.bounds.origin, target) else { return }
            isApplyingScroll = true
            clipView.scroll(to: target)
            scrollView.reflectScrolledClipView(clipView)
            isApplyingScroll = false
        }

        // MARK: Selección

        private func applySelection(_ ranges: [NSRange], to textView: NSTextView) {
            let length = (textView.string as NSString).length
            let validRanges = ranges.compactMap { range -> NSValue? in
                let location = min(max(0, range.location), length)
                let maxLength = max(0, length - location)
                let safeRange = NSRange(location: location, length: min(range.length, maxLength))
                return NSValue(range: safeRange)
            }

            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }

        // MARK: Delegado de NSTextView

        func textDidChange(_ notification: Notification) {
            guard let sender = notification.object as? NSTextView,
                  sender === textView,
                  !sender.hasMarkedText() else { return }
            let newText = editorText()
            guard !newText.isIdentical(to: parent.text) else { return }
            lastSentText = newText
            lastSentDocumentID = currentDocumentID
            parent.text = newText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let sender = notification.object as? NSTextView,
                  sender === textView else { return }
            if typewriterMode.isEnabled, let scrollView {
                typewriterMode.update(textView: sender, scrollView: scrollView)
            }
            let ranges = sender.selectedRanges.compactMap { value -> NSRange? in
                value.rangeValue
            }
            guard ranges != parent.selectedRanges else { return }
            let documentID = currentDocumentID
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentDocumentID == documentID,
                      self.parent.selectedRanges != ranges else { return }
                self.parent.selectedRanges = ranges
            }
        }

        private func approximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
            abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
        }
    }
}
