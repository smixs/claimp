# PLAN: внедрение DJPlayer v1

Дата: 2026-09-15 10:06. Спека: `SPEC.md`. Решения владельца: `DECISIONS.md`.
Правила для всех задач: работа в своём worktree `.worktrees/<id>` от ветки `master` (remote нет, пушить
некуда - сдача = ветка + SHA локально), субагентов не запускать, за периметр файлов не выходить,
`Package.swift` не трогать (его правит только скелетчик), перед сдачей rebase на `master` и прогон
`swift build && swift test`, отчёт тремя строками: SHA, ветка, суть.

Оценки - чистое время исполнителя, не календарь. Волны W1 идут параллельно.

---

## W0. Скелет (идёт)

- [x] **T0 - скелет пакета** · исполнитель: скелетчик · зависимости: нет
  - Периметр: `Package.swift`, `Sources/{Core,Playback,Waveform,App}/*`, `Tests/*`, `scripts/build-app.sh`, `scripts/run.sh`
  - Из клонов: шаблон `~/.claude/skills/macos-spm-app-packaging/assets/templates/package_app.sh`; блок
    `CFBundleDocumentTypes` с `public.folder` - `aural-player/Info.plist:382-393`
  - Сдача: `swift build` и `swift test` зелёные, `scripts/build-app.sh` даёт запускаемый `build/DJPlayer.app`
  - Оценка: 1.5 ч (сделано)

- [x] **T0b - тестовая оснастка** · исполнитель: скелетчик · зависимости: T0
  - Периметр: `Package.swift` (только блок dependencies и testTarget), `version.env`, `Tests/Fixtures/README.md`
  - Что делаем: добавить `.package(url: "https://github.com/x-sheep/swift-property-based", from: "2.0.0")`
    и `.product(name: "PropertyBased", package: "swift-property-based")` во все три тест-таргета;
    `version.env` с `MARKETING_VERSION=0.1.0`, `BUILD_NUMBER=1`; скопировать тестовые файлы с
    контролируемыми тегами из рабочих файлов ресёрча (в публичное дерево не входят; `id3v23.mp3`, `id3v24.mp3`, `tagged.flac`, `tagged.m4a`,
    `tone.wav`, `tone.aiff`) в `Tests/Fixtures/` и описать, что в них лежит
  - Проверено заранее (Fable, 10:03): PropertyBased собирается и проходит на Swift 6.3.3, стенд
    — проба `pbtcheck`
  - Тесты: один смоук-тест `propertyCheck` в `CoreTests`, чтобы зависимость была доказанно рабочей
  - Тест-таргетов остаётся ровно три (`CoreTests`, `PlaybackTests`, `WaveformTests`), `AppTests`
    не заводить: структура пакета зафиксирована, логика App вынесена в Core
  - Сдача: `swift test` зелёный, ни один исполнитель W1 больше не обязан трогать `Package.swift`
  - Оценка: 0.5 ч
  - **Блокирует старт W1.**

---

## W1. Параллельная реализация (четыре исполнителя, четыре worktree)

- [x] **T1 - Core: модель, сканер, год, база** · исполнитель: DeepSeek V4.1 Flash (pi) · зависимости: T0b
  - Спека: T1-core
  - Периметр: `Sources/Core/*`, `Tests/CoreTests/*`
  - Из клонов: арбитраж длительности VBR - `Petrichor/Petrichor/Core/Metadata/MetadataMapping.swift:55-83`;
    год регуляркой - там же `:14-27`; поля тегов и свойств -
    `SFBAudioEngine/Sources/CSFBAudioEngine/include/SFBAudioEngine/SFBAudioMetadata.h:129-282`,
    `SFBAudioProperties.h:44-62`; схема и индексы SQLite - `Petrichor/.../DatabaseMigration.swift:236-256`
  - Дополнительно в Core (у App тест-таргета нет, вся проверяемая без окна логика живёт здесь):
    `TrackFilter`, `TrackSort`, `PlaylistSummary`
  - Тесты: год из четырёх форматов тега (фикстуры) · PBT `YearParser` · PBT фильтра поиска ·
    сортировка по длительности и по году с `nil` в конце · текст статусной строки ·
    скан папки: порядок по имени, битый файл пропущен · `PlayedStore`: set/is, переживает переоткрытие базы,
    `savePlaylist`/`loadPlaylist` roundtrip
  - Сдача: `swift test --filter CoreTests` зелёный, скан папки из 50 файлов < 1 с (число в отчёте)
  - Оценка: 5 ч

