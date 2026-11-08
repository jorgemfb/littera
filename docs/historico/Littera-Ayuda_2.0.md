# Littera — Ayuda

**Littera** es un editor de Markdown nativo para macOS. Está diseñado para escribir sin distracciones: una ventana, un documento, sin barras laterales ni paneles extra.

---

## Primeros pasos

### Abrir un documento

- **Archivo → Abrir…** (`⌘O`) abre un archivo `.md` existente.
- **Archivo → Nuevo** (`⌘N`) crea un documento nuevo con las propiedades del documento ya preparadas.
- Al arrancar sin documentos abiertos, Littera crea uno vacío automáticamente (configurable en Ajustes → General).

### Guardar

- **Archivo → Guardar** (`⌘S`) guarda en el archivo actual.
- **Archivo → Guardar como…** (`⇧⌘S`) guarda una copia con otro nombre o ubicación.
- Littera detecta si el archivo ha cambiado en el disco mientras trabajas y te avisa.

### Documentos recientes

**Archivo → Abrir reciente** muestra los últimos documentos. También puedes usar la paleta de documentos (`⇧⌘O`).

---

## Modos de edición

Littera tiene cuatro modos, cambiables con `⌘K` o desde el menú **Vista**:

| Modo | Descripción |
|---|---|
| **Fuente** | Edición de Markdown en texto plano. |
| **Visual** | Edición con aspecto renderizado; los marcadores Markdown permanecen visibles y atenuados. |
| **Dividido** | Fuente a la izquierda, vista previa a la derecha, sincronizados. |
| **Vista previa** | Solo lectura, representación final del documento. |

Cambiar de modo no crea copias ni modifica el contenido del archivo.

---

## Búsqueda y reemplazo

- **`⌘F`** — Abre el buscador.
- **`⌘G` / `⇧⌘G`** — Resultado siguiente / anterior.
- **`⌥⌘F`** — Abre el buscador con el campo de reemplazo.
  - **Reemplazar** sustituye la coincidencia actual.
  - **Reemplazar todo** sustituye todas las coincidencias del documento.
- La búsqueda no distingue mayúsculas ni acentos.

---

## Formato

Puedes aplicar formato con atajos de teclado mientras escribes:

| Acción | Atajo |
|---|---|
| Negrita | `⌘B` |
| Cursiva | `⌘I` |
| Código en línea | `⇧⌘K` |
| Encabezado | `⌘1` – `⌘6` |
| Enlace | `⌘K` (en Paleta de comandos) |
| Lista con viñetas | `⌥⌘L` |
| Lista numerada | `⌥⌘⇧L` |
| Cita | `⌥⌘Q` |
| Bloque de código | `⌥⌘C` |
| Tachado | `⌥⌘⇧S` |
| Línea horizontal | `⌥⌘R` |

Los atajos de formato se pueden personalizar en **Ajustes → Atajos**.

---

## Propiedades del documento

El botón **Propiedades** de la barra superior (también en el menú `···` y en la paleta de comandos) edita el frontmatter YAML sin escribir YAML:

- **Título** (`title`): se guarda con `Intro` o al salir del campo.
- **Estado** (`status`): Borrador (`draft`), En desarrollo (`in-progress`), En revisión (`review`) o Terminado (`done`).
- **Etiquetas** (`tags`): una o varias separadas por comas y `Intro`; la **×** quita una.
- **Fecha de creación** (`created`), `AAAA-MM-DD`.
- **Generar índice automáticamente** (`toc`): índice con los encabezados H1–H3 al principio de la Vista previa (cada entrada lleva a su sección), el PDF y el HTML (enlaces).
- Las demás claves aparecen debajo y todas se editan: valores simples como texto (conservan las comillas), listas como etiquetas y objetos o textos de varias líneas como YAML (se guarda al salir del campo).
- Las claves habituales se muestran en español (`author` → Autor, `keywords` → Palabras clave…) y siguen en inglés en el documento; al pasar el puntero se ve la clave real.
- Con muchas propiedades el panel se desplaza; la cabecera y la opción de índice quedan fijas.

Los documentos nuevos empiezan con estas propiedades (Borrador y la fecha de hoy). Cada cambio se deshace con `⌘Z`; el YAML sigue visible en Fuente y Visual.

---

## Edición asistida

