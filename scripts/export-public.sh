#!/usr/bin/env bash
# export-public.sh - собирает чистое дерево для публичного релиза Claimp.
#
# Берёт файлы из текущего checkout и складывает в
#   .scratch/public-export/claimp
# без внутренних материалов: рабочего каталога .scratch, чужих worktree, скриншотов
# экрана владельца (research/owner-*.png), ресёрч-клона research/raw, журнала
# решений DECISIONS.md, черновика OPEN-QUESTIONS.md. Затем git init и один коммит
# «Claimp: initial public release».
#
# Идемпотентно: каталог экспорта пересоздаётся с нуля, повторный запуск даёт то же
# содержимое (отличается только время коммита). Ничего не пушит и не трогает
# репозиторий-источник.
#
# Использование:
#   bash scripts/export-public.sh            # собрать дерево и сделать коммит
#   bash scripts/export-public.sh --verify   # плюс swift build и swift test в экспорте
#
# Автор коммита - штатный git-идентификатор (git config user.name/user.email);
# переопределяется переменными GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL перед запуском.
#
# Дополнительные запрещённые строки (внутренние имена проектов и т.п.) задаются
# снаружи, чтобы сами они не оказались в публичном дереве:
#   EXTRA_BANNED_PATTERNS='имя1 имя2' bash scripts/export-public.sh
set -euo pipefail

# Тулчейн один на все скрипты и Makefile: SDK macOS 27 с MusicUnderstanding (scripts/toolchain.sh).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/toolchain.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXPORT_BASE=${EXPORT_BASE:-"$ROOT/.scratch/public-export"}
DEST="$EXPORT_BASE/claimp"
COMMIT_MSG="Claimp: initial public release"

# Файлы в корне публичного дерева.
FILES=(
  .gitignore
  version.env
  Package.swift
  Package.resolved
  Makefile
  README.md
  LICENSE
  NOTICE
  SPEC.md
  PLAN.md
  AGENTS.md
  implementation-notes.md
)

# Фид автообновления: появляется после первого `make appcast` (цель релиза) и
# коммитится в публичный main - Sparkle читает его по raw-ссылке. До первого релиза
# со Sparkle файла в репозитории нет, поэтому список отдельный: отсутствие - строка
# отчёта, а не остановка.
OPTIONAL_FILES=(
  appcast.xml
)

# Каталоги, которые копируются целиком (внутреннее вычищается ниже).
DIRS=(
  Sources
  Tests
  Resources
  scripts
  docs
  research
)

VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --verify) VERIFY=1 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "неизвестный аргумент: $arg (см. --help)" >&2; exit 2 ;;
  esac
done