- [x] **T2 - Playback: движок и системная интеграция** · исполнитель: DeepSeek V4.1 Flash (вторая панель) или Opus · зависимости: T0b
  - Спека: T2-playback
  - Периметр: `Sources/Playback/*`, `Tests/PlaybackTests/*`
  - Из клонов: API плеера - `SFBAudioEngine/.../SFBAudioPlayer.h:75-257,338-395`,
    `SFBAudioEngine/Sources/SFBAudioEngine/SFBPlaybackPosition.swift:29-45`;
    медиаклавиши и Now Playing - `bocan-music/Modules/Playback/Sources/Playback/NowPlaying/RemoteCommands.swift`,
    `NowPlayingCentre.swift` (Apache-2.0, NOTICE обязателен)
  - Тесты: `seek(fraction:)` клампит вход · загрузка несуществующего файла даёт `cannotOpen`, а не крэш ·
    `PlaybackPosition.fraction` при `total <= 0` даёт 0 · `NowPlayingBridge.register()` идемпотентен
  - Сдача: `swift test --filter PlaybackTests` зелёный; ручная проба в `swift run` (или мини-харнесс):
    файл играет, `seek` слышен, `onEndOfTrack` приходит
  - Оценка: 5 ч

- [x] **T3 - Waveform: декодер, анализ, кэш** · исполнитель: Opus 5 (свой worktree, периметр жёсткий) · зависимости: T0b
  - Спека: T3-waveform
  - Периметр: `Sources/Waveform/{WaveformData,WaveformAnalyzer,WaveformCache,PCMReader}.swift`, `Tests/WaveformTests/*`
  - Из клонов: потоковый декодер и vDSP-даунсемплинг -
    `aural-player/Source/UI/Waveform/RenderOperation/Decoders/AVFWaveformDecoder.swift:52-80`,
    `WaveformDecoderProtocol.swift:15` (чанк 44100*10), `WaveformRenderOperation+Analysis.swift:40-110,240-285`;
    альтернативный путь `AVAssetReader` с `alwaysCopiesSampleData = false` -
    `WaveformKit/Sources/WaveformKit/Audio/AudioDecoder.swift:38-60`;
    ключ кэша - `WaveformKit/.../WaveformCache.swift:26-33`; 3840 колонок на трек -
    `mixxx/src/analyzer/analyzerwaveform.cpp:61-72` (алгоритм, не код)
  - Отдельный первый шаг: замер `AVAudioFile.read(into:)` против `AVAssetReader` на настоящем
    60-минутном MP3 и на FLAC, цифры в отчёт, выбор обоснован замером (риск №2 из `research/INDEX.md`)
  - Тесты: PBT roundtrip кодека кэша · битый кэш даёт `badCache` · анализ тона 5 с: ровно 3840 колонок,
    значения в 0…1, тишина даёт нули · отмена задачи прекращает чтение
  - Сдача: `swift test --filter WaveformTests` зелёный; замер: 60-минутный MP3 < 3 с, повтор из кэша < 100 мс
  - Оценка: 7 ч

