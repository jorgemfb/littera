# Littera · entrega de interfaz a Codex (UI 1.0 · iteración 8)

## Mandato

Completar Littera como editor Markdown local-first completamente nativo (Swift, SwiftUI, AppKit) respetando **exactamente** la interfaz aprobada. La iteración 8 establece los contratos de Preferencias, incluido almacenamiento local por defecto y una futura opción de iCloud Drive. Ninguna funcionalidad debe rediseñar el editor por su cuenta.

## Aspecto inamovible salvo aprobación explícita

1. **Una única barra de título nativa**, con nombre de documento clicable centrado, lupa y `···` a la derecha. Sin pestañas, selector de vistas visible, segunda barra ni cápsulas personalizadas.
2. `⌘K` para comandos (incluido formato) y `⇧⌘O` / clic en el título para documentos abiertos. Mantener navegación de flechas, Enter y Esc y el foco de teclado al abrir por atajo o por menú.
3. Las dos paletas comparten `LitteraPaletteFrame`. Los comandos se registran en `LitteraCommandRegistry`, la vista no contiene lógica de edición.
4. Respetar los tokens de `LitteraDesignSystem.swift`, con temas suaves claro/oscuro; solo cambiar diseño tras aprobación y capturas comparativas.
5. Preferencias usan `LitteraSettingsComponents.swift`: no duplicar estilos ni dispersar colores, tamaños y medidas en vistas funcionales.
6. El selector de tema existe **solo en Apariencia de Preferencias**. No añadir otro en `···` ni en `⌘K`.
7. No introducir Electron, WKWebView, interfaces web, paneles fijos, inspectores ni sistema de pestañas.

## Contratos de ajustes

Archivo: `Settings/LitteraPreferences.swift`.

| Clave | Tipo | Default | Conexión actual |
|---|---|---|---|
| `littera.appearance` | String (`system`, `light`, `dark`) | `system` | Editor + Preferencias |
| `littera.editor.initialMode` | String (`Fuente`, `Visual`, `Dividido`, `Vista previa`) | `Visual` | Nueva ventana |
| `littera.editor.writingWidth` | String (`Estrecho`, `Medio`, `Ancho`) | `Medio` | Vista previa y menú `···` |
| `littera.editor.sourceFontSize` | Double | `14.0` | Fuente (TextEditor) |

No cambiar los nombres de claves sin migración. Mantener controles inaccesibles/etiquetados «Pendiente» hasta que exista una implementación real. No poner un toggle de «iCloud activado» que no haga nada; no guardar una bandera de sincronización falsa.

## Contrato de almacenamiento y sincronización

- Documentos del usuario = archivos `.md` estándar, **UTF-8**, editables por terceros. La fuente persistente de verdad es el archivo, nunca un formato o base de datos propietarios. Datos derivados (índice/estado UI) pueden guardarse localmente sin sustituir al documento.
- **Local-first:** abrir/crear/editar/guardar debe funcionar sin red, sin Apple ID y sin dependencias externas. Ningún flujo básico puede bloquearse por estado de iCloud.
- **iCloud Drive es opt-in:** ofrecer en Preferencias una ubicación iCloud (cuando esté implementada) como alternativa a una ubicación local. No trasladar carpetas ni documentos existentes por cambiar un ajuste. Proporcionar confirmación explícita de cualquier traslado, vista previa de lo que cambia, recuperación ante errores y capacidad de elegir ubicaciones por documento.
- Evaluar arquitectura de almacenamiento: carpeta de iCloud Drive elegida por el usuario vía `NSOpenPanel` y acceso con security-scoped bookmarks si hace falta; o contenedor ubicuo de la app (con las capacidades/entitlements exigidas). No confundir ambas rutas ni crear entitlements innecesarios. Validar con pruebas en app sandboxed y no sandboxed según distribución.
- Para archivos iCloud sin descargar: mostrar descarga/indisponibilidad; nunca declarar disponibles offline archivos solo remotos. Descargar o mantener copia local si el usuario lo solicita y macOS lo permite.
- Para guardado externo y sincronización: coordinación y observación de ficheros cuando corresponda (`NSFileCoordinator`, `NSFilePresenter`); no sobrescribir silenciosamente cambios concurrentes ni conflictos del proveedor. Usar guardado seguro y versiones/conflictos recuperables. MacOS controla la transferencia iCloud; Littera debe reflejar estado real, no simular progreso.
- No depender de `CloudKit` para sincronizar el contenido Markdown salvo nueva decisión explícita. iCloud Drive permite archivos ordinarios y sincronización gestionada por macOS.
- Una preferencia de iCloud debe ser operativa solo cuando se pruebe: disponible, no disponible, sin cuenta, descarga pendiente, offline, conflicto y fallo en escritura, con casos de prueba.

