import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Puntos de entrada de las acciones: barra de menús real, paletas por
/// todas sus rutas de apertura y atajos (revisión de comandos, 2026-11-07).
@MainActor
final class LitteraCommandEntryTests: XCTestCase {
    private var window: NSWindow?
    private let applicationDelegate = LitteraApplicationDelegate()

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found = (view as? T).map { [$0] } ?? []
        for subview in view.subviews { found += views(type, in: subview) }
        return found
    }

    private func host() throws -> (LitteraDocumentStore, NSWindow) {
        let store = LitteraDocumentStore.isolated()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LitteraMainWindow(
            documentStore: store,
            applicationDelegate: applicationDelegate
        ))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        spin(1)
        return (store, window)
    }

    /// Campo de búsqueda de la paleta abierta, si lo hay.
    /// El foco de teclado solo existe en la ventana clave. Si otra app está
    /// al frente, la prueba se omite (no se da por buena).
    private func requireKeyWindow(_ window: NSWindow) throws {
        try XCTSkipUnless(window.isKeyWindow, "La app de pruebas no está al frente: no se puede comprobar el foco de teclado")
    }

    private func paletteField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        return views(NSTextField.self, in: content).first { $0.isEditable }
    }

    private func paletteHasFocus(in window: NSWindow) -> Bool {
        guard let field = paletteField(in: window), let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    private func press(_ keyCode: UInt16, _ characters: String, in window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        window.sendEvent(event)
        spin(0.3)
    }

    // MARK: Paletas: foco, flechas, Intro y Esc desde cada ruta

    /// ⌘K y ⇧⌘O (menú, paleta, título, `···`) publican estas dos
    /// notificaciones; el campo de búsqueda recibe el foco en ambas.
    func testEveryPaletteRouteFocusesTheSearchField() throws {
        let (_, window) = try host()
        try requireKeyWindow(window)
        for route in [Notification.Name.litteraShowPalette, .litteraShowDocuments] {
            NotificationCenter.default.post(name: route, object: nil)
            spin(0.5)
            XCTAssertTrue(paletteHasFocus(in: window), "\(route.rawValue): el campo de búsqueda tiene el foco; clave: \(window.isKeyWindow), activa: \(NSApp.isActive)")
            press(53, "\u{1b}", in: window)
            XCTAssertNil(paletteField(in: window), "\(route.rawValue): Esc cierra la paleta")
        }
    }

    /// El comando «Cambiar de documento abierto» de ⌘K abre la de documentos
    /// con el foco en su campo.
    func testDocumentsCommandFromThePaletteKeepsTheFocus() throws {
        let (_, window) = try host()
        try requireKeyWindow(window)
        NotificationCenter.default.post(name: .litteraShowPalette, object: nil)
        spin(0.5)
        NotificationCenter.default.post(name: .litteraRunCommand, object: "documents.switch")
        spin(0.6)
        XCTAssertTrue(paletteHasFocus(in: window), "clave: \(window.isKeyWindow), activa: \(NSApp.isActive)")
    }

    func testArrowsAndReturnChooseFromTheKeyboard() throws {
        let (store, window) = try host()
        try requireKeyWindow(window)
        store.newDocument(locale: Locale(identifier: "es"))
        spin(0.3)
        let second = store.activeDocumentID
        let first = try XCTUnwrap(store.documents.first { $0.id != second }?.id)

        NotificationCenter.default.post(name: .litteraShowDocuments, object: nil)
        spin(0.5)
        XCTAssertTrue(paletteHasFocus(in: window))
        // Abiertos en orden; ↓ pasa al siguiente e Intro lo activa.
        press(125, String(UnicodeScalar(NSDownArrowFunctionKey)!), in: window)
        press(36, "\r", in: window)
        XCTAssertNil(paletteField(in: window), "Intro elige y cierra la paleta")
        XCTAssertEqual(store.activeDocumentID, first, "↓ + Intro activa el segundo de la lista")
    }

    // MARK: Barra de menús real

    private func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
    }

    func testMenuBarHasNoDuplicatesOrStraySeparators() throws {
        _ = try host()
        let mainMenu = try XCTUnwrap(NSApp.mainMenu)
        // Lo que hace macOS al abrir la barra de menús.
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: mainMenu)
        for top in mainMenu.items {
            guard let menu = top.submenu else { continue }
            menu.update()
            let visible = menu.items.filter { !$0.isHidden }
            XCTAssertFalse(visible.last?.isSeparatorItem ?? false, "\(top.title) termina en separador \(visible.map { $0.isSeparatorItem ? "———" : $0.title })")
            XCTAssertFalse(visible.first?.isSeparatorItem ?? false, "\(top.title) empieza en separador")
            for (a, b) in zip(visible, visible.dropFirst()) {
                XCTAssertFalse(a.isSeparatorItem && b.isSeparatorItem, "\(top.title): dos separadores seguidos")
            }
            let titles = visible.filter { !$0.isSeparatorItem }.map(\.title)
            XCTAssertEqual(Set(titles).count, titles.count, "\(top.title): entradas repetidas \(titles)")
        }
        // Ningún atajo visible asignado a dos entradas.
        let shortcuts = items(mainMenu).filter { !$0.isHidden && !$0.keyEquivalent.isEmpty }
            .map { "\($0.keyEquivalentModifierMask.rawValue)-\($0.keyEquivalent)" }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count, "Atajos repetidos en la barra de menús")
    }

    /// Las entradas de funciones retiradas o inexistentes en v1 no vuelven.
    func testRetiredEntriesAreNotOffered() {
        for key in ["ui.nuevo.texto.plano", "ui.abrir.carpeta"] {
            XCTAssertEqual(L10n.tr(key, locale: Locale(identifier: "es")), key, "\(key) sigue traducida: ¿vuelve a usarse?")
        }
    }

    /// Atajos por defecto: ninguno repetido entre comandos ni reservado del
    /// sistema; ⌘K es la paleta y el enlace es ⇧⌘K (contrato v1).
    func testDefaultShortcutsAreUniqueAndFollowTheContract() {
        let combos = LitteraShortcuts.definitions.compactMap(\.defaultCombo)
        XCTAssertEqual(Set(combos).count, combos.count, "Atajos por defecto repetidos")
        XCTAssertTrue(combos.allSatisfy { !LitteraShortcuts.reserved.contains($0) })
        XCTAssertEqual(LitteraShortcuts.definition("palette")?.defaultCombo, .command("k"))
        XCTAssertEqual(LitteraShortcuts.definition("format.link")?.defaultCombo, .command("k", .shift))
        XCTAssertEqual(LitteraShortcuts.definition("documents.switch")?.defaultCombo, .command("o", .shift))
        // El atajo que muestra la paleta es el mismo que usan los menús.
        for command in LitteraCommandRegistry.all where LitteraShortcuts.definition(command.id) != nil {
            if let fallback = command.shortcut {
                XCTAssertEqual(fallback, LitteraShortcuts.definition(command.id)?.defaultCombo?.display, command.id)
            }
        }
    }

    /// El tooltip del título usa el atajo configurado, no uno escrito a mano.
    func testTitleHelpShowsTheConfiguredShortcut() {
        let help = LitteraDocumentTitle.helpText(locale: Locale(identifier: "es"))
        let display = LitteraShortcuts.shared.display(for: "documents.switch")
        if let display {
            XCTAssertTrue(help.hasSuffix("(\(display))"), help)
        } else {
            XCTAssertFalse(help.contains("("), help)
        }
    }
}
