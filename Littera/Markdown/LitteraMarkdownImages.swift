import AppKit
import Combine
import SwiftUI

/// Acceso a las imágenes locales de los documentos dentro del sandbox.
///
/// El sandbox solo concede el archivo que el usuario abre, no las imágenes de
/// su carpeta. Cuando el usuario lo pide, Littera solicita acceso a una
/// carpeta mediante el panel nativo y guarda un bookmark de seguridad por
/// carpeta, de modo que el permiso se conserva entre sesiones. Solo se leen
/// archivos dentro de carpetas autorizadas.
@MainActor
final class LitteraLocalImageAccess: ObservableObject {
    static let shared = LitteraLocalImageAccess()

    /// Cambia cuando se concede una carpeta: las imágenes pendientes reintentan.
    @Published private(set) var grantsVersion = 0

    private static let storageKey = "littera.imageFolderBookmarks"
    private static let maximumImageBytes = 40 * 1024 * 1024
    private var resolvedFolders: [String: URL] = [:]
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 64
    }

    // MARK: - Carpetas autorizadas

    private var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.storageKey) }
    }

    /// Carpeta autorizada que contiene `fileURL`, si la hay.
    func grantedFolder(containing fileURL: URL) -> URL? {
        let path = fileURL.standardizedFileURL.path
        let candidates = bookmarks.keys
            .filter { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .sorted { $0.count > $1.count }
        for folderPath in candidates {
            if let url = resolvedFolders[folderPath] { return url }
            guard let data = bookmarks[folderPath] else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                // El bookmark ya no es válido (carpeta movida o eliminada).
                var all = bookmarks
                all.removeValue(forKey: folderPath)
                bookmarks = all
                continue
            }
            if isStale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope]) {
                var all = bookmarks
                all[folderPath] = refreshed
                bookmarks = all
            }
            resolvedFolders[folderPath] = url
            return url
        }
        return nil
    }

    /// Muestra el panel nativo para autorizar una carpeta. Devuelve `true` si
    /// la carpeta elegida contiene la imagen solicitada.
    @discardableResult
    func requestAccess(for imageURL: URL, locale: Locale) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = imageURL.deletingLastPathComponent()
        panel.message = L10n.tr("ui.imagen.panel.mensaje", locale: locale)
        panel.prompt = L10n.tr("ui.imagen.panel.permitir", locale: locale)
        guard panel.runModal() == .OK, let folder = panel.url,
              let data = try? folder.bookmarkData(options: [.withSecurityScope]) else { return false }

        let folderPath = folder.standardizedFileURL.path
        var all = bookmarks
        all[folderPath] = data
        bookmarks = all
        resolvedFolders[folderPath] = folder
        grantsVersion += 1
        return grantedFolder(containing: imageURL) != nil
    }

    // MARK: - Carga

    enum LoadResult {
        case image(NSImage)
        case needsAccess
        case notFound
    }

    /// Lectura inmediata para la exportación, que no puede esperar a la carga
    /// asíncrona de la Vista previa.
    func loadNow(_ fileURL: URL) -> LoadResult {
        guard let folder = grantedFolder(containing: fileURL) else { return .needsAccess }
        let key = fileURL.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) { return .image(cached) }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumImageBytes,
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let image = NSImage(data: data) else { return .notFound }
        cache.setObject(image, forKey: key)
        return .image(image)
    }

    /// Lee la imagen fuera del hilo principal dentro de su carpeta autorizada.
    func load(_ fileURL: URL) async -> LoadResult {
        guard let folder = grantedFolder(containing: fileURL) else { return .needsAccess }
        let key = fileURL.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) { return .image(cached) }

        let limit = Self.maximumImageBytes
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= limit,
                  let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
            return NSImage(data: data)
        }.value

        guard let image else { return .notFound }
        cache.setObject(image, forKey: key)
        return .image(image)
    }
}

