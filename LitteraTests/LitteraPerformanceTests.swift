import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Mediciones de rendimiento de las operaciones que se ejecutan al escribir.
/// Documento de referencia: unas 10.000 palabras con todos los tipos de bloque.
@MainActor
final class LitteraPerformanceTests: XCTestCase {
    static let largeDocument: String = {
        var parts = ["---\ntitle: Rendimiento\ntags: [littera]\n---\n"]
        for section in 1...60 {
            parts.append("""
            ## Sección \(section)

            Párrafo con **negrita**, *cursiva*, `código` y un [enlace](https://example.com). \
            Texto de relleno para medir el análisis y el estilo de un documento largo con \
            muchas palabras repartidas en varios bloques distintos del documento.

            > Una cita breve dentro de la sección \(section).

            - Elemento uno
            - [x] Tarea hecha
            - Elemento tres

            ```swift
            let valor = \(section) // comentario
            func ejemplo() -> Int { valor * 2 }
            ```

            | Columna | Valor |
            | --- | --- |
            | a | \(section) |

            Otro párrafo largo de relleno que repite palabras para alcanzar el tamaño \
            de un documento real escrito en Littera durante una sesión de trabajo larga. \
            Este texto continúa con más palabras y signos de puntuación, comas y puntos.

            """)
        }
        return parts.joined(separator: "\n")
    }()

    private let options: XCTMeasureOptions = {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }()

    func testDocumentSizeIsRealistic() {
        XCTAssertGreaterThan(Self.largeDocument.split(whereSeparator: \.isWhitespace).count, 7_000)
    }

    /// Análisis completo (parser, renderer, tramos Visual, recuento).
    func testDeriveLargeDocument() {
        measure(options: options) {
            _ = LitteraMarkdownDerivedDocument(source: Self.largeDocument, revision: 1)
        }
    }

    /// Estilo Fuente completo.
    func testSourceStyleFullDocument() {
        let derived = LitteraMarkdownDerivedDocument(source: Self.largeDocument, revision: 1)
        measure(options: options) {
            let storage = NSTextStorage(string: Self.largeDocument)
            LitteraSourceStyler().apply(runs: derived.visualRuns, to: storage, scheme: .dark, fontSize: 14)
        }
    }

    /// Una pulsación: análisis de la nueva versión y reestilo solo de la zona cambiada.
    func testIncrementalSourceRestyleAfterKeystroke() {
        let original = LitteraMarkdownDerivedDocument(source: Self.largeDocument, revision: 1)
        let storage = NSTextStorage(string: Self.largeDocument)
        let styler = LitteraSourceStyler()
        styler.apply(runs: original.visualRuns, to: storage, scheme: .light, fontSize: 14)
        var revision: UInt64 = 1
        measure(options: options) {
            let location = (storage.string as NSString).length / 2
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
            revision += 1
            let derived = LitteraMarkdownDerivedDocument(source: storage.string, revision: revision)
            styler.apply(runs: derived.visualRuns, to: storage, scheme: .light, fontSize: 14)
        }
    }

    func testExportHTML() {
        measure(options: options) {
            _ = LitteraExporter.html(for: Self.largeDocument, title: "Rendimiento")
        }
    }

    func testExportPDF() throws {
        let derived = LitteraMarkdownDerivedDocument(source: Self.largeDocument, revision: 1)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(options: options) {
            _ = try? LitteraExporter.pdf(for: derived, documentURL: nil)
        }
    }
}
