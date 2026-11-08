import Foundation

/// Edición de texto resultante de un comando de formato: un único reemplazo
/// (un paso de Deshacer) y la selección que debe quedar después.
nonisolated struct LitteraTextEdit: Equatable, Sendable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

/// Aplica los comandos de formato al Markdown como texto. No depende de AppKit
/// ni de SwiftUI: recibe el texto y la selección (UTF-16) y devuelve la
/// edición. Funciona igual en Fuente y Dividido.
///
/// - En línea (negrita, cursiva, tachado, código): rodea la selección o, si ya
///   está marcada, quita las marcas. Sin selección inserta el par de marcas
///   con el cursor dentro.
/// - Por líneas (encabezados, párrafo, cita, listas, tareas): actúa sobre las
///   líneas tocadas por la selección; si todas tienen ya ese formato, lo quita.
/// - Bloques (código, separador, tabla): se insertan en líneas propias.
nonisolated enum LitteraMarkdownFormatter {
    static func edit(
        for action: LitteraFormattingAction,
        in text: String,
        selection: NSRange
    ) -> LitteraTextEdit {
        let ns = text as NSString
        let selection = clamp(selection, length: ns.length)

        switch action {
        case .bold: return toggleInline("**", in: ns, selection: selection)
        case .italic: return toggleInline("*", in: ns, selection: selection)
        case .strikethrough: return toggleInline("~~", in: ns, selection: selection)
        case .inlineCode: return toggleInline("`", in: ns, selection: selection)
        case .link: return wrapLink(prefix: "[", in: ns, selection: selection)
        case .image: return wrapLink(prefix: "![", in: ns, selection: selection)
        case .paragraph: return transformLines(in: ns, selection: selection, style: .paragraph)
        case .heading1: return transformLines(in: ns, selection: selection, style: .heading(1))
        case .heading2: return transformLines(in: ns, selection: selection, style: .heading(2))
        case .heading3: return transformLines(in: ns, selection: selection, style: .heading(3))
        case .heading4: return transformLines(in: ns, selection: selection, style: .heading(4))
        case .heading5: return transformLines(in: ns, selection: selection, style: .heading(5))
        case .heading6: return transformLines(in: ns, selection: selection, style: .heading(6))
        case .quote: return transformLines(in: ns, selection: selection, style: .quote)
        case .bulletList: return transformLines(in: ns, selection: selection, style: .bullet)
        case .numberedList: return transformLines(in: ns, selection: selection, style: .numbered)
        case .taskList: return transformLines(in: ns, selection: selection, style: .task)
        case .codeBlock: return codeBlock(in: ns, selection: selection)
        case .separator: return insertBlock("---", cursorOffset: 3, in: ns, at: selection)
        case .table: return insertBlock("|  |  |\n| --- | --- |\n|  |  |", cursorOffset: 2, in: ns, at: selection)
        }
    }

    private static func clamp(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    // MARK: - En línea

    private static func toggleInline(_ marker: String, in ns: NSString, selection: NSRange) -> LitteraTextEdit {
        let m = (marker as NSString).length
        var target = selection

        // Las marcas no pueden quedar junto a espacios: se excluyen los extremos.
        if target.length > 0 {
            let selected = ns.substring(with: target) as NSString
            var start = 0
            var end = selected.length
            while start < end, isWhitespace(selected.character(at: start)) { start += 1 }
            while end > start, isWhitespace(selected.character(at: end - 1)) { end -= 1 }
            if end > start {
                target = NSRange(location: target.location + start, length: end - start)
            }
        }
        let selected = ns.substring(with: target)

        // 1. La selección incluye las marcas: quitarlas.
        if target.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker),
           delimiterRun(marker, before: target.location + m, after: NSMaxRange(target) - m, in: ns, inside: true) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: target.length - 2 * m))
            return LitteraTextEdit(
                range: target,
                replacement: inner,
                selection: NSRange(location: target.location, length: (inner as NSString).length)
            )
        }

        // 2. Las marcas rodean la selección (o el cursor): quitarlas.
        if target.location >= m, NSMaxRange(target) + m <= ns.length,
           ns.substring(with: NSRange(location: target.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(target), length: m)) == marker,
           delimiterRun(marker, before: target.location, after: NSMaxRange(target), in: ns, inside: false) {
            return LitteraTextEdit(
                range: NSRange(location: target.location - m, length: target.length + 2 * m),
                replacement: selected,
                selection: NSRange(location: target.location - m, length: target.length)
            )
        }

        // 3. Añadir las marcas. El código en línea usa un delimitador más largo
        // si el contenido ya tiene comillas invertidas.
        var open = marker
        var close = marker
        if marker == "`", selected.contains("`") {
            open = "`` "
            close = " ``"
        }
        let replacement = open + selected + close
        return LitteraTextEdit(
            range: target,
            replacement: replacement,
            selection: NSRange(location: target.location + (open as NSString).length, length: target.length)
        )
    }

    /// Comprueba que las marcas encontradas forman un delimitador completo:
    /// por ejemplo, que el `*` de cursiva no sea la mitad de un `**` de negrita.
    private static func delimiterRun(_ marker: String, before: Int, after: Int, in ns: NSString, inside: Bool) -> Bool {
        guard marker == "*" || marker == "**" else { return true }
        let star: unichar = 0x2A
        func run(from index: Int, step: Int) -> Int {
            var count = 0
            var cursor = index
            while cursor >= 0, cursor < ns.length, ns.character(at: cursor) == star {
                count += 1
                cursor += step
            }
            return count
        }
        // Estrellas contiguas a cada lado del contenido.
        let left = run(from: before - 1, step: -1)
        let right = run(from: after, step: 1)
        if marker == "*" {
            return left % 2 == 1 && right % 2 == 1
        }
        return left >= 2 && right >= 2 && left != 4 && right != 4
    }

    private static func wrapLink(prefix: String, in ns: NSString, selection: NSRange) -> LitteraTextEdit {
        let label = ns.substring(with: selection)
        let replacement = prefix + label + "](url)"
        let p = (prefix as NSString).length
        // Con texto seleccionado se selecciona la dirección para escribirla;
        // sin selección, el cursor queda en la etiqueta.
        let next = selection.length > 0
            ? NSRange(location: selection.location + p + selection.length + 2, length: 3)
            : NSRange(location: selection.location + p, length: 0)
        return LitteraTextEdit(range: selection, replacement: replacement, selection: next)
    }

    // MARK: - Por líneas

    private enum LineStyle: Equatable {
        case paragraph
        case heading(Int)
        case quote
        case bullet
        case numbered
        case task
    }

    /// Partes de una línea: sangría, cita, marcador de bloque y contenido.
    private struct LineParts {
        var indent: String
        var quote: String
        var marker: String
        var content: String

        var headingLevel: Int? {
            let hashes = marker.prefix { $0 == "#" }.count
            return hashes > 0 && marker.hasSuffix(" ") ? hashes : nil
        }
        var isTask: Bool { marker.range(of: #"^[-*+] \[[ xX]\] $"#, options: .regularExpression) != nil }
        var isBullet: Bool { !isTask && marker.range(of: #"^[-*+] $"#, options: .regularExpression) != nil }
        var isNumbered: Bool { marker.range(of: #"^\d{1,9}[.)] $"#, options: .regularExpression) != nil }
    }

    private static func parse(_ line: String) -> LineParts {
        var rest = Substring(line)
        let indent = rest.prefix { $0 == " " || $0 == "\t" }
        rest = rest.dropFirst(indent.count)

        var quote = ""
        if rest.hasPrefix(">") {
            quote = rest.hasPrefix("> ") ? "> " : ">"
            rest = rest.dropFirst(quote.count)
        }

        let text = String(rest)
        let patterns = [#"^#{1,6} "#, #"^[-*+] \[[ xX]\] "#, #"^[-*+] "#, #"^\d{1,9}[.)] "#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return LineParts(
                    indent: String(indent),
                    quote: quote,
                    marker: String(text[range]),
                    content: String(text[range.upperBound...])
                )
            }
        }
        return LineParts(indent: String(indent), quote: quote, marker: "", content: text)
    }

    private static func transformLines(in ns: NSString, selection: NSRange, style: LineStyle) -> LitteraTextEdit {
        let block = ns.paragraphRange(for: selection)
        var blockText = ns.substring(with: block)
        let trailingNewline = blockText.hasSuffix("\n")
        if trailingNewline { blockText.removeLast() }
        let lines = blockText.components(separatedBy: "\n")
        let parts = lines.map(parse)
        let content = parts.enumerated().filter { !lines[$0.offset].trimmingCharacters(in: .whitespaces).isEmpty }.map(\.element)

        // Si todas las líneas ya tienen el formato pedido, el comando lo quita.
        let alreadyApplied: Bool = {
            guard !content.isEmpty else { return false }
            switch style {
            case .paragraph: return false
            case let .heading(level): return content.allSatisfy { $0.headingLevel == level }
            case .quote: return content.allSatisfy { !$0.quote.isEmpty }
            case .bullet: return content.allSatisfy(\.isBullet)
            case .numbered: return content.allSatisfy(\.isNumbered)
            case .task: return content.allSatisfy(\.isTask)
            }
        }()

        var number = 1
        let result: [String] = zip(lines, parts).map { line, part in
            let isEmpty = line.trimmingCharacters(in: .whitespaces).isEmpty
            switch style {
            case .quote:
                if alreadyApplied { return part.indent + part.marker + part.content }
                return part.indent + (isEmpty ? ">" : "> ") + part.marker + part.content
            default:
                if isEmpty { return line }
                let marker: String
                if alreadyApplied {
                    marker = ""
                } else {
                    switch style {
                    case .paragraph: marker = ""
                    case let .heading(level): marker = String(repeating: "#", count: level) + " "
                    case .bullet: marker = "- "
                    case .numbered:
                        marker = "\(number). "
                        number += 1
                    case .task: marker = "- [ ] "
                    case .quote: marker = ""
                    }
                }
                // Los encabezados no admiten sangría de bloque.
                let indent = (style == .paragraph || { if case .heading = style { return true }; return false }())
                    ? "" : part.indent
                return indent + part.quote + marker + part.content
            }
        }

        let replacement = result.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let newLength = (replacement as NSString).length - (trailingNewline ? 1 : 0)
        let newSelection: NSRange
        if selection.length == 0, lines.count == 1 {
            // Cursor al final de la línea transformada.
            newSelection = NSRange(location: block.location + newLength, length: 0)
        } else {
            newSelection = NSRange(location: block.location, length: newLength)
        }
        return LitteraTextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    // MARK: - Bloques

    private static func codeBlock(in ns: NSString, selection: NSRange) -> LitteraTextEdit {
        guard selection.length > 0 else {
            // Cursor en la línea interior, lista para escribir.
            return insertBlock("```\n\n```", cursorOffset: 4, in: ns, at: selection)
        }
        let block = ns.paragraphRange(for: selection)
        var body = ns.substring(with: block)
        let trailingNewline = body.hasSuffix("\n")
        if trailingNewline { body.removeLast() }
        let replacement = "```\n" + body + "\n```" + (trailingNewline ? "\n" : "")
        // Cursor tras el fence de apertura, para escribir el lenguaje.
        return LitteraTextEdit(
            range: block,
            replacement: replacement,
            selection: NSRange(location: block.location + 3, length: 0)
        )
    }

    /// Inserta un bloque en líneas propias, separado por líneas en blanco del
    /// texto anterior y posterior cuando hace falta.
    private static func insertBlock(_ block: String, cursorOffset: Int, in ns: NSString, at selection: NSRange) -> LitteraTextEdit {
        let location = selection.location
        let newline: unichar = 0x0A
        func char(_ index: Int) -> unichar? { index >= 0 && index < ns.length ? ns.character(at: index) : nil }

        var prefix = ""
        if location > 0 {
            if char(location - 1) != newline {
                prefix = "\n\n"
            } else if char(location - 2) != newline, location > 1 {
                prefix = "\n"
            }
        }
        var suffix = ""
        let end = NSMaxRange(selection)
        if let next = char(end) {
            if next != newline {
                suffix = "\n\n"
            } else if let following = char(end + 1), following != newline {
                suffix = "\n"
            }
        }
        let replacement = prefix + block + suffix
        return LitteraTextEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: location + (prefix as NSString).length + cursorOffset, length: 0)
        )
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A
    }
}
