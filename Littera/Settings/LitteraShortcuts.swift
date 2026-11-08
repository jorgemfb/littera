import AppKit
import Combine
import SwiftUI

/// Combinación de teclas guardable: tecla base (sin Mayúsculas aplicada) y
/// modificadores ⌃ ⌥ ⇧ ⌘.
nonisolated struct LitteraKeyCombo: Codable, Hashable, Sendable {
    /// Carácter base en minúsculas o nombre de tecla especial.
    let key: String
    let modifiers: UInt

    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.allowedModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    // MARK: Teclas especiales

    private static let specialKeys: [UInt16: String] = [
        36: "return", 48: "tab", 49: "space", 51: "delete", 117: "forwardDelete",
        123: "left", 124: "right", 125: "down", 126: "up"
    ]

    /// Combinación pulsada, o `nil` si la tecla no se puede asignar.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.allowedModifiers)
        if let special = Self.specialKeys[event.keyCode] {
            key = special
        } else if let base = event.characters(byApplyingModifiers: [])?.lowercased(),
                  base.count == 1, let scalar = base.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar) {
            key = base
        } else {
            return nil
        }
        modifiers = flags.rawValue
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let other = LitteraKeyCombo(event: event) else { return false }
        return other == self
    }

    /// Requiere ⌘, ⌃ u ⌥: sin modificador, la tecla escribiría texto.
    var hasCommandModifier: Bool {
        !modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    var display: String {
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        switch key {
        case "return": text += "↩"
        case "tab": text += "⇥"
        case "space": text += "␣"
        case "delete": text += "⌫"
        case "forwardDelete": text += "⌦"
        case "left": text += "←"
        case "right": text += "→"
        case "down": text += "↓"
        case "up": text += "↑"
        default: text += key.uppercased()
        }
        return text
    }

    var keyboardShortcut: KeyboardShortcut {
        let equivalent: KeyEquivalent
        switch key {
        case "return": equivalent = .return
        case "tab": equivalent = .tab
        case "space": equivalent = .space
        case "delete": equivalent = .delete
        case "forwardDelete": equivalent = .deleteForward
        case "left": equivalent = .leftArrow
        case "right": equivalent = .rightArrow
        case "down": equivalent = .downArrow
        case "up": equivalent = .upArrow
        default: equivalent = KeyEquivalent(Character(key))
        }
        var eventModifiers: EventModifiers = []
        let flags = modifierFlags
        if flags.contains(.command) { eventModifiers.insert(.command) }
        if flags.contains(.shift) { eventModifiers.insert(.shift) }
        if flags.contains(.option) { eventModifiers.insert(.option) }
        if flags.contains(.control) { eventModifiers.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }

    static func command(_ key: String, _ modifiers: NSEvent.ModifierFlags = []) -> Self {
        Self(key: key, modifiers: modifiers.union(.command))
    }
}

/// Comando con atajo configurable. El `id` coincide con el de la paleta.
nonisolated struct LitteraShortcutDefinition: Identifiable, Sendable {
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case documents = "ui.atajos.documentos"
        case search = "ui.atajos.busqueda"
        case views = "ui.atajos.vistas"
        case format = "ui.atajos.formato"
        case editing = "ui.atajos.edicion"
        var id: String { rawValue }
    }

    let id: String
    let titleKey: String
    let group: Group
    let defaultCombo: LitteraKeyCombo?
}

/// Atajos de Littera: valores por defecto y cambios del usuario, guardados
/// en Preferencias. Los menús, la paleta y el editor los leen de aquí.
@MainActor
final class LitteraShortcuts: ObservableObject {
    static let shared = LitteraShortcuts()

