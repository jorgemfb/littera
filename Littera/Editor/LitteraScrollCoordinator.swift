import AppKit
import SwiftUI

/// Posición de lectura de un documento, independiente del modo.
///
/// Se expresa en términos del Markdown, no de píxeles: el bloque superior del
/// AST que ocupa el borde superior del panel y la fracción recorrida hasta el
/// bloque siguiente. Fuente, Dividido y Vista previa la traducen a su propia
/// geometría, así que el mismo contenido queda arriba en los tres.
struct LitteraDocumentViewportPosition: Equatable {
    /// `nil` representa el tramo anterior al primer bloque (inicio del documento).
    var blockID: String?
    var fraction: CGFloat
}

/// Coordina el desplazamiento de los paneles Fuente y Vista previa.
///
/// - Conserva una única posición de lectura por documento y la reaplica al
///   cambiar de modo o de documento.
/// - En Dividido sincroniza ambos paneles directamente sobre sus `NSClipView`.
///
/// Un evento de scroll nunca escribe estado de SwiftUI, nunca analiza Markdown
/// y nunca recorre el texto: solo consulta tablas precalculadas por versión
/// del documento y geometría del panel (búsqueda binaria).
final class LitteraScrollCoordinator {
    /// Inicio de un bloque superior en la coordenada Y del documento de un panel.
    private struct Segment {
        let blockID: String?
        /// Orden entre los bloques superiores; -1 para el inicio del documento.
        let order: Int
        let y: CGFloat
    }

    private struct Anchor {
        let source: CGFloat
        let preview: CGFloat
    }

    private struct SourceLayoutSignature: Equatable {
        let document: ObjectIdentifier
        let width: CGFloat
        let height: CGFloat
    }

    private struct AnchorSignature: Equatable {
        let source: SourceLayoutSignature
        let previewHeight: CGFloat
        let previewOffsetsVersion: Int
    }

    private weak var store: LitteraDocumentStore?
    private var activeDocumentID: String?
    private var isSplit = false

    /// Posición de lectura por documento: la única fuente de verdad del
    /// desplazamiento entre modos. No es estado de SwiftUI.
    private var positions: [String: LitteraDocumentViewportPosition] = [:]

    // Panel Fuente.
    private weak var sourceScrollView: NSScrollView?
    private weak var sourceTextView: NSTextView?
    private var sourceDocumentID: String?
    private var sourceRestored = false
    private var sourceSegmentsCache: (signature: SourceLayoutSignature, segments: [Segment])?

    // Panel Vista previa.
    private weak var previewScrollView: NSScrollView?
    private var previewObserver: NSObjectProtocol?
    private var previewFrameObserver: NSObjectProtocol?
    private var sourceFrameObserver: NSObjectProtocol?
    private var alignmentScheduled = false
    /// Al cambiar la anchura (redimensionar la ventana) la alineación exige el
    /// layout completo del editor: se hace cuando la anchura se asienta (H8).
    private var observedWidths: [ObjectIdentifier: CGFloat] = [:]
    private var settledAlignment: DispatchWorkItem?
    static let widthSettleDelay: TimeInterval = 0.2
    private var previewDocumentID: String?
    private var previewRestored = false
    /// La Vista previa puede estar construida pero oculta: entonces no restaura
    /// ni registra posiciones.
    private var previewVisible = false
    /// SwiftUI puede entregar las posiciones de bloque antes de que el panel
    /// se registre y no las reenvía si no cambian: se guardan por documento.
    private var blockOffsetsByDocument: [String: [String: CGFloat]] = [:]
    private var previewOffsetsVersion = 0
    private var previewSegmentsCache: (version: Int, documentID: String, segments: [Segment])?

    private var anchorsCache: (signature: AnchorSignature, anchors: [Anchor])?
    private var isApplyingScroll = false