extension EnvironmentValues {
    /// Archivo del documento mostrado: base para resolver rutas relativas.
    @Entry var litteraDocumentURL: URL? = nil
    /// Imágenes ya cargadas por ruta del Markdown (exportación a PDF).
    @Entry var litteraPreloadedImages: [String: NSImage] = [:]
}

/// Imagen de la Vista previa. Las imágenes locales se muestran cuando su
/// carpeta está autorizada; en otro caso, una tarjeta con el texto
/// alternativo explica por qué no se ve y, si procede, permite autorizarla.
struct LitteraMarkdownImageView: View {
    let source: String?
    let alt: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale
    @Environment(\.litteraDocumentURL) private var documentURL
    @Environment(\.litteraPreloadedImages) private var preloadedImages
    @ObservedObject private var access = LitteraLocalImageAccess.shared
    @State private var state: ImageState = .loading

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    private enum ImageState {
        case loading
        case loaded(NSImage)
        case needsAccess(URL)
        case notFound
        case remote
        case unsavedDocument
    }

    private enum Target: Equatable {
        case file(URL)
        case remote
        case unsavedDocument
        case invalid
    }

    var body: some View {
        content
            .task(id: TaskKey(target: target, grants: access.grantsVersion)) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch source.flatMap({ preloadedImages[$0] }).map(ImageState.loaded) ?? state {
        case let .loaded(image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(alt.isEmpty ? L10n.tr("ui.imagen", locale: locale) : alt)
        case .loading:
            placeholder(message: nil, action: nil)
        case let .needsAccess(url):
            placeholder(message: "ui.imagen.necesita.acceso") {
                access.requestAccess(for: url, locale: locale)
            }
        case .notFound:
            placeholder(message: "ui.imagen.no.encontrada", action: nil)
        case .remote:
            placeholder(message: "ui.imagen.remota", action: nil)
        case .unsavedDocument:
            placeholder(message: "ui.imagen.sin.guardar", action: nil)
        }
    }

    private func placeholder(message: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 18))
                .foregroundStyle(colors.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(alt.isEmpty ? (source ?? L10n.tr("ui.imagen", locale: locale)) : alt)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.primaryText)
                    .lineLimit(2)
                if let message {
                    Text(L10n.tr(message, locale: locale))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.secondaryText)
                }
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Text(L10n.tr("ui.imagen.permitir.acceso", locale: locale))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(colors.canvas, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line, lineWidth: 1))
    }

    private struct TaskKey: Equatable {
        let target: Target
        let grants: Int
    }

    private var target: Target { Self.target(for: source, documentURL: documentURL) }

    private static func target(for source: String?, documentURL: URL?) -> Target {
        guard let source = source?.trimmingCharacters(in: .whitespaces), !source.isEmpty else { return .invalid }
        if let url = URL(string: source), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https": return .remote
            case "file": return .file(url.standardizedFileURL)
            default: return .invalid
            }
        }
        let decoded = source.removingPercentEncoding ?? source
        if decoded.hasPrefix("/") {
            return .file(URL(fileURLWithPath: decoded).standardizedFileURL)
        }
        if decoded.hasPrefix("~/") {
            return .file(URL(fileURLWithPath: NSString(string: decoded).expandingTildeInPath).standardizedFileURL)
        }
        guard let documentURL else { return .unsavedDocument }
        let base = documentURL.deletingLastPathComponent()
        return .file(base.appendingPathComponent(decoded).standardizedFileURL)
    }

    /// Archivo local de una imagen del Markdown, si lo es.
    static func localFile(for source: String?, documentURL: URL?) -> URL? {
        if case let .file(url) = target(for: source, documentURL: documentURL) { return url }
        return nil
    }

    private func load() async {
        switch target {
        case .remote:
            state = .remote
        case .unsavedDocument:
            state = .unsavedDocument
        case .invalid:
            state = .notFound
        case let .file(url):
            switch await access.load(url) {
            case let .image(image): state = .loaded(image)
            case .needsAccess: state = .needsAccess(url)
            case .notFound: state = .notFound
            }
        }
    }
}
