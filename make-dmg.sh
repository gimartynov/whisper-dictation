#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

rm -rf dist
mkdir -p dist
cp -R build/WhisperDictation.app dist/
cp "Resources/Установка.txt" dist/
cp THIRD-PARTY-NOTICES.txt dist/

rm -f build/WhisperDictation.dmg
hdiutil create -volname "Whisper Dictation" -srcfolder dist -ov -format UDZO build/WhisperDictation.dmg >/dev/null

echo "✓ DMG: $(pwd)/build/WhisperDictation.dmg"
du -h build/WhisperDictation.dmg
