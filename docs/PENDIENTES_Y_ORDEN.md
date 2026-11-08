# Littera · Estado y siguiente iteración

**Fecha:** 2026-11-08 · **Rama:** `main` (fusionada desde `feature/littera-ui-redesign`) · **Respaldo previo:** `backup/pre-v1-30caf81`
**Versión:** **1.0.1** (build 15, etiqueta local `v1.0.1`, 2026-11-08): corrige los diagramas Mermaid invisibles en la Vista previa. La 1.0.0 fue la build 14 (`v1.0.0`) y la RC1 la 13.
**Estado:** 1.0.0 cerrada. Suite completa: **334 pruebas, 0 fallos, 12 omitidas** (9 de benchmark, que solo corren con `LITTERA_BENCH`, y 3 de foco de teclado que se omiten si la app de pruebas no está al frente). La hoja de ruta 2.0 está en `docs/historico/PENDIENTES_Y_ORDEN_2.0.md`.

Origen: auditoría del 2026-11-07 (hallazgos H1–H23). Cada paso es un commit con compilación, suite completa y, si toca la interfaz, capturas en claro y oscuro.

---

## Bloque A · Correcciones críticas ✅

| Paso | Commit | Resultado |
|---|---|---|
| Decisiones v1 (C1) | `f1585aa` | D76–D80, `AGENTS.md`, `UI_CONTRACT.md` y `PROJECT_CONTEXT.md` para v1 |
| H1 | `43e073b` | Guardar ya no falla tras escribir por la cuarentena del sandbox (EPERM al restaurar `com.apple.quarantine`) |
| H3 | `f3cbd7e` | Guardar a mano un archivo borrado fuera lo vuelve a crear (D37); el guardado automático, nunca |
| H4 | `50730c1` | Con un enlace simbólico se usa la fecha del archivo al que apunta |
| H2 | `9b8a3d9` | Cancelar la salida ya no descarta ediciones contestadas con «No guardar» |
| H5 | `1c1d32e` | Un archivo de solo lectura nunca se sobrescribe; Guardar propone Guardar como |
| H6 | `734d525` | Un archivo que falla al leerse en un arranque no se borra de la sesión |
| Fix A | `81d0247` | Revertido (neutro en A/B) y corregidas las cifras de `30caf81` |

Nada de esto se ha comprobado aún en la app real: solo con XCTest en el anfitrión de pruebas (sandbox).

## Bloque C · Simplificación v1 ✅
Revisado en la app por el propietario tras cada paso de interfaz.

| Paso | Commit | Resultado |
|---|---|---|
| C1 | `5018d3a` | Ventana con barra nativa (título, propiedades, lupa, `···`) y el editor como protagonista |
| C2 | `89e2094` | Visual retirado: una sola `NSTextView`, ⌘1–⌘3, Deshacer sobrevive al cambio de modo; «Vista inicial» = Visual migra a Fuente |
| C3 | `bcf75f4` | Biblioteca, barra lateral, inspector, Zen, favoritos, notas rápidas, atrás/adelante e índice de carpeta retirados (~5 370 líneas) |
| C4a | `602605b` | Paleta sin pestañas ni etiquetas; documentos abiertos y recientes |
| C4b | `ced269d` | Preferencias en tres pestañas nativas (General, Editor, Atajos); claves conservadas |
| C5 | `84fd77f` | Barra de estado oculta por omisión, activable en General |
| C6 | este commit | 265 claves de texto sin uso retiradas (343 en es/en), código sin referencias, comentarios, ayuda integrada y documentación al día |

Quedan, a propósito: dos sistemas de color (el del editor y el de la paleta), unificarlos es un cambio visual; el modo `chromeless` de `LitteraEditorView`, que ya solo usan las pruebas.

## Bloque B · Rendimiento ✅
Arnés A/B en Release con corpus sintético (ver `AGENTS.md`). Diagnóstico medido por variantes: la memoria era la propia Vista previa SwiftUI (~6 MB por KB de Markdown, ×2 con las dos ocultas), no las mediciones de posición ni `.textSelection`.

