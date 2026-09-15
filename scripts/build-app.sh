#!/usr/bin/env bash
# Собирает release и складывает build/Claimp.app с Info.plist и подписью
# (ad-hoc по умолчанию, Developer ID при SIGN_ID/SIGN_FLAGS).
# Основан на шаблоне скилла macos-spm-app-packaging (assets/templates/package_app.sh).
set -euo pipefail

# Тулчейн один на все скрипты и Makefile: SDK macOS 27 с MusicUnderstanding (scripts/toolchain.sh).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain.sh"

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-Claimp}
BUNDLE_ID=${BUNDLE_ID:-dev.shima.claimp}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-27.0}
# Подпись. По умолчанию ad-hoc ("-"): локальная сборка и запуск.
# Дистрибутив: SIGN_ID="Developer ID Application: ..." SIGN_FLAGS="--options runtime --timestamp"
# (см. цель `dist` в Makefile). SIGN_FLAGS разбивается по пробелам в массив аргументов.
SIGN_ID=${SIGN_ID:--}
SIGN_FLAGS=${SIGN_FLAGS:-}

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
fi
MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  ARCH_LIST=("$(uname -m)")
fi

for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH"
done

# Иконка: пересобираем, если её нет или знак новее (скрипт детерминированный).
ICON_SRC="$ROOT/Resources/Logo/claimp-mark.svg"
ICON="$ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON" || "$ICON_SRC" -nt "$ICON" ]]; then
  bash "$ROOT/scripts/make-icon.sh"
fi

APP="$ROOT/build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>audio</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
            </array>
        </dict>
        <dict>
            <key>LSTypeIsPackage</key><false/>
            <key>CFBundleTypeName</key><string>folder</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

# Каталог продуктов спрашиваем у самого SwiftPM: у тулчейна CLT (Swift 6.4, новая система
# сборки) это `.build/out/Products/<Conf>`, а не `.build/<arch>-apple-macosx/<conf>`, как было
# у Xcode 26.6. Захардкоженный путь ломал сборку .app молча - «нет бинарника для arm64».
build_product_path() {
  local arch="$1"
  local dir
  dir=$(swift build -c "$CONF" --arch "$arch" --show-bin-path)
  if [[ -f "$dir/$APP_NAME" ]]; then
    echo "$dir/$APP_NAME"
  else
    echo "$dir/App"
  fi
}

BINARIES=()
for ARCH in "${ARCH_LIST[@]}"; do
  SRC=$(build_product_path "$ARCH")
  if [[ ! -f "$SRC" ]]; then
    echo "ERROR: нет собранного бинарника для ${ARCH} (искал ${SRC})" >&2
    exit 1
  fi
  BINARIES+=("$SRC")
done

DEST="$APP/Contents/MacOS/$APP_NAME"
if [[ ${#BINARIES[@]} -gt 1 ]]; then
  lipo -create "${BINARIES[@]}" -output "$DEST"
else
  cp "${BINARIES[0]}" "$DEST"
fi
chmod +x "$DEST"

if [[ ! -f "$ICON" ]]; then
  echo "ERROR: нет $ICON после make-icon.sh" >&2
  exit 1
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Ресурсные бандлы SwiftPM лежат рядом с бинарником.
BUILD_DIR="$(dirname "${BINARIES[0]}")"
shopt -s nullglob
BUNDLES=("${BUILD_DIR}/"*.bundle)
FRAMEWORKS=("${BUILD_DIR}/"*.framework)
shopt -u nullglob
for bundle in "${BUNDLES[@]}"; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
if [[ ${#FRAMEWORKS[@]} -gt 0 ]]; then
  cp -R "${FRAMEWORKS[@]}" "$APP/Contents/Frameworks/"
  chmod -R a+rX "$APP/Contents/Frameworks"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$DEST"
fi

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

# Подпись строго изнутри наружу (inside-out): вложенные бинарники фреймворков →
# сами фреймворки → ресурсные бандлы → приложение. `codesign --deep` Apple не
# рекомендует: он не даёт задать флаги для вложенного кода, а нотаризация требует
# hardened runtime и на фреймворках тоже.
SIGN_ARGS=(--force --sign "$SIGN_ID")
read -r -a SIGN_FLAG_ARGS <<< "$SIGN_FLAGS"
if [[ ${#SIGN_FLAG_ARGS[@]} -gt 0 ]]; then
  SIGN_ARGS+=("${SIGN_FLAG_ARGS[@]}")
fi

for fw in "$APP/Contents/Frameworks/"*.framework; do
  [[ -d "$fw" ]] || continue
  # Внутренние подписи xcframework-бинарников SFBAudioEngine чужие (их автор):
  # для нотаризации каждый Mach-O должен нести нашу Developer ID подпись.
  while IFS= read -r -d '' bin; do
    codesign "${SIGN_ARGS[@]}" "$bin"
  done < <(find "$fw" -type f -perm -111 -print0)
  codesign "${SIGN_ARGS[@]}" "$fw"
done

# Ресурсные бандлы SwiftPM. Подписываем только настоящие бандлы (с Info.plist):
# без него codesign отвечает "bundle format unrecognized" - такой каталог для него
# просто ресурс и запечатывается подписью приложения.
for rb in "$APP/Contents/Resources/"*.bundle; do
  [[ -d "$rb" ]] || continue
  [[ -f "$rb/Info.plist" || -f "$rb/Contents/Info.plist" ]] || continue
  codesign "${SIGN_ARGS[@]}" "$rb"
done

codesign "${SIGN_ARGS[@]}" "$APP"

echo "Собрано: $APP (подпись: $SIGN_ID ${SIGN_FLAGS})"
