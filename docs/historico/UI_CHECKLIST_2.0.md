# Littera · Checklist visual y funcional

> **Nota 2026-11-07.** Las casillas de abajo se marcaron el 2026-10-27 sobre la interfaz 2.0, que se retira con Littera v1 (D76–D80); la checklist de v1 se escribirá en el bloque C. La cifra «263 pruebas, 0 fallos» ya no era cierta: la auditoría del 2026-11-07 encontró 17 casos en rojo. Tras el bloque A la suite tiene 311 pruebas, 0 fallos y 9 omitidas (`docs/PENDIENTES_Y_ORDEN.md`).

## Littera 2.0 (rediseño) — estado al 2026-10-27

Rama `feature/littera-ui-redesign`. Capturas de referencia en `docs/referencias-visuales/2026-10-27/` (retiradas el 2026-11-08 al publicar el repositorio: mostraban datos personales) (claro y oscuro: biblioteca, Fuente, Visual, Dividido, Vista previa; ventana a ~1170 pt, documento `prueba.md`). Leyenda: [x] comprobado en la app real · [ ] pendiente.

### Ventana
- [x] Semáforos visibles; barra del rediseño sin toolbar nativa duplicada.
- [x] Mínimo 960×620 respetado; nada se recorta al estrechar (D67).
- [x] Puntero en flecha en todo el cromo; I-beam solo sobre el texto.

### Biblioteca (vista al abrir, D65)
- [x] Datos reales: nombre y tipo de ubicación (iCloud Drive), recuentos, etiquetas, ruta en la barra de estado.
- [x] Pestañas Todos / Recientes / Sin etiquetar; «Marcados con estrella» deshabilitada (sin favoritos).
- [x] Búsqueda, orden (fecha, nombre, tamaño), cuadrícula y lista, doble clic abre el documento.
- [x] Etiquetas de las tarjetas enteras o «+N», nunca aplastadas.
- [x] Inspector: datos reales, ruta truncada por el medio con tooltip, × cierra, «Exportar PDF / HTML» es un menú.
- [x] `⌘K` y `⇧⌘O` desde la biblioteca muestran el editor con la paleta abierta.
- [ ] «Exportar PDF / HTML» del inspector hasta el panel de guardado.

### Editor
- [x] Selector de modos refleja el modo real del editor y respeta Ajustes → General → Vista inicial.
- [x] Cuatro modos con el inspector entero (en Fuente y Visual se salía por la derecha).
- [x] Breadcrumb «Littera» vuelve a la biblioteca.
- [x] Búsqueda desde la barra (sin abrir un segundo cuadro).
- [x] Diseño del documento: tamaño e interlineado reales (mismas preferencias que Ajustes → Editor); iconos de formato aplican el formato (desactivados en Vista previa).

### Tema
- [x] Claro y oscuro: biblioteca y los cuatro modos sin textos ilegibles ni controles con estilo ajeno.
- [ ] Aumentar contraste en ambos temas.

### Accesibilidad (VoiceOver)
- [x] Etiquetas en los botones de icono de la biblioteca (barra, vista, limpiar búsqueda, orden), barra lateral (Ajustes) e inspectores (cerrar, formato).
- [x] Tarjetas y filas de la biblioteca como un solo elemento, con acción «Abrir en Editor».
- [ ] Recorrido real con VoiceOver activado (solo revisado en código).

### Compilación y pruebas
- [x] `Tools/probar.command`: traducciones (paridad es/en), frontera UI/backend y XCTest — 263 pruebas, 0 fallos, 0 avisos de Swift.

---

## Littera 1.x (UI 1.0 y motor) — histórico
Estado al 2026-10-22 (rama `feature/markdown-sync`). Capturas de referencia actuales en `docs/referencias-visuales/2026-10-22/` (claro y oscuro: Visual, Fuente, Dividido, Vista previa, paleta de comandos y Ajustes → Apariencia). Las capturas de UI 1.0 siguen en `docs/referencias-visuales/` como referencia histórica.

