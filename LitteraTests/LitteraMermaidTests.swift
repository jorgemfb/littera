import XCTest
@testable import Littera

final class LitteraMermaidParserTests: XCTestCase {
    private func flowchart(_ code: String, file: StaticString = #filePath, line: UInt = #line) throws -> LitteraMermaidFlowchart {
        guard case let .flowchart(chart) = LitteraMermaidParser.parse(code) else {
            XCTFail("Se esperaba un diagrama de flujo: \(LitteraMermaidParser.parse(code))", file: file, line: line)
            throw XCTSkip()
        }
        return chart
    }

    func testRecognizesMermaidFence() {
        XCTAssertTrue(LitteraMermaidParser.isMermaid("mermaid"))
        XCTAssertTrue(LitteraMermaidParser.isMermaid(" Mermaid "))
        XCTAssertFalse(LitteraMermaidParser.isMermaid("swift"))
        XCTAssertFalse(LitteraMermaidParser.isMermaid(nil))
    }

    func testBasicFlowchartWithShapesAndLabels() throws {
        let chart = try flowchart("""
        graph TD
            A[Inicio] --> B{¿Válido?}
            B -->|Sí| C(Fin)
            B -- No --> A
        """)
        XCTAssertEqual(chart.direction, .topDown)
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(chart.nodes.map(\.label), ["Inicio", "¿Válido?", "Fin"])
        XCTAssertEqual(chart.nodes.map(\.shape), [.rectangle, .diamond, .rounded])
        XCTAssertEqual(chart.edges.count, 3)
        XCTAssertEqual(chart.edges[1].label, "Sí")
        XCTAssertEqual(chart.edges[2].label, "No")
        XCTAssertEqual(chart.edges[2].from, "B")
        XCTAssertEqual(chart.edges[2].to, "A")
        XCTAssertTrue(chart.edges.allSatisfy { $0.arrowAtEnd && !$0.arrowAtStart && $0.style == .solid })
    }

    func testAllShapes() throws {
        let chart = try flowchart("""
        flowchart LR
        a[r] --> b(r) --> c([s]) --> d((c)) --> e{d} --> f{{h}} --> g[[s]] --> h[(c)] --> i[/p/]
        """)
        XCTAssertEqual(chart.direction, .leftRight)
        XCTAssertEqual(chart.nodes.map(\.shape), [.rectangle, .rounded, .stadium, .circle, .diamond, .hexagon, .subroutine, .cylinder, .rectangle])
        XCTAssertEqual(chart.nodes.last?.label, "p")
        XCTAssertEqual(chart.edges.count, 8)
    }

    func testLinkStyles() throws {
        let chart = try flowchart("""
        graph LR
        A --- B
        A -.-> C
        A ==> D
        A <--> E
        A -. punteada .-> F
        A == gruesa ==> G
        A -.- H
        A === I
        A ---> J
        """)
        let edges = chart.edges
        XCTAssertEqual(edges.map(\.style), [.solid, .dotted, .thick, .solid, .dotted, .thick, .dotted, .thick, .solid])
        XCTAssertEqual(edges.map(\.arrowAtEnd), [false, true, true, true, true, true, false, false, true])
        XCTAssertEqual(edges.map(\.arrowAtStart), [false, false, false, true, false, false, false, false, false])
        XCTAssertEqual(edges[4].label, "punteada")
        XCTAssertEqual(edges[5].label, "gruesa")
    }

    func testInlineLabelMayContainHyphens() throws {
        let chart = try flowchart("graph TD\nA -- auto-guardado --> B")
        XCTAssertEqual(chart.edges.first?.label, "auto-guardado")
    }

    func testAmpersandAndChains() throws {
        let chart = try flowchart("graph TD\nA & B --> C & D\nC --> E --> F")
        XCTAssertEqual(chart.edges.count, 6)
        XCTAssertEqual(chart.edges.prefix(4).map { "\($0.from)\($0.to)" }, ["AC", "AD", "BC", "BD"])
        XCTAssertEqual(chart.edges.suffix(2).map { "\($0.from)\($0.to)" }, ["CE", "EF"])
    }

    func testSemicolonsCommentsStylesAndSubgraphs() throws {
        let chart = try flowchart("""
        %%{init: {"theme": "dark"}}%%
        graph LR; A-->B; B-->C;
        %% comentario
        classDef rojo fill:#f00
        class A rojo
        style B fill:#0f0
        subgraph uno [Grupo]
          direction TB
          C --> D:::rojo
        end
        linkStyle 0 stroke:#f00
        """)
        XCTAssertEqual(chart.nodes.map(\.id), ["A", "B", "C", "D"])
        XCTAssertEqual(chart.edges.count, 3)
    }

