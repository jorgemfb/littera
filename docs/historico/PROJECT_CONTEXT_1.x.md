# Littera · Contexto maestro de producto

**Versión del documento:** 2026-10-26 · Reconciliado tras el cutover del rediseño 2.0.

> **Aviso de vigencia (2026-10-26).** Desde el cutover (D65) la ventana principal es el **rediseño 2.0** basado en Google Stitch: biblioteca como vista inicial, barra lateral (D60), inspector (D59, D68) y selector de modos visible (D62). Por eso las secciones «Experiencia central aprobada» y «El aspecto aprobado» describen la **UI 1.0** y quedan como historia: donde contradigan a D56–D68, mandan estas. La filosofía local-first está retirada (D63). Estado y orden de trabajo vigentes: `docs/PENDIENTES_Y_ORDEN.md`.

## Qué es
Littera es un editor de documentos **Markdown**, completamente **nativo en macOS** (Swift + SwiftUI + AppKit cuando corresponda), con una experiencia de escritura de estilo **Zen permanente**, minimalista, cuidada y elegante. Se diseña primero la interfaz y después Codex implementa funcionalidad. Se prioriza que el usuario comprenda y controle sus archivos y que el programa siga funcionando sin Internet.

**Plataformas:** macOS ahora; iPadOS e iOS **más adelante, solo tras estabilizar macOS**. La arquitectura puede prever su ampliación, sin desarrollarlas prematuramente.

**Quién decide:** el diseño, los cambios visuales y la experiencia de usuario se revisan en ChatGPT con el usuario. Codex implementa funcionalidad, conexiones y pruebas respetando los contratos del diseño. La interfaz puede evolucionar, pero solo mediante cambios pedidos, nunca como efecto lateral de una tarea funcional.

## Experiencia central aprobada
- Ventana principal de macOS, una **sola barra de título/herramientas nativa**, sin otra fila inventada. Integración SwiftUI `ToolbarItem` y estilo `unifiedCompact` donde sea compatible.
- Controles nativos del sistema a la izquierda; **título de documento centrado, pulsable**; icono de búsqueda y menú de tres puntos `···` a la derecha. No flecha desplegable visible junto a `···`; tampoco flecha extra junto al título.
- **No pestañas para archivos abiertos**, ni biblioteca de documentos, barra lateral, inspector ni selector de vistas visible en el encabezado.
- Documento centrado horizontalmente, márgenes amplios, anchura configurable, tipografía editorial y componentes visuales Markdown. Modo Zen no es un interruptor aparte: **es toda la experiencia principal**.
- Estado inferior discreto/flotante: estado, número de palabras, modo activo (y futuras estadísticas reales); no barra de herramientas auxiliar invasiva.
- **Paleta de comandos** `⌘K` para cambiar entre Fuente, Visual, Dividido, Vista previa; formato, inserción, navegación, documentos, exportación y herramientas.
- **Paleta de documentos** al hacer clic en el título o `⇧⌘O`: listado de documentos abiertos, búsqueda por nombre/ruta, indicador de activo y de cambios, flechas, Enter, Escape. Un documento visible a la vez; múltiples sesiones sin pestañas.
- **No panel flotante exclusivo para formato**: los formatos se registran como comandos en `⌘K`. La paleta es extensible; registro de comandos aislado de su representación visual.
- Menú `···` nativo y menú principal macOS conservados, con funciones y atajos congruentes con las paletas.

