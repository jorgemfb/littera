import AppKit
import Foundation
import Markdown
import SwiftUI

/// Representación derivada del AST que puede consumir la vista previa sin
/// conocer el almacenamiento ni volver a interpretar Markdown.
nonisolated struct LitteraMarkdownRenderDocument: Equatable, Sendable {
    let blocks: [LitteraMarkdownRenderBlock]

    static let empty = Self(blocks: [])
}

nonisolated struct LitteraMarkdownRenderBlock: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading(level: Int, content: [LitteraMarkdownRenderInline])
        case paragraph(content: [LitteraMarkdownRenderInline])
        /// Bloque de código con su lenguaje (del fence) y el resaltado calculado
        /// durante el análisis, fuera del hilo principal.
        case codeBlock(language: String?, code: String, highlights: [LitteraSyntaxToken])
        /// Bloque ```mermaid: diagrama de flujo ya dispuesto o, si no se puede
        /// dibujar, el motivo y el código resaltado (D48).
        case mermaid(code: String, diagram: LitteraMermaidDiagram, highlights: [LitteraSyntaxToken])
        case unorderedList(items: [LitteraMarkdownRenderListItem])
        case orderedList(start: Int, items: [LitteraMarkdownRenderListItem])
        case blockQuote([LitteraMarkdownRenderBlock])
        case thematicBreak
        /// Índice generado con los encabezados (`toc: true` en el frontmatter, D53).
        case tableOfContents([LitteraTableOfContentsEntry])
        /// Tabla GFM: alineación por columna, cabecera y filas de celdas inline.
        case table(
            alignments: [LitteraTableAlignment],
            header: [[LitteraMarkdownRenderInline]],
            rows: [[[LitteraMarkdownRenderInline]]]
        )
    }

    let id: String
    let sourceRange: LitteraMarkdownSourceRange?
    let kind: Kind
}

nonisolated extension LitteraMarkdownRenderBlock {
    /// Igualdad de lo que muestra la Vista previa: identificador y contenido,
    /// sin los rangos de origen (tampoco los de los bloques anidados en citas
    /// y listas), que cambian con cualquier edición anterior al bloque.
    func rendersSame(as other: Self) -> Bool {
        id == other.id && Self.rendersSame(kind, other.kind)
    }

    private static func rendersSame(_ lhs: Kind, _ rhs: Kind) -> Bool {
        switch (lhs, rhs) {
        case let (.blockQuote(left), .blockQuote(right)):
            return rendersSame(left, right)
        case let (.unorderedList(left), .unorderedList(right)):
            return rendersSame(left, right)
        case let (.orderedList(leftStart, left), .orderedList(rightStart, right)):
            return leftStart == rightStart && rendersSame(left, right)
        default:
            return lhs == rhs
        }
    }

    private static func rendersSame(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.rendersSame(as: $1) }
    }

    private static func rendersSame(_ lhs: [LitteraMarkdownRenderListItem], _ rhs: [LitteraMarkdownRenderListItem]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id && left.index == right.index && left.checkbox == right.checkbox
                && rendersSame(left.blocks, right.blocks)
        }
    }
}

nonisolated extension LitteraMarkdownRenderInline {
    var isImage: Bool {
        if case .image = kind { return true }
        return false
    }

    /// Texto plano de una secuencia inline (texto alternativo de imágenes).
    static func plainText(_ inlines: [LitteraMarkdownRenderInline]) -> String {
        inlines.map { inline in
            switch inline.kind {
            case let .text(value), let .inlineCode(value): value
            case let .strong(children), let .emphasis(children), let .strikethrough(children):
                plainText(children)
            case let .link(_, label): plainText(label)
            case let .image(_, alt): plainText(alt)
            }
        }.joined()
    }
}

/// Entrada del índice: enlaza con el bloque del encabezado.
nonisolated struct LitteraTableOfContentsEntry: Identifiable, Equatable, Sendable {
    let blockID: String
    let level: Int
    let title: String
    var id: String { blockID }
}

