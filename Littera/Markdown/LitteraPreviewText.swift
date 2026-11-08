import AppKit
import SwiftUI

/// Vista previa con TextKit: el documento analizado se convierte en un único
/// texto con atributos que muestra una `NSTextView` de solo lectura. Sustituye
/// a las miles de vistas de SwiftUI, cuya memoria crecía unos 6 MB por KB de
/// Markdown. Mismas tipografías y espaciados que `LitteraMarkdownBlockView`,
/// que sigue sirviendo para el PDF.

extension NSAttributedString.Key {
    /// Tarjeta, cita o separador que el layout manager dibuja detrás del texto.
    static let litteraPreviewDecoration = NSAttributedString.Key("LitteraPreviewDecoration")
}

/// Decoración de un bloque. Dos tramos solo se funden si son el mismo bloque.
final class LitteraPreviewDecoration: NSObject {
    enum Kind: Equatable { case card, quote, rule }

    let id: String
    let kind: Kind
    /// Margen interior que el espaciado de párrafo ya reserva arriba y abajo.
    let padding: CGFloat

    init(id: String, kind: Kind, padding: CGFloat) {
        self.id = id
        self.kind = kind
        self.padding = padding
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? LitteraPreviewDecoration else { return false }
        return other.id == id && other.kind == kind
    }

    override var hash: Int { id.hashValue }
}

struct LitteraPreviewTextStyle: Equatable {
    var scheme: ColorScheme
    var bodyLineSpacing: CGFloat
    var locale: Locale
}

/// Resultado de una imagen local al construir la Vista previa.
enum LitteraPreviewImageState {
    case image(NSImage)
    case needsAccess(URL)
    case notFound
    case remote
    case unsavedDocument
}

@MainActor
struct LitteraPreviewTextBuilder {
    static let blockLinkScheme = "littera-block"
    static let imageAccessScheme = "littera-image-access"

    struct Result {
        let text: NSAttributedString
        /// Rango de cada bloque superior, para las posiciones de lectura.
        let blockRanges: [(id: String, range: NSRange)]
        /// Bloques de código y su texto, para copiarlos.
        let codeBlocks: [(range: NSRange, code: String)]
    }

    private let style: LitteraPreviewTextStyle
    private let colors: LitteraPalette
    private let imageState: (String?) -> LitteraPreviewImageState
    private let output = NSMutableAttributedString()
    private var blockRanges: [(id: String, range: NSRange)] = []
    private var codeBlocks: [(range: NSRange, code: String)] = []

    init(style: LitteraPreviewTextStyle, imageState: @escaping (String?) -> LitteraPreviewImageState) {
        self.style = style
        self.colors = LitteraPalette(style.scheme)
        self.imageState = imageState
    }

    static func build(
        _ document: LitteraMarkdownRenderDocument,
        style: LitteraPreviewTextStyle,
        imageState: @escaping (String?) -> LitteraPreviewImageState = { _ in .notFound }
    ) -> Result {
        var builder = LitteraPreviewTextBuilder(style: style, imageState: imageState)
        for block in document.blocks {
            let start = builder.output.length
            builder.append(block, context: Context())
            builder.blockRanges.append((block.id, NSRange(location: start, length: builder.output.length - start)))
        }
        return Result(text: builder.output, blockRanges: builder.blockRanges, codeBlocks: builder.codeBlocks)
    }

    // MARK: - Contexto

    /// Dónde está el bloque: dentro de citas, listas o tareas completadas.
    private struct Context {
        var indent: CGFloat = 0
        var tailIndent: CGFloat = 0
        var inQuote = false
        var completedTask = false
        /// Marcador de lista para el primer párrafo del elemento.
        var marker: NSAttributedString?
        /// Espacio tras el último párrafo del bloque.
        var spacingAfter: CGFloat?
    }

    // MARK: - Tipografía

    private var bodyFont: NSFont { .systemFont(ofSize: 16) }
    private var quoteFont: NSFont {
        Self.font(size: LitteraMarkdownBlockView.quoteFontSize, weight: .regular, serif: true, italic: true)
    }
    private var primary: NSColor { NSColor(colors.primaryText) }
    private var secondaryText: NSColor { NSColor(colors.secondaryText) }
    private var secondary: NSColor { NSColor(colors.secondary) }
    private var accent: NSColor { NSColor(colors.accent) }

