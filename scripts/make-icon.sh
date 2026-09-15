#!/usr/bin/env bash
# Иконка приложения Claimp: знак владельца (Resources/Logo/claimp-mark.svg) по центру
# тёмного скруглённого квадрата цвета темы. Детерминированно: один мастер 1024 и ресайзы.
# Запускается из build-app.sh (когда icns старше знака) или руками.
set -euo pipefail

# Тулчейн один на все скрипты и Makefile: SDK macOS 27 с MusicUnderstanding (scripts/toolchain.sh).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

MARK=${MARK:-Resources/Logo/claimp-mark.svg}
OUT=${OUT:-Resources/AppIcon.icns}
BG=${BG:-#2B2F3A}          # Theme.background.base
MASTER=1024
PAD_PERCENT=18             # поля с каждой стороны
RADIUS_PERCENT=225         # 22.5 % стороны, стандартная маска macOS (десятые доли)

if ! command -v magick >/dev/null 2>&1; then
  echo "ERROR: нет magick (ImageMagick), иконку собрать нечем" >&2
  exit 1
fi
if [[ ! -f "$MARK" ]]; then
  echo "ERROR: нет знака $MARK" >&2
  exit 1
fi

INNER=$(( MASTER * (100 - 2 * PAD_PERCENT) / 100 ))
RADIUS=$(( MASTER * RADIUS_PERCENT / 1000 ))
WORK="$ROOT/build/icon-work"
ICONSET="$WORK/Claimp.iconset"
rm -rf "$WORK"
mkdir -p "$ICONSET"

# -trim: в SVG знака есть пустые поля, без обрезки штрихи уезжают из центра квадрата.
magick -background none "$MARK" -trim +repage -resize "${INNER}x${INNER}" "$WORK/mark.png"
magick -size "${MASTER}x${MASTER}" xc:none -fill "$BG" \
  -draw "roundrectangle 0,0,$((MASTER - 1)),$((MASTER - 1)),$RADIUS,$RADIUS" "$WORK/bg.png"
magick "$WORK/bg.png" "$WORK/mark.png" -gravity center -composite "$WORK/master.png"

# Имена и размеры - те, что ждёт iconutil.
while read -r size name; do
  magick "$WORK/master.png" -resize "${size}x${size}" "$ICONSET/${name}.png"
done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
cp "$WORK/master.png" "$ROOT/build/icon-master.png"
rm -rf "$WORK"
echo "Иконка: $OUT (мастер для проверки: build/icon-master.png)"