| Paso | Commit | Resultado (antes → después, xlarge 131 KB salvo indicación) |
|---|---|---|
| B1 | `5433b7e` | Constructor del texto con atributos de la Vista previa (TextKit) |
| B2 | `d4ea96c` | Vista previa con una `NSTextView`: memoria en Fuente 1 741 → 84 MB (large 730 → 73, medium 210 → 41); redimensionar 535 → 131 ms por paso; escritura p95 33 → 21 ms; bloqueo al dejar de escribir 241 → 0 ms; cambios de modo iguales o más rápidos. Revisado por el propietario |
| B3 | `6801b09` | Una publicación del store por pulsación; la app ya no observa el store (H17) |
| H8 | `c54754c` | Redimensionar en Fuente 286 → 17 ms por paso; Dividido 359 → 224 ms. Las Vistas previas ocultas ya no rehacen el diseño de todo el documento en cada cambio de anchura: lo hacen 0,5 s después del último (~200 ms una sola vez) o al mostrarse. Cambios de modo tras redimensionar, iguales |
| H8b | `89e4516` | Dividido: la Vista previa visible y la alineación con la Fuente se rehacen al asentarse la anchura (0,2 s), no en cada paso. Mismo arnés: 111 → 43 ms por paso arriba del documento y 115 → 73 a mitad; posiciones finales idénticas. Durante el arrastre la Vista previa no se realinea (se corrige al soltar). Revisado por el propietario |
| H24 | `87c1216` | Al salir de Dividido, el editor oculto que se ensancha ya no registra la posición: la posición de lectura retrocedía (~0,50 → 0,37 del documento al volver a Fuente) y costaba un layout completo (~80 ms, 0,2 s después). Dividido → Vista previa: 32 ms sin trabajo aplazado. Vista previa → Fuente sube de ~42 a ~195 ms porque ahora restaura la posición correcta (igual que Fuente → Dividido). Comprobado por el propietario |

- **H8, cómo se encontró:** Time Profiler sobre el redimensionado sostenido: el 89,6 % del hilo principal estaba en `LitteraPreviewTextHost.Coordinator.refreshLayout()` (`ensureLayout` de las dos Vistas previas ocultas). La cifra anterior de «~130 ms por paso» y la conclusión de que las Vistas previas ocultas no influían eran **erróneas**: aquel arnés no esperaba al refresco asíncrono que se ejecuta en la vuelta siguiente del bucle. El arnés nuevo vacía el bucle en cada paso (3 rondas alternas A/B en Release, xlarge 131 KB, 60 pasos de −40/+37 px).
- **Variación del arnés:** la misma base (`c54754c`) dio ~224 ms por paso en Dividido en una sesión y ~111 en otra; solo se comparan cifras de la misma ronda A/B.
- **H24, cómo se encontró:** el «~1,3 s» de Dividido → Vista previa no era un bloqueo: el cambio tardaba 36 ms y el arnés contaba hasta el último tramo ocupado (82 ms a los 0,22 s y tramos menores hasta 1,3 s). El tramo de 82 ms escondía el error de posición.
- Probado y descartado: aplazar el diseño de las Vistas previas ocultas al construirlas (ahorra ~40 MB, pero el primer cambio a Vista previa se vuelve ~40 ms más lento); desactivar el diseño en segundo plano de las ocultas (las dejaba a medio maquetar).

## Bloque D · Opcionales ✅

| Paso | Commit | Resultado |
|---|---|---|
| H10 | `89e2094` | Deshacer sobrevive al cambio de modo (resuelto al retirar Visual, C2) |
| H12 | `cdcd0f7` | Un documento movido a la Papelera desde Finder ya no se guarda allí: queda sin guardar y Guardar lo recrea en su sitio |
| H11 | `1b786b8` | Conflictos de iCloud: sin preguntas en segundo plano (D50); al resolver solo se retiran las versiones en conflicto, no todo el historial (esta parte necesita iCloud real para probarse) |
| H13 | `a31fa2c` | Los accesos de seguridad de los marcadores se cierran al cerrar el documento; los caducados ya se renovaban al abrir |
| H18 | `dec878f` | Se conserva el BOM UTF-8 al guardar |
| H19 | `82a3862` | Un cambio solo de normalización Unicode (NFC ↔ NFD) cuenta como cambio |
| H20 | `fe8fc0d` | Plurales («1 palabra») y el error de guardado en el idioma de la interfaz |
| H14 | `387b964` | Cerrar la única ventana sale de la app (D82) |
| H21 | `815fe18` | Hardened Runtime en Release; `xcuserdata` fuera del repositorio; macOS 27.0 se mantiene (D83) |
| H23 | — | Guardado atómico también con hard links (D81) |

