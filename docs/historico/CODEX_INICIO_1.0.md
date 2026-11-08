# Primer mensaje para Codex (copiar y pegar)

Estamos desarrollando **Littera**, un editor Markdown 100 % nativo para macOS, local-first con iCloud Drive opcional. La interfaz **UI 1.0 / iteración 9** ya está diseñada y NO debes cambiarla por tu cuenta.

1. Lee íntegros `AGENTS.md`, `docs/PROJECT_CONTEXT.md`, `docs/DECISIONS.md`, `docs/UI_CONTRACT.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/TRANSLATIONS.md` y `docs/UI_CHECKLIST.md` antes de editar código.
2. Inspecciona el proyecto Xcode **existente** y compara su estado con los archivos fuente recibidos. El paquete de fuentes no incluye `.xcodeproj`. No crees un repositorio o proyecto alternativo sin necesidad.
3. **Primera tarea exclusivamente: Fase 0 (integración, compilación y pruebas de interfaz)**. Detecta errores de compilación y de integración de recursos, especialmente traducciones `es`/`en`, menús de macOS y navegación por teclado con `⌘K` y `⇧⌘O`.
4. Respeta la barra de título de una fila, título centrado pulsable, búsqueda y `···`, ninguna pestaña ni selector de vistas visible, paletas ya aprobadas, esquema claro/oscuro y preferencia local-first.
5. No implementes todavía el motor Markdown, la edición Visual, iCloud ni funciones adicionales. No habilites controles falsos.
6. Trabaja en cambios pequeños, explica el diagnóstico antes de cambiar arquitectura, comprueba con `xcodebuild`/Xcode y `swift Tools/CheckLocalizations.swift`. Registra evidencias, limitaciones y siguiente tarea en `docs/SESSION_LOG.md`.
7. Al concluir, entrega informe: compilación, pruebas, diferencias visuales, archivos modificados, estado Git y dudas concretas que requieran aprobación.

El diseño y futuras modificaciones visuales se decidirán en ChatGPT y se documentarán en estos archivos; tu responsabilidad es hacer que ese diseño funcione, no reinventarlo.
