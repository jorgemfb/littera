import SwiftUI

/// Ventana principal de Littera v1 (D76): el editor con su barra nativa
/// (título, propiedades, lupa y `···`) dentro del centro de mando de
/// documentos, paletas y avisos de la app.
struct LitteraMainWindow: View {
    let documentStore: LitteraDocumentStore
    let applicationDelegate: LitteraApplicationDelegate

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        LitteraCommandHost(documentStore: documentStore, applicationDelegate: applicationDelegate) {
            LitteraEditorView(documentStore: documentStore, applicationDelegate: applicationDelegate)
        }
        // La paleta conserva su tema hasta simplificarla (D80).
        .litteraUITheme(scheme, contrast: contrast)
    }
}
