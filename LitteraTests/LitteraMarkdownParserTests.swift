import XCTest
@testable import Littera

final class LitteraMarkdownParserTests: XCTestCase {
    private let parser = LitteraMarkdownParser()
    private let renderer = LitteraMarkdownRenderer()

    func testPreservesSourceAndBuildsASTForBasicMarkdown() {
        let source = "# Título\n\nPárrafo con *énfasis* y **negrita**."

        let result = parser.parse(source)
        let tree = result.ast.debugDescription()

        XCTAssertEqual(result.source, source)
        XCTAssertTrue(tree.contains("Heading"))
        XCTAssertTrue(tree.contains("Paragraph"))
        XCTAssertTrue(tree.contains("Emphasis"))
        XCTAssertTrue(tree.contains("Strong"))
    }

    func testBuildsASTForGFMAndNestedBlockSyntax() {
        let source = """
        > Cita con `código`.

        - [x] Hecho
        - [ ] Pendiente
          - elemento anidado

        ---

        ```swift
        let value = 1
        ```

        | A | B |
        |---|---|
        | 1 | 2 |
        """

        let tree = parser.parse(source).ast.debugDescription()

        XCTAssertTrue(tree.contains("BlockQuote"), tree)
        XCTAssertTrue(tree.contains("UnorderedList"), tree)
        XCTAssertTrue(tree.contains("ListItem checkbox: [x]"), tree)
        XCTAssertTrue(tree.contains("ListItem checkbox: [ ]"), tree)
        XCTAssertTrue(tree.contains("ThematicBreak"), tree)
        XCTAssertTrue(tree.contains("CodeBlock"), tree)
        XCTAssertTrue(tree.contains("Table"), tree)
        XCTAssertTrue(tree.contains("InlineCode"), tree)
    }

    func testBuildsASTForLinksImagesAutolinksEscapesAndStrikethrough() {
        let source = #"[enlace](https://example.com) ![imagen](image.png) <https://example.com> ~~tachado~~ \*literal\*"#

        let tree = parser.parse(source).ast.debugDescription()

        XCTAssertTrue(tree.contains("Link"), tree)
        XCTAssertTrue(tree.contains("Image"), tree)
        XCTAssertTrue(tree.contains("Link destination: \"https://example.com\""), tree)
        XCTAssertTrue(tree.contains("Strikethrough"), tree)
        XCTAssertTrue(tree.contains("Text"), tree)
    }

    func testAcceptsUnicodeIncompleteAndEmptyDocumentsWithoutChangingSource() {
        let sources = [
            "",
            "# Encabezado sin cierre [😺]",
            "Texto con **énfasis sin cerrar",
            "- [x] tarea\n- [ pendiente",
            "Привет, мир — مرحباً بالعالم — こんにちは世界"
        ]

        for source in sources {
            let result = parser.parse(source)
            XCTAssertEqual(result.source, source)
        }
    }

    func testHandlesLargeDocument() {
        let source = String(repeating: "## Sección\n\nContenido con *énfasis*.\n\n", count: 2_000)

        let result = parser.parse(source)

        XCTAssertEqual(result.source.count, source.count)
        _ = result.ast
    }

