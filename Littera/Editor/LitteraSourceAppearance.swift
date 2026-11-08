import AppKit
import CoreText
import SwiftUI

// Apariencia del modo Fuente (Fase 2): tipografía, anchura de la columna y
// paleta semántica del resaltado. El motor de resaltado es uno solo
// (`LitteraSourceStyler`); aquí solo se decide qué aspecto tiene cada categoría.

// MARK: - Tipografía

/// JetBrains Mono NL (variante oficial sin ligaduras: `->`, `--` o `!=` se ven
/// como los caracteres reales del Markdown). Licencia SIL OFL 1.1, incluida en
/// `Fonts/JetBrainsMono-OFL.txt`. Solo se incluyen Regular, Medium e Italic.
/// Si una fuente no se pudiera cargar, se usa la monoespaciada del sistema.
nonisolated enum LitteraSourceFont {
    static let regularName = "JetBrainsMonoNL-Regular"
    static let mediumName = "JetBrainsMonoNL-Medium"
    static let italicName = "JetBrainsMonoNL-Italic"

    /// Se registran una sola vez, solo para este proceso.
    private static let registered: Bool = {
        var ok = true
        for name in [regularName, mediumName, italicName] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                ok = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Ya registrada (por ejemplo, instalada por el usuario): sirve igual.
                ok = ok && NSFont(name: name, size: 12) != nil
            }
        }
        return ok
    }()

    /// `true` si las tres variantes están disponibles.
    static var isAvailable: Bool {
        _ = registered
        return [regularName, mediumName, italicName].allSatisfy { NSFont(name: $0, size: 12) != nil }
    }

    static func regular(_ size: CGFloat) -> NSFont {
        _ = registered
        return NSFont(name: regularName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Peso máximo del modo Fuente: encabezados y negrita.
    static func medium(_ size: CGFloat) -> NSFont {
        _ = registered
        return NSFont(name: mediumName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    }

    static func italic(_ size: CGFloat) -> NSFont {
        _ = registered
        if let font = NSFont(name: italicName, size: size) { return font }
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? base
    }
}

// MARK: - Anchura

/// Anchura de la columna de texto en Fuente. Independiente de la de Vista
/// previa, pero con sus mismos valores (`LitteraWritingWidth`).
enum LitteraSourceWidth: String, CaseIterable, Identifiable, Sendable {
    case narrow = "Estrecho"
    case medium = "Medio"
    case wide = "Ancho"
    case available = "Disponible"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .narrow: "ui.estrecho"
        case .medium: "ui.medio"
        case .wide: "ui.ancho"
        case .available: "ui.disponible"
        }
    }

    /// `nil`: todo el ancho del editor, con los márgenes mínimos.
    var columnWidth: CGFloat? {
        switch self {
        case .narrow: LitteraWritingWidth.narrow.points
        case .medium: LitteraWritingWidth.medium.points
        case .wide: LitteraWritingWidth.wide.points
        case .available: nil
        }
    }

    static func stored(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .medium }

    /// Margen horizontal que centra la columna. Solo cambia la presentación:
    /// el ajuste de línea es visual y el Markdown no se modifica.
    static func horizontalInset(viewWidth: CGFloat, column: CGFloat?) -> CGFloat {
        let minimum = LitteraDesign.Editor.sourceHorizontalPadding
        guard let column else { return minimum }
        return max(minimum, ((viewWidth - column) / 2).rounded(.down))
    }
}

// MARK: - Paletas

/// Estilo del resaltado de Fuente (Ajustes → Editor y menú «…»).
nonisolated enum LitteraSourceHighlightStyle: String, CaseIterable, Identifiable, Sendable {
    /// Discreto, para escribir durante mucho tiempo.
    case soft = "suave"
    /// Más expresivo: encabezados y marcadores muy visibles.
    case vivid = "viva"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .soft: "ui.resaltado.suave"
        case .vivid: "ui.resaltado.viva"
        }
    }

    static func stored(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .soft }
}

/// Colores del resaltado de Fuente por categoría semántica. Es la única tabla
/// de colores del modo: el motor pide aquí el color de cada tramo.
/// Contraste mínimo comprobado (WCAG) sobre el fondo de Fuente y sobre la
/// selección: 3:1 para los marcadores y 4,5:1 para el texto (ver pruebas).
struct LitteraSourcePalette {
    let background: NSColor
    let text: NSColor
    let headingMarker: NSColor
    let marker: NSColor
    let strong: NSColor
    let emphasis: NSColor
    let link: NSColor
    let image: NSColor
    let listMarker: NSColor
    let task: NSColor
    let completedTask: NSColor
    let quote: NSColor
    let inlineCode: NSColor
    let inlineCodeBackground: NSColor
    let codeText: NSColor
    let mermaid: NSColor
    let thematicBreak: NSColor
    let selection: NSColor
    let insertionPoint: NSColor
    private let headings: [NSColor]
    private let syntax: LitteraSyntaxPalette
    private let syntaxBlend: CGFloat

