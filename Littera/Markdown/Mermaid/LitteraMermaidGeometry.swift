import CoreGraphics
import CoreText
import Foundation

/// Formas de nodos, aristas y puntas de flecha como `CGPath`. Las comparten la
/// Vista previa, el PDF y el SVG de la exportación HTML, para que los tres
/// dibujen exactamente lo mismo.
nonisolated enum LitteraMermaidGeometry {
    struct NodePaths {
        /// Silueta que se rellena.
        let fill: CGPath
        /// Silueta más los detalles interiores (borde del cilindro, barras
        /// de la subrutina).
        let stroke: CGPath
    }

    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        LitteraMermaidLayout.measureText("Hg", fontSize: fontSize).height
    }

    // MARK: Nodos

    static func nodePaths(_ node: LitteraMermaidLayout.PlacedNode) -> NodePaths {
        let rect = node.frame
        switch node.shape {
        case .rectangle:
            let radius = min(LitteraMermaidLayout.Metrics.cornerRadius, rect.height / 2)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return NodePaths(fill: path, stroke: path)
        case .rounded:
            let radius = min(LitteraMermaidLayout.Metrics.roundedCornerRadius, rect.height / 2)
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return NodePaths(fill: path, stroke: path)
        case .stadium:
            let radius = min(rect.width, rect.height) / 2
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            return NodePaths(fill: path, stroke: path)
        case .circle:
            let path = CGPath(ellipseIn: rect, transform: nil)
            return NodePaths(fill: path, stroke: path)
        case .diamond:
            let path = polygon([
                CGPoint(x: rect.midX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.midX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.midY),
            ])
            return NodePaths(fill: path, stroke: path)
        case .hexagon:
            let inset = LitteraMermaidLayout.hexagonInset(height: rect.height)
            let path = polygon([
                CGPoint(x: rect.minX, y: rect.midY),
                CGPoint(x: rect.minX + inset, y: rect.minY),
                CGPoint(x: rect.maxX - inset, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.midY),
                CGPoint(x: rect.maxX - inset, y: rect.maxY),
                CGPoint(x: rect.minX + inset, y: rect.maxY),
            ])
            return NodePaths(fill: path, stroke: path)
        case .subroutine:
            let radius = min(LitteraMermaidLayout.Metrics.cornerRadius, rect.height / 2)
            let outline = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            let stroke = CGMutablePath()
            stroke.addPath(outline)
            for x in [rect.minX + 8, rect.maxX - 8] {
                stroke.move(to: CGPoint(x: x, y: rect.minY))
                stroke.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            return NodePaths(fill: outline, stroke: stroke)
        case .cylinder:
            let radiusY = LitteraMermaidLayout.Metrics.cylinderCap / 2
            let top = rect.minY + radiusY
            let bottom = rect.maxY - radiusY
            let outline = CGMutablePath()
            outline.move(to: CGPoint(x: rect.minX, y: top))
            addHalfEllipse(outline, from: rect.minX, to: rect.maxX, y: top, radiusY: -radiusY)
            outline.addLine(to: CGPoint(x: rect.maxX, y: bottom))
            addHalfEllipse(outline, from: rect.maxX, to: rect.minX, y: bottom, radiusY: radiusY)
            outline.closeSubpath()
            let stroke = CGMutablePath()
            stroke.addPath(outline)
            // Borde delantero de la tapa superior.
            stroke.move(to: CGPoint(x: rect.minX, y: top))
            addHalfEllipse(stroke, from: rect.minX, to: rect.maxX, y: top, radiusY: radiusY)
            return NodePaths(fill: outline, stroke: stroke)
        }
    }

    /// Media elipse de `from` a `to` a la altura `y`, abombada `radiusY`
    /// (positivo hacia abajo).
    private static func addHalfEllipse(_ path: CGMutablePath, from: CGFloat, to: CGFloat, y: CGFloat, radiusY: CGFloat) {
        let k: CGFloat = 0.5523
        let middle = (from + to) / 2
        let radiusX = (to - from) / 2
        path.addCurve(
            to: CGPoint(x: middle, y: y + radiusY),
            control1: CGPoint(x: from, y: y + radiusY * k),
            control2: CGPoint(x: middle - radiusX * k, y: y + radiusY)
        )
        path.addCurve(
            to: CGPoint(x: to, y: y),
            control1: CGPoint(x: middle + radiusX * k, y: y + radiusY),
            control2: CGPoint(x: to, y: y + radiusY * k)
        )
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// Centro vertical del texto: el cilindro baja la mitad de su tapa.
    static func textCenter(_ node: LitteraMermaidLayout.PlacedNode) -> CGPoint {
        let offset = node.shape == .cylinder ? LitteraMermaidLayout.Metrics.cylinderCap / 2 : 0
        return CGPoint(x: node.frame.midX, y: node.frame.midY + offset)
    }

    // MARK: Aristas

    static func strokeWidth(_ style: LitteraMermaidFlowchart.EdgeStyle) -> CGFloat {
        style == .thick ? 2.6 : 1.3
    }

    static func dashPattern(_ style: LitteraMermaidFlowchart.EdgeStyle) -> [CGFloat] {
        style == .dotted ? [3, 3.5] : []
    }

    private static func arrowSize(_ style: LitteraMermaidFlowchart.EdgeStyle) -> (length: CGFloat, halfWidth: CGFloat) {
        style == .thick ? (10, 5.5) : (LitteraMermaidLayout.Metrics.arrowLength, 4)
    }

    /// Trazo de la arista, recortado bajo las puntas de flecha para que la
    /// línea no asome por delante.
    static func edgePath(_ edge: LitteraMermaidLayout.PlacedEdge) -> CGPath {
        let path = CGMutablePath()
        guard !edge.curves.isEmpty else { return path }
        let trim = arrowSize(edge.style).length * 0.8
        var start = edge.start
        var curves = edge.curves
        if edge.arrowAtStart {
            let direction = unit(from: start, to: curves[0].control1, fallback: curves[0].end)
            start = CGPoint(x: start.x + direction.x * trim, y: start.y + direction.y * trim)
        }
        if edge.arrowAtEnd, let last = curves.last {
            let direction = unit(from: last.control2, to: last.end, fallback: curves.count > 1 ? curves[curves.count - 2].end : edge.start)
            curves[curves.count - 1] = LitteraMermaidLayout.Curve(
                control1: last.control1,
                control2: last.control2,
                end: CGPoint(x: last.end.x - direction.x * trim, y: last.end.y - direction.y * trim)
            )
        }
        path.move(to: start)
        for curve in curves {
            path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
        }
        return path
    }

    /// Puntas de flecha de la arista (0, 1 o 2 triángulos).
    static func arrowHeads(_ edge: LitteraMermaidLayout.PlacedEdge) -> CGPath {
        let path = CGMutablePath()
        guard let first = edge.curves.first, let last = edge.curves.last else { return path }
        let size = arrowSize(edge.style)
        if edge.arrowAtEnd {
            let previous = edge.curves.count > 1 ? edge.curves[edge.curves.count - 2].end : edge.start
            addArrow(path, tip: last.end, direction: unit(from: last.control2, to: last.end, fallback: previous), size: size)
        }
        if edge.arrowAtStart {
            let direction = unit(from: first.control1, to: edge.start, fallback: first.end)
            addArrow(path, tip: edge.start, direction: direction, size: size)
        }
        return path
    }

    private static func addArrow(
        _ path: CGMutablePath,
        tip: CGPoint,
        direction: CGPoint,
        size: (length: CGFloat, halfWidth: CGFloat)
    ) {
        let base = CGPoint(x: tip.x - direction.x * size.length, y: tip.y - direction.y * size.length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        path.addLines(between: [
            tip,
            CGPoint(x: base.x + normal.x * size.halfWidth, y: base.y + normal.y * size.halfWidth),
            CGPoint(x: base.x - normal.x * size.halfWidth, y: base.y - normal.y * size.halfWidth),
        ])
        path.closeSubpath()
    }

    /// Vector unitario de `from` a `to`; si casi coinciden, desde `fallback`
    /// (cuando es la referencia de llegada) hacia `to`.
    private static func unit(from: CGPoint, to: CGPoint, fallback: CGPoint) -> CGPoint {
        var dx = to.x - from.x
        var dy = to.y - from.y
        if (dx * dx + dy * dy) < 0.01 {
            dx = to.x - fallback.x
            dy = to.y - fallback.y
        }
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return CGPoint(x: dx / length, y: dy / length)
    }

    // MARK: SVG

    /// Atributo `d` de SVG para un `CGPath`.
    static func svgPathData(_ path: CGPath) -> String {
        var parts: [String] = []
        func number(_ value: CGFloat) -> String {
            let rounded = (value * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(rounded))
        }
        func point(_ point: CGPoint) -> String { "\(number(point.x)) \(number(point.y))" }
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                parts.append("M\(point(points[0]))")
            case .addLineToPoint:
                parts.append("L\(point(points[0]))")
            case .addQuadCurveToPoint:
                parts.append("Q\(point(points[0])) \(point(points[1]))")
            case .addCurveToPoint:
                parts.append("C\(point(points[0])) \(point(points[1])) \(point(points[2]))")
            case .closeSubpath:
                parts.append("Z")
            @unknown default:
                break
            }
        }
        return parts.joined(separator: " ")
    }
}
