import Foundation

/// Estadísticas del texto del documento (sin el frontmatter YAML).
nonisolated struct LitteraDocumentStatistics: Equatable, Sendable {
    let words: Int
    let characters: Int
    let charactersWithoutSpaces: Int
    let paragraphs: Int
    let lines: Int

    /// Minutos de lectura a 200 palabras por minuto (mínimo 1).
    var readingMinutes: Int { max(1, (words + 199) / 200) }

    init(source: String, frontmatter: LitteraFrontmatter?) {
        let prose = frontmatter.map { (source as NSString).substring(from: NSMaxRange($0.range)) } ?? source
        // Recorrido único sin crear substrings (reduce presión de memoria).
        var wordCount = 0
        var noSpaceCount = 0
        var lineCount = 0
        var paragraphCount = 0
        var inWord = false
        var inParagraph = false
        var lineHasContent = false
        for c in prose.unicodeScalars {
            let isNL = c == "\n" || c == "\r"
            if isNL {
                inWord = false
                if lineHasContent {
                    lineCount += 1
                } else {
                    inParagraph = false
                }
                lineHasContent = false
            } else if c == " " || c == "\t" {
                inWord = false
            } else {
                noSpaceCount += 1
                if !lineHasContent {
                    lineHasContent = true
                    if !inParagraph {
                        paragraphCount += 1
                        inParagraph = true
                    }
                }
                if !inWord {
                    inWord = true
                    wordCount += 1
                }
            }
        }
        if lineHasContent { lineCount += 1 }
        words = wordCount
        characters = prose.count
        charactersWithoutSpaces = noSpaceCount
        lines = lineCount
        paragraphs = paragraphCount
    }

    init(_ document: LitteraMarkdownDerivedDocument) {
        self.init(source: document.source, frontmatter: document.frontmatter)
    }
}
