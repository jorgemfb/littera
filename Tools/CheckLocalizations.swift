import Foundation

// Comprobador de recursos localizados, sin Python ni dependencias externas.
// Ejecutar desde la raíz del repositorio: swift Tools/CheckLocalizations.swift
// O pasar la raíz como primer argumento.

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Littera", isDirectory: true)
let localization = source.appendingPathComponent("Localization", isDirectory: true)
let fm = FileManager.default

func fail(_ message: String) -> Never {
    fputs("ERROR: \(message)\n", stderr)
    exit(1)
}

func matches(_ pattern: String, in value: String, options: NSRegularExpression.Options = []) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        fail("Expresión regular incorrecta")
    }
    let ns = value as NSString
    return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).map { result in
        (0..<result.numberOfRanges).map { idx in
            let range = result.range(at: idx)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
}

let stringsPattern = #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$"#
let placeholderPattern = #"%(?:\d+\$)?(?:@|d|ld|f|s)"#
let keyReferencePattern = #""((?:ui|menu)\.[A-Za-z0-9_.]+)""#

let paths: [URL]
do {
    paths = try fm.contentsOfDirectory(at: localization, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "lproj" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
} catch {
    fail("No se encuentran recursos localizados en \(localization.path): \(error)")
}

var catalogs: [String: [String: String]] = [:]
var errors: [String] = []

for folder in paths {
    let language = folder.deletingPathExtension().lastPathComponent
    let file = folder.appendingPathComponent("Localizable.strings")
    guard let content = try? String(contentsOf: file, encoding: .utf8) else {
        errors.append("\(language): falta Localizable.strings o no se puede leer")
        continue
    }
    var catalog: [String: String] = [:]
    for match in matches(stringsPattern, in: content, options: [.anchorsMatchLines]) {
        let key = match[1]
        if catalog[key] != nil { errors.append("\(language): clave duplicada \(key)") }
        catalog[key] = match[2]
    }
    if catalog.isEmpty { errors.append("\(language): catálogo vacío/no interpretable") }
    catalogs[language] = catalog
}

if catalogs["es"] == nil { errors.append("Falta el catálogo español es.lproj") }
if catalogs["en"] == nil { errors.append("Falta el catálogo inglés en.lproj") }
let base = catalogs["es"] ?? [:]
for (language, catalog) in catalogs {
    for key in Set(base.keys).subtracting(catalog.keys).sorted() {
        errors.append("\(language): falta \(key)")
    }
    for key in Set(catalog.keys).subtracting(base.keys).sorted() {
        errors.append("\(language): clave adicional \(key)")
    }
    for key in Set(base.keys).intersection(catalog.keys) {
        let a = matches(placeholderPattern, in: base[key] ?? "").map { $0[0] }.sorted()
        let b = matches(placeholderPattern, in: catalog[key] ?? "").map { $0[0] }.sorted()
        if a != b { errors.append("\(language): marcadores incompatibles en \(key)") }
    }
}

guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: nil) else {
    fail("No se pueden enumerar archivos Swift")
}
let allSwift: [URL] = enumerator.compactMap { $0 as? URL }
    .filter { $0.pathExtension == "swift" }

let combinedSwift = allSwift.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
let referenced = Set(matches(keyReferencePattern, in: combinedSwift).map { $0[1] })
for key in referenced.subtracting(base.keys).sorted() {
    errors.append("Swift: falta la traducción española \(key)")
}

if !errors.isEmpty {
    for error in errors.sorted() { fputs("ERROR: \(error)\n", stderr) }
    exit(1)
}
print("OK · \(base.count) claves · idiomas: \(catalogs.keys.sorted().joined(separator: ", ")) · referencias Swift: \(referenced.count)")
