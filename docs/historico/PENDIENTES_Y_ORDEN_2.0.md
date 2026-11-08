# Littera 2.0 · Qué falta y en qué orden

**Fecha:** 2026-10-27 · **Rama:** `feature/littera-ui-redesign` · **Último commit:** `2e4f7f3`
**Estado:** el rediseño es la única interfaz de la ventana principal (cutover hecho, D65). **Etapas 0 a 6 cerradas:** 293 pruebas en verde, 0 avisos de Swift, versión 2.0.0 y `dist/Littera-2.0.0.dmg`. Falta solo: prueba del DMG por el propietario y su autorización para fusionar la rama. Para añadir funciones: `docs/EXTENDER_LITTERA.md`.

Este documento es la hoja de ruta vigente hasta cerrar Littera 2.0. Sustituye a las «Fases 2–7» de la sesión del 2026-10-26, que están terminadas (ver `SESSION_LOG.md`).

---

## 1. Estado actual en una tabla

| Área | Funciona con datos reales | Falta |
|---|---|---|
| Biblioteca | Lista de documentos del store, pestañas Todos / Recientes / Sin etiquetar con recuentos, búsqueda, ordenación (fecha, nombre, tamaño), cuadrícula y lista, abrir con doble clic, estado vacío | Pestaña «Marcados con estrella» (favoritos), botones atrás/adelante, «···», «info» de la barra |
| Barra lateral | Nombre y tipo de ubicación, «Nuevo documento», «Todas las notas» con recuento, etiquetas reales, engranaje → Ajustes | Notas rápidas, Favoritos, Papelera (deshabilitados), botón de almacenamiento del pie |
| Inspector de la biblioteca | Título, archivo, extracto, ubicación, tamaño, palabras/caracteres, lectura, fechas, «Abrir en editor» | «+ Agregar» etiqueta, «Exportar PDF / HTML» (sin acción), botón cerrar (×) es solo un icono |
| Editor | Editor de producción embebido (Fuente/Visual/Dividido/Vista previa), selector de modos, breadcrumb a la biblioteca, búsqueda desde la barra, exportar, «···» (Guardar, Guardar como, Documentos abiertos, Cerrar) | — |
| Inspector del editor | Propiedades del frontmatter, estadísticas, navegación por encabezados, ancho de lectura | Panel «Diseño del documento»: Fuente / Tamaño / Interlineado sin conectar a las preferencias reales |
| Ventana | Mínimo 960×620 respetado, contenido que encoge (D67), cursor flecha en el cromo | — |
| Pantallas maqueta | Preferencias, paleta y Zen reales (Etapa 5) | — |

### Textos falsos que siguen en pantalla (contradicen D66)
- Barra de estado de la biblioteca: «Modo Solo Lectura: Desactivado» (no existe tal modo).
- Inspector de la biblioteca: «Pulse Espacio para Quick Look nativo» (Espacio no hace nada).
- Pestaña «Modificado» de la barra superior de la biblioteca: duplicado decorativo del menú de orden.

### Defectos vistos y no resueltos
- Barra de estado de la biblioteca: la ruta de la ubicación sale vacía (queda un punto suelto al final).
- Barra lateral dice «En este Mac» aunque Documentos está sincronizado con iCloud: comprobar `folderInfo()` / `isSyncedWithICloud` con la carpeta real.
- Tarjetas con varias etiquetas: los chips se aplastan en «…» / «#…».
- Literales sin localizar: «Inspector» (inspector de la biblioteca), «Biblioteca de Documentos» (breadcrumb), «Personal Vault» (valor por defecto), «Markdown (UTF-8)» y «Copiar» (vista demo).

---

## 2. Orden de trabajo

Cada etapa termina con: compilación en Xcode, pruebas en verde, comprobación en la app real (no suposiciones) y entrada en `SESSION_LOG.md`.