## Etapas para Codex

1. **Compilar UI 1.0/iteración 8 en Xcode**, corregir únicamente problemas de compilación y accesibilidad sin rediseñar. Guardar capturas base de tema claro y oscuro: título, editor, citas, paletas y siete páginas de Preferencias.
2. Crear gestor real de documentos (new/open/save/close), integrando Finder, permisos, sesiones, cambios pendientes y recuperación. No introducir pestañas. Preservar estado/selección por documento.
3. Parser Markdown (CommonMark/GFM), renderer con los componentes visuales aprobados, Fuente/Dividido/Visual/Vista previa conectados al **mismo** archivo real. Sustituir la maqueta `LitteraSampleDocument` sin inventar atribuciones o comillas que no estén en el documento.
4. Aplicar formatos desde el registro de comandos a la selección/cursor con UndoManager, validación contextual y foco correcto. Solo habilitar acciones cuando funcionen.
5. Conectar opciones pendientes de Preferencias a mecanismos reales: autoguardado, corrección, tipografía, restauración, rutas, etc. Usar el `LitteraPreferences` como contrato. Añadir pruebas.
6. Implementar iCloud Drive opcional separadamente, sin romper el flujo local. Habilitar su control solo tras pruebas de cambios concurrentes, offline y permisos.
7. Exportación, atajos personalizables y funciones adicionales. Cada iteración debe pasar regresiones visuales y de datos.

## Criterios de aceptación mínimos

- 1 sola fila en barra principal; no controles nuevos visibles al añadir funciones.
- `⌘K` y `⇧⌘O` siempre funcionan con teclado y ratón sin pérdida de foco.
- Modo claro, oscuro y sistema coherentes también dentro de Preferencias.
- Ninguna acción de UI de estado «Pendiente» aparenta trabajar.
- Configuraciones persistidas via `UserDefaults` con claves estables; interacción inmediata donde se indica.
- El modo Visual renderiza **datos del `.md` real**, no contenido de demostración.
- Guardar, cerrar y reabrir no pierde datos; apertura concurrente resuelve conflictos sin pérdida silenciosa.
- iCloud apagado/sin conexión no impide trabajar localmente. Elegir iCloud requiere consentimiento del usuario y no mueve ficheros por sorpresa.
- Pruebas de regresión y capturas antes de aceptar cualquier cambio visual.

**Límites reales:** la UI actual no es aún un editor completo. No hay archivos reales ni sincronización iCloud; ambos son trabajo futuro y no deben publicitarse como implementados.

---

## ITERACIÓN 9 · CONTRATO DE LOCALIZACIÓN (OBLIGATORIO)

- Los textos de interfaz, los comandos, los mensajes y los accesos de menú deben utilizar **claves estables** almacenadas en `Localization/<idioma>.lproj/Localizable.strings`. No introduzcas nuevas cadenas visibles en Swift sin extraerlas.
- El idioma se elige desde **Preferencias → General → Idioma de la interfaz** y se conserva en `littera.interfaceLanguage`. El idioma predeterminado es español.
- `Localization/LitteraLocalization.swift` concentra resolución de recursos y localización de menús superiores. No copies lógica de traducción en cada vista.
- Los textos derivados de modelos técnicos (`LitteraEditorMode`, `LitteraWritingWidth`) se traducen para mostrar, **nunca cambies los rawValue persistidos**.
- Los documentos Markdown, nombres de archivo y rutas no se modifican nunca por cambio de idioma.
- Para añadir idiomas, crear únicamente el nuevo `<idioma>.lproj/Localizable.strings` y registrarlo como localización del recurso en Xcode. El selector detecta las localizaciones del bundle; no programar un `switch` con los idiomas.
- Los menús nativos pueden requerir reinicio, y las localizaciones del target son obligatorias. No simules los menús del sistema.
- Conserva intacto el DesignSystem, la barra Zen, las paletas y las teclas `⌘K` / `⇧⌘O`.
- Antes de dar una tarea por terminada: `python3 scripts/check_localizations.py`, `plutil -lint ...`, compilación en Xcode y revisión en es/en de comandos, Preferencias, paletas y menú principal.
