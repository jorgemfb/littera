import SwiftUI

// La barra es nativa: nada de cápsulas personalizadas, segunda fila o selector.
// El título existente sirve como acceso a los documentos abiertos.
struct LitteraDocumentTitle: View {
    let fileName: String
    let isDirty: Bool
    let openDocuments: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        Button(action: openDocuments) {
            HStack(spacing: LitteraDesign.Titlebar.titleSpacing) {
                Circle()
                    .fill(colors.accent)
                    .frame(
                        width: LitteraDesign.Titlebar.indicatorDiameter,
                        height: LitteraDesign.Titlebar.indicatorDiameter
                    )
                    .accessibilityHidden(true)

                Text(fileName)
                    .font(.system(size: LitteraDesign.Titlebar.documentFontSize, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(1)

                if isDirty {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.accent)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.helpText(locale: locale))
        .accessibilityLabel(L10n.formatted("ui.documento.mostrar.documentos.abiertos", locale: locale, fileName))
        .accessibilityValue(isDirty ? L10n.tr("ui.cambios.sin.guardar", locale: locale) : "")
    }

    /// Con el atajo configurado en Ajustes → Atajos, no uno fijo en el texto.
    @MainActor
    static func helpText(locale: Locale) -> String {
        let title = L10n.tr("ui.cambiar.de.documento.abierto", locale: locale)
        guard let shortcut = LitteraShortcuts.shared.display(for: "documents.switch") else { return title }
        return "\(title) (\(shortcut))"
    }
}

struct LitteraTitlebarActions: View {
    @Binding var writingWidth: LitteraWritingWidth
    @Binding var isSearchPresented: Bool
    @Binding var searchQuery: String
    @Binding var isReplacing: Bool
    @Binding var replacement: String

    let canSearch: Bool
    let search: (LitteraSearchDirection) -> LitteraSearchResult?
    let endSearch: () -> Void
    let replaceCurrent: () -> LitteraSearchResult?
    let replaceAll: () -> Int
    @Binding var showStats: Bool
    @Binding var isPropertiesPresented: Bool
    let hasDocument: Bool
    let currentMarkdown: () -> String
    let setProperty: (_ key: String, _ value: String?) -> Void
    let derivedDocument: LitteraMarkdownDerivedDocument?
    let newDocument: () -> Void
    let openDocument: () -> Void
    let saveDocument: () -> Void
    let saveAsDocument: () -> Void
    let openCommandPalette: () -> Void
    let openDocumentsPalette: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void

    @AppStorage(LitteraPreferenceKeys.typewriterMode)
    private var typewriterMode = LitteraPreferenceDefaults.typewriterMode
    @AppStorage(LitteraPreferenceKeys.spellChecking)
    private var spellChecking = LitteraPreferenceDefaults.spellChecking
    @AppStorage(LitteraPreferenceKeys.sourceHighlightStyle)
    private var sourceHighlightStyle = LitteraPreferenceDefaults.sourceHighlightStyle
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        HStack(spacing: LitteraDesign.Titlebar.actionSpacing) {
            propertiesButton
            searchButton
            optionsMenu
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Propiedades del documento: el frontmatter YAML en un panel (D53).
    private var propertiesButton: some View {
        Button { isPropertiesPresented.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: LitteraDesign.Titlebar.actionIconSize))
                .foregroundStyle(colors.primaryText)
                .frame(
                    width: LitteraDesign.Titlebar.actionHitSize,
                    height: LitteraDesign.Titlebar.actionHitSize
                )
                .contentShape(Rectangle())
        }
        .disabled(!hasDocument)
        .accessibilityLabel(L10n.tr("ui.propiedades.del.documento", locale: locale))
        .help(L10n.tr("ui.propiedades.del.documento", locale: locale))
        .popover(isPresented: $isPropertiesPresented, arrowEdge: .bottom) {
            LitteraPropertiesPopover(currentMarkdown: currentMarkdown, setProperty: setProperty)
        }
    }

    private var searchButton: some View {
        Button { isSearchPresented.toggle() } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LitteraDesign.Titlebar.actionIconSize))
                .foregroundStyle(colors.primaryText)
                .frame(
                    width: LitteraDesign.Titlebar.actionHitSize,
                    height: LitteraDesign.Titlebar.actionHitSize
                )
                .contentShape(Rectangle())
        }
        .disabled(!canSearch)
        .accessibilityLabel(L10n.tr("ui.buscar.en.el.documento", locale: locale))
        .help(L10n.tr(
            canSearch ? "ui.buscar.en.el.documento" : "ui.busqueda.no.disponible.en.vista.previa",
            locale: locale
        ))
        .popover(isPresented: $isSearchPresented, arrowEdge: .bottom) {
            LitteraSearchPopover(
                searchQuery: $searchQuery,
                isReplacing: $isReplacing,
                replacement: $replacement,
                search: search,
                endSearch: endSearch,
                replaceCurrent: replaceCurrent,
                replaceAll: replaceAll
            )
        }
        .onChange(of: canSearch) { _, available in
            if !available { isSearchPresented = false }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("ui.nuevo.documento.markdown", action: newDocument)

            Divider()

            Button("ui.abrir.documento", action: openDocument)
            Button("ui.documentos.abiertos", action: openDocumentsPalette)

            Divider()

            Button("ui.guardar.documento", action: saveDocument)
            Button("ui.guardar.como", action: saveAsDocument)
            Menu("ui.exportar") {
                Button("ui.exportar.como.pdf", action: exportPDF)
                Button("ui.exportar.como.html", action: exportHTML)
            }

            Divider()

            Menu("ui.anchura.del.texto") {
                ForEach(LitteraWritingWidth.allCases) { option in
                    Button {
                        writingWidth = option
                    } label: {
                        HStack {
                            Text(L10n.tr(option.titleKey, locale: locale))
                            if writingWidth == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Menu("ui.resaltado.de.fuente") {
                Picker("ui.resaltado.de.fuente", selection: $sourceHighlightStyle) {
                    ForEach(LitteraSourceHighlightStyle.allCases) { option in
                        Text(L10n.tr(option.titleKey, locale: locale)).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Button("ui.paleta.de.comandos", action: openCommandPalette)
            Toggle("ui.modo.maquina.de.escribir", isOn: $typewriterMode)
            Toggle("ui.corrector.ortografico", isOn: $spellChecking)

            Divider()

            Button("ui.propiedades.del.documento") { isPropertiesPresented = true }
                .disabled(!hasDocument)
            Button("ui.estadisticas.del.documento") { showStats = true }

            SettingsLink { Text("ui.ajustes") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: LitteraDesign.Titlebar.actionIconSize, weight: .medium))
                .foregroundStyle(colors.primaryText)
                .frame(
                    width: LitteraDesign.Titlebar.actionHitSize,
                    height: LitteraDesign.Titlebar.actionHitSize
                )
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .help("ui.mas.opciones")
        .accessibilityLabel(L10n.tr("ui.mas.opciones", locale: locale))
        .popover(isPresented: $showStats) {
            let statistics = derivedDocument.map(LitteraDocumentStatistics.init)
            VStack(alignment: .leading, spacing: 10) {
                Text("ui.estadisticas.del.documento").font(.headline)
                Text(L10n.counted("ui.d.palabras", statistics?.words ?? 0, locale: locale))
                Text(L10n.counted("ui.d.caracteres", statistics?.characters ?? 0, locale: locale))
                Text(L10n.counted("ui.d.caracteres.sin.espacios", statistics?.charactersWithoutSpaces ?? 0, locale: locale))
                Text(L10n.counted("ui.d.parrafos", statistics?.paragraphs ?? 0, locale: locale))
                Text(L10n.counted("ui.d.lineas", statistics?.lines ?? 0, locale: locale))
                Text(L10n.formatted("ui.tiempo.estimado.d.min", locale: locale, statistics?.readingMinutes ?? 1))
            }
            .padding(18)
            .frame(width: 245, alignment: .leading)
        }
    }
}

/// Contenido del popover de la lupa. Es una vista propia para que observe
/// directamente sus valores: el contenido de un popover de la barra de
/// herramientas no siempre se actualiza con los cambios de la vista padre.
/// Compartido con el modo sin cromo del rediseño (fase 7), que lo ancla
/// en el área del editor porque no hay barra de título donde colgarlo.
struct LitteraSearchPopover: View {
    @Binding var searchQuery: String
    @Binding var isReplacing: Bool
    @Binding var replacement: String

    let search: (LitteraSearchDirection) -> LitteraSearchResult?
    let endSearch: () -> Void
    let replaceCurrent: () -> LitteraSearchResult?
    let replaceAll: () -> Int

    @State private var searchResult: LitteraSearchResult?
    @State private var replacedCount: Int?
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("ui.buscar.en.el.documento", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFieldFocused)
                .onKeyPress(.return, phases: .down) { press in
                    runSearch(press.modifiers.contains(.shift) ? .previous : .next)
                    return .handled
                }
            if isReplacing {
                TextField("ui.reemplazar.con", text: $replacement)
                    .textFieldStyle(.roundedBorder)
                    .onKeyPress(.return, phases: .down) { _ in
                        runReplace()
                        return .handled
                    }
            }
            HStack(spacing: 8) {
                Text(searchStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(1)
                if isReplacing {
                    Spacer(minLength: 8)
                    Button("ui.reemplazar", action: runReplace)
                        .fixedSize()
                    Button("ui.reemplazar.todo", action: runReplaceAll)
                        .fixedSize()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(searchQuery.isEmpty)
        }
        .padding(16)
        .frame(width: 330)
        .onAppear {
            isSearchFieldFocused = true
            runSearch(.incremental)
        }
        .onDisappear {
            isReplacing = false
            replacedCount = nil
            endSearch()
        }
        .onChange(of: searchQuery) { _, _ in
            replacedCount = nil
            runSearch(.incremental)
        }
    }

    private var searchStatus: String {
        if let replacedCount {
            return L10n.counted("ui.busqueda.d.reemplazos", replacedCount, locale: locale)
        }
        guard !searchQuery.isEmpty, let searchResult else {
            // Con Reemplazar, los botones ya explican qué hacer.
            return isReplacing ? "" : L10n.tr("ui.busqueda.ayuda", locale: locale)
        }
        guard searchResult.total > 0 else {
            return L10n.tr("ui.busqueda.sin.resultados", locale: locale)
        }
        return L10n.formatted("ui.busqueda.d.de.d", locale: locale, searchResult.current, searchResult.total)
    }

    private func runSearch(_ direction: LitteraSearchDirection) {
        searchResult = searchQuery.isEmpty ? nil : search(direction)
    }

    private func runReplace() {
        guard !searchQuery.isEmpty else { return }
        replacedCount = nil
        searchResult = replaceCurrent()
    }

    private func runReplaceAll() {
        guard !searchQuery.isEmpty else { return }
        replacedCount = replaceAll()
        searchResult = nil
    }
}
