#!/usr/bin/env bash
# Собирает дистрибутивный DMG Claimp через dmgbuild (uvx): тёмный фон со знаком
# и надписью, слева Claimp.app, справа ярлык Applications, между ними стрелка.
# Раскладка пишется детерминированно в .DS_Store самим dmgbuild, без Finder.
# Использование: scripts/make-dmg.sh <path/to/Claimp.app> <output.dmg>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/make-dmg.sh <Claimp.app> <out.dmg>" >&2
  exit 2
fi

APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: нет приложения $APP" >&2
  exit 1
fi

# Фон рисуется скриптом из SVG знака и надписи - каждый раз заново, чтобы
# правка логотипа сразу попадала в DMG.
BG2X="$ROOT/build/dmg-bg@2x.png"
python3 "$ROOT/scripts/make-dmg-bg.py" > /dev/null

# HiDPI TIFF: 1x получается уменьшением @2x, Finder сам выбирает нужное представление.
WORK="$ROOT/build/dmg-work"
rm -rf "$WORK"
mkdir -p "$WORK"
sips -Z 560 "$BG2X" --out "$WORK/bg-1x.png" > /dev/null
tiffutil -cathidpicheck "$WORK/bg-1x.png" "$BG2X" -out "$WORK/bg.tiff" 2>/dev/null

rm -f "$OUT"
uvx --from 'dmgbuild[badge_icons]' dmgbuild \
    -s "$ROOT/scripts/dmg-settings.py" \
    -D app="$APP" -D background="$WORK/bg.tiff" \
    Claimp "$OUT"
rm -rf "$WORK"
echo "Собрано: $OUT"
