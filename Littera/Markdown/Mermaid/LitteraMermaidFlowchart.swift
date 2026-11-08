import Foundation

/// Diagrama de flujo Mermaid (`flowchart` / `graph`) ya interpretado.
///
/// Littera no ejecuta mermaid.js (D29, D43): interpreta de forma nativa el
/// subconjunto de diagramas de flujo descrito en D48 y lo dibuja con
/// SwiftUI/CoreGraphics. Lo que no se reconoce no se inventa: el bloque se
/// muestra como código con un aviso.
nonisolated struct LitteraMermaidFlowchart: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case topDown, bottomUp, leftRight, rightLeft
    }

    enum NodeShape: Equatable, Sendable {
        /// `A[texto]`
        case rectangle
        /// `A(texto)`
        case rounded
        /// `A([texto])`
        case stadium
        /// `A((texto))`
        case circle
        /// `A{texto}`
        case diamond
        /// `A{{texto}}`
        case hexagon
        /// `A[[texto]]`
        case subroutine
        /// `A[(texto)]`
        case cylinder
    }

    struct Node: Equatable, Sendable {
        let id: String
        var label: String
        var shape: NodeShape
    }

    enum EdgeStyle: Equatable, Sendable {
        case solid, dotted, thick
    }

    struct Edge: Equatable, Sendable {
        let from: String
        let to: String
        var label: String?
        var style: EdgeStyle
        var arrowAtStart: Bool
        var arrowAtEnd: Bool
    }

    var direction: Direction
    /// En orden de aparición.
    var nodes: [Node]
    var edges: [Edge]
}

/// Resultado de interpretar un bloque ```mermaid.
nonisolated enum LitteraMermaidParseResult: Equatable, Sendable {
    case flowchart(LitteraMermaidFlowchart)
    /// Otro tipo de diagrama Mermaid (secuencia, Gantt…): se nombra el tipo.
    case unsupported(diagramType: String)
    /// Diagrama de flujo con una línea que no se entiende (1 = primera línea
    /// del bloque).
    case invalid(line: Int)
    case empty
}

