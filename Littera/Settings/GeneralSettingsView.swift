import SwiftUI

struct LitteraGeneralSettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var theme: LitteraThemeController
    @AppStorage(LitteraPreferenceKeys.language) private var language = LitteraLanguage.fallback
    @AppStorage(LitteraPreferenceKeys.initialMode)
    private var initialMode = LitteraPreferenceDefaults.initialMode
    @AppStorage(LitteraPreferenceKeys.startupWithoutDocuments)
    private var startupWithoutDocuments = LitteraPreferenceDefaults.startupWithoutDocuments
    @AppStorage(LitteraPreferenceKeys.restoreSession)
    private var restoreSession = LitteraPreferenceDefaults.restoreSession
    @AppStorage(LitteraPreferenceKeys.autosave)
    private var autosave = LitteraPreferenceDefaults.autosave
    @AppStorage(LitteraPreferenceKeys.defaultFolderBookmark)
    private var defaultFolderBookmark: Data?
    @AppStorage(LitteraPreferenceKeys.showStatusBar)
    private var showStatusBar = LitteraPreferenceDefaults.showStatusBar

    private var appearance: Binding<LitteraAppearance> {
        Binding(get: { theme.selection }, set: { theme.select($0) })
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("ui.idioma.de.la.interfaz"), selection: $language) {
                    ForEach(LitteraLanguage.availableCodes, id: \.self) { code in
                        Text(LitteraLanguage.name(for: code)).tag(code)
                    }
                }
                .onChange(of: language) { _, code in
                    // Solo la preferencia de Littera, no la global de macOS.
                    // Los submenús del sistema se actualizan tras reiniciar.
                    UserDefaults.standard.set([code], forKey: "AppleLanguages")
                }
                Picker(tr("ui.apariencia"), selection: appearance) {
                    ForEach(LitteraAppearance.allCases) { option in
                        Text(tr(option.name)).tag(option)
                    }
                }
                Toggle(tr("ui.mostrar.barra.de.estado"), isOn: $showStatusBar)
            } footer: {
                Text(tr("ui.reinicia.littera.para.aplicar.el.idioma.a.todos.los.menus.nativos.de.m"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(tr("ui.inicio")) {
                Picker(tr("ui.vista.inicial"), selection: $initialMode) {
                    ForEach(LitteraEditorMode.allCases) { mode in
                        Text(tr(mode.titleKey)).tag(mode.rawValue)
                    }
                }
                Toggle(tr("ui.restaurar.documentos.abiertos"), isOn: $restoreSession)
                Picker(tr("ui.documento.nuevo.al.iniciar"), selection: $startupWithoutDocuments) {
                    Text(tr("ui.al.iniciar.documento.vacio")).tag("empty")
                    Text(tr("ui.al.iniciar.abrir")).tag("open")
                }
            }

            Section {
                Toggle(tr("ui.guardar.automaticamente"), isOn: $autosave)
                    .onChange(of: autosave) { _, enabled in
                        // Los documentos que ya tenían cambios se guardan al activarlo.
                        if enabled { NotificationCenter.default.post(name: .litteraAutosaveEnabled, object: nil) }
                    }
                LabeledContent(tr("ui.carpeta.predeterminada")) {
                    HStack(spacing: 8) {
                        Text(folderName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if defaultFolderBookmark != nil {
                            Button {
                                LitteraDefaultFolder.set(nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(tr("ui.quitar.carpeta.predeterminada"))
                            .accessibilityLabel(tr("ui.quitar.carpeta.predeterminada"))
                        }
                        Button(tr("ui.elegir.carpeta"), action: chooseFolder)
                    }
                }
            } header: {
                Text(tr("ui.documentos"))
            } footer: {
                Text(tr("ui.el.destino.de.los.archivos.no.cambiara.silenciosamente.abrir.guardar.y"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Nombre de la carpeta y, si está sincronizada, «iCloud Drive».
    private var folderName: String {
        guard let bookmark = defaultFolderBookmark,
              let name = LitteraDefaultFolder.displayName(for: bookmark) else {
            return tr("ui.carpeta.ninguna")
        }
        let synced = LitteraDefaultFolder.path(for: bookmark).map { LitteraStorageLocation.isSyncedWithICloud(path: $0) } ?? false
        return synced ? "\(name) · \(tr("ui.icloud.drive"))" : name
    }

    private func chooseFolder() {
        LitteraFolderPicker.choose(
            title: tr("ui.elegir.carpeta.predeterminada"),
            prompt: tr("ui.elegir"),
            startingAt: LitteraDefaultFolder.url() ?? LitteraDefaultFolder.proposed
        ) { LitteraDefaultFolder.set($0) }
    }

    private func tr(_ key: String) -> String { L10n.tr(key, locale: locale) }
}
