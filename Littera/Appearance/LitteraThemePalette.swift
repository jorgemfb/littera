import AppKit
import SwiftUI

// Colores suaves aprobados de Littera.
// Este archivo no guarda preferencias ni cambia la apariencia de ventanas.

struct LitteraPalette {
    let canvas: Color
    let chrome: Color
    let secondary: Color
    let control: Color
    let selected: Color
    let line: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let overlay: Color

    /// Colores tomados de las referencias aprobadas (capturas de 2026-10-22).
    /// Oscuro: grises neutros de base #151515. Claro: blancos cálidos de base
    /// #FCFCFB. Acento terracota; los controles nativos conservan el del sistema.
    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        canvas = Color(hex: dark ? 0x151515 : 0xFCFCFB)
        chrome = Color(hex: dark ? 0x111111 : 0xFBFBF9)
        secondary = Color(hex: dark ? 0x212121 : 0xF0F0EF)
        control = Color(hex: dark ? 0x262626 : 0xF0F0EF)
        selected = Color(hex: dark ? 0x353535 : 0xEDECE9)
        line = Color(hex: dark ? 0x313130 : 0xE7E7E7)
        primaryText = Color(hex: dark ? 0xF0EFEC : 0x0B0B0B)
        // «Aumentar contraste» de macOS: texto secundario más legible
        // (#898782 sobre el fondo claro no llega a 4,5:1).
        secondaryText = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? Color(hex: dark ? 0xB3B1AC : 0x5E5C58)
            : Color(hex: 0x898782)
        accent = Color(hex: dark ? 0xC5785B : 0xD78363)
        overlay = Color.black.opacity(dark ? 0.45 : 0.24)
    }
}

/// Colores de resaltado de sintaxis de los bloques de código. Tomados de las
/// referencias aprobadas (estilo One Dark en oscuro; su variante One Light en
/// claro). El texto sin categoría usa el color principal del tema.
struct LitteraSyntaxPalette {
    let key: Color
    let string: Color
    let number: Color
    let punctuation: Color
    let keyword: Color
    let comment: Color
    let type: Color
    let function: Color
    let variable: Color
    let tag: Color
    let attribute: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        key = Color(hex: dark ? 0xE06C75 : 0xE45649)
        string = Color(hex: dark ? 0x98C379 : 0x50A14F)
        number = Color(hex: dark ? 0xD19A66 : 0x986801)
        punctuation = Color(hex: dark ? 0x56B6C2 : 0x0184BC)
        keyword = Color(hex: dark ? 0xC678DD : 0xA626A4)
        comment = Color(hex: dark ? 0x7F848E : 0xA0A1A7)
        type = Color(hex: dark ? 0xE5C07B : 0xC18401)
        function = Color(hex: dark ? 0x61AFEF : 0x4078F2)
        variable = Color(hex: dark ? 0xE06C75 : 0xE45649)
        tag = Color(hex: dark ? 0xE06C75 : 0xE45649)
        attribute = Color(hex: dark ? 0xD19A66 : 0x986801)
    }

    func color(for kind: LitteraSyntaxTokenKind) -> Color {
        switch kind {
        case .key: key
        case .string: string
        case .number: number
        case .punctuation: punctuation
        case .keyword: keyword
        case .comment: comment
        case .type: type
        case .function: function
        case .variable: variable
        case .tag: tag
        case .attribute: attribute
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
