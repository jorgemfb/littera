import Foundation

/// Categoría sintáctica de un fragmento de código.
nonisolated enum LitteraSyntaxTokenKind: String, Sendable, Equatable, CaseIterable {
    case keyword
    case string
    case number
    case comment
    /// Claves de objetos (JSON, YAML) y propiedades CSS.
    case key
    case punctuation
    case type
    case function
    case variable
    case tag
    case attribute
}

/// Fragmento resaltado. `range` usa offsets UTF-16 relativos al código.
nonisolated struct LitteraSyntaxToken: Sendable, Equatable {
    let range: NSRange
    let kind: LitteraSyntaxTokenKind
}

/// Resaltador de sintaxis nativo, sin dependencias ni motores JavaScript.
///
/// Es un analizador léxico de una sola pasada con un perfil por lenguaje
/// (comentarios, cadenas, palabras clave, variables, etiquetas). No pretende
/// ser un analizador sintáctico completo: prioriza ser rápido, predecible y
/// seguro con cualquier entrada. Se ejecuta fuera del hilo principal, durante
/// el análisis del documento.
nonisolated enum LitteraSyntaxHighlighter {
    static func tokens(for code: String, language: String?) -> [LitteraSyntaxToken] {
        guard let profile = LanguageProfile.profile(for: language) else { return [] }
        var scanner = Scanner(code: code, profile: profile)
        return scanner.scan()
    }

    /// Indica si existe un perfil de resaltado para el lenguaje del bloque.
    static func supports(_ language: String?) -> Bool {
        LanguageProfile.profile(for: language) != nil
    }

    // MARK: - Perfiles

    struct LanguageProfile: Sendable {
        var lineComments: [String] = []
        var blockComments: [(open: String, close: String)] = []
        var stringDelimiters: Set<UInt16> = [0x22, 0x27] // " '
        var tripleQuotedStrings = false
        var keywords: Set<String> = []
        var builtinTypes: Set<String> = []
        var capitalizedTypes = false
        var variablePrefix: UInt16?          // $ en PHP y shell, @ en otros
        var keysBeforeColon = false          // JSON, YAML, CSS
        var bareKeysAtLineStart = false      // YAML
        var markup = false                   // HTML, XML
        var caseInsensitiveKeywords = false  // SQL
        var dashInIdentifiers = false        // CSS (font-size), YAML (my-key)

        static func profile(for language: String?) -> LanguageProfile? {
            guard let raw = language?.trimmingCharacters(in: .whitespaces).lowercased(),
                  let name = raw.split(separator: " ").first.map(String.init) else { return nil }
            switch name {
            case "json", "jsonc", "json5", "geojson":
                return LanguageProfile(
                    lineComments: name == "json" ? [] : ["//"],
                    stringDelimiters: [0x22],
                    keywords: ["true", "false", "null"],
                    keysBeforeColon: true
                )
            case "swift":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    stringDelimiters: [0x22], tripleQuotedStrings: true,
                    keywords: swiftKeywords, capitalizedTypes: true
                )
            case "php":
                return LanguageProfile(
                    lineComments: ["//", "#"], blockComments: [("/*", "*/")],
                    keywords: phpKeywords, variablePrefix: 0x24
                )
            case "js", "javascript", "jsx", "mjs", "cjs", "ts", "typescript", "tsx":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    stringDelimiters: [0x22, 0x27, 0x60],
                    keywords: javaScriptKeywords, capitalizedTypes: true
                )
            case "python", "py":
                return LanguageProfile(
                    lineComments: ["#"], tripleQuotedStrings: true,
                    keywords: pythonKeywords, capitalizedTypes: true
                )
            case "bash", "sh", "zsh", "shell", "console", "shellsession":
                return LanguageProfile(
                    lineComments: ["#"], keywords: shellKeywords, variablePrefix: 0x24
                )
            case "html", "xml", "svg", "xhtml", "plist", "vue":
                return LanguageProfile(
                    blockComments: [("<!--", "-->")], markup: true
                )
            case "css", "scss", "less":
                return LanguageProfile(
                    lineComments: name == "css" ? [] : ["//"], blockComments: [("/*", "*/")],
                    keywords: ["important", "media", "import", "include", "mixin", "extend"],
                    variablePrefix: name == "scss" ? 0x24 : nil, keysBeforeColon: true,
                    dashInIdentifiers: true
                )
            case "sql", "mysql", "postgresql", "postgres", "sqlite":
                return LanguageProfile(
                    lineComments: ["--"], blockComments: [("/*", "*/")],
                    keywords: sqlKeywords, caseInsensitiveKeywords: true
                )
            case "mermaid":
                return LanguageProfile(
                    lineComments: ["%%"],
                    stringDelimiters: [0x22],
                    keywords: mermaidKeywords
                )
            case "yaml", "yml":
                return LanguageProfile(
                    lineComments: ["#"],
                    keywords: ["true", "false", "null", "yes", "no", "on", "off"],
                    keysBeforeColon: true, bareKeysAtLineStart: true,
                    dashInIdentifiers: true
                )
            case "ruby", "rb":
                return LanguageProfile(
                    lineComments: ["#"], keywords: rubyKeywords,
                    capitalizedTypes: true, variablePrefix: 0x40
                )
            case "go", "golang":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    stringDelimiters: [0x22, 0x27, 0x60],
                    keywords: goKeywords, builtinTypes: goTypes
                )
            case "rust", "rs":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    stringDelimiters: [0x22],
                    keywords: rustKeywords, builtinTypes: rustTypes, capitalizedTypes: true
                )
            case "java", "kotlin", "kt", "kts", "scala", "dart":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    tripleQuotedStrings: name != "java",
                    keywords: jvmKeywords, capitalizedTypes: true
                )
            case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "objectivec", "m", "mm", "cs", "csharp":
                return LanguageProfile(
                    lineComments: ["//"], blockComments: [("/*", "*/")],
                    keywords: cFamilyKeywords, capitalizedTypes: name.hasPrefix("obj") || name == "cs" || name == "csharp"
                )
            default:
                return nil
            }
        }
    }

    // MARK: - Analizador

    private struct Scanner {
        let text: [UInt16]
        let profile: LanguageProfile
        var tokens: [LitteraSyntaxToken] = []

        init(code: String, profile: LanguageProfile) {
            text = Array(code.utf16)
            self.profile = profile
        }

        mutating func scan() -> [LitteraSyntaxToken] {
            var index = 0
            var atLineStart = true
            var insideTag = false

            while index < text.count {
                let unit = text[index]

                if unit == 0x0A { // \n
                    atLineStart = true
                    index += 1
                    continue
                }
                if unit == 0x20 || unit == 0x09 || unit == 0x0D {
                    index += 1
                    continue
                }

                // Comentarios.
                if let end = blockCommentEnd(at: index) {
                    add(index, end, .comment)
                    index = end
                    continue
                }
                if matchesAny(profile.lineComments, at: index), !(profile.markup) {
                    let end = lineEnd(from: index)
                    add(index, end, .comment)
                    index = end
                    continue
                }

                // Marcado (HTML, XML).
                if profile.markup {
                    if unit == 0x3C { // <
                        var cursor = index + 1
                        if cursor < text.count, text[cursor] == 0x2F || text[cursor] == 0x21 || text[cursor] == 0x3F { cursor += 1 }
                        let nameEnd = identifierEnd(from: cursor, allowDash: true)
                        add(index, cursor, .punctuation)
                        if nameEnd > cursor { add(cursor, nameEnd, .tag) }
                        insideTag = true
                        index = max(nameEnd, cursor)
                        atLineStart = false
                        continue
                    }
                    if insideTag, unit == 0x3E || (unit == 0x2F && peek(index + 1) == 0x3E) { // > o />
                        let end = unit == 0x2F ? index + 2 : index + 1
                        add(index, end, .punctuation)
                        insideTag = false
                        index = end
                        continue
                    }
                    if insideTag, isIdentifierStart(unit) {
                        let end = identifierEnd(from: index, allowDash: true)
                        add(index, end, .attribute)
                        index = end
                        continue
                    }
                    if insideTag, profile.stringDelimiters.contains(unit) {
                        let end = stringEnd(from: index, delimiter: unit)
                        add(index, end, .string)
                        index = end
                        continue
                    }
                    if !insideTag {
                        index += 1
                        continue
                    }
                }

                // Cadenas.
                if profile.stringDelimiters.contains(unit) {
                    let end = stringEnd(from: index, delimiter: unit)
                    let kind: LitteraSyntaxTokenKind = profile.keysBeforeColon && nextNonSpace(from: end) == 0x3A
                        ? .key : .string
                    add(index, end, kind)
                    index = end
                    atLineStart = false
                    continue
                }

                // Variables ($nombre, @nombre).
                if let prefix = profile.variablePrefix, unit == prefix,
                   index + 1 < text.count,
                   isIdentifierStart(text[index + 1]) || (prefix == 0x24 && text[index + 1] == 0x7B) {
                    var end: Int
                    if text[index + 1] == 0x7B { // ${...}
                        end = index + 2
                        while end < text.count, text[end] != 0x7D, text[end] != 0x0A { end += 1 }
                        if end < text.count, text[end] == 0x7D { end += 1 }
                    } else {
                        end = identifierEnd(from: index + 1, allowDash: false)
                    }
                    add(index, end, .variable)
                    index = end
                    atLineStart = false
                    continue
                }

                // Números.
                if isDigit(unit) || (unit == 0x2D && isDigit(peek(index + 1)) && !previousIsIdentifier(index) && profile.keysBeforeColon) {
                    guard !previousIsIdentifier(index) else {
                        index += 1
                        continue
                    }
                    let end = numberEnd(from: unit == 0x2D ? index + 1 : index)
                    add(index, end, .number)
                    index = end
                    atLineStart = false
                    continue
                }

                // Identificadores: palabras clave, tipos, funciones, claves.
                if isIdentifierStart(unit) {
                    let end = identifierEnd(from: index, allowDash: profile.dashInIdentifiers)
                    let word = String(utf16CodeUnits: Array(text[index..<end]), count: end - index)
                    let next = nextNonSpace(from: end)
                    if profile.bareKeysAtLineStart, atLineStart || previousNonSpace(before: index) == 0x2D, next == 0x3A {
                        add(index, end, .key)
                    } else if profile.keysBeforeColon, profile.dashInIdentifiers, next == 0x3A, atLineStart {
                        // Propiedades CSS.
                        add(index, end, .key)
                    } else if isKeyword(word) {
                        add(index, end, .keyword)
                    } else if profile.builtinTypes.contains(word)
                                || (profile.capitalizedTypes && word.first?.isUppercase == true) {
                        add(index, end, .type)
                    } else if next == 0x28 { // (
                        add(index, end, .function)
                    }
                    index = end
                    atLineStart = false
                    continue
                }

                // Puntuación estructural.
                if Self.punctuation.contains(unit) {
                    add(index, index + 1, .punctuation)
                }
                index += 1
                atLineStart = false
            }
            return tokens
        }

        private static let punctuation: Set<UInt16> = [
            0x7B, 0x7D, 0x5B, 0x5D, 0x28, 0x29, 0x2C, 0x3A, 0x3B // { } [ ] ( ) , : ;
        ]

        private func isKeyword(_ word: String) -> Bool {
            profile.keywords.contains(profile.caseInsensitiveKeywords ? word.lowercased() : word)
        }

        private mutating func add(_ start: Int, _ end: Int, _ kind: LitteraSyntaxTokenKind) {
            guard end > start else { return }
            tokens.append(LitteraSyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
        }

        private func peek(_ index: Int) -> UInt16 {
            index < text.count ? text[index] : 0
        }

        private func matches(_ value: String, at index: Int) -> Bool {
            let units = Array(value.utf16)
            guard index + units.count <= text.count else { return false }
            for offset in 0..<units.count where text[index + offset] != units[offset] { return false }
            return true
        }

        private func matchesAny(_ values: [String], at index: Int) -> Bool {
            values.contains { matches($0, at: index) }
        }

        private func blockCommentEnd(at index: Int) -> Int? {
            for (open, close) in profile.blockComments where matches(open, at: index) {
                var cursor = index + open.utf16.count
                while cursor < text.count {
                    if matches(close, at: cursor) { return cursor + close.utf16.count }
                    cursor += 1
                }
                return text.count
            }
            return nil
        }

        private func lineEnd(from index: Int) -> Int {
            var cursor = index
            while cursor < text.count, text[cursor] != 0x0A { cursor += 1 }
            return cursor
        }

        private func stringEnd(from index: Int, delimiter: UInt16) -> Int {
            let triple = profile.tripleQuotedStrings
                && peek(index + 1) == delimiter && peek(index + 2) == delimiter
            var cursor = index + (triple ? 3 : 1)
            while cursor < text.count {
                let unit = text[cursor]
                if unit == 0x5C { // \ escapa el siguiente carácter
                    cursor += 2
                    continue
                }
                if triple {
                    if unit == delimiter, peek(cursor + 1) == delimiter, peek(cursor + 2) == delimiter {
                        return cursor + 3
                    }
                } else {
                    if unit == delimiter { return cursor + 1 }
                    // Las cadenas simples no cruzan líneas, salvo las de plantilla (`).
                    if unit == 0x0A, delimiter != 0x60 { return cursor }
                }
                cursor += 1
            }
            return text.count
        }

        private func numberEnd(from index: Int) -> Int {
            var cursor = index
            while cursor < text.count {
                let unit = text[cursor]
                if isDigit(unit) || isIdentifierPart(unit) || unit == 0x2E { // dígitos, 0x, 1e5, 1_000, .
                    if unit == 0x2E, !isDigit(peek(cursor + 1)) { break }
                    cursor += 1
                } else {
                    break
                }
            }
            return cursor
        }

        private func identifierEnd(from index: Int, allowDash: Bool) -> Int {
            var cursor = index
            while cursor < text.count,
                  isIdentifierPart(text[cursor]) || (allowDash && (text[cursor] == 0x2D || text[cursor] == 0x3A && profile.markup)) {
                cursor += 1
            }
            return cursor
        }

        private func nextNonSpace(from index: Int) -> UInt16 {
            var cursor = index
            while cursor < text.count, text[cursor] == 0x20 || text[cursor] == 0x09 { cursor += 1 }
            return peek(cursor)
        }

        private func previousNonSpace(before index: Int) -> UInt16 {
            var cursor = index - 1
            while cursor >= 0, text[cursor] == 0x20 || text[cursor] == 0x09 { cursor -= 1 }
            return cursor >= 0 ? text[cursor] : 0
        }

        private func previousIsIdentifier(_ index: Int) -> Bool {
            index > 0 && isIdentifierPart(text[index - 1])
        }

        private func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }

        private func isIdentifierStart(_ unit: UInt16) -> Bool {
            (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F || unit > 0x7F
        }

        private func isIdentifierPart(_ unit: UInt16) -> Bool {
            isIdentifierStart(unit) || isDigit(unit)
        }
    }

    // MARK: - Palabras clave

    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "default",
        "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final",
        "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "lazy", "mutating",
        "nil", "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat",
        "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while"
    ]
    private static let phpKeywords: Set<String> = [
        "abstract", "and", "array", "as", "break", "case", "catch", "class", "clone", "const", "continue",
        "declare", "default", "do", "echo", "else", "elseif", "empty", "enum", "extends", "false", "final",
        "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "include_once",
        "instanceof", "interface", "isset", "list", "match", "namespace", "new", "null", "or", "print",
        "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch",
        "throw", "trait", "true", "try", "unset", "use", "var", "while", "yield"
    ]
    private static let javaScriptKeywords: Set<String> = [
        "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for",
        "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "keyof", "let",
        "namespace", "new", "null", "of", "private", "protected", "public", "readonly", "return", "set",
        "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var",
        "void", "while", "with", "yield"
    ]
    private static let pythonKeywords: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
        "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda",
        "match", "case", "nonlocal", "not", "or", "pass", "raise", "return", "self", "try", "while", "with", "yield"
    ]
    private static let shellKeywords: Set<String> = [
        "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function", "if", "in", "local",
        "readonly", "return", "select", "then", "until", "while", "echo", "exit", "source", "sudo", "cd"
    ]
    private static let mermaidKeywords: Set<String> = [
        "graph", "flowchart", "subgraph", "end", "direction", "TD", "TB", "BT", "LR", "RL",
        "classDef", "class", "style", "linkStyle", "click", "accTitle", "accDescr",
        "sequenceDiagram", "classDiagram", "stateDiagram", "erDiagram", "gantt", "pie", "journey", "mindmap", "timeline"
    ]
    private static let sqlKeywords: Set<String> = [
        "add", "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "check", "column", "commit",
        "constraint", "create", "cross", "database", "default", "delete", "desc", "distinct", "drop", "else",
        "end", "exists", "false", "foreign", "from", "full", "group", "having", "if", "in", "index", "inner",
        "insert", "into", "is", "join", "key", "left", "like", "limit", "not", "null", "offset", "on", "or",
        "order", "outer", "primary", "references", "returning", "right", "rollback", "select", "set", "table",
        "then", "true", "union", "unique", "update", "values", "view", "when", "where", "with",
        "int", "integer", "text", "varchar", "boolean", "date", "timestamp", "serial", "bigint", "real"
    ]
    private static let rubyKeywords: Set<String> = [
        "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
        "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
        "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require"
    ]
    private static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for",
        "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select",
        "struct", "switch", "true", "type", "var"
    ]
    private static let goTypes: Set<String> = [
        "bool", "byte", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune",
        "string", "uint", "uint8", "uint16", "uint32", "uint64", "any"
    ]
    private static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
        "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
        "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"
    ]
    private static let rustTypes: Set<String> = [
        "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32",
        "u64", "u128", "usize"
    ]
    private static let jvmKeywords: Set<String> = [
        "abstract", "as", "boolean", "break", "byte", "case", "catch", "char", "class", "companion", "const",
        "continue", "data", "default", "do", "double", "else", "enum", "extends", "false", "final", "finally",
        "float", "for", "fun", "if", "implements", "import", "in", "int", "interface", "is", "long", "new", "null",
        "object", "override", "package", "private", "protected", "public", "return", "sealed", "short",
        "static", "super", "switch", "this", "throw", "throws", "true", "try", "val", "var", "void", "when", "while"
    ]
    private static let cFamilyKeywords: Set<String> = [
        "auto", "bool", "break", "case", "catch", "char", "class", "const", "continue", "default", "delete",
        "do", "double", "else", "enum", "extern", "false", "float", "for", "goto", "if", "include", "define",
        "inline", "int", "long", "namespace", "new", "nil", "NULL", "nullptr", "private", "protected", "public",
        "return", "self", "short", "signed", "sizeof", "static", "struct", "switch", "template", "this", "throw",
        "true", "try", "typedef", "typename", "union", "unsigned", "using", "virtual", "void", "volatile",
        "while", "YES", "NO", "id", "string", "var", "async", "await"
    ]
}
