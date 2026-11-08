import Foundation
import AppKit

// Idioma de interfaz independiente de los datos y de los archivos Markdown.
// Las traducciones están exclusivamente en Localization/<código>.lproj/Localizable.strings.
enum LitteraLanguage {
    static let settingKey = "littera.interfaceLanguage"
    static let fallback = "es"

    static var availableCodes: [String] {
        let codes = Set(Bundle.main.localizations.filter { $0 != "Base" } + ["es", "en"])
        return codes.sorted { left, right in
            if left == fallback { return true }
            if right == fallback { return false }
            return left < right
        }
    }

    static func locale(for code: String) -> Locale {
        Locale(identifier: availableCodes.contains(code) ? code : fallback)
    }

    static func name(for code: String) -> String {
        // Nombre autónimo: Deutsch, Français, Español, English…
        let nativeLocale = Locale(identifier: code)
        return (nativeLocale.localizedString(forLanguageCode: code) ?? code).capitalized(with: nativeLocale)
    }
}

enum L10n {
    static func tr(_ key: String, locale: Locale) -> String {
        // Locale suele normalizar pt-BR a pt_BR. Buscar primero la variante
        // regional completa y después el idioma base, sin modificar Swift.
        let code = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = lookup(key, language: code) { return exact }
        let base = String(code.split(separator: "-").first ?? Substring(code))
        return string(key, language: base)
    }

    static func string(_ key: String, language: String) -> String {
        if let value = lookup(key, language: language) { return value }
        if let value = lookup(key, language: LitteraLanguage.fallback) { return value }
        // Mostrar la clave es deliberado: facilita detectar recursos mal integrados.
        return key
    }

    private static func lookup(_ key: String, language: String) -> String? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        let result = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return result == key ? nil : result
    }

    static func formatted(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: tr(key, locale: locale), locale: locale, arguments: arguments)
    }

    /// Cantidad con su forma singular: para 1 usa la clave terminada en
    /// `.uno` («1 palabra»), para el resto la clave base («%d palabras»).
    /// Español e inglés solo distinguen esas dos formas.
    static func counted(_ key: String, _ count: Int, locale: Locale) -> String {
        formatted(count == 1 ? key + ".uno" : key, locale: locale, count)
    }
}

// Los menús File/Edit/View/Window/Help pertenecen a AppKit.
// Esta capa cambia solo sus títulos visibles: no sustituye acciones ni atajos.
// Los elementos internos del sistema necesitan localizaciones del target y
// pueden exigir reiniciar la aplicación para adoptar por completo el idioma.
@MainActor
enum LitteraMenuLocalization {
    static func apply(language: String) {
        guard let mainMenu = NSApp.mainMenu else { return }
        // Solo aliases de detección. Las traducciones están en .lproj.
        let topMenus: [(key: String, aliases: [String])] = [
            ("menu.file", ["File", "Archivo"]),
            ("menu.edit", ["Edit", "Edición", "Editar"]),
            ("menu.view", ["View", "Ver", "Visualización"]),
            ("menu.window", ["Window", "Ventana"]),
            ("menu.help", ["Help", "Ayuda"]),
            ("menu.tools", ["Tools", "Herramientas", "ui.herramientas"])
        ]
        for item in mainMenu.items {
            guard let menu = topMenus.first(where: {
                $0.aliases.contains(item.title)
            }) else { continue }
            let newTitle = L10n.string(menu.key, language: language)
            item.title = newTitle
            item.submenu?.title = newTitle
        }
    }
}

/// SwiftUI deja un separador por cada grupo estándar de menú aunque Littera
/// lo vacíe o lo sustituya (Archivo mostraba dos seguidos). Se ocultan los
/// separadores sobrantes cada vez que se abre la barra de menús, porque
/// SwiftUI puede reconstruir los menús en cualquier momento. No cambia
/// ninguna entrada, acción ni atajo.
@MainActor
enum LitteraMenuTidy {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let menu = note.object as? NSMenu, menu === NSApp.mainMenu else { return }
                tidy(menu)
            }
        }
    }

    /// Oculta separadores al principio, al final o repetidos, en todos los submenús.
    static func tidy(_ menu: NSMenu) {
        var previousVisibleIsSeparator = true
        var lastVisibleSeparator: NSMenuItem?
        for item in menu.items {
            if let submenu = item.submenu { tidy(submenu) }
            if item.isSeparatorItem {
                item.isHidden = previousVisibleIsSeparator
                if !item.isHidden {
                    previousVisibleIsSeparator = true
                    lastVisibleSeparator = item
                }
            } else if !item.isHidden {
                previousVisibleIsSeparator = false
                lastVisibleSeparator = nil
            }
        }
        lastVisibleSeparator?.isHidden = true
    }
}
