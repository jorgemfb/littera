import Foundation

/// Frontmatter YAML al principio del documento:
///
///     ---
///     title: Mi texto
///     tags: [a, b]
///     ---
///
/// Littera no lo interpreta como Markdown (sin esto, el `---` final convierte
/// la última línea en un encabezado). El texto se conserva tal cual.
nonisolated struct LitteraFrontmatter: Equatable, Sendable {
    /// Rango UTF-16 completo, delimitadores y salto de línea final incluidos.
    let range: NSRange
    /// Contenido YAML entre los delimitadores.
    let yaml: String
    /// Rango UTF-16 del contenido YAML (sin delimitadores).
    var yamlRange: NSRange = NSRange(location: 0, length: 0)

    /// Pares `clave: valor` de primer nivel, en orden. Las listas y los
    /// valores anidados se muestran como texto, sin interpretar.
    var entries: [(key: String, value: String)] {
        yaml.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            guard let first = line.first, !first.isWhitespace, first != "#", first != "-",
                  let colon = line.firstIndex(of: ":") else { return nil }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? nil : (key, value)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && lhs.yaml == rhs.yaml
    }

    /// Detecta el frontmatter: `---` en la primera línea y un cierre `---` o
    /// `...` en una línea propia.
    static func detect(in source: String) -> LitteraFrontmatter? {
        let text = source as NSString
        guard text.length >= 3 else { return nil }
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        guard trimmedLine(text, firstLine) == "---", NSMaxRange(firstLine) < text.length else { return nil }

        var location = NSMaxRange(firstLine)
        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let content = trimmedLine(text, line)
            if content == "---" || content == "..." {
                let yamlRange = NSRange(location: NSMaxRange(firstLine), length: line.location - NSMaxRange(firstLine))
                var yaml = text.substring(with: yamlRange)
                if yaml.hasSuffix("\n") { yaml.removeLast() }
                return LitteraFrontmatter(
                    range: NSRange(location: 0, length: NSMaxRange(line)),
                    yaml: yaml,
                    yamlRange: NSRange(location: yamlRange.location, length: (yaml as NSString).length)
                )
            }
            guard NSMaxRange(line) > location else { break }
            location = NSMaxRange(line)
        }
        return nil
    }

    /// El documento con el frontmatter sustituido por líneas vacías: las
    /// posiciones (línea y columna) del resto no cambian.
    func masking(_ source: String) -> String {
        let text = source as NSString
        let newlines = text.substring(with: range).reduce(0) { $1 == "\n" || $1 == "\r\n" ? $0 + 1 : $0 }
        return String(repeating: "\n", count: newlines) + text.substring(from: NSMaxRange(range))
    }

    private static func trimmedLine(_ text: NSString, _ line: NSRange) -> String {
        text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