    static func font(size: CGFloat, weight: NSFont.Weight, serif: Bool = false, italic: Bool = false) -> NSFont {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if serif, let descriptor = font.fontDescriptor.withDesign(.serif) {
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: Self.font(size: 34, weight: .bold, serif: true)
        case 2: Self.font(size: 27, weight: .semibold, serif: true)
        case 3: Self.font(size: 23, weight: .semibold, serif: true)
        case 4: Self.font(size: 20, weight: .semibold, serif: true)
        case 5: Self.font(size: 18, weight: .semibold, serif: true)
        default: Self.font(size: 16, weight: .semibold, serif: true)
        }
    }

    private func paragraphStyle(
        _ context: Context,
        spacingAfter: CGFloat,
        spacingBefore: CGFloat = 0,
        lineSpacing: CGFloat = 0,
        alignment: NSTextAlignment = .natural
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = context.indent
        paragraph.headIndent = context.indent
        paragraph.tailIndent = -context.tailIndent
        paragraph.paragraphSpacing = spacingAfter
        paragraph.paragraphSpacingBefore = spacingBefore
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        return paragraph
    }

    // MARK: - Bloques

    private mutating func append(_ block: LitteraMarkdownRenderBlock, context: Context) {
        switch block.kind {
        case let .heading(level, content):
            let text = inline(content, font: headingFont(level), color: primary)
            if level == 1 { text.addAttribute(.kern, value: -0.6, range: NSRange(location: 0, length: text.length)) }
            appendParagraph(text, style: paragraphStyle(
                context, spacingAfter: context.spacingAfter ?? (level == 1 ? 18 : 20), lineSpacing: level == 1 ? 2 : 0
            ), context: context)

        case let .paragraph(content):
            appendParagraphContent(content, context: context)

        case let .codeBlock(_, code, highlights):
            appendCode(code, highlights: highlights, id: block.id, context: context)

        case let .mermaid(code, diagram, highlights):
            appendMermaid(code: code, diagram: diagram, highlights: highlights, id: block.id, context: context)

        case let .unorderedList(items):
            appendList(items, context: context) { _ in "•" }

        case let .orderedList(start, items):
            appendList(items, context: context) { "\(start + $0.index)." }

        case let .blockQuote(blocks):
            appendQuote(blocks, id: block.id, context: context)

        case .thematicBreak:
            let rule = NSMutableAttributedString(string: "\u{00A0}", attributes: [.font: bodyFont])
            rule.addAttribute(.litteraPreviewDecoration, value: LitteraPreviewDecoration(id: block.id, kind: .rule, padding: 0),
                              range: NSRange(location: 0, length: rule.length))
            appendParagraph(rule, style: paragraphStyle(context, spacingAfter: 32, spacingBefore: 32), context: context)

        case let .tableOfContents(entries):
            appendTableOfContents(entries, id: block.id, context: context)

        case let .table(alignments, header, rows):
            appendTable(alignments: alignments, header: header, rows: rows, context: context)
        }
    }

