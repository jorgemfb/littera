# Bitácora de trabajo Littera

Usar esta plantilla para **cada sesión de Codex o de diseño en ChatGPT**. Es el mecanismo de continuidad entre conversaciones: no depender de memoria implícita.

## Estado inicial, 2026-10-21
- Base entregada: UI 1.0 / iteración 9.
- Siguiente tarea: **Fase 0, compilar/integrar/verificar la interfaz en el proyecto Xcode real**.
- Hecho en la maqueta: barra superior Zen, dos paletas, comandos de formato deshabilitados, preferencias visuales, traducciones es/en.
- Aún pendiente: archivos reales, parser/renderer real, editor Visual, iCloud, exportación, pruebas Xcode.
- Restricciones: `AGENTS.md`, `PROJECT_CONTEXT.md`, `DECISIONS.md`, `UI_CONTRACT.md`.

### 2026-10-21 · Fase 0 · preservación, integración y diagnóstico inicial
- Objetivo: preservar el checkout, establecer una línea base Git separada y diagnosticar la compilación sin implementar funcionalidad.
- Rama/commit: `chore/ui-1-0-integration` · `6b246d5 chore: integrate Littera UI 1.0 baseline`; validación en `chore/project-validation`.
- Archivos afectados: copia externa `/tmp/Littera-preservation-2026-10-21`; integración de la UI, documentación, localizaciones, `Tools/CheckLocalizations.swift` y `.gitignore`; configuración del target en `Littera.xcodeproj/project.pbxproj` para macOS exclusivamente.
- Cambios y decisiones: los borrados de `Littera/Assets.xcassets` se conservaron fuera del commit porque el target aún referencia `AppIcon` y `AccentColor`; no se confirmaron. Se eliminó la configuración residual de iOS/visionOS del target en la rama técnica, sin cambios visuales.
- Pruebas ejecutadas y resultado: copia verificada por conteo de archivos, `HEAD` y huella de estado; `swiftc -frontend -parse` de 24 Swift correcto; `Tools/CheckLocalizations.swift` correcto (199 claves, `en`/`es`); `plutil -lint` correcto; Debug falla en `SwiftUIMacros.StateMacro` con `swift-plugin-server` produciendo respuesta malformada.
- Capturas de interfaz/revisión visual: pendientes; no se ha ejecutado la aplicación.
- Limitaciones o bugs: el primer error de compilación es la expansión de `@State`, no los errores derivados de bindings; el problema se reproduce con caches limpias y modos Swift 5/6. Hay avisos de CoreSimulator y permisos del entorno durante `xcodebuild`.
- Siguiente paso: aislar el fallo de `swift-plugin-server` con una compilación Xcode limpia en el host macOS y, cuando compile, verificar la interfaz en claro/oscuro y las paletas. Después separar cualquier corrección adicional en un commit propio.

### 2026-10-21 · Cierre de validación de Fase 0
- Objetivo: cerrar la discrepancia entre Xcode y el entorno restringido de Codex sin modificar Swift ni la interfaz.
- Rama/commit: `chore/project-validation`; pendiente el commit de esta documentación.
- Archivos afectados: restaurados únicamente `Littera/Assets.xcassets/Contents.json`, `AccentColor.colorset/Contents.json` y `AppIcon.appiconset/Contents.json`; añadida `docs/PHASE0-MANUAL-CHECKLIST.md`.
- Cambios y decisiones: los tres assets eran recursos originales de `HEAD` y el target los referencia explícitamente mediante `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` y `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`. Las eliminaciones no eran intencionadas y se restauraron sin alterar su contenido.
- Pruebas ejecutadas y resultado: proyecto, esquema `Littera`, configuración `Debug`, destino macOS y toolchain Xcode 27.1/SDK 27.0 confirmados; localizaciones es/en validadas; compilación Debug limpia autorizada en `/tmp/Littera-Codex-clean-DD` completada con `BUILD SUCCEEDED`.
- Capturas de interfaz/revisión visual: pendientes; la checklist manual queda en `docs/PHASE0-MANUAL-CHECKLIST.md`.
- Limitaciones o bugs: la compilación dentro del sandbox de Codex sigue sin ser una evidencia válida por el bloqueo de `swift-plugin-server`, caches y logs de Xcode. La compilación autorizada fuera del sandbox no presenta el error `SwiftUIMacros.StateMacro`.
- Siguiente paso: ejecutar la checklist visual manual en Xcode y revisar capturas antes de aceptar la línea base UI 1.0. No iniciar todavía funcionalidades nuevas.

### 2026-10-21 · Corrección UI · menú de anchura y apariencia Sistema
- Objetivo: corregir exclusivamente el submenú redundante de anchura y la restauración incorrecta del tema Sistema.
- Rama/commit: `fix/ui-menu-and-system-appearance`; commit pendiente.
- Archivos afectados: `Littera/Editor/LitteraTitlebarView.swift`, `Littera/LitteraApp.swift`.
- Cambios y decisiones: se sustituyó el `Picker` anidado dentro de `Menu` por tres `Button` del propio menú, conservando `LitteraWritingWidth`, la selección marcada y la preferencia persistida. Se centralizó en `LitteraApp` la conversión de la preferencia a `ColorScheme?`: Sistema devuelve `nil`, Claro `.light` y Oscuro `.dark`; se aplica el mismo valor a la ventana principal y a Preferencias. No se usa `NSApp.appearance`.
- Pruebas ejecutadas y resultado: `git diff --check` correcto; `Tools/CheckLocalizations.swift` correcto (199 claves); parseo de todos los Swift correcto; compilación Debug limpia autorizada en `/tmp/Littera-fix-DD` correcta (`BUILD SUCCEEDED`).
- Capturas de interfaz/revisión visual: pendientes.
- Limitaciones o bugs: no se han ejecutado aún las ocho secuencias manuales de cambio de tema ni la comprobación visual del menú en una ventana real.
- Siguiente paso: ejecutar la revisión manual en Xcode con macOS inicialmente claro y oscuro; comprobar ventana principal, Preferencias y ambas paletas antes de fusionar.

### 2026-10-21 · Corrección UI · fallo persistente del tema Sistema
- Objetivo: investigar el fallo real de herencia de apariencia y corregirlo sin cambiar la interfaz.
- Rama/commit: `fix/ui-menu-and-system-appearance`; commit independiente pendiente.
- Archivos afectados: `Littera/LitteraApp.swift`, nuevo `Littera/Appearance/LitteraWindowAppearanceBridge.swift`; se retiró la instrumentación temporal de `Littera/Debug/`.
- Diagnóstico: `@AppStorage` contenía correctamente `system`, `light` o `dark`; no existía uso de `NSApp.appearance` ni otro `NSAppearance`. `preferredColorScheme(nil)` retiraba el override SwiftUI, pero no garantizaba limpiar la apariencia ya impuesta en las `NSWindow` existentes. Por eso una ventana que había pasado por Claro conservaba apariencia efectiva clara aunque la preferencia volviera a Sistema.
- Corrección: se retiró `preferredColorScheme` como mecanismo de imposición y se usa una única fuente de verdad (`LitteraAppearance` almacenada). Un bridge nativo asigna `.aqua`, `.darkAqua` o `nil` a cada ventana; `nil` elimina el override por ventana y restablece la herencia de macOS. La misma vía se aplica a la ventana principal y a Configuración.
- 2026-10-21 · Corrección de barra de título de Configuración: el puente nativo mantiene la apariencia de la `NSWindow` y limpia la apariencia explícita retenida por su `contentView`, de modo que contenido, título nativo y controles traffic-light siguen la misma cadena de herencia. No se añadieron colores ni controles personalizados.
- Verificación: `swift Tools/CheckLocalizations.swift` OK (199 claves, `en`/`es`); parsing Swift OK con cachés temporales; compilación Debug limpia autorizada con `xcodebuild` y DerivedData en `/tmp/Littera-titlebar-DD` OK. La misma compilación dentro del sandbox reprodujo el fallo externo de `SwiftUIMacros.StateMacro`/`swift-plugin-server`, ya diagnosticado como restricción del entorno.
- Verificación visual: se abrió la ventana real de Configuración y se comprobó por Accessibility que conserva título nativo, botones nativos y selección de apariencia. La captura oscura mostró título legible y controles nativos. La captura posterior al cambio a claro quedó en blanco en la captura CUA aunque el árbol Accessibility siguió presente; por tanto, quedan pendientes las comprobaciones visuales concluyentes de claro/inactivo y de las seis secuencias solicitadas.
- Pruebas ejecutadas y resultado: `Tools/CheckLocalizations.swift`, parseo Swift y compilación Debug limpia (`BUILD SUCCEEDED`) correctos. En la app real se comprobó `Sistema → Claro → Sistema`, `Oscuro → Claro → Sistema`, selección de Sistema en Preferencias, la ventana principal y cierre/reapertura conservando Sistema; al volver a Sistema con macOS oscuro la ventana volvió a oscuro.
- Capturas de interfaz/revisión visual: comprobación visual directa mediante la app compilada; paletas no alteradas por el bridge.
- Limitaciones o bugs: pendiente comprobar `Sistema → Oscuro → Sistema`, `Claro → Oscuro → Sistema`, ambos estados iniciales de macOS y cambiar la apariencia del propio macOS mientras Littera está en Sistema. No se ejecutó el cambio del ajuste de macOS desde UI por requerir autorización específica.
- 2026-10-21 · Contrato de ventanas: `LitteraThemeHost` mantiene un único árbol SwiftUI y aplica el `colorScheme` efectivo sin ramas estructurales, evitando recrear Settings y perder navegación, scroll o selección de Apariencia durante un cambio de tema. La ventana principal se marca como restorable mediante `NSWindow.isRestorable` e `identifier`; Littera no guarda ni reaplica frames.
- Validación: compilación Debug limpia autorizada OK (`/tmp/Littera-windows-DD`), localizaciones OK (199 claves). En la app compilada se confirmó que Settings conserva la sección Apariencia y la selección Oscuro tras el cambio de tema, y que la ventana principal se reabre mediante el ciclo nativo de macOS. No se modifican tamaños mínimos, posiciones, foco, paletas ni controles.
- Pendiente de validación manual: mover físicamente ambas ventanas a posiciones distintas y repetir todas las transiciones Sistema/Claro/Oscuro comprobando coordenadas y tamaño antes/después; confirmar también cambios de apariencia de macOS mientras está seleccionado Sistema. La automatización disponible no expone una comprobación fiable de geometría de `NSWindow`.
- Siguiente paso: ejecutar esas secuencias restantes y, si pasan, fusionar la rama tras revisión; no iniciar funcionalidades nuevas antes de cerrar esta validación.