    func testQuotedLabelsAndLineBreaks() throws {
        let chart = try flowchart("graph TD\nA[\"Texto [con] corchetes; y punto y coma\"] --> B[Uno<br>Dos]")
        XCTAssertEqual(chart.nodes[0].label, "Texto [con] corchetes; y punto y coma")
        XCTAssertEqual(chart.nodes[1].label, "Uno\nDos")
    }

    func testLaterShapeDeclarationWins() throws {
        let chart = try flowchart("graph TD\nA --> B\nB[Segundo]")
        XCTAssertEqual(chart.nodes[1].label, "Segundo")
        XCTAssertEqual(chart.nodes[1].shape, .rectangle)
        let plain = try flowchart("graph TD\nA[Primero] --> B\nA --> C")
        XCTAssertEqual(plain.nodes[0].label, "Primero", "Una mención sin forma no borra la etiqueta")
    }

    func testDefaultDirectionAndAliases() throws {
        XCTAssertEqual(try flowchart("graph\nA-->B").direction, .topDown)
        XCTAssertEqual(try flowchart("flowchart TB\nA-->B").direction, .topDown)
        XCTAssertEqual(try flowchart("flowchart BT\nA-->B").direction, .bottomUp)
        XCTAssertEqual(try flowchart("flowchart RL\nA-->B").direction, .rightLeft)
    }

    func testMermaidFrontmatterIsSkipped() throws {
        let chart = try flowchart("---\ntitle: Ejemplo\n---\nflowchart LR\nA --> B")
        XCTAssertEqual(chart.nodes.count, 2)
    }

    func testUnsupportedAndInvalidDiagrams() {
        XCTAssertEqual(LitteraMermaidParser.parse("sequenceDiagram\nA->>B: Hola"), .unsupported(diagramType: "sequenceDiagram"))
        XCTAssertEqual(LitteraMermaidParser.parse("pie title Mascotas\n\"Perros\" : 3"), .unsupported(diagramType: "pie"))
        XCTAssertEqual(LitteraMermaidParser.parse("graph TD\nA --> B\nA -->\n"), .invalid(line: 3))
        XCTAssertEqual(LitteraMermaidParser.parse("graph XX\nA-->B"), .invalid(line: 1))
        XCTAssertEqual(LitteraMermaidParser.parse("graph TD\nA[sin cerrar --> B"), .invalid(line: 2))
        XCTAssertEqual(LitteraMermaidParser.parse("  \n%% solo comentario\n"), .empty)
    }
}

final class LitteraMermaidLayoutTests: XCTestCase {
    /// Medida fija para que las pruebas no dependan de las fuentes.
    private let measure: LitteraMermaidLayout.Measure = { text, fontSize in
        let lines = text.components(separatedBy: "\n")
        let width = CGFloat(lines.map(\.count).max() ?? 0) * fontSize * 0.55
        return CGSize(width: width.rounded(.up), height: CGFloat(lines.count) * 16)
    }

    private func layout(_ code: String) -> LitteraMermaidLayout {
        guard case let .flowchart(chart) = LitteraMermaidParser.parse(code) else {
            XCTFail("Diagrama no válido")
            return LitteraMermaidLayout(size: .zero, nodes: [], edges: [])
        }
        return LitteraMermaidLayout.make(chart, measure: measure)
    }

