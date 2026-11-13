#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

rm -rf dist
mkdir -p dist
cp -R build/WhisperDictation.app dist/
ln -sfn /Applications dist/Applications
cp "Resources/Установка.txt" dist/
cp THIRD-PARTY-NOTICES.txt dist/
cp LICENSE dist/LICENSE.txt
cp PRIVACY.md dist/PRIVACY.md

rm -f build/WhisperDictation.dmg
chmod 0644 dist/*.txt dist/*.md 2>/dev/null || true
hdiutil create -volname "Whisper Dictation" -srcfolder dist -ov -format UDZO build/WhisperDictation.dmg >/dev/null

shasum -a 256 build/WhisperDictation.dmg | awk '{print $1"  WhisperDictation.dmg"}' > build/WhisperDictation.dmg.sha256

echo "✓ DMG: $(pwd)/build/WhisperDictation.dmg"
cat build/WhisperDictation.dmg.sha256
du -h build/WhisperDictation.dmg