### 2026-10-21 · Funcionalidad 05A · integración de parser Markdown
- Objetivo: integrar `swift-markdown` como capa de análisis independiente, sin conectar todavía el parser con el renderer ni modificar la UI congelada.
- Rama/commit: `feature/markdown-editor`; commit de esta funcionalidad pendiente tras la validación final.
- Archivos afectados: `Littera.xcodeproj/project.pbxproj`, `Littera.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `Littera.xcodeproj/xcshareddata/xcschemes/Littera.xcscheme`, `Littera/Markdown/LitteraMarkdownParser.swift`, `Littera/Markdown/LitteraMarkdownParseResult.swift`, `LitteraTests/LitteraMarkdownParserTests.swift`.
- Cambios y decisiones: dependencia oficial `swift-markdown` fijada en `0.8.0`, producto `Markdown`; `LitteraMarkdownParser` recibe el `String` original y devuelve un resultado con la fuente intacta y `Markdown.Document` como AST. No se modifican `LitteraDocumentSession`, `LitteraEditorView`, `LitteraSampleDocument` ni ningún renderer o comando visual. Se añadió un target XCTest mínimo y un scheme compartido para ejecutarlo.
- Pruebas ejecutadas y resultado: resolución SPM correcta (`swift-markdown 0.8.0`, `swift-cmark 0.9.0`); Debug `build-for-testing` correcto; XCTest 5/5 correcto; Release `BUILD SUCCEEDED`; `swift Tools/CheckLocalizations.swift` correcto (208 claves, `en`/`es`); `swiftc -frontend -parse` correcto; `git diff --check` correcto.
- Capturas de interfaz/revisión visual: no aplicable; no se modificaron vistas, estilos, geometría, menús, paletas ni localizaciones.
- Limitaciones o bugs: el primer build directo por target mostró un fallo de rutas de cabeceras C de `swift-cmark` con ese modo de invocación; el scheme macOS normal de Xcode compiló y probó correctamente. Persisten avisos del entorno sobre CoreSimulator y `com.apple.linkd.autoShortcut`, ajenos al parser.
- Siguiente paso: implementar el renderer nativo y conectar la vista previa únicamente en una tarea posterior autorizada, manteniendo `LitteraDocumentSession.markdown` como fuente única de verdad.

### 2026-10-22 · Recuperación, rendimiento, modo Visual y acabado de motor
- Objetivo: recuperar la compilación, resolver el rendimiento de Dividido y completar motor, modos y Vista previa.
- Rama/commits: `feature/markdown-sync`, de `8410a66` a `e766378` (sin merge ni push).
- Cambios y decisiones:
  - Compilación: `LitteraMarkdownSourceIndex` (refactorización incompleta); conversión UTF-8→UTF-16 lineal.
  - Rendimiento: análisis fuera del hilo principal (una tarea por documento, gana la última versión); sincronización de Dividido directa sobre `NSClipView` con correspondencia semántica interpolada; bloques de la Vista previa `Equatable`.
  - Editor: envío síncrono del texto y respeto de la composición (teclas muertas); posición semántica compartida entre modos y persistida por archivo.
  - Modo Visual editable (D27), resaltado de sintaxis y Copiar (D29), tablas (D34), tareas con casilla, imágenes locales (D30), paleta de color (D28), icono, paletas con teclado/trackpad/puntero (D32), documento vacío al arrancar (D31).
- Pruebas ejecutadas: XCTest 34/34; Release `BUILD SUCCEEDED` antes de añadir `Littera.entitlements`; paridad de localización es/en; validación manual en la app con un documento de 9.052 palabras (Dividido, cambio de modos, escritura, Deshacer, tablas, imágenes, temas).
- Limitaciones: sin medición con Instruments; Release no recompilado tras `Littera.entitlements`; capturas de `referencias-visuales/` desactualizadas.
- Siguiente paso: comandos de formato y búsqueda; después cerrar/recientes/cambios externos/restaurar sesión.

### 2026-10-22 · Comandos de formato y búsqueda
- Objetivo: paso 2 del orden aprobado.
- Rama/commit: `feature/markdown-sync`, `d9ae38e` (sin merge ni push).
- Archivos afectados: `Formatting/LitteraMarkdownFormatter.swift`, `Formatting/LitteraEditingTarget.swift`, `Formatting/LitteraTextSearch.swift`, `CommandPalette/LitteraCommandRegistry.swift`, `Editor/LitteraEditorView.swift`, `Editor/LitteraSourceTextView.swift`, `Editor/LitteraTitlebarView.swift`, `Editor/LitteraVisualStyle.swift`, `LitteraApp.swift`, localizaciones, dos ficheros de pruebas.
- Cambios y decisiones: formateador puro sobre el Markdown (una edición = un paso de Deshacer); destino de edición único (en Dividido, el panel Fuente); la búsqueda usa el popover de la lupa ya aprobado en UI 1.0 en lugar de la barra de búsqueda nativa de AppKit, para no introducir elementos visuales nuevos; submenú Edición → Buscar.
- Pruebas ejecutadas y resultado: XCTest 55/55; paridad es/en 231 claves; en la app: ⌘B/⌘I/⇧⌘K, Título 2 desde la paleta, Deshacer paso a paso, búsqueda «cancion» encuentra «canción»/«CANCION» (1 de 3 → 3 de 3 → 2 de 3), Escape devuelve el foco, ⌘G con el popover cerrado, Vista previa deshabilita lupa y formato.
- Capturas de interfaz/revisión visual: el popover conserva su tamaño y estilo; el texto «Búsqueda pendiente de implementar» se sustituye por la ayuda o el recuento.
- Limitaciones o bugs: el formato en línea sobre una selección de varios párrafos envuelve toda la selección (Markdown no admite negrita entre párrafos); Reemplazar añadido después (ver entrada siguiente); búsqueda no disponible en Vista previa.
- Siguiente paso: cerrar documento, recientes, cambios externos y restaurar sesión.

### 2026-10-22 · Buscar y reemplazar
- Objetivo: Reemplazar según la opción 1 aprobada por el propietario.
- Cambios y decisiones (D35): `⌥⌘F` (Edición → Buscar → Buscar y reemplazar…) abre el mismo popover con un segundo campo «Reemplazar con…» y los botones Reemplazar y Reemplazar todo; con `⌘F` o la lupa no aparecen. Intro en el campo de reemplazo equivale a Reemplazar. Reemplazar todo es un único paso de Deshacer.
- Pruebas: XCTest 58/58; paridad es/en; en la app: Reemplazar pasa a la siguiente coincidencia, Reemplazar todo muestra «3 reemplazos», `⌘Z` lo deshace de una vez, `⌘F` muestra el popover sin reemplazo.
- Limitaciones: búsqueda sin distinguir mayúsculas ni acentos, sin opciones (palabra completa, expresiones regulares).

### 2026-10-22 · Paso 3: cerrar, recientes, cambios externos y sesión
- Objetivo: paso 3 del orden aprobado. Además, icono que no aparecía.
- Icono: la app compilada ya incluía `AppIcon.icns`/`Assets.car` y `CFBundleIconName`; el Dock mostraba la caché de macOS. Al actualizar la fecha del paquete y relanzar, aparece. Sin cambios de código.
- Archivos: `Documents/LitteraDocumentFiles.swift` (nuevo), `Documents/LitteraDocumentPrompts.swift` (nuevo), `LitteraDocumentStore`, `LitteraDocumentSession`, `LitteraApplicationDelegate`, `LitteraApp`, `LitteraEditorView`, `LitteraCommandRegistry`, `GeneralSettingsView`, `LitteraPreferences`, localizaciones, pruebas.
- Cambios y decisiones:
  - Cerrar documento `⌘W` (menú Archivo y paleta); pregunta si hay cambios; si no queda ninguno, documento vacío (D31). En Ajustes, `⌘W` cierra esa ventana.
  - Abrir sustituye el documento vacío intacto (D36).
  - Abrir reciente (10, «Borrar menú»), con marcadores de seguridad; un reciente que ya no existe se avisa y se quita.
  - Cambios externos al volver a la app: sin cambios locales se recarga en silencio; con cambios, «Mantener mi versión» / «Cargar versión del disco»; guardar sobre un archivo cambiado fuera pide «Sobrescribir»; archivo borrado → texto conservado y marcado como no guardado (D37).
  - Restaurar sesión (archivos guardados y documento activo); Ajustes → General → interruptor «Restaurar documentos abiertos», activado por defecto.
  - Las preguntas al usuario son un protocolo (`LitteraDocumentPrompts`): alertas nativas en la app, respuestas fijas en pruebas; las pruebas usan Preferencias propias.
  - Corrección: la ventana del editor no se registraba en el delegado (la vista puente no tenía ventana en `updateNSView`); ahora se registra en `viewDidMoveToWindow`, con lo que también se activa la protección al cerrar la ventana.
  - Fechas de modificación leídas con `FileManager` (los valores de recurso de `URL` quedan en caché y no veían cambios externos).
- Pruebas: XCTest 71/71; paridad es/en 246 claves; en la app: abrir dos archivos, ⌘W activa el vecino y al final deja «Sin título.md», cambio externo sin edición recargado, con edición muestra la alerta y «Mantener mi versión» + ⌘S guarda sin volver a preguntar, reinicio de Littera restaura el documento, Abrir reciente reabre tras reiniciar, ⌘W en Ajustes cierra Ajustes.
- No probado en la app: archivo borrado fuera (cubierto por XCTest), varias ventanas.
- Limitaciones: con varias ventanas, ⌘N/⌘S/⌘W actúan en todas (avisos por notificación sin destino); los documentos nunca guardados no se restauran; la comprobación de cambios externos ocurre al activar Littera, no en tiempo real.
- Siguiente paso: paso 4 (frontmatter YAML y resaltado Markdown en Fuente).

### 2026-10-22 · Corrección: Buscar y reemplazar desde el menú
- Fallo (informado por el propietario): Edición → Buscar → Buscar y reemplazar no mostraba el campo de reemplazo si antes no se había abierto Buscar.
- Causas: (1) el contenido del popover de la barra de herramientas no se actualizaba con `isReplacing` hasta que cambiaba otro valor; (2) sin el editor como primer respondedor, las acciones Buscar del menú no llegaban a ningún sitio.
- Corrección: el contenido del popover es una vista propia (`LitteraSearchPopover`) que observa sus valores; si el editor no tiene el foco, la acción se envía a la ventana del editor por notificación. Con Reemplazar, la ayuda se oculta y los botones no se recortan.
- Pruebas: en la app, ⌥⌘F nada más arrancar muestra el reemplazo; ⌘F y luego ⌥⌘F cambia a reemplazo con el popover abierto.
- Decisiones D36 y D37 aprobadas por el propietario.

### 2026-10-22 · Paso 4: frontmatter YAML y resaltado en Fuente
- Objetivo: paso 4 del orden aprobado.
- Archivos: `Markdown/LitteraFrontmatter.swift` (nuevo), `Editor/LitteraSourceStyle.swift` (nuevo), parser, resultado del análisis, documento derivado, tramos Visual, estilo Visual, `LitteraSourceTextView`, `LitteraEditorView`, pruebas.
- Cambios y decisiones:
  - Frontmatter: `---` en la primera línea y cierre `---` o `...`. Se analiza el resto con las mismas líneas (el frontmatter se sustituye por líneas vacías antes de llamar a swift-markdown), así que los rangos de los bloques siguen apuntando al texto original. Antes, el `---` final convertía la última línea del YAML en un encabezado.
  - Vista previa: el frontmatter no se muestra (D38, pendiente de revisión). Visual: monoespaciado y atenuado. Fuente: atenuado. No cuenta como palabras.
  - Resaltado en Fuente (D39, pendiente de revisión): misma fuente monoespaciada y tamaño; marcadores atenuados, encabezados en seminegrita, negrita, cursiva, tachado, enlaces en color de acento, tareas hechas atenuadas, código con el resaltado por lenguaje del modo Visual. Se aplica por zonas, como Visual.
  - Corrección: el editor convertía `---` en raya (—) y las comillas rectas en tipográficas (sustituciones automáticas de macOS). Desactivadas en Fuente y Visual: en Markdown el texto es literal.
- Pruebas: XCTest 77/77 (`LitteraFrontmatterTests`); en la app, documento nuevo con frontmatter, título, énfasis, código, enlace, cita, tareas y bloque Swift en Visual, Fuente, Dividido y Vista previa; edición en Fuente con reestilizado incremental.
- Limitaciones: el YAML no se valida; las claves anidadas o listas se muestran como texto.
- Siguiente paso: paso 5 (exportación PDF/HTML, máquina de escribir, interlineado, ortografía, estadísticas, atajos, documento nuevo al iniciar).

### 2026-10-22 · Paso 5 (parte 1): resaltado de Fuente v2, interlineado, máquina de escribir, ortografía y exportación
- Decisiones del propietario: D38 confirmada (frontmatter solo en Visual, Fuente y Dividido); D39 rechazada por «sosa» → nueva versión; PDF con el aspecto de la Vista previa; HTML con el conversor de swift-markdown; máquina de escribir = línea centrada + resto atenuado; interlineado en Ajustes → Editor con tres opciones. Personalizar atajos: sin respuesta todavía.
- Resaltado de Fuente v2 (D39 bis, pendiente de revisión): encabezados más grandes en la misma familia monoespaciada (×1,45/1,3/1,15/1,05) y en negrita; `#`, viñetas, números, casillas y `>` en color de acento; citas en cursiva atenuada; código en línea con color propio y fondo; enlaces subrayados en acento; YAML del frontmatter resaltado (también en Visual).
- Interlineado (Compacto/Normal/Amplio): Visual y Vista previa 5/9/14 pt; Fuente 0/0/5 pt. Normal = UI 1.0. En Visual se compensa la separación entre párrafos para que coincida con la Vista previa.
- Máquina de escribir (Ajustes → Editor y menú `···`): la línea activa queda centrada (márgenes de media ventana) y el resto se atenúa con atributos temporales (no toca el texto ni Deshacer).
- Corrección ortográfica (Ajustes → Editor y menú `···`): corrector de macOS; desactivada por defecto.
- Exportar (menú `···` → Exportar, menú Archivo y paleta): PDF A4 con las vistas de la Vista previa en tema claro, saltos de página entre bloques; HTML autónomo con CSS de los colores de Littera (claro/oscuro). El frontmatter no se exporta.
- Pruebas: XCTest 79/79 (`LitteraExporterTests`); en la app: resaltado v2, máquina de escribir (inicio, final y escritura), interlineado Amplio en Visual y Vista previa, exportación a PDF y HTML de `prueba.md` revisadas. Preferencias devueltas a sus valores por defecto tras probar.
- Limitaciones: las imágenes locales no aparecen en el PDF (se cargan de forma asíncrona); la máquina de escribir con Dividido solo centra el panel Fuente.
- Siguiente: estadísticas ampliadas, documento nuevo al iniciar, personalizar atajos (pendiente de respuesta).

