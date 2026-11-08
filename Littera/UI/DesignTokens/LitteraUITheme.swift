//  LitteraUITheme.swift
//  Rediseño de interfaz (Fase UI) · Etapa B · paso 1 (apariencia)
//
//  Paleta del rediseño alineada con los tokens reales de Stitch («macOS Markdown
//  Editor», roles Material 3), con el acento en terracota de Littera (D56).
//  Los valores provienen del HTML del proyecto Stitch (ver docs/
//  UI_FIDELITY_DIAGNOSIS.md §2). Archivo aparte del tema en producción (D57).
//
//  Capa de presentación: no importa servicios del backend.

import SwiftUI

/// Colores del rediseño resueltos por esquema. Inmutable y Sendable.
nonisolated struct LitteraUITheme: Equatable, Sendable {
    // Superficies (de lowest a highest en Stitch)
    let canvas: Color          // contenido (editor / vista previa) · surface-container-lowest
    let chrome: Color          // barras y barra lateral · surface-container-low
    let secondary: Color       // tarjetas / superficies secundarias · surface-container
    let control: Color         // controles en reposo (segmentado, botones) · surface-container-high
    let selected: Color        // selección atenuada · primary/10
    let line: Color            // bordes y separadores · outline-variant
    // Texto
    let primaryText: Color     // on-surface
    let secondaryText: Color   // on-surface-variant
    let muted: Color           // outline (números de línea, texto muy atenuado)
    // Acentos
    let accent: Color          // primario · terracota (D56)
    let accentSecondary: Color // secondary · morado (claves YAML, etiquetas)
    let accentTertiary: Color  // tertiary · verde (checklist, estados, iCloud)
    let overlay: Color         // velo tras las paletas

    init(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) {
        let dark = scheme == .dark
        if dark {
            canvas = Color(litteraUIHex: 0x1C1C1E)
            chrome = Color(litteraUIHex: 0x242426)
            secondary = Color(litteraUIHex: 0x2A2A2E)
            control = Color(litteraUIHex: 0x323234)
            line = Color(litteraUIHex: 0x3A3A3C)
            primaryText = Color(litteraUIHex: 0xECECEC)
            accent = Color(litteraUIHex: 0xC5785B)          // terracota oscuro (D28)
            accentSecondary = Color(litteraUIHex: 0xC2C1FF) // secondary-fixed-dim
            accentTertiary = Color(litteraUIHex: 0x53E16F)  // tertiary-fixed-dim
            overlay = Color.black.opacity(0.45)
        } else {
            canvas = Color(litteraUIHex: 0xFFFFFF)          // surface-container-lowest
            chrome = Color(litteraUIHex: 0xF4F3F8)          // surface-container-low
            secondary = Color(litteraUIHex: 0xEEEDF3)       // surface-container
            control = Color(litteraUIHex: 0xE9E7ED)         // surface-container-high
            line = Color(litteraUIHex: 0xC1C6D7)            // outline-variant
            primaryText = Color(litteraUIHex: 0x1A1B1F)     // on-surface
            accent = Color(litteraUIHex: 0xD78363)          // terracota (D28)
            accentSecondary = Color(litteraUIHex: 0x4C4ACA) // secondary
            accentTertiary = Color(litteraUIHex: 0x006B27)  // tertiary
            overlay = Color.black.opacity(0.25)
        }
        // D47: «Aumentar contraste» refuerza el texto secundario y atenuado.
        if contrast == .increased {
            secondaryText = dark ? Color(litteraUIHex: 0xD4D4D9) : Color(litteraUIHex: 0x2A2E38)
            muted       = dark ? Color(litteraUIHex: 0xA8A8AD) : Color(litteraUIHex: 0x4A4F5C)
        } else {
            secondaryText = dark ? Color(litteraUIHex: 0x9A9A9E) : Color(litteraUIHex: 0x414755)
            muted       = dark ? Color(litteraUIHex: 0x6E6E73) : Color(litteraUIHex: 0x717786)
        }
        selected = accent.opacity(0.12)
    }
}

nonisolated struct LitteraUIThemeKey: EnvironmentKey {
    static let defaultValue = LitteraUITheme(.light)
}

extension EnvironmentValues {
    nonisolated var litteraUITheme: LitteraUITheme {
        get { self[LitteraUIThemeKey.self] }
        set { self[LitteraUIThemeKey.self] = newValue }
    }
}

extension View {
    func litteraUITheme(_ scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> some View {
        environment(\.litteraUITheme, LitteraUITheme(scheme, contrast: contrast))
    }
}

private extension Color {
    nonisolated init(litteraUIHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
