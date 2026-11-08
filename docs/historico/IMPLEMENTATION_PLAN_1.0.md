# Plan de ejecución para Codex tras UI 1.0 / iteración 9

**No construir todo de golpe.** Cada tarea debe terminar con compilación Xcode, pruebas apropiadas, lista de archivos modificados y estado funcional declarado.

## Fase 0 · Integración y línea base (PRIMERA TAREA)
1. Inspeccionar el proyecto/repo **real**, destino de despliegue, firma, entitlements y estado Git. No crear otro proyecto si ya existe.
2. Integrar los 24 archivos `.swift`, las variantes de `Localizable.strings` y la documentación de esta entrega, evitando tipos duplicados.
3. Compilar Debug y corregir errores de integración mínimos.
4. Verificar tema claro/oscuro, barra nativa, búsqueda, `···`, ⌘K, ⇧⌘O, navegación teclado, Preferencias e idiomas.
5. Generar capturas de referencia de la versión real; comprobar que la UI sigue el contrato.
6. Commit/etiqueta de línea base aprobada con consentimiento del usuario. **No implementar aún motor Markdown.**

## Fase 1 · Documentos locales reales
- Modelos por documento con URL/identidad estable, contenido `.md`, cambios, foco/cursor/Undo según API del motor futuro.
- Nuevo, Abrir desde Finder, Guardar, Guardar como, Cerrar, recents, múltiples sesiones sin pestañas; seguridad de acceso en sandbox cuando proceda.
- Guardado atómico, coordinación y protección contra sobrescritura/conflictos; restauración de documento cuando sea razonable.
- Sustituir demos en memoria de la paleta de documentos. Deshabilitar acciones no conectadas.
- Pruebas: cierre con cambios, errores de permisos, UTF-8, documentos grandes, dos archivos con mismo nombre, recuperación.

## Fase 2 · Parser y vista previa real
- Evaluar `swift-markdown`/CommonMark + GFM según necesidad real; arquitectura parser/AST/renderer desacoplada de edición.
- Renderizar encabezados, párrafos, énfasis, listas, citas, enlaces, imágenes, tareas, tablas y bloques de código con **componentes nativos** según estilo aprobado.
- Sustituir `LitteraSampleDocument` por render del Markdown real. No fabricar cita/autor/cita tipográfica ausentes.
- Sincronizar Fuente y Vista previa, después Dividido; una sola fuente de verdad.
- Pruebas de sintaxis, caracteres Unicode, texto mal formado, Markdown largo y rendimiento.

## Fase 3 · Formato desde el registro de comandos
- Implementar negrita, cursiva, tachado, encabezados, citas, listas, enlaces, imágenes, tablas y bloques de código de forma incremental.
- Operar sobre selección o cursor, aplicar Undo/Redo, preservar selección y desplazamiento; devolver foco al editor tras ejecutar comando.
- Mostrar el comando solo si tiene sentido, deshabilitar si no está listo.

## Fase 4 · Editor Visual realmente editable
- Resolver selección, mapeo entre fuente Markdown y contenido representado, IME, composición, cursor, portapapeles, bloques y undo/redo nativos (AppKit/TextKit donde convenga).
- Los cuatro modos deben conservar documento y ediciones. Evitar roundtrips con pérdida de sintaxis.
- Pruebas de edición visual compleja, tablas/tareas/enlaces, pegar contenido, cambios concurrentes entre modos.

## Fase 5 · Preferencias y productividad
- Conectar preferencias pendientes, autocorrección, tipografías, exportación PDF/HTML, búsqueda/reemplazo, modo máquina de escribir opcional, estadísticas reales y estado de cambios.
- Idiomas: añadir claves nuevas a `Localizable.strings` en `es` y `en`; comprobar paridad con `swift Tools/CheckLocalizations.swift`.

## Fase 6 · iCloud Drive opt-in
- Elegir ubicación local o iCloud Drive con autorización, capacidades/entitlements correctas, File Coordination, placeholders no descargados, errores offline y conflictos.
- **Nunca** mover documentos existentes automáticamente al activar la opción. No impedir uso local sin conexión.
- Pruebas manuales entre dispositivos, colisiones y recuperación; solo entonces habilitar la opción en Preferencias.

## Fase 7 · Estabilización y entrega
- Revisar accesibilidad, rendimiento, regresión visual, consumo de memoria, integridad documental y localización en Xcode.
- iPadOS/iOS **fuera** de esta fase: primero macOS final y estable.

## Criterio de acabado por tarea
Compila y se prueba en macOS; las interfaces no cambian salvo lo aprobado; no simular éxito; documentación actualizada; notas para retomar conversación en `docs/SESSION_LOG.md`.
