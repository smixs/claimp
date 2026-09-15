# Настройки dmgbuild для дистрибутивного DMG Claimp.
# Запускается из scripts/make-dmg.sh:
#   uvx dmgbuild -s dmg-settings.py -D app=<Claimp.app> -D background=<bg.tiff> Claimp <out.dmg>
# .DS_Store пишет сам dmgbuild (ds_store + mac_alias): раскладка детерминированная,
# в отличие от Finder/AppleScript, который сохраняет .DS_Store асинхронно и теряет её.
# Геометрия дублируется в scripts/make-dmg-bg.py - менять оба файла вместе.

app = defines["app"]  # noqa: F821 - подставляет dmgbuild

format = "UDZO"
filesystem = "HFS+"  # APFS-образы не монтируются на macOS < 10.13

files = [(app, "Claimp.app")]
symlinks = {"Applications": "/Applications"}
# Иконка тома = иконка приложения на значке диска (extras: dmgbuild[badge_icons]).
badge_icon = app + "/Contents/Resources/AppIcon.icns"

background = defines["background"]  # noqa: F821
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
# Содержимое 560x360 pt; +28 на титлбар.
window_rect = ((200, 180), (560, 388))
icon_size = 128
text_size = 13
scroll_position = (0, 0)
icon_locations = {
    "Claimp.app": (150, 230),
    "Applications": (410, 230),
    # Служебные файлы вынесены за окно: флаг invisible прячет их от обычного
    # пользователя, это - от тех, у кого включён показ скрытых файлов.
    ".background.tiff": (900, 130),
    ".VolumeIcon.icns": (900, 280),
    ".DS_Store": (900, 430),
    ".fseventsd": (900, 580),
    ".Trashes": (1060, 580),
}
