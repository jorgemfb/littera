import Foundation

/// Estado de descarga de un archivo que puede estar en iCloud Drive.
nonisolated enum LitteraDownloadStatus: Equatable, Sendable {
    /// Local, o de iCloud y ya descargado: se puede leer.
    case available
    /// En iCloud pero no en este Mac (o descargándose).
    case needsDownload
    /// iCloud informó de un error al descargarlo (por ejemplo, sin conexión).
    case failed(String)
}

/// Una versión en conflicto: otro dispositivo guardó el mismo archivo a la vez.
nonisolated struct LitteraConflictVersion: Equatable, Sendable {
    let id: String
    let deviceName: String?
    let modificationDate: Date?
}

/// Operaciones de iCloud Drive sobre los documentos (D50). La app usa
/// `LitteraSystemCloudFiles`; las pruebas, una versión simulada.
protocol LitteraCloudFileService: AnyObject {
    func isInICloud(_ url: URL) -> Bool
    func downloadStatus(_ url: URL) -> LitteraDownloadStatus
    func startDownloading(_ url: URL) throws
    func conflicts(at url: URL) -> [LitteraConflictVersion]
    func contents(of version: LitteraConflictVersion, at url: URL) throws -> String
    /// Marca los conflictos como resueltos. Con `version`, esa versión pasa a
    /// ser el archivo; sin ella, se conserva el actual.
    func resolveConflicts(at url: URL, using version: LitteraConflictVersion?) throws
}

final class LitteraSystemCloudFiles: LitteraCloudFileService {
    func isInICloud(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return true
        }
        return LitteraStorageLocation.isICloudPath(url)
    }

    func downloadStatus(_ url: URL) -> LitteraDownloadStatus {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let values = try? fresh.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey,
        ]), values.isUbiquitousItem == true else { return .available }
        if let error = values.ubiquitousItemDownloadingError {
            return .failed(error.localizedDescription)
        }
        return values.ubiquitousItemDownloadingStatus == .notDownloaded ? .needsDownload : .available
    }

    func startDownloading(_ url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    func conflicts(at url: URL) -> [LitteraConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { Self.describe($0) }
    }

    func contents(of version: LitteraConflictVersion, at url: URL) throws -> String {
        guard let fileVersion = Self.version(version.id, at: url) else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: fileVersion.url)
        guard let text = String(data: data, encoding: .utf8) else { throw LitteraDocumentFile.ReadError.notUTF8 }
        return text
    }

    func resolveConflicts(at url: URL, using version: LitteraConflictVersion?) throws {
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { writingURL in
            do {
                if let version {
                    guard let fileVersion = Self.version(version.id, at: writingURL) else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try fileVersion.replaceItem(at: writingURL, options: [])
                }
                // Solo se retiran las versiones en conflicto: removeOtherVersions
                // borraría también el historial de versiones del archivo.
                for conflict in NSFileVersion.unresolvedConflictVersionsOfItem(at: writingURL) ?? [] {
                    conflict.isResolved = true
                    try conflict.remove()
                }
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    private static func describe(_ version: NSFileVersion) -> LitteraConflictVersion {
        LitteraConflictVersion(
            id: version.url.absoluteString,
            deviceName: version.localizedNameOfSavingComputer,
            modificationDate: version.modificationDate
        )
    }

    private static func version(_ id: String, at url: URL) -> NSFileVersion? {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.first { $0.url.absoluteString == id }
    }
}

/// Dónde viven los documentos: la carpeta predeterminada (D49) en este Mac o
/// en iCloud Drive (D50). Cambiarla nunca mueve archivos.
enum LitteraStorageLocation {
    nonisolated static func isICloudPath(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Library/Mobile Documents/")
    }

    /// Carpeta sincronizada con iCloud Drive: dentro de iCloud Drive o en
    /// Escritorio/Documentos con «Escritorio y Documentos» activado.
    static func isSyncedWithICloud(path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if isICloudPath(url) { return true }
        return (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }
}
