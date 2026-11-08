# Cómo añadir funciones a Littera

**Vigente desde:** 2026-10-27 (D72–D73), actualizado para Littera v1 el 2026-11-07 (D76–D80). Regla: una función nueva se **declara** en un registro; las pantallas que la muestran no se tocan.

## 1. Un comando (paleta ⌘K, atajo configurable)

Archivo único: `Littera/CommandPalette/LitteraCommandRegistry.swift`.

```swift
.init(id: "miFuncion",                 // único
      title: "ui.mi.funcion",          // clave es/en
      group: "ui.herramientas.2",      // clave del grupo (se crea si es nueva)
      symbol: "sparkles",              // SF Symbol
      keywords: ["sinónimo", "synonym"],
      requiresEditing: false,          // true: deshabilitado en Vista previa
      showsEditor: true,               // lleva al espacio de trabajo antes
      perform: post(.miNotificacion))
```

- Añádela a la sección que corresponda (`views`, `documents`, `tools`, `appearance`, `formatting`, `editing`, `export`) o crea una sección y súmala en `all`.
- `perform` **solo avisa** (notificación o preferencia). Quien hace el trabajo escucha:
  - documentos/ventana → `Integration/LitteraCommandHost.swift`;
  - depende de la selección o el modo → `.litteraEditorCommand` con el id (lo atiende `LitteraEditorView.runCommand`).
- **Atajo configurable:** una línea en `LitteraShortcuts.definitions` con el mismo `id`; aparece en Preferencias → Atajos y la paleta muestra el atajo guardado. Si además debe estar en la barra de menús, un `Button` en `LitteraApp.swift` con `.keyboardShortcut(shortcuts.keyboardShortcut(for: "miFuncion"))`.
- Las pruebas `LitteraPaletteTests.testRegistryIDsAreUniqueAndLocalized` fallan si falta la traducción o el id se repite.

## 2. Una página de Preferencias

Archivo único: `Littera/Settings/LitteraSettingsView.swift` → `LitteraPreferencesRegistry.pages`.

```swift
.init(id: "miPagina", titleKey: "ui.mi.pagina", symbol: "puzzlepiece",
      content: { AnyView(MiPaginaSettingsView()) })
```

D80 limita Preferencias a tres páginas (General, Editor, Atajos): antes de añadir una cuarta, pregunta al propietario; casi siempre es mejor una sección nueva en una página existente. Cada página es un `Form` con `.formStyle(.grouped)` y controles nativos; los textos salen de `L10n.tr(clave, locale:)`. Cada control se enlaza con `@AppStorage(LitteraPreferenceKeys.x)` a una preferencia real (D66: nada simulado).

## 3. Algo que se busca en la paleta (no un comando)

La paleta recibe entradas `LitteraUIPaletteEntry` de dos tipos: documentos (abiertos y recientes, de `LitteraCommandHostPalette.documentEntries`) y comandos. Tiene dos alcances, sin pestañas: ⌘K (documentos y comandos) y ⇧⌘O (documentos). Un tipo de resultado nuevo = un `Kind` nuevo en `LitteraUIPaletteEntry` + su fila en `LitteraUICommandPaletteView` + la sección en `LitteraUIPaletteSearch.sections`, y requiere aprobación del propietario (D80).

## 4. Fronteras que no se cruzan

- `Littera/UI/` no importa el backend (`probar.sh` lo comprueba). Lo que necesite el store va en `Littera/Integration/` como adaptador.
- Textos: siempre claves en `es.lproj` y `en.lproj` (paridad comprobada por `probar.sh`).
- Colores y medidas: `\.litteraUITheme` y `LitteraUITokens`, nunca valores sueltos.
- Cada cambio se verifica en la app real antes de darlo por hecho.
