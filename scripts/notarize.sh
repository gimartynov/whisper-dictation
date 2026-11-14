#!/bin/bash
# Нотаризация уже собранного DMG (без пересборки): подпись DMG, тикет, SHA-256.
# Для полного цикла с нотаризацией самого приложения используйте scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="build/WhisperDictation.dmg"
APP="build/WhisperDictation.app"
PROFILE="${NOTARY_PROFILE:-whisper-dictation}"

if [ ! -f "$DMG" ]; then
    echo "✗ Нет $DMG — сначала ./make-dmg.sh"
    exit 1
fi

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
if [ -z "$IDENTITY" ]; then
    echo "✗ Нет сертификата Developer ID Application."
    exit 1
fi

echo "→ Проверка подписи приложения…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "→ Подпись DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "→ Нотаризация $(basename "$DMG") (обычно 1–5 минут)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "→ Прикрепление тикета к DMG…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# stapler меняет байты DMG, поэтому контрольная сумма считается только сейчас
shasum -a 256 "$DMG" | awk '{print $1"  WhisperDictation.dmg"}' > "$DMG.sha256"
echo "→ SHA-256 (после прикрепления тикета):"
cat "$DMG.sha256"

echo "→ Проверка Gatekeeper…"
spctl -a -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "✓ Нотаризация пройдена"