nonisolated enum LitteraTableAlignment: Sendable, Equatable {
    case leading, center, trailing
}

nonisolated struct LitteraMarkdownRenderListItem: Identifiable, Equatable, Sendable {
    let id: String
    let index: Int
    /// Lista de tareas GFM: `true` marcada, `false` sin marcar, `nil` si no es tarea.
    var checkbox: Bool? = nil
    let blocks: [LitteraMarkdownRenderBlock]
}

nonisolated struct LitteraMarkdownRenderInline: Identifiable, Equatable, Sendable {
    indirect enum Kind: Equatable, Sendable {
        case text(String)
        case strong([LitteraMarkdownRenderInline])
        case emphasis([LitteraMarkdownRenderInline])
        case strikethrough([LitteraMarkdownRenderInline])
        case inlineCode(String)
        case link(destination: String?, label: [LitteraMarkdownRenderInline])
        /// Imagen: ruta tal como aparece en el Markdown y texto alternativo.
        case image(source: String?, alt: [LitteraMarkdownRenderInline])
    }

    let id: String
    let kind: Kind
}

struct LitteraMarkdownBlockFramePreferenceKey: PreferenceKey {
    static let coordinateSpace = "littera.preview.content"
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Convierte exclusivamente nodos soportados del AST de swift-markdown.
/// Nunca modifica la cadena Markdown original ni el árbol recibido.
nonisolated struct LitteraMarkdownRenderer {
    func render(_ result: LitteraMarkdownParseResult) -> LitteraMarkdownRenderDocument {
        var blocks = renderBlocks(result.ast.children, path: "block", source: LitteraMarkdownSourceIndex(result.source))
        if LitteraDocumentProperties(frontmatter: result.frontmatter).toc {
            let entries = Self.tableOfContents(for: blocks)
            if !entries.isEmpty {
                blocks.insert(LitteraMarkdownRenderBlock(id: Self.tableOfContentsID, sourceRange: nil, kind: .tableOfContents(entries)), at: 0)
            }
        }
        return LitteraMarkdownRenderDocument(blocks: blocks)
    }

    static let tableOfContentsID = "toc"
    /// Niveles que entran en el índice.
    static let tableOfContentsLevels = 1...3

    /// Encabezados de primer nivel del documento (no los de citas o listas).
    static func tableOfContents(for blocks: [LitteraMarkdownRenderBlock]) -> [LitteraTableOfContentsEntry] {
        blocks.compactMap { block in
            guard case let .heading(level, content) = block.kind, tableOfContentsLevels.contains(level) else { return nil }
            let title = LitteraMarkdownRenderInline.plainText(content).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : LitteraTableOfContentsEntry(blockID: block.id, level: level, title: title)
        }
    }

    private func renderBlocks(
        _ children: some Sequence<Markdown.Markup>,
        path: String,
        source: LitteraMarkdownSourceIndex
    ) -> [LitteraMarkdownRenderBlock] {
        children.enumerated().compactMap { offset, child in
            renderBlock(child, id: "\(path).\(offset)", source: source)
        }
    }

    private func renderBlock(
        _ markup: Markdown.Markup,
        id: String,
        source: LitteraMarkdownSourceIndex
    ) -> LitteraMarkdownRenderBlock? {
        if let heading = markup as? Markdown.Heading {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .heading(
                    level: min(max(heading.level, 1), 6),
                    content: renderInlines(heading.children, path: "\(id).inline")
                )
            )
        }

        if let paragraph = markup as? Markdown.Paragraph {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .paragraph(
                    content: renderInlines(paragraph.children, path: "\(id).inline")
                )
            )
        }