    static let definitions: [LitteraShortcutDefinition] = {
        var list: [LitteraShortcutDefinition] = [
            .init(id: "new", titleKey: "ui.nuevo.documento.markdown", group: .documents, defaultCombo: .command("n")),
            .init(id: "open", titleKey: "ui.abrir.documento", group: .documents, defaultCombo: .command("o")),
            .init(id: "save", titleKey: "ui.guardar.documento", group: .documents, defaultCombo: .command("s")),
            .init(id: "saveAs", titleKey: "ui.guardar.como", group: .documents, defaultCombo: .command("s", .shift)),
            .init(id: "close", titleKey: "ui.cerrar.documento", group: .documents, defaultCombo: .command("w")),
            .init(id: "export.pdf", titleKey: "ui.exportar.como.pdf", group: .documents, defaultCombo: nil),
            .init(id: "export.html", titleKey: "ui.exportar.como.html", group: .documents, defaultCombo: nil),
            .init(id: "palette", titleKey: "ui.paleta.de.comandos", group: .documents, defaultCombo: .command("k")),
            .init(id: "documents.switch", titleKey: "ui.documentos.abiertos", group: .documents, defaultCombo: .command("o", .shift)),
            .init(id: "find", titleKey: "menu.buscar.ellipsis", group: .search, defaultCombo: .command("f")),
            .init(id: "find.replace", titleKey: "menu.buscar.reemplazar", group: .search, defaultCombo: .command("f", .option)),
            .init(id: "find.next", titleKey: "menu.buscar.siguiente", group: .search, defaultCombo: .command("g")),
            .init(id: "find.previous", titleKey: "menu.buscar.anterior", group: .search, defaultCombo: .command("g", .shift)),
            .init(id: "find.selection", titleKey: "menu.buscar.usar.seleccion", group: .search, defaultCombo: .command("e")),
            .init(id: "source", titleKey: "ui.fuente", group: .views, defaultCombo: .command("1")),
            .init(id: "split", titleKey: "ui.dividido", group: .views, defaultCombo: .command("2")),
            .init(id: "preview", titleKey: "ui.vista.previa", group: .views, defaultCombo: .command("3")),
            .init(id: "typewriter", titleKey: "ui.modo.maquina.de.escribir", group: .views, defaultCombo: nil),
        ]
        let formatDefaults: [LitteraFormattingAction: LitteraKeyCombo] = [
            .bold: .command("b"), .italic: .command("i"), .link: .command("k", .shift)
        ]
        list += LitteraFormattingAction.allCases.map { action in
            .init(id: "format.\(action.rawValue)", titleKey: action.label, group: .format, defaultCombo: formatDefaults[action])
        }
        // Edición (D52): ⌥⌘↑/↓ mover, ⌘D duplicar, ⌘↩ tarea, ⇧⌘D fecha.
        let editingDefaults: [LitteraEditingCommand: LitteraKeyCombo] = [
            .moveLinesUp: .command("up", .option), .moveLinesDown: .command("down", .option),
            .duplicateLines: .command("d"), .toggleTask: .command("return"), .insertDate: .command("d", .shift)
        ]
        list += LitteraEditingCommand.allCases.map { command in
            .init(id: command.commandID, titleKey: command.label, group: .editing, defaultCombo: editingDefaults[command])
        }
        return list
    }()

    /// Atajos del sistema que no se pueden reasignar.
    static let reserved: [LitteraKeyCombo] = [
        .command("q"), .command(","), .command("z"), .command("z", .shift), .command("x"), .command("c"),
        .command("v"), .command("a"), .command("h"), .command("h", .option), .command("m"), .command("`")
    ]

    private static let storageKey = "littera.shortcuts.v1"
    /// Cambios del usuario: combinación, o `nil` si quitó el atajo.
    @Published private(set) var overrides: [String: LitteraKeyCombo?]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([String: Stored].self, from: data) {
            overrides = stored.mapValues(\.combo)
        } else {
            overrides = [:]
        }
    }

    private struct Stored: Codable {
        let combo: LitteraKeyCombo?
    }

    static func definition(_ id: String) -> LitteraShortcutDefinition? {
        definitions.first { $0.id == id }
    }

    func combo(for id: String) -> LitteraKeyCombo? {
        if let override = overrides[id] { return override }
        return Self.definition(id)?.defaultCombo
    }

    func keyboardShortcut(for id: String) -> KeyboardShortcut? {
        combo(for: id)?.keyboardShortcut
    }

    func display(for id: String) -> String? {
        combo(for: id)?.display
    }

    func isCustomized(_ id: String) -> Bool {
        overrides[id] != nil
    }

    /// Comando que ya usa la combinación (o "system" si está reservada).
    func conflict(for combo: LitteraKeyCombo, excluding id: String) -> String? {
        if Self.reserved.contains(combo) { return "system" }
        return Self.definitions.first { $0.id != id && self.combo(for: $0.id) == combo }?.id
    }

    enum AssignResult: Equatable {
        case assigned
        case needsModifier
        case conflict(String)
    }

    @discardableResult
    func assign(_ combo: LitteraKeyCombo, to id: String) -> AssignResult {
        guard combo.hasCommandModifier else { return .needsModifier }
        if let other = conflict(for: combo, excluding: id) { return .conflict(other) }
        if combo == Self.definition(id)?.defaultCombo {
            overrides.removeValue(forKey: id)
        } else {
            overrides.updateValue(combo, forKey: id)
        }
        persist()
        return .assigned
    }

    /// Quita el atajo del comando.
    func clear(_ id: String) {
        if Self.definition(id)?.defaultCombo == nil {
            overrides.removeValue(forKey: id)
        } else {
            overrides.updateValue(nil, forKey: id)
        }
        persist()
    }

    func reset(_ id: String) {
        overrides.removeValue(forKey: id)
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    private func persist() {
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(overrides.mapValues(Stored.init)) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Comando de edición asignado a la pulsación, si lo hay.
    func editingCommand(for event: NSEvent) -> LitteraEditingCommand? {
        LitteraEditingCommand.allCases.first { command in
            combo(for: command.commandID)?.matches(event) == true
        }
    }

    /// Acción de formato asignada a la pulsación, si la hay.
    func formatAction(for event: NSEvent) -> LitteraFormattingAction? {
        for action in LitteraFormattingAction.allCases {
            if let combo = combo(for: "format.\(action.rawValue)"), combo.matches(event) { return action }
        }
        return nil
    }
}