    private func assertNoOverlaps(_ layout: LitteraMermaidLayout, file: StaticString = #filePath, line: UInt = #line) {
        let frames = layout.nodes.map(\.frame) + layout.edges.compactMap(\.labelFrame)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(
                    frames[i].insetBy(dx: 0.5, dy: 0.5).intersects(frames[j].insetBy(dx: 0.5, dy: 0.5)),
                    "Se solapan \(frames[i]) y \(frames[j])",
                    file: file, line: line
                )
            }
        }
        let bounds = CGRect(origin: .zero, size: layout.size)
        for frame in frames {
            XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(frame) fuera de \(layout.size)", file: file, line: line)
        }
    }

    func testTopDownPlacesTargetsBelow() {
        let result = layout("graph TD\nA[Inicio] --> B[Paso] --> C[Fin]")
        XCTAssertEqual(result.nodes.count, 3)
        XCTAssertLessThan(result.nodes[0].frame.maxY, result.nodes[1].frame.minY)
        XCTAssertLessThan(result.nodes[1].frame.maxY, result.nodes[2].frame.minY)
        for edge in result.edges {
            XCTAssertGreaterThan(edge.end.y, edge.start.y, "Las flechas bajan")
        }
        // La flecha llega al borde superior del destino.
        XCTAssertEqual(result.edges[0].end.y, result.nodes[1].frame.minY, accuracy: 0.5)
        assertNoOverlaps(result)
    }

    func testOtherDirections() {
        let leftRight = layout("graph LR\nA --> B")
        XCTAssertLessThan(leftRight.nodes[0].frame.maxX, leftRight.nodes[1].frame.minX)
        let rightLeft = layout("graph RL\nA --> B")
        XCTAssertGreaterThan(rightLeft.nodes[0].frame.minX, rightLeft.nodes[1].frame.maxX)
        let bottomUp = layout("graph BT\nA --> B")
        XCTAssertGreaterThan(bottomUp.nodes[0].frame.minY, bottomUp.nodes[1].frame.maxY)
    }

    func testBranchesSitSideBySideWithoutOverlap() {
        let result = layout("""
        graph TD
        A{¿Seguir?} -->|Sí| B[Guardar documento]
        A -->|No| C[Descartar cambios]
        B --> D[Fin]
        C --> D
        """)
        XCTAssertEqual(result.nodes[1].frame.midY, result.nodes[2].frame.midY, accuracy: 0.5)
        XCTAssertEqual(result.edges.compactMap(\.labelFrame).count, 2)
        assertNoOverlaps(result)
    }

    func testCyclesAndSelfLoopsAreLaidOut() {
        let result = layout("graph TD\nA --> B --> C --> A\nB --> B\nC -->|otra vez| C")
        XCTAssertEqual(result.edges.count, 5)
        XCTAssertTrue(result.edges.allSatisfy { !$0.curves.isEmpty })
        assertNoOverlaps(result)
    }

    func testLongEdgesAndManyNodes() {
        var lines = ["graph TD"]
        for index in 0..<40 { lines.append("N\(index) --> N\(index + 1)") }
        lines.append("N0 --> N40")
        lines.append("N5 & N6 & N7 --> N30")
        let result = layout(lines.joined(separator: "\n"))
        XCTAssertEqual(result.nodes.count, 41)
        assertNoOverlaps(result)
    }

    func testDiagramBlockInPreviewAndHTML() throws {
        let source = "# Proceso\n\n```mermaid\ngraph TD\nA[Inicio] --> B[Fin]\n```\n\n```mermaid\nsequenceDiagram\nA->>B: Hola\n```\n"
        let derived = LitteraMarkdownDerivedDocument(source: source, revision: 1)
        guard case let .mermaid(_, diagram, _) = derived.rendered.blocks[1].kind,
              case let .flowchart(chart) = diagram else {
            return XCTFail("El primer bloque debería ser un diagrama de flujo")
        }
        XCTAssertEqual(chart.nodes.map(\.label), ["Inicio", "Fin"])
        guard case let .mermaid(_, unsupported, highlights) = derived.rendered.blocks[2].kind else {
            return XCTFail("El segundo bloque debería ser Mermaid")
        }
        XCTAssertEqual(unsupported, .unsupported(diagramType: "sequenceDiagram"))
        XCTAssertFalse(highlights.isEmpty, "El código Mermaid se resalta")
    }
}

@MainActor
final class LitteraMermaidExportTests: XCTestCase {
    func testHTMLExportEmbedsSVGAndKeepsUnsupportedCode() {
        let html = LitteraExporter.html(
            for: "```mermaid\ngraph LR\nA[\"<b>Inicio</b>\"] -->|Sí & no| B((Fin))\n```\n\n```mermaid\ngantt\n```\n",
            title: "Diagrama"
        )
        XCTAssertTrue(html.contains("<figure class=\"mermaid\">"))
        XCTAssertTrue(html.contains("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(html.contains("&lt;b&gt;Inicio&lt;/b&gt;"), "Las etiquetas se escapan")
        XCTAssertTrue(html.contains("Sí &amp; no"))
        XCTAssertTrue(html.contains("language-mermaid"), "Lo no compatible sigue como código")
        XCTAssertTrue(html.contains("figure.mermaid .edge"))
    }

    func testPDFExportWithDiagram() throws {
        let source = "```mermaid\nflowchart TD\nA --> B{¿Sí?}\nB --> C\nB --> D\n```\n"
        let derived = LitteraMarkdownDerivedDocument(source: source, revision: 1)
        let data = try LitteraExporter.pdf(for: derived, documentURL: nil)
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
    }
}