- [x] **T4 - App: окно, таблица, drag-out, drop, поиск** · исполнитель: Muse Spark 1.3 **contributor** (проверить модель в статус-строке pi ДО первого промпта) · зависимости: T0b
  - Спека: T4-app-ui
  - Периметр: `Sources/App/*` (кроме склейки с движком и волной - это T5/T6)
  - Из клонов: `pasteboardWriterForRow` с `.fileURL` -
    `bocan-music/Modules/UI/Sources/UI/Browse/TrackTableHelpers.swift:230-245`,
    `TrackTable.swift:130-134`; ячейка-чекбокс - `TrackTableHelpers.swift:49-89`;
    спеки колонок - `TrackTable+ColSpecs.swift:5-60`; высота строки -
    `TrackTableCoordinator.swift:163-174`; сортировка по заголовку - `TrackTableHelpers.swift:221-228`;
    приём drop - `aural-player/Source/UI/Player/DragDroppablePlayerView.swift:18-52`;
    своё выделение строки - `aural-player/Source/UI/Playlist/AuralPlaylistViews.swift:15-45`;
    Dock - `bocan-music/App/BocanApp.swift:113-120`
  - Тестов нет по построению: тест-таргета у App нет (структура зафиксирована), вся проверяемая без
    окна логика - в Core (T1). Вместо тестов - восемь ручных проверок со скриншотами (drag в Finder,
    мультидраг, шесть сортировок, поиск, лампочка, Delete, дроп папки без аудио, минимальная ширина)
  - Сдача: `swift test` зелёный; `scripts/run.sh` показывает **компактное окно 500×760 pt** (минимум
    420×600) по макету `SPEC.md §4.1` с фейковыми треками, все шесть колонок читаемы на минимальной
    ширине; drag строки в Finder даёт файл (живая проверка руками, скриншот в evidence рядом с
    панелью терминала для сверки с `research/owner-size-reference.png`)
  - Оценка: 8 ч

---

## W2. Интеграция

- [x] **T5 - склейка App ↔ Playback ↔ Core** · исполнитель: интеграция (Fable или DeepSeek) · зависимости: T1, T2, T4
  - Периметр: `Sources/App/*` + ровно один новый файл `Sources/Core/PlaylistNavigator.swift`
    и тесты к нему в `Tests/CoreTests/`
  - Что: реальный сканер вместо фейковых треков; double-click играет; конец трека - следующий по порядку
    строк; лампочка пишет в `PlayedStore`; порядок и текущий трек сохраняются и восстанавливаются;
    громкость в `UserDefaults`; шапка (обложка, три строки, транспорт) живёт от состояния движка
  - `PlaylistNavigator.next(after:in:)` / `previous(after:in:)` - чистые функции в Core, чтобы шов
    «конец трека - следующий» был покрыт тестом, а не только руками
  - Тесты (в `CoreTests`): 1 happy + 1 failure на шов «следующий трек» (последний трек даёт `nil`) и
    на «восстановление плейлиста при отсутствующем на диске файле» (такой URL выбрасывается)
  - Сдача: пункты 2, 3, 4, 10, 11, 12 живого смока из `SPEC.md §8` проходят руками
  - Оценка: 5 ч

- [x] **T6 - WaveformView и её привязка** · исполнитель: Opus 5 · зависимости: T3, T5
  - Периметр: `Sources/Waveform/WaveformView.swift`, точка встраивания в `Sources/App/`
  - Из клонов: слои и маска прогресса - `aural-player/Source/UI/Waveform/View/WaveformView.swift:135-148,222-330`;
    клик-перемотка - `WaveformView+GestureHandling.swift:44,86-101`
  - Что: рисование 3840 колонок ресемплом под текущую ширину (ресайз окна **не** вызывает переанализ),
    курсор, клик и драг = `onSeek`, подписи времени слева и справа, палитра `.amplitude`
  - Тесты: ресемпл 3840 → произвольная ширина не выходит за границы массива (PBT-подобный кейс с
    краями 1 px и 5000 px) · `progress` вне 0…1 клампится
  - Сдача: пункты 5, 6, 7 живого смока проходят, время построения записано
  - Оценка: 5 ч

