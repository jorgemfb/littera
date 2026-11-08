# Littera · Checklist visual y funcional para validar en Xcode

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
- [ ] `python3 scripts/check_localizations.py` y `plutil -lint` pasan.
- [ ] El documento de ejemplo sigue sin traducirse, y ningún `.md` se altera por elegir idioma.
