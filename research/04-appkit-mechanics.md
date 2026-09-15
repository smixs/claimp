# 04. Механика окна и плейлиста на macOS: что берём готовым

Дата: 2026-09-15 09:38. Задача №4 брифа. Источники: код в `clones/*` (shallow clone upstream-репозиториев; в этот репозиторий не входят),
доки Apple (developer.apple.com), два внешних технических разбора помечены как вторичные.
Приложение не строилось, живых прогонов drag-and-drop не было - см. раздел «Что не установлено».

---

## 1. DRAG-OUT реального файла из строки плейлиста

### Вердикт: `NSTableViewDataSource.tableView(_:pasteboardWriterForRow:)` + `NSPasteboardItem` с типом `.fileURL`

Это то, чем реально сделан drag-out в двух живых плеерах (Cog, Bòcan). Промисы (`NSFilePromiseProvider`)
здесь не нужны, потому что файл уже лежит на диске.

**Опора в доках Apple:**

- `NSFilePromiseProvider` - «A file promise is a possible future file of a specified type. When you're working
  with drag and drop, use promises to indicate intent for future action.»
  (https://developer.apple.com/documentation/appkit/nsfilepromiseprovider, раздел Overview).
- Архивный гайд Dragging Files: «In some cases, you may want to drag a file before it actually exists within the
  file system. You may have a new document that hasn't been saved, yet, or perhaps the file exists on a remote
  system, such as a web server, to which the dragging destination may not have access.»
  (https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Tasks/DraggingFiles.html).
  То есть промис - для несуществующего или удалённого файла. У нас MP3 на диске → промис не нужен.
- Тот же гайд про одиночный URL: «This holds a single NSURL object… you cannot store more than one URL on the
  pasteboard, therefore you cannot drag more than one file with a URL». Это про **старый** непоэлементный API
  (`NSURLPboardType`). Ограничение снимается поэлементным API: `tableView(_:pasteboardWriterForRow:)` -
  «Called to allow the table to support multiple item dragging… This method is required for multi-image dragging.
  If this method is implemented, then `tableView(_:writeRowsWith:to:)` will not be called.»
  (https://developer.apple.com/documentation/appkit/nstableviewdatasource/tableview(_:pasteboardwriterforrow:)).
  Каждая строка отдаёт свой `NSPasteboardItem` → мультивыделение уезжает как несколько файлов.
- Тип: `NSPasteboard.PasteboardType.fileURL` - «A file URL»
  (https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/fileurl).

**Опора в коде (оба примера - реальные работающие плееры):**

- Bòcan (Swift, Apache-2.0, коммит 2026-09-15), `Modules/UI/Sources/UI/Browse/TrackTableHelpers.swift:230-245`:
  ```
  let item = NSPasteboardItem()
  // The track-ID string drives intra-table reorder; the file URL lets the
  // same drag drop a real file onto Finder/Desktop or another app (#311).
  item.setString(String(id), forType: .string)
  item.setString(url.absoluteString, forType: .fileURL)
  ```
  Один и тот же `NSPasteboardItem` несёт две вещи: внутренний id (для переупорядочивания внутри таблицы) и
  file URL (для внешнего приложения). Резолвер URL - `TrackTableCoordinator.swift:53-59`, он отдаёт `nil`
  для не-файловых (стриминговых) строк, то есть радио не «утекает» как файл.
- Cog (Objective-C, GPL-2, коммит 2026-09-09), `Playlist/PlaylistController.m:806-821` - та же схема,
  но данными: `[item setData:[song.url dataRepresentation] forType:NSPasteboardTypeFileURL];`,
  поверх `NSPasteboardItem`, который вернул базовый `DNDArrayController` с внутренним индексом
  (`Playlist/DNDArrayController.m:21-27`, тип `org.cogx.cog.dnd-index`).

**Грабли, подтверждённые кодом и доками:**

1. **Aural Player НЕ умеет drag-out файла**, вопреки ожиданию. Он пишет на pasteboard только архив индексов строк:
   `Source/UI/Utils/TableView/TableViewController/TrackListTableViewController+DataSource.swift:21-25` →
   `TableDragDropContext.setIndicesAndData(...)` → `Source/UI/Utils/TableView/TableDragDropContext.swift:29-37` →
   `pasteboard.sourceIndexes = indices` → `Source/UI/Utils/Extensions/TableViewDragDropExtensions.swift:38-43`
   (`NSKeyedArchiver` под типом `kUTTypeData`). Комментарий в исходнике прямо говорит цель: «Do this to prevent
   the pasteboard from complaining when dragging / dropping». `.fileURL` на выход не пишется нигде в репо
   (grep по `Source`: `.fileURL` встречается только в `registerForDraggedTypes`, то есть на приём).
   **Вывод: Aural как образец drag-out не годится**, только как образец drop-in и тёмной темы.
2. **SwiftUI `.draggable` / `Transferable` только с `FileRepresentation` не даёт файл Finder-у.**
   Вторичный источник (разбор Nonstrict, macOS 13-14): «when we started to drop the file on Finder or other apps
   like Slack nothing happened. They just didn't accept the content»; рабочий обход - добавить
   `ProxyRepresentation { $0.url }` рядом с `FileRepresentation`
   (https://nonstrict.eu/blog/2023/transferable-drag-drop-fails-with-only-FileRepresentation/).
   Второй вторичный источник в том же духе: «SwiftUI doesn't offer anything equivalent to NSFilePromiseProvider…
   you have to use AppKit's drag & drop APIs instead» (https://wadetregaskis.com/swiftui-drag-drop-does-not-support-file-promises/).
   Доки Apple по `FileRepresentation` это косвенно подтверждают: там сказано «Use a FileRepresentation for
   transferring types that involve a large amount of data», то есть это транспорт данных, а не «вот тебе файл на диске»
   (https://developer.apple.com/documentation/coretransferable/filerepresentation).
   Утверждение «SwiftUI на macOS кладёт file promise вместо URL» дословно в доках Apple **не найдено** -
   подтверждено только вторичными источниками и косвенно тем, что оба живых плеера делают drag-out через AppKit.
3. **`.onDrag { NSItemProvider(contentsOf: url) }`** по докам «Provides data-backed content from an existing file…
   The system uses the URL's filename extension to select an appropriate universal type identifier»
   (https://developer.apple.com/documentation/foundation/nsitemprovider/init(contentsof:)). То есть провайдер
   отдаёт **содержимое** под UTI типа `public.mp3`, а не file-URL. Поведение в Finder не установлено (не тестировали).
   В клонах этот вариант для файлов никто не использует: Petrichor через `.onDrag` таскает только UUID-строку
   для переупорядочивания (`Views/Main/PlayQueueView.swift:180-184`, `NSItemProvider(object: track.id.uuidString as NSString)`).

**Что берём буквально:** `TrackTableHelpers.swift:214-245` из Bòcan (Apache-2.0) как готовый подкласс
`NSTableViewDiffableDataSource` с drag-out; `TrackTableCoordinator.swift:53-59` как резолвер URL.
Cog - только чтение (GPL-2 несовместим с закрытым кодом, копировать нельзя).

---

## 2. DROP папки на окно и на иконку в Dock

### Вердикт: `.fileURL` + `.folder` на приёме, обход `FileManager.enumerator`, плюс `public.folder` в `CFBundleDocumentTypes`

**Промис-ресивер (`NSFilePromiseReceiver`) не нужен** - Finder и файловые менеджеры кладут на pasteboard готовый
file URL. Обе реализации в клонах читают `NSURL` напрямую:

- AppKit-путь, Aural: `Source/UI/Player/DragDroppablePlayerView.swift:18` - `registerForDraggedTypes([.fileURL])`,
  чтение в `Source/UI/Utils/Extensions/TableViewDragDropExtensions.swift:48-53`:
  `draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]`. Валидация в `draggingUpdated` через
  `URL.atLeastOneSupportedURL(in:)` (`Source/Core/Utils/Extensions/URLExtensions.swift:66-76`), которая явно
  пропускает директории и симлинки: `if url.isSupportedFile || url.isDirectory || url.isAliasOrSymLink`.
  Приём выполняется в `performDragOperation` (`DragDroppablePlayerView.swift:42-52`).
- SwiftUI-путь, Bòcan: `Modules/UI/Sources/UI/AppRoot/RootView.swift:197-213`:
  `.onDrop(of: [UTType.fileURL, UTType.folder], isTargeted: $vm.isDragTargeted) { providers in … }`,
  с рамкой-подсветкой цели через `.overlay` (строки 188-196). Дальше `LibraryViewModel+Scanning.swift:93-104`
  разводит плейлисты (`m3u/m3u8/pls/xspf/cue`) и всё остальное в сканер.
  То есть на приём SwiftUI годится - проблема пункта 1 касается только выдачи.

**Dock-иконка и «Открыть с помощью»:** делегат `application(_:openFiles:)`.
Bòcan, `App/BocanApp.swift:113-120`:
```
/// Handles files dragged onto the Dock icon or opened via "Open With…".
func application(_: NSApplication, openFiles filenames: [String]) {
    let urls = filenames.map { URL(fileURLWithPath: $0) }
    ...
}
```
Apple про родственный `application(_:open:)`: «AppKit calls this method when your app is asked to open one or more
URL-based resources… You configure document types using Xcode, or by adding the CFBundleDocumentTypes key to your
Info.plist file. If your delegate implements this method, AppKit does not call the
`application(_:openFile:)` or `application(_:openFiles:)` methods»
(https://developer.apple.com/documentation/appkit/nsapplicationdelegate/application(_:open:)).
Значит, реализуем **один** из них, не оба.

**Регистрация папки в Info.plist** (иначе Dock не подсветит папку как принимаемую) - готовый кусок у Aural,
`Info.plist:382-393`:
```
<dict>
    <key>LSTypeIsPackage</key><false/>
    <key>CFBundleTypeName</key><string>folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
</dict>
```
Там же готовый список аудио-типов: `public.mp3` (строки 25-38), `public.mpeg-4-audio` (39-52) и т.д.
У Bòcan в `Resources/Info.plist` секции `CFBundleDocumentTypes` **нет** (grep не нашёл, есть только
`UTExportedTypeDeclarations`) - при этом `application(_:openFiles:)` реализован; работает ли у них перетаскивание
папки на Dock без объявления типа, по коду **не установлено**.

**Фильтр аудио по UTType:** `UTType.audio` - «A type that represents audio that doesn't contain video.
The identifier for this type is public.audio»
(https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/audio).
Bòcan использует такой набор для `NSOpenPanel` (`LibraryViewModel+Scanning.swift:61`, `panel.allowedContentTypes = Self.supportedAudioTypes`),
Aural фильтрует по расширениям (`URLExtensions.swift:41-47`, `SupportedTypes.playlistExtensions`).
Рекурсивный обход в обоих проектах делается в сканере библиотеки, не в UI; готового компактного «обойди папку и
верни аудио» мы в клонах не нашли в виде отдельного файла - это 15 строк на `FileManager.enumerator(at:includingPropertiesForKeys:)`,
пишем сами.

---

## 3. Таблица плейлиста: NSTableView vs SwiftUI Table

### Вердикт: NSTableView (view-based) + `NSTableViewDiffableDataSource`, завёрнутый в `NSViewRepresentable`

Это не теоретический выбор - это ровно то, к чему пришёл самый свежий из живых SwiftUI-плееров.
Bòcan, `Modules/UI/Sources/UI/Browse/TrackTable.swift:71-73`, комментарий в исходнике:

> `/// Wraps NSTableView in SwiftUI using diffable data source.`
> `/// Replaces SwiftUI Table to avoid gesture-recogniser contention on rows.`
> `public struct TrackTable: NSViewRepresentable {`

Их собственная проектная запись, сделанная **до** миграции, `docs/design-spec/ADR-005-library-ui.md:250`:

> «`Table` virtualisation in SwiftUI for macOS is decent but not perfect. If you hit jank past 5k rows, swap the
> backing source to a paginated query or drop to `NSTableView` via representable — but measure first.»

и там же строка 136: «Table backed by a paged query when > 5000 rows; otherwise direct fetch».
Фактический исход по коду: они ушли на NSTableView.

**Что говорят доки Apple про переиспользование:** `makeView(withIdentifier:owner:)` - «This method may also return
a reused view with the same identifier that is no longer available on screen»
(https://developer.apple.com/documentation/appkit/nstableview/makeview(withidentifier:owner:)).
То есть NSTableView перерабатывает вьюхи; SwiftUI `List`/`Table` такого контракта не даёт.

**Внешняя опора по производительности (вторичная, WebSearch-выжимка форумов Apple и блогов):** жалобы на
SwiftUI `Table`/`List` при 10 000 строк (нитки Apple Developer Forums «macOS SwiftUI Table Performance Issue»
thread/739849, «macOS 15.5 destroys SwiftUI Table Performance» thread/784845, hackingwithswift «SwiftUI List
performance with row count > 2000»). Точных цифр FPS мы не мерили - **не установлено**, свой замер не делали.
Практический вывод для нас другой и он важнее цифр: у AIMP-подобного плейлиста строка не простая
(две строки текста + чекбокс + кастомная подсветка), а именно на таких строках SwiftUI и проседает.

**SwiftUI Table умеет то, что нам нужно по фичам** (если решим всё же брать его):
сортировка - «To make the columns of a table sortable, provide a binding to an array of KeyPathComparator
instances… the table itself doesn't perform a sort operation»
(https://developer.apple.com/documentation/swiftui/table). macOS 12.0+.
Живой рабочий пример с колонками Year и Duration и с сохранением настроек колонок -
Petrichor (MIT, коммит 2026-09-15), `Views/Components/TrackViews/TrackTableView.swift:176-330`:
`TableColumn("Year", value: \.year)` (271), `TableColumn("Duration", value: \.duration)` (319),
`TableColumnCustomization<Track>` с сохранением в `UserDefaults` (40-50). Показательно, что даже Petrichor
сортирует **не на главном потоке**: `performBackgroundSort(with:)` → `Task.detached(priority: .userInitiated)`
(`TrackTableView.swift:451-462`).

### Конкретные куски, которые можно взять готовыми (Bòcan, Apache-2.0)

| Что нужно | Где лежит | Комментарий |
|---|---|---|
| Обёртка NSTableView в SwiftUI | `Modules/UI/Sources/UI/Browse/TrackTable.swift` (371 стр.; весь комплект из 6 файлов `TrackTable*` - 1863 стр., из них контекстное меню 278 нам не нужно) | `NSViewRepresentable` → `NSScrollView`, координатор отдельным файлом |
| Diffable data source + drag | `TrackTableHelpers.swift:208-280` | секция `Int`, элемент `Int64` id; drag-out и reorder в одном классе |
| Описание колонок таблицей данных | `TrackTable+ColSpecs.swift:5-60` | `ColSpec(id, title, minWidth, idealWidth, maxWidth, sortKey, hidden)` - ровно то, что нужно под «длительность/год» |
| Сортировка по клику на заголовок | `TrackTableHelpers.swift:221-228` → `coordinator.handleSortDescriptorsDidChange(in:)` | по докам: `tableView(_:sortDescriptorsDidChange:)` - «The data source typically sorts and reloads the data» (https://developer.apple.com/documentation/appkit/nstableviewdatasource/tableview(_:sortdescriptorsdidchange:)) |
| **Колонка-чекбокс** | `TrackTableHelpers.swift:49-89`, класс `ShuffleCheckCell` | `NSButton(checkboxWithTitle:target:action:)` в `NSTableCellView`, переиспользуется по `identifier`. Под «галочку проиграно» - один в один |
| Высота строки (двухстрочная) | `TrackTableCoordinator.swift:163-174` | `heightOfRow` 22/28/36 по настройке плотности; для двух строк AIMP ставим свою константу |
| Ячейка с обложкой | `TrackTableHelpers.swift:192-205` | асинхронная загрузка миниатюры по высоте строки (~40 pt), отмена по `loadTask?.cancel()` |
| Ловушка синхронизации выделения | `TrackTableCoordinator.swift:176-186` | комментарий в коде: «Defer to avoid publishing inside AppKit's table layout (SwiftUI runtime fault)» - публиковать выделение в SwiftUI только через `Task { @MainActor }` |

### Кастомная тёмная тема в стиле AIMP (оранжевый акцент)

Берём у Aural (MIT), он визуально ближе всех к AIMP:

- Своя отрисовка выделенной строки: `Source/UI/Playlist/AuralPlaylistViews.swift:15-27`, класс `GenericTableRowView`,
  `override func drawSelection(in:)` → `NSBezierPath.fillRoundedRect(bounds.insetBy(dx:1,dy:0), radius: 2, withColor: .playlistSelectionBoxColor)`.
  Комментарий в исходнике: «Customizes the selection look and feel». Это и есть способ получить оранжевую плашку
  вместо системного синего.
- Цвет текста по состоянию строки: `AuralPlaylistViews.swift:29-45`, `BasicTableCellView` с
  `unselectedTextColor` / `selectedTextColor` и реакцией на `backgroundStyle`.
- Фон таблицы и скроллвью одной функцией: `Source/UI/Utils/Extensions/NSTableViewExtensions.swift`,
  `setBackgroundColor(_:)` красит `tableView`, `enclosingScrollView` и `clipView` - иначе при скролле видны
  светлые полосы.
- Целая система схем цветов (если захотим сменные темы): `Source/UI/ColorSchemes/Domain/ColorScheme.swift`,
  `ColorScheme+Presets.swift`.

### Поиск

- SwiftUI-путь: `.searchable(text:placement:.toolbar, prompt:)` - Bòcan, `RootView.swift:102`.
- AppKit-путь под кастомный тёмный вид строки поиска как в AIMP (нижняя панель «Quick search»):
  Petrichor, `Views/Components/Widgets/SearchInputField.swift:4-40` - `NSSearchField` в `NSViewRepresentable`,
  настраивается `bezelStyle`, `controlSize`, шрифт, гашение тени слоя.

---

## 4. Шапка: обложка, название, транспорт, громкость, медиа-клавиши

**Медиа-клавиши и системный «Now Playing» - штатные MediaPlayer.framework, на macOS есть с 10.12.2**
(проверено по метаданным доков: `MPRemoteCommandCenter` - macOS 10.12.2+, `MPNowPlayingInfoCenter` - macOS 10.12.2+).

- `MPRemoteCommandCenter` - «An object that responds to remote control events sent by external accessories and
  system controls… Don't create instances of this class yourself. Instead, use the shared method»
  (https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter).
- `MPNowPlayingInfoCenter` - «An object for setting the Now Playing information for media that your app plays…
  The system displays Now Playing information on the device's Lock Screen and in the media controls in Control Center»
  (https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter).

Готовый рабочий модуль на две штуки, Bòcan (Apache-2.0), забирается целиком:

- `Modules/Playback/Sources/Playback/NowPlaying/RemoteCommands.swift` - регистрация play/pause/toggle/next/prev/
  seek/skip, идемпотентный `register()` с флагом `isRegistered` (строки 34-36), все хендлеры как замыкания
  `onPlay`/`onPause`/… (15-22). Комментарий в исходнике: «Must be created on the `@MainActor` because
  `MPRemoteCommandCenter.shared()` is a main-thread singleton» (9-10).
- `Modules/Playback/Sources/Playback/NowPlaying/NowPlayingCentre.swift` - заполнение `nowPlayingInfo`
  (`MPMediaItemPropertyTitle`, `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyPlaybackRate`,
  `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `MPNowPlayingInfoPropertyMediaType` - строки 54-61),
  тикер позиции 1 Гц (`positionTimer`, 24) и монотонный токен против гонки поздно приехавшей обложки
  (`artworkToken`, 28-33) - последнее реально важно при быстром перещёлкивании треков, что у DJ норма.

Обложка/название/транспорт/громкость в шапке - это обычные вьюхи, готовых компонентов брать не нужно;
раскладка снимается со скриншота AIMP. Touch Bar по заданию не нужен.

**Не установлено:** требует ли macOS-приложению чего-то ещё (entitlement, `playbackState`), чтобы физические
медиа-клавиши F7/F8/F9 перехватывались именно нашим приложением, а не Музыкой. В коде Bòcan свойство
`MPNowPlayingInfoCenter.playbackState` не встречается (grep по `Modules` пустой), в их `docs/GOTCHAS.md`
раздела про медиа-клавиши нет. Проверяется только живым запуском.

---

## Таблица кандидатов

| Кандидат | Язык / лицензия | Последний коммит | Что берём | Вердикт |
|---|---|---|---|---|
| **bocan/bocan-music** | Swift 6, SwiftUI+AppKit, **Apache-2.0** | 2026-09-15 | `TrackTable*` (обёртка NSTableView + diffable + drag-out `.fileURL` + чекбокс-ячейка + спеки колонок), `RemoteCommands.swift`, `NowPlayingCentre.swift`, `RootView.swift:197-213` (drop), `BocanApp.swift:113-120` (Dock) | **Берём.** Лицензия позволяет, код свежий, есть тесты (`Modules/UI/Tests/.../TrackTableDragTests.swift` покрывает именно резолв file URL для drag-out) |
| **kushalpandya/Petrichor** | Swift, SwiftUI, **MIT** | 2026-09-15 | `SearchInputField.swift` (NSSearchField), `TrackTableView.swift` как эталон SwiftUI `Table` с колонками Year/Duration и фоновой сортировкой, `TrackListView.swift` (двухстрочная строка: заголовок + «артист · альбом · год» + длительность справа моноширинными цифрами, строки 310-340 и 370-395; комментарий-описание на строке 15) | **Резерв.** Drag-out файла нет (только UUID-строка для reorder, `PlayQueueView.swift:180-184`); берём точечно вёрстку строки и поиск |
| **kartik-venugopal/aural-player** | Swift, AppKit, **MIT** | 2025-06-22 | `Info.plist:9-393` (типы документов + `public.folder`), `DragDroppablePlayerView.swift` (drop), `AuralPlaylistViews.swift:15-45` (оранжевая подсветка строки), `NSTableViewExtensions.setBackgroundColor`, `ColorSchemes/*` | **Берём частично** (drop, тема, Info.plist). **Для drag-out - нет:** файловый URL на pasteboard не пишется вообще |
| **losnoco/Cog** | Objective-C, **GPL-2** | 2026-09-09 | - | **Нет для копирования.** GPL-2 заражает. Ценность только как подтверждение схемы drag-out: `Playlist/PlaylistController.m:806-821` |
| **flocked/AdvancedCollectionTableView** | Swift, **MIT** | 2026-09-04 | расширения NSTableView: cell registration, diffable для NSOutlineView | **Нет.** Зависит от `FZUIKit` и `FZQuicklook` по `branch: "main"` (`Package.swift:18-19`) - незакреплённые зависимости; каталога `Tests` в репо нет; 2,2 МБ исходников ради того, что у нас закрывают 300 строк из Bòcan. `platforms: [.macOS("12.0")]` - собирается |

---

## Рекомендуемая связка (одной строкой каждая)

1. **Drag-out:** `NSTableViewDiffableDataSource` + `tableView(_:pasteboardWriterForRow:)`, один `NSPasteboardItem`
   на строку с `.fileURL` и внутренним id. Промисы не нужны.
2. **Drop:** `.onDrop(of: [.fileURL, .folder])` на корневой вью (или `registerForDraggedTypes([.fileURL])` на AppKit-вью),
   `readObjects(forClasses: [NSURL.self])`, рекурсивный обход папки через `FileManager.enumerator`, фильтр по `UTType.audio`.
3. **Dock:** `application(_:openFiles:)` + `CFBundleDocumentTypes` с `public.folder` и аудио-UTI.
4. **Таблица:** NSTableView view-based в `NSViewRepresentable`, кастомный `NSTableRowView.drawSelection` под оранжевый AIMP-акцент,
   `heightOfRow` под две строки, колонка-чекбокс на `NSButton(checkboxWithTitle:)`, сортировка через `sortDescriptorsDidChange`.
5. **Шапка:** `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` из модуля Bòcan целиком.

---

## Что не установлено (честно)

- Реальное поведение drag-out **в rekordbox, Ableton Live, Logic Pro, Telegram Desktop** - не проверялось, приложения
  не запускались. Код Bòcan упоминает только Finder/Desktop и «another app» (`TrackTableHelpers.swift:236-237`).
  Схема `.fileURL` - стандартная, но подтверждения конкретно по этим четырём приложениям нет.
- Числа производительности SwiftUI `Table` на 5 000 строк - своих замеров нет; решение обосновано выбором Bòcan
  и их собственной ADR, а не бенчмарком.
- Работает ли drop папки на иконку Dock без `CFBundleDocumentTypes` (случай Bòcan) - по коду не определяется.
- Нужен ли `MPNowPlayingInfoCenter.playbackState` и/или entitlement, чтобы физические медиа-клавиши доставались
  нашему приложению - в исходниках клонов не найдено.
- Влияние App Sandbox на drag-out (нужен ли security-scoped доступ при передаче URL наружу) - не проверялось.

## Открытые вопросы владельцу

1. **Сортировка по колонкам или по меню?** На скриншоте AIMP у плейлиста **нет заголовков колонок** - строка
   двухстрочная и занимает всю ширину, а сортировка в AIMP вызывается из меню. Требование брифа «сортировка по
   длительности» технически проще решается колонками с заголовками (это меняет вид на «как Музыка», а не «как AIMP»).
   Нужно выбрать: (а) как на скриншоте - две строки без заголовков, сортировка пунктом меню; (б) колонки с
   кликабельными заголовками. Смешанного варианта в готовых компонентах нет.
2. **Sandbox / подпись.** Планируется ли раздача приложения (нотаризация, App Store) или это личный инструмент?
   От этого зависит, тянуть ли security-scoped bookmarks для папок (в Bòcan они есть, это заметный объём кода)
   или обойтись без сэндбокса вовсе.
3. **Что делает галочка «проиграно»** - ставится автоматически при завершении трека, ставится руками, или и то и другое?
   От этого зависит, нужна ли колонка-чекбокс кликабельной (готовая `ShuffleCheckCell`) или это просто индикатор.
