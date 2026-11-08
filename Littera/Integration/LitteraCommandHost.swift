//  LitteraCommandHost.swift
//  Centro de mando de la ventana
//
//  Este anfitrión envuelve toda la ventana y está siempre montado. Atiende lo
//  que es de la ventana y de los documentos; el editor conserva solo lo que
//  depende de su estado (modo, búsqueda, formato, comandos de edición), que le
//  llega por notificación. Vive fuera de Littera/UI/: usa el backend.

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LitteraCommandHost<Content: View>: View {
    @ObservedObject var documentStore: LitteraDocumentStore
    let applicationDelegate: LitteraApplicationDelegate
    @ViewBuilder var content: Content

    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(LitteraPreferenceKeys.language) private var language = LitteraLanguage.fallback

    /// Paleta abierta (⌘K: documentos y comandos; ⇧⌘O: documentos).
    @State private var activePalette: LitteraUIPaletteScope?
    /// Cada apertura es una paleta nueva (búsqueda limpia).
    @State private var paletteSerial = 0
    /// Modo real del editor (lo publica el editor): decide si la paleta
    /// ofrece los comandos de edición, que no valen en Vista previa.
    @State private var editorMode: LitteraEditorMode = .source

    @Environment(\.litteraUITheme) private var theme

    var body: some View {
        ZStack {
            content

            if let activePalette {
                theme.overlay
                    .ignoresSafeArea()
                    .onTapGesture { self.activePalette = nil }
                    .transition(.opacity)

                VStack {
                    LitteraUICommandPaletteView(
                        documents: paletteDocumentEntries,
                        commands: paletteCommands,
                        scope: activePalette,
                        onChooseDocument: chooseDocument,
                        onChooseCommand: runCommand,
                        onDismiss: dismissPalette
                    )
                    .id(paletteSerial)
                    Spacer()
                }
                .padding(.top, LitteraDesign.CommandPalette.topOffset)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(2)
            }
        }
        .background(
            LitteraWindowDelegateBridge(delegate: applicationDelegate)
                .frame(width: 0, height: 0)
        )
        .onAppear {
            applicationDelegate.documentStore = documentStore
            applicationDelegate.locale = LitteraLanguage.locale(for: language)
            DispatchQueue.main.async { LitteraMenuLocalization.apply(language: language) }
            handleStartupWithoutDocuments()
        }
        .onChange(of: language) { _, value in
            applicationDelegate.locale = LitteraLanguage.locale(for: value)
            DispatchQueue.main.async { LitteraMenuLocalization.apply(language: value) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: activePalette != nil)
        .onReceive(LitteraCommandHostStartup.commandNotifications) { handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: .litteraModeDidChange)) { note in
            if let raw = note.object as? String, let mode = LitteraEditorMode(rawValue: raw) {
                editorMode = mode
            }
        }
    }

    // MARK: Comandos de la ventana

    private func handle(_ notification: Notification) {
        switch notification.name {
        case .litteraShowPalette: openPalette(.all)
        case .litteraShowDocuments: openPalette(.documents)
        case .litteraNewDocument: createNewDocument()
        case .litteraOpenDocument: openDocument()
        case .litteraSaveDocument: saveActiveDocument(forceSavePanel: false)
        case .litteraSaveAsDocument: saveActiveDocument(forceSavePanel: true)
        case .litteraExportPDF: exportActiveDocument(.pdf)
        case .litteraExportHTML: exportActiveDocument(.html)
        case .litteraCloseDocument: closeActiveDocument()
        // Menús generados desde el registro: misma vía que la paleta.
        case .litteraRunCommand:
            if let id = notification.object as? String { runCommand(id) }
        case NSApplication.didBecomeActiveNotification:
            documentStore.checkExternalChanges(locale: locale)
            documentStore.checkConflicts(locale: locale)
        case .litteraAutosaveEnabled:
            documentStore.autosaveDirtyDocuments()
        case NSApplication.willResignActiveNotification:
            // Guardado automático: al cambiar de app no se espera a la pausa.
            documentStore.flushPendingAutosaves()
        default:
            break
        }
    }

    // MARK: Paletas

    // Se aplaza al siguiente ciclo para que el ⌘K o ⇧⌘O no compita con el foco
    // inicial del campo de búsqueda de la paleta.
    private func openPalette(_ scope: LitteraUIPaletteScope) {
        DispatchQueue.main.async {
            activePalette = nil
            DispatchQueue.main.async {
                paletteSerial += 1
                activePalette = scope
            }
        }
    }

    private func dismissPalette() { activePalette = nil }

    /// Comandos del registro (D72), localizados y con su disponibilidad.
    private var paletteCommands: [LitteraUIPaletteEntry] {
        let canEdit = editorMode != .preview
        return LitteraCommandRegistry.all.map { command in
            LitteraUIPaletteEntry(
                id: command.id,
                kind: .command,
                title: L10n.tr(command.title, locale: locale),
                symbol: command.symbol,
                group: L10n.tr(command.group, locale: locale),
                shortcut: LitteraCommandRegistry.shortcut(for: command),
                keywords: command.keywords.map { L10n.tr($0, locale: locale) },
                enabled: !command.requiresEditing || canEdit
            )
        }
    }

    /// Documentos abiertos y, después, los recientes que no lo están (D80).
    private var paletteDocumentEntries: [LitteraUIPaletteEntry] {
        LitteraCommandHostPalette.documentEntries(
            documents: documentStore.documents,
            activeID: documentStore.activeDocumentID,
            recents: documentStore.recentDocuments
        )
    }

    private func chooseDocument(_ id: String) {
        dismissPalette()
        if documentStore.documents.contains(where: { $0.id == id }) {
            documentStore.activeDocumentID = id
        } else if let path = LitteraCommandHostPalette.recentPath(fromID: id),
                  let recent = documentStore.recentDocuments.first(where: { $0.path == path }) {
            documentStore.openRecent(recent, locale: locale)
        } else {
            return
        }
        focusEditorAfterUpdate()
    }

    /// Ejecuta un comando del registro sin saber qué hace.
    private func runCommand(_ id: String) {
        guard let command = LitteraCommandRegistry.command(id) else { return }
        dismissPalette()
        command.perform()
    }

    // MARK: Documentos

    private func createNewDocument() {
        documentStore.newDocument(locale: locale)
        dismissPalette()
        focusEditorAfterUpdate()
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("ui.abrir.documento", locale: locale)
        panel.allowedContentTypes = [.markdown, UTType(filenameExtension: "markdown")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let folder = LitteraDefaultFolder.url() {
            panel.directoryURL = folder
        }
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        documentStore.openDocument(at: selectedURL, locale: locale)
        dismissPalette()
        focusEditorAfterUpdate()
    }

    /// Tras crear o abrir, el foco vuelve al editor para escribir sin hacer
    /// clic (1.1.0), cuando SwiftUI ya ha cargado el texto nuevo.
    private func focusEditorAfterUpdate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .litteraFocusEditor, object: nil)
        }
    }

    private func exportActiveDocument(_ format: LitteraExporter.Format) {
        dismissPalette()
        guard let document = documentStore.activeDocument,
              let derived = documentStore.derivedDocuments[document.id] else { return }
        LitteraExporter.export(document, derived: derived, format: format, locale: locale)
    }

    private func closeActiveDocument() {
        dismissPalette()
        documentStore.closeDocument(id: documentStore.activeDocumentID, locale: locale)
    }

    private func saveActiveDocument(forceSavePanel: Bool) {
        _ = documentStore.saveDocument(
            id: documentStore.activeDocumentID,
            forceSavePanel: forceSavePanel,
            locale: locale
        )
    }

    // MARK: Arranque

    /// Solo la primera ventana: copias de recuperación (LIT-001) y, si así se
    /// eligió en Ajustes → General, el panel Abrir cuando no se restauró nada.
    private func handleStartupWithoutDocuments() {
        // Como anfitriona de las pruebas no se abre ningún panel (LIT-014).
        guard !LitteraCommandHostStartup.done, !LitteraRuntime.isRunningTests else { return }
        LitteraCommandHostStartup.done = true
        DispatchQueue.main.async {
            documentStore.offerRecovery(locale: locale)
            let choice = UserDefaults.standard.string(forKey: LitteraPreferenceKeys.startupWithoutDocuments)
                ?? LitteraPreferenceDefaults.startupWithoutDocuments
            guard choice == "open",
                  documentStore.documents.count == 1,
                  documentStore.activeDocument?.isPristineUntitled == true else { return }
            openDocument()
        }
    }
}

