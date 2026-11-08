# Añadir un idioma a Littera

La localización **no debe introducir textos en las vistas SwiftUI ni modificar el sistema visual**.

## Ejemplo: francés

1. Registra **French (fr)** en **Xcode → PROJECT → Info → Localizations** y agrega la localización del recurso `Localizable.strings`. Si el proyecto utiliza *folder-synchronized groups* configurados para recursos localizables, confirma que el nuevo archivo entra en el target.
2. Crea `Littera/Localization/fr.lproj/Localizable.strings`, copiando las claves de `es.lproj/Localizable.strings`.
3. Traduce exclusivamente los valores entre comillas, sin alterar las claves. Conserva marcadores de formato como `%d` y `%@`.
4. Compila. El idioma `fr` aparecerá automáticamente en el selector dentro de Preferencias → General. **No hace falta añadir un `case` ni editar un `Picker`**.
5. Comprueba el francés con el selector, ambas paletas, los menús, el modo claro y el oscuro. Reinicia para verificar los menús nativos del sistema.

Ejemplo de contenido:

```text
"ui.paleta.de.comandos" = "Palette de commandes";
"ui.d.palabras" = "%d mots";
```

`LitteraLanguage.availableCodes` consulta las localizaciones del bundle; no contiene un listado permanente de idiomas. El idioma por defecto es `es`. Si falta una cadena en la traducción elegida, `L10n` intenta usar la versión española. Por ello se debe ejecutar una auditoría de paridad antes de distribuir una traducción.

Los documentos `.md`, sus rutas, los nombres de fichero y el texto escrito **no se traducen** al cambiar el idioma de la interfaz. Tampoco deben traducirse los identificadores persistentes de los modos: `Fuente`, `Visual`, `Dividido`, `Vista previa`, `Estrecho`, `Medio`, `Ancho`. Son valores técnicos internos anteriores a la localización, convertidos mediante `titleKey` para su presentación.

## Notas sobre los menús de macOS

Los textos estándar del sistema no son todos propiedad de Littera. La aplicación puede localizar títulos de primer nivel con AppKit y sus comandos propios por recursos, pero las entradas administradas por macOS pueden depender de la configuración de localizaciones del target y del idioma cargado al comenzar el proceso. Tras seleccionar otro idioma puede requerirse **salir de Littera y abrirla de nuevo**. No sustituyas los menús nativos por una simulación web ni alteres sus acciones para traducirlos.

## Validación

Desde el directorio que contiene `Littera/`:

```bash
python3 scripts/check_localizations.py
plutil -lint Littera/Localization/es.lproj/Localizable.strings
plutil -lint Littera/Localization/en.lproj/Localizable.strings
```

`plutil` es una utilidad incluida con macOS. El script usa exclusivamente Python estándar y se incluye como ayuda de desarrollo, no como dependencia de la aplicación.