### 2026-10-22 · Paso 5 (parte 2): atajos, imágenes en PDF, estadísticas y arranque
- Decisiones del propietario: hacer ya la pantalla de atajos; las imágenes locales deben salir en el PDF; en Dividido la máquina de escribir solo centra el panel Fuente (correcto así por ahora).
- Atajos personalizables (D44): `LitteraShortcuts` guarda los cambios en Preferencias; menús, paleta y editor leen de ahí. Ajustes → Atajos lista Documentos y ventanas, Búsqueda, Vistas y Formato (los 20 comandos); al pulsar un atajo se graba el siguiente (Esc cancela, ⌫ lo quita), con aviso si falta ⌘/⌃/⌥, si está reservado por macOS o si ya lo usa otro comando; botón para restablecer cada atajo y «Restaurar todos los atajos». Nuevo: «Guardar como…» ⇧⌘S por defecto; los cuatro modos y la máquina de escribir aparecen en el menú Visualización (sin atajo por defecto).
- Imágenes en el PDF: se cargan antes de dibujar; si su carpeta no está autorizada se pide acceso una vez por carpeta.
- Estadísticas: palabras, caracteres, caracteres sin espacios, párrafos, líneas y tiempo de lectura (sin frontmatter); un único popover anclado al menú `···`, también desde la paleta.
- Ajustes → General → «Documento nuevo al iniciar»: Documento vacío (D31, por defecto) o Abrir documento… (muestra el panel Abrir si no se restauró ningún documento).
- Interno: los avisos de menú del editor pasan por un único receptor (la cadena de `onReceive` superaba al comprobador de tipos).
- Pruebas: XCTest 85/85 (`LitteraShortcutsTests`, `LitteraDocumentStatisticsTests`); en la app: asignar ⌘1 a Fuente y usarlo desde el teclado y el menú Visualización, conflicto con ⌘B, restaurar todos; PDF con imagen local (tras autorizar la carpeta de pruebas); estadísticas desde la paleta; corrector activado/desactivado en vivo. Preferencias y atajos devueltos a los valores por defecto.
- No probado en la app: «Abrir documento…» al iniciar (requiere reiniciar sin documentos).

### 2026-10-22 · Paso 6: medición, accesibilidad, capturas y checklist
- D39 aprobada por el propietario.
- Rendimiento (XCTest `LitteraPerformanceTests`, documento de ~10.000 palabras con todos los tipos de bloque; tiempos aproximados por operación a partir de la duración de cada prueba, 5 iteraciones): análisis completo ≈0,15–0,18 s (fuera del hilo principal); estilo Visual completo ≈0,02 s; estilo Fuente completo ≈0,015 s; pulsación (análisis + reestilo de la zona) ≈0,15 s, del que el reestilo en el hilo principal es una fracción pequeña; HTML ≈0,06 s; PDF ≈1,8 s. No se ha usado Instruments (requiere la app Instruments con control completo): pendiente si se quiere un perfil de CPU/memoria.
- Accesibilidad (D47): etiquetas VoiceOver (lupa, `···`, barra de estado como un solo elemento, título con estado de cambios, restablecer atajo), iconos decorativos ocultos, «Reducir movimiento» y «Aumentar contraste».
- Contraste: el texto secundario #898782 sobre el fondo claro #FCFCFB es ≈3,6:1 (por debajo de 4,5:1 para texto pequeño); sobre el oscuro, ≈5:1. No se cambia el color aprobado: solo con «Aumentar contraste».
- Regresión corregida (D46): la cita de la Vista previa había perdido la serif cursiva de la referencia aprobada y tenía más margen abajo que arriba. Restaurada en Vista previa, Visual y PDF.
- Capturas nuevas en `docs/referencias-visuales/2026-10-22/` (10, claro y oscuro). `UI_CHECKLIST.md` reescrito con el estado actual.
- Pruebas: XCTest 92/92. Tema, interlineado, corrector y atajos devueltos a sus valores (Sistema, Normal, desactivado, por defecto).
- Pendiente: Release con entitlements (necesita `xcodebuild` en Terminal o control completo de Xcode), Instruments, VoiceOver completo, inglés tras reiniciar.

### 2026-10-22 · Paso 6: Release e Instruments
- Release: compilado con Product → Profile (configuración Release, con `Littera.entitlements`) y ejecutado bajo Instruments sin problemas.
- Instruments (Time Profiler + Hangs, 53 s): documento de 7.445 palabras (`grande.md`), abrirlo, Dividido, desplazamiento, escritura en Fuente y en Visual.
  - Dos bloqueos («hangs») de ~1–1,5 s mientras se escribía en Dividido.
  - Causa 1 (≈1,9 s en esa ventana): `accessibilityHitTest` de `NSHostingView` pedido por un cliente de accesibilidad (la propia herramienta de control remoto que usa Claude): recorrer la jerarquía SwiftUI de una Vista previa con cientos de bloques es caro. Afecta también a VoiceOver con documentos grandes.
  - Causa 2 (≈0,5 s): maquetación SwiftUI de toda la Vista previa (`VStack` no perezoso) cada vez que llega una versión analizada nueva mientras se escribe en Dividido.
  - El resto del trabajo propio es pequeño: comparaciones de cadenas largas ≈0,29 s en toda la sesión, estilo Visual/Fuente y sincronización de desplazamiento en decenas de ms.
- Aplicado (aprobado por el propietario, sin nueva medición): en Dividido la Vista previa se actualiza 250 ms después de la última versión analizada, no con cada pulsación. Pendiente de estudio: lista perezosa para la Vista previa conservando la sincronización.
- Entrega: Release en `dist/Littera/Littera.app`, `dist/Littera-1.0.zip` y `dist/Littera-1.0.dmg` (Utilidad de Discos, imagen comprimida de solo lectura). `dist/` está en `.gitignore`. Firma: la de desarrollo automática de Xcode; sin notarizar (para instalar en este Mac).
- Aviso: hay compilaciones antiguas de Littera en DerivedData (`Littera-emjz…`, `Littera-cszg…`); «abrir Littera» desde el sistema llegó a lanzar una versión antigua con la interfaz de demostración.