nonisolated enum LitteraMermaidParser {
    static func isMermaid(_ language: String?) -> Bool {
        guard let raw = language?.trimmingCharacters(in: .whitespaces).lowercased(),
              let name = raw.split(separator: " ").first else { return false }
        return name == "mermaid"
    }

    static func parse(_ code: String) -> LitteraMermaidParseResult {
        let statements = statements(in: code)
        guard let header = statements.first else { return .empty }

        let headerWords = header.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let keyword = headerWords.first else { return .empty }
        guard keyword == "graph" || keyword == "flowchart" else {
            return .unsupported(diagramType: keyword)
        }

        var direction = LitteraMermaidFlowchart.Direction.topDown
        if headerWords.count > 1 {
            guard let parsed = Self.direction(headerWords[1]) else { return .invalid(line: header.line) }
            direction = parsed
        }
        guard headerWords.count <= 2 else { return .invalid(line: header.line) }

        var builder = Builder()
        for statement in statements.dropFirst() {
            guard builder.apply(statement.text) else { return .invalid(line: statement.line) }
        }
        return .flowchart(LitteraMermaidFlowchart(
            direction: direction,
            nodes: builder.nodes,
            edges: builder.edges
        ))
    }

    static func direction(_ word: String) -> LitteraMermaidFlowchart.Direction? {
        switch word.uppercased() {
        case "TD", "TB": .topDown
        case "BT": .bottomUp
        case "LR": .leftRight
        case "RL": .rightLeft
        default: nil
        }
    }

    // MARK: - Sentencias

    struct Statement: Equatable {
        let text: String
        let line: Int
    }

    /// Divide el bloque en sentencias (líneas y `;`), sin comentarios `%%`,
    /// directivas `%%{…}%%` ni el frontmatter `---` de Mermaid. Los `;` entre
    /// comillas o dentro de una forma no separan.
    static func statements(in code: String) -> [Statement] {
        var result: [Statement] = []
        var lines = code.components(separatedBy: .newlines)
        var firstLine = 1

        // Frontmatter de Mermaid (`---` … `---`) antes de la cabecera.
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces) == "---",
           let close = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            firstLine += close + 1
            lines = Array(lines[(close + 1)...])
        }

        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("%%") { continue }
            for piece in splitOnSemicolons(line) {
                let text = piece.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { result.append(Statement(text: text, line: firstLine + offset)) }
            }
        }
        return result
    }

    private static func splitOnSemicolons(_ line: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var inQuotes = false
        var depth = 0
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if "[({".contains(character) {
                    depth += 1
                } else if "])}".contains(character) {
                    depth = max(0, depth - 1)
                } else if character == ";", depth == 0 {
                    pieces.append(current)
                    current = ""
                    continue
                }
            }
            current.append(character)
        }
        pieces.append(current)
        return pieces
    }

    // MARK: - Construcción del grafo

    private struct Builder {
        var nodes: [LitteraMermaidFlowchart.Node] = []
        var edges: [LitteraMermaidFlowchart.Edge] = []
        private var indexByID: [String: Int] = [:]

        /// `false` si la sentencia no se entiende.
        mutating func apply(_ statement: String) -> Bool {
            let words = statement.split(whereSeparator: \.isWhitespace)
            switch words.first.map(String.init) {
            // Directivas de estilo o interacción: no cambian la estructura.
            case "classDef", "class", "style", "linkStyle", "click", "accTitle", "accDescr", "accTitle:", "accDescr:":
                return true
            // Los subgrafos se aplanan: sus nodos y conexiones se conservan.
            case "end", "direction":
                return true
            case "subgraph":
                return words.count > 1
            default:
                break
            }

            var scanner = StatementScanner(statement)
            guard var group = scanner.nodeGroup() else { return false }
            group.forEach { declare($0) }
            while !scanner.isAtEnd {
                guard let link = scanner.link(), let next = scanner.nodeGroup() else { return false }
                next.forEach { declare($0) }
                for from in group {
                    for to in next {
                        edges.append(LitteraMermaidFlowchart.Edge(
                            from: from.id,
                            to: to.id,
                            label: link.label,
                            style: link.style,
                            arrowAtStart: link.arrowAtStart,
                            arrowAtEnd: link.arrowAtEnd
                        ))
                    }
                }
                group = next
            }
            return true
        }

        /// La última forma declarada prevalece, como en Mermaid; una mención
        /// sin forma no cambia lo ya declarado.
        private mutating func declare(_ reference: NodeReference) {
            if let index = indexByID[reference.id] {
                if let shape = reference.shape {
                    nodes[index].shape = shape
                    nodes[index].label = reference.label ?? reference.id
                }
            } else {
                indexByID[reference.id] = nodes.count
                nodes.append(LitteraMermaidFlowchart.Node(
                    id: reference.id,
                    label: reference.label ?? reference.id,
                    shape: reference.shape ?? .rectangle
                ))
            }
        }
    }

    struct NodeReference: Equatable {
        let id: String
        let label: String?
        let shape: LitteraMermaidFlowchart.NodeShape?
    }

    struct Link: Equatable {
        var style: LitteraMermaidFlowchart.EdgeStyle
        var arrowAtStart: Bool
        var arrowAtEnd: Bool
        var label: String?
    }

    // MARK: - Analizador de una sentencia

    struct StatementScanner {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) {
            characters = Array(text)
        }

        var isAtEnd: Bool {
            var probe = index
            while probe < characters.count, characters[probe].isWhitespace { probe += 1 }
            return probe >= characters.count
        }

        private func peek(_ offset: Int = 0) -> Character? {
            let position = index + offset
            return position < characters.count ? characters[position] : nil
        }

        private mutating func skipSpaces() {
            while let character = peek(), character.isWhitespace { index += 1 }
        }

        private func hasPrefix(_ text: String) -> Bool {
            var offset = 0
            for character in text {
                guard peek(offset) == character else { return false }
                offset += 1
            }
            return true
        }

        static func isIdentifierCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }

        // MARK: Nodos

        /// `A`, `A[texto]` o varios unidos con `&`.
        mutating func nodeGroup() -> [NodeReference]? {
            var group: [NodeReference] = []
            repeat {
                skipSpaces()
                guard let node = node() else { return nil }
                group.append(node)
                skipSpaces()
            } while consume("&")
            return group
        }

        private mutating func consume(_ text: String) -> Bool {
            guard hasPrefix(text) else { return false }
            index += text.count
            return true
        }

        private mutating func node() -> NodeReference? {
            let start = index
            while let character = peek(), Self.isIdentifierCharacter(character) { index += 1 }
            guard index > start else { return nil }
            let id = String(characters[start..<index])

            var label: String?
            var shape: LitteraMermaidFlowchart.NodeShape?
            // El orden importa: los delimitadores dobles antes que los simples.
            let delimiters: [(open: String, close: String, shape: LitteraMermaidFlowchart.NodeShape)] = [
                ("([", "])", .stadium),
                ("((", "))", .circle),
                ("[[", "]]", .subroutine),
                ("[(", ")]", .cylinder),
                ("{{", "}}", .hexagon),
                ("[", "]", .rectangle),
                ("(", ")", .rounded),
                ("{", "}", .diamond),
            ]
            for delimiter in delimiters where hasPrefix(delimiter.open) {
                index += delimiter.open.count
                guard var text = readLabel(until: delimiter.close) else { return nil }
                // Paralelogramos y trapecios (`[/texto/]`, `[\texto\]`…) se
                // dibujan como rectángulo, sin las barras.
                if delimiter.shape == .rectangle, text.count >= 2,
                   let first = text.first, let last = text.last,
                   "/\\".contains(first), "/\\".contains(last) {
                    text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                }
                label = text
                shape = delimiter.shape
                break
            }

            // Clase abreviada `A:::nombre`: estilo, se ignora.
            if consume(":::") {
                while let character = peek(), Self.isIdentifierCharacter(character) || character == "-" { index += 1 }
            }
            return NodeReference(id: id, label: label, shape: shape)
        }

        /// Texto hasta el cierre, entre comillas o no. Devuelve `nil` si el
        /// cierre no aparece.
        private mutating func readLabel(until close: String) -> String? {
            skipSpaces()
            var value = ""
            if peek() == "\"" {
                index += 1
                while let character = peek(), character != "\"" {
                    value.append(character)
                    index += 1
                }
                guard peek() == "\"" else { return nil }
                index += 1
                skipSpaces()
                guard consume(close) else { return nil }
            } else {
                while !hasPrefix(close) {
                    guard let character = peek() else { return nil }
                    value.append(character)
                    index += 1
                }
                index += close.count
            }
            return LitteraMermaidParser.cleanLabel(value)
        }

        // MARK: Conexiones

        /// `-->`, `---`, `-.->`, `==>`, `<-->`, con o sin etiqueta
        /// (`-->|texto|`, `-- texto -->`, `-. texto .->`, `== texto ==>`).
        mutating func link() -> Link? {
            skipSpaces()
            let arrowAtStart = consume("<")

            let bodyStart = index
            while let character = peek(), "-.=".contains(character) { index += 1 }
            var body = String(characters[bodyStart..<index])
            guard body.count >= 2 else { return nil }
            var arrowAtEnd = consume(">")

            var label: String?
            if !arrowAtEnd, peek()?.isWhitespace == true, ["--", "==", "-."].contains(body) {
                // Etiqueta en medio: `-- texto -->`.
                guard let (text, closing, closingArrow) = inlineLabel(opening: body) else { return nil }
                label = text
                body += closing
                arrowAtEnd = closingArrow
            }

            guard Self.isValidBody(body, hasArrow: arrowAtEnd || arrowAtStart) else { return nil }

            skipSpaces()
            if consume("|") {
                var text = ""
                while let character = peek(), character != "|" {
                    text.append(character)
                    index += 1
                }
                guard consume("|") else { return nil }
                label = LitteraMermaidParser.cleanLabel(text)
            }

            let style: LitteraMermaidFlowchart.EdgeStyle = body.contains(".") ? .dotted : (body.contains("=") ? .thick : .solid)
            return Link(
                style: style,
                arrowAtStart: arrowAtStart,
                arrowAtEnd: arrowAtEnd,
                label: label.flatMap { $0.isEmpty ? nil : $0 }
            )
        }

        /// Lee `texto -->` tras `--` (o `texto ==>` tras `==`, `texto .->`
        /// tras `-.`). Devuelve el texto, el cierre y si termina en flecha.
        private mutating func inlineLabel(opening: String) -> (String, String, Bool)? {
            let closingCharacters: Set<Character> = opening == "==" ? ["="] : (opening == "-." ? [".", "-"] : ["-"])
            var text = ""
            while let character = peek() {
                if closingCharacters.contains(character), let closing = closingRun(from: index, allowed: closingCharacters, opening: opening) {
                    index = closing.end
                    return (LitteraMermaidParser.cleanLabel(text), closing.body, closing.arrow)
                }
                text.append(character)
                index += 1
            }
            return nil
        }

        private func closingRun(
            from start: Int,
            allowed: Set<Character>,
            opening: String
        ) -> (body: String, arrow: Bool, end: Int)? {
            var end = start
            while end < characters.count, allowed.contains(characters[end]) { end += 1 }
            let body = String(characters[start..<end])
            let arrow = end < characters.count && characters[end] == ">"
            switch opening {
            case "-.":
                // `.->` o `.-`
                guard body.hasPrefix("."), body.dropFirst().allSatisfy({ $0 == "-" }), body.count >= 2 else { return nil }
            case "==":
                guard body.count >= (arrow ? 2 : 3) else { return nil }
            default:
                guard body.count >= (arrow ? 2 : 3) else { return nil }
            }
            return (body, arrow, arrow ? end + 1 : end)
        }

        /// Cuerpos de conexión aceptados: `--`+ con flecha, `---`+ sin ella,
        /// `-.`…`.-` punteados y `==`+ gruesos.
        static func isValidBody(_ body: String, hasArrow: Bool) -> Bool {
            if body.allSatisfy({ $0 == "-" }) { return body.count >= (hasArrow ? 2 : 3) }
            if body.allSatisfy({ $0 == "=" }) { return body.count >= (hasArrow ? 2 : 3) }
            // Punteado: `-.-`, `-..-`, `-. … .-` (ya concatenado como `-..-`).
            guard body.hasPrefix("-"), body.hasSuffix("-") || body.hasSuffix(".") else { return false }
            let inner = body.dropFirst().drop(while: { $0 == "." })
            return body.contains(".") && inner.allSatisfy { $0 == "-" || $0 == "." }
        }
    }

    // MARK: - Texto

    /// Etiqueta legible: sin comillas ni comillas invertidas de Markdown,
    /// `<br>` como salto de línea y entidades básicas resueltas.
    static func cleanLabel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        if text.count >= 2, text.hasPrefix("`"), text.hasSuffix("`") {
            text = String(text.dropFirst().dropLast())
        }
        for breakTag in ["<br/>", "<br />", "<br>", "<BR>", "<BR/>"] {
            text = text.replacingOccurrences(of: breakTag, with: "\n")
        }
        let entities = ["&quot;": "\"", "&lt;": "<", "&gt;": ">", "&#35;": "#", "&nbsp;": " ", "&amp;": "&"]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }
}
