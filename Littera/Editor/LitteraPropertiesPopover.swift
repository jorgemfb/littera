import AppKit
import SwiftUI

/// Panel de propiedades del documento (D53): lee y escribe el frontmatter
/// YAML. Cada cambio es una edición del texto, con su paso de deshacer
/// cuando hay un editor abierto.
///
/// Es una vista propia que pide el texto al aparecer y tras cada cambio: el
/// contenido de un popover de la barra no siempre se actualiza con la vista
/// padre. Los campos se desplazan entre la cabecera y la opción de índice,
/// que quedan fijas, para que un frontmatter largo no salga de la pantalla.
struct LitteraPropertiesPopover: View {
    /// Markdown actual del documento activo.
    let currentMarkdown: () -> String
    /// Cambia una clave del frontmatter (`nil` la elimina).
    let setProperty: (_ key: String, _ value: String?) -> Void

    @State private var properties = LitteraDocumentProperties()
    @State private var title = ""
    /// Texto en edición de las otras claves (valores de una línea y YAML).
    @State private var drafts: [String: String] = [:]
    /// Texto del campo «Añadir…» de cada lista (`tags` y otras claves).
    @State private var newItems: [String: String] = [:]
    @State private var contentHeight: CGFloat = 0
    /// Si no es nil, el frontmatter no se puede editar con seguridad.
    @State private var limitation: LitteraDocumentProperties.EditingLimitation?
    @FocusState private var focusedField: Field?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    private var colors: LitteraPalette { LitteraPalette(scheme) }

    private enum Field: Hashable {
        case title
        case newItem(String)
        case extra(String)
    }

    private static let width: CGFloat = 400
    private static let horizontalPadding: CGFloat = 20

