import CryptoKit
import Foundation
import os.log

/// Copia de seguridad de un documento con cambios sin guardar (LIT-001).
/// Nunca sustituye al archivo original: solo sirve para ofrecer la
/// recuperación si Littera se cierra de forma inesperada.
nonisolated struct LitteraRecoverySnapshot: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format = LitteraRecoverySnapshot.currentFormat
    /// Identidad del documento en la sesión que creó la copia.
    let documentID: String
    /// Orden de las copias de un mismo documento: una más antigua nunca
    /// sustituye a otra más reciente.
    let revision: UInt64
    let savedAt: Date
    let fileName: String
    /// Archivo original, si el documento tenía uno.
    let filePath: String?
    let bookmark: Data?
    /// Huella del contenido en disco sobre el que se hicieron los cambios:
    /// permite saber si el original cambió fuera de Littera después.
    let baseContentHash: String?
    let markdown: String

    static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Almacén privado de copias de recuperación, en Application Support del
/// contenedor de la app. Escribe en una cola serie propia: el editor nunca
/// espera al disco. No registra el contenido de los documentos en ningún log.
nonisolated final class LitteraRecoveryStore: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.littera", category: "recovery")
    static let fileExtension = "littera-recovery"

    struct Contents {
        var snapshots: [LitteraRecoverySnapshot]
        /// Copias que no se pudieron leer. Se conservan sin tocarlas.
        var unreadable: [URL]
    }

    let directory: URL
    private let queue = DispatchQueue(label: "Littera.Recovery", qos: .utility)
    /// Última revisión escrita o retirada por documento. Solo en `queue`.
    private var lastRevision: [String: UInt64] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Containers/<app>/Data/Library/Application Support/Littera/Recovery`.
    static func standard() -> LitteraRecoveryStore? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return LitteraRecoveryStore(directory: support.appendingPathComponent("Littera/Recovery", isDirectory: true))
    }

    func fileURL(for documentID: String) -> URL {
        directory.appendingPathComponent(documentID).appendingPathExtension(Self.fileExtension)
    }

    func save(_ snapshot: LitteraRecoverySnapshot) {
        queue.async { self.write(snapshot) }
    }

    /// Retira la copia de un documento. `revision` ordena la retirada respecto
    /// a las escrituras pendientes; `.max` la hace definitiva.
    func remove(documentID: String, revision: UInt64 = .max) {
        queue.async {
            guard revision >= self.lastRevision[documentID, default: 0] else { return }
            self.lastRevision[documentID] = revision
            try? FileManager.default.removeItem(at: self.fileURL(for: documentID))
        }
    }

    /// Espera a que terminen las escrituras y retiradas pendientes.
    func flush() {
        queue.sync {}
    }

    func load() -> Contents {
        queue.sync { read() }
    }

    private func write(_ snapshot: LitteraRecoverySnapshot) {
        guard snapshot.revision > lastRevision[snapshot.documentID, default: 0] else { return }
        lastRevision[snapshot.documentID] = snapshot.revision
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = fileURL(for: snapshot.documentID)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Self.log.error("No se pudo escribir la copia de recuperación: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func read() -> Contents {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return Contents(snapshots: [], unreadable: []) }
        var contents = Contents(snapshots: [], unreadable: [])
        for url in urls where url.pathExtension == Self.fileExtension {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(LitteraRecoverySnapshot.self, from: data),
                  snapshot.format <= LitteraRecoverySnapshot.currentFormat,
                  url.deletingPathExtension().lastPathComponent == snapshot.documentID else {
                contents.unreadable.append(url)
                continue
            }
            contents.snapshots.append(snapshot)
        }
        contents.snapshots.sort { $0.savedAt < $1.savedAt }
        contents.unreadable.sort { $0.path < $1.path }
        return contents
    }
}
