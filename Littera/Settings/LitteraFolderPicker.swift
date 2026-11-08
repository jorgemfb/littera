import AppKit

/// Panel para elegir una carpeta desde Ajustes. Se presenta como hoja de la
/// ventana de Ajustes: con `runModal()` el panel era una ventana suelta y, al
/// cerrarse, macOS devolvía al frente la ventana del editor, que tapaba
/// Ajustes como si se hubiera cerrado (1.0.4).
enum LitteraFolderPicker {
    static func choose(
        title: String,
        prompt: String,
        startingAt folder: URL?,
        completion: @escaping (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let folder { panel.directoryURL = folder }

        // La ventana que tiene el foco es la de Ajustes, desde donde se pulsó.
        guard let window = NSApp.keyWindow else {
            if panel.runModal() == .OK, let url = panel.url { completion(url) }
            return
        }
        panel.beginSheetModal(for: window) { response in
            window.makeKeyAndOrderFront(nil)
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
