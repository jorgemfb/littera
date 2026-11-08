import Foundation

// Modelo de documento independiente de la UI: identidad estable, Markdown
// actual y guardado, y archivo asociado cuando existe.
struct LitteraDocumentSession: Identifiable, Equatable {
    let id: String
    var fileName: String
    var folderDescription: String
    var markdown: String
    var savedMarkdown: String
    var isDirty: Bool
    var fileURL: URL?
    /// Fecha de modificación del archivo cuando Littera lo leyó o guardó por
    /// última vez; sirve para detectar cambios hechos fuera de Littera.
    var diskModificationDate: Date? = nil
    /// Marcador de seguridad para volver a abrir el archivo en otra sesión.
    var bookmark: Data? = nil
    /// El archivo se borró o movió fuera de Littera: el texto solo existe en memoria.
    var isMissingOnDisk = false
    /// El archivo tenía la marca de orden de bytes UTF-8: se conserva al guardar.
    var hasByteOrderMark = false

    static func newMarkdownDocument(fileName: String, folderDescription: String) -> Self {
        .init(id: UUID().uuidString, fileName: fileName, folderDescription: folderDescription, markdown: "", savedMarkdown: "", isDirty: false, fileURL: nil)
    }

    /// Contenido de los documentos nuevos: frontmatter con las propiedades
    /// del panel prerrellenadas y la fecha de hoy (D53).
    static var newDocumentTemplate: String { LitteraDocumentProperties.newDocumentTemplate() }

    /// Documento nuevo sin guardar: el que Littera muestra al arrancar o
    /// cuando no queda ningún documento abierto. Empieza con el frontmatter
    /// de la plantilla y sin cambios pendientes.
    static func untitled(locale: Locale) -> Self {
        var document = newMarkdownDocument(
            fileName: L10n.tr("ui.sin.titulo.md", locale: locale),
            folderDescription: L10n.tr("ui.documento.sin.guardar", locale: locale)
        )
        let template = LitteraDocumentProperties.newDocumentTemplate(
            language: locale.language.languageCode?.identifier ?? "es"
        )
        document.markdown = template
        document.savedMarkdown = template
        return document
    }

    /// Documento leído de disco.
    static func file(at url: URL, contents: LitteraDocumentFile.Contents) -> Self {
        .init(
            id: UUID().uuidString,
            fileName: url.lastPathComponent,
            folderDescription: url.deletingLastPathComponent().path,
            markdown: contents.markdown,
            savedMarkdown: contents.markdown,
            isDirty: false,
            fileURL: url,
            diskModificationDate: contents.modificationDate,
            bookmark: LitteraDocumentFile.bookmark(for: url),
            hasByteOrderMark: contents.hasByteOrderMark
        )
    }

    /// Documento vacío, limpio y sin archivo: puede sustituirse al abrir otro.
    var isPristineUntitled: Bool {
        fileURL == nil && !isDirty && (markdown.isEmpty || LitteraDocumentProperties.isNewDocumentTemplate(markdown))
    }
}

nonisolated extension String {
    /// Igualdad byte a byte. `==` considera iguales los textos Unicode
    /// equivalentes («é» precompuesta y «e» + tilde combinada), y un cambio
    /// solo de normalización no llegaba al documento ni se guardaba.
    func isIdentical(to other: String) -> Bool {
        utf8.count == other.utf8.count && utf8.elementsEqual(other.utf8)
    }
}
