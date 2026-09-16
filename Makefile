.PHONY: build test app run clean dist notarize verify release toolchain brew-cask sparkle-keys appcast

# Тулчейн один на всех: анализ BPM/тональности собирается только SDK macOS 27 из
# Command Line Tools (в SDK Xcode 26.6 нет MusicUnderstanding.framework). Значение
# можно переопределить снаружи, но цель `toolchain` проверит, что фреймворк на месте,
# и остановит сборку с понятной причиной. Вручную: DEVELOPER_DIR=... swift build.
DEVELOPER_DIR ?= /Library/Developer/CommandLineTools
export DEVELOPER_DIR

# Версия берётся из version.env (тот же источник, что и у build-app.sh).
VERSION = $(shell sed -n 's/^MARKETING_VERSION=//p' version.env)
APP_BUNDLE = build/Claimp.app
ZIP = build/Claimp-$(VERSION).zip
DMG = build/Claimp-$(VERSION).dmg

# Дистрибутивная подпись: Developer ID + hardened runtime + доверенный таймстамп -
# без этого нотаризация не принимает. Локальная сборка (`make app`) подписывается
# ad-hoc, идентификатор ей не нужен.
DIST_SIGN_ID ?= Developer ID Application: MAJENTO, MCHJ (M37N642Q58)
DIST_SIGN_FLAGS = --options runtime --timestamp
# Профиль нотаризации в Keychain (создан один раз, команда та же, что у сертификата:
#   xcrun notarytool store-credentials majento-notary \
#     --apple-id <apple-id> --team-id M37N642Q58 --password <app-specific-password>)
# Профиль чужой команды не подойдёт: notarytool проверяет, что Team ID подписи совпадает.
NOTARY_PROFILE ?= majento-notary

# Утилиты Sparkle (generate_keys / generate_appcast) приезжают тем же бинарным
# артефактом, что и сам фреймворк; конкретный путь выбирает SwiftPM, поэтому его
# ищем, а не прописываем. Артефакт появляется после `make build`.
SPARKLE_BIN = $(shell find .build/artifacts -type d -path '*/sparkle/Sparkle/bin' | head -1)
# Каталог для фида: ровно один архив - последняя версия. Дельт у Claimp нет осознанно.
UPDATES_DIR = build/updates

toolchain:
	scripts/toolchain.sh

build: toolchain
	swift build

# Плагин макросов swift-testing грузим в процесс компилятора: через отдельный сервер
# плагинов тулчейн CLT теряет его («TestingMacros ... not found», 3 из 3 прогонов 16.09),
# с -load-plugin-library 3 из 3 зелёные. Путь считается от DEVELOPER_DIR.
TESTING_MACROS = $(DEVELOPER_DIR)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
TEST_BUILD_FLAGS = -Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS)

test: toolchain
	test -f "$(TESTING_MACROS)" || { echo "ERROR: нет плагина макросов swift-testing: $(TESTING_MACROS)"; exit 1; }
	swift build --build-tests $(TEST_BUILD_FLAGS)
	swift test --skip-build

app:
	scripts/build-app.sh

run:
	scripts/run.sh

clean:
	rm -rf .build build

# Дистрибутив: одно приложение с Developer ID уезжает и в zip, и в DMG.
# После `make dist` обязателен `make notarize` - без тикета Gatekeeper покажет
# «повреждено» на чужой машине.
dist:
	SIGN_ID="$(DIST_SIGN_ID)" SIGN_FLAGS="$(DIST_SIGN_FLAGS)" scripts/build-app.sh release
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	scripts/make-dmg.sh "$(APP_BUNDLE)" "$(DMG)"

# Нотаризация. Сначала приложение (в zip - notarytool не принимает .app), затем
# stapler кладёт тикет внутрь бандла; zip после этого пересобирается, чтобы в нём
# лежала уже проштампованная копия.
# DMG пересобирается ПОСЛЕ штамповки приложения: образ из `dist` содержит копию
# приложения без тикета, и вытащенная из него копия проверяется у Apple по сети
# (`stapler validate` на такой копии = «does not have a ticket stapled»). Своя
# нотаризация DMG этого не лечит - тикет образа на вложенное приложение не
# распространяется. Затем образ подписывается и нотаризуется отдельно.
notarize:
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP_BUNDLE)" "$(ZIP)"
	scripts/make-dmg.sh "$(APP_BUNDLE)" "$(DMG)"
	codesign --force --timestamp --sign "$(DIST_SIGN_ID)" "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"

