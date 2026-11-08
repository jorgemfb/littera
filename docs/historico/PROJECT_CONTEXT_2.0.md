# Littera · Contexto maestro de producto (2.0)

**Versión del documento:** 2026-10-27 · Littera 2.0.0. La versión 1.x de este documento está en `docs/historico/PROJECT_CONTEXT_1.x.md`.

## Qué es
Editor de documentos **Markdown nativo de macOS** (Swift, SwiftUI y AppKit). Los documentos son archivos `.md` normales en UTF-8, guardados donde el usuario decide; no hay formato propietario ni base de datos. Plataforma: macOS; iPadOS/iOS solo tras estabilizar macOS.

**Quién decide:** el propietario (Jorge) aprueba los cambios visuales y de experiencia. Las decisiones vigentes están en `DECISIONS.md` (la última prevalece).

## La ventana (rediseño 2.0, D56–D75)
- Una sola ventana con **biblioteca** como vista inicial (D65) y **espacio de trabajo** al abrir un documento. Mínimo 960×620 en la raíz (D67).
- **Biblioteca** (D71): todos los `.md` de la carpeta de documentos de Preferencias, en segundo plano y con caché; pestañas Todos/Recientes/Marcados con estrella/Sin etiquetar; cuadrícula o lista; inspector con propiedades, etiquetas editables, exportar, compartir y papelera de macOS (D70).
- **Barra lateral** (D60): nuevo documento, todas las notas, notas rápidas (carpeta «Notas rápidas»), favoritos (lista propia de Littera) y etiquetas.
- **Espacio de trabajo**: barra superior de una fila con ruta, selector de modos visible (D62), búsqueda, «···», exportar/compartir, Zen e inspector; editor de producción embebido; inspector con propiedades, diseño del documento (D68), estadísticas y navegación.
- **Paleta** (D72): ⌘K (Todos) y ⇧⌘O (Documentos); pestañas Todos/Documentos/Comandos/Etiquetas; `#etiqueta`.
- **Modo Zen** (D58, D74): presentación sin cromo del mismo espacio de trabajo; ⌃⌘Z, botón, menú o paleta.
- **Atrás/adelante** (D75): ⌘[ ⌘], menú Ir y botones de la biblioteca.
- **Preferencias** (D73): escena `Settings` (⌘,) con el aspecto del rediseño; General, Editor, Apariencia, Markdown, Documentos, Sincronización, Atajos.
- Sin datos inventados ni controles simulados en la app real (D66).

## Los cuatro modos
Fuente (`NSTextView`, sintaxis real), Visual (Markdown editable con aspecto de vista previa; marcadores visibles y atenuados, D27), Dividido (fuente y vista previa sincronizadas) y Vista previa (solo lectura). Cambiar de modo no crea copias ni altera el texto; el modo, la selección y el desplazamiento se conservan al ir a la biblioteca o al Zen.

## Aspecto
Tema del rediseño en `Littera/UI/DesignTokens/LitteraUITheme.swift` (D56/D57): roles de superficie de Stitch con acento **terracota** (`#D78363` claro, `#C5785B` oscuro), tipografía Inter / JetBrains Mono, medidas en `LitteraUITokens`. Claro y oscuro; «Aumentar contraste» refuerza los textos secundarios (D47). Nada de valores sueltos en las vistas.

## Markdown
CommonMark + GFM (tablas, tareas, tachado), frontmatter YAML editable desde el inspector (D53), imágenes locales, enlaces seguros, código con resaltado, diagramas Mermaid, índice automático (`toc`). Exportación a PDF y HTML.

## Documentos y almacenamiento
Varios documentos abiertos por sesión, abrir/guardar/guardar como/cerrar, recientes, restaurar sesión, cambios externos y conflictos sin sobrescritura silenciosa, guardado automático opcional, carpeta de documentos (D64) en el Mac o en iCloud Drive (opcional). Sandbox con marcadores de ámbito de seguridad.

## Arquitectura
- `Littera/UI/`: solo presentación; no importa el backend (lo comprueba `Tools/probar.sh`).
- `Littera/Integration/`: adaptadores y anfitriones que conectan la UI con el store (`LitteraCommandHost`, `LitteraRedesignContainer`, `LitteraUIAdapters`, `LitteraFolderIndex`, `LitteraLibraryServices`).
- Registros extensibles: `LitteraCommandRegistry` (comandos de paleta y menús) y `LitteraPreferencesRegistry` (páginas de Preferencias). **Cómo añadir funciones:** `docs/EXTENDER_LITTERA.md`.
- Localización es/en con paridad comprobada (603 claves); el contenido de los documentos nunca se traduce.

## Estado y verificación
- Pruebas: `Tools/probar.command` (localización, frontera UI/backend y XCTest). Estado y orden: `PENDIENTES_Y_ORDEN.md`; historial: `SESSION_LOG.md`.
- Instalador: `Tools/crear-dmg.command` (Release + DMG en `dist/`).
- Regla de trabajo: todo cambio se verifica en la app real antes de darlo por hecho.
