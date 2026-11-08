# Littera · Checklist manual de verificación UI 1.0

Estas pruebas requieren ejecutar la aplicación desde Xcode en macOS. No se consideran superadas hasta comprobarlas visualmente.

## Ventana principal

- [ ] La ventana abre con el área de escritura Zen y una sola barra superior nativa.
- [ ] El título del documento está centrado y es pulsable.
- [ ] La búsqueda y el menú `···` aparecen a la derecha.
- [ ] No aparecen pestañas, barra secundaria, selector permanente de modos, biblioteca ni paneles laterales.
- [ ] La barra de estado inferior muestra estado, palabras y modo sin invadir el editor.

## Paletas y teclado

- [ ] `⌘K` abre la paleta de comandos desde el editor.
- [ ] El comando equivalente del menú abre la misma paleta y coloca el foco en la búsqueda.
- [ ] Las flechas cambian la selección, `Enter` ejecuta y `Escape` cierra.
- [ ] `⇧⌘O` abre la paleta de documentos abiertos.
- [ ] El clic en el título abre la misma paleta.
- [ ] La paleta de documentos permite buscar, navegar, identificar el documento activo y cerrar con `Escape`.
- [ ] El foco vuelve al editor después de cerrar cualquiera de las paletas.

## Preferencias y localización

- [ ] `⌘,` abre Configuración con General, Editor, Apariencia, Markdown, Documentos, Sincronización y Atajos.
- [ ] El idioma español y English muestran textos completos y coherentes.
- [ ] Cambiar idioma no modifica el contenido, nombre ni ruta del documento.
- [ ] Los modos mantienen sus identificadores y solo cambia su presentación.
- [ ] Los menús nativos se comprueban también tras cerrar y volver a abrir la aplicación.

## Apariencia y modos

- [ ] El tema Sistema se comporta según macOS.
- [ ] Claro y Oscuro conservan la misma distribución, tipografías, espaciados y controles.
- [ ] La paleta permite cambiar entre Fuente, Visual, Dividido y Vista previa.
- [ ] El cambio de modo no añade controles persistentes ni modifica la barra superior.
- [ ] Se comprueba el redimensionado de la ventana y el foco de teclado en cada modo.

## Evidencia

- [ ] Captura de ventana principal en claro.
- [ ] Captura de ventana principal en oscuro.
- [ ] Capturas de ambas paletas.
- [ ] Capturas de Configuración en español e inglés.
- [ ] Registrar cualquier diferencia frente a `docs/referencias-visuales/` antes de aceptar la línea base.
