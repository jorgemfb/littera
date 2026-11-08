import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Modo Fuente (Fase 2): tipografía, paletas Suave y Viva, y anchura.
@MainActor
final class LitteraSourceAppearanceTests: XCTestCase {
    // MARK: Tipografía

    func testBundledFontsAreRegisteredAndOnlyTheNeededOnesAreIncluded() throws {
        XCTAssertTrue(LitteraSourceFont.isAvailable)
        for name in [LitteraSourceFont.regularName, LitteraSourceFont.mediumName, LitteraSourceFont.italicName] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf"), name)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "JetBrainsMono-OFL", withExtension: "txt"), "Aviso de licencia OFL")
        let resources = try FileManager.default.contentsOfDirectory(atPath: try XCTUnwrap(Bundle.main.resourcePath))
        XCTAssertEqual(resources.filter { $0.hasPrefix("JetBrainsMono") }.sorted(), [
            "JetBrainsMono-OFL.txt", "JetBrainsMonoNL-Italic.ttf", "JetBrainsMonoNL-Medium.ttf", "JetBrainsMonoNL-Regular.ttf",
        ])
        XCTAssertEqual(LitteraSourceFont.regular(14).familyName, "JetBrains Mono NL")
        XCTAssertEqual(LitteraSourceFont.regular(14).pointSize, 14)
        XCTAssertTrue(LitteraSourceFont.italic(14).fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(LitteraSourceFont.regular(14).isFixedPitch)
    }

    private let sample = """
    ---
    title: "Prueba"
    tags: [a, b]
    ---

    # Uno
    ## Dos
    ### Tres
    #### Cuatro
    ##### Cinco
    ###### Seis

    Texto con **negrita**, *cursiva*, `código`, [enlace](https://example.com) e ![imagen](foto.png).

    - Elemento
    - [ ] Tarea
    - [x] Hecha

    > Cita

    ```swift
    let a = 1
    ```

    ```mermaid
    graph TD
      A --> B
    ```

    ---
    """

    private func styled(_ text: String, style: LitteraSourceHighlightStyle, scheme: ColorScheme = .light, size: CGFloat = 14) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let document = LitteraMarkdownDerivedDocument(source: text, revision: 1)
        LitteraSourceStyler().apply(runs: document.visualRuns, to: storage, scheme: scheme, style: style, fontSize: size)
        return storage
    }

    private func location(of needle: String, in text: String, offset: Int = 0) -> Int {
        let range = (text as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, needle)
        return range.location + offset
    }