# Проверки готового дистрибутива: ресурсы, живой запуск, подпись, тикет, Gatekeeper.
# Первые два шага - про дефект релиза 0.1.0: аксессор ресурсов модуля находил
# `Claimp_App.bundle` по пути каталога сборки, поэтому на машине разработчика всё
# работало, а установленное приложение падало на старте.
verify: toolchain
	if grep -rn "Bundle\.module" Sources; then echo "ERROR: аксессор ресурсов модуля в Sources - установленное приложение не найдёт Claimp_App.bundle"; exit 1; fi
	scripts/verify-launch.sh "$(APP_BUNDLE)"
	codesign -vvv --deep --strict "$(APP_BUNDLE)"
	/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$(APP_BUNDLE)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$(APP_BUNDLE)/Contents/Info.plist"
	codesign -dv --verbose=4 "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"
	xcrun stapler validate "$(DMG)"
	spctl -a -vv -t install "$(DMG)"
	spctl -a -vv "$(APP_BUNDLE)"

# Одноразовая настройка автообновления. generate_keys кладёт приватный ключ EdDSA в
# login Keychain под аккаунтом Claimp (ключ Sezish не переиспользуем) и печатает
# публичный - его и только его кладём в Resources/sparkle-public-key.txt.
# Приватный ключ не коммитить и не пересылать; резервная копия делается отдельно
# (`generate_keys --account Claimp -x <файл>`) и хранится офлайн: потеря ключа
# означает, что уже установленные копии обновить больше нечем.
sparkle-keys: build
	$(SPARKLE_BIN)/generate_keys --account Claimp
	$(SPARKLE_BIN)/generate_keys --account Claimp -p > Resources/sparkle-public-key.txt

# Фид обновлений. Запускать ПОСЛЕ `make notarize`: именно там zip пересобирается из
# проштампованного бандла, и в фид должен попасть архив с тикетом.
# generate_appcast подписывает архив приватным ключом из Keychain (аккаунт Claimp)
# и пишет appcast.xml; копия в корне репозитория - это и есть публикуемый фид
# (raw main), его коммитит тимлид.
appcast:
	rm -rf "$(UPDATES_DIR)"
	mkdir -p "$(UPDATES_DIR)"
	cp "$(ZIP)" "$(UPDATES_DIR)/Claimp-$(VERSION).zip"
	$(SPARKLE_BIN)/generate_appcast "$(UPDATES_DIR)" --account Claimp \
		--download-url-prefix https://github.com/smixs/claimp/releases/download/v$(VERSION)/ \
		--link https://github.com/smixs/claimp
	cp "$(UPDATES_DIR)/appcast.xml" appcast.xml

# Полный релиз. Перед запуском поднять в version.env И MARKETING_VERSION, И
# BUILD_NUMBER: Sparkle сравнивает CFBundleVersion (BUILD_NUMBER), и если он не
# вырос, установленные копии новую версию просто не увидят.
release:
	$(MAKE) dist
	$(MAKE) notarize
	$(MAKE) appcast
	$(MAKE) verify

# Homebrew tap smixs/homebrew-claimp: после публикации релиза на GitHub обновить версию и
# sha256 каска и запушить. Клон tap лежит в .scratch/public-export/homebrew-claimp.
TAP_DIR = .scratch/public-export/homebrew-claimp
brew-cask:
	test -f "build/Claimp-$(VERSION).dmg"
	sed -i '' 's/^  version ".*"/  version "$(VERSION)"/' "$(TAP_DIR)/Casks/claimp.rb"
	sed -i '' "s/^  sha256 \".*\"/  sha256 \"$$(shasum -a 256 build/Claimp-$(VERSION).dmg | cut -d' ' -f1)\"/" "$(TAP_DIR)/Casks/claimp.rb"
	cd "$(TAP_DIR)" && git add -A && git -c user.name=smixs -c user.email=smixs@users.noreply.github.com commit -m "Claimp $(VERSION)" && git push