Leyenda: [x] comprobado en la app esta sesión · [ ] pendiente de comprobar.

## Ventana y barra superior
- [x] Una sola fila nativa: semáforo, título centrado pulsable, lupa y `···`; sin pestañas ni selector de modos.
- [x] Título con punto de acento; `•` adicional si hay cambios sin guardar.
- [x] Barra de estado: estado (Sin guardar / Cambios sin guardar / Guardado), palabras y modo.
- [x] Icono de la app en el Dock y en «Acerca de».

## Modos
- [x] Visual: marcadores atenuados, tipografía de la Vista previa, citas en serif cursiva, código con resaltado, tablas, tareas, frontmatter atenuado con YAML resaltado.
- [x] Fuente: resaltado v2 (D39, aprobado): títulos más grandes en negrita monoespaciada, marcadores estructurales en acento, citas en cursiva atenuada, código en línea con color y fondo.
- [x] Dividido: Fuente + Vista previa sincronizadas.
- [x] Vista previa: sin frontmatter; cita con márgenes simétricos (como la referencia aprobada); bloque de código con «Copiar»; tablas.
- [x] Posición de lectura compartida entre modos y entre sesiones.

## Paletas y teclado
- [x] `⌘K` comandos y `⇧⌘O` documentos: flechas, Intro, Esc, puntero sin cambiar la selección.
- [x] Comandos de formato operativos (deshabilitados en Vista previa); un paso de Deshacer cada uno.
- [x] Atajos personalizables en Ajustes → Atajos; menús, paleta y editor los respetan.

## Búsqueda
- [x] Lupa / `⌘F`: búsqueda incremental sin mayúsculas ni acentos, Intro/⇧Intro, recuento.
- [x] `⌥⌘F`: reemplazo en el mismo popover; Reemplazar todo en un paso de Deshacer.

## Documentos
- [x] Abrir, Abrir reciente, Guardar, Guardar como, Cerrar (`⌘W`), documento vacío al cerrar el último.
- [x] Cambios externos: recarga silenciosa o elección de versión; nunca se sobrescribe en silencio.
- [x] Restaurar sesión al arrancar.
- [ ] «Abrir documento…» al iniciar sin documentos (Ajustes → General).
- [ ] Archivo borrado fuera de Littera (cubierto por XCTest).

## Editor
- [x] Interlineado Compacto/Normal/Amplio (Visual, Fuente, Vista previa).
- [x] Máquina de escribir: línea centrada y resto atenuado.
- [x] Corrección ortográfica activable.
- [x] Sin sustitución automática de rayas ni comillas.

## Exportación
- [x] PDF A4 con el aspecto de la Vista previa, incluidas imágenes locales.
- [x] HTML autónomo con CSS de Littera.

