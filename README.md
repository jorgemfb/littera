# Littera

Editor de Markdown **nativo para macOS**, escrito en Swift, SwiftUI y AppKit. Abrir un archivo, escribir, previsualizar, buscar y guardar; nada más debe estorbar.

- **Local-first:** funciona sin conexión y sin cuenta. Tus documentos son archivos `.md` estándar en UTF-8, en las carpetas que tú elijas. iCloud Drive es opcional.
- **Tres modos:** Fuente, Dividido y Vista previa (`⌘1`, `⌘2`, `⌘3`), sobre el mismo archivo.
- **Paleta de comandos** (`⌘K`) con los comandos y los documentos abiertos o recientes.
- **Markdown CommonMark y GFM:** tablas, tareas, tachado, bloques de código con resaltado y diagramas **Mermaid** dibujados de forma nativa.
- **Propiedades del frontmatter YAML** editables desde un panel (`title`, `description`, `tags`, `author`, `created`, `updated`, `version`, `status`, `project`, `requirements`), sin tocar el resto del YAML.
- **Exportación** a PDF y HTML, con índice opcional.
- Interfaz en **español e inglés**, claro y oscuro, atajos configurables.

**Versión actual:** 1.0.1 · **Requisitos:** macOS 27 o posterior.

## Instalación

1. Descarga `Littera-1.0.1.dmg` desde [Releases](https://github.com/jorgemfb/littera/releases).
2. Abre el DMG y arrastra **Littera** a **Aplicaciones**.
3. **La primera vez**, macOS avisará de que no puede comprobar el desarrollador: esta versión no lleva firma Developer ID ni notarización de Apple. Abre Littera con **clic derecho → Abrir → Abrir**, o ve a **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**. Solo hace falta una vez.

Littera se ejecuta en la sandbox de macOS y no tiene permiso de red: solo accede a los archivos y carpetas que abres o eliges.

## Atajos principales

| Acción | Atajo |
|---|---|
| Nuevo, abrir, guardar, guardar como | `⌘N`, `⌘O`, `⌘S`, `⇧⌘S` |
| Paleta de comandos | `⌘K` |
| Documentos abiertos | `⇧⌘O` o clic en el título |
| Fuente, Dividido, Vista previa | `⌘1`, `⌘2`, `⌘3` |
| Buscar, buscar y reemplazar | `⌘F`, `⌥⌘F` |
| Negrita, cursiva, enlace | `⌘B`, `⌘I`, `⇧⌘K` |

Todos se pueden cambiar en **Ajustes → Atajos**. La ayuda completa está en **Ayuda → Ayuda de Littera**.

## Compilar desde el código

Requisitos: macOS 27 y Xcode 27. La única dependencia, [Swift Markdown](https://github.com/swiftlang/swift-markdown), se descarga sola con Swift Package Manager.

```bash
git clone https://github.com/jorgemfb/littera.git
cd littera
open Littera.xcodeproj
```

En Xcode, elige el esquema **Littera** y pulsa `⌘R`. Para las pruebas, `⌘U`, o desde la terminal:

```bash
xcodebuild test -project Littera.xcodeproj -scheme Littera -destination 'platform=macOS'
```

El instalador se genera con `bash Tools/crear-dmg.sh` (deja `dist/Littera-<versión>.dmg`).

> Consejo: no guardes el proyecto en una carpeta sincronizada con iCloud (como Documentos o Escritorio). iCloud crea copias «… 2.swift» que rompen la compilación.

## Documentación del proyecto

El proyecto se documenta en español:

- [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md): qué es Littera y cómo está construido.
- [`docs/DECISIONS.md`](docs/DECISIONS.md): decisiones de producto y de diseño.
- [`docs/UI_CONTRACT.md`](docs/UI_CONTRACT.md): contrato de la interfaz.
- [`docs/EXTENDER_LITTERA.md`](docs/EXTENDER_LITTERA.md): cómo añadir comandos y páginas de Ajustes.
- [`docs/PENDIENTES_Y_ORDEN.md`](docs/PENDIENTES_Y_ORDEN.md): estado y próxima iteración.
- [`AGENTS.md`](AGENTS.md): reglas de trabajo del repositorio.

## Licencia

Littera se distribuye con la [licencia MIT](LICENSE). © 2026 Jorge Raúl Saavedra Cabrol.

Incluye componentes de terceros con sus propias licencias: Swift Markdown (Apache 2.0), swift-cmark (BSD de 2 cláusulas y MIT), y las fuentes Inter y JetBrains Mono (SIL Open Font License 1.1). Los textos completos están en **Littera → Acerca de Littera**.

---

## English

**Littera** is a native Markdown editor for macOS, built with Swift, SwiftUI and AppKit. It is local-first (no account, works offline, plain UTF-8 `.md` files), with three modes (Source, Split, Preview), a `⌘K` command palette, CommonMark + GFM, native Mermaid diagrams, an editable YAML frontmatter panel and PDF/HTML export. The interface is available in Spanish and English.

Download the DMG from [Releases](https://github.com/jorgemfb/littera/releases). The app is not signed with a Developer ID yet, so the first time open it with **right-click → Open**. Requires macOS 27 or later. To build it, open `Littera.xcodeproj` in Xcode 27 and run the **Littera** scheme. Released under the [MIT License](LICENSE).
