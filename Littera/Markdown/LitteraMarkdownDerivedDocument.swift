import Foundation

/// Instantánea inmutable de un documento analizado, propiedad del Store.
/// Se construye fuera del hilo principal y nunca la crean las vistas.
nonisolated final class LitteraMarkdownDerivedDocument: Sendable {
    let source: String
    let revision: UInt64
    let rendered: LitteraMarkdownRenderDocument
    /// Tramos de estilo del resaltado de Fuente, calculados con el mismo AST.
    let visualRuns: [LitteraVisualRun]
    /// Calculado una vez por versión; la barra de estado no recorre el texto.
    let wordCount: Int
    let statistics: LitteraDocumentStatistics
    let frontmatter: LitteraFrontmatter?
    private let byID: [String: LitteraMarkdownRenderBlock]
    private let rangedBlocks: [LitteraMarkdownRenderBlock]
    private let topLevelIndexByID: [String: Int]

    init(source: String, revision: UInt64) {
        self.source = source
        self.revision = revision
        let parsed = LitteraMarkdownParser().parse(source)
        rendered = LitteraMarkdownRenderer().render(parsed)
        visualRuns = LitteraVisualRunBuilder.runs(for: parsed)
        // Contar palabras sin crear substrings (reduce presión de memoria).
        let prose = parsed.frontmatter.map { (source as NSString).substring(from: NSMaxRange($0.range)) } ?? source
        var words = 0
        var inWord = false
        for c in prose.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(c) {
                inWord = false
            } else if !inWord {
                inWord = true
                words += 1
            }
        }
        wordCount = words
        statistics = LitteraDocumentStatistics(source: source, frontmatter: parsed.frontmatter)
        frontmatter = parsed.frontmatter
        byID = Dictionary(uniqueKeysWithValues: rendered.blocks.map { ($0.id, $0) })
        rangedBlocks = rendered.blocks.filter { $0.sourceRange != nil }
        topLevelIndexByID = Dictionary(
            uniqueKeysWithValues: rendered.blocks.enumerated().map { ($1.id, $0) }
        )
    }

    func block(withID id: String) -> LitteraMarkdownRenderBlock? { byID[id] }

    /// Orden del bloque entre los bloques superiores del documento.
    func topLevelIndex(ofBlockID id: String) -> Int? { topLevelIndexByID[id] }

    func block(containingOrFollowingUTF16Character index: Int) -> LitteraMarkdownRenderBlock? {
        var low = 0
        var high = rangedBlocks.count
        while low < high {
            let mid = (low + high) / 2
            let range = rangedBlocks[mid].sourceRange!.utf16Range
            if max(NSMaxRange(range), range.location + 1) <= index {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low < rangedBlocks.count ? rangedBlocks[low] : rangedBlocks.last
    }
}
