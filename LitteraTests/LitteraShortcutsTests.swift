import AppKit
import XCTest
@testable import Littera

@MainActor
final class LitteraShortcutsTests: XCTestCase {
    private func makeStore() -> (LitteraShortcuts, UserDefaults) {
        let defaults = LitteraTestDefaults.make()
        return (LitteraShortcuts(defaults: defaults), defaults)
    }

    func testDefaultsAndDisplay() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.display(for: "format.bold"), "⌘B")
        XCTAssertEqual(store.display(for: "format.link"), "⇧⌘K")
        XCTAssertEqual(store.display(for: "find.replace"), "⌥⌘F")
        XCTAssertNil(store.combo(for: "format.heading1"))
    }

    func testDefinitionsHaveNoDuplicateDefaults() {
        let combos = LitteraShortcuts.definitions.compactMap(\.defaultCombo)
        XCTAssertEqual(combos.count, Set(combos).count)
        XCTAssertTrue(combos.allSatisfy { !LitteraShortcuts.reserved.contains($0) })
    }

    func testAssignRejectsConflictsReservedAndPlainKeys() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.assign(.command("b"), to: "format.heading1"), .conflict("format.bold"))
        XCTAssertEqual(store.assign(.command("q"), to: "format.heading1"), .conflict("system"))
        XCTAssertEqual(store.assign(LitteraKeyCombo(key: "h", modifiers: [.shift]), to: "format.heading1"), .needsModifier)
        XCTAssertEqual(store.assign(.command("8"), to: "format.heading1"), .assigned)
        XCTAssertEqual(store.display(for: "format.heading1"), "⌘8")
    }

    func testClearResetAndPersistence() {
        let (store, defaults) = makeStore()
        store.clear("format.bold")
        XCTAssertNil(store.combo(for: "format.bold"))
        XCTAssertTrue(store.isCustomized("format.bold"))
        store.assign(.command("9"), to: "format.heading2")

        let reloaded = LitteraShortcuts(defaults: defaults)
        XCTAssertNil(reloaded.combo(for: "format.bold"))
        XCTAssertEqual(reloaded.display(for: "format.heading2"), "⌘9")

        reloaded.reset("format.bold")
        XCTAssertEqual(reloaded.display(for: "format.bold"), "⌘B")
        reloaded.resetAll()
        XCTAssertNil(reloaded.combo(for: "format.heading2"))
        XCTAssertNil(defaults.data(forKey: "littera.shortcuts.v1"))
    }

    func testAssigningDefaultRemovesOverride() {
        let (store, _) = makeStore()
        store.assign(.command("j"), to: "format.bold")
        XCTAssertTrue(store.isCustomized("format.bold"))
        store.assign(.command("b"), to: "format.bold")
        XCTAssertFalse(store.isCustomized("format.bold"))
    }
}