    deinit {
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
        }
    }

    // MARK: - Configuración

    func update(store: LitteraDocumentStore, activeDocumentID: String, isSplit: Bool, previewVisible: Bool) {
        self.store = store
        let modeChanged = self.isSplit != isSplit
        self.activeDocumentID = activeDocumentID
        self.isSplit = isSplit
        positions = positions.filter { id, _ in store.derivedDocuments[id] != nil }
        if self.previewVisible != previewVisible {
            self.previewVisible = previewVisible
            previewRestored = false
        }

        // El documento puede haberse analizado después de que el panel se
        // registrara: reintentar lo pendiente.
        applyPendingPreviewRestore()
        if modeChanged || bothPanelsReady { alignPreviewToSource() }
    }

    // MARK: - Posiciones

    /// Posición del documento: la de esta sesión o, si no la hay, la guardada
    /// para su archivo en una sesión anterior.
    private func readingPosition(for documentID: String) -> LitteraDocumentViewportPosition? {
        if let position = positions[documentID] { return position }
        guard let path = filePath(for: documentID),
              let stored = Self.storedPositions()[path],
              let fraction = stored["fraction"] as? Double else { return nil }
        let block = stored["block"] as? String
        return LitteraDocumentViewportPosition(blockID: block?.isEmpty == false ? block : nil, fraction: fraction)
    }

    private func setPosition(for documentID: String, _ position: LitteraDocumentViewportPosition) {
        guard positions[documentID] != position else { return }
        positions[documentID] = position
        schedulePersistence()
    }

    private func filePath(for documentID: String) -> String? {
        store?.documents.first(where: { $0.id == documentID })?.fileURL?.standardizedFileURL.path
    }

    // Persistencia entre sesiones, por ruta de archivo. Se escribe con retardo
    // para no tocar el disco en cada evento de desplazamiento.
    private static let storageKey = "littera.readingPositions"
    private static let storageLimit = 200
    private var pendingPersistence: DispatchWorkItem?

    private static func storedPositions() -> [String: [String: Any]] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: [String: Any]] ?? [:]
    }

    private func schedulePersistence() {
        pendingPersistence?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistPositions() }
        pendingPersistence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func persistPositions() {
        var stored = Self.storedPositions()
        let now = Date().timeIntervalSince1970
        for (documentID, position) in positions {
            guard let path = filePath(for: documentID) else { continue }
            stored[path] = ["block": position.blockID ?? "", "fraction": Double(position.fraction), "updated": now]
        }
        if stored.count > Self.storageLimit {
            let oldest = stored.sorted { ($0.value["updated"] as? Double ?? 0) < ($1.value["updated"] as? Double ?? 0) }
            for (path, _) in oldest.prefix(stored.count - Self.storageLimit) {
                stored.removeValue(forKey: path)
            }
        }
        UserDefaults.standard.set(stored, forKey: Self.storageKey)
    }

    // MARK: - Panel Fuente

    func attachSource(scrollView: NSScrollView, textView: NSTextView, documentID: String) {
        sourceScrollView = scrollView
        sourceTextView = textView
        sourceDocumentID = documentID
        sourceRestored = false
        sourceSegmentsCache = nil
        anchorsCache = nil
        replaceObserver(&sourceFrameObserver, for: textView)
    }

    /// Al entrar en Dividido el texto se recoloca después del primer alineado:
    /// sin este aviso, los paneles quedarían desfasados hasta el siguiente scroll.
    private func replaceObserver(_ observer: inout NSObjectProtocol?, for view: NSView?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let view else { return }
        view.postsFrameChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: view,
            queue: nil
        ) { [weak self, weak view] _ in
            MainActor.assumeIsolated { self?.frameDidChange(view) }
        }
    }

    private func frameDidChange(_ view: NSView?) {
        guard let view else { return }
        let key = ObjectIdentifier(view)
        let width = view.frame.width
        let previous = observedWidths[key]
        observedWidths[key] = width
        guard let previous, abs(previous - width) > 0.5 else {
            scheduleAlignment()
            return
        }
        guard isSplit else { return }
        settledAlignment?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.settledAlignment = nil
            self?.alignPreviewToSource()
        }
        settledAlignment = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.widthSettleDelay, execute: work)
    }

    private func scheduleAlignment() {
        guard isSplit, !alignmentScheduled else { return }
        alignmentScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.alignmentScheduled = false
            self?.alignPreviewToSource()
        }
    }

    /// Lo llama el editor Fuente tras su primer layout. Devuelve `false` si no
    /// hay posición semántica que aplicar (el editor usa entonces su respaldo).
    func restoreSource(scrollView: NSScrollView, documentID: String) -> Bool {
        guard scrollView === sourceScrollView,
              let position = readingPosition(for: documentID),
              let segments = sourceSegments(),
              let targetTop = top(for: position, documentID: documentID, in: segments, end: documentHeight(of: scrollView)) else {
            return false
        }
        apply(targetTop, to: scrollView)
        return true
    }

    func sourceDidRestore(scrollView: NSScrollView) {
        guard scrollView === sourceScrollView else { return }
        sourceRestored = true
        if isSplit { alignPreviewToSource() }
    }

    /// Llamado de forma síncrona por el editor Fuente en cada cambio de bounds.
    func sourceDidScroll() {
        guard sourceRestored, !isApplyingScroll else { return }
        if isSplit, previewRestored {
            alignPreviewToSource()
        }
        // En Fuente sola, la posición se registra al salir del panel: calcularla
        // exige el layout completo y no debe hacerse en cada evento.
    }

    /// SwiftUI puede crear el editor nuevo antes de desmontar el anterior, así
    /// que la posición se calcula con la vista que se desmonta, no con la actual.
    func detachSource(scrollView: NSScrollView, textView: NSTextView, documentID: String) {
        let isCurrent = sourceScrollView === scrollView
        if !isCurrent || sourceRestored {
            recordSourcePosition(scrollView: scrollView, textView: textView, documentID: documentID)
        }
        guard isCurrent else { return }
        replaceObserver(&sourceFrameObserver, for: nil)
        sourceScrollView = nil
        sourceTextView = nil
        sourceDocumentID = nil
        sourceRestored = false
        sourceSegmentsCache = nil
        anchorsCache = nil
    }

    /// Registra la posición del editor Fuente. Lo llama el editor cuando el
    /// desplazamiento se detiene y al desmontarse; nunca en cada evento.
    func recordSourcePosition(scrollView: NSScrollView, textView: NSTextView, documentID: String) {
        if scrollView === sourceScrollView, !sourceRestored { return }
        guard let segments = sourceSegments(textView: textView, scrollView: scrollView, documentID: documentID) else {
            return
        }
        setPosition(for: documentID, Self.position(
            at: viewportTop(of: scrollView),
            in: segments,
            end: documentHeight(of: scrollView)
        ))
    }

    // MARK: - Panel Vista previa

    func attachPreview(scrollView: NSScrollView, documentID: String) {
        guard previewScrollView !== scrollView || previewDocumentID != documentID else { return }
        if let previewObserver {
            NotificationCenter.default.removeObserver(previewObserver)
        }
        previewScrollView = scrollView
        previewDocumentID = documentID
        previewRestored = false
        previewSegmentsCache = nil
        anchorsCache = nil

        scrollView.contentView.postsBoundsChangedNotifications = true
        previewObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.previewDidScroll() }
        }
        replaceObserver(&previewFrameObserver, for: scrollView.documentView)
        applyPendingPreviewRestore()
    }

    /// Posiciones de los bloques en coordenadas del contenido. Solo cambian con
    /// el layout, no durante el desplazamiento.
    func updatePreviewBlockOffsets(_ offsets: [String: CGFloat], documentID: String) {
        guard blockOffsetsByDocument[documentID] != offsets else { return }
        blockOffsetsByDocument[documentID] = offsets
        previewOffsetsVersion += 1
        guard documentID == previewDocumentID else { return }

        if previewRestored {
            // El contenido ha cambiado de altura (edición, anchura): en Dividido
            // la Fuente manda; en Vista previa se conserva la posición semántica.
            if isSplit, sourceRestored {
                alignPreviewToSource()
            } else if let position = readingPosition(for: documentID) {
                applyPosition(position, toPreviewOf: documentID)
            }
        } else {
            applyPendingPreviewRestore()
        }
    }

    /// Lleva la Vista previa hasta un bloque (entrada del índice, D53). Se
    /// comporta como un desplazamiento del usuario: en Dividido sigue la Fuente.
    func scrollPreview(toBlockID blockID: String) {
        guard let previewScrollView, let previewDocumentID,
              let y = blockOffsetsByDocument[previewDocumentID]?[blockID] else { return }
        setViewportTop(max(0, y - LitteraDesign.Editor.previewTopPadding / 2), of: previewScrollView)
    }

    /// El editor acaba de registrar su posición al pasar a Vista previa.
    func showPreviewAtReadingPosition() {
        previewVisible = true
        previewRestored = false
        applyPendingPreviewRestore()
    }

    private func applyPendingPreviewRestore() {
        guard previewVisible, !previewRestored,
              let previewDocumentID,
              let previewScrollView,
              let segments = previewSegments(), segments.count > 1 else { return }
        if let position = readingPosition(for: previewDocumentID),
           let targetTop = top(for: position, documentID: previewDocumentID, in: segments, end: documentHeight(of: previewScrollView)) {
            apply(targetTop, to: previewScrollView)
        } else {
            apply(0, to: previewScrollView)
        }
        previewRestored = true
        if isSplit { alignPreviewToSource() }
    }

    private func applyPosition(_ position: LitteraDocumentViewportPosition, toPreviewOf documentID: String) {
        guard let previewScrollView,
              let segments = previewSegments(),
              let targetTop = top(for: position, documentID: documentID, in: segments, end: documentHeight(of: previewScrollView)) else { return }
        apply(targetTop, to: previewScrollView)
    }

    private func previewDidScroll() {
        // Al desmontarse, el panel puede cambiar de bounds: no es un desplazamiento.
        guard previewRestored, let previewScrollView, previewScrollView.window != nil,
              let previewDocumentID else { return }
        // Registrar en la Vista previa es barato (búsqueda binaria), así que se
        // hace siempre, también cuando el movimiento lo provoca la sincronización.
        if let segments = previewSegments() {
            setPosition(for: previewDocumentID, Self.position(
                at: viewportTop(of: previewScrollView),
                in: segments,
                end: documentHeight(of: previewScrollView)
            ))
        }

        guard isSplit, sourceRestored, !isApplyingScroll,
              let sourceScrollView,
              let anchors = currentAnchors() else { return }
        let target = Self.interpolate(
            viewportTop(of: previewScrollView),
            in: anchors,
            from: \.preview,
            to: \.source
        )
        apply(target, to: sourceScrollView)
    }

    // MARK: - Dividido

    private var bothPanelsReady: Bool {
        isSplit && sourceRestored && previewRestored
    }

    private func alignPreviewToSource() {
        guard bothPanelsReady, !isApplyingScroll,
              let sourceScrollView,
              let previewScrollView,
              let anchors = currentAnchors() else { return }
        let target = Self.interpolate(
            viewportTop(of: sourceScrollView),
            in: anchors,
            from: \.source,
            to: \.preview
        )
        apply(target, to: previewScrollView)
        // `apply` silencia la notificación: registrar aquí la posición resultante.
        if let previewDocumentID, let segments = previewSegments() {
            setPosition(for: previewDocumentID, Self.position(
                at: viewportTop(of: previewScrollView),
                in: segments,
                end: documentHeight(of: previewScrollView)
            ))
        }
    }

    private func apply(_ top: CGFloat, to scrollView: NSScrollView) {
        isApplyingScroll = true
        setViewportTop(top, of: scrollView)
        isApplyingScroll = false
    }

    /// Pares (Fuente, Vista previa) por bloque común, más inicio y final.
    private func currentAnchors() -> [Anchor]? {
        guard let sourceScrollView,
              let previewScrollView,
              sourceDocumentID == previewDocumentID,
              let sourceSignature = sourceLayoutSignature() else { return nil }
        let signature = AnchorSignature(
            source: sourceSignature,
            previewHeight: documentHeight(of: previewScrollView),
            previewOffsetsVersion: previewOffsetsVersion
        )
        if let anchorsCache, anchorsCache.signature == signature { return anchorsCache.anchors }

        guard let sourceSegments = sourceSegments(),
              let previewSegments = previewSegments() else { return nil }
        let sourceMax = maxViewportTop(of: sourceScrollView)
        let previewMax = maxViewportTop(of: previewScrollView)
        let previewByID = Dictionary(
            previewSegments.compactMap { segment in segment.blockID.map { ($0, segment.y) } },
            uniquingKeysWith: { first, _ in first }
        )

        var anchors = [Anchor(source: 0, preview: 0)]
        for segment in sourceSegments {
            guard let id = segment.blockID,
                  let previewY = previewByID[id],
                  segment.y < sourceMax, previewY < previewMax,
                  let last = anchors.last,
                  segment.y > last.source, previewY > last.preview else { continue }
            anchors.append(Anchor(source: segment.y, preview: previewY))
        }
        // El final de ambos documentos siempre coincide.
        if sourceMax > 0, previewMax > 0 {
            anchors.append(Anchor(source: sourceMax, preview: previewMax))
        }
        anchorsCache = (signature, anchors)
        return anchors
    }

    // MARK: - Tablas de bloques

    private func sourceLayoutSignature() -> SourceLayoutSignature? {
        guard let sourceDocumentID, let sourceScrollView, let sourceTextView else { return nil }
        return sourceLayoutSignature(textView: sourceTextView, scrollView: sourceScrollView, documentID: sourceDocumentID)
    }

    private func sourceLayoutSignature(
        textView: NSTextView,
        scrollView: NSScrollView,
        documentID: String
    ) -> SourceLayoutSignature? {
        guard let document = store?.derivedDocuments[documentID] else { return nil }
        return SourceLayoutSignature(
            document: ObjectIdentifier(document),
            width: textView.frame.width,
            height: documentHeight(of: scrollView)
        )
    }

    private func sourceSegments() -> [Segment]? {
        guard let sourceDocumentID, let sourceScrollView, let sourceTextView else { return nil }
        return sourceSegments(textView: sourceTextView, scrollView: sourceScrollView, documentID: sourceDocumentID)
    }

    /// Inicio de cada bloque superior en un editor Fuente. Exige el layout
    /// completo de TextKit: se calcula una vez por versión y anchura.
    private func sourceSegments(
        textView: NSTextView,
        scrollView: NSScrollView,
        documentID: String
    ) -> [Segment]? {
        guard let signature = sourceLayoutSignature(textView: textView, scrollView: scrollView, documentID: documentID),
              let document = store?.derivedDocuments[documentID],
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let isCurrent = textView === sourceTextView
        if isCurrent, let sourceSegmentsCache, sourceSegmentsCache.signature == signature {
            return sourceSegmentsCache.segments
        }
        // Si el texto del editor aún no coincide con la versión analizada, las
        // posiciones no serían fiables.
        // Copia nativa: comparar la cadena puenteada de `NSTextView` era muy
        // lento con documentos grandes (LIT-004).
        var current = textView.string
        current.makeContiguousUTF8()
        guard current == document.source else { return nil }

        layoutManager.ensureLayout(for: textContainer)
        let originY = textView.textContainerOrigin.y
        let textLength = (textView.string as NSString).length

        var segments = [Segment(blockID: nil, order: -1, y: 0)]
        for (order, block) in document.rendered.blocks.enumerated() {
            guard let range = block.sourceRange, range.utf16Range.location < textLength else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.utf16Range.location)
            let y = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + originY
            guard let last = segments.last, y > last.y else { continue }
            segments.append(Segment(blockID: block.id, order: order, y: y))
        }
        if isCurrent {
            sourceSegmentsCache = (signature, segments)
        }
        return segments
    }

    /// Inicio de cada bloque superior en la Vista previa, en orden del documento.
    private func previewSegments() -> [Segment]? {
        guard let previewDocumentID,
              let document = store?.derivedDocuments[previewDocumentID],
              let offsets = blockOffsetsByDocument[previewDocumentID],
              !offsets.isEmpty else { return nil }
        if let previewSegmentsCache,
           previewSegmentsCache.version == previewOffsetsVersion,
           previewSegmentsCache.documentID == previewDocumentID {
            return previewSegmentsCache.segments
        }
        var segments = [Segment(blockID: nil, order: -1, y: 0)]
        for (order, block) in document.rendered.blocks.enumerated() {
            guard let y = offsets[block.id], let last = segments.last, y > last.y else { continue }
            segments.append(Segment(blockID: block.id, order: order, y: y))
        }
        previewSegmentsCache = (previewOffsetsVersion, previewDocumentID, segments)
        return segments
    }

    // MARK: - Conversión posición ↔ coordenada

    private static func position(
        at top: CGFloat,
        in segments: [Segment],
        end: CGFloat
    ) -> LitteraDocumentViewportPosition {
        // Último segmento cuyo inicio es <= top.
        var low = 0
        var high = segments.count
        while low < high {
            let mid = (low + high) / 2
            if segments[mid].y <= top {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let index = max(0, low - 1)
        let start = segments[index].y
        let next = index + 1 < segments.count ? segments[index + 1].y : max(end, start)
        let fraction = next > start ? min(max((top - start) / (next - start), 0), 1) : 0
        return LitteraDocumentViewportPosition(blockID: segments[index].blockID, fraction: fraction)
    }

    /// Coordenada del panel para una posición. Si el bloque no tiene tramo
    /// propio en este panel se usa el bloque anterior más cercano (fracción 0).
    private func top(
        for position: LitteraDocumentViewportPosition,
        documentID: String,
        in segments: [Segment],
        end: CGFloat
    ) -> CGFloat? {
        let index: Int
        var fraction = position.fraction
        if let exact = segments.firstIndex(where: { $0.blockID == position.blockID }) {
            index = exact
        } else if let blockID = position.blockID,
                  let order = store?.derivedDocuments[documentID]?.topLevelIndex(ofBlockID: blockID),
                  let preceding = segments.lastIndex(where: { $0.order <= order }) {
            index = preceding
            fraction = 0
        } else {
            return nil
        }
        let start = segments[index].y
        let next = index + 1 < segments.count ? segments[index + 1].y : max(end, start)
        return start + fraction * (next - start)
    }

    private static func interpolate(
        _ value: CGFloat,
        in anchors: [Anchor],
        from input: KeyPath<Anchor, CGFloat>,
        to output: KeyPath<Anchor, CGFloat>
    ) -> CGFloat {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if value <= first[keyPath: input] { return first[keyPath: output] }
        if value >= last[keyPath: input] { return last[keyPath: output] }

        var low = 0
        var high = anchors.count
        while low < high {
            let mid = (low + high) / 2
            if anchors[mid][keyPath: input] <= value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upper = anchors[low]
        let lower = anchors[low - 1]
        let span = upper[keyPath: input] - lower[keyPath: input]
        guard span > 0 else { return lower[keyPath: output] }
        let fraction = (value - lower[keyPath: input]) / span
        return lower[keyPath: output] + fraction * (upper[keyPath: output] - lower[keyPath: output])
    }

    // MARK: - Geometría de NSScrollView

    /// Coordenada Y del documento visible en el borde superior del panel.
    private func viewportTop(of scrollView: NSScrollView) -> CGFloat {
        scrollView.contentView.bounds.minY + scrollView.contentInsets.top
    }

    private func documentHeight(of scrollView: NSScrollView) -> CGFloat {
        scrollView.documentView?.frame.height ?? 0
    }

    private func maxViewportTop(of scrollView: NSScrollView) -> CGFloat {
        let insets = scrollView.contentInsets
        let visibleHeight = scrollView.contentView.bounds.height - insets.top - insets.bottom
        return max(0, documentHeight(of: scrollView) - visibleHeight)
    }

    private func setViewportTop(_ top: CGFloat, of scrollView: NSScrollView) {
        let clipView = scrollView.contentView
        let clamped = min(max(0, top), maxViewportTop(of: scrollView))
        let target = NSPoint(x: clipView.bounds.minX, y: clamped - scrollView.contentInsets.top)
        guard abs(clipView.bounds.minY - target.y) >= 0.5 else { return }
        clipView.scroll(to: target)
        scrollView.reflectScrolledClipView(clipView)
    }
}

/// Localiza el `NSScrollView` nativo que respalda un `ScrollView` de SwiftUI.
struct LitteraEnclosingScrollViewReader: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ResolverView {
        let view = ResolverView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ view: ResolverView, context: Context) {
        view.onResolve = onResolve
        view.resolve()
    }

    final class ResolverView: NSView {
        var onResolve: ((NSScrollView) -> Void)?
        private weak var resolved: NSScrollView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolve()
        }

        func resolve() {
            guard let scrollView = enclosingScrollView, scrollView !== resolved else { return }
            resolved = scrollView
            onResolve?(scrollView)
        }
    }
}