    func testTransformsSupportedASTNodesWithoutChangingSource() {
        let source = """
        # Título

        Párrafo con **negrita**, *énfasis*, ~~tachado~~, `código` y [enlace](https://example.com).

        1. Primero
        2. Segundo

        > Cita

        ---

        ```swift
        let value = 1
        """

        let parsed = parser.parse(source)
        let rendered = renderer.render(parsed)

        XCTAssertEqual(parsed.source, source)
        XCTAssertEqual(rendered.blocks.count, 6)

        guard case let .heading(level, headingContent) = rendered.blocks[0].kind else {
            return XCTFail("Se esperaba un encabezado")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(headingContent.first?.kind, .text("Título"))

        guard case let .paragraph(content) = rendered.blocks[1].kind else {
            return XCTFail("Se esperaba un párrafo")
        }
        XCTAssertTrue(content.contains { inline in
            if case .strong = inline.kind { return true }
            return false
        })
        XCTAssertTrue(content.contains { inline in
            if case let .link(destination, _) = inline.kind {
                return destination == "https://example.com"
            }
            return false
        })

        guard case let .orderedList(start, items) = rendered.blocks[2].kind else {
            return XCTFail("Se esperaba una lista ordenada")
        }
        XCTAssertEqual(start, 1)
        XCTAssertEqual(items.count, 2)

        guard case .blockQuote = rendered.blocks[3].kind else {
            return XCTFail("Se esperaba una cita")
        }
        guard case .thematicBreak = rendered.blocks[4].kind else {
            return XCTFail("Se esperaba una separación temática")
        }
        guard case let .codeBlock(_, code, _) = rendered.blocks[5].kind else {
            return XCTFail("Se esperaba un bloque de código")
        }
        XCTAssertEqual(code, "let value = 1\n")
    }

    func testEmptyAndUnsupportedNodesRenderSafely() {
        let source = ""
        let empty = renderer.render(parser.parse(source))
        XCTAssertTrue(empty.blocks.isEmpty)

        let html = renderer.render(parser.parse("<div>bloque HTML</div>"))
        XCTAssertTrue(html.blocks.isEmpty)
    }

    func testRendersGFMTablesWithAlignment() {
        let table = renderer.render(parser.parse("| A | B | C |\n|:--|:-:|--:|\n| 1 | **2** | 3 |\n| x |"))
        guard case let .table(alignments, header, rows) = table.blocks.first?.kind else {
            return XCTFail("Se esperaba una tabla")
        }
        XCTAssertEqual(alignments, [.leading, .center, .trailing])
        XCTAssertEqual(header.map { $0.first?.kind }, [.text("A"), .text("B"), .text("C")])
        XCTAssertEqual(rows.count, 2)
        guard case .strong = rows[0][1].first?.kind else {
            return XCTFail("Se esperaba negrita en la celda")
        }
        XCTAssertNotNil(table.blocks.first?.sourceRange)
    }

    func testPreservesUnicodeAndCodeBlockNewlines() {
        let source = """
        Привет, мир — مرحباً بالعالم — こんにちは世界

        ```
        primera
          segunda
        tercera
        ```
        """

        let rendered = renderer.render(parser.parse(source))
        XCTAssertEqual(rendered.blocks.count, 2)
        guard case let .codeBlock(_, code, _) = rendered.blocks[1].kind else {
            return XCTFail("Se esperaba un bloque de código")
        }
        XCTAssertEqual(code, "primera\n  segunda\ntercera\n")
    }

    func testTransformsAllHeadingLevelsAndNestedUnorderedLists() {
        let source = """
        # Uno
        ## Dos
        ### Tres
        #### Cuatro
        ##### Cinco
        ###### Seis

        - Padre
          - Hijo con **negrita**
        """

        let rendered = renderer.render(parser.parse(source))
        XCTAssertEqual(rendered.blocks.count, 7)

        for (index, expectedLevel) in (1...6).enumerated() {
            guard case let .heading(level, _) = rendered.blocks[index].kind else {
                return XCTFail("Se esperaba H\(expectedLevel)")
            }
            XCTAssertEqual(level, expectedLevel)
        }

        guard case let .unorderedList(items) = rendered.blocks[6].kind,
              let parentParagraph = items.first?.blocks.first,
              case .paragraph = parentParagraph.kind,
              items.first?.blocks.contains(where: { block in
                  if case .unorderedList = block.kind { return true }
                  return false
              }) == true else {
            return XCTFail("Se esperaba una lista no ordenada anidada")
        }
    }

    func testConvertsUTF8SourceColumnsToUTF16Ranges() {
        let source = "🙂e\u{301}\n"
        let range = LitteraMarkdownSourceRange(
            utf8Range: 0..<7,
            source: source
        )

        XCTAssertEqual(range?.utf8Range, 0..<7)
        XCTAssertEqual(range?.utf16Range, NSRange(location: 0, length: 4))
        XCTAssertEqual((source as NSString).substring(with: range!.utf16Range), "🙂e\u{301}")
    }

    func testRenderBlocksKeepSemanticSourceRangesForUnicodeAndNestedMarkdown() {
        let source = "# 😺 Encabezado\n\nTexto con e\u{301} y 🚀.\n\n- uno\n- dos\n"
        let rendered = renderer.render(parser.parse(source))

        XCTAssertEqual(rendered.blocks.count, 3)
        XCTAssertTrue(rendered.blocks.allSatisfy { $0.sourceRange != nil })

        let heading = rendered.blocks[0]
        XCTAssertEqual(
            (source as NSString).substring(with: heading.sourceRange!.utf16Range),
            "# 😺 Encabezado"
        )

        let paragraph = rendered.blocks[1]
        XCTAssertTrue(
            (source as NSString).substring(with: paragraph.sourceRange!.utf16Range)
                .contains("e\u{301} y 🚀")
        )

        let list = rendered.blocks[2]
        XCTAssertEqual(
            rendered.block(containingOrFollowingUTF16Character: list.sourceRange!.utf16Range.location)?.id,
            list.id
        )
        XCTAssertEqual(
            rendered.block(containingOrFollowingUTF16Character: list.sourceRange!.utf16Range.location - 1)?.id,
            list.id
        )
        XCTAssertEqual(rendered.block(withID: heading.id)?.id, heading.id)
    }

    func testScrollMappingIgnoresBlocksWithoutSourceRanges() {
        let document = LitteraMarkdownRenderDocument(
            blocks: [
                LitteraMarkdownRenderBlock(
                    id: "unranged",
                    sourceRange: nil,
                    kind: .thematicBreak
                )
            ]
        )

        XCTAssertNil(document.block(containingOrFollowingUTF16Character: 0))
        XCTAssertNil(document.block(withID: "missing"))
    }
}
