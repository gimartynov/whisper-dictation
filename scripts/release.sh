#!/bin/bash
# Полный релизный цикл: подпись → нотаризация приложения → DMG → нотаризация
# DMG → stapling → SHA-256. Требует Developer ID и профиль notarytool.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/WhisperDictation.app"
DMG="build/WhisperDictation.dmg"
PROFILE="${NOTARY_PROFILE:-whisper-dictation}"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
fi
if [ -z "$IDENTITY" ]; then
    echo "✗ Нет сертификата Developer ID Application — релиз невозможен."
    exit 1
fi

echo "→ 1/6 Сборка (Developer ID обязателен)…"
REQUIRE_DEVELOPER_ID=1 CODESIGN_IDENTITY="$IDENTITY" ./build.sh

echo "→ 2/6 Нотаризация приложения…"
rm -f /tmp/wd-app.zip
ditto -c -k --keepParent "$APP" /tmp/wd-app.zip
xcrun notarytool submit /tmp/wd-app.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "→ 3/6 DMG из уже застапленного приложения…"
SKIP_BUILD=1 ./make-dmg.sh

echo "→ 4/6 Подпись и нотаризация DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "→ 5/6 SHA-256 после stapling…"
shasum -a 256 "$DMG" | awk '{print $1"  WhisperDictation.dmg"}' > "$DMG.sha256"
cat "$DMG.sha256"

echo "→ 6/6 Проверка Gatekeeper…"
spctl -a -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "✓ Релиз готов: $PWD/$DMG"
