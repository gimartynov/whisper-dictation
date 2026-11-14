#!/bin/bash
# Устанавливает Whisper Dictation в «Программы».
# Приложение подписано Developer ID и нотаризовано, поэтому карантин снимать
# не нужно: Gatekeeper сам проверит подпись при первом запуске.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/WhisperDictation.app"

echo "Whisper Dictation — установка"
echo "============================="
echo

if [ ! -d "$SRC" ]; then
    echo "✗ Рядом со скриптом нет WhisperDictation.app."
    echo "  Запускайте этот файл прямо из окна смонтированного DMG."
    echo
    read -n 1 -s -r -p "Нажмите любую клавишу, чтобы закрыть…"
    exit 1
fi

DEST="${WD_DEST:-/Applications/WhisperDictation.app}"

echo "→ Копирую в «Программы»…"
if ! rm -rf "$DEST" 2>/dev/null || ! ditto "$SRC" "$DEST" 2>/dev/null; then
    DEST="$HOME/Applications/WhisperDictation.app"
    echo "  Нет прав на /Applications — ставлю в ~/Applications."
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$SRC" "$DEST"
fi

echo "→ Запускаю…"
killall WhisperDictation 2>/dev/null || true
open "$DEST"

echo
echo "✓ Готово. Приложение лежит здесь:"
echo "  $DEST"
echo
echo "Дальше: скачайте модель 1,6 ГБ в открывшемся окне,"
echo "разрешите микрофон и нажмите ⌥ Space для записи."
echo
read -n 1 -s -r -p "Нажмите любую клавишу, чтобы закрыть это окно…"
