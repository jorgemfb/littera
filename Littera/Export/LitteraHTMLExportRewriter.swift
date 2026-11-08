import Foundation
import Markdown

/// Prepara el árbol de swift-markdown para `HTMLFormatter`, que copia el
/// texto tal cual (1.0.4): `a < b` rompía la página y un `<script>` dentro de
/// un bloque de código se ejecutaba al abrir el HTML. Aquí se escapa todo el
/// texto del usuario, las imágenes llevan `alt`, los enlaces siguen el mismo
/// criterio que la Vista previa y los diagramas Mermaid pasan a SVG (D48).
/// El HTML escrito a mano en el documento se conserva, como en CommonMark.
nonisolated struct LitteraHTMLExportRewriter: MarkupRewriter {
    /// `id` de cada encabezado de primer nivel del documento, en orden, para
    /// los enlaces del índice (D53); `nil` si no lleva.
    var headingIDs: [String?] = []
    private var headingIndex = 0

    mutating func visitText(_ text: Text) -> Markup? {
        InlineHTML(Self.escape(text.string))
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineHTML("<code>\(Self.escape(inlineCode.code))</code>")
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        if LitteraMermaidParser.isMermaid(codeBlock.language),
           case let .flowchart(layout) = LitteraMermaidDiagram.make(code: codeBlock.code) {
            return HTMLBlock(LitteraMermaidSVG.figure(for: layout))
        }
        let language = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }
            .map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        return HTMLBlock("<pre><code\(language)>\(Self.escape(codeBlock.code))</code></pre>\n")
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        guard var rewritten = defaultVisit(link) as? Link else { return link }
        // Sin destino seguro (javascript:, data:…), el texto queda sin enlace.
        guard let destination = Self.safeDestination(link.destination) else {
            return InlineHTML(rewritten.children.map { HTMLFormatter.format($0) }.joined())
        }
        rewritten.destination = Self.escape(destination)
        return rewritten
    }

    mutating func visitImage(_ image: Image) -> Markup? {
        var html = "<img"
        if let source = image.source, !source.isEmpty, Self.isSafeImageSource(source) {
            html += " src=\"\(Self.escape(source))\""
        }
        html += " alt=\"\(Self.escape(image.plainText))\""
        if let title = image.title, !title.isEmpty {
            html += " title=\"\(Self.escape(title))\""
        }
        return InlineHTML(html + " />")
    }

    /// `HTMLFormatter` escribe los encabezados con su texto plano: se perdían
    /// la negrita, la cursiva, el código y los enlaces de su interior.
    mutating func visitHeading(_ heading: Heading) -> Markup? {
        guard let rewritten = defaultVisit(heading) as? Heading else { return heading }
        let level = min(max(heading.level, 1), 6)
        let content = rewritten.children.map { HTMLFormatter.format($0) }.joined()
        var identifier = ""
        if heading.parent is Document {
            if headingIndex < headingIDs.count, let id = headingIDs[headingIndex] {
                identifier = " id=\"\(Self.escape(id))\""
            }
            headingIndex += 1
        }
        return HTMLBlock("<h\(level)\(identifier)>\(content)</h\(level)>\n")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Esquemas http, https y mailto, como en la Vista previa, y rutas
    /// relativas o anclas dentro del documento.
    static func safeDestination(_ destination: String?) -> String? {
        guard let destination, !destination.isEmpty else { return nil }
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else {
            return destination.contains(":") ? nil : destination
        }
        return ["http", "https", "mailto"].contains(scheme) ? destination : nil
    }

    private static func isSafeImageSource(_ source: String) -> Bool {
        guard let scheme = URL(string: source)?.scheme?.lowercased() else { return !source.contains(":") }
        return ["http", "https", "file"].contains(scheme)
    }
}
