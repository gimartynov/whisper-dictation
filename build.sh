#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "→ Сборка…"
mkdir -p .build/tmp .build/modulecache .build/spm-cache
export TMPDIR="$PWD/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/modulecache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/spm-cache" --scratch-path "$PWD/.build"

APP="build/WhisperDictation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WhisperDictation "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/licenses "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp THIRD-PARTY-NOTICES.txt "$APP/Contents/Resources/"

echo "→ Упаковка whisper-server и библиотек…"
WHISPER_DIR="$APP/Contents/Resources/whisper"
mkdir -p "$WHISPER_DIR"
cp -L /opt/homebrew/bin/whisper-server "$WHISPER_DIR/whisper-server"
cp -L /opt/homebrew/lib/libwhisper.1.dylib "$WHISPER_DIR/"
cp -L /opt/homebrew/lib/libggml.0.dylib "$WHISPER_DIR/"
cp -L /opt/homebrew/lib/libggml-base.0.dylib "$WHISPER_DIR/"
cp -L /opt/homebrew/opt/libomp/lib/libomp.dylib "$WHISPER_DIR/"
cp -L /opt/homebrew/Cellar/ggml/0.29.0/libexec/libggml-blas.so "$WHISPER_DIR/"
cp -L /opt/homebrew/Cellar/ggml/0.29.0/libexec/libggml-metal.so "$WHISPER_DIR/"
cp -L /opt/homebrew/Cellar/ggml/0.29.0/libexec/libggml-cpu-apple_m1.so "$WHISPER_DIR/"
cp -L /opt/homebrew/Cellar/ggml/0.29.0/libexec/libggml-cpu-apple_m2_m3.so "$WHISPER_DIR/"
cp -L /opt/homebrew/Cellar/ggml/0.29.0/libexec/libggml-cpu-apple_m4.so "$WHISPER_DIR/"
chmod u+w "$WHISPER_DIR"/*

rewrite() { install_name_tool "$@" 2>/dev/null; }

rewrite -change @rpath/libwhisper.1.dylib @executable_path/libwhisper.1.dylib "$WHISPER_DIR/whisper-server"
rewrite -change /opt/homebrew/opt/ggml/lib/libggml.0.dylib @executable_path/libggml.0.dylib "$WHISPER_DIR/whisper-server"
rewrite -change /opt/homebrew/opt/ggml/lib/libggml-base.0.dylib @executable_path/libggml-base.0.dylib "$WHISPER_DIR/whisper-server"

rewrite -id @executable_path/libwhisper.1.dylib "$WHISPER_DIR/libwhisper.1.dylib"
rewrite -change /opt/homebrew/opt/whisper.cpp/lib/libwhisper.1.dylib @executable_path/libwhisper.1.dylib "$WHISPER_DIR/libwhisper.1.dylib"
rewrite -change /opt/homebrew/opt/ggml/lib/libggml.0.dylib @executable_path/libggml.0.dylib "$WHISPER_DIR/libwhisper.1.dylib"
rewrite -change /opt/homebrew/opt/ggml/lib/libggml-base.0.dylib @executable_path/libggml-base.0.dylib "$WHISPER_DIR/libwhisper.1.dylib"

rewrite -id @executable_path/libggml.0.dylib "$WHISPER_DIR/libggml.0.dylib"
rewrite -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib "$WHISPER_DIR/libggml.0.dylib"

rewrite -id @executable_path/libggml-base.0.dylib "$WHISPER_DIR/libggml-base.0.dylib"
rewrite -change /opt/homebrew/opt/libomp/lib/libomp.dylib @executable_path/libomp.dylib "$WHISPER_DIR/libggml-base.0.dylib"
rewrite -id @executable_path/libomp.dylib "$WHISPER_DIR/libomp.dylib"

for f in "$WHISPER_DIR"/*.so; do
    rewrite -change @rpath/libggml-base.0.dylib @executable_path/libggml-base.0.dylib "$f"
    rewrite -change /opt/homebrew/opt/libomp/lib/libomp.dylib @executable_path/libomp.dylib "$f"
done


if otool -L "$WHISPER_DIR/whisper-server" "$WHISPER_DIR"/*.dylib | grep -q "/opt/homebrew"; then
    echo "✗ Остались ссылки на /opt/homebrew:"
    otool -L "$WHISPER_DIR/whisper-server" "$WHISPER_DIR"/*.dylib | grep "/opt/homebrew"
    exit 1
fi

for f in "$WHISPER_DIR"/*; do
    codesign --force --sign - "$f" >/dev/null 2>&1
done

codesign --force --deep --sign - --identifier com.grigorii.whisperdictation --requirements '=designated => identifier "com.grigorii.whisperdictation"' "$APP"
echo "✓ Готово: $(pwd)/$APP"
