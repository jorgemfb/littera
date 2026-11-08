import Foundation
import Markdown

/// Tramo de estilo del Markdown, en offsets UTF-16 del texto original. El
/// resaltado de Fuente los usa para colorear sin cambiar el texto. Se calculan
/// fuera del hilo principal, junto con el resto del análisis.
nonisolated struct LitteraVisualRun: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// Sintaxis Markdown visible pero atenuada: #, **, `, >, -, [x], fences…
        case marker
        case heading(level: Int)
        case strong
        case emphasis
        case strikethrough
        case inlineCode
        case link
        /// Bloque de código completo, incluidos sus fences.
        case codeBlock
        case codeToken(LitteraSyntaxTokenKind)
        case blockQuote(depth: Int)
        /// Elemento de lista. `markerLength`: longitud del marcador ("- ", "1. ",
        /// "- [x] ") al inicio del tramo, para alinear las líneas siguientes.
        case listItem(depth: Int, markerLength: Int)
        case completedTask
        case thematicBreak
        /// Tabla GFM completa: filas compactas, como en la Vista previa.
        case table
        /// Frontmatter YAML inicial, delimitadores incluidos.
        case frontmatter
    }

    let range: NSRange
    let kind: Kind
}

nonisolated enum LitteraVisualRunBuilder {
    static func runs(for result: LitteraMarkdownParseResult) -> [LitteraVisualRun] {
        var builder = Builder(source: result.source)
        if let frontmatter = result.frontmatter {
            builder.addFrontmatter(frontmatter)
        }
        builder.visitBlocks(result.ast.children, quoteDepth: 0, listDepth: 0)
        return builder.runs
    }

    private struct Builder {
        let index: LitteraMarkdownSourceIndex
        let text: NSString
        var runs: [LitteraVisualRun] = []

        init(source: String) {
            index = LitteraMarkdownSourceIndex(source)
            text = source as NSString
        }

        // MARK: - Rangos

        private func range(of markup: Markup) -> NSRange? {
            LitteraMarkdownSourceRange(sourceRange: markup.range, source: index)?.utf16Range
        }

        private func childrenRange(of markup: Markup) -> NSRange? {
            var lower: Int?
            var upper: Int?
            for child in markup.children {
                guard let range = range(of: child) else { continue }
                lower = min(lower ?? range.location, range.location)
                upper = max(upper ?? NSMaxRange(range), NSMaxRange(range))
            }
            guard let lower, let upper, upper >= lower else { return nil }
            return NSRange(location: lower, length: upper - lower)
        }

        private mutating func add(_ range: NSRange, _ kind: LitteraVisualRun.Kind) {
            guard range.length > 0, NSMaxRange(range) <= text.length else { return }
            runs.append(LitteraVisualRun(range: range, kind: kind))
        }

        /// Frontmatter con el YAML resaltado como un bloque de código.
        mutating func addFrontmatter(_ frontmatter: LitteraFrontmatter) {
            add(frontmatter.range, .frontmatter)
            for token in LitteraSyntaxHighlighter.tokens(for: frontmatter.yaml, language: "yaml") {
                add(
                    NSRange(location: frontmatter.yamlRange.location + token.range.location, length: token.range.length),
                    .codeToken(token.kind)
                )
            }
        }

        /// Marca como atenuado lo que rodea al contenido (delimitadores).
        private mutating func addDelimiters(around content: NSRange, in outer: NSRange) {
            add(NSRange(location: outer.location, length: content.location - outer.location), .marker)
            add(NSRange(location: NSMaxRange(content), length: NSMaxRange(outer) - NSMaxRange(content)), .marker)
        }

        private func lineRanges(in range: NSRange) -> [NSRange] {
            var lines: [NSRange] = []
            var location = range.location
            while location < NSMaxRange(range) {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                lines.append(NSIntersectionRange(line, range))
                guard NSMaxRange(line) > location else { break }
                location = NSMaxRange(line)
            }
            return lines
        }

        /// Longitud de los caracteres iniciales de `line` que cumplen `predicate`.
        private func prefixLength(of line: NSRange, while predicate: (unichar) -> Bool) -> Int {
            var length = 0
            while length < line.length, predicate(text.character(at: line.location + length)) { length += 1 }
            return length
        }

        // MARK: - Bloques

        mutating func visitBlocks(_ children: MarkupChildren, quoteDepth: Int, listDepth: Int) {
            for child in children {
                visitBlock(child, quoteDepth: quoteDepth, listDepth: listDepth)
            }
        }

        mutating func visitBlock(_ markup: Markup, quoteDepth: Int, listDepth: Int) {
            guard let range = range(of: markup) else { return }

            switch markup {
            case let heading as Heading:
                add(range, .heading(level: min(max(heading.level, 1), 6)))
                if let content = childrenRange(of: heading) {
                    addDelimiters(around: content, in: range)
                } else {
                    add(range, .marker)
                }
                visitInlines(heading.children)

            case let paragraph as Paragraph:
                visitInlines(paragraph.children)

            case let codeBlock as CodeBlock:
                add(range, .codeBlock)
                visitCodeBlock(codeBlock, range: range)

            case let quote as BlockQuote:
                add(range, .blockQuote(depth: quoteDepth + 1))
                for line in lineRanges(in: range) {
                    // Sangría y ">" (con su espacio) de cada línea de la cita.
                    var length = prefixLength(of: line) { $0 == 0x20 || $0 == 0x3E }
                    if length > 0, length < line.length, text.character(at: line.location + length - 1) != 0x20,
                       text.character(at: line.location + length) == 0x20 {
                        length += 1
                    }
                    add(NSRange(location: line.location, length: length), .marker)
                }
                visitBlocks(quote.children, quoteDepth: quoteDepth + 1, listDepth: listDepth)

            case let list as UnorderedList:
                visitListItems(list.children, depth: listDepth + 1, quoteDepth: quoteDepth)

            case let list as OrderedList:
                visitListItems(list.children, depth: listDepth + 1, quoteDepth: quoteDepth)

            case let table as Table:
                add(range, .table)
                // Tuberías y fila de alineación atenuadas; las celdas conservan
                // sus estilos inline.
                for (offset, line) in lineRanges(in: range).enumerated() {
                    if offset == 1 {
                        add(line, .marker)
                        continue
                    }
                    for index in line.location..<NSMaxRange(line) where text.character(at: index) == 0x7C {
                        add(NSRange(location: index, length: 1), .marker)
                    }
                }
                for cell in table.head.children {
                    visitInlines(cell.children)
                }
                for row in table.body.rows {
                    for cell in row.children {
                        visitInlines(cell.children)
                    }
                }

            case is ThematicBreak:
                add(range, .thematicBreak)
                add(range, .marker)

            case is HTMLBlock:
                add(range, .marker)

            default:
                break
            }
        }

        private mutating func visitListItems(_ children: MarkupChildren, depth: Int, quoteDepth: Int) {
            for child in children {
                guard let item = child as? ListItem, let range = range(of: item) else { continue }
                let contentStart = childrenRange(of: item)?.location ?? NSMaxRange(range)
                var markerLength = max(0, contentStart - range.location)
                // La casilla "[x] " forma parte del marcador.
                if item.checkbox != nil {
                    let rest = text.substring(with: NSRange(location: contentStart, length: min(4, text.length - contentStart)))
                    if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") || rest.hasPrefix("[ ] ") {
                        markerLength += 4
                    } else if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") || rest.hasPrefix("[ ]") {
                        markerLength += 3
                    }
                }
                add(range, .listItem(depth: depth, markerLength: markerLength))
                add(NSRange(location: range.location, length: markerLength), .marker)
                if item.checkbox == .checked {
                    let start = range.location + markerLength
                    add(NSRange(location: start, length: NSMaxRange(range) - start), .completedTask)
                }
                visitBlocks(item.children, quoteDepth: quoteDepth, listDepth: depth)
            }
        }

        private mutating func visitCodeBlock(_ codeBlock: CodeBlock, range: NSRange) {
            let lines = lineRanges(in: range)
            guard let first = lines.first else { return }
            let firstLine = text.substring(with: first).trimmingCharacters(in: .whitespaces)
            let isFenced = firstLine.hasPrefix("```") || firstLine.hasPrefix("~~~")
            guard isFenced else { return }

            add(first, .marker)
            var contentEnd = NSMaxRange(range)
            if lines.count > 1, let last = lines.last {
                let lastLine = text.substring(with: last).trimmingCharacters(in: .whitespacesAndNewlines)
                if lastLine.hasPrefix("```") || lastLine.hasPrefix("~~~") {
                    add(last, .marker)
                    contentEnd = last.location
                }
            }

            // Resaltado: solo si el contenido del Markdown coincide exactamente
            // con el código (sin sangrías de lista o cita que desplacen offsets).
            let contentStart = NSMaxRange(first)
            guard contentEnd > contentStart else { return }
            let content = NSRange(location: contentStart, length: contentEnd - contentStart)
            guard text.substring(with: content) == codeBlock.code else { return }
            for token in LitteraSyntaxHighlighter.tokens(for: codeBlock.code, language: codeBlock.language) {
                add(NSRange(location: contentStart + token.range.location, length: token.range.length), .codeToken(token.kind))
            }
        }

        // MARK: - Inline

        private mutating func visitInlines(_ children: MarkupChildren) {
            for child in children {
                visitInline(child)
            }
        }

        private mutating func visitInline(_ markup: Markup) {
            guard let range = range(of: markup) else { return }
            switch markup {
            case is Strong:
                add(range, .strong)
                if let content = childrenRange(of: markup) { addDelimiters(around: content, in: range) }
                visitInlines(markup.children)

            case is Emphasis:
                add(range, .emphasis)
                if let content = childrenRange(of: markup) { addDelimiters(around: content, in: range) }
                visitInlines(markup.children)

            case is Strikethrough:
                add(range, .strikethrough)
                if let content = childrenRange(of: markup) { addDelimiters(around: content, in: range) }
                visitInlines(markup.children)

            case is InlineCode:
                add(range, .inlineCode)
                let ticks = prefixLength(of: range) { $0 == 0x60 }
                if ticks > 0, range.length >= ticks * 2 {
                    add(NSRange(location: range.location, length: ticks), .marker)
                    add(NSRange(location: NSMaxRange(range) - ticks, length: ticks), .marker)
                }

            case is Link:
                if let label = childrenRange(of: markup) {
                    add(label, .link)
                    addDelimiters(around: label, in: range)
                } else {
                    add(range, .link)
                }
                visitInlines(markup.children)

            case is Image:
                add(range, .marker)

            case is InlineHTML:
                add(range, .marker)

            default:
                break
            }
        }
    }
}