- [x] **T7 - упаковка, Dock, медиаклавиши живьём** · исполнитель: интеграция · зависимости: T5, T6
  - Периметр: `scripts/build-app.sh` (только Info.plist-блок при необходимости), `Sources/App/AppDelegate.swift`
  - Что: `application(_:openFiles:)`, иконка-заглушка не нужна, проверка что `.app` открывается из Finder,
    медиаклавиши доходят при неактивном окне
  - Сдача: пункты 1, 3, 13 живого смока
  - Оценка: 2 ч

---

## W2b. После v1 (не входит в v1, отдельная волна)

- [x] **T3b - цвет волны по частотам (RGB по Mixxx)** · исполнитель: Opus 5 · зависимости: T6 сдан, v1 у владельца
  - Периметр: `Sources/Waveform/{BandSplitter,WaveformAnalyzer,WaveformView}.swift`, `Tests/WaveformTests/*`
  - Из клонов (алгоритм, не код, GPL не копируем): три фильтра на границах 600 Гц и 4 кГц -
    `mixxx/src/analyzer/analyzerwaveform.cpp:18-20,175-190`; максимум по колонке на полосу - `:240-265`;
    смесь и нормировка цвета - `mixxx/src/waveform/renderers/allshader/waveformrendererrgb.cpp:182-213`.
    Реализация на `vDSP_biquad`/`vDSP_deq22`, без FFT
  - Что меняется в интерфейсах: **ничего**, только заполнение `Column.low/mid/high` и
    `WaveformView.palette = .rgb`, прогресс - яркостью, версия кэша `formatVersion = 2`
  - Сдача: волна цветная как в Serato, старые кэши инвалидируются по версии, время анализа выросло не более
    чем в 1.5 раза (замер до/после)
  - Оценка: 6 ч

---

## W3. Приёмка

- [ ] **T8 - слепой QA** · исполнитель: Opus 5, свежий контекст, effort high · зависимости: T7
  - Даём: `SPEC.md`, диффы веток, собранный `.app`. Не даём: рассуждения билдеров
  - Задача: проверить каждый пункт `SPEC.md §6` и `§8` руками и по коду; каждое утверждение с `file:line`
    или скриншотом; «не установлено» - допустимый ответ; субагентов не запускать
  - Выход: отчёт слепого QA со списком ACCEPT/REJECT по пунктам
  - Оценка: 3 ч

- [ ] **T9 - гейт** · исполнитель: Fable · зависимости: T8
  - Чек-лист ниже; мутант выбирает критик (не билдер)
  - Оценка: 2 ч

- [ ] **T10 - живой смок владельцем** · исполнитель: владелец · зависимости: T9
  - Чек-лист ниже, на настоящей папке с миксами
  - Оценка: 0.5 ч

**Итого до v1:** T0b…T7 ≈ 38 ч исполнителей, из них W1 (26 ч) идёт в четыре руки параллельно.

---

## Гейт-чеклист (T9, каждая строка - отдельная команда, вывод в файл, пайпов на проверочных командах нет)

```
[ ] 1. Чистый worktree .worktrees/gate от master, без .env и без build/
[ ] 2. swift build 2>&1 | tee 01-build.log ; проверить код выхода отдельно
[ ] 3. swift build -Xswiftc -warnings-as-errors  (предупреждений Swift 6 быть не должно)
[ ] 4. swift test                                (три тест-таргета, все зелёные)
[ ] 5. swift test --enable-code-coverage + llvm-cov export: покрытие изменённых строк >= 80 %
[ ] 6. CRAP по изменённым функциям: сложность <= 10, ни одной функции с CRAP > 30, среднее < 5
[ ] 7. Циклы импортов: grep по Sources/ - в Core нет import Playback|Waveform|App; в Playback/Waveform нет import App
[ ] 8. Зависимости пакета: ровно SFBAudioEngine, GRDB.swift + PropertyBased только в тест-таргетах
[ ] 9. Одна мутация на границе потребителя (выбирает критик), якорь - точная строка, sed без 0,/re/,
       путь теста проверен ls до запуска; красный тест назван поимённо; откат копией файла,
       git diff --stat после отката пустой
[ ] 10. git diff --stat: ни один исполнитель не вышел за свой периметр файлов
[ ] 11. bash scripts/build-app.sh: build/DJPlayer.app собран, codesign -dv проходит, open запускает окно
[ ] 12. Лицензии: NOTICE с Apache-2.0 (bocan-music) и MIT (aural-player, SFBAudioEngine, GRDB,
        PropertyBased, WaveformKit) лежит в репо; GPL-кода Mixxx/Cog в дереве нет (grep по характерным
        именам функций)
[ ] 13. Отчёт QA (T8) прочитан, все REJECT закрыты или явно приняты владельцем
```