- **Listas**: `Intro` en un elemento de lista (viñetas, numerada, tarea o cita) crea el siguiente; los números avanzan solos. `Intro` en un elemento vacío termina la lista. Ajustes → Editor → Continuar listas.
- **Cierre de símbolos**: `(`, `[`, `{`, `"`, `` ` ``, `*` y `_` se cierran solos; con selección, la rodean. Escribir el cierre lo sobrescribe y `⌫` borra la pareja vacía. Ajustes → Editor → Cerrar símbolos.
- **Pegar enlace**: con texto seleccionado, pegar una URL (`http`, `https`, `mailto`) crea `[texto](url)`.
- **Convertir texto**: menú contextual → Convertir texto → Mayúsculas, Minúsculas o Capitalizar.
- **Paleta de comandos → Edición**: limpiar espacios finales (respeta los saltos de línea con dos espacios y los bloques de código), ordenar líneas ascendente o descendente.
- **Insertar fecha**: formato en Ajustes → Editor → Formato de fecha (ISO, ISO con hora, corta, larga).

| Acción | Atajo |
|---|---|
| Mover líneas arriba / abajo | `⌥⌘↑` / `⌥⌘↓` |
| Duplicar línea | `⌘D` |
| Alternar tarea `- [ ]` / `- [x]` | `⌘↩` |
| Insertar fecha actual | `⇧⌘D` |

Personalizables en **Ajustes → Atajos → Edición**.

---

## Diagramas Mermaid

Un bloque de código con el lenguaje `mermaid` se dibuja como diagrama de flujo en la Vista previa, en el panel derecho de Dividido y en las exportaciones PDF y HTML. En Fuente y Visual se edita como código resaltado.

- Dirección: `TD`/`TB`, `BT`, `LR`, `RL` tras `flowchart` o `graph`.
- Formas: `[rectángulo]`, `(redondeado)`, `([estadio])`, `((círculo))`, `{rombo}`, `{{hexágono}}`, `[[subrutina]]`, `[(cilindro)]`.
- Conexiones: `-->`, `---`, `-.->`, `==>`, `<-->`, con etiqueta `-->|texto|` o `-- texto -->`; varias a la vez con `&`.
- `classDef`, `class`, `style` y `linkStyle` se ignoran; los `subgraph` se muestran sin recuadro.
- Otros tipos de Mermaid o líneas no reconocidas se muestran como código, con un aviso.

## Paleta de comandos

Pulsa **`⌘K`** para abrir la paleta de comandos. Desde aquí puedes:

- Cambiar de modo (Fuente, Visual, Dividido, Vista previa).
- Insertar elementos Markdown.
- Exportar el documento.
- Activar o desactivar herramientas como el modo máquina de escribir.

Navega con las flechas del teclado y confirma con **Intro**. **Escape** cierra la paleta.

---

## Paleta de documentos

Pulsa **`⇧⌘O`** o haz clic en el título del documento en la barra superior para ver todos los documentos abiertos en la sesión. Puedes buscar por nombre o ruta y cambiar entre ellos con el teclado.

---

## Modo máquina de escribir

Actívalo desde el menú `···` en la barra superior o desde la paleta de comandos. En este modo:

- La línea que estás editando se mantiene centrada verticalmente.
- El resto del texto aparece atenuado para reducir las distracciones.

En modo **Dividido**, el centrado se aplica solo al panel de Fuente.

---

## Frontmatter YAML

Littera reconoce un bloque YAML al inicio del documento delimitado por `---`:

```yaml
---
título: Mi artículo
fecha: 2026-10-23
etiquetas: [escritura, notas]
---
```

El frontmatter aparece destacado en los modos Fuente, Visual y Dividido. En Vista previa queda oculto.

---

## Exportar

Accede a la exportación desde el menú `···` o desde **Archivo → Exportar**:

- **HTML** — Genera un archivo `.html` con el contenido renderizado del documento.
- **PDF** — Genera un PDF con el mismo aspecto que la Vista previa, incluidas las imágenes locales.

---

## Imágenes

Littera carga imágenes locales referenciadas en el documento con rutas relativas o absolutas. Las imágenes se incluyen en la exportación a PDF.

```markdown
![Descripción](./imagen.png)
![Descripción](/ruta/absoluta/imagen.jpg)
```

---

## Estadísticas

Haz clic en el área de estado en la barra inferior (palabras, modo) para ver el recuento detallado: palabras, caracteres, párrafos, tiempo de lectura estimado y más.

---

## Ajustes

Abre los ajustes con **`⌘,`** o desde el menú **Littera → Ajustes**. Los cambios se aplican al instante.

| Categoría | Contenido |
|---|---|
| **General** | Idioma de la interfaz, vista inicial, restaurar los documentos abiertos y qué mostrar al arrancar sin documentos. |
| **Editor** | Tamaño de letra en Fuente, anchura del texto (para los tres modos), interlineado, modo máquina de escribir y corrección ortográfica. |
| **Apariencia** | Tema Sistema, Claro u Oscuro. |
| **Markdown** | Qué admite el motor: CommonMark, GFM, bloques de código, frontmatter YAML y diagramas Mermaid. |
| **Documentos** | Guardado automático y carpeta predeterminada. |
| **Sincronización** | Guardar los documentos en este Mac o en una carpeta de iCloud Drive. |
| **Atajos** | Personalizar los atajos de documentos, búsqueda, vistas y formato. |

**Guardado automático** (Ajustes → Documentos): guarda los documentos que ya tienen archivo al dejar de escribir un par de segundos, al cambiar de app y al cerrarlos. Los nuevos se guardan la primera vez con `⌘S`. Nunca sobrescribe cambios hechos fuera de Littera. Desactivado por omisión.

**Carpeta predeterminada** (Ajustes → Documentos → Elegir…): dónde se proponen los documentos nuevos al guardarlos y dónde empiezan Abrir y Exportar.

**iCloud Drive** (Ajustes → Sincronización → iCloud Drive → Elegir…): elige o crea una carpeta de iCloud Drive; es la misma carpeta predeterminada y macOS la sincroniza con tus dispositivos. Cambiar de ubicación no mueve documentos. Los archivos que no estén en este Mac se descargan al abrirlos (sin conexión, Littera avisa); los cambios de otro dispositivo se cargan solos si no estás editando ese documento; si dos dispositivos guardan a la vez, Littera pregunta: Conservar ambas, Conservar la de este Mac o Usar la otra.

---

## Ortografía

Activa o desactiva la corrección ortográfica desde el menú `···` en la barra superior. El corrector usa el sistema de macOS y el idioma del documento.

---

## Interlineado

Elige entre tres niveles desde **Ajustes → Editor → Interlineado**:

- **Compacto** — Líneas más juntas.
- **Normal** — Espaciado estándar.
- **Amplio** — Más espacio entre líneas.

---

## Cambios externos

Si otro programa (o tú mismo desde el Finder) modifica el archivo mientras Littera está abierto, aparecerá una alerta con las opciones de **mantener tu versión** o **recargar del disco**.

---

## Restaurar sesión

Si la opción está activa en **Ajustes → Documentos**, Littera reabre al arrancar los documentos que tenías abiertos en la sesión anterior.

---

## Instalación y privacidad

Littera es una app nativa para macOS. No requiere conexión a Internet para funcionar. No envía datos a servidores externos. Los documentos se guardan donde tú decidas: en tu Mac o en iCloud Drive (opcional).

### Primera apertura (macOS Gatekeeper)

Si macOS muestra la alerta «No se ha abierto Littera» al abrirla por primera vez:

1. Ve a **Configuración del sistema → Privacidad y seguridad**.
2. Baja hasta la sección **Seguridad**.
3. Verás el mensaje «"Littera" fue bloqueada porque no es de un desarrollador identificado». Pulsa **Abrir igualmente**.
4. En la siguiente alerta, confirma pulsando **Abrir**.

Esto ocurre porque Littera no está notarizada por Apple. La app es segura; simplemente aún no tiene firma de distribución pública.

---

## Atajos de teclado completos

| Acción | Atajo |
|---|---|
| Nuevo documento | `⌘N` |
| Abrir… | `⌘O` |
| Paleta de documentos | `⇧⌘O` |
| Guardar | `⌘S` |
| Guardar como… | `⇧⌘S` |
| Cerrar documento | `⌘W` |
| Paleta de comandos | `⌘K` |
| Buscar | `⌘F` |
| Buscar y reemplazar | `⌥⌘F` |
| Siguiente resultado | `⌘G` |
| Resultado anterior | `⇧⌘G` |
| Negrita | `⌘B` |
| Cursiva | `⌘I` |
| Código en línea | `⇧⌘K` |
| Mover líneas arriba / abajo | `⌥⌘↑` / `⌥⌘↓` |
| Duplicar línea | `⌘D` |
| Alternar tarea | `⌘↩` |
| Insertar fecha actual | `⇧⌘D` |
| Ajustes | `⌘,` |
| Exportar como HTML | — |
| Exportar como PDF | — |

---

*Littera — Editor de Markdown para macOS*