### Etapa 0 · Red de seguridad ✅ (2026-10-27, `837d420`)
Resultado: 252 pruebas existentes en verde (la cifra «177» estaba desfasada); 298 avisos de concurrencia en `Littera/UI/` corregidos (vistas `nonisolated` en un proyecto MainActor); 11 pruebas nuevas de adaptadores; `probar.sh` comprueba la frontera UI/backend. Total: 263.

1. Ejecutar la suite completa: `Tools/probar.sh` (traducciones + XCTest). Línea base anterior: 177/177 (v1.2.2).
2. Clasificar fallos: regresión del cutover (se corrige ya) o prueba que asume la UI 1.0 (se adapta, nunca se borra sin decirlo).
3. Pruebas nuevas para `LitteraUIAdapter`: `workspaceInfo` (recuentos, etiquetas, recientes, iCloud), `uiLibraryItem`, `excerpt`, `uiStatus`, `editorMode`/`writingWidth` (rawValues en español).
4. Prueba de que ningún archivo de `Littera/UI/` importa el backend (contrato `UI_BACKEND_CONTRACTS.md`).

**No se empieza la Etapa 1 sin la suite en verde.**

### Etapa 1 · Honestidad y defectos visibles ✅ (2026-10-27, `154a1a7`)
Resultado: hecho todo lo de abajo, comprobado en la app. «Fuente» se retiró del panel (no hay preferencia real); los iconos de formato aplican el formato real. Quedan como texto fijo, a propósito: «Personal Vault» (solo en datos de demostración) y «Markdown (UTF-8)» (nombre de formato, vista de demostración).

1. Quitar los tres textos falsos de §1.
2. Corregir ruta vacía, «En este Mac» frente a iCloud y chips aplastados.
3. Localizar los literales pendientes (paridad es/en).
4. Conectar el panel «Diseño del documento» a las preferencias reales (`sourceFontSize`, interlineado D41).
5. Dar acción a lo que ya tiene backend: «Exportar PDF / HTML» del inspector de la biblioteca, botón cerrar (×) del inspector.

### Etapa 2 · Validación transversal ✅ (2026-10-27)
Resultado: tema claro revisado pantalla por pantalla; aparecieron y se corrigieron cuatro fallos que no se veían en oscuro o no se habían probado: inspector recortado en Fuente/Visual (segmentado nativo), selector de modos que pisaba «Vista inicial», ⌘K/⇧⌘O muertos en la biblioteca, botón de exportar sin fondo. VoiceOver revisado en código (etiquetas añadidas), **no** recorrido con VoiceOver activado. Capturas en `docs/referencias-visuales/2026-10-27/` (10). `UI_CHECKLIST.md` con sección 2.0.

1. Tema claro en la app real, pantalla por pantalla (nunca se ha validado tras el cutover).
2. VoiceOver en biblioteca, barra lateral e inspectores (hoy solo cubre el cromo del editor).
3. Capturas de referencia nuevas en `docs/referencias-visuales/2026-10-2x/` (claro/oscuro, biblioteca, editor en los cuatro modos, ancho mínimo) y `UI_CHECKLIST.md` reescrito.

### Etapa 3 · Deuda de arquitectura ✅ (2026-10-27, D69)
Resultado: `LitteraCommandHost` envuelve la ventana; el editor solo atiende lo que depende de su estado. Paletas sobre la biblioteca, modo conservado al cambiar de pantalla, ⌘N/⌘O desde la biblioteca muestran el documento. Corregidos además Estado (texto fijo) y Navegación (contaba comentarios) del inspector, y «Estadísticas»/«Propiedades» de la paleta (abrían popovers inexistentes). Pendiente conocido: al pasar al espacio de trabajo se crea un editor nuevo y se pierden selección y desplazamiento del documento (no la posición de lectura por archivo).

