.PHONY: build test app run clean dist notarize verify release

# Версия берётся из version.env (тот же источник, что и у build-app.sh).
VERSION = $(shell sed -n 's/^MARKETING_VERSION=//p' version.env)
APP_BUNDLE = build/Claimp.app
ZIP = build/Claimp-$(VERSION).zip
DMG = build/Claimp-$(VERSION).dmg

# Дистрибутивная подпись: Developer ID + hardened runtime + доверенный таймстамп -
# без этого нотаризация не принимает. Локальная сборка (`make app`) подписывается
# ad-hoc, идентификатор ей не нужен.
DIST_SIGN_ID = Developer ID Application: Timurkhuja Latipov (WW2ZW8XUX3)
DIST_SIGN_FLAGS = --options runtime --timestamp
# Профиль нотаризации в Keychain (создан один раз:
#   xcrun notarytool store-credentials sezish-notary \
#     --apple-id <apple-id> --team-id WW2ZW8XUX3 --password <app-specific-password>)
NOTARY_PROFILE ?= sezish-notary

build:
	swift build

test:
	swift test

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

# Проверки готового дистрибутива: подпись, тикет, вердикт Gatekeeper.
verify:
	codesign -vvv --deep --strict "$(APP_BUNDLE)"
	codesign -dv --verbose=4 "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"
	xcrun stapler validate "$(DMG)"
	spctl -a -vv -t install "$(DMG)"
	spctl -a -vv "$(APP_BUNDLE)"

release:
	$(MAKE) dist
	$(MAKE) notarize
	$(MAKE) verify