        if let codeBlock = markup as? Markdown.CodeBlock, LitteraMermaidParser.isMermaid(codeBlock.language) {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .mermaid(
                    code: codeBlock.code,
                    diagram: LitteraMermaidDiagram.make(code: codeBlock.code),
                    highlights: LitteraSyntaxHighlighter.tokens(for: codeBlock.code, language: codeBlock.language)
                )
            )
        }

        if let codeBlock = markup as? Markdown.CodeBlock {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .codeBlock(
                    language: codeBlock.language.flatMap { $0.isEmpty ? nil : $0 },
                    code: codeBlock.code,
                    highlights: LitteraSyntaxHighlighter.tokens(for: codeBlock.code, language: codeBlock.language)
                )
            )
        }

        if let unorderedList = markup as? Markdown.UnorderedList {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .unorderedList(
                    items: renderListItems(unorderedList.children, path: "\(id).item", source: source)
                )
            )
        }

        if let orderedList = markup as? Markdown.OrderedList {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .orderedList(
                    start: Int(orderedList.startIndex),
                    items: renderListItems(orderedList.children, path: "\(id).item", source: source)
                )
            )
        }

        if let blockQuote = markup as? Markdown.BlockQuote {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .blockQuote(renderBlocks(blockQuote.children, path: "\(id).quote", source: source))
            )
        }

        if let table = markup as? Markdown.Table {
            let alignments: [LitteraTableAlignment] = table.columnAlignments.map { alignment in
                switch alignment {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
            }
            let header = table.head.children.enumerated().map { column, cell in
                renderInlines(cell.children, path: "\(id).head.\(column)")
            }
            let rows = table.body.rows.enumerated().map { row, tableRow in
                tableRow.children.enumerated().map { column, cell in
                    renderInlines(cell.children, path: "\(id).row.\(row).\(column)")
                }
            }
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .table(alignments: alignments, header: header, rows: rows)
            )
        }

        if markup is Markdown.ThematicBreak {
            return LitteraMarkdownRenderBlock(
                id: id,
                sourceRange: LitteraMarkdownSourceRange(sourceRange: markup.range, source: source),
                kind: .thematicBreak
            )
        }

        return nil
    }

    private func renderListItems(
        _ children: some Sequence<Markdown.Markup>,
        path: String,
        source: LitteraMarkdownSourceIndex
    ) -> [LitteraMarkdownRenderListItem] {
        children.enumerated().compactMap { offset, child in
            guard let item = child as? Markdown.ListItem else { return nil }
            return LitteraMarkdownRenderListItem(
                id: "\(path).\(offset)",
                index: offset,
                checkbox: item.checkbox.map { $0 == .checked },
                blocks: renderBlocks(item.children, path: "\(path).\(offset).block", source: source)
            )
        }
    }

    private func renderInlines(
        _ children: some Sequence<Markdown.Markup>,
        path: String
    ) -> [LitteraMarkdownRenderInline] {
        children.enumerated().compactMap { offset, child in
            renderInline(child, id: "\(path).\(offset)")
        }
    }

    private func renderInline(
        _ markup: Markdown.Markup,
        id: String
    ) -> LitteraMarkdownRenderInline? {
        if let text = markup as? Markdown.Text {
            return LitteraMarkdownRenderInline(id: id, kind: .text(text.string))
        }

        if let inlineCode = markup as? Markdown.InlineCode {
            return LitteraMarkdownRenderInline(id: id, kind: .inlineCode(inlineCode.code))
        }

        if let strong = markup as? Markdown.Strong {
            return LitteraMarkdownRenderInline(
                id: id,
                kind: .strong(renderInlines(strong.children, path: "\(id).inline"))
            )
        }

        if let emphasis = markup as? Markdown.Emphasis {
            return LitteraMarkdownRenderInline(
                id: id,
                kind: .emphasis(renderInlines(emphasis.children, path: "\(id).inline"))
            )
        }

        if let strikethrough = markup as? Markdown.Strikethrough {
            return LitteraMarkdownRenderInline(
                id: id,
                kind: .strikethrough(renderInlines(strikethrough.children, path: "\(id).inline"))
            )
        }

        if let link = markup as? Markdown.Link {
            return LitteraMarkdownRenderInline(
                id: id,
                kind: .link(
                    destination: link.destination,
                    label: renderInlines(link.children, path: "\(id).label")
                )
            )
        }

        if let image = markup as? Markdown.Image {
            return LitteraMarkdownRenderInline(
                id: id,
                kind: .image(
                    source: image.source.flatMap { $0.isEmpty ? nil : $0 },
                    alt: renderInlines(image.children, path: "\(id).alt")
                )
            )
        }

        // CommonMark: un salto duro es un salto de línea; un salto suave (el
        // fin de línea dentro de un párrafo) se representa como un espacio.
        if markup is Markdown.LineBreak {
            return LitteraMarkdownRenderInline(id: id, kind: .text("\n"))
        }
        if markup is Markdown.SoftBreak {
            return LitteraMarkdownRenderInline(id: id, kind: .text(" "))
        }

        // HTML en línea y extensiones no se representan.
        return nil
    }
}

