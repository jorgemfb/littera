# Reglas del repositorio Littera para agentes (Codex, Claude)

**Lee antes de modificar nada**: `docs/PROJECT_CONTEXT.md`, `docs/DECISIONS.md` (sobre todo D76–D88), `docs/UI_CONTRACT.md` y `docs/UI_CHECKLIST.md`. Para añadir comandos o páginas de Preferencias, `docs/EXTENDER_LITTERA.md` (sus apartados sobre biblioteca, inspector y pestañas de la paleta quedan obsoletos por D76 y D80).

## Objetivo
**Littera v1**: editor Markdown nativo de macOS, precioso, calmado y rápido. Abrir un archivo, escribir, previsualizar, buscar y guardar; nada más debe estorbar. **Local-first**, con iCloud Drive opcional (D79). iPadOS e iOS, pospuestos hasta tener macOS estable.

**Estado (2026-11-08):** **1.0.1** (build 15, etiqueta local `v1.0.1`) en `main`; la 1.0.0 es `v1.0.0`. La siguiente iteración está propuesta en `docs/PENDIENTES_Y_ORDEN.md` y espera la aprobación del propietario. Repositorio público: `https://github.com/jorgemfb/littera` (licencia MIT), con un historial propio y limpio en la rama local `publico`; el historial completo solo está en este Mac. Subir requiere autorización del propietario.

## Límites obligatorios
- **Una sola barra superior nativa** de macOS: título del documento centrado y pulsable (abre los documentos abiertos) y, a la derecha, propiedades, lupa y `···`. Sin pestañas, selector de modos, segunda fila, biblioteca, barra lateral, inspector ni barras permanentes (D76). La barra de estado existe, pero está oculta por omisión (D78).
- **Tres modos**: Fuente, Dividido y Vista previa (D77). Se eligen con ⌘1–⌘3, el menú Visualización o la paleta.
- `⌘K`: paleta de comandos y documentos abiertos o recientes. `⇧⌘O` o clic en el título: documentos abiertos. Flechas, Intro y Esc con el foco de teclado correcto desde cualquier ruta de apertura (D13, D80).
- Las acciones de formato son **comandos del registro central** (`LitteraCommandRegistry`), no paneles ni botones sueltos. Se deshabilitan las acciones sin implementar. `⌘K` nunca inserta enlaces (`⇧⌘K` es el enlace).
- **Un mismo `.md`** es la fuente de verdad de los tres modos. El render no inventa información que no esté en el documento. Archivos Markdown estándar en UTF-8, accesibles desde Finder.
- Swift, SwiftUI, AppKit, Foundation y frameworks nativos. **Nada de Electron, WebView ni motores HTML/JS para el editor.** Sin Python, Homebrew ni dependencias de desarrollo innecesarias. Una dependencia externa o un cambio de arquitectura se discute antes de introducirlo.
- **Local-first**: usable sin Internet y sin Apple ID. iCloud Drive solo con consentimiento expreso, sin mover nunca documentos; conflictos resueltos sin pérdida silenciosa (D50, D79).
- **Integridad de los documentos por encima de todo**: guardar nunca sobrescribe en silencio un archivo cambiado fuera, ni descarta ediciones sin una decisión explícita del usuario, ni da por fallido un guardado que ya se escribió. Cualquier pérdida de metadatos (atributos extendidos, etiquetas de Finder, fechas, permisos, hard links) se trata como riesgo crítico y se documenta.
- Textos de interfaz exclusivamente por claves en `Localization/<lang>.lproj/Localizable.strings`; español por defecto, inglés incluido, configurable en Preferencias. Nunca se traducen documentos, rutas ni nombres de archivo. Los menús nativos se prueban también tras reiniciar.
- `UserDefaults` para las preferencias; ninguna base de datos sustituye a los archivos Markdown. No se rompen claves persistidas sin migración.
- Antes de cada fase: rama o commit de respaldo. Después: compilación real con Xcode, pruebas unitarias y de UI, validación de traducciones, capturas en claro y oscuro e informe de archivos cambiados y riesgos. **No se afirman pruebas ni mediciones que no se hayan ejecutado.**

## Proceso de trabajo
1. **Una funcionalidad o un cambio por tarea**, siguiendo el plan aprobado (bloques A: correcciones críticas, B: rendimiento, C: simplificación v1, D: opcionales).
2. Antes de escribir código: revisar estas reglas y las decisiones aplicables, inspeccionar la implementación actual, identificar los archivos estrictamente necesarios y presentar un plan breve.
3. Durante la implementación: limitarse al alcance autorizado, sin refactorizaciones ajenas ni dependencias nuevas sin autorización.
4. Después: compilar, ejecutar la suite completa, comprobar que no hay regresiones, verificar la interfaz con capturas, documentar lo hecho y lo pendiente, y crear un commit específico.
5. Si una instrucción entra en conflicto con el código o con una plataforma Apple, mostrar la evidencia y proponer el menor cambio seguro antes de aplicarlo.

No hacer merge ni push sin autorización.

## Mediciones de rendimiento
- Siempre en Release (`ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO` para las pruebas: con Hardened Runtime el anfitrión no carga el paquete de pruebas firmado en local), con el mismo corpus sintético y el mismo arnés antes y después; nunca con documentos del usuario.
- Medir hasta que el hilo principal quede inactivo un intervalo mayor que cualquier trabajo aplazado (por ejemplo, 0,8 s si hay tareas a 0,4 s), y declarar el trabajo total, no solo la primera respuesta.
- Comparar con la versión anterior en el mismo arnés (A/B). Un resultado que no se pueda reproducir no se publica en un commit.

## Contrato de estabilidad visual
La interfaz de destino es **Littera v1** (D76–D80 y `docs/UI_CONTRACT.md`). Fuera de los pasos aprobados del plan de simplificación, un agente **no** puede:
- cambiar colores, tipografías, tamaños, espaciados, distribución o jerarquía visual;
- añadir, eliminar o reubicar botones, menús, paneles o controles;
- modificar barras de título, controles nativos o el comportamiento de las ventanas;
- introducir animaciones o efectos no aprobados;
- cambiar el sistema de temas o la arquitectura de localización;
- sustituir componentes nativos por implementaciones visuales propias.

Sí puede implementar funcionalidades que ya tengan un punto de entrada, conectar comandos existentes a lógica real, crear modelos y servicios, corregir errores funcionales, añadir pruebas y refactorizar internamente sin alterar el resultado visual.

Si una funcionalidad requiere tocar la interfaz fuera del plan: detenerse, explicar el cambio visual necesario y por qué, proponer alternativas compatibles y esperar autorización expresa. Una petición de funcionalidad no es una autorización implícita para rediseñar.

**Criterio de aceptación**: una tarea solo está terminada cuando funciona, no introduce regresiones, respeta la arquitectura aprobada y supera sus pruebas. Un `BUILD SUCCEEDED` no demuestra que una funcionalidad esté terminada.

## Fuente de verdad
Prioridad: decisiones más recientes de `docs/DECISIONS.md` (D76–D80 prevalecen sobre D56–D75) + `docs/UI_CONTRACT.md` > propuestas antiguas > ejemplos temporales. El código describe el estado actual; una maqueta no demuestra funcionalidad. No adivinar funciones ausentes. Los documentos de versiones anteriores están en `docs/historico/`.
