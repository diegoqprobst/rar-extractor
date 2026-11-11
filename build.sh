#!/usr/bin/env bash
# Compila RarExtractor y arma el bundle .app en build/RarExtractor.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/RarExtractor.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/RarExtractor"
[ -f "$BIN" ] || { echo "no se encontró el binario en $BIN"; exit 1; }

echo "==> armando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RarExtractor"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Firma ad-hoc: suficiente para ejecutarla en este Mac.
codesign --force --sign - --identifier com.diego.rarextractor "$APP"

# Registra la app en Launch Services para que aparezca en "Abrir con…".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "==> listo: $APP"