struct LitteraMarkdownPreviewView: View, Equatable {
    let document: LitteraMarkdownDerivedDocument?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.document === rhs.document }

    var body: some View {
        LitteraMarkdownDocumentView(document: document?.rendered ?? .empty)
    }
}

private struct LitteraMarkdownDocumentView: View {
    let document: LitteraMarkdownRenderDocument

    @Environment(\.colorScheme) private var scheme

    /// Construir todos los bloques de golpe bloqueaba el hilo principal más de
    /// medio segundo: se añaden por tandas, sin interrumpir la escritura.
    private static let blocksPerBatch = 30
    @State private var builtBlocks = blocksPerBatch

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks.prefix(builtBlocks)) { block in
                // Cada bloque es una vista Equatable: tras una edición solo se
                // recalculan los bloques cuyo contenido ha cambiado.
                LitteraMarkdownBlockView(block: block)
                    .equatable()
                    .id(block.id)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: LitteraMarkdownBlockFramePreferenceKey.self,
                                value: [block.id: proxy.frame(in: .named(LitteraMarkdownBlockFramePreferenceKey.coordinateSpace)).minY]
                            )
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
        // Los enlaces de `Text` usan el tinte: el mismo acento que antes.
        .tint(colors.accent)
        .task(id: document.blocks.count) {
            while builtBlocks < document.blocks.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                builtBlocks += Self.blocksPerBatch
            }
        }
    }
}

struct LitteraMarkdownBlockView: View, Equatable {
    let block: LitteraMarkdownRenderBlock

    @Environment(\.colorScheme) private var scheme
    @Environment(\.litteraCompletedTask) private var completedTask
    @Environment(\.litteraBodyLineSpacing) private var bodyLineSpacing

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    /// Solo lo que se dibuja: el rango de origen se desplaza en todos los
    /// bloques posteriores a cualquier edición y obligaba a recalcularlos todos
    /// (LIT-005). La vista no lo usa.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.block.rendersSame(as: rhs.block) }

    var body: some View {
        blockView(block)
    }

    /// Cita de la referencia aprobada (UI 1.0): serif en cursiva y márgenes
    /// interiores iguales arriba y abajo.
    static let quoteFontSize: CGFloat = 18

