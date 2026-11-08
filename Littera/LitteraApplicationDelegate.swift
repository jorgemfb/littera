import AppKit
import SwiftUI

final class LitteraApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var documentStore: LitteraDocumentStore? {
        didSet { openPendingURLs() }
    }
    var locale = Locale(identifier: "es_ES")

    /// Archivos recibidos de Finder («Abrir con», doble clic, arrastrar al
    /// icono) antes de que exista la ventana: se abren al registrarse el store.
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs += urls
        openPendingURLs()
    }

    private func openPendingURLs() {
        guard let documentStore, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        var opened = false
        for url in urls where url.isFileURL {
            opened = documentStore.openDocument(at: url, locale: locale) || opened
        }
        guard opened else { return }
        bringEditorWindowHere()
        // En un arranque en frío la ventana aún puede no existir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.bringEditorWindowHere()
        }
    }

    /// Dock: si ya hay ventana (aunque esté en otro escritorio, donde macOS la
    /// restaura), se trae aquí en lugar de dejar que SwiftUI cree otra.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !editorWindows.allObjects.isEmpty else { return true }
        bringEditorWindowHere()
        return false
    }

    /// Lleva la ventana principal al escritorio actual y al frente.
    private func bringEditorWindowHere() {
        guard let window = editorWindows.allObjects.first else { return }
        // Solo para este traslado: con el comportamiento fijo la ventana no
        // podría ir a pantalla completa ni quedarse en su escritorio.
        guard !window.styleMask.contains(.fullScreen) else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            window.collectionBehavior.remove(.moveToActiveSpace)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registrar el Help Book para que NSHelpManager pueda encontrarlo aunque
        // CFBundleHelpBookFolder esté en el Info.plist del target. El registro
        // explícito evita problemas al ejecutar en Debug desde Xcode.
        if Bundle.main.url(forResource: "Littera", withExtension: "help") != nil {
            NSHelpManager.shared.registerBooks(in: .main)
        }
        LitteraMenuTidy.install()
    }

    /// Littera tiene una sola ventana (D76): cerrarla sale de la app. Sin
    /// esto, la app quedaba abierta sin ventana y ⌘N, ⌘O o «Abrir con» no
    /// mostraban nada. Las preguntas por cambios sin guardar ya se hacen al
    /// cerrar la ventana.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let documentStore else { return .terminateNow }
        guard documentStore.protectUnsavedDocuments(locale: locale) else { return .terminateCancel }
        // Las copias de recuperación quedan al día antes de salir (LIT-001).
        documentStore.flushRecovery()
        return .terminateNow
    }

    /// Ventanas del editor (no Ajustes ni paneles): SwiftUI puede sustituir
    /// el delegado de la ventana, así que se registran aparte.
    private let editorWindows = NSHashTable<NSWindow>.weakObjects()

    func isEditorWindow(_ window: NSWindow) -> Bool {
        editorWindows.contains(window)
    }

    func attach(to window: NSWindow) {
        editorWindows.add(window)
        guard window.delegate !== self else { return }
        window.delegate = self
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let documentStore else { return true }
        return documentStore.protectUnsavedDocuments(locale: locale)
    }

    /// Abre el visor de ayuda de macOS en el índice de Littera.
    static func openHelp() {
        NSApplication.shared.showHelp(nil)
    }
}

/// Panel «Acerca de Littera»: el estándar de macOS, con el copyright del
/// Info.plist y los créditos de `Credits.html` (componentes de terceros y
/// sus licencias) en el idioma de la interfaz.
@MainActor
enum LitteraAbout {
    /// Créditos con el color de texto del sistema: macOS pinta el HTML en
    /// negro fijo, ilegible en modo oscuro.
    static func credits(language: String) -> NSAttributedString? {
        let code = Bundle.main.localizations.contains(language) ? language : LitteraLanguage.fallback
        guard let url = Bundle.main.url(forResource: "Credits", withExtension: "html", subdirectory: nil, localization: code)
                ?? Bundle.main.url(forResource: "Credits", withExtension: "html"),
              let data = try? Data(contentsOf: url),
              let credits = try? NSMutableAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return nil }
        credits.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: credits.length))
        return credits
    }

    static func show(language: String) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let credits = credits(language: language) { options[.credits] = credits }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate()
    }
}

struct LitteraWindowDelegateBridge: NSViewRepresentable {
    let delegate: LitteraApplicationDelegate

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView(frame: .zero)
        view.delegate = delegate
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { delegate.attach(to: window) }
    }

    /// Registra la ventana en cuanto la vista entra en ella: `updateNSView`
    /// puede ejecutarse antes de que exista la ventana.
    final class WindowObserverView: NSView {
        weak var delegate: LitteraApplicationDelegate?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { delegate?.attach(to: window) }
        }
    }
}