/// Zona modificada entre dos versiones de los tramos, para reestilar solo
/// esa parte tras una edición.
nonisolated extension LitteraVisualRun {
    /// Rango del documento nuevo afectado por el cambio de tramos: se comparan
    /// los tramos desde el principio y desde el final (desplazados por la
    /// diferencia de longitud).
    static func changedRange(
        old: [LitteraVisualRun],
        oldLength: Int,
        new: [LitteraVisualRun],
        newLength: Int
    ) -> NSRange? {
        let delta = newLength - oldLength
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        if prefix == old.count, prefix == new.count, delta == 0 { return nil }

        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix {
            let lhs = old[old.count - 1 - suffix]
            let rhs = new[new.count - 1 - suffix]
            guard lhs.kind == rhs.kind,
                  lhs.range.length == rhs.range.length,
                  lhs.range.location + delta == rhs.range.location else { break }
            suffix += 1
        }

        let firstChanged = new[prefix..<(new.count - suffix)]
        let oldChanged = old[prefix..<(old.count - suffix)]
        var lower = newLength
        var upper = 0
        for run in firstChanged {
            lower = min(lower, run.range.location)
            upper = max(upper, NSMaxRange(run.range))
        }
        // Los tramos que desaparecen también cuentan, trasladados al documento nuevo.
        for run in oldChanged {
            lower = min(lower, max(0, min(run.range.location, newLength)))
            upper = max(upper, min(newLength, max(0, NSMaxRange(run.range) + delta)))
        }
        // El texto editado sin tramos (texto normal) queda entre los tramos
        // intactos: limitarlo por el último tramo común anterior y el primero
        // común posterior.
        let before = prefix > 0 ? NSMaxRange(new[prefix - 1].range) : 0
        let after = suffix > 0 ? new[new.count - suffix].range.location : newLength
        lower = min(lower, before)
        upper = max(upper, min(after, newLength))
        guard upper >= lower else { return NSRange(location: 0, length: newLength) }
        return NSRange(location: lower, length: upper - lower)
    }
}
