#!/usr/bin/env bash
# Живой запуск собранного .app при ВРЕМЕННО СКРЫТОМ каталоге .build.
#
# Зачем: ресурсы таргета App лежат в `Claimp_App.bundle`. Штатный SwiftPM-аксессор
# ресурсов модуля ищет этот бандл рядом с `.app` и по АБСОЛЮТНОМУ пути каталога
# сборки, поэтому на машине разработчика приложение запускается даже тогда, когда
# внутри `.app` бандл лежит не там, где его ищут, - а у пользователя из
# `/Applications` падает fatalError. Релиз 0.1.0 уехал именно с этим дефектом.
# Скрываем `.build` и проверяем, что приложение живо без него: гейт видит то же,
# что пользователь.
#
# Запускаем ровно как пользователь - через `open` (LaunchServices). Прямой запуск
# исполняемого файла НЕ годится: при нём главный бандл резолвится иначе и битое
# приложение 0.1.0 спокойно живёт (проверено 15.09.2026). Свой процесс ищем по
# полному пути исполняемого файла копии (`pgrep -f`), а не по имени: `pgrep -x
# Claimp` ловит чужой запущенный или падающий экземпляр и даёт ложное «OK».
# Использование: scripts/verify-launch.sh [path/to/Claimp.app] [секунды ожидания]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP=${1:-build/Claimp.app}
WAIT=${2:-5}
HIDDEN="$ROOT/.build.hidden-verify"
WORK="$ROOT/.scratch/work/evidence/verify-launch"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: нет приложения $APP" >&2
  exit 1
fi
NAME=$(basename "$APP")
EXEC="$WORK/$NAME/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
if pgrep -f "$EXEC" > /dev/null; then
  echo "ERROR: копия из прошлого прогона ещё запущена: $EXEC" >&2
  exit 1
fi

restore() {
  if [[ -d "$HIDDEN" ]]; then
    rm -rf "$ROOT/.build"
    mv "$HIDDEN" "$ROOT/.build"
  fi
}
trap restore EXIT INT TERM

rm -rf "$WORK"
mkdir -p "$WORK"
ditto "$APP" "$WORK/$NAME"

if [[ -d "$ROOT/.build" ]]; then
  mv "$ROOT/.build" "$HIDDEN"
fi

open -n "$WORK/$NAME"
sleep "$WAIT"
PIDS=$(pgrep -f "$EXEC" || true)

if [[ -z "$PIDS" ]]; then
  echo "FAIL: приложение не живёт через ${WAIT} с без каталога .build" >&2
  echo "--- свежий crash-репорт, если он есть:" >&2
  ls -t "$HOME/Library/Logs/DiagnosticReports"/Claimp-*.ips 2> /dev/null | head -1 >&2
  exit 1
fi

for pid in $PIDS; do
  kill "$pid"
done
for _ in 1 2 3 4 5 6; do
  pgrep -f "$EXEC" > /dev/null || break
  sleep 0.5
done
for pid in $(pgrep -f "$EXEC" || true); do
  kill -9 "$pid" 2> /dev/null || true
done
echo "OK: запуск без .build прошёл (свой pid $PIDS, процесс остановлен)"