    /// Alto máximo de la zona desplazable: el panel cabe siempre en pantalla.
    private var maxScrollHeight: CGFloat {
        let screen = NSApp.keyWindow?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800
        return min(max(screen - 260, 240), 620)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView(.vertical) {
                fields
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.bottom, 14)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(max(contentHeight, 1), maxScrollHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

            Divider()
            tableOfContentsRow
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 14)
                .disabled(limitation != nil)
        }
        .frame(width: Self.width, alignment: .leading)
        .onAppear(perform: reload)
        .onDisappear(perform: commitPending)
        .onChange(of: focusedField) { oldValue, _ in
            // Al salir de un campo de texto se guarda lo escrito.
            switch oldValue {
            case .title: commitTitle()
            case let .extra(key): commitField(key)
            case let .newItem(key): addItems(to: key)
            case nil: break
            }
        }
    }

    private struct ContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let limitation {
                limitationNotice(limitation)
            }
            // Las propiedades gestionadas, siempre (vacías si faltan), y
            // después las demás claves del documento en su orden.
            ForEach(LitteraDocumentProperties.managedKeys, id: \.self) { key in
                managedSection(key)
            }
            ForEach(properties.otherExtras) { extra in
                extraSection(extra)
            }
        }
        .disabled(limitation != nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func managedSection(_ key: String) -> some View {
        switch key {
        case LitteraDocumentProperties.titleKey: titleSection
        case LitteraDocumentProperties.statusKey: statusSection
        case LitteraDocumentProperties.tagsKey: tagsSection
        case LitteraDocumentProperties.createdKey, LitteraDocumentProperties.updatedKey: dateSection(key)
        default: extraSection(properties.managedExtra(key))
        }
    }

    /// YAML que Littera no puede modificar sin riesgo: se muestran los
    /// valores, sin editar, y se explica por qué.
    private func limitationNotice(_ limitation: LitteraDocumentProperties.EditingLimitation) -> some View {
        let message: String
        switch limitation {
        case .unclosedFrontmatter:
            message = L10n.tr("ui.propiedad.frontmatter.sin.cerrar", locale: locale)
        case let .unsupportedYAML(line):
            message = L10n.formatted("ui.propiedad.yaml.no.editable", locale: locale, line)
        }
        return Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12))
            .foregroundStyle(colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    // MARK: - Secciones

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.primaryText)
                .accessibilityHidden(true)
            Text("ui.propiedades.del.documento")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.primaryText)
        }
    }

    private var titleSection: some View {
        section("ui.propiedad.titulo") {
            TextField("ui.propiedad.titulo.marcador", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(fieldBorder, lineWidth: 1)
                )
                .focused($focusedField, equals: .title)
                .onSubmit(commitTitle)
                .accessibilityLabel(L10n.tr("ui.propiedad.titulo", locale: locale))
        }
    }

    private var fieldBorder: Color { colors.secondaryText.opacity(0.35) }

    private var statusSection: some View {
        section("ui.propiedad.estado") {
            Menu {
                ForEach(LitteraPropertyStatus.allCases) { status in
                    Button {
                        set(LitteraDocumentProperties.statusKey, status.rawValue)
                    } label: {
                        Label(L10n.tr(status.titleKey, locale: locale), systemImage: status.symbol)
                    }
                }
                Divider()
                Button("ui.propiedad.sin.estado") {
                    set(LitteraDocumentProperties.statusKey, nil)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: properties.knownStatus?.symbol ?? "circle.dotted")
                        .font(.system(size: 15))
                        .foregroundStyle(colors.secondaryText)
                    Text(statusTitle)
                        .font(.system(size: 14))
                        .foregroundStyle(properties.status == nil ? colors.secondaryText : colors.primaryText)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L10n.tr("ui.propiedad.estado", locale: locale))
            .accessibilityValue(statusTitle)
        }
    }

    private var statusTitle: String {
        if let status = properties.knownStatus { return L10n.tr(status.titleKey, locale: locale) }
        return properties.status ?? L10n.tr("ui.propiedad.sin.estado", locale: locale)
    }

    private var tagsSection: some View {
        section("ui.propiedad.etiquetas") {
            chips(properties.tags, key: LitteraDocumentProperties.tagsKey, placeholder: "ui.propiedad.anadir.etiqueta")
        }
    }

    /// Lista editable como etiquetas: la × quita un elemento; el campo del
    /// final añade uno o varios separados por comas.
    private func chips(_ items: [String], key: String, placeholder: LocalizedStringKey) -> some View {
        LitteraFlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                chip(item) {
                    var remaining = items
                    remaining.remove(at: index)
                    setList(remaining, for: key)
                }
            }
            TextField(placeholder, text: newItemBinding(key))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 130)
                .padding(.vertical, 6)
                .focused($focusedField, equals: .newItem(key))
                .onSubmit { addItems(to: key) }
                .accessibilityLabel(Text(placeholder))
        }
    }

    private func chip(_ item: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(item)
                .font(.system(size: 13))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(colors.secondaryText)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.formatted("ui.propiedad.quitar.etiqueta", locale: locale, item))
            .accessibilityLabel(L10n.formatted("ui.propiedad.quitar.etiqueta", locale: locale, item))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: Self.width - Self.horizontalPadding * 2, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// `created` y `updated`: el valor tal cual (`AAAA-MM-DD`), editable, con
    /// la fecha larga al lado si es válida. Nunca se rellenan solas: «Usar hoy»
    /// solo aparece si faltan.
    private func dateSection(_ key: String) -> some View {
        let value = properties.dateValue(for: key)
        let title: LocalizedStringKey = key == LitteraDocumentProperties.updatedKey
            ? "ui.propiedad.fecha.de.actualizacion" : "ui.propiedad.fecha.de.creacion"
        return section(title) {
            HStack(spacing: 10) {
                TextField("ui.propiedad.fecha.marcador", text: draftBinding(key))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 110)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(fieldBorder, lineWidth: 1)
                    )
                    .focused($focusedField, equals: .extra(key))
                    .onSubmit { commitDate(key) }
                    .accessibilityLabel(Text(title))
                if let date = LitteraDocumentProperties.date(from: value) {
                    Text(date.formatted(
                        Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(colors.secondaryText)
                    .lineLimit(1)
                } else if value == nil {
                    Button("ui.propiedad.usar.hoy") {
                        set(key, LitteraDocumentProperties.dayString(from: Date()))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func commitDate(_ key: String) {
        let typed = (drafts[key] ?? "").trimmingCharacters(in: .whitespaces)
        let current = properties.dateValue(for: key) ?? ""
        guard typed != current else { return }
        // Vacío: se quita el valor; una fecha `AAAA-MM-DD` se escribe sin comillas.
        set(key, typed.isEmpty ? nil : LitteraDocumentProperties.scalar(typed))
    }

    @ViewBuilder
    private func extraSection(_ extra: LitteraDocumentProperties.Extra) -> some View {
        section(verbatim: LitteraPropertyLabels.label(for: extra.key, locale: locale), yamlKey: extra.key) {
            switch extra.kind {
            case .scalar:
                TextField("", text: draftBinding(extra))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(fieldBorder, lineWidth: 1)
                    )
                    .focused($focusedField, equals: .extra(extra.key))
                    .onSubmit { commitExtra(extra.key) }
                    .accessibilityLabel(Text(verbatim: LitteraPropertyLabels.label(for: extra.key, locale: locale)))
            case let .list(items, _):
                chips(items, key: extra.key, placeholder: "ui.propiedad.anadir.elemento")
            case .block:
                // Objetos y textos de varias líneas: YAML sin la sangría de la
                // clave. Se guarda al salir del campo.
                TextEditor(text: draftBinding(extra))
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: blockHeight(for: drafts[extra.key] ?? ""))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(fieldBorder, lineWidth: 1)
                    )
                    .focused($focusedField, equals: .extra(extra.key))
                    .accessibilityLabel(Text(verbatim: LitteraPropertyLabels.label(for: extra.key, locale: locale)))
            }
        }
    }

    /// Alto del editor de YAML: todas sus líneas, sin barra de desplazamiento propia.
    private func blockHeight(for text: String) -> CGFloat {
        let lines = max(text.components(separatedBy: "\n").count, 2)
        return CGFloat(lines) * 16 + 4
    }

    private var tableOfContentsRow: some View {
        Button {
            set(LitteraDocumentProperties.tocKey, properties.toc ? "false" : "true")
        } label: {
            HStack {
                Text("ui.propiedad.generar.indice")
                    .font(.system(size: 14))
                    .foregroundStyle(colors.secondaryText)
                Spacer(minLength: 12)
                Image(systemName: properties.toc ? "checkmark.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(properties.toc ? Color.green : colors.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("ui.propiedad.generar.indice", locale: locale))
        .accessibilityValue(L10n.tr(properties.toc ? "ui.activado" : "ui.desactivado", locale: locale))
        .help(L10n.tr("ui.propiedad.generar.indice.detalle", locale: locale))
    }

    private func section<Content: View>(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey)
                .font(.system(size: 12))
                .foregroundStyle(colors.secondaryText)
            content()
        }
    }

    /// Sección de otra clave: nombre traducido; la clave real del YAML se
    /// ve como ayuda al pasar el puntero (D55).
    private func section<Content: View>(
        verbatim title: String,
        yamlKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.system(size: 12))
                .foregroundStyle(colors.secondaryText)
                .help(yamlKey)
            content()
        }
    }

    // MARK: - Cambios

    private func reload() {
        let markdown = currentMarkdown()
        properties = LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: markdown))
        limitation = LitteraDocumentProperties.editingLimitation(in: markdown)
        if focusedField != .title { title = properties.title }
        var updated: [String: String] = [:]
        for extra in properties.panelExtras {
            if case let .extra(key) = focusedField, key == extra.key, let draft = drafts[key] {
                updated[key] = draft
                continue
            }
            switch extra.kind {
            case let .scalar(text, _): updated[extra.key] = text
            case let .block(text, _, _): updated[extra.key] = text
            case .list: break
            }
        }
        for key in [LitteraDocumentProperties.createdKey, LitteraDocumentProperties.updatedKey] {
            if case let .extra(focused) = focusedField, focused == key, let draft = drafts[key] {
                updated[key] = draft
            } else {
                updated[key] = properties.dateValue(for: key) ?? ""
            }
        }
        drafts = updated
    }

    private func set(_ key: String, _ value: String?) {
        setProperty(key, value)
        reload()
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != properties.title else { return }
        set(LitteraDocumentProperties.titleKey, LitteraDocumentProperties.scalar(trimmed))
    }

    private func newItemBinding(_ key: String) -> Binding<String> {
        Binding(get: { newItems[key] ?? "" }, set: { newItems[key] = $0 })
    }

    private func currentList(for key: String) -> [String]? {
        if key == LitteraDocumentProperties.tagsKey { return properties.tags }
        guard let extra = properties.panelExtras.first(where: { $0.key == key }),
              case let .list(items, _) = extra.kind else { return nil }
        return items
    }

    private func addItems(to key: String) {
        let typed = newItems[key] ?? ""
        newItems[key] = ""
        guard let current = currentList(for: key) else { return }
        var result = current
        for item in typed.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        where !item.isEmpty && !result.contains(item) {
            result.append(item)
        }
        guard result != current else { return }
        setList(result, for: key)
    }

    private func setList(_ items: [String], for key: String) {
        if key == LitteraDocumentProperties.tagsKey {
            set(key, properties.tagsYAMLValue(items))
        } else if let extra = properties.panelExtras.first(where: { $0.key == key }) {
            set(key, extra.yamlValue(list: items))
        }
    }

    private func draftBinding(_ extra: LitteraDocumentProperties.Extra) -> Binding<String> {
        Binding(
            get: { drafts[extra.key] ?? "" },
            set: { drafts[extra.key] = $0 }
        )
    }

    private func draftBinding(_ key: String) -> Binding<String> {
        Binding(get: { drafts[key] ?? "" }, set: { drafts[key] = $0 })
    }

    private func commitExtra(_ key: String) {
        guard let draft = drafts[key],
              let extra = properties.panelExtras.first(where: { $0.key == key }) else { return }
        switch extra.kind {
        case let .scalar(text, _):
            let trimmed = draft.trimmingCharacters(in: .whitespaces)
            guard trimmed != text else { return }
            set(key, extra.yamlValue(scalar: trimmed))
        case let .block(text, _, _):
            guard draft != text else { return }
            set(key, extra.yamlValue(block: draft))
        case .list:
            break
        }
    }

    private func commitField(_ key: String) {
        if key == LitteraDocumentProperties.createdKey || key == LitteraDocumentProperties.updatedKey {
            commitDate(key)
        } else {
            commitExtra(key)
        }
    }

    private func commitPending() {
        commitTitle()
        switch focusedField {
        case let .extra(key): commitField(key)
        case let .newItem(key): addItems(to: key)
        default: break
        }
    }
}

/// Coloca las vistas en filas y salta de línea cuando no caben (etiquetas).
struct LitteraFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
