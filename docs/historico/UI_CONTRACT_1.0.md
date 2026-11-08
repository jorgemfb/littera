# Contrato de interfaz UI 1.0

## Disposición que no debe cambiar por implementar funciones

```text
macOS [● ● ●]             [  Documento.md  ]              [ 🔍  ··· ]
┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│                   DOCUMENTO MARKDOWN CENTRADO                    │
│                                                                    │
│                  (sin paneles persistentes)                       │
│                                                                    │
│                [ estado · palabras · modo ]                       │
└────────────────────────────────────────────────────────────────────┘
```

- La barra superior es nativa y de **una sola fila**. Sin selector de cuatro modos, sin pestañas, sin segunda barra.
- El título abre documentos abiertos; búsqueda y menú `ellipsis` nativo a la derecha, `menuIndicator(.hidden)`.
- `⌘K` abre la paleta de comandos y `⇧⌘O` la paleta de documentos. Mismo estilo/foco/navegación; no abrir varias a la vez. No hay paleta de formato adicional.
- Barra de estado inferior discreta, documento con máxima área libre y anchura configurable.
- Foco de teclado: ↑ ↓ mueve, Enter ejecuta, Escape cierra; debe funcionar desde clic, menú y atajo, y devolver el foco correctamente al editor.
- Ajustes (7 secciones): General, Editor, Apariencia, Markdown, Documentos, Sincronización y Atajos.

## Tokens, componentes y recursos
- `Littera/DesignSystem/LitteraDesignSystem.swift`: colores, dimensiones y tipografía compartidos. No duplicar valores `Color(red:...)` por vistas.
- `Littera/Editor/LitteraTitlebarView.swift`: título y acciones en barra superior.
- `Littera/Editor/LitteraStatusBarView.swift`: estado inferior.
- `Littera/CommandPalette/LitteraPaletteFrame.swift`: estructura común de paletas.
- `Littera/CommandPalette/LitteraCommandRegistry.swift`: registro de acciones; estado de habilitación fiel a su funcionamiento real.
- `Littera/Documents/LitteraOpenDocumentsPaletteView.swift`: solo selección visual; no persistencia de disco.
- `Littera/Localization/*`: texto visible, independiente de SwiftUI y del diseño.

## Markdown representado
- Tipografía y jerarquía editorial como en las referencias; citas con línea de acento, fondo discreto, interlineado relajado y texto real.
- Ejemplo del prototipo: `> La verdadera productividad...` se dibuja como cita; las comillas tipográficas y la atribución que se ven en la demo **no están en el Markdown de origen** y NO pueden añadirse al contenido real sin indicación del usuario.
- Los contenidos Fuente y Vista previa deben proceder del mismo archivo y reflejarse después de editar.

## Accesibilidad y adaptación
- Verificar ambos temas, tipografía del sistema, accesibilidad por teclado, VoiceOver y tamaños de ventana admitidos.
- Es posible mostrar ayuda contextual/hover para descubrir que el título es pulsable. No añadir flechas o botones persistentes por iniciativa propia.
- No quitar controles de macOS para dibujar imitaciones visuales.

## Regresión visual
Antes de fusionar un cambio: capturas lado a lado del proyecto real frente a `referencias-visuales`. Si cambia la estética sin pedido expreso, es regresión, aunque compile correctamente.

---

## Geometría, apariencia y persistencia de ventanas

### 1. Principio general

Littera debe comportarse como una aplicación nativa de macOS, respetando las convenciones del sistema operativo y conservando el estado de sus ventanas.

La apariencia, la geometría y la navegación son responsabilidades independientes.

**Ninguna modificación de apariencia debe alterar el tamaño, la posición, el contenido o el estado de navegación de una ventana.**

Estas decisiones forman parte del contrato de diseño y experiencia de usuario de Littera.

### 2. Ventana principal: tamaño y posición

La ventana principal debe:

- Recordar su último tamaño entre ejecuciones.
- Recordar su última posición en pantalla.
- Restaurar automáticamente ambos valores al volver a iniciar Littera.
- Permitir al usuario redimensionarla y moverla libremente.
- Respetar unas dimensiones mínimas de **960 × 620 puntos**.
- Utilizar el comportamiento nativo de restauración de ventanas de macOS.
- Adaptarse a cambios de pantalla o resolución conforme al comportamiento nativo del sistema.

El tamaño y la posición iniciales solo se utilizarán cuando no exista una geometría previamente restaurable.

No deben imponerse tamaños o posiciones fijos durante cada inicio.

### 3. Implementación nativa aprobada

La ventana principal utiliza un `WindowGroup` de SwiftUI con identificador estable:

```swift
WindowGroup(id: "littera.main") {
    LitteraEditorView()
        .frame(minWidth: 960, minHeight: 620)
}
```

Este fragmento representa el contrato de identidad y geometría, no la declaración completa de la escena.

