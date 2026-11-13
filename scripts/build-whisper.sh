#!/bin/bash
# Собирает whisper-server статически: только системные библиотеки macOS,
# без Homebrew, без libomp, без внешних ggml-бэкендов.
set -euo pipefail
cd "$(dirname "$0")/.."

VER=1.9.5
VENDOR="$PWD/.vendor"
SRC="$VENDOR/whisper.cpp-$VER"
CM="${CMAKE:-$(command -v cmake || true)}"

mkdir -p "$VENDOR"

if [ ! -d "$SRC" ]; then
    echo "→ Скачиваю whisper.cpp $VER…"
    curl -L --retry 3 -o "$VENDOR/wcpp.tar.gz" \
        "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$VER.tar.gz"
    tar xzf "$VENDOR/wcpp.tar.gz" -C "$VENDOR"
fi

if [ -z "$CM" ] || [ ! -x "$CM" ]; then
    echo "✗ cmake не найден. Установите: brew install cmake"
    echo "  или скачайте CMake.app и передайте CMAKE=/path/to/cmake"
    exit 1
fi

echo "→ Собираю статический whisper-server…"
PREFIX_MAP="-ffile-prefix-map=$SRC=. -fmacro-prefix-map=$SRC=."
"$CM" -S "$SRC" -B "$SRC/build-static" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DGGML_METAL=ON -DGGML_NATIVE=OFF -DGGML_BLAS=OFF -DGGML_OPENMP=OFF \
    -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_SDL2=OFF \
    -DCMAKE_C_FLAGS="$PREFIX_MAP" -DCMAKE_CXX_FLAGS="$PREFIX_MAP"
"$CM" --build "$SRC/build-static" --target whisper-server --parallel 8

strip -x "$SRC/build-static/bin/whisper-server" 2>/dev/null || true
echo "✓ Готово: $SRC/build-static/bin/whisper-server"
otool -L "$SRC/build-static/bin/whisper-server"
