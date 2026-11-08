//  LitteraUICommandPaletteView.swift
//  Littera v1 · Paleta de comandos y documentos (D72, D80)
//
//  Una sola paleta para ⌘K (documentos y comandos) y ⇧⌘O (solo documentos),
//  sin pestañas ni etiquetas: búsqueda, resultados agrupados y pie de ayuda.
//  Recibe entradas ya preparadas (documentos abiertos y recientes, comandos
//  del registro), así que una función nueva aparece aquí sin cambiar esta vista.
//
//  Capa de presentación: no importa servicios del backend.

import SwiftUI

// MARK: - Modelo

nonisolated struct LitteraUIPaletteEntry: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case document, command }

    let id: String
    let kind: Kind
    let title: String
    /// Documento: nombre de archivo. Comando: vacío.
    var detail: String
    /// Documento: carpeta.
    var secondary: String
    let symbol: String
    /// Comando: título de su grupo, ya localizado.
    var group: String
    var shortcut: String?
    var date: Date?
    var keywords: [String]
    var isOpen: Bool
    var isActive: Bool
    var enabled: Bool

    init(id: String, kind: Kind, title: String, detail: String = "", secondary: String = "",
         symbol: String, group: String = "", shortcut: String? = nil, date: Date? = nil,
         keywords: [String] = [], isOpen: Bool = false,
         isActive: Bool = false, enabled: Bool = true) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail
        self.secondary = secondary; self.symbol = symbol; self.group = group
        self.shortcut = shortcut; self.date = date; self.keywords = keywords
        self.isOpen = isOpen; self.isActive = isActive; self.enabled = enabled
    }
}

/// Qué muestra la paleta: ⌘K, documentos y comandos; ⇧⌘O, solo documentos.
nonisolated enum LitteraUIPaletteScope: Sendable {
    case all, documents
}

nonisolated struct LitteraUIPaletteSection: Identifiable, Equatable, Sendable {
    enum Header: Equatable, Sendable { case recent, documents(Int), group(String) }
    let header: Header
    let entries: [LitteraUIPaletteEntry]

    var id: String {
        switch header {
        case .recent: "recent"
        case .documents: "documents"
        case .group(let g): "group." + g
        }
    }
}

// MARK: - Búsqueda