## Accesibilidad
- [x] Lupa, `···`, restablecer atajo y barra de estado con etiquetas de VoiceOver; iconos decorativos ocultos.
- [x] «Reducir movimiento» desactiva la animación de las paletas.
- [x] «Aumentar contraste» oscurece el texto secundario (#898782 sobre el fondo claro da ≈3,6:1; con contraste aumentado ≈6,5:1).
- [ ] Recorrido completo con VoiceOver (no se puede automatizar desde aquí).
- [ ] Tamaños de ventana mínimos y Texto grande del sistema.

## Localización
- [x] Paridad es/en de todas las claves (267).
- [ ] Revisión completa en inglés tras reiniciar con English.

## Compilación
- [x] Debug y XCTest (92/92).
- [x] Release con `Littera.entitlements` (compilado con Product → Profile, que usa la configuración Release, y ejecutado bajo Instruments).

---

## Histórico (checklists de UI 1.0)


## Principal (sin regresiones respecto a iteración 7)

- [ ] Barra superior nativa, **una fila**: controles macOS, título centrado, búsqueda y `···`; sin selector de modos, tabs ni fondo/cápsulas manuales.
- [ ] Modo claro/oscuro con fondos suaves y contraste legible; verificar tema Sistema.
- [ ] `⌘K`: búsqueda con foco, flechas, Enter y Escape; abrir desde menú hace lo mismo.
- [ ] `⇧⌘O` y clic en título: paleta de documentos con los mismos controles de teclado.
- [ ] Los comandos de formato se ven pero están deshabilitados, no hay panel flotante de formato.
- [ ] La barra de estado y la representación de cita no cambian de aspecto.

## Preferencias (iteración 8)

- [ ] `⌘,` abre Preferencias. Ventana ~870 × 620; sidebar clara con General, Editor, Apariencia, Markdown, Documentos, Sincronización y Atajos.
- [ ] Navegación por sidebar, clic y teclado, sin recortes al reducir tamaño.
- [ ] Buscar categoría filtra secciones, no simula búsqueda global de ajustes.
- [ ] Apariencia Sistema/Claro/Oscuro actualiza también la ventana del editor. No aparece selector de tema fuera de Preferencias.
- [ ] General → Vista inicial se guarda y se aplica al abrir una ventana nueva.
- [ ] Editor → tamaño en Fuente cambia el tamaño del texto monoespaciado.
- [ ] Editor → anchura de lectura cambia el ancho del documento, incluido desde menú `···`.
- [ ] Los avisos «Pendiente» son visibles para opciones no implementadas.
- [ ] Documentos aclara `.md` / `UTF-8`; no finge guardar ni elegir carpetas.
- [ ] Sincronización indica local como predeterminado y **iCloud Drive pendiente**, sin interruptor operativo ficticio.
- [ ] Las vistas conservan diseño consistente con el editor, incluso al cambiar tema.

## Futuro: pruebas que tendrá que pasar Codex

- [ ] Abrir/guardar `.md` real, cambios pendientes y conflictos resueltos sin sobrescribir.
- [ ] Modo Fuente y visual sincronizados con el contenido, no con una maqueta.
- [ ] Acciones de formato y de archivo habilitadas solo cuando funcionen.
- [ ] Archivos locales editables sin Apple ID ni Internet.
- [ ] iCloud Drive opt-in, descarga offline y resolución de conflictos comprobados antes de habilitar el selector.

## Validación local de esta entrega

`swiftc -frontend -parse` sobre todos los `.swift` pasó. **No disponible Xcode/macOS SDK** para compilar UI o realizar captura/ejecución real; eso debe probarse en Mac antes de congelar UI 1.0.

---

## Localización, iteración 9

- [ ] En Preferencias → General aparece **Idioma de la interfaz** con Español y English.
- [ ] Cambiar a English actualiza las 7 secciones y los rótulos visibles sin borrar ni reiniciar el editor.
- [ ] Volver a Español recupera todos los textos de los controles.
- [ ] `⌘K`: comandos y formatos traducidos; flechas, Enter y Esc siguen funcionando.
- [ ] `⇧⌘O` y clic en título: títulos de paleta traducidos; los nombres de archivo no cambian.
- [ ] La barra de estado muestra «palabras» / «words» correctamente.
- [ ] Los modos Fuente/Visual/Dividido/Vista previa conservan sus IDs y comportamiento al cambiar idioma.
- [ ] Los menús principales File/Edit/View/Window/Help muestran títulos traducidos tras elegir idioma; comprobar también después de relanzar la app.
- [ ] Verificar las entradas nativas de los menús del sistema y las localizaciones de Xcode. No asumir que los menús internos se actualizan sin reinicio.
- [ ] Verificar el diseño claro y oscuro tras cambiar idioma. No aparecen botones ni barras adicionales.
- [ ] `swift Tools/CheckLocalizations.swift` y `plutil -lint` pasan.
- [ ] El documento de ejemplo sigue sin traducirse, y ningún `.md` se altera por elegir idioma.
