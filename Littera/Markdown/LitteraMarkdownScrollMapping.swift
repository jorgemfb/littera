import Foundation
import Markdown

/// Rango de origen normalizado a offsets UTF-8 y UTF-16 del mismo Markdown.
/// `swift-markdown` expresa las columnas como bytes UTF-8; AppKit usa índices
/// UTF-16. Mantener ambas representaciones evita convertir por porcentajes.
nonisolated struct LitteraMarkdownSourceRange: Equatable, Sendable {
    let utf8Range: Range<Int>
    let utf16Range: NSRange

    init?(sourceRange: Markdown.SourceRange?, source: String) {
        self.init(sourceRange: sourceRange, source: LitteraMarkdownSourceIndex(source))
    }

    init?(utf8Range: Range<Int>, source: String) {
        self.init(utf8Range: utf8Range, source: LitteraMarkdownSourceIndex(source))
    }

    init?(sourceRange: Markdown.SourceRange?, source: LitteraMarkdownSourceIndex) {
        guard let sourceRange,
              let startUTF8 = source.utf8Offset(for: sourceRange.lowerBound),
              let endUTF8 = source.utf8Offset(for: sourceRange.upperBound),
              endUTF8 >= startUTF8 else {
            return nil
        }

        self.init(utf8Range: startUTF8..<endUTF8, source: source)
    }

    init?(utf8Range: Range<Int>, source: LitteraMarkdownSourceIndex) {
        guard utf8Range.lowerBound >= 0,
              utf8Range.upperBound >= utf8Range.lowerBound,
              utf8Range.lowerBound <= source.utf8Count else {
            return nil
        }

        let startUTF16 = source.utf16Offset(forUTF8Offset: utf8Range.lowerBound, rounding: .down)
        let endUTF16 = source.utf16Offset(
            forUTF8Offset: min(utf8Range.upperBound, source.utf8Count),
            rounding: .up
        )

        self.utf8Range = utf8Range
        utf16Range = NSRange(location: startUTF16, length: max(0, endUTF16 - startUTF16))
    }

    func containsUTF16Character(_ characterIndex: Int) -> Bool {
        let start = utf16Range.location
        let end = NSMaxRange(utf16Range)
        return characterIndex >= start && characterIndex < max(end, start + 1)
    }
}

nonisolated extension LitteraMarkdownRenderDocument {
    func block(containingOrFollowingUTF16Character characterIndex: Int) -> LitteraMarkdownRenderBlock? {
        let rangedBlocks = blocks.compactMap { block -> (LitteraMarkdownRenderBlock, LitteraMarkdownSourceRange)? in
            guard let sourceRange = block.sourceRange else { return nil }
            return (block, sourceRange)
        }
        guard !rangedBlocks.isEmpty else { return nil }

        if let matchingBlock = rangedBlocks.first(where: { _, sourceRange in
            sourceRange.containsUTF16Character(characterIndex)
        }) {
            return matchingBlock.0
        }

        if let followingBlock = rangedBlocks.first(where: { _, sourceRange in
            sourceRange.utf16Range.location > characterIndex
        }) { return followingBlock.0 }

        return rangedBlocks.last?.0
    }

    func block(withID id: String) -> LitteraMarkdownRenderBlock? {
        blocks.first(where: { $0.id == id })
    }
}
