import Foundation

/// Vigila el archivo de un documento abierto (D50). macOS avisa a los
/// presentadores cuando otro proceso escribe de forma coordinada (iCloud
/// Drive al traer cambios de otro dispositivo, Finder al mover…). Los avisos
/// llegan en una cola propia y se pasan al hilo principal.
nonisolated final class LitteraFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    enum Event: Sendable {
        case changed
        case moved(URL)
        case newVersion
    }

    let documentID: String
    let presentedItemOperationQueue: OperationQueue
    private let lock = NSLock()
    private var url: URL
    private let handler: @Sendable (String, Event) -> Void

    init(documentID: String, url: URL, handler: @escaping @Sendable (String, Event) -> Void) {
        self.documentID = documentID
        self.url = url
        self.handler = handler
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "Littera.FilePresenter"
        presentedItemOperationQueue = queue
        super.init()
    }

    var presentedItemURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return url
    }

    func presentedItemDidChange() {
        handler(documentID, .changed)
    }

    func presentedItemDidMove(to newURL: URL) {
        lock.lock(); url = newURL; lock.unlock()
        handler(documentID, .moved(newURL))
    }

    func presentedItemDidGain(_ version: NSFileVersion) {
        handler(documentID, .newVersion)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
        handler(documentID, .changed)
    }
}
