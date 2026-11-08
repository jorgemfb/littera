import Foundation

/// Datos del entorno de ejecución (LIT-014).
nonisolated enum LitteraRuntime {
    /// `true` cuando Littera hace de app anfitriona de las pruebas de Xcode.
    /// Xcode define estas variables al lanzar la app para cargar las pruebas.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
