import Markdown

/// Resultado inmutable de analizar un documento Markdown.
///
/// `source` conserva exactamente la cadena recibida. `ast` es la representación
/// estructurada derivada de esa misma cadena y no sustituye al contenido del
/// documento almacenado en `LitteraDocumentSession`.
nonisolated struct LitteraMarkdownParseResult {
    let source: String
    let ast: Markdown.Document
    /// Frontmatter YAML inicial, si existe. No forma parte del AST.
    var frontmatter: LitteraFrontmatter? = nil
}
