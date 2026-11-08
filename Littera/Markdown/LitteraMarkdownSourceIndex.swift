import Foundation
import Markdown

/// Índice inmutable de posiciones de un Markdown, construido una sola vez por
/// análisis. Permite convertir ubicaciones de `swift-markdown` (línea y columna
/// en bytes UTF-8) a offsets UTF-16 de AppKit sin copiar ni recorrer el
/// documento completo por cada bloque.
///
/// Coste: O(n) al construirlo; cada conversión es O(1) para localizar la línea
/// más O(longitud de la línea) para resolver la columna.
nonisolated struct LitteraMarkdownSourceIndex: Sendable {
    enum Rounding: Sendable {
        case down
        case up
    }

    private let bytes: ContiguousArray<UInt8>
    /// Offset UTF-8 del primer byte de cada línea (la línea 1 está en el índice 0).
    private let lineStartsUTF8: [Int]
    /// Offset UTF-16 equivalente al inicio de cada línea.
    private let lineStartsUTF16: [Int]

    var utf8Count: Int { bytes.count }

    init(_ source: String) {
        let bytes = ContiguousArray(source.utf8)
        var startsUTF8 = [0]
        var startsUTF16 = [0]
        var utf16Offset = 0
        var index = 0

        while index < bytes.count {
            let length = Self.scalarLength(leadByte: bytes[index])
            utf16Offset += length == 4 ? 2 : 1
            if bytes[index] == 0x0A {
                startsUTF8.append(index + 1)
                startsUTF16.append(utf16Offset)
            }
            index += length
        }

        self.bytes = bytes
        lineStartsUTF8 = startsUTF8
        lineStartsUTF16 = startsUTF16
    }

    /// Offset UTF-8 de una ubicación de `swift-markdown`. Las columnas se
    /// limitan al final de su línea, como en la conversión original.
    func utf8Offset(for location: Markdown.SourceLocation) -> Int? {
        utf8Offset(line: location.line, column: location.column)
    }

    /// `line` y `column` empiezan en 1; la columna se mide en bytes UTF-8.
    func utf8Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, column >= 1, line <= lineStartsUTF8.count else { return nil }
        let lineStart = lineStartsUTF8[line - 1]
        let lineEnd = line < lineStartsUTF8.count
            ? lineStartsUTF8[line] - 1
            : bytes.count
        return min(lineStart + column - 1, lineEnd)
    }

    /// Offset UTF-16 de un offset UTF-8. Si el offset cae dentro de un escalar
    /// multibyte se redondea a su inicio (`.down`) o a su final (`.up`).
    func utf16Offset(forUTF8Offset requestedOffset: Int, rounding: Rounding) -> Int {
        let target = max(0, min(requestedOffset, bytes.count))
        let line = lineIndex(containingUTF8Offset: target)
        var utf8Offset = lineStartsUTF8[line]
        var utf16Offset = lineStartsUTF16[line]

        while utf8Offset < target {
            let length = Self.scalarLength(leadByte: bytes[utf8Offset])
            let utf16Length = length == 4 ? 2 : 1
            if target < utf8Offset + length {
                return rounding == .down ? utf16Offset : utf16Offset + utf16Length
            }
            utf8Offset += length
            utf16Offset += utf16Length
        }
        return utf16Offset
    }

    private func lineIndex(containingUTF8Offset offset: Int) -> Int {
        // Última línea cuyo inicio es <= offset.
        var low = 0
        var high = lineStartsUTF8.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartsUTF8[mid] <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }

    private static func scalarLength(leadByte: UInt8) -> Int {
        switch leadByte {
        case 0..<0x80: 1
        case 0xC0..<0xE0: 2
        case 0xE0..<0xF0: 3
        case 0xF0...: 4
        default: 1 // Byte de continuación: no debería aparecer en UTF-8 válido de String.
        }
    }
}
