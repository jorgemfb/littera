import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

final class LitteraDocumentStore: ObservableObject {
    @Published var documents: [LitteraDocumentSession] {
        didSet {
            scheduleDerivations()
            persistSessionIfNeeded()
            syncFilePresenters()
            syncRecovery()
        }
    }
    @Published var activeDocumentID: String {
        didSet { persistSessionIfNeeded() }
    }
    /// Representación analizada por documento. Se publica porque, tras una
    /// edición, llega de forma asíncrona.
    @Published private(set) var derivedDocuments: [String: LitteraMarkdownDerivedDocument] = [:]
    /// Abrir reciente: el más reciente primero.
    @Published private(set) var recentDocuments: [LitteraRecentDocument]
    @Published private(set) var derivationCount = 0
    /// Una tarea de análisis por documento. El parser de CommonMark no ofrece
    /// puntos de cancelación, así que una tarea ya dentro del parser termina,
    /// pero jamás publica si su instantánea ha quedado obsoleta.
    private var derivationTasks: [String: Task<Void, Never>] = [:]
    /// Espera breve para agrupar una ráfaga de pulsaciones antes de iniciar
    /// un análisis completo. Es ajustable desde pruebas de rendimiento.
    var derivationDebounce: TimeInterval = 0.08
    /// Aun escribiendo sin pausa se inicia un análisis al menos a este ritmo.
    /// La publicación sigue exigiendo que la instantánea sea la más reciente.
    var maximumDerivationWait: TimeInterval = 0.5
    private var pendingDerivations: [String: DispatchWorkItem] = [:]
    private var derivationPendingSince: [String: Date] = [:]

    private let defaults: UserDefaults
    private let prompts: LitteraDocumentPrompts
    private var lastPersistedSession: LitteraSavedSession?
    /// Entradas de la sesión anterior que no se pudieron abrir en este
    /// arranque (permisos, volumen sin montar, descarga de iCloud pendiente).
    /// Se conservan para el siguiente en lugar de borrar la sesión.
    private var unrestoredSessionEntries: [LitteraSavedSession.Entry] = []
    /// Pausa tras la última pulsación antes del guardado automático (D49).
    var autosaveDelay: TimeInterval = 2
    private var pendingAutosaves: [String: DispatchWorkItem] = [:]

    // iCloud Drive (D50)
    private let cloud: LitteraCloudFileService
    private let observesFiles: Bool
    private var presenters: [String: LitteraFilePresenter] = [:]
    /// Archivos de iCloud que se están descargando para abrirlos.
    private var downloadsInFlight: Set<String> = []
    /// Si Littera está en primer plano (las pruebas lo fijan).
    var isApplicationActive: () -> Bool = { NSApp?.isActive ?? true }
    var downloadPollInterval: TimeInterval = 0.5
    var downloadTimeout: TimeInterval = 90

    // Recuperación tras un cierre inesperado (LIT-001)
    private let recovery: LitteraRecoveryStore?
    /// Pausa tras la última edición antes de copiar. Independiente del
    /// guardado automático y del modo Dividido.
    var recoveryDelay: TimeInterval = 3
    /// Escribiendo sin pausa, se copia como mucho cada este intervalo.
    var recoveryMaximumWait: TimeInterval = 15
    private var recoveryRevisions: [String: UInt64] = [:]
    /// Último texto copiado o programado por documento con copia.
    private var recoveryTexts: [String: String] = [:]
    private var pendingRecoveries: [String: DispatchWorkItem] = [:]
    private var recoveryPendingSince: [String: Date] = [:]