/// Estado estático fuera del tipo genérico (los genéricos no admiten
/// propiedades estáticas almacenadas).
private enum LitteraCommandHostStartup {
    static var done = false

    static let commandNotifications = Publishers.MergeMany(
        [
            Notification.Name.litteraShowPalette, .litteraShowDocuments, .litteraNewDocument,
            .litteraOpenDocument, .litteraSaveDocument, .litteraSaveAsDocument,
            .litteraExportPDF, .litteraExportHTML, .litteraCloseDocument, .litteraRunCommand,
            NSApplication.didBecomeActiveNotification,
            NSApplication.willResignActiveNotification, .litteraAutosaveEnabled
        ].map { NotificationCenter.default.publisher(for: $0) }
    )
}

/// Entradas de documentos de la paleta, fuera del tipo genérico para poder
/// probarlas sin vistas.
enum LitteraCommandHostPalette {
    static let recentPrefix = "recent:"

    static func documentEntries(
        documents: [LitteraDocumentSession],
        activeID: String,
        recents: [LitteraRecentDocument]
    ) -> [LitteraUIPaletteEntry] {
        let openPaths = Set(documents.compactMap { $0.fileURL?.path })
        let open = documents.map { session in
            LitteraUIPaletteEntry(
                id: session.id, kind: .document, title: session.fileName,
                detail: session.fileName, secondary: session.folderDescription,
                symbol: "doc.text", isOpen: true,
                isActive: session.id == activeID
            )
        }
        let closed = recents.filter { !openPaths.contains($0.path) }.map { recent in
            LitteraUIPaletteEntry(
                id: recentPrefix + recent.path, kind: .document, title: recent.fileName,
                detail: recent.fileName, secondary: (recent.path as NSString).deletingLastPathComponent,
                symbol: "clock"
            )
        }
        return open + closed
    }

    static func recentPath(fromID id: String) -> String? {
        id.hasPrefix(recentPrefix) ? String(id.dropFirst(recentPrefix.count)) : nil
    }
}