### 2026-10-23 · Mermaid y versión 1.0.1
- Objetivo: compatibilidad con Mermaid y versión 1.0.1 con instalador DMG (fondo del propietario, iconos grandes).
- Rama: `feature/markdown-sync`.
- Archivos: `Markdown/Mermaid/` (parser, disposición, geometría, vista, SVG; nuevos), `LitteraMarkdownRenderer.swift`, `LitteraExporter.swift`, `LitteraSyntaxHighlighter.swift`, `Localizable.strings` es/en, Ayuda es/en, `LitteraTests/LitteraMermaidTests.swift`, `project.pbxproj` (1.0.1, compilación 2), `Tools/probar.sh`, `Tools/crear-dmg.sh`, `Tools/dmg/`.
- Cambios y decisiones (D48): alcance acordado con el propietario, solo diagramas de flujo y solo en Vista previa/Dividido/exportaciones. Disposición por capas (Sugiyama simplificado): ciclos invertidos, rangos por camino más largo, nodos ficticios (también para etiquetas), orden por baricentros y posición por regresión isotónica ponderada; aristas en curvas S con puertos repartidos. Se calcula durante el análisis, fuera del hilo principal; la medida del texto usa CoreText. `classDef`/`style`/`linkStyle`/`click` se ignoran y `subgraph` se aplana. Resaltado de ```mermaid en Fuente y Visual.
- DMG: compilación Release en `$TMPDIR` (dentro de `~/Documents` con iCloud, `codesign` fallaba por atributos extendidos); se conserva la firma de Xcode con los entitlements (el script anterior la sustituía por una ad hoc sin ellos); fondo = imagen del propietario sin modificar como TIFF Retina (1408×768 a 2x, ventana 704×384), iconos de 128 pt a ambos lados del logo.
- Pruebas: `Tools/probar.sh` → traducciones OK (paridad es/en), XCTest 112/112 (20 nuevas de Mermaid), sin avisos en los archivos nuevos. Revisión visual en la app (oscuro) con el árbol genealógico real del propietario: `<br/>`, comillas y tildes correctos, sin solapes.
- No probado: tema claro en la app, VoiceOver sobre el diagrama, exportación HTML abierta en un navegador, documentos con diagramas de cientos de nodos (rendimiento).
- Limitaciones: sin `subgraph` con recuadro, sin estilos ni clases, sin flechas `--o`/`--x`, sin formas asimétricas `>texto]`, paralelogramos y trapecios como rectángulo; el bloque de HTMLFormatter no escapa el código de bloques no compatibles (comportamiento previo de swift-markdown).
- Pendiente: decidir sobre el cambio sin commit en `Littera.entitlements` (no es de esta sesión); revisión visual de D48.

### 2026-10-23 · Versión 1.0.2: panel de Ajustes completo (salvo Sincronización)
- Objetivo: revisar Ajustes y terminar lo pendiente, excepto Sincronización.
- Revisión: General, Editor, Apariencia y Atajos ya estaban conectados (vista inicial, restaurar sesión, documento al iniciar, tamaño en Fuente, anchura, interlineado, máquina de escribir, ortografía, tema, atajos). Pendiente real: Documentos → Guardar automáticamente y Carpeta predeterminada. Markdown marcaba el frontmatter YAML como pendiente aunque funciona (D38). Avisos con títulos de la maqueta («Interfaz preparada», «Cambios reales y cambios pendientes») y textos obsoletos.
- Archivos: `Documents/LitteraDefaultFolder.swift` (nuevo), `LitteraDocumentStore.swift` (escritura común a Guardar y guardado automático), `LitteraEditorView.swift` (panel Abrir, guardado al cambiar de app), `LitteraExporter.swift`, `Settings/DocumentSettingsView.swift`, `Settings/MarkdownSettingsView.swift`, `LitteraPreferences.swift`, `Localizable.strings` es/en, Ayuda es/en y `docs/Littera-Ayuda.md` (tabla de Ajustes corregida), `LitteraTests/LitteraAutosaveTests.swift` (nuevo), versión 1.0.2 (3).
- Decisión D49 (ver DECISIONS.md). Guardado automático desactivado por omisión para no cambiar el comportamiento sin que el usuario lo pida.
- Pruebas: `Tools/probar.sh` → traducciones OK, XCTest 122/122 (10 nuevas), sin avisos en los archivos tocados. En la app (oscuro): secciones Documentos y Markdown revisadas; «Elegir…» abre el panel de carpetas (cancelado).
- No probado en la app: el guardado automático de extremo a extremo (cubierto por pruebas unitarias con el mismo camino de escritura), elegir una carpeta real y que Abrir/Guardar/Exportar empiecen en ella, tema claro.
- Sincronización sin cambios, como se pidió.

### 2026-10-23 · Versión 1.0.3: sincronización con iCloud Drive (D50)
- Objetivo: Fase 6, iCloud Drive opcional.
- Enfoque (D50): carpeta de iCloud Drive elegida por el usuario. El contenedor propio de iCloud no es posible sin equipo de desarrollador (el proyecto firma «Sign to Run Locally»); si en el futuro hay cuenta del Apple Developer Program, se puede añadir sin cambiar el modelo de documentos.
- Archivos: `Documents/LitteraCloudFiles.swift` (servicio de iCloud tras un protocolo, ubicación), `Documents/LitteraFilePresenter.swift` (nuevos); `LitteraDocumentFiles.swift` (lectura/escritura coordinadas), `LitteraDocumentStore.swift` (descargas diferidas, presentadores, conflictos, cambios externos no interactivos), `LitteraDocumentPrompts.swift` (pregunta de conflicto), `LitteraDefaultFolder.swift`, `LitteraEditorView.swift` (conflictos al volver a la app), `Settings/SyncSettingsView.swift`, `Localizable.strings` es/en, Ayuda es/en, `docs/Littera-Ayuda.md`, pruebas (`LitteraCloudTests.swift` nuevo, ayudantes de pruebas), versión 1.0.3 (4).
- Ajustes → Sincronización: «En este Mac» / «iCloud Drive» muestran cuál está activo (la misma carpeta que Documentos → Carpeta predeterminada); «Usar este Mac», «Elegir…» (abre iCloud Drive) y «Seleccionar…» (cualquier carpeta). Se detecta como iCloud tanto iCloud Drive como Escritorio/Documentos sincronizados. Nueva fila informativa «Conflictos». Eliminado el texto fijo «Predeterminado» sin traducir.
- Pruebas: `Tools/probar.sh` → traducciones OK, XCTest 135/135 (13 nuevas: descargas, errores, tiempo de espera, restauración diferida, tres resoluciones de conflicto, versión ilegible, archivos locales, presentador real con escritura coordinada, cambios en vivo sin preguntas), sin avisos. En la app: la carpeta «Notas» ya elegida por el propietario aparece como iCloud Drive activo; el documento restaurado de Documentos (sincronizado con iCloud) se abre por la ruta coordinada sin falsos conflictos.
- No probado (requiere dos dispositivos o quitar la conexión): un conflicto real entre dispositivos, la descarga de un archivo desalojado, la descarga sin conexión, un traslado en Finder con el documento abierto. El plan de la Fase 6 pide estas pruebas manuales antes de dar la función por cerrada.

### 2026-10-23 · Versión 1.0.4: selector de carpetas en Ajustes y auditoría
- Fallo informado: en Ajustes, al cancelar el panel de «Carpeta predeterminada» o el de iCloud Drive, la ventana de Ajustes desaparecía. Causa: el panel se abría con `runModal()` como ventana suelta y, con Stage Manager, macOS devolvía al frente la ventana del editor, que tapaba Ajustes (seguía abierta detrás). Solución: `LitteraFolderPicker` presenta el panel como hoja de la ventana de Ajustes y la devuelve al frente.
- Auditoría y correcciones:
  - Exportación HTML: `HTMLFormatter` de swift-markdown no escapa nada; `a < b` rompía la página y un `<script>` en un bloque de código se ejecutaba al abrir el HTML. `LitteraHTMLExportRewriter` escapa texto, código y atributos, añade `alt` a las imágenes (no lo tenían), aplica a los enlaces el mismo criterio que la Vista previa (http, https, mailto y rutas relativas; `javascript:` y `data:` se quitan) y conserva negrita/cursiva/código/enlaces dentro de los encabezados. El HTML escrito a mano se conserva (CommonMark).
  - Puntuación tipográfica (D51): cmark convertía comillas, `--`, `---` y `...` en la Vista previa, el PDF y el HTML; desactivada.
  - Ajustes: «Preferencias», «Buscar sección», «Sin coincidencias» y «Local-first · macOS» eran textos fijos y salían en español con la interfaz en inglés (las claves ya existían); el pie mostraba «UI 1.0» en todas las versiones y ahora muestra la versión real.
  - Carpeta predeterminada: cada panel volvía a resolver el marcador y abría un acceso de seguridad sin cerrarlo; ahora se resuelve una vez, se cierra al cambiar de carpeta y se renueva el marcador si macOS lo marca como caducado.
  - Guardado automático: al activarlo, los documentos que ya tenían cambios se guardan en ese momento.
- Revisado sin cambios: los demás paneles (Abrir, Guardar, Exportar, acceso a imágenes) se abren desde el editor, que ya es la ventana principal; ⌘W en Ajustes cierra Ajustes; el monitor de teclado de Atajos se retira al desaparecer.
- Pruebas: XCTest 145/145 (10 nuevas), sin avisos. En la app (segunda instancia con la compilación nueva): Documentos → Elegir… → Cancelar y Sincronización → iCloud Drive → Elegir… → Cancelar mantienen Ajustes abierto y al frente; el panel aparece como hoja con su título.
- No probado en la app: abrir en un navegador un HTML exportado, la renovación de un marcador caducado (requiere mover la carpeta elegida).

### 2026-10-23 · Versión 1.1.0: edición asistida (D52)
- Objetivo: continuación de listas, cierre de símbolos, pegar URL como enlace, mover/duplicar líneas, alternar tareas, insertar fecha con formato configurable, limpiar espacios finales, ordenar líneas, convertir texto desde el menú contextual y frontmatter YAML vacío en cada documento nuevo.
- Rama/commit: `feature/markdown-sync`; versión 1.1.0 (6).
- Archivos afectados: nuevo `Littera/Formatting/LitteraTextCommands.swift` (transformaciones puras de texto); `LitteraEditingTarget.swift` (Intro, escritura, borrado, pegar, menú contextual, atajos); `LitteraShortcuts.swift`, `LitteraCommandRegistry.swift`, `LitteraPreferences.swift`, `EditorSettingsView.swift`, `LitteraDocumentSession.swift`, `LitteraEditorView.swift` (foco tras crear/abrir); localizaciones es/en; Ayuda es/en y `docs/Littera-Ayuda.md`; pruebas `LitteraTextCommandsTests.swift`.
- Cambios y decisiones: D52.
- Pruebas ejecutadas y resultado: 165/165 pruebas correctas, sin avisos. Prueba manual en una segunda instancia: documento nuevo con frontmatter vacío y «Sin guardar · 0 palabras»; foco directo tras `⌘N`; listas con viñetas y numeradas (incremento y fin con elemento vacío); `(x)` con sobrescritura del cierre, `[` → `[]`, `⌫` borra la pareja; `⌘↩`, `⌘D`, `⌥⌘↑`, `⇧⌘D`; menú contextual «Convertir texto» → mayúsculas.
- Capturas de interfaz/revisión visual: sin cambios de UI salvo tres filas nuevas en Ajustes → Editor y el grupo Edición en Ajustes → Atajos (componentes existentes).
- Limitaciones o no probado en la app: pegar URL sobre selección (solo pruebas unitarias; requiere escribir en el portapapeles), limpiar espacios y ordenar líneas desde la paleta, capitalizar/minúsculas, formatos de fecha distintos de ISO, `⌥⌘↓`, edición asistida en el modo Visual (comparte la vista base, no se probó a mano), tema claro, VoiceOver. Teclas muertas (`^`, `¨`) cubiertas por la lógica post-inserción, no probadas con teclado físico.
- Siguiente paso: revisión del propietario; no se ha fusionado ni publicado.

### 2026-10-23 · Versión 1.2.0: propiedades del documento (D53)
- Objetivo: panel de propiedades del documento (según la captura del propietario) que edita el frontmatter YAML, con índice automático real y plantilla prerrellenada en documentos nuevos.
- Decisiones del propietario: popover desde la barra; los 5 campos más las otras claves; campos prerrellenados en documentos nuevos; índice real en Vista previa, PDF y HTML.
- Rama/commit: `feature/markdown-sync`; versión 1.2.0 (7).
- Archivos afectados: nuevos `Littera/Markdown/LitteraDocumentProperties.swift` (lectura/escritura de claves, plantilla) y `Littera/Editor/LitteraPropertiesPopover.swift`; `LitteraTitlebarView.swift`, `LitteraEditorView.swift`, `LitteraEditingTarget.swift`, `LitteraScrollCoordinator.swift`, `LitteraCommandRegistry.swift`, `LitteraMarkdownRenderer.swift` (bloque de índice), `LitteraExporter.swift` y `LitteraHTMLExportRewriter.swift` (índice e `id` en HTML), `LitteraDocumentSession.swift`; localizaciones es/en; Ayuda; pruebas `LitteraDocumentPropertiesTests.swift`.
- Pruebas ejecutadas y resultado: 174/174 correctas. Prueba manual en una segunda instancia: documento nuevo con la plantilla; botón de propiedades abre el panel; título con Intro, dos etiquetas separadas por comas, estado En desarrollo desde el menú, índice activado y desactivado (también en Vista previa, sin editor); `⌘Z`/`⇧⌘Z` deshacen y rehacen; la Vista previa muestra el índice.
- Limitaciones o no probado en la app: clic en una entrada del índice (desplazamiento), exportación PDF/HTML con índice (solo pruebas unitarias del HTML), edición de otras claves, quitar etiquetas con ×, «Usar hoy», tema claro, VoiceOver, inglés. Aviso previo de Xcode (no nuevo): `Info.plist` en Copy Bundle Resources.
- Siguiente paso: revisión visual del propietario del popover frente a la maqueta.

### 2026-10-23 · Versión 1.2.1: panel de propiedades desplazable y todo editable (D54)
- Problema del propietario (captura): con un frontmatter largo el panel salía cortado sin poder desplazarse; listas (`aliases`, `categories`, `keywords`) y objetos (`custom`) no se podían editar; los valores mostraban sus comillas.
- Cambios: ScrollView con alto medido y máximo según pantalla; tipos de valor `scalar`/`list`/`block` con escritura que conserva estilo; textos de ayuda.
- Pruebas: 176/176. Manual en segunda instancia con un frontmatter de 30 claves como el del propietario: panel completo con desplazamiento, `priority` y `version` editados (comillas conservadas), `custom` editado como YAML y deshecho con `⌘Z` (sangría correcta).
- No probado en la app: añadir/quitar elementos en listas distintas de `tags`, textos `|` o `>`, pantallas pequeñas, tema claro.

### 2026-10-24 · Versión 1.2.2: nombres de propiedades en español (D55)
- Petición del propietario: las etiquetas del panel en español aunque las claves del documento sigan en inglés.
- Cambios: nuevo `Littera/Markdown/LitteraPropertyLabels.swift` (79 claves habituales → claves de localización `ui.clave.*`, es/en) y nombre legible para las desconocidas; ayuda con la clave real.
- Pruebas: 177/177 (incluida la comprobación de que todas las claves tienen traducción es/en). Manual en segunda instancia sobre `implementaciones.md` sin modificarlo: Subtítulo, Descripción, Identificador (slug), Alias, Autor, Colaboradores.
- No probado en la app: interfaz en inglés.

### 2026-10-25 · Rediseño UI: primera entrega de documentación (pre-implementación)
- Objetivo: analizar el proyecto Stitch («macOS Markdown Editor»), diagnosticar la arquitectura visual y documentar antes de escribir Swift.
- Archivos: `docs/UI_REDESIGN_PLAN.md` (13 pantallas de Stitch, riesgos R1–R8, etapas 0–9, decisiones A–F), `docs/UI_COMPONENTS.md`, `docs/UI_BACKEND_CONTRACTS.md` (frontera presentación/backend e importaciones prohibidas en `Littera/UI/`).
- Decisiones: D56–D61 (terracota, fondo oscuro #1C1C1E aparte, botón Zen, inspector con tres paneles, barra lateral, prefijo `Littera`).

### 2026-10-25 · Rediseño UI · Etapa 0: scaffold de Littera/UI/
- Rama/commit: `feature/littera-ui-redesign`, `e47a230` (parte de `4a30108`, build 11 de `feature/markdown-sync`).
- Archivos nuevos bajo `Littera/UI/`: `DesignTokens/LitteraUITheme.swift` (D57), `DesignTokens/LitteraUITokens.swift`, `Models/LitteraUIDocument.swift`, `Models/LitteraUILibraryItem.swift`, `Models/LitteraUIMockData.swift`. Entran por `PBXFileSystemSynchronizedRootGroup` (sin tocar `project.pbxproj`).
- Pruebas: compilación Debug correcta en Xcode (propietario).
- Nota de proceso: la herramienta de escritura del asistente escribe en la nube; los archivos del repositorio se escriben por el puente (`device_bash`).

### 2026-10-25 · Rediseño UI · Etapas 1–3: sistema de diseño, barra lateral y espacio de trabajo
- Commits: `4449dbd`, `cd51c38`, `2ef8d94`, `2ee4bc7`.
- `LitteraUISurface.swift` (paneles, tarjetas, chips, botón de acento), `LitteraSidebarView.swift` (D60), selector de modos (D62), barra superior, barra de estado y `LitteraWorkspaceView`. Paridad es/en 446/446.
- Corrección: `folderRow` recursivo en `@ViewBuilder` daba decenas de errores; árbol de carpetas aplanado.

### 2026-10-25/26 · Rediseño UI · Etapas 4–7: fidelidad a Stitch, biblioteca, paleta, inspector y Zen
- Commits: `1c92395` (editor dividido fiel a Stitch), `d515295` (barra superior plana y tokens de Stitch), `f590163` (biblioteca, paleta, inspector y paneles redimensionables), `4263381` (Modo Zen), `80a6c3c` (Inter + JetBrains Mono, modo Visual D27, tarjetas uniformes).
- Diagnóstico de fidelidad previo en `docs/UI_FIDELITY_DIAGNOSIS.md`.
- Todo con datos de demostración; sin conexión al backend.

### 2026-10-26 · Rediseño UI · Fases 2–5: localización, diseño del documento, tema claro y accesibilidad
- Commits: `a568c25` (es/en de las pantallas nuevas), `5058969`, `013358d`, `d3f620c` (ancho de lectura, primero en el editor y después, a petición del propietario, en el panel «Diseño del documento» del inspector, junto con fuente, tamaño, interlineado e iconos de formato: D68), `f48471e` (bloque de código tema-aware), `117d770` (accesibilidad D47 en el cromo del espacio de trabajo).

### 2026-10-26 · Rediseño UI · Fases 6–7: integración con el backend y cutover
- Commits: `f80e15e`, `2e9b83c` (costura `LitteraUIActions`/`LitteraUIWorkspaceInfo` en `Littera/UI/LitteraUIIntegration.swift`, sin importar el backend), `d1e3596`–`fed777f` (cutover reversible, editor real embebido sin cromo), `2f458bb` (biblioteca como vista por defecto), `e7d9a6a` (el rediseño pasa a ser la ventana principal, D65).
- Archivos nuevos fuera de `UI/`: `Littera/Integration/LitteraUIAdapters.swift` (sesión/derivado → modelos de presentación, acciones reales) y `Littera/Integration/LitteraRedesignContainer.swift`.
- `LitteraEditorView` gana `chromeless`: sin barra de estado propia ni `.toolbar`; búsqueda como capa flotante.
- Hallazgo clave: `.toolbar`, `.toolbarBackground` y `.toolbarBackgroundVisibility` configuran la **ventana**, no la subvista. Cuatro intentos fallidos con la barra y los semáforos hasta no declarar ningún toolbar en modo chromeless.

### 2026-10-26 · Datos reales (punto 1), controles conectados (punto 2) y retirada de local-first
- Commits: `db3322e`, `e17b359`, `cd07c31`, `7446976` (barra lateral, biblioteca e inspectores con datos reales, D66), `fa56250` (detección de iCloud en Documentos con `isSyncedWithICloud(path:)` y textos local-first reescritos, D63), `29030d9` (Documentos como ubicación propuesta, D64), `4efce1f`, `0af2962`, `e4a2d6c` (exportar, «···», ancho de lectura y búsqueda reales).
- Decisiones del propietario: D63, D64.

### 2026-10-26 · Auditoría en la app real con control del Mac
- Problema: «no funciona nada» tras el cutover. Diagnóstico erróneo inicial del asistente: se lanzó una copia antigua (`com.cnyps.es.Littera`) en vez de la compilación Debug (`com.cnyps.es.Littera.debug`); corregido por el propietario.
- Causa real: `LitteraEditorView` es el **centro de mando** de la app (único receptor de las notificaciones de ⌘N/⌘O/⌘S/⌘W/⌘F, modos, exportar y paletas; registra el store en el delegado; resuelve el arranque). Al arrancar en la biblioteca no estaba montado y la app quedaba sin comandos.
- Commits: `2d1411b` (editor siempre montado bajo la biblioteca), `19a8e34` (sin cromo duplicado), `9d4cf8b`, `4a7e9c2` (buscar escribe en la barra con `.litteraSearchQuery`; engranaje con `@Environment(\.openSettings)`; etiquetas con `LitteraUIFlowRow`), `0f82bb3` (pestañas, ordenación y lista reales; cursor).
- Cursor: dos causas. El editor montado a tamaño completo bajo la biblioteca instalaba zonas de cursor I-beam en toda la ventana (ahora 1×1, invisible y sin clics), y `NSCursor.set()` se pierde en cada movimiento (ahora `onContinuousHover`). Verificado por el propietario.
- Pruebas: compilación correcta; **la suite XCTest no se ejecutó**.

### 2026-10-26 · Recorte de paneles al redimensionar (D67)
- Problema del propietario (capturas): al estrechar la ventana, el contenido de barra lateral e inspector desaparecía por los bordes.
- Intentos fallidos: `824d28c` (repliegue automático de paneles; revertido en `8f2c7f8`, empeoraba el inspector), `04633bb` (truncar la ruta larga del inspector: útil, pero no era la causa), `82e4948` (quitar mínimos interiores: necesario, pero insuficiente).
- Causa verificada en pantalla: macOS dejaba encoger la ventana por debajo del mínimo pero el contenido conservaba unos 1150 pt; SwiftUI lo centraba y recortaba ambos bordes (incluidos los semáforos).
- Solución `60090e4`: `.windowResizability(.contentMinSize)` y contenido que encoge (búsqueda flexible, rejilla adaptable, pestañas desplazables, breadcrumb truncable, orden a icono). Comprobado al ancho mínimo en biblioteca y editor. Compilado y lanzado desde Xcode por el asistente (control del Mac; la shell del puente es una VM Linux sin Xcode).
- Lección: verificar en la app antes de declarar algo arreglado.
- Siguiente paso: `docs/PENDIENTES_Y_ORDEN.md`, Etapa 0 — ejecutar las 177 pruebas (2026-10-27).

### 2026-10-27 · Hoja de ruta 2.0 · Etapas 0 y 1
- Objetivo: Etapas 0 (red de seguridad) y 1 (honestidad y defectos visibles) de `PENDIENTES_Y_ORDEN.md`.
- Rama/commits: `feature/littera-ui-redesign`, `837d420` (Etapa 0), `154a1a7` (Etapa 1).
- Etapa 0: la suite completa pasa (252 pruebas, 9 omitidas a propósito: benchmarks). 298 avisos en `Littera/UI/` por vistas `nonisolated struct …: View` en un proyecto con aislamiento por defecto `MainActor` (errores en Swift 6) → 0; 12 `Text + Text` obsoletos en las vistas de demostración → interpolación. Nuevo `LitteraUIAdapterTests` (11). `probar.sh` comprueba que `Littera/UI/` no usa tipos del backend.
- Etapa 1: quitados tres textos falsos («Modo Solo Lectura», pista de Quick Look, pastilla «Modificado»); «Diseño del documento» con tamaño e interlineado reales (mismas preferencias que Ajustes → Editor), sin «Fuente» inventada, e iconos de formato que aplican el formato real (`.litteraApplyFormat`); ubicación propuesta (Documentos) cuando no hay carpeta elegida; etiquetas de las tarjetas sin aplastar; × y «Exportar PDF / HTML» reales en el inspector de la biblioteca; textos localizados (566 claves es/en).
- Pruebas: 263/263 (9 omitidas), 0 avisos de Swift. En la app (Debug, oscuro): biblioteca con «Notas · iCloud Drive» y ruta real, «#genealogía +5», tamaño 14 → 15 pt, interlineado Amplio en Fuente y Vista previa, B sobre una selección → `**Prueba**` y `⌘Z`. Preferencias devueltas a 14 pt / Normal.
- Proceso: las pruebas se lanzan con `Tools/probar.command` desde Finder (control del Mac); la app, con Run en Xcode. El Mac se bloqueó a mitad de la sesión y hubo que esperar.
- No probado en la app: «Exportar PDF / HTML» desde el inspector de la biblioteca (abre un panel de guardado), ubicación propuesta sin carpeta elegida (la Debug ya tiene «Notas»), tema claro.
- Siguiente paso: Etapa 2 (tema claro, VoiceOver, capturas de referencia).

### 2026-10-27 · Hoja de ruta 2.0 · Etapa 2: validación transversal
- Rama/commit: `feature/littera-ui-redesign`, ver `git log` (Etapa 2).
- Tema claro (Ajustes → Apariencia → Claro, devuelto después a Oscuro, el ajuste del propietario), revisado en biblioteca y los cuatro modos. Fallos encontrados y corregidos:
  - Inspector recortado por ambos lados en Fuente y Visual: el `Picker(.segmented)` nativo del interlineado tiene ancho mínimo rígido. Nuevo `LitteraUISegmented` (estilo terracota, el mismo del ancho de lectura); contenido del inspector fijado al ancho del panel; columna central sin mínimo.
  - El selector imponía «Dividido» al aparecer y pisaba «Vista inicial» (Visual). El editor publica su modo (`.litteraModeDidChange`) y el selector lo refleja.
  - `⌘K`/`⇧⌘O` en la biblioteca abrían la paleta en el editor invisible (1×1). Provisional: el contenedor muestra el editor y repite la petición.
  - «Exportar PDF / HTML» sin fondo de botón (`.borderlessButton` descarta el fondo de la etiqueta) → `.menuStyle(.button)` + `.buttonStyle(.plain)`.
  - Iconos de formato desactivados en Vista previa.
- VoiceOver: etiquetas en botones de icono de la biblioteca y la barra lateral, tarjetas/filas como un elemento con acción «Abrir en Editor». Revisado en código; no se recorrió con VoiceOver activado.
- Capturas de referencia: `docs/referencias-visuales/2026-10-27/` (retiradas el 2026-11-08 al publicar el repositorio: mostraban datos personales) (claro/oscuro × biblioteca, Fuente, Visual, Dividido, Vista previa). `UI_CHECKLIST.md`: sección 2.0 nueva; la de 1.x queda como histórico.
- Pruebas: 263/263, 0 avisos de Swift.
- No probado: recorrido real con VoiceOver, «Aumentar contraste», exportar desde el inspector de la biblioteca hasta el panel de guardado.
- Siguiente paso: Etapa 3 (sacar el centro de mando del editor).

### 2026-10-27 · Hoja de ruta 2.0 · Etapa 3: centro de mando fuera del editor (D69)
- Rama/commit: `feature/littera-ui-redesign`, ver `git log` (Etapa 3).
- Archivos: nuevo `Littera/Integration/LitteraCommandHost.swift`; `LitteraEditorView.swift` (707 → 540 líneas), `LitteraRedesignContainer.swift`, `LitteraWorkspaceView.swift`, `LitteraInspectorView.swift`, `LitteraUIDocument.swift`, `LitteraUIAdapters.swift`, `LitteraApp.swift` (notificaciones `.litteraEditorCommand`, `.litteraFocusEditor`), pruebas.
- Diseño: el anfitrión atiende documentos, paletas, exportar, arranque y avisos de la app; el editor, modo/búsqueda/formato/edición por notificación. Se retira el reenvío provisional de la Etapa 2.
- Hallado en la app y corregido: (1) SwiftUI crea otro editor al pasar de la biblioteca al espacio de trabajo y perdía el modo → `startMode` con el último modo; (2) el selector reenviaba el modo reflejado → solo avisa si lo cambia el usuario; (3) ⌘N/⌘O desde la biblioteca no mostraban el documento; (4) Estado del inspector era un texto fijo; (5) Navegación contaba comentarios YAML y de código; (6) «Estadísticas»/«Propiedades» de la paleta no hacían nada en el rediseño → muestran el inspector.
- Pruebas: 265/265 (9 omitidas), 0 avisos. En la app: ⌘K y ⇧⌘O sobre la biblioteca, «Cambiar a Fuente» desde la biblioteca, cambio de documento conservando el modo, ⌘N desde la biblioteca y ⌘W, Estado «—» sin status, Navegación con los títulos reales, «Estadísticas» con el inspector cerrado.
- Limitación conocida: el editor nuevo pierde selección y desplazamiento al volver de la biblioteca.
- No probado: arranque con «Abrir documento…» (Ajustes → General), cambios externos y conflictos tras el traslado (sin cambios de lógica, solo de sitio).
- Siguiente paso: Etapa 4, que necesita decisiones del propietario (favoritos, notas rápidas, papelera, compartir).

### 2026-10-27 · Hoja de ruta 2.0 · Etapa 4: biblioteca con funciones reales (D70)
- Decisiones del propietario: favoritos en lista propia; notas rápidas = documentos sin título en carpeta propia; papelera de macOS; compartir nativo; etiquetas editables.
- Archivos: nuevos `Littera/Integration/LitteraLibraryServices.swift` (favoritos, notas rápidas, papelera), `Littera/UI/DesignTokens/LitteraUITagEditor.swift`, `LitteraTests/LitteraLibraryServicesTests.swift`; adaptadores, contenedor, biblioteca, barra lateral, inspector, barra del editor, modelos, localización (586 claves es/en).
- Además: la barra lateral navega a secciones de la biblioteca (también desde el editor); «Nuevo documento» de la barra lateral de la biblioteca no hacía nada; quitado «(Return)» falso de «Abrir en el editor»; recuento de la sección en la cabecera; inspector con un documento visible; sin caja de extracto vacía.
- Pruebas: 272/272 (9 omitidas), 0 avisos. En la app: nota rápida «Nota rápida 2026-10-27 10.02.md» creada en `Notas/Notas rápidas/`, etiquetas «prueba, #etapa4» añadidas (YAML `tags: [prueba, etapa4]`) y «etapa4» quitada, filtro de notas rápidas, favorito (recuentos y pestaña), panel Compartir de macOS (cerrado sin enviar), «Mover a la Papelera» con aviso por cambios sin guardar → nota en la Papelera de macOS, recuentos a 0. La carpeta `Notas rápidas` queda creada y vacía.
- Limitación: la biblioteca muestra documentos abiertos, no el contenido de la carpeta (decisión pendiente para la Etapa 5). Un favorito movido o renombrado fuera de Littera deja de reconocerse (se guarda por ruta).
- No probado: notas rápidas sin carpeta autorizada (aviso), compartir un documento sin guardar (texto), Papelera desde el «···» del editor.

### 2026-10-27 · Hoja de ruta 2.0 · Etapa 5: biblioteca, paleta, Preferencias y Zen (D71–D74)
- Decisiones del propietario: la biblioteca muestra todos los .md de la carpeta de Ajustes; Preferencias del rediseño sustituyen a los Ajustes; paleta del rediseño coherente; Zen con botón (D58); «todo preparado para añadir funciones sin modificar nada».
- Commits: `b86e413` (5.1 índice de carpeta, D71), `bd9e2ea` (5.2 paleta + registro de comandos, D72), `601ec71` (5.3 Preferencias + registro de páginas, D73), `3d424b0` (5.4 Zen, D74).
- Arquitectura extensible: `LitteraCommandRegistry.all` (cada comando con su `perform`), `LitteraPreferencesRegistry.pages`; guía en `docs/EXTENDER_LITTERA.md`.
- Paleta única: ⌘K (Todos) y ⇧⌘O (Documentos); documentos de la biblioteca abiertos o no, comandos, etiquetas, `#etiqueta`, Tab entre pestañas. Eliminadas las paletas 1.x y la maqueta.
- Preferencias: misma escena `Settings` (⌘,) con el aspecto del rediseño; todas las páginas pasan al tema y la tipografía del rediseño. Eliminada la maqueta (Cancelar/Listo no aplican: cambios al momento).
- Zen: presentación del espacio de trabajo sin cromo, el editor no se recrea; botón en la barra, Visualización → Modo Zen, paleta, ⌃⌘Z; Esc o × para salir.
- Pruebas: 288 (9 omitidas), 0 fallos, 0 avisos de Swift. En la app: biblioteca con 62 documentos de `Notas`; paleta (búsqueda, `#gen`, pestaña Etiquetas → documentos, «Cambiar a Dividido», ⇧⌘O abre SESSION_LOG cerrado); Preferencias General/Apariencia/Atajos; Zen por atajo y botón, cambio de anchura, salida por Esc y ×.
- Corregido durante la verificación: Esc no cerraba la paleta tras elegir etiqueta; la paleta conservaba la búsqueda al reabrirla; plurales «1 documentos/coincidencias»; rutas sin «~»; filas de Atajos con hueco; los selectores de anchura no reflejaban la preferencia guardada.
- Limitaciones: la barra de menús sigue escrita a mano (un comando nuevo con menú necesita su `Button`); no se recorrió con VoiceOver; atrás/adelante pendiente.
- Siguiente paso: Etapa 6 (cierre de 2.0).

### 2026-10-27 · Pendientes 2.0 y Etapa 6: cierre de Littera 2.0 (D75)
- Commits: `5b252fb` (pendientes: editor conservado, atrás/adelante, menús del registro), `2e4f7f3` (versión 2.0.0, ayuda, documentación).
- Editor conservado: el espacio de trabajo mantiene la misma jerarquía bajo la biblioteca; comprobado que el desplazamiento se conserva al volver.
- Atrás/adelante (D75): historial puro `LitteraUINavigationHistory`, botones de la biblioteca, menú Ir, ⌘[ ⌘] configurables. Comprobado desde el menú Ir. ⌘[ enviado por la herramienta de control no llegó (teclado español: «[» lleva ⌥); el atajo se puede cambiar en Preferencias → Atajos.
- Menús generados desde el registro (`menu:`); «···» de la biblioteca con acciones reales; quitado el botón «info» sin función.
- Accesibilidad: árbol AX de biblioteca y espacio de trabajo revisado en la app real; todos los botones tienen etiqueta. No se recorrió con VoiceOver activado.
- Etapa 6: versión 2.0.0 (build 12); ayuda integrada es/en actualizada; `PROJECT_CONTEXT.md` y `UI_CONTRACT.md` reescritos (1.x en `docs/historico/`); README y AGENTS; prueba de rendimiento del índice (2 000 documentos: 3,3 s la primera pasada en segundo plano, 0,15 s con caché).
- Pruebas: 293 (9 omitidas), 0 fallos, 0 avisos de Swift. Release: compilado, firmado (firma local, sin Developer ID) y `dist/Littera-2.0.0.dmg` (6,8 MB).
- No probado: instalar el DMG y abrir la versión Release (usa las preferencias reales, no las de Debug); Instruments; VoiceOver activado.
- Siguiente paso: que el propietario pruebe el DMG y autorice la fusión de `feature/littera-ui-redesign`.

### 2026-10-27 · Instalación: «Abrir con», categoría de Apps y ventana en el escritorio actual
- Info.plist: `CFBundleDocumentTypes` (Markdown como editor, texto sin formato como alternativa), `UTImportedTypeDeclarations` de `net.daringfireball.markdown` y `LSApplicationCategoryType` = productividad.
- `LitteraApplicationDelegate`: abre los archivos que manda Finder (también antes de que exista la ventana), lleva la ventana al escritorio actual y, al pulsar el Dock, reutiliza la ventana en vez de crear otra. El contenedor muestra el editor al recibirlos.
- Hallado en la app: macOS restauraba la ventana en otro escritorio y SwiftUI creaba una segunda al pulsar el Dock; `handlesExternalEvents` dejaba una ventana vacía (retirado).
- `crear-dmg.sh` da de baja en LaunchServices la copia compilada temporal para que no compita con la instalada.
- Comprobado con la app instalada desde el DMG: Littera aparece en «Abrir con»; abrir un .md con la app cerrada y con la app abierta muestra el documento en el editor, una sola ventana. Pruebas: 293.
- No comprobado: que Littera aparezca en la app Apps (no es visible para el control remoto).

## Plantilla para futuras entradas
### YYYY-MM-DD · Fase/tarea
- Objetivo:
- Rama/commit:
- Archivos afectados:
- Cambios y decisiones:
- Pruebas ejecutadas y resultado:
- Capturas de interfaz/revisión visual:
- Limitaciones o bugs:
- Siguiente paso:

### 2026-11-06 · Derivaciones durante la edición
- Se evita publicar cada resultado intermedio si el texto ya cambió; se mantiene una sola derivación simultánea por documento y se permiten publicaciones periódicas durante escritura continua. Esto reduce actualizaciones de presentación redundantes, sin modificar el diseño.
- La prueba nueva comprueba que una edición rápida termina publicando la última versión sin publicar la intermedia. La paridad de localización es/en pasó (606 claves).
- La batería anterior al cambio falló en dos pruebas que esperan una derivación inicial síncrona, aunque la implementación ya es asíncrona. Las mediciones de cambio de modo de esa ejecución variaron entre 46 y 259 ms; no son una garantía de respuesta ni una comparación estadística.
- Pendiente: medir CPU, memoria y latencia de la aplicación completa con documentos reales y comparar capturas en claro y oscuro. Revisar el guardado verificado cuando el archivo desaparece durante la coordinación y las pruebas antiguas que presuponen análisis síncrono.
- Validación posterior: compilación Debug y 11 pruebas específicas en verde (derivación rápida y 10 pruebas de cambio de modo). En una ejecución, cambios de modo de 41 a 296 ms; sin evidencia suficiente para afirmar una mejora estadística ni que el cambio sea instantáneo. La batería completa no se repitió tras el cambio.

### 2026-11-07 · Auditoría, decisiones v1 y bloque A
- Objetivo: auditar el proyecto, decidir la simplificación «Littera v1» y corregir los defectos críticos antes de tocar la interfaz.
- Rama/commit: `feature/littera-ui-redesign`, de `f1585aa` a este commit; respaldo previo en `backup/pre-v1-30caf81`.
- Hallazgos principales: suite en rojo (17 casos de 306) frente a «293 en verde» documentados; guardado que fallaba tras escribir (cuarentena del sandbox); pérdida de ediciones al cancelar la salida; enlaces simbólicos, archivos borrados y de solo lectura mal tratados; sesión que se borraba con un fallo pasajero; memoria de 0,5–1,25 GB con documentos de 72–131 KB; redimensionar con documentos grandes muy lento. Las cifras de `30caf81` no eran válidas.
- Decisiones del propietario: D76–D80 (ventana v1 sin biblioteca/inspector/Zen, tres modos sin Visual, barra de estado oculta por omisión, local-first, paleta y Preferencias mínimas).
- Cambios: H1–H6 corregidos, Fix A revertido, documentación al día (`PENDIENTES_Y_ORDEN.md` reescrito; la versión 2.0 en `docs/historico/`).
- Pruebas: suite completa 311 (9 omitidas), 0 fallos; paridad es/en 607 claves. A/B de rendimiento en Release con corpus sintético, en copias temporales.
- No comprobado: nada de lo anterior en la app real (solo XCTest en el anfitrión con sandbox); VoiceOver; iCloud entre dispositivos.
- Siguiente paso: bloque C, paso 1 (ventana v1 con barra nativa).

### 2026-11-07 · Bloques B, C y D de Littera v1
- Rama/commit: `feature/littera-ui-redesign`, de `5018d3a` a este commit.
- C (simplificación v1, revisada por el propietario en la app tras cada paso de interfaz): ventana con barra nativa, Visual retirado (una sola NSTextView, ⌘1–⌘3, Deshacer entre modos), biblioteca/barra lateral/inspector/Zen retirados (~5 370 líneas), paleta sin pestañas con recientes, Preferencias en tres pestañas nativas, barra de estado oculta por omisión, limpieza (265 claves sin uso, ayuda es/en reescrita).
- B (rendimiento): la Vista previa pasa de SwiftUI a TextKit tras medir que costaba ~6 MB por KB de Markdown. A/B en Release con el documento de 131 KB: memoria en Fuente 1 741 → 84 MB, redimensionar 535 → 131 ms por paso, bloqueo al dejar de escribir 241 → 0 ms. Una publicación del store por pulsación y la app sin observar el store. H8 queda parcial.
- D: H11, H12, H13, H14, H18, H19, H20, H21 corregidos; decisiones D81–D83.
- Pruebas: suite completa 302 (9 omitidas), 0 fallos; paridad es/en 350 claves.
- No comprobado: iCloud entre dispositivos (resolución de conflictos), firma Developer ID, VoiceOver, menús tras reiniciar en inglés.
- Siguiente paso: perfilar H8 con Instruments si interesa; pruebas manuales; fusión cuando el propietario lo autorice.

### 2026-11-07 · H8 perfilado y corregido
- Rama/commit: `feature/littera-ui-redesign`, este commit.
- Perfil (Time Profiler, Release, documento sintético de 131 KB, redimensionado sostenido en Fuente): el 89,6 % del hilo principal era `refreshLayout()` de las dos Vistas previas ocultas, que rehacían el diseño de todo el documento en cada cambio de anchura.
- Cambio: oculta, la Vista previa aplaza ese trabajo hasta 0,5 s después del último cambio de anchura o hasta mostrarse, lo que llegue antes.
- A/B en Release (3 rondas alternas, 60 pasos): Fuente 286 → 17 ms por paso, más ~200 ms una sola vez al terminar; Dividido 359 → 224 ms por paso, más ~45 ms; cambios de modo tras redimensionar sin diferencia (~113, ~210 y ~25 ms).
- Corrección: la cifra anterior de ~130 ms por paso y la conclusión de que las Vistas previas ocultas no influían eran erróneas (el arnés no esperaba al refresco asíncrono).
- Desde H21, el arnés de Release necesita `ENABLE_HARDENED_RUNTIME=NO` para cargar el paquete de pruebas (anotado en `AGENTS.md`).
- Pruebas: suite completa 304 (9 omitidas), 0 fallos; 2 nuevas en `LitteraPreviewResizeTests`.
- No comprobado: el redimensionado en la app real con el ratón; sin capturas, porque no cambia nada visible.
- Pendiente opcional: Dividido sigue maquetando la Vista previa visible entera en cada paso.

### 2026-11-07 · H8b: redimensionar en Dividido
- Perfil en Dividido: 55 % en `refreshLayout()` de la Vista previa visible y 29 % en `LitteraScrollCoordinator.sourceSegments` (layout completo del editor para alinear), ambos en cada cambio de anchura.
- Cambio: cuando lo que cambia es la anchura, ambos esperan a que se asiente (0,2 s); los cambios de altura (escritura) siguen alineando al instante.
- A/B en Release (2 rondas, xlarge 131 KB): 111 → 43 ms por paso arriba del documento y 115 → 73 a mitad; posiciones finales de ambos paneles idénticas a la base; cambios de modo iguales.
- Hallazgo sin tocar: Dividido → Vista previa con el documento a mitad cuesta ~1,3 s, ya antes de H8.
- Pruebas: suite completa 305 (9 omitidas), 0 fallos; 1 nueva.
- Revisado por el propietario en la app: durante el arrastre en Dividido la Vista previa no se realinea ni recoloca los botones Copiar hasta soltar, y se ve bien.

### 2026-11-07 · H24: posición de lectura al salir de Dividido
- El «~1,3 s» de Dividido → Vista previa (documento a mitad, 131 KB) no era un bloqueo: el cambio tardaba 36 ms y el arnés medía hasta el último tramo ocupado. El tramo mayor (82 ms a los 0,22 s) era `recordSourcePosition` del editor oculto: SwiftUI lo ensancha al salir de Dividido, su texto refluye y el cambio de bounds se registraba como desplazamiento, con layout completo y pisando la posición de lectura.
- Efecto visible del error: al volver a Fuente la posición retrocedía (0,50 → 0,37 del documento) y seguía mal al volver a Vista previa.
- Cambio: el editor no registra desplazamientos mientras está suspendido en Vista previa.
- A/B en Release (2 rondas): Dividido → Vista previa 168–200 ms repartidos en 1,3 s → 32 ms; Fuente → Dividido → Vista previa 289–303 → 28 ms; Vista previa → Fuente 42 → ~195 ms (ahora restaura la posición correcta, el mismo coste que Fuente → Dividido). Posiciones de ida y vuelta estables.
- Pruebas: nueva `testReadingPositionSurvivesLeavingSplit` (falla sin el cambio); suite completa 306 (9 omitidas), 0 fallos.
- Comprobado por el propietario en la app: la posición se mantiene al alternar Dividido, Vista previa y Fuente con un documento largo.

### 2026-11-07 · Revisión de menús, paleta y comandos
- Revisados: barra de menús real (volcada desde el anfitrión de pruebas, es/en), menú `···`, botones de la barra, paleta ⌘K y de documentos ⇧⌘O, registro central, atajos por defecto y sus conflictos, comandos que dependen del modo.
- Duplicados reales: dos separadores seguidos en Archivo (SwiftUI añade uno por cada grupo estándar vacío; ninguna combinación de grupos lo evita) y separador final en Visualización. Corregido: se quita el separador sobrante de Visualización y, al abrir la barra de menús, se ocultan los separadores redundantes (`LitteraMenuTidy`), sin tocar entradas, acciones ni atajos.
- Entradas obsoletas: «Nuevo texto plano» y «Abrir carpeta» en `···` (deshabilitadas; funciones retiradas o fuera de v1, D76). Retiradas junto con sus claves.
- Incoherencia: el tooltip del título decía «(⇧⌘O)» fijo aunque el atajo es configurable; ahora muestra el atajo configurado.
- Sin cambios: no hay atajos repetidos en la barra de menús ni entre los atajos por defecto; todos los comandos del registro tienen acción y localización es/en; formato y edición se deshabilitan en Vista previa en la paleta.
- No resuelto (requiere decisión): `UI_CONTRACT.md` incluye «Compartir» en Archivo, `···` y la paleta, pero no existe en el código; añadirlo es un control nuevo. El contrato tampoco muestra el botón de propiedades de la barra, aprobado en C1.
- Pruebas: `LitteraCommandEntryTests` (7). Las 3 de foco de teclado se omiten si la app de pruebas no está al frente; pasaron en las ejecuciones aisladas con la ventana clave y se omitieron en la suite completa. Suite completa 313 (12 omitidas), 0 fallos.

### 2026-11-07 · Propiedades gestionadas del frontmatter (D84)
- Antes: el esquema ya tenía title, description, tags, author, created, version, status y project; faltaban `updated` y `requirements`, y `created` no se podía editar una vez puesta. Cada edición **normalizaba** todo el frontmatter (añadía ~30 claves vacías, lo reordenaba en secciones con comentarios), en contra de D53 y de esta petición. En Vista previa el cambio iba directo al documento y volver a Fuente vaciaba el historial de deshacer. Un frontmatter sin cierre se trataba como inexistente: editar habría añadido un segundo bloque.
- Ahora: D84. Edición mínima por clave; claves gestionadas siempre visibles; `created`/`updated` editables; detección de YAML no seguro con aviso y panel de solo lectura; edición en Vista previa por el editor oculto (deshacer al volver). La plantilla de documento nuevo es idéntica (no incluye `updated` ni `requirements`).
- Pruebas actualizadas por el cambio de comportamiento (no debilitadas): `testEditShiftsSelectionAfterFrontmatter` y `testEditFillsEmptyFrontmatterAndCreatesMissingOne` comprueban el resultado exacto sin normalizar; `testPanelShowsEveryPropertyEvenWhenMissing` → `testPanelShowsManagedPropertiesAndOnlyThePresentOthers`; `testRemovingASchemaKeyLeavesItEmpty` → `testRemovingAKeyRemovesOnlyItsLines`; `testNewDocumentTemplate` ya no cuenta los campos del panel y comprueba que la plantilla no cambia.
- Pruebas nuevas: `LitteraManagedPropertiesTests` (10: ejemplo completo, una sola línea cambiada, `version "2.10"`, listas en bloque y en línea, claves desconocidas y comentarios, Unicode, vacías y ausentes, sin frontmatter, YAML no seguro, estados propios) y `LitteraManagedPropertiesEditorTests` (3, con el editor real y archivos temporales: sin guardar y marcado como modificado, deshacer/rehacer, guardar y volver a abrir, Vista previa).
- Capturas del panel renderizado fuera de pantalla (claro, oscuro, sin frontmatter, YAML no seguro). Suite completa 326 (12 omitidas), 0 fallos; paridad es/en 352 claves.
- No comprobado en la app real con ratón y teclado: el popover desde la barra, `···` y la paleta; la verificación es con XCTest y renderizado.

### 2026-11-07 · Una sola anchura del texto (D85)
- El propietario señaló que «Anchura del texto» y «Anchura de Fuente» en `···` hacían lo mismo en modos distintos (mismas medidas; Fuente añadía «Disponible»). Ahora hay una sola «Anchura del texto» con cuatro opciones para los tres modos: un submenú en `···`, un control en Ajustes → Editor y cuatro comandos en la paleta (nuevo «Anchura disponible»). En Vista previa, «Disponible» deja solo los márgenes mínimos.
- Migración: si solo estaba guardada la anchura de Fuente, pasa a la anchura del texto; la clave antigua se conserva. Claves `ui.anchura.de.fuente` y `ui.anchura.de.lectura` retiradas; ayuda es/en al día.
- Pruebas: `testOneTextWidthDrivesSourceAndPreview` y `testOnlyASourceWidthChoiceIsMigrated`. Suite completa 330 (12 omitidas), 0 fallos.
- Revisado por el propietario en la app: el submenú de `···` y el orden del frontmatter se ven bien.

### 2026-11-07 · Orden de las propiedades (D84 ampliada)
- Petición del propietario: el frontmatter debe seguir el orden del panel aunque las propiedades se añadan en otro (su documento tenía `updated` primero). Al editar desde el panel, las diez gestionadas se colocan en ese orden en los huecos que ya ocupaban; las demás claves, `toc` y los comentarios sueltos no se mueven; un comentario pegado a una clave viaja con ella. Una nueva entra tras la gestionada que la precede (`updated` tras `created`). Abrir no reordena.
- Excepción: un frontmatter con las secciones de la plantilla (`# AUTORÍA`, `# FECHAS`…) conserva el orden de sus secciones (reordenar mezclaba claves entre secciones; lo detectaron las pruebas de la plantilla).
- Pruebas: `testManagedKeysFollowThePanelOrderWhenEditing` (el caso de la captura), `testTemplateSectionsKeepTheirOrder`; dos resultados esperados actualizados por la nueva colocación.

### 2026-11-07 · Icono adaptable a claro y oscuro (D86)
- Antes: `AppIcon.appiconset` con PNG que llevaban dibujados el recuadro blanco, las esquinas y la sombra; no podía cambiar con el tema.
- Ahora: `Littera/AppIcon.icon` (Icon Composer, macOS 26+; el proyecto exige 27.0). La capa `Assets/glyph.png` es el trazo del icono anterior extraído por luminancia y escalado al lienzo de 1024 px (el recuadro original ocupaba 66–957 px); los colores van en `icon.json` por apariencia (claro, oscuro, tintado). El grupo sincronizado del proyecto lo incluye sin tocar `project.pbxproj`; `ASSETCATALOG_COMPILER_APPICON_NAME` sigue siendo `AppIcon`.
- Comprobado: la compilación genera en `Assets.car` variantes `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua` e `ISAppearanceTintable`, más `AppIcon.icns` de respaldo; renderizados la variante clara (del `.icns`) y la oscura (con el sistema en oscuro). Suite completa 330 (12 omitidas), 0 fallos; Release compila.
- Límites: la capa es un mapa de bits de 1024 px (no un SVG), suficiente para todos los tamaños de macOS; no se pudo renderizar la variante clara por IconServices con el sistema en oscuro, porque la elige el ajuste del sistema.
- Estilo «Transparente» (oscuro): Littera sale claro, como Notas; WhatsApp y Terminal salen oscuros porque su icono por omisión ya es oscuro o de color. Reiniciar el Dock no cambió nada (no era la caché). Probado y deshecho: un fondo `system-dark` para la apariencia `tinted` más cristal en el trazo; el Dock lo ignora. Decisión del propietario: dejarlo así (blanco en Predeterminado, oscuro en Oscuro, claro en Transparente).
- Comprobado por el propietario en su Mac: los estilos Oscuro y Tintado muestran las variantes correctas; solo Transparente sale claro (limitación conocida, ver D86).
- **Corrección:** lo anterior sobre «Transparente» era un diagnóstico erróneo. `ictool` (Icon Composer) genera bien las seis apariencias del icono guardado, también Traslúcido oscuro (fondo oscuro, trazo blanco), y el Dock mostró bien Traslúcido claro. El Traslúcido oscuro claro del Dock es la caché de iconos del sistema con el icono antiguo (reiniciar el Dock no la borra). Probado y deshecho: activar el cristal en el trazo (no cambia el resultado). Para comprobar: `ictool Littera/AppIcon.icon --export-image --output-file x.png --platform macOS --rendition ClearDark --width 256 --height 256 --scale 1` (en `Icon Composer.app/Contents/Executables/`).
- **Confirmado en el Dock del propietario:** una copia de Littera con el icono guardado y otro identificador de app (sin historial en el sistema) sale bien en Traslúcido oscuro (fondo oscuro, trazo blanco), igual que tres variantes del fondo. El icono compilado por Xcode es idéntico al compilado a mano. El icono no necesita cambios: la Littera de Xcode (`com.cnyps.es.Littera.debug`) conserva la imagen antigua de ese estilo; borrar `/Library/Caches/com.apple.iconservices.store` y reiniciar el Dock no bastó (falta comprobar tras reiniciar el Mac).
- **Resuelto:** tras limpiar el proyecto y su carpeta de compilación en Xcode, la Littera del propietario sale bien en Traslúcido oscuro. La causa era la compilación incremental de Xcode, que conservaba restos del icono anterior; no la caché del sistema ni el icono. Remedio documentado en D86: Product → Clean Build Folder tras cambiar el icono.

### 2026-11-08 · Revisión para la versión candidata y 1.0.0 RC1
- Revisión del proyecto para la release candidate (lista completa en la conversación con el propietario). Bloqueos encontrados: 75 copias «… 2.swift» y una `Littera 2.help` creadas por la sincronización de iCloud (el proyecto está en `~/Documents`) rompían la compilación desde cero, porque el grupo sincronizado del proyecto las incluía; idénticas a sus originales y sin versionar, movidas a la Papelera con autorización. Compilación Release desde cero y suite completa en verde (330, 12 omitidas). Recomendado: mover el proyecto fuera de iCloud.
- Versión: `MARKETING_VERSION` 2.0.0 → **1.0.0**, build 12 → **13** (RC1). `CFBundleShortVersionString` solo admite números: la etiqueta RC1 va en el DMG (`ETIQUETA=RC1 Tools/crear-dmg.sh`) y en la documentación. Una RC2 sería 1.0.0 con build 14.
- Licencias y copyright: hechos (D87). Pendiente para la RC: decisión sobre «Compartir»; documentación desfasada (`AGENTS.md` y `PROJECT_CONTEXT.md` con «Estado de transición», `UI_CONTRACT.md`, `UI_CHECKLIST.md`, `docs/Littera-Ayuda.md`, archivos de la etapa 2.0 en la raíz y en `docs/`); aviso de `Info.plist` copiado como recurso; DMG; pruebas manuales.
- Acerca de (D87): copyright en el `Info.plist` y `Credits.html` (es/en) generados con los textos originales de las licencias de las dependencias resueltas (swift-markdown 0.8.0 con su NOTICE, swift-cmark 0.9.0 sin las partes de pruebas y especificación, que no van en la app) y de las fuentes. La entrada «Acerca de Littera» abre el panel estándar con esos créditos en el idioma de la interfaz y el color de texto del sistema. Comprobado capturando el panel real en claro y oscuro. Suite completa 334 (12 omitidas), 0 fallos; paridad es/en 352 claves.
- «Compartir» retirado del contrato de interfaz (D88). `UI_CONTRACT.md` alineado con lo aprobado: ya no dice que el código muestra la interfaz 2.0, incluye el botón de propiedades de la barra y la anchura del texto única (D85). Sin cambios en la app.
- Documentación para la RC1: a `docs/historico/` pasan `CODEX_HANDOFF`, `CODEX_INICIO`, el `UI_CHECKLIST` y el `TRANSLATIONS` de la raíz, `IMPLEMENTATION_PLAN`, `PHASE0-MANUAL-CHECKLIST`, `UI_INTEGRATION_ADAPTERS`, `Littera-Ayuda` (la ayuda vigente es `Littera.help`) y el `UI_CHECKLIST` de 2.0/1.x. Nuevo `docs/UI_CHECKLIST.md` para la 1.0.0 RC1, con cada punto marcado [XCTest] o [manual]. `AGENTS.md` y `PROJECT_CONTEXT.md` sin «Estado de transición»; `PENDIENTES_Y_ORDEN.md` con lo que falta para cerrar la RC1.
- Aviso de compilación resuelto: `Info.plist` se copiaba también como recurso porque la carpeta `Littera` es un grupo sincronizado; se excluye con una excepción de pertenencia en `project.pbxproj` (como la crea Xcode). Compilación Release desde cero sin avisos propios; el `Info.plist` de la app conserva todas sus claves. Suite completa 334 (12 omitidas), 0 fallos.
- DMG de la RC1: `dist/Littera-1.0.0-RC1.dmg` (6,3 MB; `dist/` no se versiona). Verificado montándolo en solo lectura: suma válida, 1.0.0 (13), firma local válida, sandbox. La primera versión llevaba `com.apple.security.get-task-allow` (permiso de depuración que Xcode añade al firmar en local), que impide notarizar y que el script arrastraría a una firma Developer ID: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` en Release (Debug lo conserva para depurar) y el script lo borra al firmar con Developer ID y se detiene si aparece. DMG regenerado y verificado sin ese permiso. `spctl` rechaza la app, como corresponde a una firma local sin Developer ID.

### 2026-11-08 · Littera 1.0.0 final
- Revisión de cierre: sin copias de iCloud, compilación Release desde cero sin avisos propios, suite completa 334 (12 omitidas), 0 fallos, paridad es/en 352 claves.
- Cambios de la final (build 14): `InfoPlist.strings` es/en para el tipo de documento «Texto sin formato» («Plain text»); comentario del modo `chromeless` al día. Se mantienen a propósito `chromeless` (pruebas) y `sourceWidth` (migración).
- DMG: `dist/Littera-1.0.0.dmg` verificado montándolo en solo lectura (1.0.0 (14), firma local válida, sandbox, marcadores y archivos elegidos, sin `get-task-allow`).
- Etiqueta local `v1.0.0` (anotada). No se sube: el repositorio no tiene remoto.
- No comprobado: los puntos [manual] de `UI_CHECKLIST.md` que el propietario no revisó en la sesión (VoiceOver, «Aumentar contraste», inglés tras reiniciar, iCloud con dos Macs, exFAT/SMB, archivos grandes, DMG instalado y actualizado); pasan a la siguiente iteración, propuesta en `PENDIENTES_Y_ORDEN.md`.

### 2026-11-08 · Diagramas Mermaid invisibles en la Vista previa (tras la 1.0.0)
- Síntoma (documento real del propietario, revisado en una copia temporal con su permiso): los diagramas no se veían en Vista previa ni en Dividido; ni siquiera ocupaban espacio.
- Causa: la Vista previa ajusta cada imagen a la columna cambiando `attachment.bounds`, pero TextKit no se entera de ese cambio. Al construirse, antes de que la vista tenga su ancho real, la columna mide 1 punto: el diagrama se maquetaba con ~1 punto de alto y conservaba esa línea aunque luego recuperara su tamaño. La imagen y su `bounds` eran correctos (por eso las pruebas que solo miraban `bounds` no lo detectaban).
- No lo introdujo H8: la prueba de regresión también falla con el código anterior a H8 (`866e8b7`); viene de la Vista previa TextKit (B2).
- Corrección (`LitteraPreviewTextView.fitAttachments`): no se ajusta mientras la columna no tiene un ancho válido, y al cambiar el tamaño de un adjunto se invalida su maquetación y su dibujo.
- Prueba: `LitteraPreviewDiagramLayoutTests` mide la altura con la que TextKit maqueta el diagrama en Vista previa y Dividido (ventana completa, documento abierto desde archivo): 0,95 pt sin la corrección, su altura real con ella. Suite completa 335 (12 omitidas), 0 fallos.
- Observado, sin tocar: un diagrama muy ancho (p. ej. 21 nodos en `TD`) se reduce a la columna y su texto queda muy pequeño.
- **Littera 1.0.1** (build 15, etiqueta local `v1.0.1`): publica esta corrección. Compilación Release desde cero sin avisos propios, suite completa 335 (12 omitidas), 0 fallos, paridad es/en 352 claves. DMG `dist/Littera-1.0.1.dmg` verificado montándolo (1.0.1 (15), firma local válida, sandbox, sin `get-task-allow`).

### 2026-11-08 · Publicación en GitHub
- Repositorio público `https://github.com/jorgemfb/littera`, licencia **MIT** (decisión del propietario), README público nuevo (es, con resumen en inglés) y `LICENSE` con la nota de componentes de terceros.
- Auditoría previa del historial completo: sin secretos, claves ni archivos de firma; ningún archivo de más de 2 MB; el contenido del documento personal del propietario nunca estuvo versionado. Sí había datos personales: su correo en 197 commits (y otro en 24) y las capturas `docs/referencias-visuales/2026-10-27/` (nombre de su árbol genealógico, etiquetas con apellidos, rutas de su carpeta). Las capturas se retiran del árbol.
- Decisión del propietario: publicar un **historial nuevo y limpio** (rama local `publico`, un commit con el árbol de la 1.0.1 firmado con `48606989+jorgemfb@users.noreply.github.com`); `main` conserva el historial completo solo en este Mac. Procedimiento para versiones futuras en `PENDIENTES_Y_ORDEN.md`.
- El binario se adjunta a mano en la Release de GitHub (sin la herramienta `gh` no se puede subir sin un token).