    private func blockView(_ block: LitteraMarkdownRenderBlock, inQuote: Bool = false) -> AnyView {
        switch block.kind {
        case let .heading(level, content):
            return AnyView(inlineFlow(content)
                .font(headingFont(for: level))
                .foregroundStyle(colors.primaryText)
                .tracking(level == 1 ? -0.6 : 0)
                .lineSpacing(level == 1 ? 2 : 0)
                .padding(.bottom, level == 1 ? 18 : 20))

        case let .paragraph(content) where content.contains(where: \.isImage):
            return AnyView(paragraphWithImages(content)
                .padding(.bottom, 20))

        case let .paragraph(content):
            return AnyView(inlineFlow(content)
                .font(inQuote ? .system(size: Self.quoteFontSize, design: .serif).italic() : .system(size: 16))
                .strikethrough(completedTask)
                .foregroundStyle(completedTask ? colors.secondaryText : colors.primaryText)
                .lineSpacing(bodyLineSpacing)
                .padding(.bottom, inQuote ? 0 : 20))

        case let .codeBlock(_, code, highlights):
            return AnyView(LitteraCodeBlockView(code: code, highlights: highlights)
                .padding(.bottom, 20))

        case let .mermaid(code, diagram, highlights):
            if case let .flowchart(layout) = diagram {
                return AnyView(LitteraMermaidDiagramView(layout: layout)
                    .padding(.bottom, 20))
            }
            return AnyView(LitteraMermaidNoticeView(diagram: diagram) {
                LitteraCodeBlockView(code: code, highlights: highlights)
            }
            .padding(.bottom, 20))

        case let .unorderedList(items):
            return AnyView(listView(items: items, marker: { _ in "•" }))

        case let .orderedList(start, items):
            return AnyView(listView(items: items) { item in
                "\(start + item.index)."
            })

        case let .blockQuote(blocks):
            return AnyView(HStack(alignment: .top, spacing: 17) {
                colors.accent.frame(width: 3)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { nestedBlock in
                        blockView(nestedBlock, inQuote: true)
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.secondary, in: RoundedRectangle(cornerRadius: 10))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 25))

        case let .tableOfContents(entries):
            return AnyView(LitteraTableOfContentsView(entries: entries)
                .padding(.bottom, 25))

        case let .table(alignments, header, rows):
            return AnyView(tableView(alignments: alignments, header: header, rows: rows)
                .padding(.bottom, 20))

        case .thematicBreak:
            return AnyView(colors.line
                .frame(height: 1)
                .padding(.vertical, 32))
        }
    }

