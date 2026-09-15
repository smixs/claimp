# 01. Готовые open-source нативные macOS-плееры: что можно форкнуть

Дата: 2026-09-15. Источники: shallow-клоны upstream-репозиториев в `clones/` (в этот репозиторий не входят), GitHub REST API (`/repos/<owner>/<repo>`), WebSearch/WebFetch.
Все `path:line` даны относительно корня соответствующего клона.

## Главный вывод в одну строку

Плеера, который закрывает ВЕСЬ бриф, в природе нет - ни открытого, ни закрытого (гипотеза владельца подтверждена
для комбинации требований). Но нет и нужды писать с нуля: **цветной waveform всего трека уже написан в Aural Player
(MIT, 1764 строки Swift), а drag-out реального файла в Finder/DAW - в Cog и Bòcan (по ~20 строк).**
Эти две вещи в одном продукте не встретились ни разу.

---

## 1. Таблица кандидатов

| Репо | Язык | Лицензия | Последний коммит | Stars / open issues | Размер | Статус |
|---|---|---|---|---|---|---|
| [kartik-venugopal/aural-player](https://github.com/kartik-venugopal/aural-player) | Swift (AppKit) | MIT | 2025-06-22 | 1074 / 13 | 995 .swift, 105 531 строк | **АРХИВИРОВАН** |
| [losnoco/Cog](https://github.com/losnoco/Cog) | Obj-C / C / C++ | **GPL-2.0** | 2026-09-09 | 1022 / 85 | 48 .swift + 204 .m + 34 .mm (61 419 строк) + 1610 .c/.cpp | Активен |
| [kushalpandya/Petrichor](https://github.com/kushalpandya/Petrichor) | Swift (SwiftUI + AppKit) | MIT | 2026-09-15 | 1676 / 17 | 203 .swift, 54 855 строк | Активен |
| [bocan/bocan-music](https://github.com/bocan/bocan-music) | Swift 6 (SwiftUI + AppKit) | Apache-2.0 | 2026-09-15 | 44 / 12 | 1215 .swift, 186 174 строки | Активен |
| [samzong/MacMusicPlayer](https://github.com/samzong/MacMusicPlayer) | Swift | MIT | 2026-08-10 | 92 | 19 .swift, 5813 строк | Активен, но это меню-бар |
| [JendaT/fb2k-components-mac-suite](https://github.com/JendaT/fb2k-components-mac-suite) | Obj-C++ | MIT | 2026-08-23 | 84 | плагины к foobar2000 | Активен, не самостоятельный плеер |
| [johnnyshankman/hihat](https://github.com/johnnyshankman/hihat) | TypeScript | MIT | 2026-09-13 | 25 | - | **Электрон - вне брифа** |
| [deseven/iCanHazMusic](https://github.com/deseven/iCanHazMusic) | PureBasic | Unlicense | 2025-10-25 | 30 | - | Не Swift - вне брифа |
| [dun198/SwiftAudioPlayer](https://github.com/dun198/SwiftAudioPlayer) | Swift | MIT | 2020-11-02 | 44 | - | Мёртв 6 лет, WIP |

Данные stars/issues/pushed/archived/license: GitHub API `https://api.github.com/repos/<owner>/<repo>`, запрошено 2026-09-15.
«Musique» как macOS-плеер на Swift/AppKit по запросу не найден - **не установлено**, что такой проект существует.

## 2. Покрытие пунктов брифа по каждому кандидату

| Пункт брифа | Aural Player | Cog | Petrichor | Bòcan |
|---|---|---|---|---|
| Цветной waveform ВСЕГО трека | **ДА** | нет | нет | нет |
| Плейлист: длительность | ДА | ДА | ДА | ДА |
| Плейлист: год релиза | ДА | ДА | не проверено | ДА |
| Сортировка по длительности | ДА | не проверено | не проверено | ДА |
| Флаг «проиграно» / play count | ДА (счётчик) | ДА (счётчик) | не проверено | ДА (счётчик) |
| **Drag-out файла в другую программу** | **НЕТ** | **ДА** | **НЕТ** | **ДА** |
| Drop папки на плеер | ДА | ДА | частично | ДА |
| Движок | AVAudioEngine + FFmpeg | своя цепочка + 30+ декодеров | CrescendoKit | AVAudioEngine + FFmpeg |
| Чтение тегов | AVFoundation + FFmpeg (свои парсеры) | libid3tag и др. | не установлено | **TagLib** (Obj-C++ bridge) |
| Сборка | Xcode-проект, FFmpeg вшит .xcframework | Xcode + огромный ThirdParty | Xcode + SPM (GRDB, Sparkle) | XcodeGen, macOS 15, Swift 6 |
| Тесты | нет | не установлено | не установлено | 425 тест-файлов |

---

## 3. Разбор по коду

### 3.1 Aural Player - единственный с настоящим waveform

**Waveform - точно то, что на скриншоте AIMP.**
- Модуль целиком: `Source/UI/Waveform/` - 13 файлов, **1764 строки Swift**.
- Основан на FDWaveformView, сказано прямо в шапке:
  `Source/UI/Waveform/View/WaveformView.swift:25` - `/// This is based on ``FDWaveformView``.`
- **Весь трек, не окно**: декодер берёт длину файла целиком -
  `Source/UI/Waveform/RenderOperation/Decoders/AVFWaveformDecoder.swift:52` - `self.totalSamples = audioFile.length`,
  и даунсемплит до ширины вьюхи: `WaveformRenderOperation.swift:63` - `self.targetSamples = AVAudioFrameCount(imageSize.width)`.
- **Два цвета, как оранжевый/серый у AIMP**: рисуются два `CAShapeLayer`, верхний обрезан маской по прогрессу:
  - `WaveformView.swift:238` - `baseLayer.strokeColor = systemColorScheme.inactiveControlColor.cgColor`
  - `WaveformView.swift:320` - `progressLayer.strokeColor = systemColorScheme.activeControlColor.cgColor`
  - `WaveformView.swift:222` - маска двигается: `maskLayer.frame = CGRect(x: frameX, y: 0, width: max(0, (imgWidth * progress) - frameX), ...)`
  - цвета живые, меняются по теме: `WaveformView.swift:351-358` (`activeControlColorChanged`, `inactiveControlColorChanged`).
- Два декодера - AVFoundation и FFmpeg: `Decoders/AVFWaveformDecoder.swift`, `Decoders/FFmpegWaveformDecoder.swift`.
- Есть кэш посчитанных сэмплов: `Source/UI/Waveform/Caching/WaveformCacheEntry.swift`, `WaveformView+Caching.swift`.
- Есть клик/жест для перемотки по waveform: `Source/UI/Waveform/View/WaveformView+GestureHandling.swift`.

**Плейлист.** Поля сортировки перечислены в `Source/Core/TrackList/Sort/SortField.swift:14-27`:
`name, title, fileName, duration, artist, album, genre, trackNumber, discNumberAndTrackNumber, fileLastModifiedTime, year, playCount, format`.
Колонки таблицы: `Source/UI/PlayQueue/TabularView/PlayQueueTabularViewController.swift:102` -
`[.cid_title, .cid_fileName, .cid_artist, .cid_album, .cid_genre, .cid_trackNum, .cid_discNum, .cid_year, .cid_format, .cid_playCount, .cid_lastPlayed]`;
идентификаторы, включая `cid_duration`, в `Source/UI/Playlist/AuralPlaylistViews.swift:74-84`.
Play count берётся из истории: `Source/UI/PlayQueue/TabularView/PlayQueueTabularViewController+TableViewDelegate.swift:110`.

**Drop папки - есть.** `Source/Core/TrackIO/TrackInitializer.swift:68` - `} else if resolvedURL.isDirectory {`;
фильтр принимаемого: `Source/Core/Utils/Extensions/URLExtensions.swift:70` - `if url.isSupportedFile || url.isDirectory || url.isAliasOrSymLink {`.
Окно плеера принимает файлы: `Source/UI/Player/DragDroppablePlayerView.swift:18` - `registerForDraggedTypes([.fileURL])`.

**Drag-out файла - НЕТ. Это главный пробел.** Таблица кладёт в pasteboard только внутренний архив, не `fileURL`:
- `Source/UI/Utils/TableView/TableViewController/TrackListTableViewController+DataSource.swift:21-25` -
  `TableDragDropContext.setIndicesAndData(rowIndexes, trackList[rowIndexes], from: tableView, pasteboard: pasteboard)`
- `Source/UI/Utils/TableView/TableDragDropContext.swift:29-37` - в pasteboard идёт только `pasteboard.sourceIndexes = indices`,
  сами треки хранятся в статических переменных процесса (`Self.data = data`), то есть наружу не видны.
- `Source/UI/Utils/Extensions/TableViewDragDropExtensions.swift:38-43` - пишется `NSPasteboardItem` с типом `.data` (`kUTTypeData`), не `.fileURL`.
- Ни `NSFilePromiseProvider`, ни `filePromise` во всём репозитории не встречаются (grep по `Source/` - 0 совпадений).
- Тип `.fileURL` объявлен только для приёма извне: `TableViewDragDropExtensions.swift:60-61` -
  `// Enables drag/drop adding of tracks into the playlist from Finder`.

**Сборка.** Xcode-проект `Aural.xcodeproj`, `SWIFT_VERSION = 5.0`, `MACOSX_DEPLOYMENT_TARGET = 11.0` (для основного таргета;
у части таргетов 10.12). FFmpeg вшит бинарными xcframework'ами прямо в репо (`Frameworks/libavcodec.xcframework` 2,5 МБ,
`libavformat` 1,0 МБ, `libavutil` 2,3 МБ, `libswresample` 324 КБ, плюс `libcue`, `libebur128`) - внешних зависимостей и
пакетных менеджеров нет, `git clone` + Xcode. Тестов в репозитории нет (поиск `*test*` по коду - пусто).

**Что мешает.** Репозиторий **архивирован** (`archived: true`, GitHub API; последний push 2025-06-21).
README, `README.md:5-9`: «Project archived - It's time to say goodbye! I will no longer be actively working on this project,
so it's time to say thank you and goodbye! This means no bug fixes, no new features, no new releases.»
Преемника автор не называет - **не установлено**. Лицензия MIT, то есть форк и коммерческое использование разрешены.
105 тысяч строк - это мультиоконный комбайн (4 режима UI, эффекты, Last.fm, MusicBrainz, библиотека, лирика,
цветовые схемы, EBU R128) - для минималистичного DJ-плеера это на порядок больше нужного.

### 3.2 Cog - drag-out есть, waveform нет, лицензия GPL

- **Drag-out работает**: `Playlist/PlaylistController.m:817` - `[item setData:[song.url dataRepresentation] forType:NSPasteboardTypeFileURL];`
  и разрешён наружу: `Playlist/PlaylistController.m:159` - `[self.tableView setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];`
  Это ровно тот приём, который нужен для перетаскивания файла в Finder/DAW/Telegram.
- Приём файлов и папок: `Playlist/PlaylistView.m:427`, `PlaylistController.m:834` (`CogUrlsPboardType, NSPasteboardTypeFileURL, iTunesDropType`).
- Год и play count в модели: `Playlist/PlaylistEntry.h:103` (`int32_t year`), `Playlist/PlaylistEntry.h:90` (`playCount`).
- **Waveform всего трека нет.** Все 30 совпадений по слову «waveform» - внутренности кодеков и чип-эмуляторов
  (`Frameworks/GME/gme/Ay_Apu.cpp`, `Frameworks/vgmstream/...`, `Plugins/MIDI/.../i_oplmusic.cpp`), а не UI.
  Визуализация в `Visualization/` - спектр и осциллоскоп (`SpectrumViewCG.m`, `SpectrumViewSK.m`, `SCView.m`), то есть реалтайм, не обзор трека.
- **Лицензия GPL-2.0** (`COPYING`, строка 1: «GNU GENERAL PUBLIC LICENSE Version 2, June 1991»). Форк обязан остаться GPL -
  для личного инструмента это не проблема, для закрытой продажи - проблема.
- Objective-C/C/C++ с гигантским `ThirdParty/` и `Frameworks/` (30+ эмуляторов и декодеров: vgmstream, GME, OpenMPT, mGBA, munt,
  libsidplayfp, ffmpeg, BASS, rubberband...). Это не «минималистичный и быстрый», это архив форматов ретро-консолей.

### 3.3 Petrichor - самый живой, но пустой по нашим пунктам

- MIT, 1676 звёзд, коммиты каждый день, 203 файла Swift / 54 855 строк, macOS 14.0, SwiftUI + AppKit.
- Зависимости по SPM (`Petrichor.xcodeproj/project.pbxproj:585,593,601`): `CrescendoKit` (свой аудио-движок автора), `GRDB.swift`, `Sparkle`.
- **Waveform отсутствует полностью**: grep `waveform` по всему репозиторию без `.git` - 0 совпадений.
- **Drag-out файла отсутствует**: перетаскивание передаёт только UUID строкой -
  `Views/Main/PlayQueueView.swift:180-182` - `.onDrag { ... return NSItemProvider(object: track.id.uuidString as NSString) }`,
  то же в `Views/Components/Sidebar/SidebarListView.swift:121-123`. `NSFilePromiseProvider` в репо нет.
- `.fileURL` используется только на приём картинки обложки: `Views/Components/Widgets/ArtworkImageWell.swift:59`.
- Drop папки на окно плеера в коде не найден (`onDrop` есть только в сайдбаре, очереди и обложке) - **не установлено**, что поддерживается.

### 3.4 Bòcan Music - эталон того, как делается drag-out

- Apache-2.0 (`LICENSE`, 177 строк, «Copyright 2026 Chris Funderburg»; GitHub API отдаёт `NOASSERTION` - расхождение с самим файлом).
- Swift 6 со строгой конкурентностью, XcodeGen, macOS 15.0, arm64: `project.yml:7-8,25-28`. 1215 файлов Swift / 186 174 строки, 425 тест-файлов.
- **Drag-out реального файла - готовый рецепт на 20 строк**:
  `Modules/UI/Sources/UI/Browse/TrackTableHelpers.swift:230-245`:
  ```
  @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
      guard let id = itemIdentifier(forRow: row) else { return nil }
      let item = NSPasteboardItem()
      // The track-ID string drives intra-table reorder; the file URL lets the
      // same drag drop a real file onto Finder/Desktop or another app (#311).
      item.setString(String(id), forType: .string)
      MainActor.assumeIsolated {
          if let url = self.coordinator?.fileURL(forTrackID: id) {
              item.setString(url.absoluteString, forType: .fileURL)
          }
      }
      return item
  }
  ```
  плюс разрешение тащить наружу: `Modules/UI/Sources/UI/Browse/TrackTable.swift:134` -
  `tableView.setDraggingSourceOperationMask(.copy, forLocal: false)`.
- **Drop папки на окно**: `Modules/UI/Sources/UI/AppRoot/RootView.swift:197-198` - `.onDrop(of: [UTType.fileURL, UTType.folder], ...)`.
- Колонки и сортировка: `Modules/UI/Sources/UI/Browse/TrackTable+Helpers.swift:114-131` - ключи сортировки включают
  `yearText`, `duration`, `playCount`, `rating`, `bitrate`, `fileFormat`, `addedAt`.
- Теги читает **TagLib** через Obj-C++ мост: `Modules/Metadata/Sources/Metadata/TagReader.swift:3` - `import TagLibBridge`,
  `:5` - «Reads tag metadata from local audio files via the TagLib Obj-C++ bridge.»
- Движок: `Modules/AudioEngine/Sources/AudioEngine/` - `AudioEngine.swift`, `Graph/EngineGraph.swift`, `Graph/BufferPump.swift`,
  декодеры `Decoder/AVFoundationDecoder.swift` и `Decoder/FFmpegDecoder.swift`.
- **Waveform всего трека нет.** Есть только реалтайм-осциллоскоп на Metal
  (`Modules/UI/Tests/UITests/MetalOscilloscopeTests.swift`, `docs/design-spec/ADR-023-visualizer-metal-oscilloscope.md`),
  и слово waveform в именах его палитр. Обзора трека нет.
- Что мешает форку целиком: это медиацентр, а не плеер - библиотека на базе БД, подкасты, радио, Subsonic, лирика,
  скробблинг, AcoustID-фингерпринт, редактор тегов, DSP/EQ, 186 тысяч строк. Ставит Homebrew-зависимости (`Brewfile`)
  и требует `Secrets.xcconfig`. Бинарь тащит TagLib (LGPL) и FFmpeg - лицензионные хвосты придётся разбирать отдельно.

### 3.5 Остальные - отсев

- **MacMusicPlayer** (Swift, MIT, 19 файлов / 5813 строк): плеер в строке меню. Waveform нет (grep 0 совпадений),
  drag-out нет, таблицы с колонками нет (`MacMusicPlayer/Views/SimpleSongPickerWindow.swift` - простой пикер).
  Полезен разве что как пример компактного Xcode-проекта.
- **hihat** - TypeScript, то есть Electron. Бриф прямо запрещает.
- **iCanHazMusic** - PureBasic. Не Swift, не форкаем.
- **dun198/SwiftAudioPlayer** - последний push 2020-11-02, статус WIP в самом описании. Мёртв.
- **fb2k-components-mac-suite** (MIT, Obj-C++) - не плеер, а набор плагинов к чужому закрытому хосту foobar2000 v2.6+ для macOS 11+.
  Как база не годится. Как референс алгоритма - годится: waveform-сикбар на vDSP (Accelerate) + Core Graphics + кэш в SQLite по SHA-256.

---

## 4. Проверка гипотезы владельца «для macOS такого плеера нет»

**Вердикт: гипотеза подтверждена для комбинации требований; опровергнута для отдельных функций.**

Цветной waveform всего трека на macOS существует и не один раз:

1. **Aural Player** (open source, MIT) - `Source/UI/Waveform/`, доказательства выше. Но проект архивирован в июне 2025,
   и drag-out файла в нём нет.
2. **foobar2000 v2.6+ для macOS** (плеер бесплатный и закрытый) + сторонний **Waveform Seekbar** из
   `JendaT/fb2k-components-mac-suite` (MIT): по README компонента - «the entire track waveform at a glance»,
   клик по волне = перемотка, режимы стерео/моно, настраиваемые цвета, кэш; требует foobar2000 v2.6+ и macOS 11+.
   То есть ближайший к брифу рабочий набор сегодня - это foobar2000 for Mac с плагином, а не отдельное приложение.

По остальным закрытым/платным (только на вопрос «существует ли уже», без разбора):
- **Swinsian** - на официальном сайте и в FAQ waveform не упоминается; заявлены art grid, column browser, track inspector,
  теги, folder watching. Waveform - **не установлено** (скорее нет).
- **VOX для Mac** - на форуме VOX обсуждается показ waveform в iOS-версии; для macOS подтверждения нет - **не установлено**.
- **Doppler для Mac** - нативный macOS-плеер (не Catalyst), но waveform-сикбар в источниках не упомянут - **не установлено**.
- **AIMP для macOS не существует** - официальных сборок под Mac нет, отсюда и сама задача.

Чего нет ни у кого, ни в открытом, ни в закрытом коде, что я видел:
**связки «цветной waveform всего трека» + «перетаскивание реального файла из плейлиста в Finder/DAW/Telegram»
в одном нативном macOS-приложении.** Ни Aural, ни Cog, ни Petrichor, ни Bòcan, ни foobar2000-с-плагином
(для fb2k drag-out на macOS - **не установлено**) не дают обе функции сразу. Плюс ни один из них не минималистичный:
самый лёгкий полноценный кандидат - Petrichor на 55 тысяч строк, и он как раз без обеих ключевых функций.

---

## 5. Вердикт по каждому кандидату

| Кандидат | Вердикт | Причина |
|---|---|---|
| **Aural Player** | **Берём модули, не форкаем целиком** | Waveform-модуль (`Source/UI/Waveform/`, 1764 строки, MIT) - готовый ответ на главный пункт брифа. Остальные 104 тысячи строк - комбайн, который придётся выкидывать. Архив = чинить баги придётся самим, но MIT это разрешает. |
| **Bòcan Music** | **Берём модуль drag-out (~20 строк)** | `TrackTableHelpers.swift:230-245` + `TrackTable.swift:134` - рабочий рецепт `pasteboardWriterForRow` с `.fileURL`. Apache-2.0 требует сохранить NOTICE. Форк целиком - нет: 186 тысяч строк медиацентра, macOS 15, Homebrew, секреты. |
| **Cog** | **Нет (резерв как второй референс drag-out)** | GPL-2.0 заражает форк; Obj-C; нет waveform; тянет 30+ эмуляторов ретро-форматов. Но `PlaylistController.m:817` - второе независимое подтверждение, как правильно писать `NSPasteboardTypeFileURL`. |
| **Petrichor** | **Нет (резерв как эталон SwiftUI-структуры)** | Нет ни waveform, ни drag-out - то есть оба самых дорогих пункта брифа пришлось бы писать. Ценность: живой MIT-проект 2026 года, аккуратная раскладка `Views/Managers/Models/Core`, пример связки SwiftUI+AppKit и GRDB. |
| **MacMusicPlayer** | **Нет** | Меню-бар без таблицы, waveform и drag-out. |
| **fb2k-components-mac-suite** | **Нет как база, резерв как алгоритм** | Плагин к закрытому хосту. Но подход «vDSP + Core Graphics + SQLite-кэш по SHA-256» стоит сверить со своим, если Aural-вариант окажется медленным. |
| hihat / iCanHazMusic / SwiftAudioPlayer | **Нет** | Electron / не Swift / мёртв. |

---

## 6. Что из найденного закрывает пункты брифа, а что нет

### Закрывается чужим кодом почти без нашего

| Пункт брифа | Чем закрываем | Объём чужого кода |
|---|---|---|
| Крупный цветной waveform всего трека + перемотка кликом | Aural `Source/UI/Waveform/` целиком (view, render-operation, 2 декодера, кэш, жесты) | 1764 строки Swift, MIT |
| Drag-out реального файла в Finder/DAW/Telegram | Bòcan `pasteboardWriterForRow` + `setDraggingSourceOperationMask(.copy, forLocal: false)` (дубль-референс - Cog) | ~20 строк, Apache-2.0 |
| Drop папки на плеер | Aural `TrackInitializer.swift:68` + `URLExtensions.swift:70` + `registerForDraggedTypes([.fileURL])`, либо SwiftUI-вариант Bòcan `RootView.swift:197` | десятки строк |
| Плейлист: длительность, год, теги, сортировка, play count | Aural `Core/TrackList/Sort/SortField.swift` (13 полей, включая `duration`, `year`, `playCount`) + колонки `AuralPlaylistViews.swift:74-84` | сотни строк |
| Чтение тегов MP3 | Aural `Core/TrackIO/` (AVFoundation + FFmpeg-парсеры) - 10 233 строки; либо TagLib-мост из Bòcan | берём частично |
| Воспроизведение | Aural `Core/AudioGraph/` на AVAudioEngine - 6587 строк; либо голый `AVAudioEngine`/`AVAudioPlayerNode` своими 200 строками | на выбор |

### Не закрывается ничем готовым - это наша работа

1. **Галочка «проиграно» как в AIMP.** Ни у кого нет чекбокса на строке; у всех - числовой счётчик воспроизведений
   (Aural `playCount(forTrack:)`, Cog `playCount`, Bòcan `TrackRow.playCount`). Наш код: чекбокс + персист флага. Мелочь.
2. **Сама компоновка окна AIMP** (шапка с обложкой и полным названием сверху, под ней транспорт, под ним широкий waveform,
   под ним плейлист, снизу строка итогов «4 / 00:02:09:34 / 297,90 MB»). Готовой такой раскладки нет ни у кого;
   у Aural waveform живёт в отдельном окне/контейнере (`UI/ModularPlayer/Waveform/WaveformWindow.xib`,
   `UI/UnifiedPlayer/Waveform/UnifiedPlayerWaveformContainer.xib`). Это наша вёрстка.
3. **Минимализм и скорость.** Все живые кандидаты - тяжёлые комбайны (55-186 тысяч строк). Ужать чужой проект до
   «шапка + waveform + плейлист» - работа сопоставимая с написанием оболочки заново поверх взятых модулей.
4. **Склейка waveform-модуля Aural с новой оболочкой.** `WaveformView` завязан на инфраструктуру Aural:
   `colorSchemesManager` (`WaveformView.swift:65-67`), `systemColorScheme` (`:238,320`), `EventMonitor`, протокол `Destroyable`,
   `FFmpegWaveformDecoder` поверх вшитых xcframework'ов. Либо тащим за ним эти куски, либо режем зависимости -
   это реальная, пусть и небольшая, работа по развязке.

### Практический вывод

Форкать целиком не надо ничего. Схема: **новый минимальный Xcode-проект на Swift/AppKit → в него
waveform-модуль Aural (MIT, 1764 строки) + рецепт drag-out из Bòcan (~20 строк) + при желании TrackIO/AudioGraph Aural
или голый AVAudioEngine.** Своего кода - оболочка AIMP-раскладки, таблица плейлиста и чекбокс «проиграно».
Лицензионно чисто: MIT + Apache-2.0, GPL-кода (Cog) не берём.

---

## 7. Открытые вопросы владельцу

1. 🔴 Плеер будет только для себя или пойдёт на продажу/в открытый доступ? От этого зависит, можно ли вообще
   смотреть в сторону Cog (GPL-2.0) и как оформлять NOTICE для кода из Bòcan (Apache-2.0).
2. 🔴 Минимальная версия macOS. Aural собирается от 11.0, Bòcan требует 15.0, Petrichor 14.0. Если берём код Bòcan
   как есть (Swift 6, strict concurrency), планка уезжает вверх.
3. 🔴 Нужен ли FFmpeg. С ним waveform и воспроизведение работают для всех форматов (как у Aural), без него -
   только то, что умеет AVFoundation (MP3/AAC/ALAC/WAV/AIFF/FLAC). Если в работе только MP3 - FFmpeg можно не тащить,
   проект станет заметно легче.
4. Сейчас доступный ближайший к брифу инструмент - foobar2000 v2.6+ для macOS с MIT-плагином Waveform Seekbar
   (полный waveform трека, клик-перемотка). Посмотреть его перед тем, как строить своё, или задача не про «чем пользоваться»,
   а про «сделать своё»?
