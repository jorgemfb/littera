//  LitteraSettingsView.swift
//  Littera v1 · Preferencias mínimas y nativas (D80)
//
//  Tres páginas (General, Editor y Atajos) en pestañas nativas de macOS, con
//  formularios agrupados. Los cambios se aplican al momento (convención de
//  macOS), sin botones Cancelar/Listo.
//
//  CÓMO AÑADIR UNA PÁGINA: una entrada en `LitteraPreferencesRegistry.pages`.

import SwiftUI

struct LitteraPreferencesPage: Identifiable {
    let id: String
    let titleKey: String
    let symbol: String
    let content: () -> AnyView
}

enum LitteraPreferencesRegistry {
    static var pages: [LitteraPreferencesPage] {
        [
            .init(id: "general", titleKey: "ui.general", symbol: "gearshape",
                  content: { AnyView(LitteraGeneralSettingsView()) }),
            .init(id: "editor", titleKey: "ui.editor", symbol: "square.and.pencil",
                  content: { AnyView(LitteraEditorSettingsView()) }),
            .init(id: "shortcuts", titleKey: "ui.atajos", symbol: "command",
                  content: { AnyView(LitteraKeyboardSettingsView()) })
        ]
    }
}

/// Escena de Preferencias.
struct LitteraSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.locale) private var locale

    var body: some View {
        TabView {
            ForEach(LitteraPreferencesRegistry.pages) { page in
                page.content()
                    .tabItem { Label(L10n.tr(page.titleKey, locale: locale), systemImage: page.symbol) }
                    .tag(page.id)
            }
        }
        .frame(width: 560, height: 520)
        // El grabador de atajos usa los colores del tema de Littera.
        .litteraUITheme(scheme, contrast: contrast)
    }
}
