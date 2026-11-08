import Foundation

/// Sentido de una búsqueda en el documento.
nonisolated enum LitteraSearchDirection: Sendable {
    /// Mientras se escribe: la coincidencia que empieza en la selección o la siguiente.
    case incremental
    case next
    case previous
}

/// Resultado visible de la búsqueda: posición (desde 1) y total.
nonisolated struct LitteraSearchResult: Equatable, Sendable {
    let current: Int
    let total: Int

    static let none = LitteraSearchResult(current: 0, total: 0)
}

/// Búsqueda literal sobre el Markdown, sin distinguir mayúsculas ni acentos.
nonisolated enum LitteraTextSearch {
    static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func matches(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let string = text as NSString
        var result: [NSRange] = []
        var searchRange = NSRange(location: 0, length: string.length)
        while searchRange.length > 0 {
            let found = string.range(of: query, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            result.append(found)
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: string.length - next)
        }
        return result
    }

    /// Índice de la coincidencia que corresponde a la selección actual; da la
    /// vuelta al llegar al final o al principio del documento.
    static func index(
        in matches: [NSRange],
        selection: NSRange,
        direction: LitteraSearchDirection
    ) -> Int? {
        guard !matches.isEmpty else { return nil }
        switch direction {
        case .incremental:
            return matches.firstIndex { $0.location >= selection.location } ?? 0
        case .next:
            let end = NSMaxRange(selection)
            return matches.firstIndex { $0.location >= end && $0 != selection } ?? 0
        case .previous:
            return matches.lastIndex { $0.location < selection.location } ?? matches.count - 1
        }
    }
}
