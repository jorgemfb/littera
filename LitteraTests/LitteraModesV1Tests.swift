import XCTest
@testable import Littera

/// Tres modos de Littera v1 (D77): Fuente, Dividido y Vista previa.
final class LitteraModesV1Tests: XCTestCase {
    func testOnlyThreeModesRemain() {
        XCTAssertEqual(LitteraEditorMode.allCases, [.source, .split, .preview])
        XCTAssertNil(LitteraEditorMode(rawValue: "Visual"))
    }

    func testStoredVisualInitialModeMigratesToSourceAndOthersAreKept() {
        let defaults = LitteraTestDefaults.make()
        defaults.set("Visual", forKey: LitteraPreferenceKeys.initialMode)
        LitteraPreferenceMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: LitteraPreferenceKeys.initialMode), LitteraEditorMode.source.rawValue)

        defaults.set(LitteraEditorMode.split.rawValue, forKey: LitteraPreferenceKeys.initialMode)
        LitteraPreferenceMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: LitteraPreferenceKeys.initialMode), LitteraEditorMode.split.rawValue)
        XCTAssertEqual(LitteraPreferenceDefaults.initialMode, LitteraEditorMode.source.rawValue)
    }

    /// D78: nada permanente bajo el editor salvo que se active en Ajustes.
    func testStatusBarIsHiddenByDefault() {
        XCTAssertFalse(LitteraPreferenceDefaults.showStatusBar)
        XCTAssertNil(LitteraTestDefaults.make().object(forKey: LitteraPreferenceKeys.showStatusBar))
    }

    @MainActor
    func testModesHaveCommandOneToThreeAndNoVisualCommand() {
        XCTAssertNil(LitteraCommandRegistry.command("visual"))
        XCTAssertNil(LitteraShortcuts.definition("visual"))
        let defaults = LitteraEditorMode.allCases.map { LitteraShortcuts.definition($0.commandID)?.defaultCombo }
        XCTAssertEqual(defaults, [.command("1"), .command("2"), .command("3")])
    }
}

/// H20: cantidades con singular y plural en los dos idiomas.
final class LitteraCountedStringsTests: XCTestCase {
    func testSingularAndPluralInSpanishAndEnglish() {
        let es = Locale(identifier: "es")
        let en = Locale(identifier: "en")
        XCTAssertEqual(L10n.counted("ui.d.palabras", 1, locale: es), "1 palabra")
        XCTAssertEqual(L10n.counted("ui.d.palabras", 2, locale: es), "2 palabras")
        XCTAssertEqual(L10n.counted("ui.d.palabras", 0, locale: es), "0 palabras")
        XCTAssertEqual(L10n.counted("ui.d.lineas", 1, locale: en), "1 line")
        XCTAssertEqual(L10n.counted("ui.d.lineas", 3, locale: en), "3 lines")
        for key in ["ui.d.palabras", "ui.d.caracteres", "ui.d.caracteres.sin.espacios", "ui.d.parrafos", "ui.d.lineas", "ui.busqueda.d.reemplazos"] {
            for locale in [es, en] {
                XCTAssertNotEqual(L10n.tr(key + ".uno", locale: locale), key + ".uno", "\(key).uno sin traducir en \(locale.identifier)")
            }
        }
    }
}
