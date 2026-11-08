import XCTest
@testable import Littera

/// Preferencias mínimas de Littera v1 (D80): General, Editor y Atajos.
final class LitteraPreferencesRegistryTests: XCTestCase {
    func testThreePagesUniqueAndLocalized() {
        let pages = LitteraPreferencesRegistry.pages
        XCTAssertEqual(pages.map(\.id), ["general", "editor", "shortcuts"])
        for page in pages {
            for id in ["es", "en"] {
                XCTAssertNotEqual(L10n.tr(page.titleKey, locale: Locale(identifier: id)), page.titleKey, page.id)
            }
        }
    }
}
