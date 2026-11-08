import Foundation

// Contrato estable de preferencias. Evitar cadenas repetidas en las vistas.
// El almacenamiento local y la integridad de los archivos NO dependen de estas claves.
enum LitteraPreferenceKeys {
    // Nueva clave: descarta una sola vez el valor heredado de la implementación defectuosa.
    // Desde ahora, la selección se conserva entre reinicios y empieza en Sistema.
    static let themeMode = "littera.theme.mode.v1"
    static let language = LitteraLanguage.settingKey
    static let initialMode = "littera.editor.initialMode"
    static let writingWidth = "littera.editor.writingWidth"
    static let sourceFontSize = "littera.editor.sourceFontSize"
    /// Anchura de la columna en Fuente hasta 2026-11-07. Ya no se lee: Fuente
    /// sigue `writingWidth` (una sola anchura); se migra una vez.
    static let sourceWidth = "littera.editor.sourceWidth"
    /// Paleta del resaltado de Fuente: Suave o Viva.
    static let sourceHighlightStyle = "littera.editor.sourceHighlightStyle"
    static let restoreSession = "littera.documents.restoreSession"
    static let lineSpacing = "littera.editor.lineSpacing"
    static let typewriterMode = "littera.editor.typewriterMode"
    static let spellChecking = "littera.editor.spellChecking"
    /// Qué hacer al arrancar sin documentos: "empty" o "open".
    static let startupWithoutDocuments = "littera.startup.withoutDocuments"
    /// Guardar solo los documentos que ya tienen archivo (D49).
    static let autosave = "littera.documents.autosave"
    /// Marcador de seguridad de la carpeta predeterminada (D49).
    static let defaultFolderBookmark = "littera.documents.defaultFolder"
    /// Escritura asistida (D52).
    static let continueLists = "littera.editor.continueLists"
    static let autoPair = "littera.editor.autoPair"
    static let dateFormat = "littera.editor.dateFormat"
    /// Barra de estado bajo el editor (D78).
    static let showStatusBar = "littera.window.showStatusBar"
}

enum LitteraPreferenceDefaults {
    static let initialMode = "Fuente"
    static let writingWidth = "Medio"
    static let sourceFontSize = 14.0
    static let sourceWidth = LitteraSourceWidth.medium.rawValue
    static let sourceHighlightStyle = LitteraSourceHighlightStyle.soft.rawValue
    static let restoreSession = true
    static let lineSpacing = LitteraLineSpacing.normal.rawValue
    static let typewriterMode = false
    static let spellChecking = false
    static let startupWithoutDocuments = "empty"
    /// Desactivado: nada se escribe en disco sin que el usuario lo pida
    /// hasta que active la opción.
    static let autosave = false
    static let continueLists = true
    static let autoPair = true
    static let dateFormat = LitteraDateFormat.iso.rawValue
    /// Oculta: nada permanente bajo el editor (D78).
    static let showStatusBar = false
}

/// Migraciones de preferencias guardadas. Las claves no cambian.
enum LitteraPreferenceMigration {
    /// Visual se retiró (D77): una «Vista inicial» guardada como Visual pasa
    /// a Fuente, el modo que la sustituye.
    static func migrate(_ defaults: UserDefaults = .standard) {
        if defaults.string(forKey: LitteraPreferenceKeys.initialMode) == "Visual" {
            defaults.set(LitteraEditorMode.source.rawValue, forKey: LitteraPreferenceKeys.initialMode)
        }
        // Una sola anchura del texto: si solo se había cambiado la de Fuente,
        // se conserva esa elección. La clave antigua no se borra.
        if defaults.object(forKey: LitteraPreferenceKeys.writingWidth) == nil,
           let source = defaults.string(forKey: LitteraPreferenceKeys.sourceWidth),
           LitteraWritingWidth(rawValue: source) != nil {
            defaults.set(source, forKey: LitteraPreferenceKeys.writingWidth)
        }
    }
}
