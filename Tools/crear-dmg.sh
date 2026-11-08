#!/bin/bash
# ──────────────────────────────────────────────────────────────
# crear-dmg.sh — Instalador DMG de Littera
#
# Uso:  Tools/crear-dmg.sh
#
# 1. Compila Littera en Release fuera de ~/Documents (iCloud añade atributos
#    extendidos que hacen fallar a codesign).
# 2. Conserva la firma de Xcode (con los entitlements del sandbox). Si hay un
#    certificado «Developer ID Application», vuelve a firmar con él.
# 3. Crea dist/Littera-<versión>.dmg con fondo propio (Retina), iconos de
#    128 pt y acceso directo a Aplicaciones.
#
# Requisitos: Xcode. La primera vez macOS pedirá permiso para que Terminal
# controle Finder (necesario para colocar los iconos).
# ──────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="Littera"
VOLUME_NAME="Littera"
ICON_SIZE=128
TEXT_SIZE=13
WINDOW_W=704
WINDOW_H=384           # tamaño del fondo en puntos (imagen 1408×768 a 2x)
TITLEBAR_H=28
APP_X=122; APP_Y=205
APPS_X=582; APPS_Y=205

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${TOOLS_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
LOG_DIR="${PROJECT_DIR}/build"
BG_1X="${TOOLS_DIR}/dmg/fondo.png"
BG_2X="${TOOLS_DIR}/dmg/fondo@2x.png"
WORK_DIR="${TMPDIR:-/tmp}/littera-dmg"
DERIVED_DATA="${TMPDIR:-/tmp}/Littera-DerivedData-Release"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}▸${NC} $1"; }
warn() { echo -e "${YELLOW}▸${NC} $1"; }
fail() { echo -e "${RED}✘${NC} $1" >&2; exit 1; }

for tool in xcodebuild hdiutil osascript tiffutil codesign; do
    command -v "$tool" >/dev/null || fail "Falta ${tool} (¿Xcode instalado?)"
done
[ -f "${BG_1X}" ] && [ -f "${BG_2X}" ] || fail "Faltan las imágenes de fondo en Tools/dmg/"

# ── 1. Compilar ───────────────────────────────────────────────
info "Compilando ${APP_NAME} en Release…"
mkdir -p "${LOG_DIR}"
if ! xcodebuild -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" -configuration Release \
        -derivedDataPath "${DERIVED_DATA}" \
        clean build > "${LOG_DIR}/release.log" 2>&1; then
    grep -E "error:|Command .* failed|\*\* BUILD FAILED" "${LOG_DIR}/release.log" | head -20 >&2
    fail "La compilación falló. Registro completo en build/release.log"
fi

APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || fail "No se encontró ${APP_PATH}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist")
info "Versión ${VERSION} (${BUILD})"

# ── 2. Firma ──────────────────────────────────────────────────
DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1 || true)
if [ -n "${DEVELOPER_ID}" ]; then
    info "Firmando con ${DEVELOPER_ID}"
    # Los permisos que Xcode generó (sandbox, archivos elegidos, marcadores):
    # el archivo .entitlements solo contiene parte de ellos.
    ENTITLEMENTS="${WORK_DIR}/entitlements.plist"
    mkdir -p "${WORK_DIR}"
    codesign -d --entitlements - --xml "${APP_PATH}" > "${ENTITLEMENTS}" 2>/dev/null
    # El permiso de depuración impide notarizar: nunca en una firma Developer ID.
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "${ENTITLEMENTS}" >/dev/null 2>&1 || true
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${DEVELOPER_ID}" "${APP_PATH}"
else
    warn "Sin certificado Developer ID: se conserva la firma local de Xcode."
    warn "En otros Mac habrá que abrirla con clic derecho → Abrir la primera vez."
fi
codesign --verify --strict "${APP_PATH}" || fail "La firma de la app no es válida"
if codesign -d --entitlements - --xml "${APP_PATH}" 2>/dev/null | grep -q "get-task-allow"; then
    fail "La app lleva el permiso de depuración get-task-allow (no se podría notarizar)"
