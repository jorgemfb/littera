import Markdown

/// Capa de análisis Markdown independiente de SwiftUI, del almacenamiento y
/// de cualquier representación visual del documento.
nonisolated struct LitteraMarkdownParser {
    func parse(_ source: String) -> LitteraMarkdownParseResult {
        // El frontmatter YAML no es Markdown: se analiza el resto del texto
        // con las mismas líneas y columnas.
        let frontmatter = LitteraFrontmatter.detect(in: source)
        return LitteraMarkdownParseResult(
            source: source,
            // Sin puntuación tipográfica de cmark (1.0.4): la Vista previa y las
            // exportaciones muestran las comillas, guiones y puntos tal como
            // se escribieron (D15, D40); antes "--" aparecía como «–».
            ast: Markdown.Document(parsing: frontmatter?.masking(source) ?? source, options: [.disableSmartOpts]),
            frontmatter: frontmatter
        )
    }
}