    func testHeadingsKeepBodySizeAndAtMostMediumWeight() {
        for style in LitteraSourceHighlightStyle.allCases {
            let storage = styled(sample, style: style)
            var names = Set<String>()
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                guard let font = value as? NSFont else { return XCTFail("Sin fuente") }
                XCTAssertEqual(font.pointSize, 14, "Todo el texto tiene el mismo tamaño")
                names.insert(font.fontName)
            }
            XCTAssertTrue(names.isSubset(of: [
                LitteraSourceFont.regularName, LitteraSourceFont.mediumName, LitteraSourceFont.italicName,
            ]), "Sin Bold ni Heavy: \(names)")
            let heading = storage.attribute(.font, at: location(of: "Tres", in: sample), effectiveRange: nil) as? NSFont
            XCTAssertEqual(heading?.fontName, LitteraSourceFont.mediumName)
            let body = storage.attribute(.font, at: location(of: "Texto con", in: sample), effectiveRange: nil) as? NSFont
            XCTAssertEqual(body?.fontName, LitteraSourceFont.regularName)
        }
    }

    func testEachCategoryUsesItsPaletteColor() {
        for style in LitteraSourceHighlightStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = LitteraSourcePalette(style: style, scheme: scheme)
                let storage = styled(sample, style: style, scheme: scheme)
                func color(_ needle: String, _ offset: Int = 0) -> NSColor? {
                    storage.attribute(.foregroundColor, at: location(of: needle, in: sample, offset: offset), effectiveRange: nil) as? NSColor
                }
                XCTAssertEqual(color("# Uno"), palette.headingMarker)
                XCTAssertEqual(color("## Dos"), palette.headingMarker)
                XCTAssertEqual(color("#### Cuatro"), palette.headingMarker, "\(style) \(scheme) H4")
                XCTAssertEqual(color("###### Seis"), palette.headingMarker, "\(style) \(scheme) H6")
                XCTAssertEqual(color("Uno"), palette.heading(1))
                XCTAssertEqual(color("Dos"), palette.heading(2))
                XCTAssertEqual(color("Seis"), palette.heading(6))
                XCTAssertEqual(color("Texto con"), palette.text)
                XCTAssertEqual(color("**negrita"), palette.marker)
                XCTAssertEqual(color("negrita"), palette.strong)
                XCTAssertEqual(color("cursiva"), palette.emphasis)
                XCTAssertEqual(color("código"), palette.inlineCode)
                XCTAssertEqual(color("enlace"), palette.link)
                XCTAssertEqual(color("![imagen"), palette.image)
                XCTAssertEqual(color("- Elemento"), palette.listMarker)
                XCTAssertEqual(color("[ ] Tarea"), palette.task)
                XCTAssertEqual(color("Hecha"), palette.completedTask)
                XCTAssertEqual(color("> Cita"), palette.listMarker)
                XCTAssertEqual(color("Cita"), palette.quote)
                XCTAssertEqual(color("```swift"), palette.marker)
                XCTAssertEqual(color("graph TD"), palette.mermaid)
                XCTAssertEqual(color("---\ntitle"), palette.marker)
                XCTAssertEqual(color("---", (sample as NSString).range(of: "---", options: .backwards).location - location(of: "---", in: sample)), palette.thematicBreak)
                XCTAssertEqual(
                    storage.attribute(.backgroundColor, at: location(of: "código", in: sample), effectiveRange: nil) as? NSColor,
                    palette.inlineCodeBackground
                )
            }
        }
    }

    func testSwitchingPaletteOnlyChangesAttributes() {
        let storage = NSTextStorage(string: sample)
        let document = LitteraMarkdownDerivedDocument(source: sample, revision: 1)
        let styler = LitteraSourceStyler()
        styler.apply(runs: document.visualRuns, to: storage, scheme: .light, style: .soft, fontSize: 14)
        let soft = storage.attribute(.foregroundColor, at: location(of: "Dos", in: sample), effectiveRange: nil) as? NSColor
        styler.apply(runs: document.visualRuns, to: storage, scheme: .light, style: .vivid, fontSize: 14)
        let vivid = storage.attribute(.foregroundColor, at: location(of: "Dos", in: sample), effectiveRange: nil) as? NSColor
        XCTAssertEqual(storage.string, sample, "El documento no cambia")
        XCTAssertEqual(soft, LitteraSourcePalette(style: .soft, scheme: .light).heading(2))
        XCTAssertEqual(vivid, LitteraSourcePalette(style: .vivid, scheme: .light).heading(2))
        XCTAssertNotEqual(soft, vivid)
    }

    // MARK: Contraste

    private func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
    }

    private func contrast(_ lhs: NSColor, _ rhs: NSColor) -> Double {
        let (a, b) = (luminance(lhs), luminance(rhs))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func testPalettesRespectContrastOnBackgroundAndSelection() {
        for style in LitteraSourceHighlightStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = LitteraSourcePalette(style: style, scheme: scheme)
                let label = "\(style.rawValue)/\(scheme == .dark ? "oscuro" : "claro")"
                for (name, color, minimum) in palette.foregroundColors {
                    XCTAssertGreaterThanOrEqual(contrast(color, palette.background), minimum, "\(label) \(name) sobre el fondo")
                    XCTAssertGreaterThanOrEqual(contrast(color, palette.selection), 3, "\(label) \(name) seleccionado")
                }
                XCTAssertGreaterThanOrEqual(contrast(palette.inlineCode, palette.inlineCodeBackground), 4.5, "\(label) código en línea")
                for kind in LitteraSyntaxTokenKind.allCases where kind != .comment {
                    XCTAssertGreaterThanOrEqual(contrast(palette.codeToken(kind), palette.background), 3, "\(label) token \(kind)")
                }
                XCTAssertGreaterThanOrEqual(contrast(palette.insertionPoint, palette.background), 4.5, "\(label) cursor")
            }
        }
    }

    func testPaletteCategoriesAreDistinguishable() {
        for style in LitteraSourceHighlightStyle.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let palette = LitteraSourcePalette(style: style, scheme: scheme)
                let accents = [palette.link, palette.image, palette.task, palette.mermaid, palette.headingMarker, palette.marker, palette.text]
                for (i, a) in accents.enumerated() {
                    for b in accents[(i + 1)...] { XCTAssertNotEqual(a, b, "\(style) \(scheme)") }
                }
            }
        }
        // Viva diferencia los niveles de encabezado; Suave los mantiene sobrios.
        let vivid = LitteraSourcePalette(style: .vivid, scheme: .light)
        XCTAssertEqual(Set([1, 2, 3, 4].map { vivid.heading($0) }).count, 4)
    }

    // MARK: Anchura

    func testSourceWidthsReusePreviewValues() {
        XCTAssertEqual(LitteraSourceWidth.narrow.columnWidth, LitteraWritingWidth.narrow.points)
        XCTAssertEqual(LitteraSourceWidth.medium.columnWidth, LitteraWritingWidth.medium.points)
        XCTAssertEqual(LitteraSourceWidth.wide.columnWidth, LitteraWritingWidth.wide.points)
        XCTAssertNil(LitteraSourceWidth.available.columnWidth)
        XCTAssertEqual(LitteraSourceWidth.horizontalInset(viewWidth: 1200, column: 760), 220)
        XCTAssertEqual(LitteraSourceWidth.horizontalInset(viewWidth: 500, column: 760), LitteraDesign.Editor.sourceHorizontalPadding)
        XCTAssertEqual(LitteraSourceWidth.horizontalInset(viewWidth: 1200, column: nil), LitteraDesign.Editor.sourceHorizontalPadding)
        XCTAssertEqual(LitteraSourceWidth.stored("desconocido"), .medium)
        XCTAssertEqual(LitteraSourceHighlightStyle.stored("desconocido"), .soft)
        XCTAssertNotEqual(LitteraPreferenceKeys.sourceWidth, LitteraPreferenceKeys.writingWidth, "La clave antigua se conserva aparte")
        XCTAssertEqual(LitteraPreferenceDefaults.sourceHighlightStyle, LitteraSourceHighlightStyle.soft.rawValue)
    }

    /// Una sola «Anchura del texto» para los tres modos (2026-11-07): Fuente
    /// usa la misma, también «Disponible».
    func testOneTextWidthDrivesSourceAndPreview() {
        for width in LitteraWritingWidth.allCases {
            XCTAssertEqual(width.sourceColumnWidth, LitteraSourceWidth(rawValue: width.rawValue)?.columnWidth, width.rawValue)
        }
        XCTAssertEqual(LitteraWritingWidth.allCases.map(\.rawValue), LitteraSourceWidth.allCases.map(\.rawValue))
        XCTAssertNil(LitteraWritingWidth.available.sourceColumnWidth)
        XCTAssertGreaterThan(LitteraWritingWidth.available.points, 100_000, "Vista previa: solo los márgenes mínimos")
        XCTAssertNotNil(LitteraCommandRegistry.command("available"), "La paleta ofrece las cuatro anchuras")
        for key in ["ui.anchura.de.fuente", "ui.anchura.de.lectura"] {
            XCTAssertEqual(L10n.tr(key, locale: Locale(identifier: "es")), key, "\(key) ya no se usa")
        }
    }

    func testOnlyASourceWidthChoiceIsMigrated() {
        let defaults = LitteraTestDefaults.make()
        defaults.set(LitteraWritingWidth.available.rawValue, forKey: LitteraPreferenceKeys.sourceWidth)
        LitteraPreferenceMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: LitteraPreferenceKeys.writingWidth), "Disponible")

        let both = LitteraTestDefaults.make()
        both.set("Estrecho", forKey: LitteraPreferenceKeys.writingWidth)
        both.set("Ancho", forKey: LitteraPreferenceKeys.sourceWidth)
        LitteraPreferenceMigration.migrate(both)
        XCTAssertEqual(both.string(forKey: LitteraPreferenceKeys.writingWidth), "Estrecho", "La anchura del texto elegida manda")
    }

    func testColumnCentersWithoutTouchingTextSelectionOrUndo() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1000, height: 400))
        let textView = LitteraSourceColumnTextView(frame: scroll.bounds)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scroll.documentView = textView
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        let text = String(repeating: "palabra ", count: 200)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 37, length: 5))

        textView.columnWidth = 570
        let width = textView.bounds.width
        XCTAssertEqual(textView.textContainerInset.width, ((width - 570) / 2).rounded(.down))
        XCTAssertEqual(try XCTUnwrap(textView.textContainer).size.width, width - 2 * textView.textContainerInset.width, accuracy: 1)

        textView.columnWidth = nil
        XCTAssertEqual(textView.textContainerInset.width, LitteraDesign.Editor.sourceHorizontalPadding)
        scroll.setFrameSize(NSSize(width: 700, height: 400))
        textView.columnWidth = 950
        XCTAssertEqual(textView.textContainerInset.width, LitteraDesign.Editor.sourceHorizontalPadding, "Ventana estrecha: margen mínimo")

        XCTAssertEqual(textView.string, text, "Sin saltos de línea reales")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 37, length: 5))
    }
}
