#!/usr/bin/env bash
# Единая точка тулчейна для людей и агентов: где брать swift и SDK.
#
# Анализ BPM/тональности собран на системном фреймворке MusicUnderstanding, а он есть
# только в SDK macOS 27 из Command Line Tools (в SDK Xcode 26.6 его нет вовсе).
# Поэтому и сборка, и тесты, и упаковка идут с DEVELOPER_DIR на CLT. Значение можно
# переопределить снаружи (`DEVELOPER_DIR=... make build`), но SDK обязан содержать
# фреймворк - иначе останавливаемся здесь с понятной причиной, а не падаем потом
# на `no such module 'MusicUnderstanding'`.
#
# Использование:
#   source scripts/toolchain.sh   - в скриптах (выставляет и проверяет);
#   scripts/toolchain.sh          - отдельной строкой в Makefile (только проверяет).
: "${DEVELOPER_DIR:=/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR

# SDK лежит по-разному у CLT и у Xcode; `xcrun --show-sdk-path` здесь не годится - при
# DEVELOPER_DIR на Xcode он всё равно отдаёт путь CLT и проверка врёт (проверено 15.09).
CLAIMP_FRAMEWORK=""
for sdk in "$DEVELOPER_DIR/SDKs/MacOSX.sdk" "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"; do
  if [[ -d "$sdk/System/Library/Frameworks/MusicUnderstanding.framework" ]]; then
    CLAIMP_FRAMEWORK="$sdk/System/Library/Frameworks/MusicUnderstanding.framework"
    break
  fi
done
if [[ -z "$CLAIMP_FRAMEWORK" ]]; then
  echo "ERROR: в SDK этого тулчейна нет MusicUnderstanding.framework" >&2
  echo "       DEVELOPER_DIR=$DEVELOPER_DIR" >&2
  echo "       Claimp требует SDK macOS 27 (Swift 6.4) из Command Line Tools." >&2
  echo "       Проверь: ls /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks | grep MusicUnderstanding" >&2
  echo "       Собирать так: DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build (или make build)." >&2
  exit 1
fi
