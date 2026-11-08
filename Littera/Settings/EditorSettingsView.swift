import SwiftUI

struct LitteraEditorSettingsView: View {
    @Environment(\.locale) private var locale
    @AppStorage(LitteraPreferenceKeys.sourceFontSize)
    private var fontSize = LitteraPreferenceDefaults.sourceFontSize
    @AppStorage(LitteraPreferenceKeys.writingWidth)
    private var writingWidth = LitteraPreferenceDefaults.writingWidth
    @AppStorage(LitteraPreferenceKeys.sourceHighlightStyle)
    private var sourceHighlightStyle = LitteraPreferenceDefaults.sourceHighlightStyle
    @AppStorage(LitteraPreferenceKeys.lineSpacing)
    private var lineSpacing = LitteraPreferenceDefaults.lineSpacing
    @AppStorage(LitteraPreferenceKeys.typewriterMode)
    private var typewriterMode = LitteraPreferenceDefaults.typewriterMode
    @AppStorage(LitteraPreferenceKeys.spellChecking)
    private var spellChecking = LitteraPreferenceDefaults.spellChecking
    @AppStorage(LitteraPreferenceKeys.continueLists)
    private var continueLists = LitteraPreferenceDefaults.continueLists
    @AppStorage(LitteraPreferenceKeys.autoPair)
    private var autoPair = LitteraPreferenceDefaults.autoPair
    @AppStorage(LitteraPreferenceKeys.dateFormat)
    private var dateFormat = LitteraPreferenceDefaults.dateFormat

    var body: some View {
        Form {
            Section(tr("ui.texto")) {
                Stepper(value: $fontSize, in: 10...28, step: 1) {
                    LabeledContent(tr("ui.tamano.en.fuente"), value: "\(Int(fontSize)) pt")
                }
                Picker(tr("ui.anchura.del.texto"), selection: $writingWidth) {
                    ForEach(LitteraWritingWidth.allCases) { width in
                        Text(tr(width.titleKey)).tag(width.rawValue)
                    }
                }
                Picker(tr("ui.resaltado.de.fuente"), selection: $sourceHighlightStyle) {
                    ForEach(LitteraSourceHighlightStyle.allCases) { style in
                        Text(tr(style.titleKey)).tag(style.rawValue)
                    }
                }
                Picker(tr("ui.interlineado"), selection: $lineSpacing) {
                    ForEach(LitteraLineSpacing.allCases) { spacing in
                        Text(tr(spacing.titleKey)).tag(spacing.rawValue)
                    }
                }
            }

            Section(tr("ui.escritura.avanzada")) {
                Toggle(tr("ui.modo.maquina.de.escribir"), isOn: $typewriterMode)
                Toggle(tr("ui.correccion.ortografica"), isOn: $spellChecking)
                Toggle(isOn: $continueLists) {
                    Text(tr("ui.continuar.listas"))
                    Text(tr("ui.continuar.listas.detalle"))
                }
                Toggle(isOn: $autoPair) {
                    Text(tr("ui.cerrar.simbolos"))
                    Text(tr("ui.cerrar.simbolos.detalle"))
                }
                Picker(tr("ui.formato.de.fecha"), selection: $dateFormat) {
                    ForEach(LitteraDateFormat.allCases) { format in
                        Text(tr(format.titleKey) + " · " + format.string(from: Date(), locale: locale))
                            .tag(format.rawValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func tr(_ key: String) -> String { L10n.tr(key, locale: locale) }
}
