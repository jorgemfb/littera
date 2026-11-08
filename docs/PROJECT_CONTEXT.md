# Littera · Contexto maestro de producto (v1)

**Versión del documento:** 2026-11-07 · Littera v1 (simplificación, D76–D80). Las versiones anteriores están en `docs/historico/PROJECT_CONTEXT_1.x.md` y `docs/historico/PROJECT_CONTEXT_2.0.md`.

## Qué es
Editor de documentos **Markdown nativo de macOS** (Swift, SwiftUI y AppKit). Los documentos son archivos `.md` normales en UTF-8, guardados donde el usuario decide; no hay formato propietario ni base de datos. **Local-first**: funciona sin Internet ni Apple ID; iCloud Drive es opcional y nunca mueve archivos (D79). Plataforma: macOS; iPadOS e iOS solo tras estabilizar macOS.

Principio: *Littera debe sentirse como un editor Markdown nativo, precioso y calmado: abrir un archivo, escribir, previsualizar, buscar y guardar. Nada más debe estorbar.*

**Quién decide:** el propietario (Jorge) aprueba los cambios visuales y de experiencia. Las decisiones vigentes están en `DECISIONS.md` (la última prevalece).

## Estado
**1.0.1** (build 15, etiqueta local `v1.0.1`, 2026-11-08), en `main`; la 1.0.0 es `v1.0.0`. La simplificación v1 está aplicada (bloques A–D de la auditoría del 2026-11-07 y decisiones D76–D88). Las pruebas manuales que faltan y la siguiente iteración están en `PENDIENTES_Y_ORDEN.md`.

## La ventana (D76)
- Una ventana con el documento activo. Barra superior **nativa** de una fila: título centrado y pulsable (documentos abiertos) y, a la derecha, propiedades del frontmatter, lupa y `···`.
- Abrir: `⌘O`, Abrir reciente, Finder o arrastrar. Crear: `⌘N`. Varios documentos abiertos por sesión, sin pestañas.
- Paleta `⌘K`: comandos y documentos abiertos o recientes (D80).
- Barra de estado oculta por omisión (D78). Preferencias en tres páginas: General, Editor y Atajos (D80).

## Los tres modos (D77)
Fuente (`NSTextView` con el resaltado de D39), Dividido (Fuente y Vista previa sincronizadas) y Vista previa (solo lectura). Cambiar de modo no crea copias ni altera el texto; se conservan la selección y la posición de lectura (D33).

## Markdown
CommonMark + GFM (tablas, tareas, tachado), frontmatter YAML editable desde las propiedades de `···` (D53–D55), imágenes locales con carpeta autorizada (D30), enlaces seguros, código con resaltado nativo (D29), diagramas Mermaid nativos (D48), índice automático (`toc`). Exportación a PDF y HTML (D43). Sin puntuación tipográfica automática (D40, D51).

## Documentos y almacenamiento
Abrir, guardar, guardar como y cerrar; recientes; restaurar sesión; cambios externos y conflictos sin sobrescritura silenciosa (D37); guardado automático opcional (D49); copias de recuperación tras un cierre inesperado; iCloud Drive opcional con coordinación de archivos y conflictos (D50). Sandbox con marcadores de ámbito de seguridad. Guardar nunca descarta ediciones ni metadatos sin que el usuario lo sepa.

## Arquitectura (estado actual)
- `Littera/Documents/`: store de documentos, archivos, recuperación e iCloud.
- `Littera/Markdown/`: análisis (swift-markdown), render nativo de la Vista previa, Mermaid.
- `Littera/Editor/`: editor de texto, coordinación de desplazamiento, cromo nativo de la ventana.
- `Littera/CommandPalette/` y `Littera/Settings/`: registro único de comandos (D72) y de páginas de Preferencias (D73), que se mantienen como mecanismo.
- `Littera/UI/` e `Littera/Integration/`: interfaz 2.0, que se retira con la simplificación.
- Localización es/en con paridad comprobada; el contenido de los documentos nunca se traduce.

## Verificación
- Pruebas: `Tools/probar.command` (localización, frontera UI/backend y XCTest). Rendimiento: arnés A/B en Release con corpus sintético (ver `AGENTS.md`).
- Instalador: `Tools/crear-dmg.command` (Release + DMG en `dist/`).
- Regla de trabajo: todo cambio se verifica en la app real antes de darlo por hecho.