    init(style: LitteraSourceHighlightStyle, scheme: ColorScheme) {
        let dark = scheme == .dark
        let palette = LitteraPalette(scheme)
        func hex(_ value: Int) -> NSColor {
            NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
        background = NSColor(palette.secondary)
        text = NSColor(palette.primaryText)
        insertionPoint = NSColor(palette.primaryText)
        selection = hex(dark ? 0x314254 : 0xD3E2F0)
        syntax = LitteraSyntaxPalette(scheme)

        switch (style, dark) {
        case (.soft, false):
            headings = [0x0B0B0B, 0x0B0B0B, 0x0B0B0B, 0x33312D, 0x33312D, 0x33312D].map(hex)
            headingMarker = hex(0xA65D41)
            marker = hex(0x7A776F)
            strong = text
            emphasis = text
            link = hex(0x2F6283)
            image = hex(0x6E4F86)
            listMarker = hex(0xA65D41)
            task = hex(0x4F7449)
            quote = hex(0x55534E)
            inlineCode = hex(0x6A4A33)
            inlineCodeBackground = hex(0xE6E4E0)
            codeText = hex(0x33312D)
            mermaid = hex(0x2F6E69)
            thematicBreak = hex(0x7A776F)
            syntaxBlend = 0.5
        case (.soft, true):
            headings = [0xF0EFEC, 0xF0EFEC, 0xF0EFEC, 0xD6D4CF, 0xD6D4CF, 0xD6D4CF].map(hex)
            headingMarker = hex(0xC08A73)
            marker = hex(0x96938D)
            strong = text
            emphasis = text
            link = hex(0x97B6CC)
            image = hex(0xBDA6CC)
            listMarker = hex(0xC08A73)
            task = hex(0x9BB896)
            quote = hex(0xB0ADA7)
            inlineCode = hex(0xDDBF9F)
            inlineCodeBackground = hex(0x2B2A29)
            codeText = hex(0xD6D4CF)
            mermaid = hex(0x8FC0BB)
            thematicBreak = hex(0x96938D)
            syntaxBlend = 0.45
        case (.vivid, false):
            headings = [0x9A4422, 0x7E4E0E, 0x1F5F86, 0x3D4A57, 0x3D4A57, 0x3D4A57].map(hex)
            headingMarker = hex(0x9A4422)
            marker = hex(0x5C5850)
            strong = hex(0x7A2E12)
            emphasis = hex(0x4B3F8F)
            link = hex(0x1659A8)
            image = hex(0x7E2FA8)
            listMarker = hex(0x9A4422)
            task = hex(0x21702A)
            quote = hex(0x3E6B4C)
            inlineCode = hex(0x8A420A)
            inlineCodeBackground = hex(0xE8E1D8)
            codeText = hex(0x2A2824)
            mermaid = hex(0x00796B)
            thematicBreak = hex(0x9A4422)
            syntaxBlend = 0.25
        case (.vivid, true):
            headings = [0xEE9673, 0xE9BC6C, 0x86BAEC, 0xC2CCD6, 0xC2CCD6, 0xC2CCD6].map(hex)
            headingMarker = hex(0xEE9673)
            marker = hex(0xABA8A2)
            strong = hex(0xF4A983)
            emphasis = hex(0xC0AEF3)
            link = hex(0x72B7F7)
            image = hex(0xD093EE)
            listMarker = hex(0xEE9673)
            task = hex(0x82D086)
            quote = hex(0xA3C9AC)
            inlineCode = hex(0xE8C47F)
            inlineCodeBackground = hex(0x2E2A25)
            codeText = hex(0xDAD8D3)
            mermaid = hex(0x5CCABE)
            thematicBreak = hex(0xEE9673)
            syntaxBlend = 0
        }
        completedTask = marker
    }

    /// Texto del encabezado según su nivel (1–6).
    func heading(_ level: Int) -> NSColor { headings[min(max(level, 1), 6) - 1] }

    /// Tokens de código y del YAML del frontmatter: la paleta de los bloques de
    /// código, atenuada hacia el texto de código en Suave.
    func codeToken(_ kind: LitteraSyntaxTokenKind) -> NSColor {
        let base = NSColor(syntax.color(for: kind))
        guard syntaxBlend > 0 else { return base }
        return base.blended(withFraction: syntaxBlend, of: codeText) ?? base
    }

    /// Todos los colores de primer plano, con su nombre (pruebas de contraste).
    var foregroundColors: [(name: String, color: NSColor, minimumContrast: Double)] {
        var colors: [(String, NSColor, Double)] = [
            ("texto", text, 4.5), ("marcador", marker, 3), ("marca.encabezado", headingMarker, 3),
            ("negrita", strong, 4.5), ("cursiva", emphasis, 4.5), ("enlace", link, 4.5),
            ("imagen", image, 4.5), ("lista", listMarker, 3), ("tarea", task, 3),
            ("tarea.hecha", completedTask, 3), ("cita", quote, 4.5), ("codigo.linea", inlineCode, 4.5),
            ("codigo", codeText, 4.5), ("mermaid", mermaid, 4.5), ("separador", thematicBreak, 3),
        ]
        for level in 1...6 { colors.append(("h\(level)", heading(level), 4.5)) }
        return colors
    }
}

// MARK: - Editor

/// `NSTextView` del modo Fuente: centra la columna con la anchura elegida y
/// se adapta al redimensionar. Solo cambia los márgenes del contenedor; el
/// texto, la selección y Deshacer no se tocan.
final class LitteraSourceColumnTextView: LitteraEditorTextView {
    var columnWidth: CGFloat? {
        didSet {
            guard oldValue != columnWidth else { return }
            updateInsets()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let inset = NSSize(
            width: LitteraSourceWidth.horizontalInset(viewWidth: bounds.width, column: columnWidth),
            height: 0
        )
        guard textContainerInset != inset else { return }
        textContainerInset = inset
    }
}
