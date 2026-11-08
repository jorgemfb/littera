
import SwiftUI

@main
struct LitteraApp: App {
    @StateObject private var theme = LitteraThemeController()
    /// Sin observar: si la app observara el store, cada pulsación volvería a
    /// evaluar sus escenas y menús. Solo «Abrir reciente» lo observa.
    private let documentStore = LitteraApp.sharedDocumentStore
    @ObservedObject private var shortcuts = LitteraShortcuts.shared
    @AppStorage(LitteraPreferenceKeys.typewriterMode)
    private var typewriterMode = LitteraPreferenceDefaults.typewriterMode
    @NSApplicationDelegateAdaptor(LitteraApplicationDelegate.self) private var applicationDelegate

    @AppStorage(LitteraPreferenceKeys.language)
    private var language = LitteraLanguage.fallback

    init() {
        LitteraPreferenceMigration.migrate()
    }


    /// Elementos de menú de los comandos del registro que lo piden (`menu:`).
    /// Se ejecutan por la misma vía que la paleta (LitteraCommandHost).
    private func registryItems(_ menu: LitteraCommand.Menu) -> some View {
        ForEach(LitteraCommandRegistry.all.filter { $0.menu == menu }) { command in
            Button(L10n.string(command.title, language: language)) {
                NotificationCenter.default.post(name: .litteraRunCommand, object: command.id)
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: command.id))
        }
    }

    var body: some Scene {
        WindowGroup(id: "littera.main") {
            LitteraMainWindow(
                documentStore: documentStore,
                applicationDelegate: applicationDelegate
            )
                // ÚNICO mínimo de la ventana. Ninguna vista interior debe
                // declarar uno mayor: SwiftUI centraría el contenido y
                // recortaría los dos bordes.
                .frame(minWidth: 960, minHeight: 620)
                .environment(
                    \.locale,
                    LitteraLanguage.locale(for: language)
                )
                .litteraTheme(theme)
        }
        // Sin esto macOS dejaba encoger la ventana por debajo del mínimo del
        // contenido: el contenido conservaba su ancho, SwiftUI lo centraba y
        // recortaba ambos bordes.
        .windowResizability(.contentMinSize)
        .commands {

            // MARK: - Acerca de (créditos en el idioma de la interfaz)

            CommandGroup(replacing: .appInfo) {
                Button(L10n.string("menu.acerca.de.littera", language: language)) {
                    LitteraAbout.show(language: language)
                }
            }

            // MARK: - Nuevo y Abrir

            CommandGroup(replacing: .newItem) {
                Button(
                    L10n.string(
                        "ui.nuevo.documento.markdown",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraNewDocument,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "new"))

                Button(
                    L10n.string(
                        "ui.abrir.documento",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraOpenDocument,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "open"))

                Menu(L10n.string("menu.abrir.reciente", language: language)) {
                    LitteraRecentDocumentsMenu(store: documentStore, language: language)
                }
            }

            // MARK: - Guardar y Guardar como

            CommandGroup(replacing: .saveItem) {
                Button(L10n.string("ui.cerrar.documento", language: language)) {
                    // ⌘W cierra el documento en la ventana del editor; en
                    // cualquier otra ventana (Ajustes) cierra esa ventana.
                    if let keyWindow = NSApp.keyWindow, !applicationDelegate.isEditorWindow(keyWindow) {
                        keyWindow.performClose(nil)
                    } else {
                        NotificationCenter.default.post(name: .litteraCloseDocument, object: nil)
                    }
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "close"))

                Button(
                    L10n.string(
                        "ui.guardar.documento",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraSaveDocument,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "save"))

                Button(
                    L10n.string(
                        "ui.guardar.como",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraSaveAsDocument,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "saveAs"))

                Divider()

                Button(L10n.string("ui.exportar.como.pdf", language: language) + "…") {
                    NotificationCenter.default.post(name: .litteraExportPDF, object: nil)
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "export.pdf"))
                Button(L10n.string("ui.exportar.como.html", language: language) + "…") {
                    NotificationCenter.default.post(name: .litteraExportHTML, object: nil)
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "export.html"))
            }

            // MARK: - Buscar (menú Edición)

            CommandGroup(after: .pasteboard) {
                Divider()
                Menu(L10n.string("menu.buscar", language: language)) {
                    Button(L10n.string("menu.buscar.ellipsis", language: language)) {
                        Self.sendFinderAction(.showFindInterface)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: "find"))

                    Button(L10n.string("menu.buscar.reemplazar", language: language)) {
                        Self.sendFinderAction(.showReplaceInterface)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: "find.replace"))

                    Button(L10n.string("menu.buscar.siguiente", language: language)) {
                        Self.sendFinderAction(.nextMatch)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: "find.next"))

                    Button(L10n.string("menu.buscar.anterior", language: language)) {
                        Self.sendFinderAction(.previousMatch)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: "find.previous"))

                    Button(L10n.string("menu.buscar.usar.seleccion", language: language)) {
                        Self.sendFinderAction(.setSearchString)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: "find.selection"))
                }
            }

            // MARK: - Vistas (menú Visualización)

            CommandGroup(before: .toolbar) {
                ForEach(LitteraEditorMode.allCases) { mode in
                    Button(L10n.string(mode.titleKey, language: language)) {
                        NotificationCenter.default.post(name: .litteraSetMode, object: mode.rawValue)
                    }
                    .keyboardShortcut(shortcuts.keyboardShortcut(for: mode.commandID))
                }
                Divider()
                Toggle(L10n.string("ui.modo.maquina.de.escribir", language: language), isOn: $typewriterMode)
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "typewriter"))
                registryItems(.view)
            }

            // MARK: - Herramientas

            CommandMenu(
                LocalizedStringKey(
                    L10n.string("menu.tools", language: language)
                )
            ) {
                Button(
                    L10n.string(
                        "ui.paleta.de.comandos",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraShowPalette,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "palette"))

                Button(
                    L10n.string(
                        "ui.documentos.abiertos",
                        language: language
                    )
                ) {
                    NotificationCenter.default.post(
                        name: .litteraShowDocuments,
                        object: nil
                    )
                }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: "documents.switch"))
                registryItems(.tools)
            }

            // MARK: - Ayuda

            CommandGroup(replacing: .help) {
                Button(L10n.string("menu.ayuda.littera", language: language)) {
                    LitteraApplicationDelegate.openHelp()
                }
                .keyboardShortcut(KeyEquivalent("?"), modifiers: [.command])
            }
        }

        Settings {
            LitteraSettingsView()
                .environment(
                    \.locale,
                    LitteraLanguage.locale(for: language)
                )
                .litteraTheme(theme)
        }
    }
}

