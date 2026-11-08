import CoreGraphics
import Foundation
import Markdown

/// SVG en línea para la exportación HTML, con la misma geometría que la Vista
/// previa. Los colores vienen de las variables CSS de la página exportada
/// (`--bg`, `--muted`, `--text`, `--block`), así que siguen el tema claro u
/// oscuro del lector.
nonisolated enum LitteraMermaidSVG {
    static func figure(for layout: LitteraMermaidLayout) -> String {
        let width = format(layout.size.width)
        let height = format(layout.size.height)
        let description = layout.nodes
            .map { $0.label.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: ", ")
        var svg = """
        <figure class="mermaid">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" width="\(width)" height="\(height)" role="img" aria-label="\(escape(description))">

        """

        for edge in layout.edges {
            let dash = LitteraMermaidGeometry.dashPattern(edge.style).map(format).joined(separator: " ")
            svg += "<path class=\"edge\" d=\"\(LitteraMermaidGeometry.svgPathData(LitteraMermaidGeometry.edgePath(edge)))\""
            svg += " stroke-width=\"\(format(LitteraMermaidGeometry.strokeWidth(edge.style)))\""
            if !dash.isEmpty { svg += " stroke-dasharray=\"\(dash)\"" }
            svg += "/>\n"
            let arrows = LitteraMermaidGeometry.arrowHeads(edge)
            if !arrows.isEmpty {
                svg += "<path class=\"arrow\" d=\"\(LitteraMermaidGeometry.svgPathData(arrows))\"/>\n"
            }
        }

        for node in layout.nodes {
            let paths = LitteraMermaidGeometry.nodePaths(node)
            svg += "<path class=\"node\" d=\"\(LitteraMermaidGeometry.svgPathData(paths.fill))\"/>\n"
            if paths.stroke !== paths.fill {
                svg += "<path class=\"node-detail\" d=\"\(LitteraMermaidGeometry.svgPathData(paths.stroke))\"/>\n"
            }
            svg += text(
                node.label,
                center: LitteraMermaidGeometry.textCenter(node),
                fontSize: LitteraMermaidLayout.Metrics.nodeFontSize,
                className: "node-text"
            )
        }

        for edge in layout.edges {
            guard let label = edge.label, let frame = edge.labelFrame else { continue }
            svg += "<rect class=\"edge-label\" x=\"\(format(frame.minX))\" y=\"\(format(frame.minY))\""
            svg += " width=\"\(format(frame.width))\" height=\"\(format(frame.height))\" rx=\"4\"/>\n"
            svg += text(
                label,
                center: CGPoint(x: frame.midX, y: frame.midY),
                fontSize: LitteraMermaidLayout.Metrics.labelFontSize,
                className: "edge-text"
            )
        }

        svg += "</svg>\n</figure>\n"
        return svg
    }

    /// Una `<tspan>` por línea, centradas como en la Vista previa.
    private static func text(_ value: String, center: CGPoint, fontSize: CGFloat, className: String) -> String {
        let lines = value.components(separatedBy: "\n")
        let lineHeight = LitteraMermaidGeometry.lineHeight(fontSize: fontSize)
        let top = center.y - lineHeight * CGFloat(lines.count) / 2
        var result = "<text class=\"\(className)\" text-anchor=\"middle\" dominant-baseline=\"central\" font-size=\"\(format(fontSize))\">"
        for (index, line) in lines.enumerated() {
            let y = top + lineHeight * (CGFloat(index) + 0.5)
            result += "<tspan x=\"\(format(center.x))\" y=\"\(format(y))\">\(escape(line))</tspan>"
        }
        return result + "</text>\n"
    }

    private static func format(_ value: CGFloat) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(rounded))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Estilos del SVG, añadidos a la hoja de estilos de la exportación.
    static let stylesheet = """
    figure.mermaid { margin: 0 0 20px; padding: 16px; background: var(--block); border: 1px solid var(--line); border-radius: 10px; text-align: center; }
    figure.mermaid svg { max-width: 100%; height: auto; }
    figure.mermaid .edge { fill: none; stroke: var(--accent); stroke-linecap: round; }
    figure.mermaid .arrow { fill: var(--accent); }
    figure.mermaid .node { fill: var(--bg); stroke: var(--muted); stroke-opacity: .55; stroke-width: 1; }
    figure.mermaid .node-detail { fill: none; stroke: var(--muted); stroke-opacity: .55; stroke-width: 1; }
    figure.mermaid .edge-label { fill: var(--block); }
    figure.mermaid text { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; fill: var(--text); }
    figure.mermaid .edge-text { fill-opacity: .8; }
    """
}