    /// Littera restaura los documentos de la sesión anterior (si la
    /// preferencia está activa) y, si no hay ninguno, abre un documento vacío.
    init(
        defaults: UserDefaults = .standard,
        prompts: LitteraDocumentPrompts? = nil,
        restoresSession: Bool? = nil,
        cloud: LitteraCloudFileService? = nil,
        observesFiles: Bool = true,
        recovery: LitteraRecoveryStore? = nil
    ) {
        self.defaults = defaults
        self.recovery = recovery
        self.prompts = prompts ?? LitteraAlertPrompts()
        let cloudService = cloud ?? LitteraSystemCloudFiles()
        self.cloud = cloudService
        self.observesFiles = observesFiles
        recentDocuments = LitteraDocumentPersistence.loadRecents(defaults)

        let shouldRestore = restoresSession
            ?? (defaults.object(forKey: LitteraPreferenceKeys.restoreSession) as? Bool
                ?? LitteraPreferenceDefaults.restoreSession)
        var restored: [LitteraDocumentSession] = []
        var activeID: String?
        var pendingDownloads: [URL] = []
        var unrestored: [LitteraSavedSession.Entry] = []
        if shouldRestore, let session = LitteraDocumentPersistence.loadSession(defaults) {
            for entry in session.entries {
                guard let url = LitteraDocumentFile.resolve(entry.bookmark) else {
                    // Marcador sin resolver: con su carpeta presente, el archivo
                    // se borró; sin ella, puede ser un volumen sin montar.
                    let folder = (entry.path as NSString).deletingLastPathComponent
                    if !FileManager.default.fileExists(atPath: folder) { unrestored.append(entry) }
                    continue
                }
                // En iCloud y no descargado: se abre cuando llegue, sin bloquear el arranque.
                if cloudService.downloadStatus(url) != .available {
                    pendingDownloads.append(url)
                    unrestored.append(entry)
                    continue
                }
                guard let contents = try? LitteraDocumentFile.read(url) else {
                    // Solo se olvida un archivo que ya no existe.
                    if LitteraDocumentFile.exists(url) { unrestored.append(entry) }
                    LitteraDocumentFile.endAccess(to: url)
                    continue
                }
                var document = LitteraDocumentSession.file(at: url, contents: contents)
                if document.bookmark == nil { document.bookmark = entry.bookmark }
                restored.append(document)
                if entry.path == session.activePath { activeID = document.id }
            }
        }
        if restored.isEmpty {
            restored = [LitteraDocumentSession.untitled(locale: Self.interfaceLocale(defaults))]
        }
        documents = restored
        activeDocumentID = activeID ?? restored[0].id
        unrestoredSessionEntries = unrestored
        scheduleDerivations()
        persistSessionIfNeeded()
        syncFilePresenters()
        if !pendingDownloads.isEmpty {
            let locale = Self.interfaceLocale(defaults)
            DispatchQueue.main.async { [weak self] in
                for url in pendingDownloads { self?.openAfterDownload(url, locale: locale) }
            }
        }
    }

    private static func interfaceLocale(_ defaults: UserDefaults) -> Locale {
        let language = defaults.string(forKey: LitteraLanguage.settingKey) ?? LitteraLanguage.fallback
        return LitteraLanguage.locale(for: language)
    }

    /// Mantiene como máximo una derivación en curso por documento. Cuando
    /// termina, se procesa el texto más reciente si ha seguido cambiando.
    private func scheduleDerivations() {
        let liveIDs = Set(documents.map(\.id))
        if derivedDocuments.keys.contains(where: { !liveIDs.contains($0) }) {
            derivedDocuments = derivedDocuments.filter { liveIDs.contains($0.key) }
        }
        for id in derivationTasks.keys where !liveIDs.contains(id) {
            derivationTasks.removeValue(forKey: id)?.cancel()
        }
        for id in pendingDerivations.keys where !liveIDs.contains(id) {
            pendingDerivations.removeValue(forKey: id)?.cancel()
        }
        if derivationPendingSince.keys.contains(where: { !liveIDs.contains($0) }) {
            derivationPendingSince = derivationPendingSince.filter { liveIDs.contains($0.key) }
        }

        for document in documents {
            let previous = derivedDocuments[document.id]
            guard !(previous?.source.isIdentical(to: document.markdown) ?? false) else {
                pendingDerivations.removeValue(forKey: document.id)?.cancel()
                derivationPendingSince.removeValue(forKey: document.id)
                continue
            }
            // No iniciar análisis concurrentes para el mismo documento.
            if derivationTasks[document.id] != nil { continue }
            scheduleDerivation(for: document, previous: previous)
        }
    }

    private func scheduleDerivation(
        for document: LitteraDocumentSession,
        previous: LitteraMarkdownDerivedDocument?
    ) {
        let documentID = document.id
        pendingDerivations.removeValue(forKey: documentID)?.cancel()
        let source = document.markdown
        let revision = (previous?.revision ?? 0) + 1
        // El documento inicial debe iniciar su análisis enseguida, como antes
        // del debounce, para que las rutas de apertura no esperen un turno de
        // la cola principal solo para obtener la primera vista útil.
        guard previous != nil else {
            startDerivation(documentID: documentID, source: source, revision: revision)
            return
        }
        let pendingSince = derivationPendingSince[documentID] ?? Date()
        derivationPendingSince[documentID] = pendingSince
        let elapsed = Date().timeIntervalSince(pendingSince)
        let delay = max(0, min(derivationDebounce, maximumDerivationWait - elapsed))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDerivations.removeValue(forKey: documentID)
            self.derivationPendingSince.removeValue(forKey: documentID)
            // El documento puede haberse cerrado o haberse actualizado entre
            // la programación y este turno del hilo principal.
            guard self.documents.first(where: { $0.id == documentID })?.markdown.isIdentical(to: source) == true,
                  self.derivationTasks[documentID] == nil else {
                self.scheduleDerivations()
                return
            }
            self.startDerivation(documentID: documentID, source: source, revision: revision)
        }
        pendingDerivations[documentID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startDerivation(documentID: String, source: String, revision: UInt64) {
        derivationTasks[documentID] = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            let derived = LitteraMarkdownDerivedDocument(source: source, revision: revision)
            guard !Task.isCancelled else { return }
            await self?.finishDerivation(derived, for: documentID)
        }
    }

