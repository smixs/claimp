#!/usr/bin/env python3
"""Фон DMG Claimp: тёмный прямоугольник темы, знак + надпись Claimp сверху,
стрелка «перетащи» между слотами иконок.

Рисуется детерминированно из исходников репозитория: SVG знака и логотипа
растеризуются системным рендером (`sips`, ImageIO), композиция - `magick`.
Внутренний SVG-рендер ImageMagick на claimp-logo.svg теряет заливку у первых
трёх букв (рисует их чёрными), поэтому SVG в magick напрямую не отдаём.

Геометрия совпадает с scripts/dmg-settings.py (окно 560x360 pt, иконки 128 pt,
центры (150, 230) и (410, 230)); при правке менять оба файла вместе.

Выход: build/dmg-bg@2x.png (1120x720). make-dmg.sh складывает из него HiDPI TIFF.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
OUT = BUILD / "dmg-bg@2x.png"

SCALE = 2
W_PT, H_PT = 560, 360  # содержимое окна DMG в точках
BG = "#2B2F3A"  # Theme.background.base
ARROW = "#FE6776"  # цвет надписи Claimp (claimp-logo.svg)

# Слоты иконок (точки, центры) - должны совпадать с dmg-settings.py.
ICON_SIZE_PT = 128
APP_CENTER_PT = (150, 230)
APPS_CENTER_PT = (410, 230)

# Брендовый блок сверху: знак слева, надпись справа, вместе по центру окна.
MARK_H_PT = 100
LOGO_H_PT = 52
BRAND_GAP_PT = 20
BRAND_TOP_PT = 24


def run(*args: str) -> None:
    subprocess.run(args, check=True, capture_output=True)


def px(pt: float) -> int:
    return int(round(pt * SCALE))


def rasterize(svg: Path, height_px: int, dest: Path) -> tuple[int, int]:
    """SVG -> PNG системным ImageIO (sips): цвета файла сохраняются как есть."""
    run("sips", "-s", "format", "png", "--resampleHeight", str(height_px),
        str(svg), "--out", str(dest))
    size = subprocess.run(["magick", "identify", "-format", "%w %h", str(dest)],
                          check=True, capture_output=True, text=True).stdout.split()
    return int(size[0]), int(size[1])


def main() -> int:
    mark_svg = ROOT / "Resources/Logo/claimp-mark.svg"
    logo_svg = ROOT / "Resources/Logo/claimp-logo.svg"
    for src in (mark_svg, logo_svg):
        if not src.is_file():
            print(f"ERROR: нет {src}", file=sys.stderr)
            return 1

    BUILD.mkdir(parents=True, exist_ok=True)
    work = BUILD / "dmg-bg-work"
    subprocess.run(["rm", "-rf", str(work)], check=True)
    work.mkdir(parents=True)

    mark_png = work / "mark.png"
    logo_png = work / "logo.png"
    mark_w, mark_h = rasterize(mark_svg, px(MARK_H_PT), mark_png)
    logo_w, logo_h = rasterize(logo_svg, px(LOGO_H_PT), logo_png)

    brand_w = mark_w + px(BRAND_GAP_PT) + logo_w
    brand_x = (px(W_PT) - brand_w) // 2
    mark_y = px(BRAND_TOP_PT)
    # Надпись выравнивается по середине знака.
    logo_x = brand_x + mark_w + px(BRAND_GAP_PT)
    logo_y = mark_y + (mark_h - logo_h) // 2

    # Стрелка между иконками: от правого края иконки приложения к левому краю Applications.
    ay = px(APP_CENTER_PT[1])
    x0 = px(APP_CENTER_PT[0] + ICON_SIZE_PT / 2 + 14)
    x1 = px(APPS_CENTER_PT[0] - ICON_SIZE_PT / 2 - 14)
    shaft = px(5)
    head = px(15)

    run("magick", "-size", f"{px(W_PT)}x{px(H_PT)}", f"xc:{BG}",
        str(mark_png), "-geometry", f"+{brand_x}+{mark_y}", "-composite",
        str(logo_png), "-geometry", f"+{logo_x}+{logo_y}", "-composite",
        "-fill", ARROW, "-stroke", "none",
        "-draw", f"rectangle {x0},{ay - shaft} {x1 - 2 * head},{ay + shaft}",
        "-draw", f"polygon {x1},{ay} {x1 - 2 * head},{ay - head} {x1 - 2 * head},{ay + head}",
        "-density", "144", "-units", "PixelsPerInch",
        str(OUT))

    subprocess.run(["rm", "-rf", str(work)], check=True)
    print(OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