    /// Párrafo con su salto final y, si es el primero de un elemento de
    /// lista, con el marcador delante.
    private mutating func appendParagraph(_ text: NSAttributedString, style: NSParagraphStyle, context: Context) {
        let paragraph = NSMutableAttributedString()
        var paragraphStyle = style
        if let marker = context.marker {
            paragraph.append(marker)
            paragraphStyle = Self.markerStyle(style, marker: marker)
        }
        paragraph.append(text)
        paragraph.append(NSAttributedString(string: "\n", attributes: [.font: text.length > 0
            ? (text.attribute(.font, at: max(0, text.length - 1), effectiveRange: nil) ?? bodyFont)
            : bodyFont]))
        paragraph.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: paragraph.length))
        output.append(paragraph)
    }

    /// Primera línea en el margen de la lista: tabulador derecho a 22 pt para
    /// el marcador y tabulador izquierdo donde empieza el texto.
    private static func markerStyle(_ style: NSParagraphStyle, marker: NSAttributedString) -> NSParagraphStyle {
        guard let indent = marker.attribute(.listMarkerIndent, at: 0, effectiveRange: nil) as? CGFloat,
              let mutable = style.mutableCopy() as? NSMutableParagraphStyle else { return style }
        mutable.firstLineHeadIndent = indent
        mutable.tabStops = [
            NSTextTab(textAlignment: .right, location: indent + 22),
            NSTextTab(textAlignment: .left, location: indent + 34)
        ]
        return mutable
    }

    private mutating func appendParagraphContent(_ content: [LitteraMarkdownRenderInline], context: Context) {
        let font = context.inQuote ? quoteFont : bodyFont
        var color = context.completedTask ? secondaryText : primary
        if context.inQuote { color = primary }
        let spacing = context.spacingAfter ?? (context.inQuote ? 0 : 20)

        // Las imágenes ocupan su propio párrafo, como en la Vista previa SwiftUI.
        var pending: [LitteraMarkdownRenderInline] = []
        var segments: [(text: [LitteraMarkdownRenderInline]?, image: (source: String?, alt: String)?)] = []
        func flush() {
            let hasText = pending.contains { inline in
                if case let .text(value) = inline.kind { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return true
            }
            if hasText { segments.append((pending, nil)) }
            pending = []
        }
        for inline in content {
            if case let .image(source, alt) = inline.kind {
                flush()
                segments.append((nil, (source, LitteraMarkdownRenderInline.plainText(alt))))
            } else {
                pending.append(inline)
            }
        }
        flush()
        if segments.isEmpty { segments = [([], nil)] }

        var itemContext = context
        for (index, segment) in segments.enumerated() {
            let isLast = index == segments.count - 1
            let after = isLast ? spacing : 12
            if let text = segment.text {
                let attributed = inline(text, font: font, color: color)
                if context.completedTask {
                    attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                            range: NSRange(location: 0, length: attributed.length))
                }
                appendParagraph(attributed, style: paragraphStyle(itemContext, spacingAfter: after, lineSpacing: style.bodyLineSpacing),
                                context: itemContext)
            } else if let image = segment.image {
                appendImage(source: image.source, alt: image.alt, spacingAfter: after, context: itemContext)
            }
            itemContext.marker = nil
        }
    }

    private mutating func appendCode(_ code: String, highlights: [LitteraSyntaxToken], id: String, context: Context) {
        let visible = code.hasSuffix("\n") ? String(code.dropLast()) : code
        let text = NSMutableAttributedString(string: visible, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: primary
        ])
        let syntax = LitteraSyntaxPalette(style.scheme)
        let length = text.length
        for token in highlights {
            let range = NSIntersectionRange(token.range, NSRange(location: 0, length: length))
            guard range.length > 0 else { continue }
            text.addAttribute(.foregroundColor, value: NSColor(syntax.color(for: token.kind)), range: range)
        }
        let padding: CGFloat = 16
        var inner = context
        inner.indent += padding
        inner.tailIndent += padding
        inner.marker = nil
        let start = output.length
        if let marker = context.marker { output.append(marker) }
        let paragraph = paragraphStyle(inner, spacingAfter: padding + (context.spacingAfter ?? 20), spacingBefore: padding)
        // Las líneas del código son un solo párrafo: el salto de línea interno
        // se escribe como separador de línea para que no reciba espaciado.
        let lineSeparated = NSMutableAttributedString(attributedString: text)
        lineSeparated.mutableString.replaceOccurrences(of: "\n", with: "\u{2028}", options: [], range: NSRange(location: 0, length: lineSeparated.length))
        lineSeparated.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]))
        lineSeparated.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: lineSeparated.length))
        output.append(lineSeparated)
        let range = NSRange(location: start, length: output.length - start)
        output.addAttribute(.litteraPreviewDecoration, value: LitteraPreviewDecoration(id: id, kind: .card, padding: padding), range: range)
        codeBlocks.append((range, visible))
    }

    private mutating func appendMermaid(
        code: String,
        diagram: LitteraMermaidDiagram,
        highlights: [LitteraSyntaxToken],
        id: String,
        context: Context
    ) {
        if case let .flowchart(layout) = diagram, let image = Self.renderMermaid(layout, scheme: style.scheme) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            let text = NSMutableAttributedString(attachment: attachment)
            appendParagraph(text, style: paragraphStyle(context, spacingAfter: context.spacingAfter ?? 20, alignment: .center), context: context)
            return
        }
        let notice: String?
        switch diagram {
        case let .unsupported(type): notice = L10n.formatted("ui.mermaid.no.compatible", locale: style.locale, type)
        case let .invalid(line): notice = L10n.formatted("ui.mermaid.error.linea", locale: style.locale, line)
        case .flowchart, .empty: notice = nil
        }
        var inner = context
        if let notice {
            let text = NSMutableAttributedString(string: notice, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryText])
            appendParagraph(text, style: paragraphStyle(context, spacingAfter: 8), context: context)
            inner.marker = nil
        }
        appendCode(code, highlights: highlights, id: id, context: inner)
    }

    /// Diagrama con el mismo dibujo que la Vista previa SwiftUI, como imagen.
    static func renderMermaid(_ layout: LitteraMermaidLayout, scheme: ColorScheme) -> NSImage? {
        let renderer = ImageRenderer(content: LitteraMermaidDiagramView(layout: layout)
            .frame(width: layout.size.width + 32)
            .environment(\.colorScheme, scheme))
        renderer.scale = 2
        return renderer.nsImage
    }

    private mutating func appendList(
        _ items: [LitteraMarkdownRenderListItem],
        context: Context,
        marker: (LitteraMarkdownRenderListItem) -> String
    ) {
        let markerWidth: CGFloat = 22
        let gap: CGFloat = 12
        for (itemIndex, item) in items.enumerated() {
            let isLastItem = itemIndex == items.count - 1
            var itemContext = context
            itemContext.indent = context.indent + markerWidth + gap
            itemContext.completedTask = item.checkbox == true
            itemContext.marker = listMarker(for: item, text: marker(item), context: context, markerWidth: markerWidth)
            for (blockIndex, block) in item.blocks.enumerated() {
                let isLastBlock = blockIndex == item.blocks.count - 1
                var blockContext = itemContext
                if isLastBlock {
                    blockContext.spacingAfter = isLastItem ? (context.spacingAfter ?? 20) : 10
                } else {
                    blockContext.spacingAfter = 0
                }
                append(block, context: blockContext)
                itemContext.marker = nil
            }
            if item.blocks.isEmpty {
                appendParagraph(NSAttributedString(string: ""), style: paragraphStyle(itemContext, spacingAfter: isLastItem ? 20 : 10), context: itemContext)
            }
        }
    }

    /// Marcador alineado a la derecha en una columna de 22 pt, seguido de un
    /// tabulador hasta el texto. El párrafo del elemento empieza en el margen
    /// de la lista gracias a una sangría de primera línea menor.
    private func listMarker(
        for item: LitteraMarkdownRenderListItem,
        text: String,
        context: Context,
        markerWidth: CGFloat
    ) -> NSAttributedString {
        let marker = NSMutableAttributedString()
        marker.append(NSAttributedString(string: "\t"))
        if let checked = item.checkbox,
           let symbol = NSImage(systemSymbolName: checked ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular).applying(.init(paletteColors: [checked ? accent : secondaryText]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = NSRect(x: 0, y: -3, width: symbol.size.width, height: symbol.size.height)
            marker.append(NSAttributedString(attachment: attachment))
        } else {
            marker.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: secondaryText]))
        }
        marker.append(NSAttributedString(string: "\t"))
        marker.addAttribute(.listMarkerIndent, value: context.indent, range: NSRange(location: 0, length: marker.length))
        return marker
    }

    private mutating func appendQuote(_ blocks: [LitteraMarkdownRenderBlock], id: String, context: Context) {
        let start = output.length
        let outer: CGFloat = 17
        let bar: CGFloat = 3
        let verticalPadding: CGFloat = 22 // 10 de la tarjeta + 12 del contenido
        var inner = context
        inner.indent += outer + bar + outer
        inner.tailIndent += outer
        inner.inQuote = true
        for (index, block) in blocks.enumerated() {
            var blockContext = inner
            if index > 0 { blockContext.marker = nil }
            blockContext.spacingAfter = index == blocks.count - 1 ? verticalPadding + (context.spacingAfter ?? 25) : 12
            append(block, context: blockContext)
        }
        let range = NSRange(location: start, length: output.length - start)
        guard range.length > 0 else { return }
        Self.addSpacingBefore(verticalPadding, at: start, in: output)
        output.addAttribute(.litteraPreviewDecoration, value: LitteraPreviewDecoration(id: id, kind: .quote, padding: verticalPadding), range: range)
    }

    private mutating func appendTableOfContents(_ entries: [LitteraTableOfContentsEntry], id: String, context: Context) {
        let start = output.length
        let padding: CGFloat = 16
        var inner = context
        inner.indent += 20
        inner.tailIndent += 20
        let title = NSAttributedString(string: L10n.tr("ui.indice", locale: style.locale).uppercased(with: style.locale), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: secondaryText
        ])
        appendParagraph(title, style: paragraphStyle(inner, spacingAfter: entries.isEmpty ? padding + 25 : 10, spacingBefore: padding), context: inner)
        inner.marker = nil
        let topLevel = entries.map(\.level).min() ?? 1
        for (index, entry) in entries.enumerated() {
            var entryContext = inner
            entryContext.indent += CGFloat(entry.level - topLevel) * 18
            let isTop = entry.level == topLevel
            let link = NSAttributedString(string: entry.title, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: isTop ? .medium : .regular),
                .foregroundColor: isTop ? primary : secondaryText,
                .link: URL(string: "\(Self.blockLinkScheme):\(entry.blockID)") as Any,
                .toolTip: entry.title
            ])
            let last = index == entries.count - 1
            appendParagraph(link, style: paragraphStyle(entryContext, spacingAfter: last ? padding + (context.spacingAfter ?? 25) : 8), context: entryContext)
        }
        let range = NSRange(location: start, length: output.length - start)
        output.addAttribute(.litteraPreviewDecoration, value: LitteraPreviewDecoration(id: id, kind: .card, padding: padding), range: range)
    }

    private mutating func appendTable(
        alignments: [LitteraTableAlignment],
        header: [[LitteraMarkdownRenderInline]],
        rows: [[[LitteraMarkdownRenderInline]]],
        context: Context
    ) {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.setContentWidth(100, type: .percentageValueType)
        table.collapsesBorders = true
        let line = NSColor(colors.line)
        let allRows = [header] + rows
        for (rowIndex, row) in allRows.enumerated() {
            for column in 0..<columns {
                let cellBlock = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cellBlock.setBorderColor(line)
                cellBlock.setWidth(1, type: .absoluteValueType, for: .border)
                cellBlock.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
                cellBlock.setWidth(12, type: .absoluteValueType, for: .padding, edge: .maxX)
                cellBlock.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minY)
                cellBlock.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxY)
                if rowIndex == 0 { cellBlock.backgroundColor = secondary }
                let content = column < row.count ? row[column] : []
                let text = inline(content, font: .systemFont(ofSize: 15, weight: rowIndex == 0 ? .semibold : .regular), color: primary)
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [cellBlock]
                paragraph.lineSpacing = 4
                switch column < alignments.count ? alignments[column] : .leading {
                case .center: paragraph.alignment = .center
                case .trailing: paragraph.alignment = .right
                case .leading: paragraph.alignment = .natural
                }
                let cell = NSMutableAttributedString(attributedString: text)
                cell.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
                cell.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: cell.length))
                output.append(cell)
            }
        }
        // Espacio tras la tabla: un párrafo vacío de la altura del margen.
        let spacer = NSMutableParagraphStyle()
        let gap = context.spacingAfter ?? 20
        spacer.minimumLineHeight = gap
        spacer.maximumLineHeight = gap
        output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: spacer]))
    }

    private mutating func appendImage(source: String?, alt: String, spacingAfter: CGFloat, context: Context) {
        switch imageState(source) {
        case let .image(image):
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            let text = NSMutableAttributedString(attachment: attachment)
            text.addAttribute(.toolTip, value: alt, range: NSRange(location: 0, length: text.length))
            appendParagraph(text, style: paragraphStyle(context, spacingAfter: spacingAfter), context: context)
        case let .needsAccess(url):
            appendImagePlaceholder(alt: alt, source: source, message: "ui.imagen.necesita.acceso", accessURL: url, spacingAfter: spacingAfter, context: context)
        case .notFound:
            appendImagePlaceholder(alt: alt, source: source, message: "ui.imagen.no.encontrada", accessURL: nil, spacingAfter: spacingAfter, context: context)
        case .remote:
            appendImagePlaceholder(alt: alt, source: source, message: "ui.imagen.remota", accessURL: nil, spacingAfter: spacingAfter, context: context)
        case .unsavedDocument:
            appendImagePlaceholder(alt: alt, source: source, message: "ui.imagen.sin.guardar", accessURL: nil, spacingAfter: spacingAfter, context: context)
        }
    }

    /// Tarjeta con el texto alternativo y el motivo por el que no se ve.
    private mutating func appendImagePlaceholder(
        alt: String,
        source: String?,
        message: String,
        accessURL: URL?,
        spacingAfter: CGFloat,
        context: Context
    ) {
        let padding: CGFloat = 16
        var inner = context
        inner.indent += padding
        inner.tailIndent += padding
        let start = output.length
        let text = NSMutableAttributedString()
        if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular).applying(.init(paletteColors: [secondaryText]))) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = NSRect(x: 0, y: -2, width: symbol.size.width, height: symbol.size.height)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: "  "))
        }
        let title = alt.isEmpty ? (source ?? L10n.tr("ui.imagen", locale: style.locale)) : alt
        text.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: primary]))
        text.append(NSAttributedString(string: "\u{2028}" + L10n.tr(message, locale: style.locale), attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryText
        ]))
        if let accessURL {
            text.append(NSAttributedString(string: "  ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
            text.append(NSAttributedString(string: L10n.tr("ui.imagen.permitir.acceso", locale: style.locale), attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .link: URL(string: "\(Self.imageAccessScheme):\(accessURL.path)") ?? accessURL
            ]))
        }
        appendParagraph(text, style: paragraphStyle(inner, spacingAfter: padding + spacingAfter, spacingBefore: padding), context: inner)
        let range = NSRange(location: start, length: output.length - start)
        output.addAttribute(.litteraPreviewDecoration, value: LitteraPreviewDecoration(id: "img\(start)", kind: .card, padding: padding), range: range)
    }

    // MARK: - Inline

    private func inline(_ content: [LitteraMarkdownRenderInline], font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        appendInline(content, font: font, color: color, link: nil, strikethrough: false, into: result)
        return result
    }

    private func appendInline(
        _ content: [LitteraMarkdownRenderInline],
        font: NSFont,
        color: NSColor,
        link: URL?,
        strikethrough: Bool,
        into result: NSMutableAttributedString
    ) {
        for inline in content {
            switch inline.kind {
            case let .text(value):
                result.append(run(value, font: font, color: color, link: link, strikethrough: strikethrough))
            case let .strong(children):
                appendInline(children, font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
                             color: color, link: link, strikethrough: strikethrough, into: result)
            case let .emphasis(children):
                appendInline(children, font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask),
                             color: color, link: link, strikethrough: strikethrough, into: result)
            case let .strikethrough(children):
                appendInline(children, font: font, color: color, link: link, strikethrough: true, into: result)
            case let .inlineCode(code):
                let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                let codeRun = run(code, font: mono, color: color, link: link, strikethrough: strikethrough)
                codeRun.addAttribute(.backgroundColor, value: secondary, range: NSRange(location: 0, length: codeRun.length))
                result.append(codeRun)
            case let .link(destination, label):
                appendInline(label, font: font, color: color, link: Self.safeLinkURL(destination) ?? link,
                             strikethrough: strikethrough, into: result)
            case let .image(_, alt):
                appendInline(alt, font: font, color: color, link: link, strikethrough: strikethrough, into: result)
            }
        }
    }

    private func run(_ value: String, font: NSFont, color: NSColor, link: URL?, strikethrough: Bool) -> NSMutableAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let link {
            attributes[.link] = link
            attributes[.foregroundColor] = accent
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSMutableAttributedString(string: value, attributes: attributes)
    }

    static func safeLinkURL(_ destination: String?) -> URL? {
        guard let destination,
              let url = URL(string: destination),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }

    // MARK: - Utilidades

    /// Añade espacio antes del primer párrafo de un bloque (margen superior de
    /// una tarjeta).
    private static func addSpacingBefore(_ value: CGFloat, at location: Int, in text: NSMutableAttributedString) {
        guard location < text.length,
              let current = text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
              let style = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        style.paragraphSpacingBefore += value
        let paragraph = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        text.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }
}

private extension NSAttributedString.Key {
    /// Margen de la lista en el marcador: el párrafo lo usa para su primera línea.
    static let listMarkerIndent = NSAttributedString.Key("LitteraListMarkerIndent")
}