    /// Tabla con el lenguaje visual de los bloques de código: contenedor
    /// redondeado con borde, cabecera sobre el color secundario y separadores.
    private func tableView(
        alignments: [LitteraTableAlignment],
        header: [[LitteraMarkdownRenderInline]],
        rows: [[[LitteraMarkdownRenderInline]]]
    ) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        func alignment(_ column: Int) -> Alignment {
            switch column < alignments.count ? alignments[column] : .leading {
            case .center: .center
            case .trailing: .trailing
            case .leading: .leading
            }
        }
        func cell(_ content: [LitteraMarkdownRenderInline], column: Int, isHeader: Bool) -> some View {
            inlineFlow(content)
                .font(.system(size: 15, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(colors.primaryText)
                .lineSpacing(4)
                .multilineTextAlignment(alignment(column) == .trailing ? .trailing : alignment(column) == .center ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: alignment(column))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { column in
                    cell(column < header.count ? header[column] : [], column: column, isHeader: true)
                }
            }
            .background(colors.secondary)
            ForEach(rows.indices, id: \.self) { row in
                colors.line.frame(height: 1).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(column < rows[row].count ? rows[row][column] : [], column: column, isHeader: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Párrafo que contiene imágenes: el texto se agrupa en tramos y cada
    /// imagen ocupa su propia línea, a la anchura de la columna.
    private func paragraphWithImages(_ content: [LitteraMarkdownRenderInline]) -> some View {
        var segments: [ParagraphSegment] = []
        var pending: [LitteraMarkdownRenderInline] = []
        func flushText() {
            let hasText = pending.contains { inline in
                if case let .text(value) = inline.kind {
                    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return true
            }
            if hasText, let first = pending.first {
                segments.append(.text(id: first.id, content: pending))
            }
            pending = []
        }
        for inline in content {
            if case let .image(source, alt) = inline.kind {
                flushText()
                segments.append(.image(id: inline.id, source: source, alt: LitteraMarkdownRenderInline.plainText(alt)))
            } else {
                pending.append(inline)
            }
        }
        flushText()

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(segments) { segment in
                switch segment {
                case let .text(_, content):
                    inlineFlow(content)
                        .font(.system(size: 16))
                        .foregroundStyle(colors.primaryText)
                        .lineSpacing(bodyLineSpacing)
                case let .image(_, source, alt):
                    LitteraMarkdownImageView(source: source, alt: alt)
                }
            }
        }
    }

    private enum ParagraphSegment: Identifiable {
        case text(id: String, content: [LitteraMarkdownRenderInline])
        case image(id: String, source: String?, alt: String)

        var id: String {
            switch self {
            case let .text(id, _), let .image(id, _, _): id
            }
        }
    }

    @ViewBuilder
    private func listView(
        items: [LitteraMarkdownRenderListItem],
        marker: @escaping (LitteraMarkdownRenderListItem) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // Casilla de UI 1.0.0 para listas de tareas; marcador de
                    // texto para el resto.
                    if let checked = item.checkbox {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(checked ? colors.accent : colors.secondaryText)
                            .frame(minWidth: 22, alignment: .trailing)
                            .accessibilityLabel(checked ? "ui.tarea.completada" : "ui.tarea.pendiente")
                    } else {
                        SwiftUI.Text(marker(item))
                            .font(.system(size: 16))
                            .foregroundStyle(colors.secondaryText)
                            .frame(minWidth: 22, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        // Vistas hijas: leen el entorno de su elemento de lista.
                        ForEach(item.blocks) { block in
                            LitteraMarkdownBlockView(block: block)
                        }
                    }
                    // Tarea completada: tachada y atenuada, como en UI 1.0.0.
                    .environment(\.litteraCompletedTask, item.checkbox == true)
                }
            }
        }
        .padding(.bottom, 20)
    }

    /// Un bloque de texto inline es un único `Text`: la negrita, la cursiva,
    /// el código y los enlaces fluyen y se ajustan como un solo párrafo.
    private func inlineFlow(_ content: [LitteraMarkdownRenderInline]) -> SwiftUI.Text {
        SwiftUI.Text(attributedText(content, style: InlineStyle()))
    }

    private struct InlineStyle {
        var intent: InlinePresentationIntent = []
        var link: URL?
    }

    private func attributedText(
        _ content: [LitteraMarkdownRenderInline],
        style: InlineStyle
    ) -> AttributedString {
        var result = AttributedString()
        for inline in content {
            switch inline.kind {
            case let .text(value):
                result += styledRun(value, style: style)

            case let .strong(children):
                var nested = style
                nested.intent.insert(.stronglyEmphasized)
                result += attributedText(children, style: nested)

            case let .emphasis(children):
                var nested = style
                nested.intent.insert(.emphasized)
                result += attributedText(children, style: nested)

            case let .strikethrough(children):
                var nested = style
                nested.intent.insert(.strikethrough)
                result += attributedText(children, style: nested)

            case let .inlineCode(code):
                var nested = style
                nested.intent.insert(.code)
                var run = styledRun(code, style: nested)
                run.backgroundColor = colors.secondary
                result += run

            case let .link(destination, label):
                var nested = style
                // Solo esquemas seguros; el resto se muestra como texto.
                nested.link = safeLinkURL(destination) ?? style.link
                result += attributedText(label, style: nested)

            case let .image(_, alt):
                // Dentro de un texto (encabezado, enlace) se muestra su texto alternativo.
                result += attributedText(alt, style: style)
            }
        }
        return result
    }

    private func styledRun(_ value: String, style: InlineStyle) -> AttributedString {
        var run = AttributedString(value)
        if !style.intent.isEmpty {
            run.inlinePresentationIntent = style.intent
        }
        if let link = style.link {
            run.link = link
            run.foregroundColor = colors.accent
            run.underlineStyle = .single
        }
        return run
    }

    private func safeLinkURL(_ destination: String?) -> URL? {
        guard let destination,
              let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }
        return url
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .system(size: 34, weight: .bold, design: .serif)
        case 2: .system(size: 27, weight: .semibold, design: .serif)
        case 3: .system(size: 23, weight: .semibold, design: .serif)
        case 4: .system(size: 20, weight: .semibold, design: .serif)
        case 5: .system(size: 18, weight: .semibold, design: .serif)
        default: .system(size: 16, weight: .semibold, design: .serif)
        }
    }
}

