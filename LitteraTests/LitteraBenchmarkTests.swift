import AppKit
import SwiftUI
import XCTest
@testable import Littera

/// Mediciones de rendimiento (Fase 2). Solo se ejecutan con
/// `LITTERA_BENCH=1` (xcodebuild: `TEST_RUNNER_LITTERA_BENCH=1`); en la
/// batería normal se omiten. Cada resultado se imprime en una línea
/// `BENCH|nombre|líneas|mediana_ms|p95_ms|muestras` para extraerlo del registro.
/// Usan documentos sintéticos generados en memoria, nunca archivos del usuario.
@MainActor
final class LitteraBenchmarkTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["LITTERA_BENCH"] == "1" else {
            throw XCTSkip("Mediciones de rendimiento: solo con LITTERA_BENCH=1.")
        }
    }

    // MARK: Utilidades

    static let sizes = [1_000, 10_000, 50_000]

    /// Documento sintético con la mezcla habitual: frontmatter, encabezados,
    /// párrafos con formato, listas, tareas, citas, código, tablas y, cada
    /// diez secciones, un diagrama Mermaid.
    static func document(lines target: Int) -> String {
        var lines = ["---", "title: \"Medición\"", "status: draft", "tags: [rendimiento]", "---", ""]
        var section = 0
        while lines.count < target {
            section += 1
            lines += [
                "## Sección \(section)",
                "",
                "Párrafo con **negrita**, *cursiva*, `código` y un [enlace](https://example.com/\(section)). Texto de relleno para medir el rendimiento del editor con contenido realista.",
                "",
                "- Elemento uno",
                "- Elemento dos con *énfasis*",
                "- [x] Tarea hecha",
                "- [ ] Tarea pendiente",
                "",
                "> Cita breve de la sección \(section).",
                "",
                "```swift",
                "let valor = \(section)",
                "print(\"Sección \\(valor)\")",
                "```",
                "",
                "| Columna | Valor |",
                "|---|---|",
                "| a | \(section) |",
                "",
            ]
            if section % 10 == 0 {
                lines += ["```mermaid", "graph TD", "  A\(section)[Inicio] --> B\(section){¿Sigue?}", "  B\(section) -->|sí| C\(section)[Fin]", "  B\(section) -->|no| A\(section)", "```", ""]
            }
        }
        return lines.prefix(target).joined(separator: "\n")
    }

    private func milliseconds(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func report(_ name: String, lines: Int, _ samples: [Double]) {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
        print(String(format: "BENCH|%@|%d|%.3f|%.3f|%d", name, lines, median, p95, samples.count))
    }

    private func drainRunLoop(_ passes: Int = 3) {
        for _ in 0..<passes { CFRunLoopRunInMode(.defaultMode, 0, true) }
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
        return true
    }

    private static func middleOfParagraph(in text: String, near fraction: Double) -> Int {
        let ns = text as NSString
        let start = Int(Double(ns.length) * fraction)
        let found = ns.range(of: "Texto de relleno", options: [], range: NSRange(location: start, length: ns.length - start))
        return found.location == NSNotFound ? start : found.location
    }

    private static func inserting(_ character: String, at location: Int, in text: String) -> String {
        (text as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: character)
    }

    // MARK: Análisis Markdown (fuera del hilo principal en la app)

    func testDerivation() {
        for size in Self.sizes {
            let text = Self.document(lines: size)
            _ = LitteraMarkdownDerivedDocument(source: text, revision: 0)
            let runs = size >= 50_000 ? 3 : 7
            let samples = (0..<runs).map { index in
                milliseconds { _ = LitteraMarkdownDerivedDocument(source: text, revision: UInt64(index)) }
            }
            report("derivacion", lines: size, samples)
        }
    }

    // MARK: Resaltado del modo Fuente (hilo principal)

    func testSourceStyling() {
        for size in Self.sizes {
            let text = Self.document(lines: size)
            let first = LitteraMarkdownDerivedDocument(source: text, revision: 1)
            let location = Self.middleOfParagraph(in: text, near: 0.5)
            let edited = Self.inserting("x", at: location, in: text)
            let second = LitteraMarkdownDerivedDocument(source: edited, revision: 2)

            var full: [Double] = []
            var incremental: [Double] = []
            for _ in 0..<(size >= 50_000 ? 3 : 7) {
                let storage = NSTextStorage(string: text)
                let styler = LitteraSourceStyler()
                full.append(milliseconds {
                    styler.apply(runs: first.visualRuns, to: storage, scheme: .dark, fontSize: 13)
                })
                storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
                incremental.append(milliseconds {
                    styler.apply(runs: second.visualRuns, to: storage, scheme: .dark, fontSize: 13)
                })
            }
            report("fuente.resaltado.completo", lines: size, full)
            report("fuente.resaltado.incremental", lines: size, incremental)
        }
    }

    // MARK: Pulsación en Fuente (editor real alojado en SwiftUI)

    private struct SourceHost: View {
        @ObservedObject var store: LitteraDocumentStore
        @State private var selection: [NSRange] = []
        @State private var offset: CGPoint = .zero

        var body: some View {
            let id = store.activeDocumentID
            LitteraSourceTextView(
                text: Binding(
                    get: { store.activeDocument?.markdown ?? "" },
                    set: { store.updateMarkdown(for: id, text: $0) }
                ),
                selectedRanges: $selection,
                scrollOffset: $offset,
                documentID: id,
                fontSize: 13,
                textColor: .textColor,
                scrollCoordinator: nil,
                sourceHighlight: LitteraSourceHighlight(document: store.derivedDocuments[id], colorScheme: .dark)
            )
        }
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    func testSourceKeystroke() throws {
        for size in Self.sizes {
            let text = Self.document(lines: size)
            let store = LitteraDocumentStore.isolated()
            let id = store.activeDocumentID
            store.updateMarkdown(for: id, text: text)
            XCTAssertTrue(wait { store.derivedDocuments[id]?.source == text })

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SourceHost(store: store))
            window.orderFront(nil)
            window.layoutIfNeeded()
            drainRunLoop(10)
            let textView = try XCTUnwrap(findTextView(in: try XCTUnwrap(window.contentView)))
            window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: Self.middleOfParagraph(in: text, near: 0.5), length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
            drainRunLoop(10)

            var keystroke: [Double] = []
            var highlight: [Double] = []
            for _ in 0..<15 {
                let start = DispatchTime.now().uptimeNanoseconds
                keystroke.append(milliseconds {
                    textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
                    drainRunLoop()
                })
                let expected = textView.string
                XCTAssertTrue(wait { store.derivedDocuments[id]?.source == expected })
                drainRunLoop()
                highlight.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            report("fuente.pulsacion", lines: size, keystroke)
            report("fuente.resaltado.listo", lines: size, highlight)
            window.contentView = nil
            window.close()
        }
    }

    /// Desglose de una pulsación (diagnóstico): inserción en el editor y,
    /// por separado, el ciclo de SwiftUI que la sigue.
    func testSourceKeystrokePhases() throws {
        guard ProcessInfo.processInfo.environment["LITTERA_BENCH_PHASES"] == "1" else {
            throw XCTSkip("Desglose: solo con LITTERA_BENCH_PHASES=1.")
        }
        let size = 10_000
        let text = Self.document(lines: size)
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        store.updateMarkdown(for: id, text: text)
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == text })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SourceHost(store: store))
        window.orderFront(nil)
        drainRunLoop(10)
        let textView = try XCTUnwrap(findTextView(in: try XCTUnwrap(window.contentView)))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: Self.middleOfParagraph(in: text, near: 0.5), length: 0))
        drainRunLoop(10)

        var insert: [Double] = [], cycle: [Double] = []
        for _ in 0..<10 {
            insert.append(milliseconds { textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0)) })
            cycle.append(milliseconds { drainRunLoop() })
            let expected = textView.string
            XCTAssertTrue(wait { store.derivedDocuments[id]?.source == expected })
            drainRunLoop()
        }
        // Comparaciones de cadenas del tamaño del documento (no ASCII).
        let native = String(decoding: Array(text.utf8), as: UTF8.self)
        let other = String(decoding: Array(text.utf8), as: UTF8.self)
        let bridged = textView.string
        var stringCopy: [Double] = [], compare: [Double] = [], compareBridged: [Double] = [], compareUTF16: [Double] = [], update: [Double] = []
        for index in 0..<10 {
            var copy = ""
            stringCopy.append(milliseconds { copy = textView.string })
            compare.append(milliseconds { _ = native == other })
            compareBridged.append(milliseconds { _ = bridged == native })
            compareUTF16.append(milliseconds { _ = (bridged as NSString).isEqual(to: native) })
            update.append(milliseconds { store.updateMarkdown(for: id, text: copy + "\(index)") })
        }
        report("diag.insertText", lines: size, insert)
        report("diag.cicloSwiftUI", lines: size, cycle)
        report("diag.copiaString", lines: size, stringCopy)
        report("diag.comparacion.nativa", lines: size, compare)
        report("diag.comparacion.puenteada", lines: size, compareBridged)
        report("diag.comparacion.utf16", lines: size, compareUTF16)
        report("diag.updateMarkdown", lines: size, update)
        window.contentView = nil
        window.close()
    }

    /// Diagnóstico: coste de `updateMarkdown` (sin SwiftUI) y de comparar
    /// cadenas, con el documento normal (no ASCII) y con uno solo ASCII.
    func testStringComparisonCost() throws {
        guard ProcessInfo.processInfo.environment["LITTERA_BENCH_PHASES"] == "1" else {
            throw XCTSkip("Desglose: solo con LITTERA_BENCH_PHASES=1.")
        }
        let size = 10_000
        let accented = Self.document(lines: size)
        let ascii = String(accented.unicodeScalars.map { $0.isASCII ? Character($0) : "e" })
        var sink = 0
        for (label, text) in [("noascii", accented), ("ascii", ascii)] {
            let copyA = String(decoding: Array(text.utf8), as: UTF8.self)
            let middle = text.utf8.count / 2
            var bytes = Array(text.utf8)
            bytes[middle] = UInt8(ascii: "z")
            let differing = String(decoding: bytes, as: UTF8.self)
            let bridged = NSMutableString(string: text) as String

            var equal: [Double] = [], differ: [Double] = [], bridgedEqual: [Double] = [], update: [Double] = []
            let store = LitteraDocumentStore.isolated()
            let id = store.activeDocumentID
            store.updateMarkdown(for: id, text: text)
            for index in 0..<10 {
                equal.append(milliseconds { if copyA == text { sink += 1 } })
                differ.append(milliseconds { if differing == text { sink += 1 } })
                bridgedEqual.append(milliseconds { if bridged == text { sink += 1 } })
                let next = text + String(index)
                update.append(milliseconds { store.updateMarkdown(for: id, text: next) })
            }
            report("diag.\(label).igual", lines: size, equal)
            report("diag.\(label).distinta.mitad", lines: size, differ)
            report("diag.\(label).puenteada.igual", lines: size, bridgedEqual)
            report("diag.\(label).updateMarkdown", lines: size, update)
        }
        print("sink \(sink)")
    }

    /// Escritura continua durante unos segundos para perfilar el proceso desde
    /// fuera (`sample`). Diagnóstico: solo con LITTERA_BENCH_PROFILE=1.
    func testTypingForProfiling() throws {
        guard let mode = ProcessInfo.processInfo.environment["LITTERA_BENCH_PROFILE"] else {
            throw XCTSkip("Perfil: solo con LITTERA_BENCH_PROFILE.")
        }
        let size = 10_000
        let text = Self.document(lines: size)
        let store = LitteraDocumentStore.isolated()
        let id = store.activeDocumentID
        store.updateMarkdown(for: id, text: text)
        XCTAssertTrue(wait { store.derivedDocuments[id]?.source == text })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SourceHost(store: store))
        window.orderFront(nil)
        drainRunLoop(10)
        let textView = try XCTUnwrap(findTextView(in: try XCTUnwrap(window.contentView)))
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: Self.middleOfParagraph(in: text, near: 0.5), length: 0))
        drainRunLoop(10)
        print("PERFIL listo \(mode)")
        let end = Date().addingTimeInterval(25)
        var count = 0
        while Date() < end {
            textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
            drainRunLoop()
            count += 1
        }
        print("PERFIL pulsaciones \(count)")
        window.contentView = nil
        window.close()
    }

    // MARK: Vista previa (Dividido) tras una edición — LIT-005

    func testPreviewUpdate() {
        for size in Self.sizes {
            let text = Self.document(lines: size)
            let original = LitteraMarkdownDerivedDocument(source: text, revision: 1)
            let early = LitteraMarkdownDerivedDocument(
                source: Self.inserting("x", at: Self.middleOfParagraph(in: text, near: 0.05), in: text), revision: 2
            )
            let late = LitteraMarkdownDerivedDocument(
                source: Self.inserting("x", at: Self.middleOfParagraph(in: text, near: 0.95), in: text), revision: 3
            )
            func root(_ document: LitteraMarkdownDerivedDocument) -> AnyView {
                AnyView(ScrollView {
                    LitteraMarkdownPreviewView(document: document)
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 40)
                })
            }
            let hosting = NSHostingView(rootView: root(original))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)

            let initial = milliseconds {
                hosting.layoutSubtreeIfNeeded()
                drainRunLoop()
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
            }
            report("vista.previa.inicial", lines: size, [initial])

            var earlyEdit: [Double] = []
            var lateEdit: [Double] = []
            for _ in 0..<(size >= 50_000 ? 3 : 5) {
                for (document, bucket) in [(early, 0), (original, -1), (late, 1), (original, -1)] {
                    let elapsed = milliseconds {
                        hosting.rootView = root(document)
                        hosting.layoutSubtreeIfNeeded()
                        drainRunLoop()
                        hosting.layoutSubtreeIfNeeded()
                        hosting.displayIfNeeded()
                    }
                    if bucket == 0 { earlyEdit.append(elapsed) }
                    if bucket == 1 { lateEdit.append(elapsed) }
                }
            }
            report("vista.previa.edicion.inicio", lines: size, earlyEdit)
            report("vista.previa.edicion.final", lines: size, lateEdit)
            window.contentView = nil
            window.close()
        }
    }

    // MARK: Maquetación completa de Fuente en Dividido — LIT-008

    func testSourceFullLayoutAfterEdit() {
        for size in Self.sizes {
            let text = Self.document(lines: size)
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 700))
            let textView = NSTextView(frame: scrollView.bounds)
            textView.isRichText = false
            textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainer?.widthTracksTextView = true
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            scrollView.documentView = textView
            textView.string = text
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { continue }
            let initial = milliseconds { layoutManager.ensureLayout(for: container) }
            report("dividido.maquetacion.inicial", lines: size, [initial])

            var samples: [Double] = []
            for index in 0..<(size >= 50_000 ? 3 : 7) {
                let location = Self.middleOfParagraph(in: textView.string, near: 0.1 + Double(index) * 0.01)
                textView.textStorage?.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
                samples.append(milliseconds { layoutManager.ensureLayout(for: container) })
            }
            report("dividido.maquetacion.tras.edicion", lines: size, samples)
        }
    }

    // MARK: Mermaid (fuera del hilo principal en la app)

    func testMermaidLayout() {
        for nodes in [10, 40, 100] {
            var lines = ["graph TD"]
            for index in 0..<nodes {
                lines.append("  N\(index)[Nodo \(index)] --> N\(index + 1)[Nodo \(index + 1)]")
                if index % 5 == 0, index > 0 { lines.append("  N\(index) -->|vuelta| N\(index - 3)") }
            }
            let code = lines.joined(separator: "\n")
            _ = LitteraMermaidDiagram.make(code: code)
            let samples = (0..<5).map { _ in milliseconds { _ = LitteraMermaidDiagram.make(code: code) } }
            report("mermaid.disposicion.nodos", lines: nodes, samples)
        }
    }
}
