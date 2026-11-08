import SwiftUI

enum LitteraEditorMode: String, CaseIterable, Identifiable {
    case source = "Fuente"
    case split = "Dividido"
    case preview = "Vista previa"

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .source: "ui.fuente"
        case .split: "ui.dividido"
        case .preview: "ui.vista.previa"
        }
    }

    /// Identificador del comando (paleta y atajos).
    var commandID: String {
        switch self {
        case .source: "source"
        case .split: "split"
        case .preview: "preview"
        }
    }
}

/// Anchura del texto (una sola para Fuente, Dividido y Vista previa).
enum LitteraWritingWidth: String, CaseIterable, Identifiable {
    case narrow = "Estrecho"
    case medium = "Medio"
    case wide = "Ancho"
    /// Todo el ancho de la ventana, con los márgenes mínimos.
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

    var points: CGFloat {
        switch self {
        case .narrow: 570
        case .medium: 760
        case .wide: 950
        case .available: .greatestFiniteMagnitude
        }
    }

    /// Columna de Fuente: `nil` es todo el ancho disponible.
    var sourceColumnWidth: CGFloat? { LitteraSourceWidth.stored(rawValue).columnWidth }
}

/// Interlineado del texto (Ajustes → Editor). `normal` es el de UI 1.0.
nonisolated enum LitteraLineSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal
    case wide

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .compact: "ui.interlineado.compacto"
        case .normal: "ui.interlineado.normal"
        case .wide: "ui.interlineado.amplio"
        }
    }

    /// Espacio entre líneas del texto en Vista previa.
    var bodySpacing: CGFloat {
        switch self {
        case .compact: 5
        case .normal: 9
        case .wide: 14
        }
    }

    /// Espacio entre líneas en Fuente.
    var sourceSpacing: CGFloat {
        switch self {
        case .compact, .normal: 0
        case .wide: 5
        }
    }

    static func stored(_ rawValue: String) -> Self { Self(rawValue: rawValue) ?? .normal }
}
