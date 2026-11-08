# Littera 2.0 · Adaptadores de integración (listos para el cutover)

**Fecha:** 2026-10-26 · **Estado:** HISTÓRICO. El adaptador ya está cableado en `Littera/Integration/LitteraUIAdapters.swift` (cutover D65); el código real ha divergido de este borrador y es la referencia.

Este documento contiene el **adaptador real** que conecta el rediseño
(`Littera/UI/`) con el backend. Es código **listo para añadir** en el cutover.
No está en el target todavía a propósito: así la app en producción y la ventana
de demostración siguen intactas y el build no corre riesgo. El adaptador importa
el backend, por eso vive **fuera de `Littera/UI/`** (p. ej. `Littera/Integration/`).

La costura del lado presentación ya está en el código (fase 6):
- `Littera/UI/LitteraUIIntegration.swift` — `LitteraUIActions` (closures no-op por
  defecto) y `LitteraUIExportFormat`.
- Las vistas aceptan `actions = LitteraUIActions()` (mock por defecto): el botón
  «Nuevo» (barra lateral y biblioteca) llama `actions.onNew`; el menú
  Exportar/Compartir llama `actions.onExport(.pdf/.html)`. La demo usa los
  valores por defecto, así que no cambia.

---

## 1. `Littera/Integration/LitteraUIAdapters.swift` (añadir en el cutover)

```swift
import Foundation

/// Mapea los tipos reales del backend a los modelos de presentación del
/// rediseño. Vive FUERA de Littera/UI/ (importa el backend).
enum LitteraUIAdapter {

    // MARK: Sesión (+ derivado) -> modelo de presentación

    static func uiDocument(_ s: LitteraDocumentSession,
                           derived: LitteraMarkdownDerivedDocument?) -> LitteraUIDocument {
        let props = LitteraDocumentProperties(frontmatter: derived?.frontmatter)
        let title = props.title.isEmpty
            ? (s.fileName as NSString).deletingPathExtension
            : props.title
        return LitteraUIDocument(
            id: UUID(uuidString: s.id) ?? UUID(),   // s.id es un UUID().uuidString
            fileName: s.fileName,
            title: title,
            markdown: s.markdown,
            isDirty: s.isDirty,
            status: uiStatus(props.knownStatus),
            tags: props.tags,
            modified: s.diskModificationDate ?? Date(),
            wordCount: derived?.wordCount ?? 0
        )
    }

    static func uiLibraryItem(_ s: LitteraDocumentSession,
                              derived: LitteraMarkdownDerivedDocument?) -> LitteraUILibraryItem {
        let props = LitteraDocumentProperties(frontmatter: derived?.frontmatter)
        let title = props.title.isEmpty
            ? (s.fileName as NSString).deletingPathExtension
            : props.title
        return LitteraUILibraryItem(
            id: UUID(uuidString: s.id) ?? UUID(),
            fileName: s.fileName,
            title: title,
            excerpt: "",                 // opcional: primer párrafo del render
            status: uiStatus(props.knownStatus),
            tags: props.tags,
            isFavorite: false,           // pendiente: servicio de metadatos
            modified: s.diskModificationDate ?? Date(),
            wordCount: derived?.wordCount ?? 0
        )
    }

    static func uiStatus(_ s: LitteraPropertyStatus?) -> LitteraUIDocumentStatus {
        switch s {
        case .draft:      return .draft
        case .inProgress: return .inProgress
        case .review:     return .review
        case .done:       return .done
        case nil:         return .draft
        }
    }

    // MARK: Acciones -> store (fuente de verdad)

    @MainActor
    static func actions(store: LitteraDocumentStore, locale: Locale) -> LitteraUIActions {
        var a = LitteraUIActions()
        a.onNew = { store.newDocument(locale: locale) }
        a.onOpen = { uuid in
            if let s = store.documents.first(where: { UUID(uuidString: $0.id) == uuid }) {
                store.activeDocumentID = s.id
            }
        }
        a.onClose = { uuid in
            if let s = store.documents.first(where: { UUID(uuidString: $0.id) == uuid }) {
                _ = store.closeDocument(id: s.id, locale: locale)
            }
        }
        a.onOpenFromDisk = { /* panel Abrir de LitteraEditorView */ }
        a.onExport = { fmt in
            // LitteraExporter.export(..., format: fmt == .pdf ? .pdf : .html)
            // Requiere el derivado/base de la sesión activa y destino de archivo.
        }
        a.onEdit = { newText in
            // Aplicar a la sesión activa (markdown = newText) vía la ruta
            // existente de edición; dispara reanálisis del store.
        }
        a.onSetProperty = { key, value in
            // D53: LitteraDocumentProperties.edit(...) sobre la sesión activa.
        }
        return a
    }
}
```

> Confirmar en el cutover las firmas exactas de `LitteraExporter.export(...)`,
> la ruta de edición de la sesión activa y `LitteraDocumentProperties.edit(...)`
> (marcadas como TODO). El resto está verificado contra el código actual.

---

## 2. Panel Fuente real (contrato §2)

El `NSTextView` existente **no se reescribe**. En el cutover, un
`NSViewRepresentable` (fuera de `UI/`, p. ej. `LitteraSourcePanelBridge`)
envuelve `LitteraSourceTextView` y se inyecta en el modo Fuente/Dividido en
lugar de `LitteraSourcePaneDemo`. La posición de lectura semántica se conecta
pasando el `LitteraScrollCoordinator` existente.

Hasta entonces, las vistas del editor (`LitteraSplitDemoView` y paneles) siguen
mostrando contenido de demostración: es la última pieza del cutover, no de la
preparación.

---

## 3. Montaje en `LitteraApp` (cutover = fase 7)

En `WindowGroup`, en lugar de `LitteraEditorView`, montar un contenedor que
observe el `LitteraDocumentStore` y construya:

```swift
LitteraWorkspaceView(
    document: LitteraUIAdapter.uiDocument(store.activeDocument ?? .untitled(locale: locale),
                                          derived: store.activeDocument.flatMap { store.derivedDocuments[$0.id] }),
    actions: LitteraUIAdapter.actions(store: store, locale: locale)
)
.litteraUITheme(effectiveScheme, contrast: contrast)
.environment(\.locale, locale)
```

Recomendado: detrás de un flag (DEBUG o ajuste oculto) para poder volver al
editor de producción durante la validación. El flag se retira y se elimina la
ventana demo (`#if DEBUG` de `LitteraRedesignDemoWindow`) cuando el aspecto esté
aprobado — eso cierra la fase 7.

---

## 4. Huecos de preparación que se completan en el cutover

- Biblioteca: la rejilla usa tarjetas de demostración internas; conectar
  `[LitteraUILibraryItem]` inyectado y `actions.onOpen/onToggleFavorite` por id.
- Inspector: campos estáticos; conectar `actions.onSetProperty` a campos
  editables (D53/D55) y rellenar Propiedades/Estadísticas/Navegación desde el
  derivado.
- Paleta: envolver `LitteraCommandRegistry` (contrato §5) para el tab «Todos»;
  tabs Notas/Comandos/Etiquetas con proveedores reales.
- Preferencias: enlazar los controles a las claves `@AppStorage`
  (`LitteraPreferenceKeys`); los ajustes sin backend quedan `.disabled(true)`.
