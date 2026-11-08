import Foundation

/// Estado del documento en el panel de propiedades (D53). En el YAML se
/// guarda el valor en inglés (`status: in-progress`), compatible con otras
/// herramientas.
nonisolated enum LitteraPropertyStatus: String, CaseIterable, Identifiable, Sendable {
    case draft
    case inProgress = "in-progress"
    case review
    case done

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .draft: "ui.estado.borrador"
        case .inProgress: "ui.estado.en.desarrollo"
        case .review: "ui.estado.en.revision"
        case .done: "ui.estado.terminado"
        }
    }

    var symbol: String {
        switch self {
        case .draft: "circle"
        case .inProgress: "circle.dashed"
        case .review: "circle.lefthalf.filled"
        case .done: "checkmark.circle"
        }
    }

    /// Acepta también variantes habituales (`In progress`, `in_progress`).
    init?(yamlValue: String) {
        let normalized = yamlValue.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        guard let status = Self(rawValue: normalized) else { return nil }
        self = status
    }
}

/// Propiedades del documento leídas del frontmatter YAML. Las claves que el
/// panel no conoce se conservan y se muestran como texto.
nonisolated struct LitteraDocumentProperties: Equatable, Sendable {
    static let titleKey = "title"
    static let statusKey = "status"
    static let tagsKey = "tags"
    static let createdKey = "created"
    static let updatedKey = "updated"
    static let tocKey = "toc"
    static let descriptionKey = "description"
    static let authorKey = "author"
    static let versionKey = "version"
    static let projectKey = "project"
    static let requirementsKey = "requirements"
    /// Claves con su propio valor en este tipo (el resto va a `extras`).
    static let knownKeys: Set<String> = [titleKey, statusKey, tagsKey, createdKey, updatedKey, tocKey]

    /// Propiedades que el panel ofrece siempre, en este orden, aunque el
    /// documento no las tenga (vacías: no se inventa ningún valor).
    static let managedKeys = [
        titleKey, descriptionKey, tagsKey, authorKey, createdKey,
        updatedKey, versionKey, statusKey, projectKey, requirementsKey,
    ]
    /// Gestionadas que se editan como texto o lista genéricos.
    static let managedExtraKeys = [descriptionKey, authorKey, versionKey, projectKey, requirementsKey]
    /// Gestionadas que son listas de textos.
    static let managedListKeys: Set<String> = [tagsKey, requirementsKey]

    /// Otra clave de primer nivel. Todas se pueden editar: los valores de
    /// una línea como texto, las listas de valores simples como etiquetas y
    /// el resto (objetos, listas de objetos, textos multilínea) como YAML.
    struct Extra: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            /// Valor de una línea; `quoted` si estaba entre comillas.
            case scalar(text: String, quoted: Bool)
            /// Lista de valores simples; `block` si estaba escrita con `- `.
            case list(items: [String], block: Bool)
            /// YAML de varias líneas sin sangría; `header` es lo que sigue a
            /// los dos puntos (`|`, `>-`…), normalmente vacío.
            case block(text: String, header: String, indent: String)
        }

        let key: String
        let kind: Kind
        /// Valor YAML cuando el bloque se queda vacío: `{}` en los mapas.
        var emptyBlockValue = ""
        /// La clave aún no está en el documento (campo vacío del panel).
        var isMissing = false
        var id: String { key }

        /// Texto YAML del valor a partir de lo editado, con el mismo estilo
        /// que tenía (comillas, lista en bloque o en línea, sangría).
        func yamlValue(scalar text: String) -> String {
            guard case let .scalar(_, quoted) = kind else { return text }
            // Valor nuevo: comillas solo si hacen falta para que siga siendo
            // texto (`"2.10"` no se convierte en el número 2.1).
            if isMissing { return LitteraDocumentProperties.scalar(text) }
            if quoted { return LitteraDocumentProperties.quotedScalar(text) }
            // Sin comillas se escribe tal cual (números, `null`, fechas…),
            // salvo que el texto rompa el YAML.
            let breaksYAML = text.contains(": ") || text.contains(" #") || text.hasPrefix("#")
                || text.hasSuffix(":") || text.contains("\n")
            return breaksYAML ? LitteraDocumentProperties.quotedScalar(text) : text
        }

        func yamlValue(list items: [String]) -> String {
            guard case let .list(_, block) = kind, block, !items.isEmpty else {
                return LitteraDocumentProperties.flowList(items)
            }
            return LitteraDocumentProperties.blockList(items)
        }

        func yamlValue(block text: String) -> String {
            guard case let .block(_, header, indent) = kind else { return text }
            var lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? "" : indent + $0 }
            while lines.last == "" { lines.removeLast() }
            while lines.first == "" { lines.removeFirst() }
            guard !lines.isEmpty else { return header.isEmpty ? emptyBlockValue : header }
            // Con cabecera (`|`, `>`) queda `clave: |` y el texto debajo.
            return header + "\n" + lines.joined(separator: "\n")
        }
    }

    var title = ""
    var status: String?
    var tags: [String] = []
    /// Las etiquetas estaban escritas como lista en bloque (`- a`).
    var tagsUseBlockStyle = false
    var created: String?
    var updated: String?
    var toc = false
    var extras: [Extra] = []

    init() {}

    init(frontmatter: LitteraFrontmatter?) {
        self.init(yaml: frontmatter?.yaml ?? "")
    }

    init(yaml: String) {
        for entry in Self.topLevelEntries(in: yaml) {
            let value = entry.value
            switch entry.key {
            case Self.titleKey:
                title = Self.unquote(value)
            case Self.statusKey:
                let status = Self.unquote(value)
                self.status = status.isEmpty ? nil : status
            case Self.tagsKey:
                tags = Self.list(value: value, block: entry.block)
                tagsUseBlockStyle = value.isEmpty && !entry.block.isEmpty
            case Self.createdKey:
                let created = Self.unquote(value)
                self.created = created.isEmpty ? nil : created
            case Self.updatedKey:
                let updated = Self.unquote(value)
                self.updated = updated.isEmpty ? nil : updated
            case Self.tocKey:
                toc = ["true", "yes", "on"].contains(Self.unquote(value).lowercased())
            default:
                if value == "{}", entry.block.isEmpty {
                    // Mapa vacío (`custom: {}`): se edita como YAML.
                    extras.append(Extra(key: entry.key, kind: .block(text: "", header: "", indent: "  "), emptyBlockValue: "{}"))
                } else {
                    extras.append(Extra(key: entry.key, kind: Self.extraKind(value: value, block: entry.block)))
                }
            }
        }
    }

    /// Valor YAML de las etiquetas, con el estilo que tenían.
    func tagsYAMLValue(_ tags: [String]) -> String {
        tagsUseBlockStyle && !tags.isEmpty ? Self.blockList(tags) : Self.flowList(tags)
    }

    private static func extraKind(value: String, block: [String]) -> Extra.Kind {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if block.isEmpty {
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.dropFirst().contains("[") {
                return .list(items: splitFlow(String(trimmed.dropFirst().dropLast())), block: false)
            }
            let quoted = trimmed.count >= 2 && (trimmed.hasPrefix("\"") || trimmed.hasPrefix("'"))
                && trimmed.last == trimmed.first
            return .scalar(text: quoted ? unquote(trimmed) : trimmed, quoted: quoted)
        }
        let content = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let isSimpleList = trimmed.isEmpty && content.allSatisfy { line in
            let item = line.trimmingCharacters(in: .whitespaces)
            guard item.hasPrefix("- ") || item == "-" else { return false }
            let rest = item.dropFirst().trimmingCharacters(in: .whitespaces)
            return !rest.isEmpty && !rest.hasPrefix("[") && !rest.hasPrefix("{") && !rest.hasPrefix("- ")
                && !(rest.contains(": ") && !rest.hasPrefix("\"") && !rest.hasPrefix("'"))
        } && Set(content.map { $0.prefix(while: \.isWhitespace) }).count == 1
        if isSimpleList {
            return .list(items: list(value: "", block: block), block: true)
        }
        let indent = content.map { String($0.prefix(while: \.isWhitespace)) }.min { $0.count < $1.count } ?? "  "
        let text = block.map { line in
            line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : line.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
        return .block(text: text, header: trimmed, indent: indent.isEmpty ? "  " : indent)
    }

    var knownStatus: LitteraPropertyStatus? { status.flatMap(LitteraPropertyStatus.init(yamlValue:)) }

    /// Fecha de creación si tiene la forma `AAAA-MM-DD` (con o sin hora).
    var createdDate: Date? { Self.date(from: created) }
    var updatedDate: Date? { Self.date(from: updated) }

    /// Valor de una fecha del panel (`created`, `updated`).
    func dateValue(for key: String) -> String? {
        key == Self.updatedKey ? updated : created
    }

    static func date(from value: String?) -> Date? {
        guard let value, value.count >= 10 else { return nil }
        return dayFormatter.date(from: String(value.prefix(10)))
    }

    // MARK: - Esquema normalizado

    /// Valor de una clave del esquema cuando el documento no la tiene.
    enum EmptyValue: Sendable {
        case text, list, null, flag, map
        var yaml: String {
            switch self {
            case .text: "\"\""
            case .list: "[]"
            case .null: "null"
            case .flag: "false"
            case .map: "{}"
            }
        }
    }

    struct SchemaField: Sendable {
        let key: String
        let empty: EmptyValue
    }

    /// Sección del frontmatter: un comentario `# TÍTULO` y sus claves. El
    /// título forma parte del documento (no de la interfaz), en español o en
    /// inglés.
    struct SchemaSection: Sendable {
        let spanish: String
        let english: String
        let fields: [SchemaField]
    }

    /// Esquema de la plantilla de documento nuevo vigente (secciones y
    /// claves vacías). Solo sirve para generar y reconocer esa plantilla:
    /// editar una propiedad ya no reordena ni completa el frontmatter.
    static let schema: [SchemaSection] = [
        SchemaSection(spanish: "IDENTIFICACIÓN", english: "IDENTIFICATION", fields: [
            .init(key: titleKey, empty: .text), .init(key: "subtitle", empty: .text),
            .init(key: "description", empty: .text), .init(key: "slug", empty: .text),
            .init(key: "aliases", empty: .list),
        ]),
        SchemaSection(spanish: "AUTORÍA", english: "AUTHORSHIP", fields: [
            .init(key: "author", empty: .text), .init(key: "contributors", empty: .list),
            .init(key: "copyright", empty: .text), .init(key: "license", empty: .text),
        ]),
        SchemaSection(spanish: "FECHAS", english: "DATES", fields: [
            .init(key: "date", empty: .null), .init(key: createdKey, empty: .null),
            .init(key: "modified", empty: .null),
        ]),
        SchemaSection(spanish: "CLASIFICACIÓN", english: "CLASSIFICATION", fields: [
            .init(key: tagsKey, empty: .list), .init(key: "categories", empty: .list),
            .init(key: "keywords", empty: .list),
        ]),
        SchemaSection(spanish: "IDIOMA", english: "LANGUAGE", fields: [
            .init(key: "lang", empty: .text), .init(key: "translation_of", empty: .null),
        ]),
        SchemaSection(spanish: "ESTADO DEL DOCUMENTO", english: "DOCUMENT STATUS", fields: [
            .init(key: statusKey, empty: .text), .init(key: "version", empty: .text),
            .init(key: "revision", empty: .null), .init(key: "priority", empty: .text),
            .init(key: "progress", empty: .null),
        ]),
        SchemaSection(spanish: "ORGANIZACIÓN", english: "ORGANIZATION", fields: [
            .init(key: "project", empty: .text), .init(key: "type", empty: .text),
            .init(key: "folder", empty: .text), .init(key: "collection", empty: .text),
            .init(key: "series", empty: .null), .init(key: "order", empty: .null),
        ]),
        SchemaSection(spanish: "RELACIONES", english: "RELATIONS", fields: [
            .init(key: "parent", empty: .null), .init(key: "related", empty: .list),
        ]),
        SchemaSection(spanish: "CAMPOS PERSONALIZADOS", english: "CUSTOM FIELDS", fields: [
            .init(key: "custom", empty: .map),
        ]),
    ]

    static let schemaFields: [SchemaField] = schema.flatMap(\.fields) + [SchemaField(key: tocKey, empty: .flag)]
    static let schemaKeys: Set<String> = Set(schemaFields.map(\.key))

    /// Idioma de los títulos de sección: el que ya use el documento o, si no
    /// tiene ninguno, el de la interfaz.
    private static func sectionLanguage(in yaml: String, preferred: String) -> String {
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if schema.contains(where: { "# " + $0.english == trimmed }) { return "en" }
            if schema.contains(where: { "# " + $0.spanish == trimmed }) { return "es" }
        }
        return preferred == "en" ? "en" : "es"
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return schema.contains { "# " + $0.spanish == trimmed || "# " + $0.english == trimmed }
    }

    /// Frontmatter normalizado: todas las propiedades del esquema, en su
    /// orden y agrupadas por secciones. Las que ya tenía el documento se
    /// copian tal cual (valor, comillas, listas, comentarios propios); las que
    /// faltan se añaden vacías (o con `values`). Nada se pierde: las claves
    /// desconocidas y los comentarios sueltos pasan a «Campos personalizados».
    static func normalizedYAML(_ yaml: String, language: String = "es", values: [String: String] = [:]) -> String {
        let lines = yaml.isEmpty ? [] : yaml.components(separatedBy: "\n")
        let entries = topLevelEntries(in: yaml)
        var used = Set<Int>()
        var linesByKey: [String: [String]] = [:]
        var others: [[String]] = []

        for entry in entries {
            // Comentarios propios justo encima de la clave: viajan con ella.
            var start = entry.lines.lowerBound
            while start > 0, lines[start - 1].hasPrefix("#"), !isSectionHeader(lines[start - 1]), !used.contains(start - 1) {
                start -= 1
            }
            let block = Array(lines[start...entry.lines.upperBound])
            for index in start...entry.lines.upperBound { used.insert(index) }
            if schemaKeys.contains(entry.key), linesByKey[entry.key] == nil {
                linesByKey[entry.key] = block
            } else {
                others.append(block)
            }
        }
        // Comentarios y líneas sueltas que no pertenecen a ninguna clave.
        for (index, line) in lines.enumerated() where !used.contains(index) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isSectionHeader(line) { continue }
            others.append([line])
        }

        let english = sectionLanguage(in: yaml, preferred: language) == "en"
        var output: [String] = []
        for (index, section) in schema.enumerated() {
            if index > 0 { output.append("") }
            output.append("# " + (english ? section.english : section.spanish))
            for field in section.fields {
                output += linesByKey[field.key] ?? [line(key: field.key, value: values[field.key] ?? field.empty.yaml)]
            }
        }
        for block in others { output += block }
        output += linesByKey[tocKey] ?? [line(key: tocKey, value: values[tocKey] ?? EmptyValue.flag.yaml)]
        return output.joined(separator: "\n")
    }

    /// `true` si el YAML ya está normalizado (mismas claves y orden).
    static func isNormalized(_ yaml: String) -> Bool {
        normalizedYAML(yaml, language: sectionLanguage(in: yaml, preferred: "es")) == yaml
    }

    /// Una propiedad gestionada que se edita como texto o lista: la del
    /// documento o, si falta, un campo vacío que no escribe nada hasta que
    /// se rellena.
    func managedExtra(_ key: String) -> Extra {
        if let extra = extras.first(where: { $0.key == key }) { return extra }
        let kind: Extra.Kind = Self.managedListKeys.contains(key)
            ? .list(items: [], block: true)
            : .scalar(text: "", quoted: false)
        return Extra(key: key, kind: kind, isMissing: true)
    }

    /// Las demás claves del documento, en su orden (desconocidas incluidas).
    var otherExtras: [Extra] {
        extras.filter { !Self.managedExtraKeys.contains($0.key) }
    }

    /// Campos editables del panel: los gestionados y después los demás.
    var panelExtras: [Extra] {
        Self.managedExtraKeys.map(managedExtra) + otherExtras
    }

    // MARK: - Edición segura

    /// Por qué Littera no puede cambiar este frontmatter sin riesgo de
    /// alterar lo que no se edita. Entonces el panel solo muestra los valores.
    enum EditingLimitation: Equatable, Sendable {
        /// Empieza con `---` pero no tiene la línea de cierre.
        case unclosedFrontmatter
        /// YAML que el editor de líneas no interpreta con seguridad (anclas,
        /// tabuladores, valores de varias líneas sin cerrar, claves repetidas,
        /// raíz que no es un mapa…). `line` empieza en 1.
        case unsupportedYAML(line: Int)
    }

    static func editingLimitation(in source: String) -> EditingLimitation? {
        guard let frontmatter = LitteraFrontmatter.detect(in: source) else {
            let firstLine = source.prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
            return firstLine == "---" ? .unclosedFrontmatter : nil
        }
        return unsupportedLine(in: frontmatter.yaml).map { .unsupportedYAML(line: $0) }
    }

    /// Primera línea (desde 1) que impide editar el YAML línea a línea.
    static func unsupportedLine(in yaml: String) -> Int? {
        guard !yaml.isEmpty else { return nil }
        var seenKeys = Set<String>()
        var hasKey = false
        for (index, line) in yaml.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") { return index + 1 }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            // Indicadores YAML en la raíz (`{…}`, `[…]`, `? clave`, `&ancla`…).
            if let first = line.first, "{[?!&*|>%@`".contains(first) { return index + 1 }
            if let key = topLevelKey(line) {
                hasKey = true
                guard key != "<<", seenKeys.insert(key).inserted else { return index + 1 }
                let colon = line.firstIndex(of: ":")!
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !isSafeInlineValue(value) { return index + 1 }
            } else if line.first?.isWhitespace == true || line.first == "-" {
                // Contenido de la clave anterior; sin clave, la raíz es una lista.
                guard hasKey else { return index + 1 }
                let item = trimmed.hasPrefix("-") ? trimmed.dropFirst().trimmingCharacters(in: .whitespaces) : trimmed
                if item.hasPrefix("&") || item.hasPrefix("*") || trimmed.contains(": &") || trimmed.contains(": *") {
                    return index + 1
                }
            } else {
                // `{…}` en la raíz, claves complejas `?`, otro documento `---`…
                return index + 1
            }
        }
        return nil
    }

    /// Un valor en la línea de su clave que se puede sustituir entero.
    private static func isSafeInlineValue(_ value: String) -> Bool {
        guard let first = value.first else { return true }
        if first == "&" || first == "*" { return false }
        if first == "[" || first == "{" {
            let closing: Character = first == "[" ? "]" : "}"
            return stripComment(value).last == closing
        }
        if first == "\"" || first == "'" {
            // La comilla de cierre en la misma línea (sin contar las escapadas).
            var escaping = false
            for character in value.dropFirst() {
                if escaping { escaping = false; continue }
                if first == "\"", character == "\\" { escaping = true; continue }
                if character == first { return true }
            }
            return false
        }
        return true
    }

    // MARK: - Plantilla

    /// Frontmatter de un documento nuevo: el esquema completo, con el estado
    /// «borrador» y la fecha de hoy.
    static func newDocumentTemplate(date: Date = Date(), timeZone: TimeZone = .current, language: String = "es") -> String {
        let day = dayString(from: date, timeZone: timeZone)
        let yaml = normalizedYAML("", language: language, values: [
            statusKey: LitteraPropertyStatus.draft.rawValue,
            "date": day, createdKey: day, "modified": day,
        ])
        return "---\n" + yaml + "\n---\n\n"
    }

    /// Plantilla de 1.2.0–1.2.2 (cinco propiedades).
    private static func legacyTemplate(date: Date, timeZone: TimeZone) -> String {
        "---\n\(titleKey): \"\"\n\(statusKey): \(LitteraPropertyStatus.draft.rawValue)\n\(tagsKey): []\n"
            + "\(createdKey): \(dayString(from: date, timeZone: timeZone))\n\(tocKey): false\n---\n\n"
    }

    /// `true` si el texto es la plantilla de un documento nuevo sin tocar
    /// (también las de 1.1.0 y 1.2.x).
    static func isNewDocumentTemplate(_ text: String) -> Bool {
        if text == "---\n\n---\n\n" { return true }
        guard text.hasPrefix("---\n"),
              let created = LitteraDocumentProperties(frontmatter: LitteraFrontmatter.detect(in: text)).createdDate else {
            return false
        }
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        return text == legacyTemplate(date: created, timeZone: utc)
            || text == newDocumentTemplate(date: created, timeZone: utc, language: "es")
            || text == newDocumentTemplate(date: created, timeZone: utc, language: "en")
    }

    static func dayString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Valores YAML

    /// Texto de un escalar YAML: entre comillas solo cuando hace falta.
    static func scalar(_ text: String) -> String {
        guard needsQuotes(text, inFlow: false) else { return text }
        return quoted(text)
    }

    /// Lista en línea: `[a, "b, c"]`.
    static func flowList(_ items: [String]) -> String {
        "[" + items.map { needsQuotes($0, inFlow: true) ? quoted($0) : $0 }.joined(separator: ", ") + "]"
    }

    /// Escalar siempre entre comillas dobles (valores que ya las tenían).
    static func quotedScalar(_ text: String) -> String { quoted(text) }

    /// Lista en bloque: una línea `  - valor` por elemento. El texto empieza
    /// con un salto de línea: va después de `clave:`.
    static func blockList(_ items: [String]) -> String {
        items.map { "\n  - " + (needsQuotes($0, inFlow: false) ? quoted($0) : $0) }.joined()
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func needsQuotes(_ text: String, inFlow: Bool) -> Bool {
        guard let first = text.first, let last = text.last else { return true }
        if first.isWhitespace || last.isWhitespace { return true }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) { return true }
        if text.contains(": ") || text.contains(" #") || text.hasSuffix(":") || text.contains("\n") { return true }
        if inFlow, text.contains(where: { ",[]{}".contains($0) }) { return true }
        let reserved = ["true", "false", "yes", "no", "on", "off", "null", "~"]
        if reserved.contains(text.lowercased()) { return true }
        return Double(text) != nil
    }

    static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == trimmed.last else {
            return stripComment(trimmed)
        }
        let inner = String(trimmed.dropFirst().dropLast())
        if first == "\"" {
            var result = ""
            var escaping = false
            for character in inner {
                if escaping {
                    switch character {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default: result.append(character)
                    }
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
        if first == "'" { return inner.replacingOccurrences(of: "''", with: "'") }
        return stripComment(trimmed)
    }

    /// Quita un comentario ` # …` de un valor sin comillas.
    private static func stripComment(_ value: String) -> String {
        guard let range = value.range(of: " #") else { return value }
        return String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private static func list(value: String, block: [String]) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            return splitFlow(String(trimmed.dropFirst().dropLast()))
        }
        if trimmed.isEmpty {
            return block.compactMap { line in
                let item = line.trimmingCharacters(in: .whitespaces)
                guard item.hasPrefix("-") else { return nil }
                let text = unquote(String(item.dropFirst()))
                return text.isEmpty ? nil : text
            }
        }
        return splitFlow(trimmed)
    }

    /// Separa por comas fuera de comillas.
    private static func splitFlow(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items.map(unquote).filter { !$0.isEmpty }
    }

    // MARK: - Lectura y escritura de claves

    struct Entry: Equatable {
        let key: String
        let value: String
        /// Líneas siguientes que pertenecen a la clave (sangradas o `- `).
        let block: [String]
        /// Índices de línea [primera, última] dentro del YAML.
        let lines: ClosedRange<Int>
    }

    static func topLevelEntries(in yaml: String) -> [Entry] {
        let lines = yaml.components(separatedBy: "\n")
        var entries: [Entry] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let key = topLevelKey(line) else { index += 1; continue }
            let colon = line.firstIndex(of: ":")!
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            var end = index
            var block: [String] = []
            var next = index + 1
            while next < lines.count, isContinuation(lines[next]) {
                block.append(lines[next])
                if !lines[next].trimmingCharacters(in: .whitespaces).isEmpty { end = next }
                next += 1
            }
            // Las líneas vacías del final no son de la clave.
            block = Array(block.prefix(end - index))
            entries.append(Entry(key: key, value: value, block: block, lines: index...end))
            index = next
        }
        return entries
    }

    private static func topLevelKey(_ line: String) -> String? {
        guard let first = line.first, !first.isWhitespace, first != "#", first != "-",
              let colon = line.firstIndex(of: ":") else { return nil }
        let afterColon = line.index(after: colon)
        guard afterColon == line.endIndex || line[afterColon].isWhitespace else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    private static func isContinuation(_ line: String) -> Bool {
        guard let first = line.first else { return true }
        // Un comentario en la columna 0 no pertenece a la clave anterior.
        return first.isWhitespace || first == "-"
    }

    /// Quita de la sustitución las líneas iniciales y finales que no cambian.
    private static func minimalChange(in source: String, range: NSRange, replacement: String) -> (NSRange, String) {
        func lines(_ text: String) -> [String] {
            var result: [String] = []
            var current = ""
            for character in text {
                current.append(character)
                if character == "\n" { result.append(current); current = "" }
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
        let original = lines((source as NSString).substring(with: range))
        let updated = lines(replacement)
        var prefix = 0
        while prefix < original.count, prefix < updated.count, original[prefix] == updated[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < original.count - prefix, suffix < updated.count - prefix,
              original[original.count - 1 - suffix] == updated[updated.count - 1 - suffix] { suffix += 1 }
        let length: ([String]) -> Int = { $0.reduce(0) { $0 + ($1 as NSString).length } }
        let start = range.location + length(Array(original.prefix(prefix)))
        let removed = length(Array(original[prefix..<(original.count - suffix)]))
        return (
            NSRange(location: start, length: removed),
            updated[prefix..<(updated.count - suffix)].joined()
        )
    }

    /// `clave: valor`; un valor que empieza con salto de línea (lista en
    /// bloque, objeto) va en las líneas siguientes.
    static func line(key: String, value: String) -> String {
        if value.isEmpty { return "\(key):" }
        if value.hasPrefix("\n") { return "\(key):\(value)" }
        return "\(key): \(value)"
    }

    /// El YAML con `key` cambiado a `value` (texto YAML ya formateado) o
    /// eliminado si `value` es `nil`. El resto del texto no cambia; una clave
    /// nueva se añade al final.
    static func yaml(_ yaml: String, setting key: String, to value: String?) -> String {
        var lines = yaml.isEmpty ? [] : yaml.components(separatedBy: "\n")
        let newLine = value.map { line(key: key, value: $0) }
        if let entry = topLevelEntries(in: yaml).first(where: { $0.key == key }) {
            if let newLine {
                lines.replaceSubrange(entry.lines, with: [newLine])
            } else {
                lines.removeSubrange(entry.lines)
            }
        } else if let newLine {
            // Sin líneas vacías sobrantes al final antes de añadir.
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            lines.append(newLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Líneas de cada clave de primer nivel, con los comentarios pegados justo
    /// encima (viajan con ella al reordenar).
    private static func units(in lines: [String], entries: [Entry]) -> [(key: String, range: ClosedRange<Int>)] {
        var result: [(key: String, range: ClosedRange<Int>)] = []
        var previousEnd = -1
        for entry in entries {
            var start = entry.lines.lowerBound
            while start - 1 > previousEnd, lines[start - 1].hasPrefix("#"), !isSectionHeader(lines[start - 1]) { start -= 1 }
            result.append((entry.key, start...entry.lines.upperBound))
            previousEnd = entry.lines.upperBound
        }
        return result
    }

    /// Cambia `key` como `yaml(_:setting:to:)`, pero una propiedad gestionada
    /// nueva entra junto a las demás, en su sitio del orden del panel: tras la
    /// gestionada que la precede (`updated` tras `created`) o, si no hay
    /// ninguna, delante de la que la sigue. Sin gestionadas, al final.
    static func yaml(settingProperty key: String, to value: String?, in yaml: String) -> String {
        let entries = topLevelEntries(in: yaml)
        guard let value, let order = managedKeys.firstIndex(of: key),
              !entries.contains(where: { $0.key == key }) else {
            return Self.yaml(yaml, setting: key, to: value)
        }
        let rank: (String) -> Int? = { managedKeys.firstIndex(of: $0) }
        var lines = yaml.components(separatedBy: "\n")
        let newLine = line(key: key, value: value)
        let managed = units(in: lines, entries: entries).filter { rank($0.key) != nil }
        if let previous = managed.filter({ rank($0.key)! < order }).max(by: { rank($0.key)! < rank($1.key)! }) {
            lines.insert(newLine, at: previous.range.upperBound + 1)
        } else if let next = managed.filter({ rank($0.key)! > order }).min(by: { rank($0.key)! < rank($1.key)! }) {
            lines.insert(newLine, at: next.range.lowerBound)
        } else {
            return Self.yaml(yaml, setting: key, to: value)
        }
        return lines.joined(separator: "\n")
    }

    /// Las propiedades gestionadas en el orden del panel (`managedKeys`),
    /// ocupando los mismos huecos: las demás claves, los comentarios sueltos
    /// y las líneas vacías no se mueven. Un frontmatter con las secciones de la
    /// plantilla (`# AUTORÍA`…) conserva el orden de sus secciones.
    static func orderingManagedKeys(in yaml: String) -> String {
        let lines = yaml.components(separatedBy: "\n")
        guard !lines.contains(where: isSectionHeader) else { return yaml }
        let managed = units(in: lines, entries: topLevelEntries(in: yaml)).filter { managedKeys.contains($0.key) }
        let sorted = managed.sorted { managedKeys.firstIndex(of: $0.key)! < managedKeys.firstIndex(of: $1.key)! }
        guard managed.map(\.key) != sorted.map(\.key) else { return yaml }
        var output: [String] = []
        var index = 0
        var slot = 0
        while index < lines.count {
            if slot < managed.count, managed[slot].range.lowerBound == index {
                output += lines[sorted[slot].range]
                index = managed[slot].range.upperBound + 1
                slot += 1
            } else {
                output.append(lines[index])
                index += 1
            }
        }
        return output.joined(separator: "\n")
    }

    /// Edición del documento que cambia una clave del frontmatter (D53, D84):
    /// las líneas de esa clave y, si hace falta, el orden de las propiedades
    /// gestionadas (el del panel); el resto (comentarios, comillas, claves
    /// desconocidas y su posición) no cambia. Si no hay
    /// frontmatter, lo crea con esa única clave. `selection` se desplaza para
    /// que el cursor siga en el mismo sitio del texto. Devuelve `nil` si no hay
    /// cambio o si el frontmatter no se puede editar con seguridad
    /// (`editingLimitation`).
    static func edit(
        setting key: String,
        to value: String?,
        in source: String,
        selection: NSRange,
        language: String = "es"
    ) -> LitteraTextEdit? {
        guard editingLimitation(in: source) == nil else { return nil }
        var range: NSRange
        var replacement: String
        if let frontmatter = LitteraFrontmatter.detect(in: source) {
            let updated = orderingManagedKeys(in: yaml(settingProperty: key, to: value, in: frontmatter.yaml))
            guard updated != frontmatter.yaml else { return nil }
            if frontmatter.yaml.isEmpty {
                // Sin contenido: el cierre empieza justo después de la apertura.
                range = NSRange(location: frontmatter.yamlRange.location, length: 0)
                replacement = updated.isEmpty ? "" : updated + "\n"
            } else if updated.isEmpty {
                // Se queda vacío: se quita también el salto de línea.
                range = NSRange(location: frontmatter.yamlRange.location, length: frontmatter.yamlRange.length + 1)
                replacement = ""
            } else {
                range = frontmatter.yamlRange
                replacement = updated
            }
            guard range.length > 0 || !replacement.isEmpty else { return nil }
        } else {
            guard let value else { return nil }
            range = NSRange(location: 0, length: 0)
            replacement = "---\n" + line(key: key, value: value) + "\n---\n" + (source.isEmpty ? "" : "\n")
        }
        // Solo se sustituyen las líneas que cambian: deshacer marca lo justo.
        (range, replacement) = minimalChange(in: source, range: range, replacement: replacement)
        let delta = (replacement as NSString).length - range.length
        var newSelection = selection
        if selection.location >= NSMaxRange(range) {
            newSelection.location += delta
        } else if selection.location > range.location {
            newSelection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
        }
        return LitteraTextEdit(range: range, replacement: replacement, selection: newSelection)
    }
}