private struct LitteraCompletedTaskKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LitteraOpenBlockKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

extension EnvironmentValues {
    /// Desplaza la Vista previa hasta un bloque (entradas del índice).
    var litteraOpenBlock: (@MainActor (String) -> Void)? {
        get { self[LitteraOpenBlockKey.self] }
        set { self[LitteraOpenBlockKey.self] = newValue }
    }
}

/// Índice del documento: contenedor de los bloques de código, título y una
/// entrada por encabezado, sangrada por nivel. En la Vista previa cada
/// entrada lleva a su encabezado; en el PDF es texto.
private struct LitteraTableOfContentsView: View {
    let entries: [LitteraTableOfContentsEntry]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @Environment(\.litteraOpenBlock) private var openBlock
    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        let topLevel = entries.map(\.level).min() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Text(L10n.tr("ui.indice", locale: locale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.secondaryText)
                .textCase(.uppercase)
                .padding(.bottom, 2)
            ForEach(entries) { entry in
                Button {
                    openBlock?(entry.blockID)
                } label: {
                    SwiftUI.Text(entry.title)
                        .font(.system(size: 15, weight: entry.level == topLevel ? .medium : .regular))
                        .foregroundStyle(entry.level == topLevel ? colors.primaryText : colors.secondaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(entry.level - topLevel) * 18)
                .help(entry.title)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("ui.indice", locale: locale))
    }
}

private extension EnvironmentValues {
    var litteraCompletedTask: Bool {
        get { self[LitteraCompletedTaskKey.self] }
        set { self[LitteraCompletedTaskKey.self] = newValue }
    }
}

/// Bloque de código de la Vista previa: mismo contenedor que UI 1.0.0, con
/// resaltado de sintaxis y botón Copiar.
private struct LitteraCodeBlockView: View {
    let code: String
    let highlights: [LitteraSyntaxToken]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @State private var copied = false
    @State private var resetCopied: DispatchWorkItem?

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        // El salto final del bloque no forma parte del contenido visible.
        SwiftUI.Text(highlightedCode)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(colors.primaryText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .padding(.trailing, 64)
            .background(colors.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line, lineWidth: 1))
            .overlay(alignment: .topTrailing) { copyButton }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var copyButton: some View {
        Button(action: copy) {
            Text(L10n.tr(copied ? "ui.copiado" : "ui.copiar", locale: locale))
                .font(.system(size: 12))
                .foregroundStyle(colors.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(colors.canvas, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .help(L10n.tr("ui.copiar.codigo", locale: locale))
    }

    private var displayedCode: String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    private var highlightedCode: AttributedString {
        let visible = displayedCode
        var result = AttributedString(visible)
        let syntax = LitteraSyntaxPalette(scheme)
        let length = (visible as NSString).length
        for token in highlights {
            let range = NSIntersectionRange(token.range, NSRange(location: 0, length: length))
            guard range.length > 0,
                  let stringRange = Range(range, in: visible),
                  let attributedRange = Range(stringRange, in: result) else { continue }
            result[attributedRange].foregroundColor = syntax.color(for: token.kind)
        }
        return result
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(displayedCode, forType: .string)
        copied = true
        resetCopied?.cancel()
        let work = DispatchWorkItem { copied = false }
        resetCopied = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

extension EnvironmentValues {
    /// Interlineado del texto en la Vista previa (Ajustes → Editor).
    @Entry var litteraBodyLineSpacing: CGFloat = LitteraLineSpacing.normal.bodySpacing
}
