#!/usr/bin/env bash
# Пересобирает .app и запускает его.
set -euo pipefail

# Тулчейн один на все скрипты и Makefile: SDK macOS 27 с MusicUnderstanding (scripts/toolchain.sh).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=${APP_NAME:-Claimp}

pkill -x "$APP_NAME" 2>/dev/null || true
"$ROOT/scripts/build-app.sh" release
open "$ROOT/build/${APP_NAME}.app"