    private func finishDerivation(_ derived: LitteraMarkdownDerivedDocument, for documentID: String) {
        derivationTasks.removeValue(forKey: documentID)
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        // Una vista previa que enseñe una instantánea antigua deja de ser una
        // vista previa fiable. El resultado queda descartado y se programa el
        // último texto, incluso si ya pasó el intervalo de agrupación.
        guard document.markdown.isIdentical(to: derived.source) else {
            scheduleDerivations()
            return
        }
        derivedDocuments[documentID] = derived
        derivationCount += 1
        scheduleDerivations()
    }

    var activeDocument: LitteraDocumentSession? {
        documents.first(where: { $0.id == activeDocumentID })
    }

    func updateMarkdown(for documentID: String, text: String) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        guard !documents[index].markdown.isIdentical(to: text) else { return }
        // Una sola asignación: cada cambio del array publica y avisa a todos
        // los observadores, y esto ocurre en cada pulsación.
        var document = documents[index]
        document.markdown = text
        document.isDirty = !text.isIdentical(to: document.savedMarkdown) || document.isMissingOnDisk
        documents[index] = document
        scheduleAutosave(for: documentID)
    }

    func discardChanges(for documentID: String) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        documents[index].markdown = documents[index].savedMarkdown
        documents[index].isDirty = false
    }

    // MARK: - Nuevo, abrir y cerrar

    func newDocument(locale: Locale) {
        let document = LitteraDocumentSession.untitled(locale: locale)
        documents.append(document)
        activeDocumentID = document.id
    }

    /// Abre un `.md` o activa su documento si ya estaba abierto. Un documento
    /// vacío y sin tocar se sustituye por el archivo abierto.
    @discardableResult
    func openDocument(at url: URL, locale: Locale) -> Bool {
        let normalizedURL = LitteraDocumentFile.normalized(url)
        if let existing = documents.first(where: {
            $0.fileURL.map(LitteraDocumentFile.normalized) == normalizedURL
        }) {
            activeDocumentID = existing.id
            return true
        }

        // En iCloud Drive pero no en este Mac: se descarga y se abre al llegar.
        if cloud.downloadStatus(url) != .available {
            openAfterDownload(url, locale: locale)
            return true
        }

        let contents: LitteraDocumentFile.Contents
        do {
            contents = try LitteraDocumentFile.read(url)
        } catch LitteraDocumentFile.ReadError.notUTF8 {
            prompts.showError(titleKey: "ui.error.al.abrir", detail: L10n.tr("ui.error.archivo.utf8", locale: locale), locale: locale)
            return false
        } catch {
            prompts.showError(titleKey: "ui.error.al.abrir", detail: error.localizedDescription, locale: locale)
            return false
        }

        let document = LitteraDocumentSession.file(at: url, contents: contents)
        if let index = documents.firstIndex(where: { $0.id == activeDocumentID }),
           documents[index].isPristineUntitled {
            documents[index] = document
        } else {
            documents.append(document)
        }
        activeDocumentID = document.id
        noteRecent(url: url, bookmark: document.bookmark)
        checkConflicts(documentID: document.id, locale: locale)
        return true
    }

    /// Cierra un documento, preguntando antes si tiene cambios. Si no queda
    /// ninguno, Littera muestra un documento vacío (D31).
    @discardableResult
    func closeDocument(id documentID: String, locale: Locale) -> Bool {
        guard let document = documents.first(where: { $0.id == documentID }) else { return false }
        if document.isDirty, !autosave(documentID: documentID) {
            switch prompts.unsavedChanges(fileName: document.fileName, locale: locale) {
            case .save:
                guard saveDocument(id: documentID, forceSavePanel: false, locale: locale) else { return false }
            case .discard:
                break
            case .cancel:
                return false
            }
        }
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return false }

        var remaining = documents
        remaining.remove(at: index)
        if remaining.isEmpty {
            remaining = [LitteraDocumentSession.untitled(locale: locale)]
        }
        if activeDocumentID == documentID || !remaining.contains(where: { $0.id == activeDocumentID }) {
            activeDocumentID = remaining[min(index, remaining.count - 1)].id
        }
        documents = remaining
        if let url = document.fileURL.map(LitteraDocumentFile.normalized),
           !remaining.contains(where: { $0.fileURL.map(LitteraDocumentFile.normalized) == url }) {
            LitteraDocumentFile.endAccess(to: url)
        }
        return true
    }

    // MARK: - Guardar

    func saveDocument(
        id documentID: String,
        forceSavePanel: Bool,
        locale: Locale
    ) -> Bool {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return false }

        let destination: URL
        var verifyDate: Date?
        if !forceSavePanel, let fileURL = documents[index].fileURL {
            destination = fileURL
            // Nunca sobrescribir en silencio un archivo cambiado fuera de Littera.
            let state = LitteraDiskState.compare(
                known: documents[index].diskModificationDate,
                current: LitteraDocumentFile.modificationDate(of: fileURL),
                fileExists: LitteraDocumentFile.exists(fileURL)
            )
            switch state {
            case .modified:
                if !prompts.confirmOverwrite(fileName: documents[index].fileName, locale: locale) {
                    return false
                }
            case .deleted:
                // Guardar a mano un archivo borrado fuera lo vuelve a crear (D37);
                // el guardado automático nunca llega aquí.
                break
            case .unchanged:
                verifyDate = documents[index].diskModificationDate
            }
        } else {
            let panel = NSSavePanel()
            panel.title = L10n.tr(forceSavePanel ? "ui.guardar.como" : "ui.guardar.documento", locale: locale)
            panel.nameFieldStringValue = documents[index].fileURL?.lastPathComponent ?? documents[index].fileName
            panel.allowedContentTypes = [.markdown]
            panel.isExtensionHidden = false
            panel.canCreateDirectories = true
            if let folder = documents[index].fileURL?.deletingLastPathComponent() ?? LitteraDefaultFolder.url(defaults) {
                panel.directoryURL = folder
            }

            guard panel.runModal() == .OK, let selectedURL = panel.url else { return false }
            destination = selectedURL.pathExtension.isEmpty ? selectedURL.appendingPathExtension("md") : selectedURL
        }

        let normalizedDestination = LitteraDocumentFile.normalized(destination)
        if documents.contains(where: {
            $0.id != documentID && $0.fileURL.map(LitteraDocumentFile.normalized) == normalizedDestination
        }) {
            prompts.showError(titleKey: "ui.error.al.guardar", detail: L10n.tr("ui.error.documento.abierto", locale: locale), locale: locale)
            return false
        }

        do {
            try write(documentAt: index, to: destination, verifyDate: verifyDate)
        } catch LitteraDocumentFile.WriteError.readOnly {
            prompts.showError(
                titleKey: "ui.error.al.guardar",
                detail: L10n.formatted("ui.error.archivo.solo.lectura", locale: locale, destination.lastPathComponent),
                locale: locale
            )
            return false
        } catch LitteraDocumentFile.WriteConflictError.externallyModified {
            prompts.showError(
                titleKey: "ui.error.al.guardar",
                detail: L10n.tr("ui.error.archivo.cambiado.al.guardar", locale: locale),
                locale: locale
            )
            return false
        } catch {
            prompts.showError(titleKey: "ui.error.al.guardar", detail: error.localizedDescription, locale: locale)
            return false
        }
        return true
    }

    /// Escribe el documento de forma atómica y actualiza su estado. La usan el
    /// guardado manual y el automático. Cuando `verifyDate` no es `nil`, la
    /// fecha en disco se comprueba dentro del bloque de coordinación y se
    /// rechaza la escritura si el archivo cambió desde esa fecha.
    private func write(documentAt index: Int, to destination: URL, verifyDate: Date? = nil) throws {
        let normalizedDestination = LitteraDocumentFile.normalized(destination)
        if let verifyDate {
            try LitteraDocumentFile.writeVerified(
                documents[index].markdown,
                to: destination,
                knownDate: verifyDate,
                byteOrderMark: documents[index].hasByteOrderMark,
                presenter: presenters[documents[index].id]
            )
        } else {
            try LitteraDocumentFile.write(
                documents[index].markdown,
                to: destination,
                byteOrderMark: documents[index].hasByteOrderMark,
                presenter: presenters[documents[index].id]
            )
        }
        pendingAutosaves.removeValue(forKey: documents[index].id)?.cancel()

        var document = documents[index]
        if document.fileURL.map(LitteraDocumentFile.normalized) != normalizedDestination || document.bookmark == nil {
            document.bookmark = LitteraDocumentFile.bookmark(for: destination)
        }
        document.fileURL = destination
        document.fileName = destination.lastPathComponent
        document.folderDescription = destination.deletingLastPathComponent().path
        document.savedMarkdown = document.markdown
        document.isDirty = false
        document.isMissingOnDisk = false
        document.diskModificationDate = LitteraDocumentFile.modificationDate(of: destination)
        documents[index] = document
        noteRecent(url: destination, bookmark: document.bookmark)
    }

    // MARK: - Guardado automático (D49)

    var autosaveEnabled: Bool {
        defaults.object(forKey: LitteraPreferenceKeys.autosave) as? Bool ?? LitteraPreferenceDefaults.autosave
    }

    /// Programa el guardado automático tras una pausa al escribir. Solo para
    /// documentos que ya tienen archivo: los nuevos se guardan la primera vez
    /// con Guardar, que pide la ubicación.
    private func scheduleAutosave(for documentID: String) {
        pendingAutosaves.removeValue(forKey: documentID)?.cancel()
        guard autosaveEnabled,
              let document = documents.first(where: { $0.id == documentID }),
              document.isDirty, document.fileURL != nil, !document.isMissingOnDisk else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.autosave(documentID: documentID)
        }
        pendingAutosaves[documentID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: work)
    }

    /// Guarda sin preguntar si la opción está activa. No escribe si el archivo
    /// desapareció o cambió fuera de Littera: eso lo resuelven la comprobación
    /// al volver a la app y Guardar, que preguntan. Devuelve `true` si guardó.
    @discardableResult
    func autosave(documentID: String) -> Bool {
        pendingAutosaves.removeValue(forKey: documentID)?.cancel()
        guard autosaveEnabled,
              let index = documents.firstIndex(where: { $0.id == documentID }),
              documents[index].isDirty,
              let url = documents[index].fileURL,
              !documents[index].isMissingOnDisk else { return false }
        let state = LitteraDiskState.compare(
            known: documents[index].diskModificationDate,
            current: LitteraDocumentFile.modificationDate(of: url),
            fileExists: LitteraDocumentFile.exists(url)
        )
        guard state == .unchanged else { return false }
        do {
            try write(documentAt: index, to: url, verifyDate: documents[index].diskModificationDate)
            return true
        } catch {
            // Sin alertas repetidas: el documento sigue marcado como no guardado
            // y Guardar mostrará el error.
            return false
        }
    }

    /// Al activar la opción, guarda lo que ya tenía cambios.
    func autosaveDirtyDocuments() {
        for documentID in documents.filter(\.isDirty).map(\.id) {
            autosave(documentID: documentID)
        }
    }

    /// Al salir de la app no se espera a la pausa.
    func flushPendingAutosaves() {
        for documentID in Array(pendingAutosaves.keys) {
            autosave(documentID: documentID)
        }
    }

    /// «No guardar» solo se aplica cuando el usuario ha contestado por todos
    /// los documentos sin cancelar: cancelar en el segundo no puede costarle
    /// las ediciones del primero.
    func protectUnsavedDocuments(locale: Locale) -> Bool {
        let dirtyDocumentIDs = documents.filter(\.isDirty).map(\.id)
        var discarded: [String] = []

        for documentID in dirtyDocumentIDs {
            if autosave(documentID: documentID) { continue }
            guard let document = documents.first(where: { $0.id == documentID }) else { continue }
            switch prompts.unsavedChanges(fileName: document.fileName, locale: locale) {
            case .save:
                guard saveDocument(id: documentID, forceSavePanel: false, locale: locale) else { return false }
            case .discard:
                discarded.append(documentID)
            case .cancel:
                return false
            }
        }

        for documentID in discarded {
            discardChanges(for: documentID)
        }
        return true
    }

    // MARK: - Cambios hechos fuera de Littera

    /// Compara cada archivo abierto con su copia en disco. Sin cambios locales
    /// se recarga en silencio; con cambios locales se pregunta.
    /// `interactive: false` (avisos en vivo de iCloud o de otras apps) solo
    /// recarga en silencio; si hay que preguntar, se deja para cuando el
    /// usuario vuelva a Littera.
    func checkExternalChanges(locale: Locale, interactive: Bool = true) {
        for document in documents {
            guard let url = document.fileURL,
                  let index = documents.firstIndex(where: { $0.id == document.id }) else { continue }
            let exists = LitteraDocumentFile.exists(url)
            let state = LitteraDiskState.compare(
                known: document.diskModificationDate,
                current: LitteraDocumentFile.modificationDate(of: url),
                fileExists: exists
            )

            if state == .deleted {
                guard !document.isMissingOnDisk else { continue }
                documents[index].isMissingOnDisk = true
                documents[index].isDirty = true
                continue
            }
            guard state == .modified || document.isMissingOnDisk,
                  let contents = try? LitteraDocumentFile.read(url, presenter: presenters[document.id]) else { continue }

            if contents.markdown.isIdentical(to: document.markdown) {
                documents[index].savedMarkdown = contents.markdown
                documents[index].isDirty = false
            } else if !document.isDirty {
                documents[index].markdown = contents.markdown
                documents[index].savedMarkdown = contents.markdown
            } else if contents.markdown.isIdentical(to: document.savedMarkdown) {
                // El disco tiene lo último guardado: conservar la edición en curso.
                documents[index].isDirty = !document.markdown.isIdentical(to: contents.markdown)
            } else {
                guard interactive else { continue }
                switch prompts.externalChange(fileName: document.fileName, locale: locale) {
                case .reload:
                    documents[index].markdown = contents.markdown
                    documents[index].savedMarkdown = contents.markdown
                    documents[index].isDirty = false
                case .keepMine:
                    documents[index].savedMarkdown = contents.markdown
                    documents[index].isDirty = true
                }
            }
            documents[index].isMissingOnDisk = false
            documents[index].diskModificationDate = contents.modificationDate
            documents[index].hasByteOrderMark = contents.hasByteOrderMark
        }
    }

    // MARK: - iCloud Drive (D50)

    /// Pide a iCloud el archivo y lo abre cuando esté en este Mac. Sin
    /// conexión o si iCloud informa de un error, se avisa.
    private func openAfterDownload(_ url: URL, locale: Locale) {
        let key = LitteraDocumentFile.normalized(url).path
        guard !downloadsInFlight.contains(key) else { return }
        do {
            try cloud.startDownloading(url)
        } catch {
            reportDownloadFailure(url, locale: locale)
            return
        }
        downloadsInFlight.insert(key)
        pollDownload(url, key: key, deadline: Date().addingTimeInterval(downloadTimeout), locale: locale)
    }

    private func pollDownload(_ url: URL, key: String, deadline: Date, locale: Locale) {
        DispatchQueue.main.asyncAfter(deadline: .now() + downloadPollInterval) { [weak self] in
            guard let self else { return }
            switch self.cloud.downloadStatus(url) {
            case .available:
                self.downloadsInFlight.remove(key)
                self.openDocument(at: url, locale: locale)
            case .failed:
                self.downloadsInFlight.remove(key)
                self.reportDownloadFailure(url, locale: locale)
            case .needsDownload:
                if Date() >= deadline {
                    self.downloadsInFlight.remove(key)
                    self.reportDownloadFailure(url, locale: locale)
                } else {
                    self.pollDownload(url, key: key, deadline: deadline, locale: locale)
                }
            }
        }
    }

    private func reportDownloadFailure(_ url: URL, locale: Locale) {
        prompts.showError(
            titleKey: "ui.error.icloud",
            detail: L10n.formatted("ui.error.icloud.descarga", locale: locale, url.lastPathComponent),
            locale: locale
        )
    }

    /// Conflictos de todos los documentos de iCloud Drive abiertos.
    func checkConflicts(locale: Locale) {
        for documentID in documents.map(\.id) {
            checkConflicts(documentID: documentID, locale: locale)
        }
    }

    /// Si otro dispositivo guardó el mismo archivo a la vez, se pregunta qué
    /// conservar. Nada se pierde sin que el usuario lo elija: «Conservar
    /// ambas» abre la otra versión como documento nuevo sin guardar.
    func checkConflicts(documentID: String, locale: Locale) {
        guard let document = documents.first(where: { $0.id == documentID }),
              let url = document.fileURL, cloud.isInICloud(url) else { return }
        let versions = cloud.conflicts(at: url)
        guard let newest = versions.max(by: {
            ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast)
        }) else { return }

        let choice = prompts.conflict(
            fileName: document.fileName,
            deviceName: newest.deviceName,
            date: newest.modificationDate,
            locale: locale
        )
        do {
            switch choice {
            case .keepBoth:
                // Leer todas antes de resolver: si alguna falla, no se toca nada.
                let others = try versions.map { version in
                    (version, try cloud.contents(of: version, at: url))
                }
                try cloud.resolveConflicts(at: url, using: nil)
                let baseName = (document.fileName as NSString).deletingPathExtension
                for (version, text) in others {
                    var copy = LitteraDocumentSession.untitled(locale: locale)
                    copy.fileName = L10n.formatted(
                        "ui.conflicto.copia",
                        locale: locale,
                        baseName,
                        version.deviceName ?? L10n.tr("ui.otro.dispositivo", locale: locale)
                    )
                    copy.markdown = text
                    copy.isDirty = true
                    documents.append(copy)
                }
            case .keepMine:
                try cloud.resolveConflicts(at: url, using: nil)
            case .useOther:
                try cloud.resolveConflicts(at: url, using: newest)
                let contents = try LitteraDocumentFile.read(url, presenter: presenters[documentID])
                guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
                documents[index].markdown = contents.markdown
                documents[index].savedMarkdown = contents.markdown
                documents[index].isDirty = false
                documents[index].isMissingOnDisk = false
                documents[index].diskModificationDate = contents.modificationDate
                documents[index].hasByteOrderMark = contents.hasByteOrderMark
            }
        } catch {
            prompts.showError(
                titleKey: "ui.error.icloud",
                detail: L10n.formatted("ui.error.icloud.conflicto", locale: locale, document.fileName),
                locale: locale
            )
        }
    }

    /// Un presentador por documento con archivo; se registran y retiran al
    /// abrir, cerrar, guardar como o mover.
    private func syncFilePresenters() {
        guard observesFiles else { return }
        var wanted: [String: URL] = [:]
        for document in documents {
            if let url = document.fileURL, !document.isMissingOnDisk { wanted[document.id] = url }
        }
        for (documentID, presenter) in presenters {
            let current = presenter.presentedItemURL.map(LitteraDocumentFile.normalized)
            if wanted[documentID].map(LitteraDocumentFile.normalized) != current {
                NSFileCoordinator.removeFilePresenter(presenter)
                presenters[documentID] = nil
            }
        }
        for (documentID, url) in wanted where presenters[documentID] == nil {
            let presenter = LitteraFilePresenter(documentID: documentID, url: url) { [weak self] id, event in
                DispatchQueue.main.async { self?.handlePresenterEvent(id, event) }
            }
            presenters[documentID] = presenter
            NSFileCoordinator.addFilePresenter(presenter)
        }
    }

    func handlePresenterEvent(_ documentID: String, _ event: LitteraFilePresenter.Event) {
        let locale = Self.interfaceLocale(defaults)
        switch event {
        case .changed:
            checkExternalChanges(locale: locale, interactive: false)
        case let .moved(url):
            guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
            // Llevarlo a la Papelera es borrarlo: el texto queda sin guardar y
            // Guardar lo vuelve a crear en su sitio, nunca dentro de la Papelera.
            if Self.isInTrash(url) {
                documents[index].isMissingOnDisk = true
                documents[index].isDirty = true
                return
            }
            documents[index].fileURL = url
            documents[index].fileName = url.lastPathComponent
            documents[index].folderDescription = url.deletingLastPathComponent().path
            documents[index].bookmark = LitteraDocumentFile.bookmark(for: url) ?? documents[index].bookmark
        case .newVersion:
            // Las preguntas esperan a que el usuario vuelva a Littera (D50):
            // al activarse la app se revisan los conflictos de todos.
            guard isApplicationActive() else { return }
            checkConflicts(documentID: documentID, locale: locale)
        }
    }

    /// Papelera del usuario, de un volumen externo (`.Trashes`) o de iCloud Drive.
    static func isInTrash(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.contains(".Trash") || components.contains(".Trashes") { return true }
        guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false) else {
            return false
        }
        return url.standardizedFileURL.path.hasPrefix(trash.standardizedFileURL.path + "/")
    }

    /// Retira los presentadores (pruebas; la app los mantiene mientras vive).
    func stopObservingFiles() {
        for presenter in presenters.values { NSFileCoordinator.removeFilePresenter(presenter) }
        presenters = [:]
    }

    // MARK: - Recuperación (LIT-001)

    private func nextRecoveryRevision(for documentID: String) -> UInt64 {
        let revision = recoveryRevisions[documentID, default: 0] + 1
        recoveryRevisions[documentID] = revision
        return revision
    }

    /// Mantiene una copia privada de cada documento con cambios sin guardar.
    /// La copia se retira cuando el documento queda guardado, cuando el
    /// usuario descarta sus cambios o cuando lo cierra tras decidirlo.
    private func syncRecovery() {
        guard let recovery else { return }
        for documentID in Array(recoveryTexts.keys)
        where !documents.contains(where: { $0.id == documentID && $0.isDirty }) {
            pendingRecoveries.removeValue(forKey: documentID)?.cancel()
            recoveryPendingSince[documentID] = nil
            recoveryTexts[documentID] = nil
            recovery.remove(documentID: documentID, revision: nextRecoveryRevision(for: documentID))
        }
        for document in documents where document.isDirty && recoveryTexts[document.id] != document.markdown {
            scheduleRecovery(for: document.id, markdown: document.markdown)
        }
    }

    private func scheduleRecovery(for documentID: String, markdown: String) {
        pendingRecoveries.removeValue(forKey: documentID)?.cancel()
        recoveryTexts[documentID] = markdown
        let since = recoveryPendingSince[documentID] ?? Date()
        recoveryPendingSince[documentID] = since
        let delay = max(0, min(recoveryDelay, recoveryMaximumWait - Date().timeIntervalSince(since)))
        let work = DispatchWorkItem { [weak self] in
            self?.writeRecovery(for: documentID)
        }
        pendingRecoveries[documentID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func writeRecovery(for documentID: String) {
        pendingRecoveries.removeValue(forKey: documentID)?.cancel()
        recoveryPendingSince[documentID] = nil
        guard let recovery,
              let document = documents.first(where: { $0.id == documentID }),
              document.isDirty else { return }
        recoveryTexts[documentID] = document.markdown
        recovery.save(LitteraRecoverySnapshot(
            documentID: documentID,
            revision: nextRecoveryRevision(for: documentID),
            savedAt: Date(),
            fileName: document.fileName,
            filePath: document.fileURL?.path,
            bookmark: document.bookmark,
            baseContentHash: document.fileURL == nil ? nil : LitteraRecoverySnapshot.contentHash(document.savedMarkdown),
            markdown: document.markdown
        ))
    }

    /// Escribe ya las copias pendientes y espera al disco (salida de la app y
    /// pruebas).
    func flushRecovery() {
        for documentID in Array(pendingRecoveries.keys) {
            writeRecovery(for: documentID)
        }
        recovery?.flush()
    }

    /// Al arrancar: si quedaron copias de una sesión que terminó sin guardar,
    /// pregunta si recuperarlas, descartarlas o decidirlo más tarde. Nunca
    /// escribe en el archivo original.
    func offerRecovery(locale: Locale) {
        guard let recovery else { return }
        var candidates: [LitteraRecoverySnapshot] = []
        for snapshot in recovery.load().snapshots
        where recoveryTexts[snapshot.documentID] == nil && !documents.contains(where: { $0.id == snapshot.documentID }) {
            if let url = recoveryURL(for: snapshot),
               let disk = try? LitteraDocumentFile.read(url),
               disk.markdown == snapshot.markdown {
                // Lo que había que recuperar ya está guardado en el archivo.
                recovery.remove(documentID: snapshot.documentID)
                continue
            }
            candidates.append(snapshot)
        }
        guard !candidates.isEmpty else { return }
        switch prompts.recovery(fileNames: candidates.map(\.fileName), locale: locale) {
        case .later:
            return
        case .discard:
            for snapshot in candidates { recovery.remove(documentID: snapshot.documentID) }
        case .recover:
            restore(candidates, locale: locale)
        }
    }

    private func recoveryURL(for snapshot: LitteraRecoverySnapshot) -> URL? {
        if let bookmark = snapshot.bookmark, let url = LitteraDocumentFile.resolve(bookmark) { return url }
        return snapshot.filePath.map { URL(fileURLWithPath: $0) }
    }

    /// Abre las copias como documentos con cambios sin guardar. Si el
    /// original no cambió desde la copia, se recupera sobre él (sin guardar);
    /// si cambió, desapareció o está abierto con otros cambios, se conservan
    /// ambos: el original tal cual y la copia como documento aparte.
    private func restore(_ snapshots: [LitteraRecoverySnapshot], locale: Locale) {
        var updated = documents
        if updated.count == 1, updated[0].isPristineUntitled { updated.removeAll() }
        var lastID: String?

        func indexOfFile(_ url: URL) -> Int? {
            let normalized = LitteraDocumentFile.normalized(url)
            return updated.firstIndex { $0.fileURL.map(LitteraDocumentFile.normalized) == normalized }
        }

        for snapshot in snapshots {
            let url = recoveryURL(for: snapshot)
            let disk = url.flatMap { try? LitteraDocumentFile.read($0) }
            if let url, let disk {
                let unchanged = snapshot.baseContentHash == LitteraRecoverySnapshot.contentHash(disk.markdown)
                if let index = indexOfFile(url) {
                    if unchanged, !updated[index].isDirty {
                        updated[index].markdown = snapshot.markdown
                        updated[index].isDirty = true
                        lastID = updated[index].id
                        continue
                    }
                } else {
                    var original = LitteraDocumentSession.file(at: url, contents: disk)
                    if unchanged {
                        original.markdown = snapshot.markdown
                        original.isDirty = true
                        updated.append(original)
                        lastID = original.id
                        continue
                    }
                    updated.append(original)
                }
            }
            var copy = LitteraDocumentSession.untitled(locale: locale)
            if snapshot.filePath != nil {
                let baseName = (snapshot.fileName as NSString).deletingPathExtension
                copy.fileName = L10n.formatted("ui.recuperacion.copia", locale: locale, baseName)
            } else {
                copy.fileName = snapshot.fileName
            }
            copy.markdown = snapshot.markdown
            copy.isDirty = true
            updated.append(copy)
            lastID = copy.id
        }

        documents = updated
        if let lastID { activeDocumentID = lastID }
        // Primero las copias nuevas y después la retirada de las antiguas: la
        // cola es serie, así que nunca falta una copia válida.
        flushRecovery()
        for snapshot in snapshots { recovery?.remove(documentID: snapshot.documentID) }
        recovery?.flush()
    }

    // MARK: - Recientes

    func openRecent(_ recent: LitteraRecentDocument, locale: Locale) {
        let resolved = LitteraDocumentFile.resolve(recent.bookmark)
        guard let url = resolved, LitteraDocumentFile.exists(url) else {
            if let resolved { LitteraDocumentFile.endAccess(to: resolved) }
            recentDocuments.removeAll { $0.path == recent.path }
            LitteraDocumentPersistence.saveRecents(recentDocuments, defaults)
            prompts.showError(
                titleKey: "ui.error.al.abrir",
                detail: L10n.formatted("ui.reciente.no.disponible", locale: locale, recent.fileName),
                locale: locale
            )
            return
        }
        openDocument(at: url, locale: locale)
    }

    func clearRecentDocuments() {
        recentDocuments = []
        LitteraDocumentPersistence.saveRecents([], defaults)
    }

    private func noteRecent(url: URL, bookmark: Data?) {
        guard let bookmark else { return }
        recentDocuments = LitteraDocumentPersistence.adding(
            LitteraRecentDocument(path: url.path, bookmark: bookmark),
            to: recentDocuments
        )
        LitteraDocumentPersistence.saveRecents(recentDocuments, defaults)
    }

    // MARK: - Sesión

    /// Guarda qué archivos están abiertos solo cuando cambia la lista o el
    /// documento activo, no a cada pulsación.
    private func persistSessionIfNeeded() {
        let entries = documents.compactMap { document -> LitteraSavedSession.Entry? in
            guard let url = document.fileURL, let bookmark = document.bookmark else { return nil }
            return .init(path: url.path, bookmark: bookmark)
        }
        let openPaths = Set(entries.map(\.path))
        let session = LitteraSavedSession(
            entries: entries + unrestoredSessionEntries.filter { !openPaths.contains($0.path) },
            activePath: documents.first(where: { $0.id == activeDocumentID })?.fileURL?.path
        )
        guard session != lastPersistedSession else { return }
        lastPersistedSession = session
        LitteraDocumentPersistence.saveSession(session, defaults)
    }
}
