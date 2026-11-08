# Contrato de interfaz · Littera 2.0

**Vigente desde:** 2026-10-27 (sustituye a `docs/historico/UI_CONTRACT_1.0.md`). Las decisiones de detalle están en `DECISIONS.md` (D56–D75).

## Disposición que no cambia como efecto lateral de una función

```text
Biblioteca (vista inicial)
[● ● ●] ‹ › Littera › Biblioteca      [ buscar ] [▦ ≡] [···] [inspector]
┌ barra lateral ┬──────────── documentos (cuadrícula/lista) ─────┬ inspector ┐
└───────────────┴─────────────────────────────────────────────────┴───────────┘

Espacio de trabajo
[● ● ●] Littera › carpeta › archivo  [Fuente|Visual|Dividido|Vista previa]  [buscar] [···] [⇪] [Zen] [inspector]
┌ barra lateral ┬──────────── editor ──────────────────────────────┬ inspector ┐
└ estado: palabras · caracteres · tiempo · línea/columna · codificación ┘
```

## Reglas
1. Colores, tipografía y medidas salen de `\.litteraUITheme` y `LitteraUITokens`.
2. La UI (`Littera/UI/`) no importa el backend; los datos llegan por adaptadores.
3. Nada simulado en la app real (D66): un control sin función se oculta o se deshabilita.
4. Un mínimo de ventana único (D67); el contenido encoge sin recortar los paneles.
5. Funciones nuevas: se **registran** (comandos, páginas de Preferencias) en vez de añadir botones sueltos (`EXTENDER_LITTERA.md`).
6. Cambios visuales: con captura y aprobación del propietario; referencias en `docs/referencias-visuales/`.
