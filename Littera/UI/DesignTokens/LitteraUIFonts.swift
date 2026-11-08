//  LitteraUIFonts.swift
//  Rediseño de interfaz (Fase UI) · Etapa B · tipografía (§F)
//
//  Tipografía del rediseño: Inter para la interfaz y el documento (familias de
//  Stitch), JetBrains Mono NL para Fuente y bloques de código. Las fuentes se
//  incluyen en Littera/Fonts/ (Inter: OFL, ver Inter-OFL.txt) y se registran
//  para el proceso. `Font.litteraUI(size:weight:design:)` sustituye a
//  `.system(size:…)` en toda la UI del rediseño con tamaños fijos en px (como
//  Stitch). Solo presentación; sin backend.

import SwiftUI
import CoreText

nonisolated enum LitteraUIFonts {
    /// Registro único por proceso de Inter y JetBrains Mono NL.
    private static let registered: Bool = {
        let names = [
            "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Inter-Italic",
            "JetBrainsMonoNL-Regular", "JetBrainsMonoNL-Medium", "JetBrainsMonoNL-Italic"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()

    static func inter(_ weight: Font.Weight) -> String {
        _ = registered
        switch weight {
        case .bold, .heavy, .black: return "Inter-Bold"
        case .semibold: return "Inter-SemiBold"
        case .medium: return "Inter-Medium"
        default: return "Inter-Regular"
        }
    }

    static func mono(_ weight: Font.Weight) -> String {
        _ = registered
        switch weight {
        case .medium, .semibold, .bold, .heavy, .black: return "JetBrainsMonoNL-Medium"
        default: return "JetBrainsMonoNL-Regular"
        }
    }
}

extension Font {
    /// Fuente del rediseño. `design: .monospaced` usa JetBrains Mono; `.serif`
    /// usa la serif del sistema (para citas); el resto usa Inter. Tamaño fijo en
    /// px (sin escalado dinámico) para respetar la escala de Stitch.
    static func litteraUI(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        switch design {
        case .monospaced:
            return .custom(LitteraUIFonts.mono(weight), fixedSize: size)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        default:
            return .custom(LitteraUIFonts.inter(weight), fixedSize: size)
        }
    }
}
