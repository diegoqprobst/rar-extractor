#!/usr/bin/env bash
# Compila RarExtractor y arma el bundle .app en build/RarExtractor.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/RarExtractor.app"

# Binario universal: funciona en Apple Silicon y en Mac Intel.
ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "==> swift build -c $CONFIG (arm64 + x86_64)"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"

BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/RarExtractor"
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

# Con "zip": deja build/RarExtractor.zip listo para publicar (ditto conserva el bundle y la firma).
if [ "${2:-}" = "zip" ]; then
  rm -f build/RarExtractor.zip
  ditto -c -k --keepParent "$APP" build/RarExtractor.zip
  echo "==> zip: build/RarExtractor.zip"
fi
