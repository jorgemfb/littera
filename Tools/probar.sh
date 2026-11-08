#!/bin/bash
# Compila Littera (Debug) y pasa las pruebas XCTest. El registro completo
# queda en build/pruebas.log y el resumen en build/pruebas-resumen.log.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
echo "▸ Comprobando traducciones…"
swift Tools/CheckLocalizations.swift || exit 1
echo "▸ Comprobando la frontera UI/backend…"
# Frontera de docs/EXTENDER_LITTERA.md (§4): la capa de presentación no conoce el
# backend. Los adaptadores viven en Littera/Integration/.
prohibidos='LitteraDocumentStore|LitteraDocumentFiles|LitteraMarkdownParser|LitteraExporter|LitteraCloudFiles'
if grep -rnE "\b($prohibidos)\b" Littera/UI --include='*.swift' | grep -vE '^[^:]+:[0-9]+:\s*//'; then
    echo "✘ Littera/UI/ usa tipos del backend (ver arriba)"; exit 1
fi
echo "▸ Compilando y probando Littera…"
xcodebuild -project Littera.xcodeproj -scheme Littera \
    -destination 'platform=macOS' \
    -derivedDataPath "${TMPDIR:-/tmp}/Littera-DerivedData-Pruebas" \
    test > build/pruebas.log 2>&1
status=$?
grep -E "error:|Mermaid[^ ]*\.swift:[0-9]+:[0-9]+: warning:|Test Case .*failed|Executed [0-9]+ tests|\*\* (TEST|BUILD) (SUCCEEDED|FAILED) \*\*|Failing tests:|^\s+-\[" build/pruebas.log \
    | sed 's#^/Users/[^ ]*/Littera/##' > build/pruebas-resumen.log
cat build/pruebas-resumen.log | tail -40
if [ $status -eq 0 ]; then echo "✅ Pruebas superadas"; else echo "✘ Fallo (código $status). Detalle en build/pruebas.log"; fi
exit $status
