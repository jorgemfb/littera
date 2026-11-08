import Darwin
import Foundation
import os.log

/// Lectura y escritura de archivos `.md` y marcadores de seguridad. No
/// depende de la interfaz: el almacén de documentos decide qué hacer con
/// los errores y los conflictos.
nonisolated enum LitteraDocumentFile {
    private static let log = Logger(subsystem: "com.littera", category: "files")

    enum ReadError: Error {
        case notUTF8
    }

    enum WriteError: Error {
        /// El archivo existe y no tiene permiso de escritura.
        case readOnly
    }

    /// El reemplazo atómico renombra sobre el archivo aunque sea de solo
    /// lectura: sin esta comprobación se sobrescribía sin preguntar.
    private static func ensureWritable(_ url: URL) throws {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              !FileManager.default.isWritableFile(atPath: path) else { return }
        throw WriteError.readOnly
    }

    struct Contents: Equatable {
        let markdown: String
        let modificationDate: Date?
        /// El archivo empezaba con la marca de orden de bytes UTF-8. `String`
        /// la descarta al decodificar; se vuelve a escribir al guardar.
        var hasByteOrderMark = false
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    private static func encoded(_ markdown: String, byteOrderMark: Bool) -> Data {
        var data = Data()
        if byteOrderMark { data.append(contentsOf: Self.byteOrderMark) }
        data.append(contentsOf: markdown.utf8)
        return data
    }

    /// Lectura coordinada (D50): si iCloud Drive u otra app está escribiendo
    /// el archivo, espera a que termine. `presenter` es el del propio
    /// documento, para no avisarse a sí mismo.
    static func read(_ url: URL, presenter: NSFilePresenter? = nil) throws -> Contents {
        var coordinationError: NSError?
        var result: Result<Contents, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { readingURL in
            result = Result {
                let data = try Data(contentsOf: readingURL)
                guard let markdown = String(data: data, encoding: .utf8) else { throw ReadError.notUTF8 }
                return Contents(
                    markdown: markdown,
                    modificationDate: modificationDate(of: readingURL),
                    hasByteOrderMark: data.starts(with: byteOrderMark)
                )
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Escritura atómica y coordinada (D50).
    ///
    /// Un enlace simbólico se conserva: se escribe en el archivo al que apunta
    /// en lugar de sustituir el enlace por un archivo nuevo (LIT-012).
    static func write(
        _ markdown: String,
        to url: URL,
        byteOrderMark: Bool = false,
        presenter: NSFilePresenter? = nil
    ) throws {
        let url = url.resolvingSymlinksInPath()
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { writingURL in
            do {
                try ensureWritable(writingURL)
                let metadata = try FileMetadata.snapshot(of: writingURL)
                try encoded(markdown, byteOrderMark: byteOrderMark).write(to: writingURL, options: .atomic)
                metadata?.restore(to: writingURL)
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    /// El archivo cambió en el disco justo antes de escribir. El mensaje lo
    /// pone el store, en el idioma de la interfaz.
    enum WriteConflictError: Error {
        case externallyModified
    }

    /// Escritura atómica y coordinada que verifica que el archivo no fue
    /// modificado desde `knownDate` antes de escribir. Si la fecha cambió,
    /// lanza `WriteConflictError.externallyModified`.
    static func writeVerified(
        _ markdown: String,
        to url: URL,
        knownDate: Date?,
        byteOrderMark: Bool = false,
        presenter: NSFilePresenter? = nil
    ) throws {
        let url = url.resolvingSymlinksInPath()
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { writingURL in
            do {
                let currentDate = modificationDate(of: writingURL)
                let exists = FileManager.default.fileExists(atPath: writingURL.path)
                let state = LitteraDiskState.compare(known: knownDate, current: currentDate, fileExists: exists)
                // Si desaparece tras la comprobación previa no se recrea: el
                // autosave debe conservar el texto como no guardado para que
                // el usuario decida la nueva ubicación o resuelva el conflicto.
                guard state == .unchanged else { throw WriteConflictError.externallyModified }
                try ensureWritable(writingURL)
                let metadata = try FileMetadata.snapshot(of: writingURL)
                try encoded(markdown, byteOrderMark: byteOrderMark).write(to: writingURL, options: .atomic)
                metadata?.restore(to: writingURL)
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    /// Metadatos propios del inode que `Data.WritingOptions.atomic` sustituye
    /// al instalar el archivo temporal. Se restauran dentro de la misma
    /// coordinación, después de que el contenido ya sea atómico.
    ///
    /// Los hard links no se restauran: preservar su identidad exigiría
    /// escribir en el inode compartido y perder el reemplazo atómico. Littera
    /// prioriza que la ruta guardada nunca exponga contenido parcial; los
    /// demás enlaces conservan el contenido anterior.
    private struct FileMetadata {
        let creationDate: Date?
        let permissions: NSNumber?
        let extendedAttributes: [(name: String, value: Data)]

        static func snapshot(of url: URL) throws -> FileMetadata? {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return FileMetadata(
                creationDate: attributes[.creationDate] as? Date,
                permissions: attributes[.posixPermissions] as? NSNumber,
                extendedAttributes: try readExtendedAttributes(at: path)
            )
        }

        /// macOS los pone en cada archivo nuevo; el sandbox no deja reescribir
        /// `com.apple.quarantine` (EPERM), lo que hacía fallar guardados ya escritos.
        static let systemManagedAttributes: Set<String> = [
            "com.apple.quarantine", "com.apple.provenance", "com.apple.macl"
        ]

        /// El contenido ya está instalado: lo que no se pueda restaurar se
        /// registra, pero no convierte el guardado en un fallo. Los permisos van
        /// al final porque, en un archivo de solo lectura, impedirían escribir
        /// los atributos extendidos.
        func restore(to url: URL) {
            for attribute in extendedAttributes {
                do {
                    try setExtendedAttribute(attribute.value, named: attribute.name, at: url.path)
                } catch {
                    LitteraDocumentFile.log.error("No se pudo restaurar el atributo \(attribute.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            var attributes: [FileAttributeKey: Any] = [:]
            if let creationDate { attributes[.creationDate] = creationDate }
            if let permissions { attributes[.posixPermissions] = permissions }
            guard !attributes.isEmpty else { return }
            do {
                try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
            } catch {
                LitteraDocumentFile.log.error("No se pudieron restaurar la fecha de creación o los permisos: \(error.localizedDescription, privacy: .public)")
            }
        }

        private static func readExtendedAttributes(at path: String) throws -> [(name: String, value: Data)] {
            let size = try path.withCString { pathPointer -> Int in
                let result = listxattr(pathPointer, nil, 0, 0)
                guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                return result
            }
            guard size > 0 else { return [] }
            var names = [CChar](repeating: 0, count: size)
            let count = try path.withCString { pathPointer -> Int in
                let result = listxattr(pathPointer, &names, names.count, 0)
                guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                return result
            }
            let attributeNames = String(decoding: names.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                .split(separator: "\0")
                .map(String.init)
                .filter { !systemManagedAttributes.contains($0) }
            return try attributeNames.map { name in
                (name, try extendedAttribute(named: name, at: path))
            }
        }

        private static func extendedAttribute(named name: String, at path: String) throws -> Data {
            let size = try path.withCString { pathPointer -> Int in
                try name.withCString { namePointer in
                    let result = getxattr(pathPointer, namePointer, nil, 0, 0, 0)
                    guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    return result
                }
            }
            var bytes = [UInt8](repeating: 0, count: size)
            let count = try path.withCString { pathPointer -> Int in
                try name.withCString { namePointer in
                    let result = bytes.withUnsafeMutableBytes { buffer in
                        getxattr(pathPointer, namePointer, buffer.baseAddress, buffer.count, 0, 0)
                    }
                    guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    return result
                }
            }
            return Data(bytes.prefix(count))
        }

        private func setExtendedAttribute(_ value: Data, named name: String, at path: String) throws {
            let result = path.withCString { pathPointer in
                name.withCString { namePointer in
                    value.withUnsafeBytes { bytes in
                        setxattr(pathPointer, namePointer, bytes.baseAddress, bytes.count, 0, 0)
                    }
                }
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }

    /// Fecha de modificación en disco, o `nil` si el archivo ya no existe.
    /// Se lee del sistema de archivos cada vez: los valores de recurso de
    /// `URL` se guardan en caché y no verían los cambios externos. Con un
    /// enlace simbólico cuenta la fecha del archivo al que apunta, que es el
    /// que se lee y se escribe (`attributesOfItem` no sigue el enlace).
    static func modificationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
        return attributes?[.modificationDate] as? Date
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    // MARK: - Marcadores

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Accesos de seguridad abiertos con `resolve`, por ruta normalizada.
    private static let accessLock = NSLock()
    nonisolated(unsafe) private static var openAccesses: [String: URL] = [:]

    /// Resuelve un marcador y abre su acceso (una sola vez por archivo) hasta
    /// `endAccess`. Un marcador caducado no se renueva aquí: abrir el archivo
    /// crea uno nuevo para la sesión y para Abrir reciente.
    static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        let key = normalized(url).path
        accessLock.lock()
        defer { accessLock.unlock() }
        if openAccesses[key] == nil, url.startAccessingSecurityScopedResource() {
            openAccesses[key] = url
        }
        return url
    }

    /// Cierra el acceso que abrió `resolve` para este archivo, si lo hay.
    static func endAccess(to url: URL) {
        let key = normalized(url).path
        accessLock.lock()
        let opened = openAccesses.removeValue(forKey: key)
        accessLock.unlock()
        opened?.stopAccessingSecurityScopedResource()
    }

    static func hasOpenAccess(to url: URL) -> Bool {
        accessLock.lock()
        defer { accessLock.unlock() }
        return openAccesses[normalized(url).path] != nil
    }
}

/// Estado de un archivo abierto frente a su copia en disco.
nonisolated enum LitteraDiskState: Equatable {
    case unchanged
    case modified
    case deleted

    static func compare(known: Date?, current: Date?, fileExists: Bool) -> LitteraDiskState {
        guard fileExists else { return .deleted }
        guard let known, let current else { return .modified }
        return abs(current.timeIntervalSince(known)) > 0.0005 ? .modified : .unchanged
    }
}

/// Documento reciente guardado en Preferencias como marcador de seguridad.
nonisolated struct LitteraRecentDocument: Codable, Equatable, Identifiable {
    let path: String
    let bookmark: Data

    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
}

/// Documentos abiertos al cerrar Littera, para restaurar la sesión.
nonisolated struct LitteraSavedSession: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let path: String
        let bookmark: Data
    }

    var entries: [Entry]
    var activePath: String?
}

nonisolated enum LitteraDocumentPersistence {
    static let recentsKey = "littera.recentDocuments"
    static let sessionKey = "littera.session"
    static let maximumRecents = 10

    static func loadRecents(_ defaults: UserDefaults = .standard) -> [LitteraRecentDocument] {
        guard let data = defaults.data(forKey: recentsKey) else { return [] }
        return (try? JSONDecoder().decode([LitteraRecentDocument].self, from: data)) ?? []
    }

    static func saveRecents(_ recents: [LitteraRecentDocument], _ defaults: UserDefaults = .standard) {
        if recents.isEmpty {
            defaults.removeObject(forKey: recentsKey)
        } else if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: recentsKey)
        }
    }

    /// El más reciente primero, sin duplicados y con un máximo de diez.
    static func adding(
        _ document: LitteraRecentDocument,
        to recents: [LitteraRecentDocument]
    ) -> [LitteraRecentDocument] {
        Array(([document] + recents.filter { $0.path != document.path }).prefix(maximumRecents))
    }

    static func loadSession(_ defaults: UserDefaults = .standard) -> LitteraSavedSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(LitteraSavedSession.self, from: data)
    }

    static func saveSession(_ session: LitteraSavedSession, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: sessionKey)
        }
    }
}
