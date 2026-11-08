import AppKit
import XCTest
@testable import Littera

/// Panel «Acerca de Littera»: copyright y licencias de terceros (RC1).
@MainActor
final class LitteraAboutTests: XCTestCase {
    func testCreditsListThirdPartyLicensesInBothLanguages() throws {
        for (language, heading) in [("es", "Componentes de terceros"), ("en", "Third-party components")] {
            let credits = try XCTUnwrap(LitteraAbout.credits(language: language), language).string
            XCTAssertTrue(credits.contains(heading), language)
            for required in ["Swift Markdown", "Apache License", "swift-cmark", "John MacFarlane", "Vicent Martí", "utf8proc", "Inter", "JetBrains Mono", "SIL OPEN FONT LICENSE"] {
                XCTAssertTrue(credits.contains(required), "\(required) falta en los créditos (\(language))")
            }
        }
    }

    func testCreditsUseTheSystemTextColorForDarkMode() throws {
        let credits = try XCTUnwrap(LitteraAbout.credits(language: "es"))
        var colors = Set<NSColor>()
        credits.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        XCTAssertEqual(colors, [NSColor.labelColor], "Texto legible en claro y oscuro")
    }

    func testCopyrightIsInTheInfoPlist() {
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        XCTAssertEqual(copyright?.hasPrefix("© 2026"), true, copyright ?? "sin copyright")
    }

    func testAppMenuHasOneAboutEntry() throws {
        let appMenu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        appMenu.update()
        let about = appMenu.items.filter { $0.title == L10n.string("menu.acerca.de.littera", language: LitteraLanguage.fallback) || $0.title.hasPrefix("About ") }
        XCTAssertEqual(about.count, 1, appMenu.items.map(\.title).description)
    }
}
