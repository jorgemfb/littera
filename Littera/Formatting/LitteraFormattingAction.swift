import SwiftUI

// Contrato entre el panel visual y el futuro motor Markdown.
// Aquí se describen los formatos, sin modificar el documento.
enum LitteraFormattingAction: String, CaseIterable, Identifiable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case paragraph
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case quote
    case bulletList
    case numberedList
    case taskList
    case codeBlock
    case separator
    case table
    case image

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case inline = "ui.en.linea"
        case blocks = "ui.parrafos.y.titulos"
        case lists = "ui.listas"
        case insert = "ui.insertar"

        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .bold, .italic, .strikethrough, .inlineCode, .link:
            return .inline
        case .paragraph, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6, .quote:
            return .blocks
        case .bulletList, .numberedList, .taskList:
            return .lists
        case .codeBlock, .separator, .table, .image:
            return .insert
        }
    }

    var label: String {
        switch self {
        case .bold: "ui.negrita"
        case .italic: "ui.cursiva"
        case .strikethrough: "ui.tachado"
        case .inlineCode: "ui.codigo"
        case .link: "ui.enlace"
        case .paragraph: "ui.parrafo"
        case .heading1: "ui.titulo.1"
        case .heading2: "ui.titulo.2"
        case .heading3: "ui.titulo.3"
        case .heading4: "ui.titulo.4"
        case .heading5: "ui.titulo.5"
        case .heading6: "ui.titulo.6"
        case .quote: "ui.cita"
        case .bulletList: "ui.vinetas"
        case .numberedList: "ui.numerada"
        case .taskList: "ui.tareas"
        case .codeBlock: "ui.bloque.codigo"
        case .separator: "ui.separador"
        case .table: "ui.tabla"
        case .image: "ui.imagen"
        }
    }

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .paragraph: "text.alignleft"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: "textformat.size"
        case .quote: "text.quote"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .taskList: "checklist"
        case .codeBlock: "curlybraces"
        case .separator: "minus"
        case .table: "tablecells"
        case .image: "photo"
        }
    }

    var markdownExample: String {
        switch self {
        case .bold: "**texto destacado**"
        case .italic: "*texto en cursiva*"
        case .strikethrough: "~~texto tachado~~"
        case .inlineCode: "`código`"
        case .link: "[texto](https://ejemplo.com)"
        case .paragraph: "Un párrafo de texto."
        case .heading1: "# Título principal"
        case .heading2: "## Título de sección"
        case .heading3: "### Subsección"
        case .heading4: "#### Encabezado 4"
        case .heading5: "##### Encabezado 5"
        case .heading6: "###### Encabezado 6"
        case .quote: "> Una cita de ejemplo."
        case .bulletList: "- Primer elemento"
        case .numberedList: "1. Primer elemento"
        case .taskList: "- [ ] Tarea pendiente"
        case .codeBlock: "```swift\nprint(\"Hola\")\n```"
        case .separator: "---"
        case .table: "| Columna | Valor |\n| --- | --- |"
        case .image: "![Descripción](imagen.png)"
        }
    }
}