fi

# ── 3. Contenido del DMG ──────────────────────────────────────
info "Preparando el contenido…"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/staging/.background"
ditto "${APP_PATH}" "${WORK_DIR}/staging/${APP_NAME}.app"
ln -s /Applications "${WORK_DIR}/staging/Applications"
# Fondo Retina: un TIFF con las dos resoluciones.
tiffutil -cathidpicheck "${BG_1X}" "${BG_2X}" -out "${WORK_DIR}/staging/.background/fondo.tiff" >/dev/null
# Icono del volumen = icono de la app.
ICNS=$(/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "AppIcon")
[ -f "${APP_PATH}/Contents/Resources/${ICNS%.icns}.icns" ] && \
    cp "${APP_PATH}/Contents/Resources/${ICNS%.icns}.icns" "${WORK_DIR}/staging/.VolumeIcon.icns"

# Un volumen anterior con el mismo nombre confundiría a Finder.
if [ -d "/Volumes/${VOLUME_NAME}" ]; then
    warn "Expulsando /Volumes/${VOLUME_NAME}…"
    hdiutil detach "/Volumes/${VOLUME_NAME}" -force -quiet || true
fi

TEMP_DMG="${WORK_DIR}/temporal.dmg"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${WORK_DIR}/staging" \
    -fs HFS+ -format UDRW -ov "${TEMP_DMG}" -quiet

# ── 4. Aspecto de la ventana ──────────────────────────────────
info "Colocando fondo e iconos…"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
[ -d "${MOUNT_POINT}" ] || fail "No se pudo montar el DMG temporal"
if command -v SetFile >/dev/null || xcrun --find SetFile >/dev/null 2>&1; then
    xcrun SetFile -a C "${MOUNT_POINT}" 2>/dev/null || true
fi

osascript <<APPLESCRIPT
tell application "Finder"
    -- Finder puede tardar en reconocer el disco recién montado.
    repeat 30 times
        if exists disk "${VOLUME_NAME}" then exit repeat
        delay 0.5
    end repeat
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {160, 120, $((160 + WINDOW_W)), $((120 + WINDOW_H + TITLEBAR_H))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to ${ICON_SIZE}
        set text size of viewOptions to ${TEXT_SIZE}
        set background picture of viewOptions to file ".background:fondo.tiff"
        set position of item "${APP_NAME}.app" of container window to {${APP_X}, ${APP_Y}}
        set position of item "Applications" of container window to {${APPS_X}, ${APPS_Y}}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

rm -rf "${MOUNT_POINT}/.fseventsd" 2>/dev/null || true
sync
hdiutil detach "${DEVICE}" -quiet || hdiutil detach "${DEVICE}" -force -quiet

# ── 5. Comprimir ──────────────────────────────────────────────
mkdir -p "${DIST_DIR}"
# Etiqueta opcional de la versión candidata: ETIQUETA=RC1 Tools/crear-dmg.sh
# crea Littera-1.0.0-RC1.dmg. La versión de la app (solo números) no cambia.
FINAL_DMG="${DIST_DIR}/${APP_NAME}-${VERSION}${ETIQUETA:+-${ETIQUETA}}.dmg"
info "Comprimiendo ${FINAL_DMG##*/}…"
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -ov -o "${FINAL_DMG}" -quiet
hdiutil verify "${FINAL_DMG}" -quiet || fail "hdiutil verify falló"
rm -rf "${WORK_DIR}"

# La copia compilada en la carpeta temporal no debe competir con la instalada
# en /Applications (Apps, «Abrir con», Spotlight).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "${LSREGISTER}" ] && "${LSREGISTER}" -u "${APP_PATH}" >/dev/null 2>&1 || true

SIZE=$(du -h "${FINAL_DMG}" | awk '{print $1}')
SHA=$(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')
info "✅ ${FINAL_DMG#${PROJECT_DIR}/} (${SIZE})"
echo "   SHA-256: ${SHA}"
echo "   Probar:  open \"${FINAL_DMG}\""
