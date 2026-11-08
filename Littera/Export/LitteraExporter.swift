import AppKit
import Markdown
import SwiftUI
import UniformTypeIdentifiers

/// Exportación del documento activo. HTML con el conversor de swift-markdown;
/// PDF con las mismas vistas de la Vista previa, en tema claro.
@MainActor
enum LitteraExporter {
    enum Format {
        case pdf
        case html

        var contentType: UTType { self == .pdf ? .pdf : .html }
        var fileExtension: String { self == .pdf ? "pdf" : "html" }
        var titleKey: String { self == .pdf ? "ui.exportar.como.pdf" : "ui.exportar.como.html" }
    }

    /// Pide el destino y exporta. Devuelve `false` si se cancela o falla.
    @discardableResult
    static func export(
        _ document: LitteraDocumentSession,
        derived: LitteraMarkdownDerivedDocument,
        format: Format,
        locale: Locale
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = L10n.tr(format.titleKey, locale: locale)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let baseName = (document.fileName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        if let folder = document.fileURL?.deletingLastPathComponent() ?? LitteraDefaultFolder.url() {
            panel.directoryURL = folder
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            switch format {
            case .html:
                let html = html(
                    for: derived.source,
                    title: baseName,
                    tableOfContentsTitle: L10n.tr("ui.indice", locale: locale)
                )
                try Data(html.utf8).write(to: url, options: .atomic)
            case .pdf:
                let images = preloadImages(in: derived.source, documentURL: document.fileURL, locale: locale)
                try pdf(for: derived, documentURL: document.fileURL, images: images).write(to: url, options: .atomic)
            }
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.tr("ui.error.al.exportar", locale: locale)
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: L10n.tr("ui.aceptar", locale: locale))
            alert.runModal()
            return false
        }
    }

    // MARK: - HTML

