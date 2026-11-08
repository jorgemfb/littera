import AppKit
import SwiftUI

struct LitteraKeyboardSettingsView: View {
    @ObservedObject private var shortcuts = LitteraShortcuts.shared
    @Environment(\.locale) private var locale
    /// Comando cuyo atajo se está grabando.
    @State private var recordingID: String?
    @State private var message: (id: String, text: String)?

    var body: some View {
        Form {
            ForEach(LitteraShortcutDefinition.Group.allCases) { group in
                Section(tr(group.rawValue)) {
                    ForEach(LitteraShortcuts.definitions.filter { $0.group == group }) { definition in
                        row(definition)
                    }
                }
            }

            Section(tr("ui.dentro.de.las.paletas")) {
                fixed("ui.mover.seleccion", "↑ ↓")
                fixed("ui.seleccionar", "↩")
                fixed("ui.cerrar", "Esc")
                fixed("ui.preferencias", "⌘,")
            }

            Section {
                HStack {
                    Spacer()
                    Button(tr("ui.atajos.restaurar.todos")) {
                        recordingID = nil
                        message = nil
                        shortcuts.resetAll()
                    }
                    .disabled(shortcuts.overrides.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tr(_ key: String) -> String { L10n.tr(key, locale: locale) }

    private func row(_ definition: LitteraShortcutDefinition) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                if shortcuts.isCustomized(definition.id) {
                    Button {
                        message = nil
                        shortcuts.reset(definition.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("ui.atajos.restablecer", locale: locale))
                    .accessibilityLabel(L10n.tr("ui.atajos.restablecer", locale: locale))
                }
                LitteraShortcutRecorder(
                    combo: shortcuts.combo(for: definition.id),
                    isRecording: recordingID == definition.id,
                    start: {
                        message = nil
                        recordingID = definition.id
                    },
                    finish: { result in
                        recordingID = nil
                        handle(result, for: definition.id)
                    }
                )
            }
        } label: {
            Text(tr(definition.titleKey))
            if let message, message.id == definition.id {
                Text(message.text)
            }
        }
    }

    private func handle(_ result: LitteraShortcutRecorder.Result, for id: String) {
        switch result {
        case .cancelled:
            break
        case .cleared:
            shortcuts.clear(id)
        case let .recorded(combo):
            switch shortcuts.assign(combo, to: id) {
            case .assigned:
                message = nil
            case .needsModifier:
                message = (id, L10n.tr("ui.atajos.necesita.modificador", locale: locale))
            case .conflict("system"):
                message = (id, L10n.formatted("ui.atajos.reservado", locale: locale, combo.display))
            case let .conflict(other):
                let title = LitteraShortcuts.definition(other).map { L10n.tr($0.titleKey, locale: locale) } ?? other
                message = (id, L10n.formatted("ui.atajos.en.uso", locale: locale, combo.display, title))
            }
        }
    }

    private func fixed(_ title: String, _ keys: String) -> some View {
        LabeledContent(tr(title)) {
            Text(keys).monospaced()
        }
    }
}

/// Botón que muestra el atajo y, al pulsarlo, graba la siguiente combinación.
/// Esc cancela; ⌫ quita el atajo.
struct LitteraShortcutRecorder: View {
    enum Result {
        case recorded(LitteraKeyCombo)
        case cleared
        case cancelled
    }

    let combo: LitteraKeyCombo?
    let isRecording: Bool
    let start: () -> Void
    let finish: (Result) -> Void

    @Environment(\.locale) private var locale
    @State private var monitor: Any?
    @Environment(\.litteraUITheme) private var colors

    var body: some View {
        Button(action: { isRecording ? finish(.cancelled) : start() }) {
            Text(label)
                .font(.litteraUI(size: 12, design: isRecording || combo == nil ? .default : .monospaced))
                .foregroundStyle(isRecording ? colors.accent : (combo == nil ? colors.secondaryText : colors.primaryText))
                .frame(minWidth: 92)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(colors.control, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? colors.accent : colors.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onChange(of: isRecording, initial: true) { _, recording in
            recording ? startMonitoring() : stopMonitoring()
        }
        .onDisappear(perform: stopMonitoring)
    }

    private var label: String {
        if isRecording { return L10n.tr("ui.atajos.pulsa", locale: locale) }
        return combo?.display ?? L10n.tr("ui.atajos.sin.atajo", locale: locale)
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(LitteraKeyCombo.allowedModifiers)
            if event.keyCode == 53, flags.isEmpty {
                finish(.cancelled)
            } else if (event.keyCode == 51 || event.keyCode == 117), flags.isEmpty {
                finish(.cleared)
            } else if let combo = LitteraKeyCombo(event: event) {
                finish(.recorded(combo))
            }
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
