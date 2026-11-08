import XCTest
@testable import Littera

/// LIT-005: tras una edición, la Vista previa solo recalcula los bloques cuyo
/// contenido cambia; el desplazamiento de los rangos de origen no cuenta.
final class LitteraPreviewBlockEqualityTests: XCTestCase {
    private let original = """
    # Título

    Primer párrafo.

    > Cita con **negrita**.
    > > Anidada.

    - Uno
    - [x] Hecho
      - Anidado

    1. Primero
    2. Segundo

    ```swift
    let a = 1
    ```

    | A | B |
    |---|---|
    | 1 | 2 |
    """

    private func blocks(_ text: String) -> [LitteraMarkdownRenderBlock] {
        LitteraMarkdownDerivedDocument(source: text, revision: 1).rendered.blocks
    }

    func testEditingEarlyParagraphKeepsLaterBlocksEqualForRendering() {
        let before = blocks(original)
        let after = blocks(original.replacingOccurrences(of: "Primer párrafo.", with: "Primer párrafo editado."))
        XCTAssertEqual(before.count, after.count)
        XCTAssertFalse(before[1].rendersSame(as: after[1]), "El bloque editado sí cambia")
        for index in 2..<before.count {
            XCTAssertNotEqual(before[index], after[index], "Los rangos de origen se han desplazado")
            XCTAssertTrue(before[index].rendersSame(as: after[index]), "Bloque \(index) no debería recalcularse")
            XCTAssertTrue(
                LitteraMarkdownBlockView(block: before[index]) == LitteraMarkdownBlockView(block: after[index])
            )
        }
        XCTAssertTrue(before[0].rendersSame(as: after[0]))
    }

    func testNestedChangesStillCount() {
        let before = blocks(original)
        let quote = blocks(original.replacingOccurrences(of: "> > Anidada.", with: "> > Anidada y cambiada."))
        XCTAssertFalse(before[2].rendersSame(as: quote[2]))

        let checkbox = blocks(original.replacingOccurrences(of: "- [x] Hecho", with: "- [ ] Hecho"))
        XCTAssertFalse(before[3].rendersSame(as: checkbox[3]))

        let nested = blocks(original.replacingOccurrences(of: "  - Anidado", with: "  - Anidado otro"))
        XCTAssertFalse(before[3].rendersSame(as: nested[3]))

        let start = blocks(original.replacingOccurrences(of: "1. Primero\n2. Segundo", with: "3. Primero\n4. Segundo"))
        XCTAssertFalse(before[4].rendersSame(as: start[4]))

        let code = blocks(original.replacingOccurrences(of: "let a = 1", with: "let a = 2"))
        XCTAssertFalse(before[5].rendersSame(as: code[5]))

        let table = blocks(original.replacingOccurrences(of: "| 1 | 2 |", with: "| 1 | 3 |"))
        XCTAssertFalse(before[6].rendersSame(as: table[6]))
    }

    func testIdenticalDocumentsRenderSame() {
        let before = blocks(original)
        let again = blocks(original)
        XCTAssertEqual(before, again)
        XCTAssertTrue(zip(before, again).allSatisfy { $0.rendersSame(as: $1) })
    }

    func testInsertedBlockShiftsPositionalIdentifiers() {
        // Comportamiento conocido (sin cambios): los identificadores son
        // posicionales y un bloque nuevo cambia los de los siguientes.
        let before = blocks(original)
        let after = blocks(original.replacingOccurrences(of: "Primer párrafo.", with: "Primer párrafo.\n\nOtro párrafo."))
        XCTAssertEqual(after.count, before.count + 1)
        XCTAssertFalse(before[2].rendersSame(as: after[3]))
    }
}
