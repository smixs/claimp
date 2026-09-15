#!/usr/bin/env bash
# Пересобирает .app и запускает его.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP_NAME=${APP_NAME:-Claimp}

pkill -x "$APP_NAME" 2>/dev/null || true
"$ROOT/scripts/build-app.sh" release
open "$ROOT/build/${APP_NAME}.app"
