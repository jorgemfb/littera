import SwiftUI

// SOLO medidas visuales compartidas.
// Los colores y los modos de apariencia viven en Appearance/.

// Medidas compartidas: cambiarlas aquí afecta a todos los controles indicados.
enum LitteraDesign {
    enum Titlebar {
        static let documentFontSize: CGFloat = 13
        static let actionIconSize: CGFloat = 14
        static let indicatorDiameter: CGFloat = 7
        static let titleSpacing: CGFloat = 8
        static let actionSpacing: CGFloat = 8
        static let actionHitSize: CGFloat = 28
        static let outerSpacing: CGFloat = 2
        // Sin fondos, bordes o cápsulas personalizados en la barra superior.
    }

    enum Status {
        static let fontSize: CGFloat = 11
        static let indicatorDiameter: CGFloat = 7
        static let itemSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
        static let height: CGFloat = 30
        static let bottomPadding: CGFloat = 12
        static let borderWidth: CGFloat = 0.7
    }

    enum Editor {
        static let sourceFontSize: CGFloat = 14
        static let sourceHorizontalPadding: CGFloat = 24
        static let sourceVerticalPadding: CGFloat = 20
        static let previewHorizontalPadding: CGFloat = 36
        static let previewTopPadding: CGFloat = 48
        static let previewBottomPadding: CGFloat = 86
    }

    enum Settings {
        static let sidebarWidth: CGFloat = 214
        static let minWidth: CGFloat = 730
        static let minHeight: CGFloat = 480
        static let idealWidth: CGFloat = 870
        static let idealHeight: CGFloat = 620
        static let contentPadding: CGFloat = 26
        static let contentSpacing: CGFloat = 22
        static let sectionSpacing: CGFloat = 10
        static let headingSize: CGFloat = 23
        static let groupLabelSize: CGFloat = 10
        static let groupRadius: CGFloat = 11
        static let rowHorizontalPadding: CGFloat = 16
        static let rowVerticalPadding: CGFloat = 13
    }

    enum CommandPalette {
        static let width: CGFloat = 590
        static let maxResultsHeight: CGFloat = 390
        static let cornerRadius: CGFloat = 16
        static let rowHeight: CGFloat = 39
        static let searchHeight: CGFloat = 57
        static let footerHeight: CGFloat = 37
        static let topOffset: CGFloat = 30
        static let groupTitleSize: CGFloat = 10
        static let rowCornerRadius: CGFloat = 8
    }
}