**Reglas técnicas:**

- Conservar el identificador estable `littera.main`.
- Permitir que SwiftUI y macOS gestionen la restauración nativa.
- No introducir sistemas paralelos de persistencia de geometría.
- No almacenar manualmente coordenadas o dimensiones en `UserDefaults`.
- No introducir puentes AppKit para gestionar geometría mientras el mecanismo actual funcione.
- No modificar la identidad de la ventana sin evaluar su efecto sobre la restauración.

El mecanismo ha sido validado manualmente y recupera correctamente el tamaño y la posición entre ejecuciones.

### 4. Cambios de apariencia

Littera ofrece tres opciones:

| Opción | Comportamiento |
|---|---|
| Sistema | Hereda la apariencia de macOS |
| Claro | Fuerza la apariencia clara |
| Oscuro | Fuerza la apariencia oscura |

**Sistema es la opción predeterminada para una instalación sin preferencias previas.**

Las elecciones posteriores del usuario deben persistir entre ejecuciones.

Al cambiar de apariencia:

- Todas las ventanas deben actualizarse inmediatamente.
- La ventana principal debe conservar exactamente su tamaño y posición.
- La ventana de Configuración debe conservar su tamaño y posición.
- No deben cerrarse ni recrearse ventanas.
- No debe modificarse el documento activo.
- No debe perderse la posición de desplazamiento del editor.
- No debe alterarse la selección actual.
- No debe reiniciarse la navegación de Configuración.
- No deben introducirse cambios de foco artificiales.

La apariencia debe estar gestionada por un único controlador compartido.

La definición de los colores del tema debe permanecer separada del sistema de diseño.

### 5. Ventana de Configuración

La ventana de Configuración es independiente de la ventana principal.

Debe:

- Utilizar controles y barra de título nativos de macOS.
- Adaptar automáticamente su apariencia al tema seleccionado.
- Mantener un contraste adecuado para títulos y controles.
- Conservar la sección seleccionada durante los cambios de tema.
- Mantener su geometría mientras permanece abierta.
- No provocar movimientos, redimensionamientos ni cambios de foco innecesarios en la ventana principal.

Si el usuario está en **Configuración → Apariencia** y cambia entre Sistema, Claro y Oscuro, debe permanecer en **Apariencia**.

La geometría de Configuración no debe compartir ningún identificador de restauración con la ventana principal.

### 6. Separación de responsabilidades

La arquitectura debe mantener claramente diferenciados:

| Responsabilidad | Componente |
|---|---|
| Apariencia global | Controlador de temas |
| Paleta de colores | Definiciones de tema |
| Tipografías, espaciados y medidas | Sistema de diseño |
| Selección de preferencias | Vista y estado de Configuración |
| Geometría de ventanas | SwiftUI y mecanismos nativos de macOS |
| Idioma y localización | Sistema de localización |

Ningún componente debe asumir responsabilidades pertenecientes a otro subsistema sin una justificación técnica y autorización expresa.

### 7. Restricciones para futuras implementaciones

Codex y cualquier agente de desarrollo deben respetar las siguientes restricciones:

1. No modificar decisiones visuales ni de experiencia de usuario sin autorización.
2. No sustituir mecanismos nativos funcionales por implementaciones personalizadas.
3. No introducir controladores duplicados de apariencia o geometría.
4. No modificar el identificador estable de la ventana principal sin autorización.
5. No introducir temporizadores, ajustes artificiales de posición ni soluciones provisionales para compensar problemas de restauración.
6. No alterar el comportamiento de ventanas al implementar nuevas funcionalidades.
7. Consultar antes de realizar cualquier modificación que afecte a este contrato.

**Codex implementa las decisiones aprobadas; no redefine unilateralmente el diseño ni el comportamiento de Littera.**

### 8. Criterios de aceptación

Una modificación relacionada con ventanas solo podrá considerarse validada cuando se compruebe que:

- La ventana principal conserva tamaño y posición tras cerrar y volver a abrir Littera.
- Los cambios entre Sistema, Claro y Oscuro son inmediatos.
- Ningún cambio de apariencia modifica la geometría.
- Configuración conserva la sección activa.
- El contenido y el desplazamiento del editor no se pierden.
- Los controles nativos siguen funcionando correctamente.
- La compilación se completa sin errores.

La compilación correcta, por sí sola, no constituye una validación del comportamiento visual.

### 9. Estado de implementación

**Estado: IMPLEMENTADO Y VALIDADO MANUALMENTE.**

- Cambio de apariencia: funcional.
- Persistencia de preferencias de apariencia: funcional.
- Conservación de navegación durante cambios de tema: funcional.
- Persistencia de tamaño y posición de la ventana principal: funcional.
- Restauración nativa mediante `WindowGroup(id: "littera.main")`: funcional.

Esta implementación constituye la referencia aprobada para futuras modificaciones de la interfaz de Littera.