/// Contenido de Archivo → Abrir reciente: la única parte de los menús que
/// depende del store.
private struct LitteraRecentDocumentsMenu: View {
    @ObservedObject var store: LitteraDocumentStore
    let language: String

    var body: some View {
        ForEach(store.recentDocuments) { recent in
            Button(recent.fileName) {
                store.openRecent(recent, locale: LitteraLanguage.locale(for: language))
            }
        }
        if !store.recentDocuments.isEmpty {
            Divider()
        }
        Button(L10n.string("menu.borrar.menu", language: language)) {
            store.clearRecentDocuments()
        }
        .disabled(store.recentDocuments.isEmpty)
    }
}

extension LitteraApp {
    /// Un único almacén para toda la vida de la app.
    static let sharedDocumentStore = makeDocumentStore()

    /// Almacén de la app. Como anfitriona de las pruebas (LIT-014), Littera
    /// no restaura la sesión, no vigila archivos, no guarda copias de
    /// recuperación y usa unas Preferencias volátiles propias: las pruebas
    /// nunca leen ni escriben la sesión o los ajustes del usuario.
    static func makeDocumentStore() -> LitteraDocumentStore {
        guard LitteraRuntime.isRunningTests else {
            return LitteraDocumentStore(recovery: LitteraRecoveryStore.standard())
        }
        let suiteName = "littera.testhost"
        // `UserDefaults(suiteName:)` solo devuelve `nil` con el identificador
        // de la app o el dominio global, que no es el caso. Nunca se recurre
        // a `UserDefaults.standard`.
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LitteraDocumentStore(
            defaults: defaults,
            restoresSession: false,
            observesFiles: false
        )
    }

    /// Envía la acción Buscar al primer respondedor de la ventana activa
    /// (el editor de Littera la atiende con la búsqueda de la lupa).
    static func sendFinderAction(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        let handled = NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
        // Si el editor no tiene el foco, la ventana del editor atiende la acción.
        if !handled || !(NSApp.keyWindow?.firstResponder is LitteraEditorTextView) {
            NotificationCenter.default.post(name: .litteraFinderAction, object: action.rawValue)
        }
    }
}

// MARK: - Notificaciones de comandos

extension Notification.Name {
    /// Ajustes → Documentos: se acaba de activar el guardado automático.
    static let litteraAutosaveEnabled = Notification.Name("littera.autosaveEnabled")
    static let litteraNewDocument =
        Notification.Name("littera.newDocument")

    static let litteraOpenDocument =
        Notification.Name("littera.openDocument")

    static let litteraSaveDocument =
        Notification.Name("littera.saveDocument")

    static let litteraSaveAsDocument =
        Notification.Name("littera.saveAsDocument")

    /// Ejecuta un comando del registro por su id (menús generados, D75).
    static let litteraRunCommand = Notification.Name("littera.runCommand")

    static let litteraSetMode =
        Notification.Name("littera.setMode")

    static let litteraExportPDF =
        Notification.Name("littera.exportPDF")

    static let litteraExportHTML =
        Notification.Name("littera.exportHTML")

    static let litteraFinderAction =
        Notification.Name("littera.finderAction")

    static let litteraCloseDocument =
        Notification.Name("littera.closeDocument")

    static let litteraShowPalette =
        Notification.Name("littera.showPalette")

    static let litteraShowDocuments =
        Notification.Name("littera.showDocuments")

    /// Consulta escrita en el campo de búsqueda de la barra del rediseño.
    static let litteraSearchQuery =
        Notification.Name("littera.searchQuery")

    /// Formato pedido por notificación. El objeto es el rawValue de
    /// `LitteraFormattingAction`.
    static let litteraApplyFormat =
        Notification.Name("littera.applyFormat")

    /// El editor cambió de modo (objeto: rawValue de `LitteraEditorMode`).
    /// El editor es la única fuente de verdad del modo; el selector del
    /// rediseño lo refleja.
    static let litteraModeDidChange =
        Notification.Name("littera.modeDidChange")

    /// Comando de la paleta que depende del editor (estadísticas,
    /// propiedades, formato, edición). Objeto: identificador del comando.
    static let litteraEditorCommand =
        Notification.Name("littera.editorCommand")

    /// Devolver el foco al editor tras crear o abrir un documento.
    static let litteraFocusEditor =
        Notification.Name("littera.focusEditor")



}