/// Filtrado y orden de la paleta. Puro: se prueba sin vistas.
nonisolated enum LitteraUIPaletteSearch {
    static let recentLimit = 6
    static let mixedDocumentLimit = 8
    static let documentLimit = 300

    static func sections(scope: LitteraUIPaletteScope, query: String,
                         documents: [LitteraUIPaletteEntry],
                         commands: [LitteraUIPaletteEntry]) -> [LitteraUIPaletteSection] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        var result: [LitteraUIPaletteSection] = []
        switch scope {
        case .all:
            if terms.isEmpty {
                result.append(.init(header: .recent, entries: Array(recent(documents).prefix(recentLimit))))
                result += grouped(commands)
            } else {
                let docs = rank(documents, terms)
                result.append(.init(header: .documents(docs.count), entries: Array(docs.prefix(mixedDocumentLimit))))
                result += grouped(rank(commands, terms))
            }
        case .documents:
            let docs = terms.isEmpty ? recent(documents) : rank(documents, terms)
            result.append(.init(header: .documents(docs.count), entries: Array(docs.prefix(documentLimit))))
        }
        return result.filter { !$0.entries.isEmpty }
    }

    /// Activo, abiertos y después los más recientes.
    static func recent(_ documents: [LitteraUIPaletteEntry]) -> [LitteraUIPaletteEntry] {
        documents.enumerated().sorted { a, b in
            let ra = a.element.isActive ? 0 : (a.element.isOpen ? 1 : 2)
            let rb = b.element.isActive ? 0 : (b.element.isOpen ? 1 : 2)
            if ra != rb { return ra < rb }
            let da = a.element.date ?? .distantPast, db = b.element.date ?? .distantPast
            if da != db { return da > db }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Todas las palabras deben aparecer; primero lo que empieza por la
    /// primera palabra, después lo que la contiene en el título.
    static func rank(_ entries: [LitteraUIPaletteEntry], _ terms: [String]) -> [LitteraUIPaletteEntry] {
        guard let first = terms.first else { return entries }
        return entries.enumerated().compactMap { index, entry -> (Int, Int, LitteraUIPaletteEntry)? in
            let haystack = ([entry.title, entry.detail, entry.secondary, entry.group] + entry.keywords)
                .joined(separator: " ")
            guard terms.allSatisfy({ haystack.localizedStandardContains($0) }) else { return nil }
            let score: Int
            if entry.title.range(of: first, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                score = 0
            } else if entry.title.localizedStandardContains(first) {
                score = 1
            } else {
                score = 2
            }
            return (score, index, entry)
        }
        .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        .map(\.2)
    }

    /// Comandos por grupo, en el orden en que aparece cada grupo.
    static func grouped(_ commands: [LitteraUIPaletteEntry]) -> [LitteraUIPaletteSection] {
        var order: [String] = []
        var byGroup: [String: [LitteraUIPaletteEntry]] = [:]
        for command in commands {
            if byGroup[command.group] == nil { order.append(command.group) }
            byGroup[command.group, default: []].append(command)
        }
        return order.map { .init(header: .group($0), entries: byGroup[$0] ?? []) }
    }
}

// MARK: - Vista

struct LitteraUICommandPaletteView: View {
    let documents: [LitteraUIPaletteEntry]
    let commands: [LitteraUIPaletteEntry]
    let onChooseDocument: (String) -> Void
    let onChooseCommand: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.litteraUITheme) private var theme
    @Environment(\.locale) private var locale
    private let scope: LitteraUIPaletteScope
    @State private var query = ""
    // Selección de teclado y puntero separados: señalar o desplazar no
    // cambia la selección (mismo comportamiento que la paleta 1.x).
    @State private var selectedID: String?
    @State private var hoveredID: String?
    @State private var listScroller = LitteraPaletteListScroller()
    @FocusState private var searchFocused: Bool

    init(documents: [LitteraUIPaletteEntry], commands: [LitteraUIPaletteEntry],
         scope: LitteraUIPaletteScope = .all,
         onChooseDocument: @escaping (String) -> Void,
         onChooseCommand: @escaping (String) -> Void,
         onDismiss: @escaping () -> Void) {
        self.documents = documents
        self.commands = commands
        self.onChooseDocument = onChooseDocument
        self.onChooseCommand = onChooseCommand
        self.onDismiss = onDismiss
        self.scope = scope
    }

    private var sections: [LitteraUIPaletteSection] {
        LitteraUIPaletteSearch.sections(scope: scope, query: query, documents: documents, commands: commands)
    }

    var body: some View {
        let sections = self.sections
        VStack(spacing: 0) {
            searchRow
            theme.line.frame(height: LitteraUITokens.Shape.hairline)
            results(sections)
            theme.line.frame(height: LitteraUITokens.Shape.hairline)
            footer
        }
        .frame(width: 640)
        .background(theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: LitteraUITokens.Shape.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LitteraUITokens.Shape.panel, style: .continuous)
                .strokeBorder(theme.line, lineWidth: LitteraUITokens.Shape.hairline)
        }
        .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
        // Esc cierra aunque el campo no tenga el foco (tras elegir una
        // etiqueta, el editor de campo puede quedarse con la tecla).
        .background {
            Button("", action: onDismiss).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .onExitCommand(perform: onDismiss)
        .onAppear {
            selectFirst()
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in selectFirst() }
    }

    // MARK: Búsqueda

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.litteraUI(size: 16)).foregroundStyle(theme.muted)
                .accessibilityHidden(true)
            TextField(L10n.tr("ui.rd.pal.placeholder", locale: locale), text: $query)
                .textFieldStyle(.plain)
                .font(.litteraUI(size: 18))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .focused($searchFocused)
                .onSubmit(performSelected)
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.escape) { onDismiss(); return .handled }
            keyChip("ESC")
        }
        .padding(.horizontal, 18).frame(height: 56)
    }

    // MARK: Resultados

    private func results(_ sections: [LitteraUIPaletteSection]) -> some View {
        ScrollView {
            if sections.isEmpty {
                Text(L10n.tr("ui.rd.pal.empty", locale: locale))
                    .font(.litteraUI(size: LitteraUITokens.FontSize.labelMd))
                    .foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(36)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        sectionLabel(section.header)
                        ForEach(section.entries) { entry in row(entry) }
                    }
                }
                .padding(.bottom, 8)
                .litteraPaletteList(listScroller)
            }
        }
        .frame(maxHeight: 380)
    }

    private func sectionLabel(_ header: LitteraUIPaletteSection.Header) -> some View {
        let title: String
        var trailing: String?
        switch header {
        case .recent: title = L10n.tr("ui.rd.pal.recent", locale: locale)
        case .documents(let n):
            title = L10n.tr("ui.rd.pal.documents", locale: locale)
            trailing = matches(n)
        case .group(let g): title = g.uppercased(with: locale)
        }
        return HStack {
            Text(title).font(.litteraUI(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(theme.muted)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.litteraUI(size: LitteraUITokens.FontSize.labelSm)).foregroundStyle(theme.muted)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }

    private func matches(_ n: Int) -> String {
        n == 1 ? L10n.tr("ui.rd.pal.matchOne", locale: locale) : L10n.formatted("ui.rd.pal.matches", locale: locale, n)
    }

    private func row(_ entry: LitteraUIPaletteEntry) -> some View {
        let isSelected = selectedID == entry.id && entry.enabled
        let isHovered = hoveredID == entry.id && entry.enabled
        return Button { choose(entry) } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: LitteraUITokens.Shape.control)
                    .fill(isSelected ? theme.accent.opacity(0.18) : theme.control)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: entry.symbol).font(.litteraUI(size: 14))
                            .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                    }
                    .accessibilityHidden(true)
                rowText(entry)
                Spacer(minLength: 8)
                rowTrailing(entry, isSelected: isSelected)
            }
            .opacity(entry.enabled ? 1 : 0.45)
            .padding(.horizontal, 12)
            .frame(minHeight: entry.kind == .document ? 48 : 38)
            .background {
                RoundedRectangle(cornerRadius: LitteraUITokens.Shape.control, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.14) : (isHovered ? theme.accent.opacity(0.07) : .clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.enabled)
        .padding(.horizontal, 8)
        .onHover { inside in
            if inside { hoveredID = entry.id } else if hoveredID == entry.id { hoveredID = nil }
        }
        .litteraPaletteRow(entry.id)
    }

    @ViewBuilder
    private func rowText(_ entry: LitteraUIPaletteEntry) -> some View {
        switch entry.kind {
        case .document:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.title).font(.litteraUI(size: LitteraUITokens.FontSize.labelMd, weight: .medium))
                        .foregroundStyle(theme.primaryText).lineLimit(1)
                    if entry.detail != entry.title {
                        Text(entry.detail).font(.litteraUI(size: LitteraUITokens.FontSize.codeSm, design: .monospaced))
                            .foregroundStyle(theme.muted).lineLimit(1)
                    }
                }
                if !entry.secondary.isEmpty {
                    Text(entry.secondary).font(.litteraUI(size: LitteraUITokens.FontSize.codeSm, design: .monospaced))
                        .foregroundStyle(theme.muted).lineLimit(1).truncationMode(.head)
                }
            }
        case .command:
            Text(entry.title).font(.litteraUI(size: LitteraUITokens.FontSize.labelMd, weight: .medium))
                .foregroundStyle(theme.primaryText).lineLimit(1)
        }
    }

    @ViewBuilder
    private func rowTrailing(_ entry: LitteraUIPaletteEntry, isSelected: Bool) -> some View {
        switch entry.kind {
        case .document:
            if entry.isActive {
                pill(L10n.tr("ui.rd.pal.active", locale: locale), filled: true)
            } else if entry.isOpen {
                pill(L10n.tr("ui.rd.pal.open", locale: locale), filled: false)
            } else if let date = entry.date {
                Text(date.formatted(.relative(presentation: .named).locale(locale)))
                    .font(.litteraUI(size: LitteraUITokens.FontSize.labelSm)).foregroundStyle(theme.muted)
            }
        case .command:
            if let shortcut = entry.shortcut, !shortcut.isEmpty { keyChip(shortcut) }
        }
        Text("↵").font(.litteraUI(size: 13)).foregroundStyle(theme.accent)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text).font(.litteraUI(size: 10, weight: .medium))
            .foregroundStyle(filled ? .white : theme.accent)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background { Capsule().fill(filled ? theme.accent : theme.accent.opacity(0.12)) }
    }

    private func keyChip(_ key: String) -> some View {
        Text(key).font(.litteraUI(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background { RoundedRectangle(cornerRadius: LitteraUITokens.Shape.small).fill(theme.control) }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", "ui.rd.pal.navigate")
            hint("↵", "ui.rd.pal.select")
            Spacer(minLength: 0)
            hint("Esc", "ui.rd.pal.close")
        }
        .padding(.horizontal, 18).frame(height: 40)
        .background(theme.chrome)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            keyChip(key)
            Text(L10n.tr(label, locale: locale)).font(.litteraUI(size: LitteraUITokens.FontSize.labelSm)).foregroundStyle(theme.muted)
        }
    }

    // MARK: Selección

    private var ordered: [LitteraUIPaletteEntry] { sections.flatMap(\.entries).filter(\.enabled) }

    private func selectFirst() {
        selectedID = ordered.first?.id
        if let selectedID { listScroller.reveal(selectedID, toTop: true) }
    }

    private func moveSelection(_ direction: Int) {
        let entries = ordered
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedID }
        let next = ((current ?? (direction > 0 ? -1 : 0)) + direction + entries.count) % entries.count
        selectedID = entries[next].id
        listScroller.reveal(entries[next].id, toTop: next == 0)
    }

    private func performSelected() {
        guard let entry = ordered.first(where: { $0.id == selectedID }) else { return }
        choose(entry)
    }

    private func choose(_ entry: LitteraUIPaletteEntry) {
        guard entry.enabled else { return }
        switch entry.kind {
        case .document: onChooseDocument(entry.id)
        case .command: onChooseCommand(entry.id)
        }
    }
}
