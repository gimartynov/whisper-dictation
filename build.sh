#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "→ Сборка…"
mkdir -p .build/tmp .build/modulecache .build/spm-cache
export TMPDIR="$PWD/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modulecache"
swift build -c release --arch arm64 --arch x86_64 --disable-sandbox --cache-path "$PWD/.build/spm-cache" --scratch-path "$PWD/.build"

APP="build/WhisperDictation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=".build/out/Products/Release/WhisperDictation"
[ -f "$BIN" ] || BIN=".build/release/WhisperDictation"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/licenses "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp PRIVACY.md "$APP/Contents/Resources/PRIVACY.md"
cp THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/"
chmod 0644 "$APP/Contents/Resources/LICENSE.txt" "$APP/Contents/Resources/PRIVACY.md" "$APP/Contents/Resources/THIRD-PARTY-NOTICES.txt"

echo "→ Упаковка whisper-server…"
WHISPER_DIR="$APP/Contents/Resources/whisper"
mkdir -p "$WHISPER_DIR"

# Сервер должен быть собран статически (см. scripts/build-whisper.sh):
# без Homebrew, без dylib, без внешних ggml-бэкендов.
SRC="$PWD/.vendor/whisper.cpp-1.9.5/build-static/bin/whisper-server"
if [ ! -x "$SRC" ]; then
    echo "✗ Не найден статический whisper-server: $SRC"
    echo "  Запустите scripts/build-whisper.sh (нужен cmake)."
    exit 1
fi
cp "$SRC" "$WHISPER_DIR/whisper-server"
chmod u+w "$WHISPER_DIR/whisper-server"

if otool -L "$WHISPER_DIR/whisper-server" | grep -q "/opt/homebrew"; then
    echo "✗ whisper-server ссылается на /opt/homebrew:"
    otool -L "$WHISPER_DIR/whisper-server" | grep "/opt/homebrew"
    exit 1
fi

# Подпись: Developer ID (если есть сертификат) или ad-hoc.
# Developer ID можно задать явно: CODESIGN_IDENTITY="Developer ID Application: ..."
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi

if [ -n "$IDENTITY" ]; then
    echo "→ Подпись Developer ID: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
        "$WHISPER_DIR/whisper-server" >/dev/null
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
        --identifier com.grigorii.whisperdictation "$APP"
else
    echo "→ Подпись ad-hoc (Developer ID не найден)"
    codesign --force --sign - "$WHISPER_DIR/whisper-server" >/dev/null 2>&1
    codesign --force --deep --sign - --identifier com.grigorii.whisperdictation \
        --requirements '=designated => identifier "com.grigorii.whisperdictation"' "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "✓ Готово: $(pwd)/$APP"