## Los cuatro modos
- **Fuente**: editar sintaxis Markdown real en un `NSTextView` nativo (TextKit), con Deshacer, composición IME/teclas muertas y posición por documento.
- **Visual**: edición del Markdown real con el aspecto de la Vista previa. Los marcadores (`#`, `**`, `` ` ``, `>`, `-`, `[x]`, fences, `|`) quedan **siempre visibles y atenuados** (decisión D27). Comparte editor, Deshacer y posición con Fuente.
- **Dividido**: Fuente a un lado, representación real sincronizada al otro; ambos comparten modelo documental.
- **Vista previa**: representación de lectura sin edición directa.
- Cambiar de modo **no crea copias**, no pierde datos, no altera las marcas Markdown por accidente.

## El aspecto aprobado
La inspiración estructural vino de capturas de «MarkFlow» (editor Zen, paleta de comandos y antiguas vistas), pero Littera tiene **identidad propia**. Diseño cálido, suave, bajo contraste aparente pero con legibilidad accesible; **no fondos blanco/negro puros**, botones negros agresivos, divisores duros, exceso de tarjetas ni elementos decorativos innecesarios. Tipografía Apple; SF Mono para código, SF Pro para cuerpo y New York/serif para títulos como intención visual inicial.

Paleta **real en código** (`Littera/Appearance/LitteraThemePalette.swift`), tomada de las capturas de referencia del 2026-10-22 (decisión D28):

| Token | Claro | Oscuro |
|---|---|---|
| canvas | `#FCFCFB` | `#151515` |
| chrome | `#FBFBF9` | `#111111` |
| secondary | `#F0F0EF` | `#212121` |
| control | `#F0F0EF` | `#262626` |
| selected | `#EDECE9` | `#353535` |
| line | `#E7E7E7` | `#313130` |
| primaryText | `#0B0B0B` | `#F0EFEC` |
| secondaryText | `#898782` | `#898782` |
| accent | `#D78363` | `#C5785B` |

Los controles nativos (interruptores, selectores) conservan el acento del sistema. El resaltado de sintaxis usa `LitteraSyntaxPalette` (estilo One Dark / One Light).

El diseño está centralizado en `LitteraDesignSystem.swift`; paletas comparten `LitteraPaletteFrame.swift`. El título y los iconos **no dibujan cápsulas personalizadas** en barra superior. La barra inferior conserva su tratamiento discreto propio. No imponer la misma forma geométrica a todos los componentes: **coherencia visual no significa encapsular todo**.

## Markdown que debe representar
CommonMark como base, extensiones GitHub Flavored Markdown útiles (tablas, listas de tareas, tachado), y evaluación de frontmatter YAML, imágenes, hipervínculos, listas, citas, bloques de código con resaltado. Citas con una línea vertical fina, fondo suave, tipografía serif/cursiva en el prototipo; NO agregar automáticamente comillas o autor que no existan en el contenido. Fuente y representación deben coincidir semánticamente.

En la versión 9 **`LitteraSampleDocument` contiene contenido renderizado fijo**; el texto fuente de ejemplo está separado. No inferir que el motor Markdown ya existe. Conectar primero Fuente -> parser -> Vista previa real, luego Dividido y al final Visual editable robusto.

## Documentos y almacenamiento
- Documentos `.md` normales UTF-8, abiertos desde Finder y guardados **donde elija el usuario** (D63); por defecto, la carpeta Documentos (D64). Sin formato propietario obligatorio ni base de datos como único almacén.
- Debe haber múltiples documentos abiertos a nivel de sesión, con documento activo y cambios independientes; preservar cursor/scroll/Undo por documento donde sea técnicamente posible.
- Abrir, crear, guardar, guardar como, cerrar (⌘W), Abrir reciente, restaurar sesión y detección de cambios externos implementados (D36, D37).
- **iCloud Drive opcional**, integrado mediante APIs Apple de documentos/archivos; iCloud no es requisito de arranque ni de escritura. Archivo remoto no descargado requiere detección/descarga explícita y tratamiento de offline. Concurrencia/conflictos sin sobrescritura silenciosa. No mover archivos preexistentes al elegir iCloud sin consentimiento. No servidor propio obligatorio ni CloudKit impuesto como almacén de Markdown.

## Preferencias
Ventana nativa con categorías **General, Editor, Apariencia, Markdown, Documentos, Sincronización, Atajos**. Apariencia Sistema/Claro/Oscuro **solo** en Ajustes. General incluye idioma y vista inicial; Editor controla anchura y fuente; almacenamiento y sincronización se presentan con estados pendientes reales, no controles falsamente operativos. `LitteraPreferences.swift` contiene las claves estables. En UI 9 se conectaron solo las preferencias explícitamente descritas en README; verificar con Xcode.

## Internacionalización
- **Español como idioma predeterminado**, inglés disponible; elección en **Configuración/Preferencias → General → Idioma de la interfaz**.
- Catálogos `Localization/es.lproj/Localizable.strings`, `Localization/en.lproj/Localizable.strings`, resolución en `LitteraLocalization.swift`, claves estables separadas de vistas y acciones.
- Idiomas nuevos se añaden con archivo `<idioma>.lproj/Localizable.strings`, localización del target Xcode y prueba de paridad. No crear `switch` de idiomas en todas las vistas.
- Traducir textos UI y menús de macOS cuando sea viable, contemplando que menús nativos pueden precisar reinicio. **Jamás traducir ni modificar automáticamente el contenido de documentos, rutas y nombres de archivos**.
- No alterar raw values/identificadores persistidos al traducir etiquetas.

## Estado real del código (2026-10-26, rama `feature/littera-ui-redesign`)
- Versión 1.2.2 + rediseño 2.0 sin publicar. Último commit de la sesión: `60090e4`.
- Interfaz: el rediseño (`Littera/UI/`, solo presentación) alimentado por el store real a través de `Littera/Integration/` (`LitteraUIAdapters.swift`, `LitteraRedesignContainer.swift`). El editor de producción va embebido sin cromo y sigue siendo el centro de mando de los comandos (deuda: extraerlo).
- Localización: 568 claves es/en con paridad.
- Pruebas: 177 XCTest en la v1.2.2; **sin ejecutar desde el cutover** (Etapa 0 de `PENDIENTES_Y_ORDEN.md`).

## Estado del código anterior (2026-10-22, rama `feature/markdown-sync`)
- Proyecto Xcode real, macOS 27, sandbox con archivos elegidos por el usuario y `Littera.entitlements` (bookmarks de ámbito de app). Debug y Release compilan; 34 pruebas XCTest.
- **Documentos**: nuevo, abrir, guardar, guardar como, varios documentos en sesión, protección de cambios sin guardar. Arranca con un documento vacío. Pendiente: cerrar, recientes, restaurar sesión, cambios externos/conflictos, autoguardado.
- **Motor Markdown**: `swift-markdown 0.8.0`; análisis en segundo plano por versión (`LitteraMarkdownDerivedDocument`), índice UTF-8/UTF-16, render nativo SwiftUI. Encabezados, párrafos, énfasis, tachado, código en línea, enlaces seguros, listas, tareas con casilla, citas, separadores, tablas GFM, bloques de código con resaltado (resaltador nativo propio) y botón Copiar, imágenes locales con acceso por carpeta. Pendiente: frontmatter YAML, HTML incrustado.
- **Modos**: los cuatro funcionan. Posición de lectura semántica por documento, compartida entre modos y conservada entre sesiones. Dividido sincroniza el desplazamiento en ambos sentidos sin pasar por SwiftUI.
- **Paletas**: `⌘K` y `⇧⌘O` con navegación por teclado, trackpad y puntero separados. Los comandos de formato funcionan en Fuente, Visual y Dividido (un paso de Deshacer cada uno; `⌘B`, `⌘I`, `⇧⌘K`) y se deshabilitan en Vista previa.
- **Búsqueda**: la lupa abre el popover existente de UI 1.0, ahora operativo (incremental, sin distinguir mayúsculas ni acentos, Intro/⇧Intro, recuento). Menú Edición → Buscar con `⌘F`, `⌥⌘F` (reemplazar en el mismo popover), `⌘G`, `⇧⌘G`, `⌘E`. Deshabilitada en Vista previa.
- **Pendiente general**: resaltado en Fuente, exportación, modo máquina de escribir, interlineado y ortografía, iCloud Drive, medición con Instruments, accesibilidad, regresión visual con capturas nuevas.

## Expectativas y forma de colaboración
El usuario y ChatGPT revisan y aprueban cambios visuales y decisiones UX. Codex trabaja sobre tareas acotadas, comunica riesgos y demuestra progreso funcional sin inventar características. Las limitaciones se declaran sin maquillar. **Nunca reescribir todo el proyecto porque se pida una función pequeña**.
