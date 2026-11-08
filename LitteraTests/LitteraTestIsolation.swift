import Foundation
import XCTest

/// Preferencias de prueba aisladas (LIT-014). Cada llamada crea un dominio
/// propio, que se vacía y elimina al terminar la prueba que lo creó. Las
/// pruebas se ejecutan además en la compilación Debug, cuyo identificador
/// (`com.cnyps.es.Littera.debug`) tiene su propio contenedor del sandbox:
/// nada de esto llega a las Preferencias reales del usuario.
enum LitteraTestDefaults {
    private static let cleaner = Cleaner()
    private static var isObserving = false
    private static var created: [(name: String, defaults: UserDefaults)] = []

    static func make() -> UserDefaults {
        if !isObserving {
            XCTestObservationCenter.shared.addTestObserver(cleaner)
            isObserving = true
        }
        let name = "littera.tests.\(UUID().uuidString)"
        // Un nombre de dominio nuevo nunca es el de la app ni el global.
        let defaults = UserDefaults(suiteName: name)!
        created.append((name, defaults))
        return defaults
    }

    fileprivate static func removeCreatedDomains() {
        for (name, defaults) in created {
            defaults.removePersistentDomain(forName: name)
        }
        created.removeAll()
    }

    private final class Cleaner: NSObject, XCTestObservation {
        func testCaseDidFinish(_ testCase: XCTestCase) {
            LitteraTestDefaults.removeCreatedDomains()
        }

        func testBundleDidFinish(_ testBundle: Bundle) {
            LitteraTestDefaults.removeCreatedDomains()
        }
    }
}
