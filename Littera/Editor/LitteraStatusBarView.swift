import SwiftUI

// Barra de estado independiente de la vista principal.
// Conserva el estilo tenue de la versión anterior.
struct LitteraStatusBarView: View {
    let wordCount: Int
    let mode: LitteraEditorMode
    /// Estado real del documento activo.
    let status: LitteraDocumentStatus

    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    private var colors: LitteraPalette { LitteraPalette(scheme) }

    var body: some View {
        HStack(spacing: LitteraDesign.Status.itemSpacing) {
            Circle()
                .fill(colors.accent)
                .frame(
                    width: LitteraDesign.Status.indicatorDiameter,
                    height: LitteraDesign.Status.indicatorDiameter
                )

            Text(L10n.tr(status.titleKey, locale: locale))
            Text("·")
            Text(L10n.counted("ui.d.palabras", wordCount, locale: locale))
            Text("·")
            Text(L10n.tr(mode.titleKey, locale: locale))
        }
        .font(.system(size: LitteraDesign.Status.fontSize))
        .foregroundStyle(colors.secondaryText)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, LitteraDesign.Status.horizontalPadding)
        .frame(height: LitteraDesign.Status.height)
        .background(colors.secondary, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                colors.line,
                lineWidth: LitteraDesign.Status.borderWidth
            )
        }
        // VoiceOver lee la barra como un solo elemento: «Guardado, 16 palabras, Visual».
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            L10n.tr(status.titleKey, locale: locale),
            L10n.counted("ui.d.palabras", wordCount, locale: locale),
            L10n.tr(mode.titleKey, locale: locale)
        ].joined(separator: ", "))
        .padding(.bottom, LitteraDesign.Status.bottomPadding)
        .frame(maxWidth: .infinity)
        .background(colors.canvas)
    }
}

/// Estado del documento que muestra la barra inferior.
enum LitteraDocumentStatus: Equatable {
    /// Documento nuevo que nunca se ha guardado.
    case unsaved
    /// Hay cambios posteriores al último guardado.
    case modified
    /// El archivo coincide con lo guardado.
    case saved

    init(_ document: LitteraDocumentSession?) {
        guard let document else {
            self = .unsaved
            return
        }
        if document.isDirty {
            self = .modified
        } else {
            self = document.fileURL == nil ? .unsaved : .saved
        }
    }

    var titleKey: String {
        switch self {
        case .unsaved: "ui.sin.guardar"
        case .modified: "ui.cambios.sin.guardar"
        case .saved: "ui.guardado"
        }
    }
}
