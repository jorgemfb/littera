import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// Vista de composición, sin métricas ni colores propios. Las paletas y el
// renderizado de demostración siguen siendo componentes independientes.
struct LitteraEditorView: View {
    @ObservedObject private var documentStore: LitteraDocumentStore
    private let applicationDelegate: LitteraApplicationDelegate
    /// Sin cromo propio (barra de estado y toolbar nativo). La app usa siempre
    /// `false`; las pruebas lo activan para alojar el editor en una ventana
    /// propia sin barra de herramientas.
    private let chromeless: Bool
    /// Modo con el que arranca esta instancia; sin él, «Vista inicial».
    private let startMode: LitteraEditorMode?

    init(
        documentStore: LitteraDocumentStore,
        applicationDelegate: LitteraApplicationDelegate,
        chromeless: Bool = false,
        startMode: LitteraEditorMode? = nil
    ) {
        self.documentStore = documentStore
        self.applicationDelegate = applicationDelegate
        self.chromeless = chromeless
        self.startMode = startMode
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(LitteraPreferenceKeys.initialMode)
    private var initialMode = LitteraPreferenceDefaults.initialMode
    @AppStorage(LitteraPreferenceKeys.writingWidth)
    private var storedWritingWidth = LitteraPreferenceDefaults.writingWidth
    @AppStorage(LitteraPreferenceKeys.sourceFontSize)
    private var sourceFontSize = LitteraPreferenceDefaults.sourceFontSize
    @AppStorage(LitteraPreferenceKeys.sourceHighlightStyle)
    private var storedSourceHighlightStyle = LitteraPreferenceDefaults.sourceHighlightStyle
    @AppStorage(LitteraPreferenceKeys.lineSpacing)
    private var storedLineSpacing = LitteraPreferenceDefaults.lineSpacing
    @AppStorage(LitteraPreferenceKeys.typewriterMode)
    private var typewriterMode = LitteraPreferenceDefaults.typewriterMode
    @AppStorage(LitteraPreferenceKeys.showStatusBar)
    private var showStatusBar = LitteraPreferenceDefaults.showStatusBar
    @AppStorage(LitteraPreferenceKeys.spellChecking)
    private var spellChecking = LitteraPreferenceDefaults.spellChecking

    @State private var mode: LitteraEditorMode = .source
    @State private var writingWidth: LitteraWritingWidth = .medium
    @State private var showStats = false
    @State private var isPropertiesPresented = false
    @State private var sourceEditorStates: [String: SourceEditorState] = [:]
    // Coordinador AppKit del desplazamiento y de la posición de lectura de
    // cada documento en los cuatro modos. Es una referencia estable: sus
    // cambios internos nunca invalidan esta vista.
    @State private var scrollCoordinator = LitteraScrollCoordinator()
    /// Editor activo para los comandos de formato de la paleta.
    @State private var editingTarget = LitteraEditingTarget()
    @State private var isSearchPresented = false
    /// Versión que muestra la Vista previa de Dividido: se actualiza 250 ms
    /// después de la última versión analizada, no con cada pulsación.
    @State private var splitPreview: (documentID: String, document: LitteraMarkdownDerivedDocument)?
    @State private var pendingSplitPreview: DispatchWorkItem?
    /// Documento y anchura para los que está construida cada Vista previa. Si
    /// cambia la anchura, la oculta se descarta y se reconstruye por tandas:
    /// remaquetarla bloqueaba el hilo principal más de un segundo.
    @State private var preparedFullPreview: PreparedPreview?
    /// La de Dividido se construye después, para no competir con la primera.
    @State private var preparedSplitPreview: PreparedPreview?
    @State private var fullPreviewSlot = LitteraPreviewSlot()
    @State private var splitPreviewSlot = LitteraPreviewSlot()
    /// Último tamaño real del área del editor.
    @State private var lastEditorSize: CGSize = .zero
    @State private var searchQuery = ""
    @State private var isReplacing = false
    @State private var replacement = ""

    private struct PreparedPreview: Equatable {
        let documentID: String
        let width: CGFloat
    }

    /// Por encima de este tamaño no se mantienen Vistas previas ocultas: su
    /// memoria crece con el documento y se construyen al mostrarse.
    private static let maxPreparedDocumentBytes = 200_000

    private struct SourceEditorState: Equatable {
        var selectedRanges: [NSRange] = []
        var scrollOffset: CGPoint = .zero
    }

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    /// Cambia solo cuando cambia el documento activo, su versión analizada o
    /// el modo; nunca durante el desplazamiento.
    private var scrollSynchronizationKey: String {
        let documentID = documentStore.activeDocumentID
        let revision = documentStore.derivedDocuments[documentID]?.revision ?? 0
        return "\(documentID)#\(revision)#\(mode.rawValue)"
    }

    private var activeDocument: LitteraDocumentSession? {
        documentStore.activeDocument
    }

    private var wordCount: Int {
        documentStore.derivedDocuments[documentStore.activeDocumentID]?.wordCount ?? 0
    }

    private var sourceText: Binding<String> {
        Binding(
            get: { activeDocument?.markdown ?? "" },
            set: { newText in
                documentStore.updateMarkdown(for: documentStore.activeDocumentID, text: newText)
            }
        )
    }

    /// Contenido del editor sin cromo de ventana.
    private var editorCore: some View {
        ZStack {
            colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                editorContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !chromeless, showStatusBar {
                    LitteraStatusBarView(wordCount: wordCount, mode: mode, status: LitteraDocumentStatus(activeDocument))
                }
            }

        }
        // Sin cromo no existe la barra de título donde colgaba el popover de
        // búsqueda. Un .popover anclado a una vista de 1x1 no se presenta de
        // forma fiable, así que el panel se dibuja como capa flotante.
        .overlay(alignment: .topTrailing) {
            if chromeless, isSearchPresented {
                LitteraSearchPopover(
                    searchQuery: $searchQuery,
                    isReplacing: $isReplacing,
                    replacement: $replacement,
                    search: { direction in editingTarget.search(searchQuery, direction: direction) },
                    endSearch: { editingTarget.focus() },
                    replaceCurrent: { editingTarget.replaceCurrent(searchQuery, with: replacement) },
                    replaceAll: { editingTarget.replaceAll(searchQuery, with: replacement) }
                )
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colors.chrome)
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(colors.line, lineWidth: 0.7)
                }
                .padding(.top, 10)
                .padding(.trailing, 16)
                .onExitCommand { isSearchPresented = false }
            }
        }
        // Cambiar a Vista previa cierra la búsqueda (no hay dónde buscar).
        .onChange(of: mode) { oldMode, newMode in
            if newMode == .preview { isSearchPresented = false }
            if oldMode == .preview || newMode == .preview { preparedFullPreview = currentPreparation }
            if oldMode == .split || newMode == .split { preparedSplitPreview = currentPreparation }
            if newMode == .split, let latest = documentStore.derivedDocuments[documentStore.activeDocumentID] {
                pendingSplitPreview?.cancel()
                splitPreview = (documentStore.activeDocumentID, latest)
            }
            NotificationCenter.default.post(name: .litteraModeDidChange, object: newMode.rawValue)
        }
    }

    /// En modo sin cromo NO se declara ningún toolbar de ventana. Declararlo,
    /// aunque sea oculto, hace que macOS reserve el área y esconda los
    /// semáforos; así la ventana se comporta como la de la demo (fase 7).
    @ViewBuilder
    private var chromeContent: some View {
        if chromeless {
            editorCore
        } else {
            editorCore
                .toolbar {
                    if #available(macOS 26.0, *) {
                        ToolbarItem(placement: .principal) { documentTitle }
                            .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .primaryAction) { titlebarActions }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .principal) { documentTitle }
                        ToolbarItem(placement: .primaryAction) { titlebarActions }
                    }
                }
                .toolbarBackground(colors.chrome, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        }
    }

    var body: some View {
        chromeContent
        .onAppear {
            editingTarget.onFindRequest = handleFindRequest
            // El modo inicial se aplica a cada ventana nueva.
            mode = startMode ?? LitteraEditorMode(rawValue: initialMode) ?? .source
            NotificationCenter.default.post(name: .litteraModeDidChange, object: mode.rawValue)
            writingWidth = LitteraWritingWidth(rawValue: storedWritingWidth) ?? .medium
        }
        .onChange(of: storedWritingWidth) { _, newValue in
            // Reflejar los ajustes abiertos en otra ventana, sin reconstruir el editor.
            guard let value = LitteraWritingWidth(rawValue: newValue), value != writingWidth else { return }
            writingWidth = value
        }
        .onChange(of: writingWidth) { _, newValue in
            guard storedWritingWidth != newValue.rawValue else { return }
            storedWritingWidth = newValue.rawValue
        }
        // Construir la Vista previa bloquea el hilo principal: se hace una vez por
        // documento, cuando lleva un momento sin editarse.
        .task(id: currentPreparation) {
            let preparation = currentPreparation
            let documentID = preparation.documentID
            guard preparation.width > 1,
                  (activeDocument?.markdown.utf8.count ?? 0) <= Self.maxPreparedDocumentBytes else { return }
            // Si el documento ya tiene Vista previa preparada, actualizar la anchura
            // de inmediato para que el NSHostingView no salga del árbol de vistas
            // durante los 300 ms de estabilización del reinicio de la tarea.
            if preparedFullPreview?.documentID == documentID { preparedFullPreview = preparation }
            if preparedSplitPreview?.documentID == documentID { preparedSplitPreview = preparation }
            var revision = documentStore.derivedDocuments[documentID]?.revision
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                let current = documentStore.derivedDocuments[documentID]?.revision
                if !Task.isCancelled, current != nil, current == revision {
                    preparedFullPreview = preparation
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { preparedSplitPreview = preparation }
                    return
                }
                revision = current
            }
        }
        .onChange(of: scrollSynchronizationKey, initial: true) { _, _ in
            scheduleSplitPreviewUpdate()
            scrollCoordinator.update(
                store: documentStore,
                activeDocumentID: documentStore.activeDocumentID,
                isSplit: mode == .split,
                previewVisible: showsPreview
            )
        }
        // Comandos de menú y avisos de la app en un único receptor: una
        // cadena larga de modificadores supera al comprobador de tipos.
        .onReceive(Self.commandNotifications) { notification in
            handleCommandNotification(notification)
        }
    }

    private var documentTitle: some View {
        LitteraDocumentTitle(
            fileName: activeDocument?.fileName ?? "ui.sin.documento",
            isDirty: activeDocument?.isDirty ?? false,
            openDocuments: { post(.litteraShowDocuments) }
        )
    }

    private var titlebarActions: some View {
        LitteraTitlebarActions(
            writingWidth: $writingWidth,
            isSearchPresented: $isSearchPresented,
            searchQuery: $searchQuery,
            isReplacing: $isReplacing,
            replacement: $replacement,
            canSearch: mode != .preview,
            search: { direction in editingTarget.search(searchQuery, direction: direction) },
            endSearch: { editingTarget.focus() },
            replaceCurrent: { editingTarget.replaceCurrent(searchQuery, with: replacement) },
            replaceAll: { editingTarget.replaceAll(searchQuery, with: replacement) },
            showStats: $showStats,
            isPropertiesPresented: $isPropertiesPresented,
            hasDocument: activeDocument != nil,
            currentMarkdown: { documentStore.activeDocument?.markdown ?? "" },
            setProperty: setDocumentProperty,
            derivedDocument: documentStore.derivedDocuments[documentStore.activeDocumentID],
            // Los comandos de documento los atiende LitteraCommandHost.
            newDocument: { post(.litteraNewDocument) },
            openDocument: { post(.litteraOpenDocument) },
            saveDocument: { post(.litteraSaveDocument) },
            saveAsDocument: { post(.litteraSaveAsDocument) },
            openCommandPalette: { post(.litteraShowPalette) },
            openDocumentsPalette: { post(.litteraShowDocuments) },
            exportPDF: { post(.litteraExportPDF) },
            exportHTML: { post(.litteraExportHTML) }
        )
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    /// Solo lo que depende del estado del editor (modo, selección, búsqueda).
    /// Documentos, paletas, exportar y avisos de la app: LitteraCommandHost.
    private static let commandNotifications = Publishers.MergeMany(
        [
            Notification.Name.litteraFinderAction, .litteraSetMode,
            .litteraSearchQuery, .litteraApplyFormat,
            .litteraEditorCommand, .litteraFocusEditor
        ].map { NotificationCenter.default.publisher(for: $0) }
    )

    private func handleCommandNotification(_ notification: Notification) {
        switch notification.name {
        case .litteraEditorCommand:
            guard let id = notification.object as? String else { return }
            runCommand(id)
        case .litteraFocusEditor:
            editingTarget.focus()
        case .litteraFinderAction:
            guard mode != .preview,
                  let rawValue = notification.object as? Int,
                  let action = NSTextFinder.Action(rawValue: rawValue) else { return }
            editingTarget.requestFinderAction(action)
        case .litteraSearchQuery:
            // Se escribe en la barra del rediseño: no abrimos el panel flotante.
            guard mode != .preview, let text = notification.object as? String else { return }
            searchQuery = text
            if !text.isEmpty { _ = editingTarget.search(text, direction: .next) }
        case .litteraApplyFormat:
            // Igual que los comandos de formato de la paleta: no en Vista previa.
            guard mode != .preview, let rawValue = notification.object as? String,
                  let action = LitteraFormattingAction(rawValue: rawValue) else { return }
            editingTarget.apply(action)
        case .litteraSetMode:
            guard let rawValue = notification.object as? String,
                  let newMode = LitteraEditorMode(rawValue: rawValue) else { return }
            mode = newMode
        default:
            break
        }
    }

    /// Comandos Buscar del menú Edición, recibidos desde el editor activo.
    private func handleFindRequest(_ action: NSTextFinder.Action, selection: String?) {
        switch action {
        case .showFindInterface:
            isReplacing = false
            isSearchPresented = true
        case .showReplaceInterface:
            isReplacing = true
            isSearchPresented = true
        case .nextMatch, .previousMatch:
            if searchQuery.isEmpty {
                isSearchPresented = true
            } else {
                editingTarget.search(searchQuery, direction: action == .nextMatch ? .next : .previous)
            }
        case .setSearchString:
            if let selection { searchQuery = selection }
        default:
            break
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        // Editor y Vista previa ocupan siempre la misma posición del árbol: si
        // dependieran de una rama por modo, SwiftUI los recrearía en cada cambio.
        GeometryReader { proxy in
            let isSplit = mode == .split
            let paneWidth = isSplit ? (proxy.size.width - 1) / 2 : proxy.size.width
            // Si el área llega a medir 1×1, la Vista previa conserva su último
            // tamaño real: maquetarla a 1 píxel es muy caro y, al crecer,
            // dejaba su contenido desplazado.
            let isOnScreen = proxy.size.width > 1
            let previewSize = isOnScreen ? proxy.size : lastEditorSize
            let splitWidth = (previewSize.width - 1) / 2
            ZStack(alignment: .topLeading) {
                unifiedEditor
                    .frame(width: paneWidth, height: proxy.size.height)
                if isSplit {
                    colors.line
                        .frame(width: 1, height: proxy.size.height)
                        .offset(x: paneWidth)
                }
                // Una instancia por anchura: remaquetar la Vista previa al entrar o
                // salir de Dividido era casi todo su coste.
                if isFullPreviewBuilt, previewSize.width > 1 {
                    documentPreview(slot: fullPreviewSlot, isVisible: mode == .preview, isOnScreen: isOnScreen)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .accessibilityHidden(mode != .preview)
                }
                if isSplitPreviewBuilt, previewSize.width > 1 {
                    documentPreview(slot: splitPreviewSlot, isVisible: isSplit, isOnScreen: isOnScreen)
                        .frame(width: splitWidth, height: previewSize.height)
                        .offset(x: splitWidth + 1)
                        .accessibilityHidden(!isSplit)
                }
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                if size.width > 1 { lastEditorSize = size }
            }
        }
    }

    private var showsPreview: Bool { mode == .preview || mode == .split }

    private var currentPreparation: PreparedPreview {
        PreparedPreview(documentID: documentStore.activeDocumentID, width: lastEditorSize.width)
    }

    private var isFullPreviewBuilt: Bool {
        mode == .preview || preparedFullPreview == currentPreparation
    }

    private var isSplitPreviewBuilt: Bool {
        mode == .split || preparedSplitPreview == currentPreparation
    }

    /// Editor Fuente (D77): una sola NSTextView que sirve a Fuente y a
    /// Dividido y queda oculta, sin recrearse, en Vista previa.
    private var unifiedEditor: some View {
        let documentID = documentStore.activeDocumentID

        return LitteraSourceTextView(
            text: sourceText,
            selectedRanges: sourceSelection(for: documentID),
            scrollOffset: sourceScrollOffset(for: documentID),
            documentID: documentID,
            fontSize: CGFloat(sourceFontSize),
            textColor: NSColor(colors.primaryText),
            scrollCoordinator: scrollCoordinator,
            mode: mode,
            sourceHighlight: LitteraSourceHighlight(
                document: documentStore.derivedDocuments[documentID],
                colorScheme: scheme,
                style: LitteraSourceHighlightStyle.stored(storedSourceHighlightStyle)
            ),
            editingTarget: editingTarget,
            lineSpacing: LitteraLineSpacing.stored(storedLineSpacing),
            typewriter: typewriterMode,
            spellChecking: spellChecking,
            sourceColumnWidth: writingWidth.sourceColumnWidth
        )
            // El margen horizontal lo pone el propio editor para centrar la
            // columna (Fase 2); la barra de desplazamiento queda en el borde.
            .padding(.vertical, LitteraDesign.Editor.sourceVerticalPadding)
            .background(colors.secondary)
            .id(documentID)
    }

    private func documentPreview(slot: LitteraPreviewSlot, isVisible: Bool, isOnScreen: Bool) -> some View {
        let documentID = documentStore.activeDocumentID

        return LitteraPreviewTextHost(
            content: LitteraPreviewContent(
                documentID: documentID,
                document: previewDocument(for: documentID),
                documentURL: documentStore.documents.first(where: { $0.id == documentID })?.fileURL,
                writingWidth: writingWidth.points,
                bodyLineSpacing: LitteraLineSpacing.stored(storedLineSpacing).bodySpacing,
                colorScheme: scheme,
                locale: locale
            ),
            scrollCoordinator: scrollCoordinator,
            slot: slot,
            isVisible: isVisible,
            isOnScreen: isOnScreen
        )
    }

    private func sourceSelection(for documentID: String) -> Binding<[NSRange]> {
        Binding(
            get: { sourceEditorStates[documentID]?.selectedRanges ?? initialSelection(for: documentID) },
            set: { newSelection in
                var state = sourceEditorStates[documentID] ?? SourceEditorState()
                guard state.selectedRanges != newSelection else { return }
                state.selectedRanges = newSelection
                sourceEditorStates[documentID] = state
            }
        )
    }

    /// Un documento nuevo empieza con el cursor debajo del frontmatter,
    /// listo para escribir; los demás, al principio.
    private func initialSelection(for documentID: String) -> [NSRange] {
        guard let document = documentStore.documents.first(where: { $0.id == documentID }),
              document.isPristineUntitled,
              LitteraDocumentProperties.isNewDocumentTemplate(document.markdown) else { return [] }
        return [NSRange(location: (document.markdown as NSString).length, length: 0)]
    }

    private func sourceScrollOffset(for documentID: String) -> Binding<CGPoint> {
        Binding(
            get: { sourceEditorStates[documentID]?.scrollOffset ?? .zero },
            set: { newOffset in
                var state = sourceEditorStates[documentID] ?? SourceEditorState()
                guard abs(state.scrollOffset.x - newOffset.x) >= 0.5
                    || abs(state.scrollOffset.y - newOffset.y) >= 0.5 else { return }
                state.scrollOffset = newOffset
                sourceEditorStates[documentID] = state
            }
        )
    }

    /// Comandos de la paleta que dependen del editor. Los de documento, modo
    /// y ancho los resuelve LitteraCommandHost.
    private func runCommand(_ id: String) {
        switch id {
        case "stats": showStats = true
        case "properties": isPropertiesPresented = true
        default:
            if let command = LitteraCommandRegistry.editingCommand(for: id) {
                guard mode != .preview else { break }
                DispatchQueue.main.async { editingTarget.apply(command) }
                break
            }
            guard let action = LitteraCommandRegistry.formatAction(for: id), mode != .preview else { break }
            // Tras cerrar la paleta, el foco vuelve al editor y se aplica el formato.
            DispatchQueue.main.async { editingTarget.apply(action) }
        }
    }

    /// Cambia una propiedad del frontmatter (D53). Es una edición del texto
    /// con su paso de deshacer, también en Vista previa (el editor sigue
    /// existiendo, oculto). Solo si el editor no tiene este documento se
    /// cambia el documento directamente.
    private func setDocumentProperty(_ key: String, _ value: String?) {
        guard let document = activeDocument else { return }
        if editingTarget.setDocumentProperty(key, to: value, documentText: document.markdown) { return }
        guard
              let edit = LitteraDocumentProperties.edit(
                setting: key,
                to: value,
                in: document.markdown,
                selection: NSRange(location: 0, length: 0),
                language: locale.language.languageCode?.identifier ?? "es"
              ) else { return }
        let text = (document.markdown as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        documentStore.updateMarkdown(for: document.id, text: text)
    }

    private func previewDocument(for documentID: String) -> LitteraMarkdownDerivedDocument? {
        let latest = documentStore.derivedDocuments[documentID]
        guard mode != .preview, let splitPreview, splitPreview.documentID == documentID else { return latest }
        return splitPreview.document
    }

    /// En Dividido, maquetar toda la Vista previa en cada pulsación bloqueaba la
    /// escritura en documentos largos (Instruments): se espera a una pausa.
    private func scheduleSplitPreviewUpdate() {
        let documentID = documentStore.activeDocumentID
        guard let latest = documentStore.derivedDocuments[documentID] else { return }
        pendingSplitPreview?.cancel()
        // Oculta no se actualiza con cada pulsación: se pone al día en cuanto se
        // deja de escribir, para no pagar ese trabajo al mostrarla.
        if !showsPreview, splitPreview?.documentID == documentID {
            guard splitPreview?.document !== latest else { return }
            let work = DispatchWorkItem {
                guard documentStore.activeDocumentID == documentID,
                      let current = documentStore.derivedDocuments[documentID] else { return }
                splitPreview = (documentID, current)
            }
            pendingSplitPreview = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            return
        }
        // Otro documento o modo: se muestra al instante.
        guard mode == .split, splitPreview?.documentID == documentID else {
            splitPreview = (documentID, latest)
            return
        }
        guard splitPreview?.document !== latest else { return }
        let work = DispatchWorkItem {
            guard documentStore.activeDocumentID == documentID,
                  let current = documentStore.derivedDocuments[documentID] else { return }
            splitPreview = (documentID, current)
        }
        pendingSplitPreview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

}

/// Una de las Vistas previas construidas. El coordinador de desplazamiento solo
/// conoce la visible: esta guarda sus posiciones para entregárselas al mostrarse.
final class LitteraPreviewSlot {
    private weak var scrollView: NSScrollView?
    private var documentID: String?
    private var offsets: [String: CGFloat] = [:]
    private var isActive = false

    func resolve(_ scrollView: NSScrollView, documentID: String, coordinator: LitteraScrollCoordinator) {
        self.scrollView = scrollView
        self.documentID = documentID
        if isActive { coordinator.attachPreview(scrollView: scrollView, documentID: documentID) }
    }

    func update(_ offsets: [String: CGFloat], documentID: String, coordinator: LitteraScrollCoordinator) {
        self.offsets = offsets
        self.documentID = documentID
        if isActive { coordinator.updatePreviewBlockOffsets(offsets, documentID: documentID) }
    }

    func setActive(_ active: Bool, coordinator: LitteraScrollCoordinator) {
        guard isActive != active else { return }
        isActive = active
        guard active, let scrollView, let documentID else { return }
        coordinator.attachPreview(scrollView: scrollView, documentID: documentID)
        coordinator.updatePreviewBlockOffsets(offsets, documentID: documentID)
    }
}
