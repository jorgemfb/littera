import AppKit
import SwiftUI

/// Resaltado del modo Fuente: el texto sigue en una sola fuente
/// monoespaciada (JetBrains Mono) y del mismo tamaño; solo cambian color y,
/// como mucho, el peso Medium de encabezados y negrita.
struct LitteraSourceHighlight {
    /// Versión analizada; se aplica cuando coincide con el texto del editor.
    let document: LitteraMarkdownDerivedDocument?
    let colorScheme: ColorScheme
    var style: LitteraSourceHighlightStyle = .soft
}

/// Aplica el resaltado Markdown del modo Fuente con los tramos del análisis.
/// Solo cambia atributos: nunca el texto, la selección ni Deshacer.
@MainActor
final class LitteraSourceStyler {
    private var appliedRuns: [LitteraVisualRun] = []
    private var appliedLength = 0
    private var appliedScheme: ColorScheme?
    private var appliedStyle: LitteraSourceHighlightStyle?
    private var appliedFontSize: CGFloat = 0
    private var appliedLineSpacing: CGFloat = -1

    func reset() {
        appliedLineSpacing = -1
        appliedRuns = []
        appliedLength = 0
        appliedScheme = nil
        appliedStyle = nil
        appliedFontSize = 0
    }

    func apply(
        runs: [LitteraVisualRun],
        to storage: NSTextStorage,
        scheme: ColorScheme,
        style: LitteraSourceHighlightStyle = .soft,
        fontSize: CGFloat,
        lineSpacing: CGFloat = 0
    ) {
        let length = storage.length
        let dirty: NSRange
        if appliedScheme != scheme || appliedStyle != style || appliedFontSize != fontSize
            || appliedLineSpacing != lineSpacing || appliedRuns.isEmpty {
            dirty = NSRange(location: 0, length: length)
        } else if let changed = LitteraVisualRun.changedRange(
            old: appliedRuns, oldLength: appliedLength, new: runs, newLength: length
        ) {
            var expanded = (storage.string as NSString).paragraphRange(for: changed)
            for run in runs where NSIntersectionRange(run.range, expanded).length > 0 || NSLocationInRange(expanded.location, run.range) {
                switch run.kind {
                case .codeBlock, .heading, .frontmatter:
                    expanded = NSUnionRange(expanded, run.range)
                default:
                    break
                }
            }
            dirty = (storage.string as NSString).paragraphRange(for: expanded)
        } else {
            return
        }

        storage.beginEditing()
        restyle(dirty, runs: runs, storage: storage, palette: LitteraSourcePalette(style: style, scheme: scheme), fontSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        storage.addAttribute(.paragraphStyle, value: paragraph, range: dirty)
        storage.endEditing()

        appliedRuns = runs
        appliedLength = length
        appliedScheme = scheme
        appliedStyle = style
        appliedFontSize = fontSize
        appliedLineSpacing = lineSpacing
    }

    private func restyle(
        _ range: NSRange,
        runs: [LitteraVisualRun],
        storage: NSTextStorage,
        palette: LitteraSourcePalette,
        fontSize: CGFloat
    ) {
        guard range.length > 0 else { return }
        let text = storage.string as NSString
        let regular = LitteraSourceFont.regular(fontSize)
        let medium = LitteraSourceFont.medium(fontSize)
        let italic = LitteraSourceFont.italic(fontSize)

        storage.addAttributes([.font: regular, .foregroundColor: palette.text], range: range)
        for key in [NSAttributedString.Key.strikethroughStyle, .underlineStyle, .backgroundColor] {
            storage.removeAttribute(key, range: range)
        }

        let relevant = runs.filter { NSIntersectionRange($0.range, range).length > 0 }
        func paint(_ color: NSColor, _ target: NSRange) {
            let clipped = NSIntersectionRange(target, range)
            if clipped.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: clipped) }
        }

        // 1. Bloques. Todos los encabezados tienen el tamaño del texto: la
        // jerarquía la dan el color y el peso Medium.
        var thematicBreaks = Set<Int>()
        var mermaidBlocks: [NSRange] = []
        for run in relevant {
            let target = NSIntersectionRange(run.range, range)
            switch run.kind {
            case let .heading(level):
                storage.addAttributes([.font: medium, .foregroundColor: palette.heading(level)], range: target)
            case .blockQuote:
                storage.addAttributes([.font: italic, .foregroundColor: palette.quote], range: target)
            case .codeBlock:
                let firstLine = text.lineRange(for: NSRange(location: run.range.location, length: 0))
                let isMermaid = text.substring(with: firstLine).lowercased().contains("mermaid")
                if isMermaid { mermaidBlocks.append(run.range) }
                paint(isMermaid ? palette.mermaid : palette.codeText, target)
            case .frontmatter:
                paint(palette.codeText, target)
                // Delimitadores `---`.
                paint(palette.marker, text.lineRange(for: NSRange(location: run.range.location, length: 0)))
                if run.range.length > 0 {
                    paint(palette.marker, text.lineRange(for: NSRange(location: NSMaxRange(run.range) - 1, length: 0)))
                }
            case .thematicBreak:
                thematicBreaks.insert(run.range.location)
            case .completedTask:
                paint(palette.completedTask, target)
            default:
                break
            }
        }

        // 2. En línea.
        for run in relevant {
            let target = NSIntersectionRange(run.range, range)
            switch run.kind {
            case .strong:
                storage.addAttributes([.font: medium, .foregroundColor: palette.strong], range: target)
            case .emphasis:
                storage.addAttributes([.font: italic, .foregroundColor: palette.emphasis], range: target)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: target)
            case .inlineCode:
                storage.addAttributes([
                    .foregroundColor: palette.inlineCode,
                    .backgroundColor: palette.inlineCodeBackground
                ], range: target)
            case .link:
                paint(palette.link, target)
            case let .codeToken(kind):
                // Mermaid se distingue como categoría propia: un solo color.
                guard !mermaidBlocks.contains(where: { NSLocationInRange(run.range.location, $0) }) else { break }
                paint(palette.codeToken(kind), target)
            default:
                break
            }
        }

        // 3. Marcadores: estructura (#, viñetas, números, >) en el color de
        // acento de la paleta; casillas, imágenes y separadores con el suyo; el
        // resto, atenuados.
        let listStarts = Set(relevant.compactMap { run -> Int? in
            if case .listItem = run.kind { return run.range.location }
            return nil
        })
        for run in relevant where run.kind == .marker {
            let target = NSIntersectionRange(run.range, range)
            let content = text.substring(with: run.range).trimmingCharacters(in: .whitespaces)
            storage.removeAttribute(.backgroundColor, range: target)
            if thematicBreaks.contains(run.range.location) {
                paint(palette.thematicBreak, target)
            } else if content.hasPrefix("![") {
                paint(palette.image, target)
            } else if listStarts.contains(run.range.location) {
                paint(palette.listMarker, target)
                let box = (text.substring(with: run.range) as NSString).range(of: "[")
                if box.location != NSNotFound {
                    paint(palette.task, NSRange(location: run.range.location + box.location, length: run.range.length - box.location))
                }
            } else if content.hasPrefix("#") {
                paint(palette.headingMarker, target)
            } else if content.hasPrefix(">") {
                paint(palette.listMarker, target)
            } else {
                paint(palette.marker, target)
            }
        }
    }
}
