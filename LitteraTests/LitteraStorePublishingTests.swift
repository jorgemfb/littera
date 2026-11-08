import Combine
import XCTest
@testable import Littera

/// Cada pulsación publica una sola vez: cada aviso del store reevalúa a todos
/// sus observadores (ventana, editor, paleta).
@MainActor
final class LitteraStorePublishingTests: XCTestCase {
    func testOneChangeNotificationPerKeystroke() {
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        var notifications = 0
        let token = store.objectWillChange.sink { notifications += 1 }
        store.updateMarkdown(for: id, text: "a")
        store.updateMarkdown(for: id, text: "ab")
        token.cancel()
        XCTAssertEqual(notifications, 2)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
    }
}

/// H19: un cambio solo de normalización Unicode (NFC ↔ NFD) cuenta como
/// cambio: llega al documento, lo marca sin guardar y se escribe tal cual.
@MainActor
final class LitteraUnicodeNormalizationTests: XCTestCase {
    func testNormalizationOnlyChangeReachesTheDocumentAndDisk() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("NFD-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cafe.md")
        let nfc = "caf\u{E9}"
        let nfd = "cafe\u{301}"
        XCTAssertEqual(nfc, nfd, "Swift los considera iguales")
        try Data(nfc.utf8).write(to: url)

        let store = LitteraDocumentStore.isolated()
        let locale = Locale(identifier: "es_ES")
        XCTAssertTrue(store.openDocument(at: url, locale: locale))
        store.updateMarkdown(for: store.activeDocumentID, text: nfd)
        XCTAssertTrue(store.activeDocument?.markdown.isIdentical(to: nfd) ?? false)
        XCTAssertTrue(store.activeDocument?.isDirty ?? false)
        XCTAssertTrue(store.saveDocument(id: store.activeDocumentID, forceSavePanel: false, locale: locale))
        XCTAssertEqual(try Data(contentsOf: url), Data(nfd.utf8))
    }
}
