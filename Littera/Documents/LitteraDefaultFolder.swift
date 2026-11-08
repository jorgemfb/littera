import Foundation

/// Carpeta predeterminada de Ajustes → Documentos (D49): donde se proponen
/// los documentos nuevos al guardarlos y donde empieza el panel Abrir. Se
/// guarda como marcador de seguridad, así sigue valiendo si se renombra o se
/// mueve la carpeta.
enum LitteraDefaultFolder {
    /// Carpeta ya resuelta: el acceso de seguridad se abre una sola vez por
    /// marcador, no en cada panel (antes se acumulaban accesos sin cerrar).
    private static var resolved: (bookmark: Data, url: URL)?

    /// Carpeta propuesta cuando el usuario aún no ha elegido ninguna: su
    /// carpeta Documentos. El sandbox no permite leerla sin autorización, pero
    /// sí proponerla en el selector para que la confirme una sola vez.
    /// `NSHomeDirectory()` devuelve el contenedor, así que se usa la carpeta
    /// personal real.
    static var proposed: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }

    static func url(_ defaults: UserDefaults = .standard) -> URL? {
        guard let bookmark = defaults.data(forKey: LitteraPreferenceKeys.defaultFolderBookmark) else { return nil }
        if let resolved, resolved.bookmark == bookmark, isExistingFolder(resolved.url) {
            return resolved.url
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        closeAccess()
        _ = url.startAccessingSecurityScopedResource()
        guard isExistingFolder(url) else {
            url.stopAccessingSecurityScopedResource()
            return nil
        }
        var current = bookmark
        // Carpeta movida o renombrada: se renueva el marcador para que siga valiendo.
        if isStale, let fresh = LitteraDocumentFile.bookmark(for: url) {
            defaults.set(fresh, forKey: LitteraPreferenceKeys.defaultFolderBookmark)
            current = fresh
        }
        resolved = (current, url)
        return url
    }

    private static func closeAccess() {
        resolved?.url.stopAccessingSecurityScopedResource()
        resolved = nil
    }

    /// Nombre para mostrar en Ajustes, sin abrir el acceso a la carpeta.
    static func displayName(for bookmark: Data?) -> String? {
        guard let bookmark, let path = path(for: bookmark) else { return nil }
        return FileManager.default.displayName(atPath: path)
    }

    /// Ruta de la carpeta del marcador, sin abrir el acceso a ella.
    static func path(for bookmark: Data) -> String? {
        var isStale = false
        return (try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ))?.path
    }

    /// `nil` quita la carpeta. Devuelve `false` si no se pudo crear el marcador.
    @discardableResult
    static func set(_ url: URL?, _ defaults: UserDefaults = .standard) -> Bool {
        closeAccess()
        guard let url else {
            defaults.removeObject(forKey: LitteraPreferenceKeys.defaultFolderBookmark)
            return true
        }
        guard let bookmark = LitteraDocumentFile.bookmark(for: url) else { return false }
        defaults.set(bookmark, forKey: LitteraPreferenceKeys.defaultFolderBookmark)
        return true
    }

    private static func isExistingFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
