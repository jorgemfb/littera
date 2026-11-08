# Littera 1.0.x · Lista de comprobación

**Versión:** 1.0.1 (build 15; la 1.0.0 fue la 14 y la RC1 la 13). Las listas de etapas anteriores están en `docs/historico/`.

Cada punto indica cómo se comprueba: **[XCTest]** lo cubre la suite automática; **[manual]** necesita la app real (ratón, teclado, VoiceOver, otro Mac…). Marca `[x]` al comprobarlo en la app compilada en Release o instalada desde el DMG; anota debajo cualquier fallo.

## Ventana y barra superior (D76, `UI_CONTRACT.md`)
- [ ] Una sola fila nativa: semáforo, título centrado, botón de propiedades, lupa y `···`. [manual]
- [ ] El punto `•` del título aparece con cambios sin guardar y desaparece al guardar. [manual]
- [ ] Clic en el título y `⇧⌘O` abren los documentos abiertos; el tooltip muestra el atajo configurado. [XCTest + manual]
- [ ] Cerrar la única ventana sale de Littera; con cambios sin guardar, pregunta antes (D82). [XCTest + manual]
- [ ] Redimensionar la ventana con un documento grande es fluido en los tres modos (H8). [manual]

## Modos (D77)
- [ ] `⌘1`, `⌘2`, `⌘3` y el menú Visualización cambian a Fuente, Dividido y Vista previa. [XCTest + manual]
- [x] La posición de lectura se mantiene al alternar los tres modos, también saliendo de Dividido (H24); revisado por el propietario. [XCTest + manual]
- [ ] Deshacer sobrevive al cambio de modo. [XCTest]
- [ ] Dividido: la Vista previa sigue el desplazamiento de Fuente. [XCTest + manual]

## Paletas y teclado (D80)
- [ ] `⌘K` abre la paleta con el foco en la búsqueda; flechas, Intro y Esc funcionan. [XCTest cuando la app está al frente + manual]
- [ ] La paleta de documentos ofrece los abiertos y después los recientes. [XCTest]
- [ ] Los comandos de formato se deshabilitan en Vista previa. [XCTest]
- [ ] `⇧⌘K` inserta un enlace; `⌘K` nunca lo hace. [XCTest]

## Menús
- [ ] Sin entradas repetidas, separadores dobles ni atajos duplicados. [XCTest]
- [ ] «Acerca de Littera» muestra versión 1.0.0 (13), copyright y licencias, legibles en claro y oscuro (D87). [XCTest + manual]
- [ ] Menús en inglés tras elegir English y **reiniciar** la app. [manual]

## Documentos e integridad
- [ ] Abrir, editar, guardar y volver a abrir un `.md` conserva el texto byte a byte (BOM, normalización Unicode). [XCTest]
- [ ] Un archivo cambiado fuera de Littera no se sobrescribe sin preguntar. [XCTest + manual]
- [ ] Un archivo de solo lectura propone Guardar como (H5). [XCTest]
- [ ] Un archivo borrado o movido a la Papelera fuera de Littera se trata sin pérdida (H3, H12). [XCTest + manual]
- [ ] Guardado automático (si se activa en Ajustes) nunca escribe sobre cambios externos (D49). [XCTest]
- [ ] Archivos creados por otras apps (TextEdit, Obsidian, VS Code) se abren y guardan bien. [manual]
- [ ] Archivos de más de 1 MB y carpetas con miles de `.md`. [manual]
- [ ] Volúmenes exFAT y SMB. [manual]
- [ ] iCloud Drive con dos Macs: conflicto, sin conexión y archivos no descargados (D79). [manual]

## Propiedades del frontmatter (D84)
- [ ] Las diez propiedades gestionadas aparecen siempre; las ausentes, vacías. [XCTest]
- [ ] Editar cambia solo la clave editada y ordena las gestionadas como el panel; con secciones de la plantilla, se respeta su orden. [XCTest]
- [ ] YAML no seguro: aviso y panel de solo lectura. [XCTest]
- [ ] Deshacer y rehacer, también desde Vista previa. [XCTest + manual]
- [ ] Panel en claro y oscuro. [manual]

## Apariencia
- [ ] Claro, oscuro y Sistema; «Aumentar contraste» y «Reducir movimiento». [manual]
- [x] Anchura del texto única para los tres modos (D85), desde `···`, Ajustes y paleta; revisado por el propietario. [XCTest + manual]
- [x] Icono en los estilos Por omisión, Oscuro, Traslúcido y Tintado (D86); revisado por el propietario. [ictool + manual]

## Accesibilidad
- [ ] Recorrido completo con VoiceOver: barra, editor, paletas, propiedades, Preferencias. [manual]
- [ ] Texto grande del sistema y tamaño mínimo de ventana sin recortes. [manual]

## Localización
- [x] `swift Tools/CheckLocalizations.swift` pasa (352 claves es/en). [herramienta]
- [ ] Cambiar el idioma en Ajustes actualiza la interfaz; los documentos y nombres de archivo no se traducen. [manual]

- [x] Los diagramas Mermaid ocupan su altura en Vista previa y Dividido (1.0.1). [XCTest]

## Exportación
- [ ] Exportar a PDF y HTML desde Archivo, `···` y la paleta; con índice si `toc: true`. [XCTest + manual]

## Instalación
- [x] `bash Tools/crear-dmg.sh` crea `dist/Littera-1.0.1.dmg` (verificado montándolo: 1.0.1 (15), firma local, sandbox, sin `get-task-allow`). [herramienta]
- [ ] Instalar desde el DMG en `/Applications`, abrir y reabrir documentos recientes (marcadores de seguridad). [manual]
- [ ] Actualizar sobre una versión anterior conserva ajustes, recientes y accesos a carpetas. [manual]

## Compilación y pruebas
- [x] Compilación Release desde cero sin errores ni avisos propios, sin copias «… 2.swift». [herramienta]
- [x] Suite completa en verde (335 pruebas, 12 omitidas, 2026-11-08). [XCTest]