# Страховка на rm -rf: экспорт живёт только внутри .scratch репозитория.
case "$DEST" in
  "$ROOT"/.scratch/*) ;;
  *) echo "СТОП: экспорт вне <репо>/.scratch: $DEST" >&2; exit 1 ;;
esac

echo "== Источник: $ROOT"
echo "== Экспорт:  $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"

for f in "${FILES[@]}"; do
  if [[ ! -f "$ROOT/$f" ]]; then
    echo "СТОП: нет файла $f - публичное дерево будет неполным" >&2
    exit 1
  fi
  cp "$ROOT/$f" "$DEST/$f"
done

for f in "${OPTIONAL_FILES[@]}"; do
  if [[ -f "$ROOT/$f" ]]; then
    cp "$ROOT/$f" "$DEST/$f"
  else
    echo "== $f в источнике нет (первый релиз со Sparkle ещё не выпущен) - в экспорт не идёт"
  fi
done

for d in "${DIRS[@]}"; do
  if [[ ! -d "$ROOT/$d" ]]; then
    echo "СТОП: нет каталога $d" >&2
    exit 1
  fi
  cp -R "$ROOT/$d" "$DEST/$d"
done

# Внутренние материалы, которые могли попасть вместе с каталогами.
find "$DEST" -name '.DS_Store' -delete
find "$DEST" -type d -name '.scratch' -prune -exec rm -rf {} +
find "$DEST" -type d -name '.worktrees' -prune -exec rm -rf {} +
find "$DEST" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$DEST" -type d -name '.build' -prune -exec rm -rf {} +
find "$DEST" -type d -name 'build' -prune -exec rm -rf {} +
rm -rf "$DEST/research/raw"
find "$DEST/research" -maxdepth 1 -type f -name 'owner-*.png' -delete

# --- проверки: ничего личного и ничего внутреннего -------------------------

fail=0
for absent in .scratch .worktrees DECISIONS.md OPEN-QUESTIONS.md research/raw; do
  if [[ -e "$DEST/$absent" ]]; then
    echo "СТОП: в экспорте оказался $absent" >&2
    fail=1
  fi
done

for required in LICENSE NOTICE README.md Package.swift docs/screenshots/claimp-window.webp \
                docs/screenshots/claimp-logo.png \
                research/aimp-reference.png research/INDEX.md Sources/App/Theme.swift; do
  if [[ ! -e "$DEST/$required" ]]; then
    echo "СТОП: в экспорте нет обязательного $required" >&2
    fail=1
  fi
done

check_absent() { # <шаблон> <что это>
  # Сам этот скрипт исключается из поиска: искомые строки записаны в нём как образцы.
  local hits
  hits=$(grep -rIl --exclude='export-public.sh' -e "$1" "$DEST" || true)
  if [[ -n "$hits" ]]; then
    echo "СТОП: в экспорте найдено «$2» ($1):" >&2
    echo "$hits" >&2
    fail=1
  fi
}

check_absent '/Users/' 'абсолютный путь с домашним каталогом'

# Внутренние имена извне: список в EXTRA_BANNED_PATTERNS (через пробел).
for pattern in ${EXTRA_BANNED_PATTERNS:-}; do
  check_absent "$pattern" "строка из EXTRA_BANNED_PATTERNS"
done

# Telegram в публичном дереве не запрещён: это сценарий drag-out в SPEC и
# в research/03 (проверенный на файлах из Telegram формат Ogg/Opus).
# Поэтому не ошибка, а строка отчёта.
telegram=$(grep -rIl --exclude='export-public.sh' -i -e 'telegram' "$DEST" || true)
if [[ -n "$telegram" ]]; then
  echo "== Упоминания Telegram (ожидаемо, сценарий drag-out):"
  echo "$telegram" | sed "s|^$DEST/||"
fi

# Скриншоты экрана владельца не должны попасть в дерево ни под каким именем.
owner_png=$(find "$DEST" -type f -name 'owner-*.png' || true)
if [[ -n "$owner_png" ]]; then
  echo "СТОП: в экспорте скриншоты владельца:" >&2
  echo "$owner_png" >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo "Экспорт не собран: см. СТОП выше." >&2
  exit 1
fi

# --- git init + один коммит ----------------------------------------------

cd "$DEST"
git init -q
git add -A
git commit -q -m "$COMMIT_MSG"

echo "== Готово: $DEST"
echo "== Файлов в коммите: $(git ls-files | wc -l | tr -d ' ')"
echo "== Коммит: $(git rev-parse --short HEAD) $COMMIT_MSG"
echo "== Автор:  $(git log -1 --format='%an <%ae>')"
echo "== Черновики задач и журнал решений в дерево не попали (grep по /Users/ даёт 0)."
if [[ -n "${EXTRA_BANNED_PATTERNS:-}" ]]; then
  echo "== Дополнительные запрещённые строки ($EXTRA_BANNED_PATTERNS) не найдены."
fi

if [[ $VERIFY -eq 1 ]]; then
  echo "== swift build в экспорте"
  swift build
  echo "== swift test в экспорте"
  swift test
fi
