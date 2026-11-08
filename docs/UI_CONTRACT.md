# Contrato de interfaz · Littera v1

**Vigente desde:** 2026-11-07 (D76–D80), actualizado el 2026-11-08 (D85, D88). Sustituye a `docs/historico/UI_CONTRACT_2.0.md`. Describe la interfaz de la 1.0.0: la simplificación está aplicada.

## Ventana

```text
[● ● ●]                ● informe.md •             [≡] [⌕] [···]
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│              # Título                                        │
│              Texto del documento en una columna centrada…    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
 (barra de estado: oculta por omisión, activable en Ajustes → General)
```

Dividido:

```text
[● ● ●]                ● informe.md •             [≡] [⌕] [···]
┌────────────── Fuente ───────────┬────────── Vista previa ───┐
│ # Título                        │  Título                   │
│ Texto **Markdown**…             │  Texto Markdown…          │
└─────────────────────────────────┴───────────────────────────┘
```

## Elementos y dónde viven

| Elemento | Lugar |
|---|---|
| Documento activo | Título centrado de la barra nativa; el punto `•` indica cambios sin guardar |
| Documentos abiertos | Clic en el título o `⇧⌘O` (paleta) |
| Modos Fuente / Dividido / Vista previa | `⌘1`–`⌘3`, menú Visualización, paleta `⌘K` |
| Buscar y reemplazar | Lupa o `⌘F` (popover); `⌥⌘F` reemplazar |
| Guardar, Guardar como, Cerrar, Exportar | Menú Archivo, `···` y paleta |
| Propiedades del frontmatter | Botón `[≡]` de la barra (a la izquierda de la lupa), `···` y paleta |
| Estadísticas, anchura del texto (una para los tres modos, D85), máquina de escribir | `···` y paleta |
| Formato y edición asistida | Paleta y atajos configurables |
| Preferencias | `⌘,`: General, Editor, Atajos |

## Reglas
1. Una sola barra superior **nativa**, de una fila, sin cápsulas propias, segunda fila, pestañas ni selector de modos.
2. Sin biblioteca, barra lateral, inspector, modo Zen ni paneles permanentes.
3. Colores y medidas desde un único sistema de tema; claro, oscuro y sistema; «Aumentar contraste» y «Reducir movimiento» respetados (D47).
4. Nada simulado en la app real (D66): un control sin función se oculta o se deshabilita.
5. Funciones nuevas: se **registran** como comandos o páginas de Preferencias (`EXTENDER_LITTERA.md`) en lugar de añadir botones sueltos.
6. Cambios visuales: con capturas en claro y oscuro y aprobación del propietario; referencias en `docs/referencias-visuales/`.