Pendiente fuera del código: firma Developer ID y notarización (cuenta de Apple Developer); comprobar que los marcadores sobreviven a una actualización firmada.

## 1.0.1 (2026-11-08)
- Los diagramas Mermaid vuelven a verse en Vista previa y Dividido (se maquetaban con ~1 pt de alto). DMG: `dist/Littera-1.0.1.dmg`.
- Publicada en GitHub (`jorgemfb/littera`, público, licencia MIT) con historial nuevo: un commit con el código de la 1.0.1, firmado con el correo privado de GitHub, y la etiqueta `v1.0.1`. El DMG se adjunta a mano en la Release.

## Cómo publicar una versión nueva
El historial público (rama local `publico`) es independiente de `main`, que conserva el historial completo con correos y capturas personales. Para publicar, tras el commit y la etiqueta en `main`:

```bash
GIT_AUTHOR_NAME="Jorge Raúl Saavedra Cabrol" GIT_AUTHOR_EMAIL=48606989+jorgemfb@users.noreply.github.com GIT_COMMITTER_NAME="Jorge Raúl Saavedra Cabrol" GIT_COMMITTER_EMAIL=48606989+jorgemfb@users.noreply.github.com git commit-tree "main^{tree}" -p publico -m "Littera X.Y.Z" > /tmp/littera-publico && git update-ref refs/heads/publico "$(cat /tmp/littera-publico)"
git push origin publico:main publico:refs/tags/vX.Y.Z
```

Antes de publicar, revisar que el árbol no contiene datos personales (capturas, rutas, documentos) y adjuntar `dist/Littera-X.Y.Z.dmg` a la Release.

## Cierre de la 1.0.0 (2026-11-08)
- RC1 (build 13): duplicados de iCloud fuera, versión 1.0.0, licencias y copyright (D87), «Compartir» fuera del contrato (D88), documentación al día, aviso de `Info.plist` resuelto, Release sin `get-task-allow`.
- Final (build 14): tipos de documento del `Info.plist` traducidos (`InfoPlist.strings` es/en), comentario del modo `chromeless` al día. DMG: `dist/Littera-1.0.0.dmg` (`bash Tools/crear-dmg.sh`; `dist/` no se versiona).
- Se quedan a propósito: el modo `chromeless` de `LitteraEditorView` (lo usan las pruebas) y la clave `sourceWidth` (la lee la migración a la anchura única).
- **Comprobado por el propietario en la app** durante la sesión: menú `···` y anchura única, propiedades y su orden, posición de lectura entre modos, redimensionado en Dividido, icono en los cuatro estilos. **No comprobado:** el resto de puntos [manual] de `UI_CHECKLIST.md` (VoiceOver, «Aumentar contraste», inglés tras reiniciar, iCloud con dos Macs, exFAT/SMB, archivos grandes, DMG instalado y actualizado). Se arrastran a la siguiente iteración.

## Siguiente iteración (propuesta, pendiente de que el propietario la apruebe)
1. Mover el proyecto fuera de `~/Documents`: iCloud crea copias «… 2.swift» que rompen la compilación desde cero. Lo hace el propietario con Xcode cerrado.
2. Terminar las pruebas manuales pendientes de `UI_CHECKLIST.md` sobre la versión instalada (1.0.1).
3. Firma Developer ID y notarización (requiere cuenta de Apple Developer) antes de distribuir fuera de este Mac.
4. ~~Remoto~~: publicado el 2026-11-08 en `https://github.com/jorgemfb/littera` (público, MIT).
5. Objetivos de producto de la nueva versión: por definir con el propietario (iPadOS e iOS siguen pospuestos, D76).
6. Diagramas Mermaid muy anchos: al reducirse a la columna su texto queda demasiado pequeño (visto con un diagrama de 21 nodos).
