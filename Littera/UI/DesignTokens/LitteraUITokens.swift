//  LitteraUITokens.swift
//
//  Medidas de la paleta: radios, bordes y escala tipográfica. Sin colores
//  (los colores viven en LitteraUITheme, D57).
//
//  Capa de presentación: no importa servicios del backend.

import CoreGraphics

nonisolated enum LitteraUITokens {

    /// Radios y bordes compartidos (valores de Stitch: 2 / 4 / 8 px).
    enum Shape {
        static let small: CGFloat = 2
        static let control: CGFloat = 4
        static let panel: CGFloat = 8
        static let hairline: CGFloat = 0.7
    }

    /// Escala tipográfica (px), con Inter en la interfaz y JetBrains Mono en código.
    enum FontSize {
        static let labelSm: CGFloat = 11
        static let labelMd: CGFloat = 13
        static let codeSm: CGFloat = 11
    }
}
