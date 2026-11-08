import Foundation

/// Comandos de edición de la 1.1.0 (D52). Igual que los de formato, son
/// transformaciones del Markdown como texto: reciben el texto y la selección
/// (UTF-16) y devuelven una edición (un paso de Deshacer), o `nil` si no
/// procede. No dependen de AppKit.
nonisolated enum LitteraEditingCommand: String, CaseIterable, Identifiable, Sendable {
    case moveLinesUp
    case moveLinesDown
    case duplicateLines
    case toggleTask
    case insertDate
    case trimTrailingWhitespace
    case sortLinesAscending
    case sortLinesDescending
    case uppercase
    case lowercase
    case capitalize

    var id: String { rawValue }
    var commandID: String { "edit.\(rawValue)" }

    var label: String {
        switch self {
        case .moveLinesUp: "ui.mover.lineas.arriba"
        case .moveLinesDown: "ui.mover.lineas.abajo"
        case .duplicateLines: "ui.duplicar.lineas"
        case .toggleTask: "ui.alternar.tarea"
        case .insertDate: "ui.insertar.fecha"
        case .trimTrailingWhitespace: "ui.limpiar.espacios.finales"
        case .sortLinesAscending: "ui.ordenar.lineas.ascendente"
        case .sortLinesDescending: "ui.ordenar.lineas.descendente"
        case .uppercase: "ui.convertir.mayusculas"
        case .lowercase: "ui.convertir.minusculas"
        case .capitalize: "ui.convertir.capitalizar"
        }
    }

    var symbol: String {
        switch self {
        case .moveLinesUp: "arrow.up.to.line"
        case .moveLinesDown: "arrow.down.to.line"
        case .duplicateLines: "plus.square.on.square"
        case .toggleTask: "checkmark.square"
        case .insertDate: "calendar"
        case .trimTrailingWhitespace: "eraser"
        case .sortLinesAscending: "arrow.up.arrow.down"
        case .sortLinesDescending: "arrow.up.arrow.down"
        case .uppercase: "textformat.size.larger"
        case .lowercase: "textformat.size.smaller"
        case .capitalize: "textformat"
        }
    }

    /// Mayúsculas, minúsculas y capitalizar solo actúan sobre una selección.
    var needsSelection: Bool {
        self == .uppercase || self == .lowercase || self == .capitalize
    }
}

