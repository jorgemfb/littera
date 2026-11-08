import SwiftUI

/// Diagrama de flujo Mermaid en la Vista previa y el PDF: mismo contenedor
/// que los bloques de código de UI 1.0.0, con el diagrama centrado. Si no
/// cabe a lo ancho, se reduce proporcionalmente (D48).
struct LitteraMermaidDiagramView: View {
    let layout: LitteraMermaidLayout

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        LitteraMermaidFitLayout(size: layout.size) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(L10n.formatted(
            "ui.mermaid.diagrama.accesible",
            locale: locale,
            layout.nodes.map { $0.label.replacingOccurrences(of: "\n", with: " ") }.joined(separator: ", ")
        ))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard layout.size.width > 0, layout.size.height > 0 else { return }
        let scale = size.width / layout.size.width
        context.scaleBy(x: scale, y: scale)

        // Conexiones y puntas en el acento terracota (D48).
        let edgeColor = colors.accent
        for edge in layout.edges {
            let style = StrokeStyle(
                lineWidth: LitteraMermaidGeometry.strokeWidth(edge.style),
                lineCap: .round,
                dash: LitteraMermaidGeometry.dashPattern(edge.style)
            )
            context.stroke(Path(LitteraMermaidGeometry.edgePath(edge)), with: .color(edgeColor), style: style)
            context.fill(Path(LitteraMermaidGeometry.arrowHeads(edge)), with: .color(edgeColor))
        }

        for node in layout.nodes {
            let paths = LitteraMermaidGeometry.nodePaths(node)
            context.fill(Path(paths.fill), with: .color(colors.canvas))
            context.stroke(Path(paths.stroke), with: .color(colors.secondaryText.opacity(0.55)), lineWidth: 1)
            drawText(
                node.label,
                center: LitteraMermaidGeometry.textCenter(node),
                fontSize: LitteraMermaidLayout.Metrics.nodeFontSize,
                color: colors.primaryText,
                in: &context
            )
        }

        // Etiquetas al final: tapan la línea que pasa por debajo.
        for edge in layout.edges {
            guard let label = edge.label, let frame = edge.labelFrame else { continue }
            context.fill(
                Path(roundedRect: frame, cornerRadius: 4),
                with: .color(colors.secondary)
            )
            drawText(
                label,
                center: CGPoint(x: frame.midX, y: frame.midY),
                fontSize: LitteraMermaidLayout.Metrics.labelFontSize,
                color: colors.primaryText.opacity(0.8),
                in: &context
            )
        }
    }

    /// Una línea cada vez, centradas, con la misma altura de línea que se usó
    /// al medir.
    private func drawText(
        _ text: String,
        center: CGPoint,
        fontSize: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let lines = text.components(separatedBy: "\n")
        let lineHeight = LitteraMermaidGeometry.lineHeight(fontSize: fontSize)
        let top = center.y - lineHeight * CGFloat(lines.count) / 2
        for (index, line) in lines.enumerated() {
            context.draw(
                SwiftUI.Text(line)
                    .font(.system(size: fontSize))
                    .foregroundColor(color),
                at: CGPoint(x: center.x, y: top + lineHeight * (CGFloat(index) + 0.5)),
                anchor: .center
            )
        }
    }
}

/// Ocupa el ancho propuesto hasta el tamaño natural del diagrama y mantiene
/// la proporción. Determinista también en `ImageRenderer` (PDF).
private struct LitteraMermaidFitLayout: Layout {
    let size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width.map { $0.isFinite ? $0 : size.width } ?? size.width
        let width = max(min(size.width, available), 1)
        return CGSize(width: width, height: size.height * width / max(size.width, 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Bloque ```mermaid que no se puede dibujar: aviso discreto y el código tal
/// cual, para no inventar un diagrama distinto del escrito.
struct LitteraMermaidNoticeView<Code: View>: View {
    let diagram: LitteraMermaidDiagram
    @ViewBuilder let code: Code

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice {
                SwiftUI.Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.secondaryText)
            }
            code
        }
    }

    private var notice: String? {
        switch diagram {
        case let .unsupported(diagramType):
            L10n.formatted("ui.mermaid.no.compatible", locale: locale, diagramType)
        case let .invalid(line):
            L10n.formatted("ui.mermaid.error.linea", locale: locale, line)
        case .flowchart, .empty:
            nil
        }
    }
}