    /// Página HTML autónoma. El frontmatter no se exporta; con `toc: true`
    /// se añade el índice enlazado a los encabezados (D53).
    nonisolated static func html(
        for source: String,
        title: String,
        tableOfContentsTitle: String = "Contents"
    ) -> String {
        let parsed = LitteraMarkdownParser().parse(source)
        // Texto escapado, enlaces seguros y Mermaid como SVG (1.0.4, D48).
        var rewriter = LitteraHTMLExportRewriter()
        var tableOfContents = ""
        if LitteraDocumentProperties(frontmatter: parsed.frontmatter).toc {
            let headings = linkedHeadings(in: parsed.ast)
            rewriter.headingIDs = headings.map { $0?.id }
            let items = headings.compactMap { $0 }
            if !items.isEmpty {
                tableOfContents = "<nav class=\"toc\">\n<p class=\"toc-title\">\(escape(tableOfContentsTitle))</p>\n<ul>\n"
                    + items.map { "<li class=\"toc-\($0.level)\"><a href=\"#\(escape($0.id))\">\(escape($0.title))</a></li>" }
                        .joined(separator: "\n")
                    + "\n</ul>\n</nav>\n"
            }
        }
        let body = tableOfContents + HTMLFormatter.format(rewriter.visit(parsed.ast) ?? parsed.ast)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Littera">
        <title>\(escape(title))</title>
        <style>
        \(stylesheet)
        \(LitteraMermaidSVG.stylesheet)
        </style>
        </head>
        <body>
        <main>
        \(body)
        </main>
        </body>
        </html>

        """
    }

    /// Encabezados de primer nivel del documento en orden: los que entran en
    /// el índice con su `id` único; el resto, `nil`.
    nonisolated static func linkedHeadings(in document: Markdown.Document) -> [(id: String, level: Int, title: String)?] {
        var used: Set<String> = []
        return document.children.compactMap { child -> (id: String, level: Int, title: String)?? in
            guard let heading = child as? Heading else { return nil }
            let title = heading.plainText.trimmingCharacters(in: .whitespaces)
            guard LitteraMarkdownRenderer.tableOfContentsLevels.contains(heading.level), !title.isEmpty else {
                return .some(nil)
            }
            var id = slug(for: title)
            if used.contains(id) {
                var counter = 2
                while used.contains("\(id)-\(counter)") { counter += 1 }
                id = "\(id)-\(counter)"
            }
            used.insert(id)
            return .some((id, heading.level, title))
        }
    }

    /// Identificador legible para un encabezado: minúsculas, letras y cifras,
    /// guiones en lugar de espacios.
    nonisolated static func slug(for text: String) -> String {
        var result = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
            } else if character.isWhitespace || character == "-", !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "seccion" : result
    }

    nonisolated static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Aproxima la Vista previa: mismas medidas y colores de los temas.
    nonisolated static let stylesheet = """
    :root { color-scheme: light dark; --text: #0B0B0B; --muted: #898782; --accent: #D78363; --block: #F0F0EF; --line: #E7E7E7; --bg: #FCFCFB; }
    @media (prefers-color-scheme: dark) { :root { --text: #F0EFEC; --accent: #C5785B; --block: #212121; --line: #313130; --bg: #151515; } }
    body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    main { max-width: 760px; margin: 0 auto; padding: 56px 32px 80px; }
    h1, h2, h3, h4, h5, h6 { font-family: "New York", ui-serif, Georgia, serif; line-height: 1.25; margin: 0 0 20px; }
    h1 { font-size: 34px; letter-spacing: -0.6px; } h2 { font-size: 27px; } h3 { font-size: 23px; } h4 { font-size: 20px; } h5 { font-size: 18px; } h6 { font-size: 16px; }
    p, ul, ol, pre, blockquote, table { margin: 0 0 20px; }
    a { color: var(--accent); }
    code { font: 15px ui-monospace, "SF Mono", Menlo, monospace; background: var(--block); padding: 1px 4px; border-radius: 4px; }
    pre { background: var(--block); border-radius: 10px; padding: 16px; overflow-x: auto; }
    pre code { font-size: 14px; background: none; padding: 0; }
    blockquote { margin-left: 0; padding: 12px 20px; background: var(--block); border-left: 3px solid var(--accent); border-radius: 4px; }
    blockquote p:last-child { margin-bottom: 0; }
    table { border-collapse: collapse; width: 100%; border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
    th { background: var(--block); text-align: left; }
    th, td { padding: 8px 12px; border-top: 1px solid var(--line); }
    hr { border: none; border-top: 1px solid var(--line); margin: 28px 0; }
    img { max-width: 100%; }
    li > input[type=checkbox] { margin-right: 6px; }
    nav.toc { margin: 0 0 28px; padding: 16px 20px; background: var(--block); border-radius: 10px; }
    nav.toc .toc-title { margin: 0 0 8px; font-size: 12px; font-weight: 600; text-transform: uppercase; color: var(--muted); }
    nav.toc ul { list-style: none; margin: 0; padding: 0; }
    nav.toc li { margin: 4px 0; }
    nav.toc a { color: var(--text); text-decoration: none; }
    nav.toc a:hover { color: var(--accent); }
    nav.toc .toc-2 { padding-left: 18px; } nav.toc .toc-3 { padding-left: 36px; }
    """

    // MARK: - Imágenes

    private struct ImageCollector: MarkupWalker {
        var sources: [String] = []
        mutating func visitImage(_ image: Markdown.Image) {
            if let source = image.source, !sources.contains(source) { sources.append(source) }
            descendInto(image)
        }
    }

    /// Carga las imágenes locales antes de dibujar el PDF. Si una carpeta no
    /// está autorizada, se pide acceso una vez por carpeta.
    static func preloadImages(in source: String, documentURL: URL?, locale: Locale) -> [String: NSImage] {
        var collector = ImageCollector()
        collector.visit(LitteraMarkdownParser().parse(source).ast)
        let access = LitteraLocalImageAccess.shared
        var declinedFolders: Set<String> = []
        var images: [String: NSImage] = [:]
        for imageSource in collector.sources {
            guard let url = LitteraMarkdownImageView.localFile(for: imageSource, documentURL: documentURL) else { continue }
            var result = access.loadNow(url)
            let folder = url.deletingLastPathComponent().path
            if case .needsAccess = result, !declinedFolders.contains(folder) {
                if access.requestAccess(for: url, locale: locale) {
                    result = access.loadNow(url)
                } else {
                    declinedFolders.insert(folder)
                }
            }
            if case let .image(image) = result { images[imageSource] = image }
        }
        return images
    }

    // MARK: - PDF

    static let pageSize = CGSize(width: 595, height: 842)
    static let pageMargin: CGFloat = 56

    /// PDF A4 con las vistas de la Vista previa. Los saltos de página se
    /// hacen entre bloques; un bloque más alto que la página se reparte.
    static func pdf(
        for derived: LitteraMarkdownDerivedDocument,
        documentURL: URL?,
        images: [String: NSImage] = [:]
    ) throws -> Data {
        let contentWidth = pageSize.width - pageMargin * 2
        let contentHeight = pageSize.height - pageMargin * 2
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var y: CGFloat = 0
        var pageOpen = false
        func newPage() {
            if pageOpen { context.endPDFPage() }
            context.beginPDFPage(nil)
            pageOpen = true
            y = 0
        }
        newPage()

        for block in derived.rendered.blocks {
            let renderer = ImageRenderer(content:
                LitteraMarkdownBlockView(block: block)
                    .frame(width: contentWidth, alignment: .leading)
                    .environment(\.colorScheme, .light)
                    .environment(\.litteraDocumentURL, documentURL)
                    .environment(\.litteraPreloadedImages, images)
                    .tint(LitteraPalette(.light).accent)
            )
            renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)
            renderer.render { size, draw in
                if y > 0, y + size.height > contentHeight { newPage() }
                var drawn: CGFloat = 0
                repeat {
                    let slice = min(size.height - drawn, contentHeight - y)
                    context.saveGState()
                    context.clip(to: CGRect(
                        x: pageMargin,
                        y: pageSize.height - pageMargin - y - slice,
                        width: contentWidth,
                        height: slice
                    ))
                    // Origen del bloque: su parte ya dibujada queda por encima.
                    context.translateBy(x: pageMargin, y: pageSize.height - pageMargin - y - size.height + drawn)
                    draw(context)
                    context.restoreGState()
                    drawn += slice
                    y += slice
                    if drawn < size.height { newPage() }
                } while drawn < size.height
            }
        }
        if pageOpen { context.endPDFPage() }
        context.closePDF()
        return data as Data
    }
}