/// Formatos de «Insertar fecha» (Ajustes → Editor).
nonisolated enum LitteraDateFormat: String, CaseIterable, Identifiable, Sendable {
    case iso
    case isoWithTime
    case short
    case long

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .iso: "ui.fecha.iso"
        case .isoWithTime: "ui.fecha.iso.hora"
        case .short: "ui.fecha.corta"
        case .long: "ui.fecha.larga"
        }
    }

    func string(from date: Date, locale: Locale, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        switch self {
        case .iso:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
        case .isoWithTime:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
        case .short:
            formatter.locale = locale
            formatter.dateStyle = .short
            formatter.timeStyle = .none
        case .long:
            formatter.locale = locale
            formatter.dateStyle = .long
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}

nonisolated enum LitteraTextCommands {
    struct Context {
        var date = Date()
        var dateFormat = LitteraDateFormat.iso
        var locale = Locale(identifier: "es_ES")
        var timeZone = TimeZone.current
    }

    static func edit(
        for command: LitteraEditingCommand,
        in text: String,
        selection: NSRange,
        context: Context = Context()
    ) -> LitteraTextEdit? {
        let ns = text as NSString
        let selection = clamp(selection, length: ns.length)
        switch command {
        case .moveLinesUp: return moveLines(in: ns, selection: selection, up: true)
        case .moveLinesDown: return moveLines(in: ns, selection: selection, up: false)
        case .duplicateLines: return duplicateLines(in: ns, selection: selection)
        case .toggleTask: return toggleTask(in: ns, selection: selection)
        case .insertDate:
            let date = context.dateFormat.string(from: context.date, locale: context.locale, timeZone: context.timeZone)
            return LitteraTextEdit(
                range: selection,
                replacement: date,
                selection: NSRange(location: selection.location + (date as NSString).length, length: 0)
            )
        case .trimTrailingWhitespace: return trimTrailingWhitespace(in: ns, selection: selection)
        case .sortLinesAscending: return sortLines(in: ns, selection: selection, ascending: true, locale: context.locale)
        case .sortLinesDescending: return sortLines(in: ns, selection: selection, ascending: false, locale: context.locale)
        case .uppercase: return convertCase(in: ns, selection: selection) { $0.uppercased(with: context.locale) }
        case .lowercase: return convertCase(in: ns, selection: selection) { $0.lowercased(with: context.locale) }
        case .capitalize: return convertCase(in: ns, selection: selection) { $0.capitalized(with: context.locale) }
        }
    }

    // MARK: - Líneas

    /// Líneas tocadas por la selección. Una selección que termina justo al
    /// principio de una línea no incluye esa línea.
    static func linesRange(in ns: NSString, selection: NSRange) -> NSRange {
        var range = selection
        if range.length > 0, NSMaxRange(range) <= ns.length, ns.character(at: NSMaxRange(range) - 1) == 0x0A {
            range.length -= 1
        }
        return ns.lineRange(for: range)
    }

    private static func contentLength(of line: NSRange, in ns: NSString) -> Int {
        var length = line.length
        if length > 0, ns.character(at: line.location + length - 1) == 0x0A { length -= 1 }
        return length
    }

    private static func moveLines(in ns: NSString, selection: NSRange, up: Bool) -> LitteraTextEdit? {
        let block = linesRange(in: ns, selection: selection)
        let other: NSRange
        if up {
            guard block.location > 0, block.length > 0 else { return nil }
            other = ns.lineRange(for: NSRange(location: block.location - 1, length: 0))
        } else {
            guard NSMaxRange(block) < ns.length,
                  ns.character(at: NSMaxRange(block) - 1) == 0x0A else { return nil }
            other = ns.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
        }
        let region = NSUnionRange(block, other)
        let regionText = ns.substring(with: region)
        let endsWithNewline = regionText.hasSuffix("\n")
        var lines = (endsWithNewline ? String(regionText.dropLast()) : regionText).components(separatedBy: "\n")
        if up {
            lines.append(lines.removeFirst())
        } else {
            lines.insert(lines.removeLast(), at: 0)
        }
        let replacement = lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        let shift = contentLength(of: other, in: ns) + 1
        return LitteraTextEdit(
            range: region,
            replacement: replacement,
            selection: NSRange(location: selection.location + (up ? -shift : shift), length: selection.length)
        )
    }

    private static func duplicateLines(in ns: NSString, selection: NSRange) -> LitteraTextEdit {
        let block = linesRange(in: ns, selection: selection)
        let blockText = ns.substring(with: block)
        if blockText.hasSuffix("\n") {
            return LitteraTextEdit(
                range: NSRange(location: NSMaxRange(block), length: 0),
                replacement: blockText,
                selection: NSRange(location: selection.location + block.length, length: selection.length)
            )
        }
        // Última línea sin salto final.
        return LitteraTextEdit(
            range: NSRange(location: NSMaxRange(block), length: 0),
            replacement: "\n" + blockText,
            selection: NSRange(location: selection.location + block.length + 1, length: selection.length)
        )
    }

    private static func sortLines(in ns: NSString, selection: NSRange, ascending: Bool, locale: Locale) -> LitteraTextEdit? {
        let block = linesRange(in: ns, selection: selection)
        let blockText = ns.substring(with: block)
        let endsWithNewline = blockText.hasSuffix("\n")
        let lines = (endsWithNewline ? String(blockText.dropLast()) : blockText).components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }
        // Orden natural de la lengua de la interfaz: sin distinguir mayúsculas
        // y con los números por su valor («2» antes que «10»).
        let sorted = lines.enumerated().sorted { a, b in
            let order = a.element.compare(b.element, options: [.caseInsensitive, .numeric], range: nil, locale: locale)
            if order == .orderedSame { return a.offset < b.offset }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.element)
        let replacement = sorted.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        guard replacement != blockText else { return nil }
        let selected = NSRange(location: block.location, length: (replacement as NSString).length - (endsWithNewline ? 1 : 0))
        return LitteraTextEdit(range: block, replacement: replacement, selection: selected)
    }

    // MARK: - Marcadores de lista

    /// Marcador de un elemento de lista: `- `, `* `, `+ `, `1. `, `2) `, con
    /// sangría y, opcionalmente, casilla de tarea `[ ]` / `[x]`.
    struct ListMarker: Equatable {
        var indent: String
        /// `-`, `*` o `+`; `nil` en listas numeradas.
        var bullet: Character?
        var number: Int?
        var delimiter: Character?
        var spacing: String
        /// `nil` si no es tarea; `true` si está marcada.
        var taskChecked: Bool?
        /// Longitud UTF-16 hasta el final del marcador (sin casilla).
        var markerLength: Int
        /// Longitud UTF-16 hasta el final de la casilla y su espacio.
        var fullLength: Int
        /// Posición UTF-16 del carácter de estado de la casilla.
        var taskStateOffset: Int?
    }

    static func listMarker(in line: String) -> ListMarker? {
        let characters = Array(line)
        var index = 0
        func utf16Length(_ upTo: Int) -> Int { String(characters[0..<upTo]).utf16.count }

        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        let indent = String(characters[0..<index])
        guard index < characters.count else { return nil }

        var bullet: Character?
        var number: Int?
        var delimiter: Character?
        if "-*+".contains(characters[index]) {
            bullet = characters[index]
            index += 1
        } else {
            let digitsStart = index
            while index < characters.count, index - digitsStart < 9, characters[index].isASCII, characters[index].isNumber { index += 1 }
            guard index > digitsStart, index < characters.count, characters[index] == "." || characters[index] == ")" else { return nil }
            number = Int(String(characters[digitsStart..<index]))
            delimiter = characters[index]
            index += 1
        }

        let spacingStart = index
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        guard index > spacingStart else { return nil }
        let spacing = String(characters[spacingStart..<index])
        let markerLength = utf16Length(index)

        var taskChecked: Bool?
        var fullLength = markerLength
        var stateOffset: Int?
        // Casilla `[ ]`, `[x]` o `[X]` seguida de espacio o fin de línea.
        if index + 2 < characters.count, characters[index] == "[", characters[index + 2] == "]",
           " xX".contains(characters[index + 1]) {
            let after = index + 3
            if after == characters.count || characters[after] == " " || characters[after] == "\t" {
                taskChecked = characters[index + 1] != " "
                stateOffset = utf16Length(index + 1)
                var end = after
                while end < characters.count, characters[end] == " " || characters[end] == "\t" { end += 1 }
                fullLength = utf16Length(end)
            }
        }
        return ListMarker(
            indent: indent, bullet: bullet, number: number, delimiter: delimiter, spacing: spacing,
            taskChecked: taskChecked, markerLength: markerLength, fullLength: fullLength, taskStateOffset: stateOffset
        )
    }

    // MARK: - Tareas

    private static func toggleTask(in ns: NSString, selection: NSRange) -> LitteraTextEdit? {
        let block = linesRange(in: ns, selection: selection)
        let blockText = ns.substring(with: block)
        let endsWithNewline = blockText.hasSuffix("\n")
        var lines = (endsWithNewline ? String(blockText.dropLast()) : blockText).components(separatedBy: "\n")

        var taskStates: [Int: Bool] = [:]
        for (index, line) in lines.enumerated() {
            if let checked = listMarker(in: line)?.taskChecked { taskStates[index] = checked }
        }

        var caretDelta = 0
        if taskStates.isEmpty {
            // Ninguna tarea: las líneas con texto pasan a ser tareas pendientes.
            for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let nsLine = line as NSString
                let converted: String
                if let marker = listMarker(in: line) {
                    converted = nsLine.substring(to: marker.markerLength) + "[ ] " + nsLine.substring(from: marker.markerLength)
                } else {
                    let indentLength = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
                    converted = nsLine.substring(to: indentLength) + "- [ ] " + nsLine.substring(from: indentLength)
                }
                if index == 0 { caretDelta = (converted as NSString).length - nsLine.length }
                lines[index] = converted
            }
        } else {
            // Todas hechas: se desmarcan. Si no, se marcan las pendientes.
            let markDone = taskStates.values.contains(false)
            for (index, _) in taskStates {
                let nsLine = lines[index] as NSString
                guard let offset = listMarker(in: lines[index])?.taskStateOffset else { continue }
                lines[index] = nsLine.replacingCharacters(in: NSRange(location: offset, length: 1), with: markDone ? "x" : " ")
            }
        }

        let replacement = lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        guard replacement != blockText else { return nil }
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(block.location, selection.location + caretDelta), length: 0)
        } else {
            newSelection = NSRange(location: block.location, length: (replacement as NSString).length - (endsWithNewline ? 1 : 0))
        }
        return LitteraTextEdit(range: block, replacement: replacement, selection: newSelection)
    }

    // MARK: - Espacios al final

    /// Quita espacios y tabuladores al final de las líneas. Se respetan los
    /// saltos de línea forzados de Markdown (dos o más espacios antes de una
    /// línea que continúa el párrafo, que quedan en exactamente dos) y el
    /// contenido de los bloques de código cercados.
    private static func trimTrailingWhitespace(in ns: NSString, selection: NSRange) -> LitteraTextEdit? {
        var removals: [NSRange] = []
        var inFence = false
        var location = 0
        var lines: [NSRange] = []
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            lines.append(line)
            location = NSMaxRange(line)
        }

        for (index, line) in lines.enumerated() {
            var end = line.location + contentLength(of: line, in: ns)
            if end > line.location, ns.character(at: end - 1) == 0x0D { end -= 1 } // \r\n
            let content = ns.substring(with: NSRange(location: line.location, length: end - line.location))
            if isFence(content) {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            var trailingStart = end
            var hasTab = false
            while trailingStart > line.location {
                let character = ns.character(at: trailingStart - 1)
                guard character == 0x20 || character == 0x09 else { break }
                if character == 0x09 { hasTab = true }
                trailingStart -= 1
            }
            let trailing = end - trailingStart
            guard trailing > 0 else { continue }

            let isBlank = trailingStart == line.location
            var keep = 0
            if !isBlank, !hasTab, trailing >= 2, index + 1 < lines.count {
                let next = ns.substring(with: lines[index + 1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty { keep = 2 }
            }
            if trailing > keep {
                removals.append(NSRange(location: trailingStart + keep, length: trailing - keep))
            }
        }
        guard !removals.isEmpty else { return nil }

        let first = removals[0].location
        let last = NSMaxRange(removals[removals.count - 1])
        let region = NSRange(location: first, length: last - first)
        let result = NSMutableString(string: ns.substring(with: region))
        for removal in removals.reversed() {
            result.deleteCharacters(in: NSRange(location: removal.location - first, length: removal.length))
        }

        func map(_ position: Int) -> Int {
            var mapped = position
            for removal in removals {
                if removal.location >= position { break }
                mapped -= min(removal.length, position - removal.location)
            }
            return mapped
        }
        let start = map(selection.location)
        let end = map(NSMaxRange(selection))
        return LitteraTextEdit(range: region, replacement: result as String, selection: NSRange(location: start, length: end - start))
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3 else { return false }
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// La posición está dentro de un bloque de código cercado (se cuentan
    /// las líneas ``` o ~~~ anteriores).
    static func isInsideFence(_ ns: NSString, at location: Int) -> Bool {
        var inFence = false
        var position = 0
        while position < min(location, ns.length) {
            let line = ns.lineRange(for: NSRange(location: position, length: 0))
            guard NSMaxRange(line) <= location else { break }
            if isFence(ns.substring(with: line).trimmingCharacters(in: .newlines)) { inFence.toggle() }
            position = NSMaxRange(line)
        }
        return inFence
    }

    // MARK: - Mayúsculas y minúsculas

    private static func convertCase(in ns: NSString, selection: NSRange, _ transform: (String) -> String) -> LitteraTextEdit? {
        guard selection.length > 0 else { return nil }
        let original = ns.substring(with: selection)
        let converted = transform(original)
        guard converted != original else { return nil }
        return LitteraTextEdit(
            range: selection,
            replacement: converted,
            selection: NSRange(location: selection.location, length: (converted as NSString).length)
        )
    }

    // MARK: - Escritura asistida

    /// Intro en una lista: continúa con el marcador siguiente (`-`, `2.`,
    /// `- [ ]`). En un elemento vacío, termina la lista quitando el marcador.
    /// Fuera de listas o dentro de un bloque de código devuelve `nil`.
    static func continueList(in text: String, selection: NSRange) -> LitteraTextEdit? {
        let ns = text as NSString
        guard selection.length == 0, selection.location <= ns.length else { return nil }
        let caret = selection.location
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        let contentEnd = line.location + contentLength(of: line, in: ns)
        guard caret <= contentEnd, !isInsideFence(ns, at: line.location) else { return nil }

        let lineText = ns.substring(with: NSRange(location: line.location, length: contentEnd - line.location))
        let nsLine = lineText as NSString
        guard let item = listMarker(in: lineText) else { return nil }
        guard caret >= line.location + item.fullLength else { return nil }

        let rest = nsLine.substring(from: item.fullLength)
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // Elemento vacío: se termina la lista.
            return LitteraTextEdit(
                range: NSRange(location: line.location, length: contentEnd - line.location),
                replacement: "",
                selection: NSRange(location: line.location, length: 0)
            )
        }

        let marker: String
        if let bullet = item.bullet {
            marker = String(bullet)
        } else {
            marker = "\((item.number ?? 0) + 1)" + String(item.delimiter ?? ".")
        }
        var insertion = "\n" + item.indent + marker + item.spacing
        if item.taskChecked != nil { insertion += "[ ] " }
        return LitteraTextEdit(
            range: NSRange(location: caret, length: 0),
            replacement: insertion,
            selection: NSRange(location: caret + (insertion as NSString).length, length: 0)
        )
    }

    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "`": "`"]
    private static let closers: Set<Character> = [")", "]", "}", "\"", "`"]

    /// Cierre automático de `( [ { " \``. Con selección, la rodea. Si el
    /// carácter siguiente es el cierre que se escribe, solo avanza el cursor.
    static func autoPair(typing typed: String, in text: String, selection: NSRange) -> LitteraTextEdit? {
        guard typed.count == 1, let character = typed.first else { return nil }
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let next = selection.location + selection.length < ns.length
            ? Character(ns.substring(with: ns.rangeOfComposedCharacterSequence(at: NSMaxRange(selection)))) : nil
        let previous = selection.location > 0
            ? Character(ns.substring(with: ns.rangeOfComposedCharacterSequence(at: selection.location - 1))) : nil

        if selection.length == 0, closers.contains(character), next == character {
            return LitteraTextEdit(
                range: NSRange(location: selection.location, length: 0),
                replacement: "",
                selection: NSRange(location: selection.location + 1, length: 0)
            )
        }
        guard let closer = pairs[character] else { return nil }
        let open = String(character)
        let close = String(closer)

        if selection.length > 0 {
            let selected = ns.substring(with: selection)
            return LitteraTextEdit(
                range: selection,
                replacement: open + selected + close,
                selection: NSRange(location: selection.location + 1, length: selection.length)
            )
        }

        if let next, !(next.isWhitespace || ")]},.;:!?".contains(next)) { return nil }
        if character == "\"", let previous, previous.isLetter || previous.isNumber { return nil }
        // Tres acentos graves seguidos abren un bloque de código: no se emparejan.
        if character == "`", previous == "`" { return nil }
        return LitteraTextEdit(
            range: NSRange(location: selection.location, length: 0),
            replacement: open + close,
            selection: NSRange(location: selection.location + 1, length: 0)
        )
    }

    /// Después de escribir `character` (ya insertado justo antes de `caret`):
    /// si es un cierre y el siguiente carácter es el mismo, se quita el
    /// duplicado (equivale a «pasar por encima»); si es una apertura, se
    /// añade su cierre detrás del cursor. Funciona también cuando el carácter
    /// llega de una tecla muerta (el acento grave en el teclado español).
    static func completePair(typed character: Character, in text: String, caret: Int) -> LitteraTextEdit? {
        let ns = text as NSString
        guard caret >= 1, caret <= ns.length else { return nil }
        let next = caret < ns.length
            ? Character(ns.substring(with: ns.rangeOfComposedCharacterSequence(at: caret))) : nil
        let previous = caret >= 2
            ? Character(ns.substring(with: ns.rangeOfComposedCharacterSequence(at: caret - 2))) : nil

        if closers.contains(character), next == character {
            return LitteraTextEdit(
                range: NSRange(location: caret, length: 1),
                replacement: "",
                selection: NSRange(location: caret, length: 0)
            )
        }
        guard let closer = pairs[character] else { return nil }
        if let next, !(next.isWhitespace || ")]},.;:!?".contains(next)) { return nil }
        if character == "\"", let previous, previous.isLetter || previous.isNumber { return nil }
        // Tres acentos graves seguidos abren un bloque de código: no se emparejan.
        if character == "`", previous == "`" { return nil }
        return LitteraTextEdit(
            range: NSRange(location: caret, length: 0),
            replacement: String(closer),
            selection: NSRange(location: caret, length: 0)
        )
    }

    /// Retroceso entre una pareja vacía (`(|)`) borra los dos caracteres.
    static func deletePair(in text: String, selection: NSRange) -> LitteraTextEdit? {
        let ns = text as NSString
        guard selection.length == 0, selection.location > 0, selection.location < ns.length else { return nil }
        let previous = Character(ns.substring(with: NSRange(location: selection.location - 1, length: 1)))
        let next = Character(ns.substring(with: NSRange(location: selection.location, length: 1)))
        guard pairs[previous] == next else { return nil }
        return LitteraTextEdit(
            range: NSRange(location: selection.location - 1, length: 2),
            replacement: "",
            selection: NSRange(location: selection.location - 1, length: 0)
        )
    }

    /// Pegar una URL sobre texto seleccionado crea un enlace Markdown.
    static func linkFromPaste(_ pasted: String, in text: String, selection: NSRange) -> LitteraTextEdit? {
        let ns = text as NSString
        guard selection.length > 0, NSMaxRange(selection) <= ns.length else { return nil }
        let selected = ns.substring(with: selection)
        guard !selected.contains("\n"), !selected.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let candidate = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLinkableURL(candidate), !isLinkableURL(selected.trimmingCharacters(in: .whitespaces)) else { return nil }
        let destination = candidate.contains("(") || candidate.contains(")") ? "<\(candidate)>" : candidate
        let label = selected.replacingOccurrences(of: "]", with: "\\]")
        let replacement = "[\(label)](\(destination))"
        return LitteraTextEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0)
        )
    }

    static func isLinkableURL(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false
        case "mailto": return text.count > "mailto:".count
        default: return false
        }
    }

    private static func clamp(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}