Sacar el **centro de mando** de `LitteraEditorView` a una vista anfitriona siempre montada. Incluye retirar el arreglo provisional de la Etapa 2 (el contenedor reenvía ⌘K/⇧⌘O tras mostrar el editor) y llevar las paletas fuera del editor para que se abran también sobre la biblioteca. Hoy el editor va montado a 1×1 invisible bajo la biblioteca solo para recibir ⌘N/⌘O/⌘S/⌘W/⌘F, modos, exportar y paletas. Funciona, pero cualquier cambio de montaje rompe todos los comandos. Requiere la suite en verde antes y después.

### Etapa 4 · Funciones con backend nuevo ✅ (2026-10-27, D70)
Resultado: etiquetas editables, favoritos (lista propia), notas rápidas (carpeta propia), compartir (nativo) y papelera (macOS), comprobados en la app. Atrás/adelante sigue pendiente. **Limitación importante:** la biblioteca muestra los documentos *abiertos*, no el contenido de la carpeta; una nota rápida o un favorito cerrados no aparecen hasta volver a abrirlos. Indexar la carpeta es una decisión aparte (ver Etapa 5).

| Función | Decisión pendiente |
|---|---|
| Etiquetas editables («+ Agregar», chips con ×) | Ninguna: escribe `tags` en el frontmatter con la lógica de D53. Solo falta el adaptador `onSetProperty`. |
| Favoritos / «Marcados con estrella» | ¿Dónde se guarda? (a) clave `favorite: true` en el frontmatter, viaja con el archivo; (b) lista propia de Littera, no toca los documentos. |
| Compartir | `NSSharingServicePicker` nativo; confirmar que se quiere. |
| Notas rápidas | ¿Qué es una nota rápida? (carpeta propia, etiqueta, documentos sin título…) |
| Papelera | ¿Papelera de macOS (mover a la Papelera) o vista propia? Borrar es irreversible para el usuario: necesita decisión explícita. |
| Atrás / adelante | Historial de navegación biblioteca ↔ documentos. |

### Etapa 5 · Pantallas maqueta → reales ✅ (2026-10-27, D71–D74)
Resultado: la biblioteca indexa la carpeta de Ajustes (D71); paleta única del rediseño con registro de comandos (D72); Preferencias del rediseño con registro de páginas (D73); modo Zen real (D74). Arquitectura de registros documentada en `EXTENDER_LITTERA.md`. Pendientes menores resueltos después (D75): atrás/adelante, menús desde el registro, editor conservado al volver de la biblioteca. Queda: recorrido con VoiceOver activado.

### Etapa 6 · Cierre de Littera 2.0 ✅ salvo fusión (2026-10-27)
Resultado: suite completa (293), Release compilado y firmado con los entitlements del sandbox (firma local), prueba de rendimiento del índice (2 000 documentos), ayuda integrada y documentación reescritas para 2.0, versión 2.0.0 (build 12), `dist/Littera-2.0.0.dmg`.

Queda, con el propietario:
1. Instalar el DMG y probar la versión Release (preferencias reales, carpeta de documentos real).
2. Autorizar la fusión de `feature/littera-ui-redesign` en la rama principal y la etiqueta `v2.0.0`.
3. Opcional: recorrido con VoiceOver activado; firma Developer ID y notarización si se distribuye fuera de este Mac.

---

## 3. Reglas de trabajo aprendidas en esta sesión
- **Verificar en la app real antes de dar algo por arreglado.** Tres «arreglos» del recorte de paneles fallaron por suponer la causa; el cuarto se hizo midiendo en pantalla (D67).
- El entorno del asistente compila en el Xcode del propietario (control del Mac, botón Run); la shell del puente es una VM Linux sin Xcode.
- La compilación Debug que usa el propietario es `com.cnyps.es.Littera.debug`; no confundir con copias antiguas de `com.cnyps.es.Littera`.
- Los modificadores `.toolbar*` configuran la ventana, no la vista: no usarlos en vistas embebidas.
