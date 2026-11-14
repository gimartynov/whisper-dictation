#!/bin/bash
# Нотаризация DMG в Apple. Требует:
#   1) сертификат "Developer ID Application" в связке ключей;
#   2) профиль notarytool:
#      xcrun notarytool store-credentials whisper-dictation \
#        --apple-id "you@example.com" --team-id K2R9STJQ84
#      (пароль — app-specific password с account.apple.com)
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-whisper-dictation}"
DMG="build/WhisperDictation.dmg"
APP="build/WhisperDictation.app"

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "✗ Нет сертификата Developer ID Application."
    echo "  Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
    exit 1
fi

echo "→ Проверка подписи…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "→ Нотаризация $(basename "$DMG") (обычно 1–5 минут)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "→ Прикрепление тикета…"
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# stapler меняет байты DMG, поэтому контрольная сумма считается только сейчас
shasum -a 256 "$DMG" | awk '{print $1"  WhisperDictation.dmg"}' > "$DMG.sha256"
echo "→ SHA-256 (после прикрепления тикета):"
cat "$DMG.sha256"

echo "→ Проверка Gatekeeper…"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "✓ Нотаризация пройдена"