Известный флейк перегонять в одиночку только если красный ровно один и это он. Зелёная мутация = стоп
и дифференциальная проба, а не «добавь тест».

---

## Чеклист живого смока для владельца (T10)

Пятнадцать пунктов `SPEC.md §8`, короткой формулировкой - что нажать и что должно случиться:

1. Запустить `DJPlayer.app` двойным кликом - окно открылось, тёмное.
2. Кинуть папку с миксами на окно - список заполнился меньше чем за пару секунд, год и длительность на месте.
3. Кинуть ту же папку на иконку в Dock - то же самое.
4. Двойной клик по треку - играет, сверху обложка и название.
5. Волна часового трека появилась за пару секунд; открыть трек второй раз - волна мгновенно.
6. Клик в середину волны - перемотка туда.
7. Курсор на волне едет ровно, сыгранное закрашено.
8. Перетащить строку в Finder - появился файл; в Ableton и Bitwig - трек на дорожке; в Telegram - вложение.
9. Клик по «Длительность», «Год», «Название», «Исполнитель» - сортирует, второй клик - наоборот.
10. Две буквы в поиск - список отфильтровался; очистить - вернулся.
11. Зажечь пару лампочек, выйти ⌘Q, запустить снова - лампочки, порядок и текущий трек те же.
12. Дослушать трек до конца - сам включился следующий.
13. Нажать F8 при неактивном окне - пауза; в Пункте управления видно, что играет.
14. Delete на строке - строка исчезла, файл в Finder на месте.
15. Погонять десяток часовых треков - память не растёт, на паузе процессор спит.

## Добавлено 15.09 по решениям владельца (после v1-скелета)
- [x] T11 - волна RMS + спектр (влито 11006d0)
- [x] T12 - плоская тема Claimp, логотип, фейдер, обрезка текста (влито 7319efb)
- [x] T13a - drag файла с волны, модуль Waveform (влито 43f1cb9)
- [x] T13b - drag за обложку/волну в App, переименование Claimp, логотип без обрезки, хвосты (последний трек, onError) · Opus
- [x] T8 - слепой QA по SPEC §6/§8 на build/Claimp.app · Opus свежий контекст
- [x] T9 - гейт gate-v1.sh с мутантом критика (WaveformData.decoded:63) · Fable
- [ ] T10 - живой смок владельцем: drag в Ableton/Bitwig/Finder, медиаклавиши, папка на Dock
- [x] T15 - фейдер капсулой, логарифмическая громкость, обложка квадрат, логотип по оси (влито 032b5f2)
- [x] QA-FIXES - звучащий трек в шапке, чистка drag волны, осевая линия, fail fast (влито dd796c2)
- [x] Публикация: https://github.com/smixs/claimp
- [x] T16 - релиз 0.1.0/0.1.1: Developer ID MAJENTO, нотаризация, DMG, GitHub Releases
- [x] T17 - сортировка по заголовкам (@objc), колонки kbps/BPM/Key, плотный плейлист (влито c2c02c6)
- [x] T18 - анализ BPM/тональности через MusicUnderstanding (macOS 27), кэш в SQLite v2, колонки заполняются (влито 9ba23fd)
- [ ] T19 - окно настроек ⌘, (колонки, шрифт, анализ, палитра) · Opus
- [ ] Релиз 0.2.0: make release (Majento), export-public, тег v0.2.0, GitHub Release с DMG/zip
