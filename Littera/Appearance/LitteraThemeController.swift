import AppKit
import Combine
import SwiftUI

// MARK: - Preferencia de tema (NO pertenece al sistema de diseño)

enum LitteraAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    // Conservamos las mismas claves que las traducciones actuales.
    var name: String {
        switch self {
        case .system: "ui.sistema"
        case .light: "ui.claro"
        case .dark: "ui.oscuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    fileprivate var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Única fuente de verdad para TODAS las ventanas de Littera

@MainActor
final class LitteraThemeController: ObservableObject {
    @Published private(set) var selection: LitteraAppearance

    init() {
        // La clave v1 es deliberadamente nueva: la preferencia previa podía
        // quedar almacenada en "Claro" mientras la aplicación aparecía oscura.
        // Primer arranque tras esta migración = Sistema. Después se respeta
        // siempre la selección que haga el usuario.
        let stored = UserDefaults.standard.string(forKey: LitteraPreferenceKeys.themeMode)
        selection = LitteraAppearance(rawValue: stored ?? "") ?? .system

        applyToApplication(selection)
    }

    func select(_ newSelection: LitteraAppearance) {
        guard selection != newSelection else { return }

        // La apariencia es una decisión de APLICACIÓN, no de una ventana.
        // AppKit hereda este valor en ventanas, paneles y menús.
        applyToApplication(newSelection)

        UserDefaults.standard.set(
            newSelection.rawValue,
            forKey: LitteraPreferenceKeys.themeMode
        )
        selection = newSelection
    }

    private func applyToApplication(_ mode: LitteraAppearance) {
        // nil devuelve el control al modo Sistema de macOS.
        // Nunca asignar apariencias por separado a NSWindow o NSView.
        NSApplication.shared.appearance = mode.appKitAppearance
    }
}

// MARK: - Actualización de SwiftUI en las dos escenas

// LitteraEditorView y LitteraSettingsView dependen del colorScheme para obtener
// los tokens de LitteraPalette. En vez de preferredColorScheme() en dos escenas
// separadas, este host observa el MISMO controlador para ambas.
private struct LitteraThemeHost<Content: View>: View {
    @ObservedObject var controller: LitteraThemeController
    let content: Content
    @Environment(\.colorScheme) private var inheritedColorScheme

    var body: some View {
        // Mantener un único árbol de vistas evita que cambiar de tema
        // reinicie @State de Settings, el scroll o la navegación. En Sistema
        // se conserva el colorScheme que AppKit haya heredado de macOS.
        content
            .environment(\.colorScheme, controller.selection.colorScheme ?? inheritedColorScheme)
            .environmentObject(controller)
    }
}

extension View {
    func litteraTheme(_ controller: LitteraThemeController) -> some View {
        LitteraThemeHost(controller: controller, content: self)
    }
}
