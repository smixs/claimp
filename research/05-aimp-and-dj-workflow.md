# 05. Референс AIMP и рабочий процесс DJ-подготовки

Дата: 2026-09-15 09:40. Задача №5 брифа. Правило «не установлено» применяется явно.

`clones/...` в таблице ниже - рабочие копии upstream-репозиториев; в этот репозиторий они не входят.

## 0. Источники и их статус

| Источник | Что это | Статус |
|---|---|---|
| `https://www.aimp.ru/?do=help` | официальная страница помощи AIMP | официальный сайт |
| `https://www.aimp.ru/forum/index.php?topic=259.0` | официальный F.A.Q. для ПК (ссылка с `?do=help`) | официальный, но форумный формат |
| `https://aimp.ru/blogs/?p=1589` | «Справка: очередь воспроизведения», автор Artem (автор AIMP), 27.02.2026 | официальный блог |
| `clones/aimp-sdk/` | AIMP SDK: исходники API (Delphi/C++), `AIMP Playlist File Format v4.rtf`, `Help/AIMP-en.chm` | зеркало `github.com/Exle/aimp-sdk`, workflow тянет zip с `https://aimp.ru/` (`.github/workflows/update-sdk.yml:64`); в CHM подпись «© Artem Izmaylov, 2006-2026, www.aimp.ru». Последний коммит зеркала 2026-07-14 |
| `clones/chm-en/` | распакованный `Help/AIMP-en.chm` (7zz), 497 файлов | официальная справка SDK |
| `https://manual.mixxx.org/latest/en/chapters/*` | Mixxx manual | официальный |
| `raw.githubusercontent.com/mixxxdj/mixxx/main/src/library/dao/trackdao.cpp` | исходник Mixxx | официальный репозиторий |
| `https://cdn.rekordbox.com/files/20250718115648/rekordbox7.1.4_manual_EN.pdf` | rekordbox 7.1.4 Instruction Manual EN | официальный |
| `support.serato.com` | база знаний Serato | **страницы отдают 403** на прямой запрос; цитаты только по сниппетам поиска, дословность не подтверждена |

Оговорка: AIMP — Windows/Linux/Android-приложение. Пользовательского руководства в виде полного мануала у AIMP нет: официально есть F.A.Q. на форуме, статьи «Справка» в блоге и справка SDK. Поэтому часть поведения UI установлена не по тексту справки, а по официальному API и официальной спецификации формата плейлиста — это помечено в каждом пункте.

---

## 1. Что видно на скриншоте `research/aimp-reference.png`

Только описание изображения, без выводов из документации.

Окно AIMP, тёмная тема, акцентный цвет оранжевый. Сверху вниз:

1. **Титульная строка:** логотип «AIMP», иконка шестерёнки, справа стандартные кнопки Windows (свернуть / развернуть / закрыть).
2. **Шапка трека:** слева квадратная обложка (фото дерева). Справа четыре строки:
   - `Future Garage Mix...` — крупно, обрезано многоточием;
   - `Dj Antiz & Zebyte`;
   - `Future Garage Mix Part 1`;
   - `MP3, 44 kHz, 320 kbps, Stereo` — мелким, серым.
   В правой части шапки: иконка динамика + горизонтальный ползунок громкости (заполнен примерно на треть), справа столбиком три иконки — эквалайзер (три слайдера), часы, «вещание» (значок волн).
3. **Ряд транспорта:** 7 иконок в строку — «повтор» (перечёркнута), предыдущий, стоп, крупная круглая «play» в кольце, пауза, следующий, «перемешать».
4. **Волна:** горизонтальная полоса во всю ширину окна, симметричная относительно горизонтальной оси (вверх и вниз от центра), рисунок пиковый — столбики разной высоты. Левая часть до позиции примерно 1/4 ширины залита оранжевым, остальное серым; граница резкая и вертикальная. Под полосой слева `8:21`, справа `32:07`. Ни одного цвета кроме оранжевого и серого в волне нет — градиента и раскраски по частотам не видно.
5. **Вкладка плейлиста:** `Dj Antiz & Zebyte` с оранжевым подчёркиванием, справа `+`.
6. **Заголовок группы:** чекбокс (отмечен) + `DJ Antiz` оранжевым, справа `4 / 2:09:34` и шеврон «свернуть».
7. **Четыре строки треков.** Каждая строка — две линии:
   - линия 1: чекбокс (все отмечены), номер `1.` … `4.`, `Dj Antiz & Zebyte - Future Garage Mix Part N`, справа длительность `32:07`, `30:21`, `30:41`, `36:26`;
   - линия 2, мелко и серым: `MP3 ≈ 44 kHz, 320 kbps, 73,87 MB`; справа на этой же линии — пять точек в ряд (у всех четырёх треков точки тусклые, ни одна не залита).
   Первая строка выделена сплошной оранжевой заливкой (текущий трек).
8. **Итог плейлиста** по центру внизу списка: `4 / 00:02:09:34 / 297,90 MB`.
9. **Нижняя панель:** слева поле `Quick search` с лупой; справа кнопки `+`, `−`, `...`, стрелки вверх-вниз (сортировка), лупа, «гамбургер».

Чего на скриншоте **нет**: шапки с названиями колонок, колоночной сетки, столбцов «Год», «BPM», «Жанр», отдельной пометки «проиграно», кнопок drag-out.

---

## 2. AIMP по официальным источникам

### 2.1 «Колонок» в плейлисте AIMP нет — есть две строки шаблона и набор переключаемых элементов

Строка трека в плейлисте описывается двумя шаблонами, а не колонками:

- `AIMP_PLAYLIST_PROPID_FORMATING_LINE1_TEMPLATE` и `AIMP_PLAYLIST_PROPID_FORMATING_LINE2_TEMPLATE` — шаблоны первой и второй строки; меняются только если `AIMP_PLAYLIST_PROPID_FORMATING_OVERRIDEN ≠ 0` (`clones/chm-en/IAIMPPlaylist.html`; константы — `clones/aimp-sdk/Sources/Delphi/apiPlaylists.pas`).
- Переключаемые элементы отображения (все действуют при `AIMP_PLAYLIST_PROPID_VIEW_OVERRIDEN ≠ 0`), `apiPlaylists.pas:115-122`:
  - `VIEW_DURATION` (31) — показ длительности,
  - `VIEW_EXPAND_BUTTONS` (32) — кнопки сворачивания групп,
  - `VIEW_MARKS` (33) — показ «отметок» (звёзд/точек),
  - `VIEW_NUMBERS` (34) и `VIEW_NUMBERS_ABSOLUTE` (35) — нумерация; при `NUMBERS_ABSOLUTE = 0` «each group will have own tracks numeration»,
  - `VIEW_SECOND_LINE` (36) — вторая строка,
  - `VIEW_SWITCHES` (37) — показ галочек.

Это ровно то, что видно на скриншоте: номер, две строки текста, длительность справа, чекбокс слева, пять точек «отметки» справа.

Официальный F.A.Q. подтверждает пользовательский путь: «Settings\Playlist\Display Settings», индивидуальные настройки — по правому клику на вкладке плейлиста (`https://www.aimp.ru/forum/index.php?topic=259.0`).

Колоночный контрол (`IAIMPUITreeList` с `AddColumn`, `AIMPUI_TL_PROPID_COLUMN_VISIBLE`, сортировкой по колонкам) в AIMP есть, но это общий UI-компонент SDK, применяемый в фонотеке и плагинах, а не плейлист (`clones/chm-en/IAIMPUITreeList.html`). **Не установлено**, можно ли в AIMP 5.x переключить плейлист в колоночный режим.

### 2.2 Какие поля вообще есть у трека

Официальная спецификация `AIMP Playlist File Format v4.rtf` (`clones/aimp-sdk/`), секция CONTENT, строка трека:

```
FileName|Title|Artist|Album|AlbumArtist|Genre|Date|TrackNumber|DiskNumber|Composer|Publisher|
Bitrate|Channels|SampleRate|Duration|FileSize|BPM|PlaybackSwitch|PlaybackQueueIndex|Custom|
Lyricist|Mood|BitDepth|URL|FileFormat|Comment
```

То есть в самом файле плейлиста хранятся в т.ч. **Date** (год/дата релиза), **BPM**, **Duration**, **FileSize**, **FileFormat**. Флага «проиграно» в этом списке нет.

Полный набор полей файла в API — `apiFileManager.pas:93-139` (`AIMP_FILEINFO_PROPID_*`): ALBUM, ALBUMART, ALBUMARTIST, ALBUMGAIN/ALBUMPEAK, ARTIST, BITRATE, **BPM**, CHANNELS, COMMENT, COMPOSER, COPYRIGHT, CUESHEET, **DATE**, DISKNUMBER/DISKTOTAL, DURATION, FILENAME, FILESIZE, GENRE, LYRICS, PUBLISHER, SAMPLERATE, TITLE, TRACKGAIN/TRACKPEAK, TRACKNUMBER/TRACKTOTAL, URL, BITDEPTH, CODEC, CONDUCTOR, MOOD, CATALOG, ISRC, LYRICIST, ENCODEDBY, RATING, **KEY** (id 46, тональность), и отдельной группой поля фонотеки: `ML_ADDINGDATE`, `ML_LASTPLAYDATE`, `ML_MARK`, `ML_PLAYCOUNT`, `ML_RATING`, `ML_DISPLAYING_MARK`, `ML_LABELS`.

### 2.3 Шаблоны и макросы

- Шаблон применяется сервисом `IAIMPServiceFileInfoFormatter`; в документации прямо сказано: «The list of supported macros for template depends from version of application» (`clones/chm-en/IAIMPServiceFileInfoFormatter.html`). Список макросов показывается контекстным меню (`IAIMPServiceFileInfoFormatterUtils.ShowMacrosLegend`), в справке он **не опубликован**.
- Официальный F.A.Q.: «Right-click the input field — a list of available templates will appear»; `%FileName` включает расширение, `%RemoveFileExt(%FileName)` — без расширения (`topic=259.0`).
- `%Custom` — пользовательское однострочное поле, «Use the %Custom macro to use value of this field for grouping or sorting the records» (`clones/chm-en/IAIMPPlaylistItem.html`).
- На официальном форуме AIMP в треде о шаблонах названы `%Title`, `%Artist`, `%Album`, `%Year`, `%Genre`, `%Duration`, `%FileName`, условные `%IF(tag, есть, нет)` и `%IFEqual(a, b, равно, не равно)` (`https://www.aimp.ru/forum/index.php?topic=63714.0`). Это форумный источник, не справка: **дословный полный список макросов официально не опубликован**, статус — «не установлено».

Итог для нашего продукта: `%Year` как макрос подтверждён только форумом; поле года в данных подтверждено официально как `Date` (формат плейлиста) / `AIMP_FILEINFO_PROPID_DATE` (API) / `Year` (фонотека).

### 2.4 Галочка в плейлисте — это НЕ «проиграно» и НЕ очередь

Самый точный официальный ответ — спецификация формата плейлиста, `AIMP Playlist File Format v4.rtf`:

> `PlaybackSwitch - (0/1) state of the automatic playback switch. If it set to 0 - track will be skiped during automatic switching between tracks.`

То есть галочка = «участвует в автоматическом переключении треков». Снятая галочка не удаляет трек и не мешает запустить его вручную — она исключает трек из автоперехода.

Подтверждения в API и командах:
- `AIMP_PLAYLISTITEM_PROPID_PLAYINGSWITCH` (`apiPlaylists.pas:87`), уведомление `AIMP_PLAYLIST_NOTIFY_PLAYINGSWITCHS` (`apiPlaylists.pas:175`);
- команды `AIMP_MSG_CMD_PLS_SWITCH_ON` / `..._SWITCH_OFF` — «Switch on/off **auto playing marker** for selected tracks in active playlist» (`clones/chm-en/AIMP_MSG_CMD_PLS_SWITCH_ON.html`, `..._OFF.html`);
- есть команда «Delete switched off tracks from active playlist» `AIMP_MSG_CMD_PLS_DELETE_SWITCHEDOFF` и её вариант с удалением с диска (`AIMP_MSG_CMD_PLS_DELETE_SWITCHEDOFF_FROM_HDD.html`).

Значит рабочий сценарий «снял галочки с ненужного → удалил снятые» в AIMP есть штатно.

### 2.5 Очередь воспроизведения — отдельный механизм

- У элемента плейлиста отдельное свойство `AIMP_PLAYLISTITEM_PROPID_PLAYBACKQUEUEINDEX` — «Index in the internal playback queue. This index is different from playlist item index!» (`IAIMPPlaylistItem.html`), и оно же пишется в файл плейлиста как `PlaybackQueueIndex`.
- Официальная «Справка: очередь воспроизведения» (`https://aimp.ru/blogs/?p=1589`, автор Artem, 27.02.2026) описывает очередь как «временный список треков, которые будут воспроизведены в указанном порядке, без необходимости менять исходный плейлист»; трек уходит из очереди по мере проигрывания.

Вывод: галочка и очередь — две разные сущности. Галочка ≠ «выбор для очереди».

### 2.6 «Отметка» (звёзды/точки) и статистика прослушиваний

- У элемента плейлиста: `AIMP_PLAYLISTITEM_PROPID_MARK` — «Mark, (0.0 to 5.0)», тип Double (`IAIMPPlaylistItem.html`, `apiPlaylists.pas:86`). Отображение включается `VIEW_MARKS`. Это те самые пять точек на втором ряду каждой строки скриншота.
- **Флага «проиграно» в плейлисте у AIMP нет**: его нет ни в формате `AIMPPL4`, ни среди `AIMP_PLAYLISTITEM_PROPID_*`.
- Статистика прослушиваний есть **только в фонотеке** (Music Library), `apiMusicLibrary.pas:274-306`: `LastPlayback` (DateTime), `PlaybackCount` (Int32), `Rating` (Int32), `UserMark` (0..5), `Added`, `Labels`, `Year`, `BPM`. Плюс зеркальные поля в файловом API: `ML_LASTPLAYDATE`, `ML_PLAYCOUNT`, `ML_MARK`, `ML_RATING` (`apiFileManager.pas:132-138`).

То есть в AIMP «проиграно» = счётчик в базе фонотеки, а не отметка в плейлисте, и он не сбрасывается «за сессию» (механизма сессии в API нет — **не установлено** обратное).

### 2.7 Волна — это waveform-навигатор по амплитуде, не спектр

- Сервис `IAIMPServiceWaveform`: «Service provides an ability to register custom data provider for the **waveform-navigator**», минимальная версия 4.10.1815 (`clones/chm-en/IAIMPServiceWaveform.html`).
- Расширение `IAIMPExtensionWaveformProvider.Calculate(FileURI, TaskOwner, Peaks, PeakCount)`: «Plugin must calculate the "wave" for the FileURI in resolution of PeakCount points» (`IAIMPExtensionWaveformProvider.html`; исходник `apiPlayer.pas:171-174`).
- Точка волны — структура `TAIMPWaveformPeakInfo` ровно из двух полей: `MaxNegative` и `MaxPositive`, «Maximal absolute value from negative/positive values from data block that presented by this point» (`TAIMPWaveformPeakInfo.html`; `apiPlayer.pas:107-116`).

Следствия, подтверждённые кодом: волна строится из **пиков амплитуды** на блок сэмплов, симметрично вверх/вниз, **частотной информации в модели данных нет**. Значит раскрасить встроенную волну «по частотам» нечем. Спектр в AIMP — отдельная вещь: визуализации получают данные по флагам `AIMP_VISUAL_FLAGS_RQD_DATA_WAVEFORM` и `..._SPECTRUM` (`apiVisuals.pas:41-44`), и F.A.Q. отдельно поясняет, что «анализатор спектра показывает весь возможный диапазон частот файла» (`topic=259.0`).

Цвет волны на скриншоте (оранжевый до текущей позиции, серый после) — это индикация прогресса. Официального текста, который называет эти два цвета, я не нашёл: **не установлено**, но модель данных исключает другие трактовки, кроме «залито до позиции воспроизведения».

### 2.8 Сортировка и группировка

Сортировка (`IAIMPPlaylist.Sort`, `apiPlaylists.pas:142-150`): `SORTMODE_TITLE`, `SORTMODE_FILENAME`, **`SORTMODE_DURATION`**, `SORTMODE_ARTIST`, `SORTMODE_INVERSE`, `SORTMODE_RANDOMIZE`, а с v5.10 — `RANDOMIZE_GROUPS`, `RANDOMIZE_GROUPITEMS`, `RANDOMIZE_GROUPS_AND_IT_ITEMS`. Те же команды есть как сообщения: `AIMP_MSG_CMD_PLS_SORT_BY_DURATION` — «Sort tracks in active playlist by duration field».

Сверх этого:
- `Sort2(Template)` — сортировка по произвольному шаблону («Sort template. Refer to the IAIMPServiceFileInfoFormatter»), `Sort3(Proc)` — своя функция сравнения (`IAIMPPlaylist.html`). Пользовательский путь из F.A.Q.: «Settings\Playlist\Template-based Sorting» → «Menu "File Sorting" > "Sort by Template"» (`topic=259.0`).
- Группировка: `AIMP_PLAYLIST_PROPID_GROUPPING`, `GROUPPING_TEMPLATE`, `GROUPPING_AUTOMERGING` (`IAIMPPlaylist.html`); в файле плейлиста группы — строки, начинающиеся с `+` (свёрнута) или `-` (развёрнута) (`AIMP Playlist File Format v4.rtf`). Метод `MergeGroup` — «Merges one or all groups with same names».
- Сортировка мышью внутри списка — `AIMPUI_TL_PROPID_DRAG_SORTING` «Allows custom sorting to user via drag-n-drop» (для UI-контрола SDK, `IAIMPUITreeList.html`).

Замечание для нашего плейлиста: сортировка по длительности у AIMP — **отдельная встроенная команда**, а не «клик по заголовку колонки». Владелец просил именно её.

### 2.9 Drag-out файлов

В SDK есть `IAIMPFileSystemCommandDropSource`: «Command creates the `IAIMPStream` instance for specified FileName for **drag-n-drop operation**. … You can edit the FileName content to change the target file name», минимальная версия 4.10.1800 (`clones/chm-en/IAIMPFileSystemCommandDropSource.html`). Это механизм отдачи файла наружу (в т.ч. для виртуальных файлов внутри контейнеров).

**Не установлено** по официальным источникам: поведение drag-out обычного файла из плейлиста в Проводник/другое приложение в пользовательской документации не описано; в блоге упомянут макрос `%IN` для функции «Отправить файлы в …» (по результатам поиска на aimp.ru, дословно не подтверждено). Для нашего продукта это не блокер — требование владельца сформулировано без опоры на AIMP-реализацию.

---

## 3. Нативные macOS-аналоги: краткая сверка

Только по официальным сайтам и репозиториям. «н/у» = не установлено по проверенному источнику (не значит «нет»).

| Продукт | Стек / лицензия / свежесть | Что есть (подтверждено) | Чего нет / н/у |
|---|---|---|---|
| **Aural Player** (`github.com/kartik-venugopal/aural-player`) | Swift, MIT, **архив с 21.06.2025**, последний коммит 22.06.2025 (`git log -1` в клоне) | Модуль waveform в коде (`Source/UI/UnifiedPlayer/Waveform/`), общий слой drag-n-drop для таблиц (`Source/UI/Utils/TableView/TableDragDropContext.swift`, `TableViewDragDropExtensions.swift`), плоский плейлист (`Source/UI/Playlist/FlatPlaylistTableViews.swift`) | Развития нет: «no bug fixes, no new features, no new releases» (README). Колонки/год/сортировка по длительности — н/у по README (он в 11 строк) |
| **foobar2000 for Mac** (`foobar2000.org/mac`) | собственная лицензия foobar2000, macOS 11+, Intel/Apple Silicon, стабильная 2.25.10 | Официально подтверждены только требования, лицензия и версии | Колонки, title formatting, waveform-seekbar — **н/у по официальной странице**; страница `/mac/help` и `/mac/changelog` отдают 404. Закрытый исходник → «взять модуль» нельзя |
| **Swinsian** (`swinsian.com`) | платный $34.95, trial | «customizable interface (art grid, **column browser**, track inspector)», теги с regex, smart playlists, **library statistics**, поиск дублей, folder watching, AppleScript | Waveform, drag-out в Finder, набор колонок — н/у по сайту. Закрытый исходник |
| **VOX** (`vox.rocks/mac-music-player`) | free + платная подписка (VOX Music Cloud) | Форматы FLAC/MP3/CUE/APE/M4A, hi-res 24/192, эквалайзер, gapless, SONOS, облако | Плейлист-колонки, waveform, drag-out — н/у по сайту. Закрытый исходник, ядро продукта — облако |
| **Doppler** (`brushedtype.co/doppler`) | платный $30, macOS 11+ | Локальная библиотека купленных файлов, FLAC/ALAC/WAV/MP3/AAC/M4A, поиск обложек, объединение альбомов, «drag, drop and play» (импорт), синк на iPhone | Колонки, сортировка по длительности, waveform, drag-out наружу — н/у. Закрытый исходник |
| **Cog** (`cog.losno.co`, `github.com/losnoco/Cog`) | Objective-C/Swift, GPL-2.0, macOS 12.0+, активная разработка (4587 коммитов) | Очень широкий список декодеров (трекеры, чиптюн, MIDI, архивы), gapless, CUE, per-track artwork, эквалайзер, **spectrum visualization**, HTTP-стримы | **Waveform не заявлен** (заявлен именно спектр). Состав колонок плейлиста — н/у по README (README — про лицензии и сборку) |
| **Musique** (`github.com/flaviotordini/musique`) | C++/Qt 6, GPL-3.0, TagLib + MPV | «music player built for speed, simplicity and style» | Целевая платформа по репо — Linux desktop; поддержка macOS **н/у**. Qt = не нативный AppKit → против требования брифа |
| **Musicat** (`github.com/basharovV/musicat`) | Svelte + **Tauri** + Rust, GPL-3.0, 0.x, активная разработка | Заявлены **waveform visualization**, smart playlists, редактор тегов, статистика, мини-плеер, авто-мониторинг папок, macOS/Linux/Windows | Tauri = веб-стек внутри (WebView), **противоречит запрету брифа на Электрон/веб**; версия 0.x, «features are being added regularly» |

Короткий вывод по разделу: из восьми только **Aural Player** одновременно нативный (Swift/AppKit), открытый (MIT) и уже содержит waveform-модуль и drag-n-drop-инфраструктуру, но он архивный. Cog — живой и нативный, но со спектром, а не волной, и на GPL-2.0 (лицензия влияет на переиспользование кода). Остальные либо закрыты, либо не macOS-нативны.

---

## 4. DJ-подготовка миксов: какие поля считаются обязательными

### 4.1 Mixxx (open source, официальный manual)

Колонки библиотеки, названные в `https://manual.mixxx.org/latest/en/chapters/library`: Title, Artist, Album, Genre, Composer, **BPM**, **Key**, **Rating**, **Color**, **Played**, **Play Count**, **Last Played**, **Comment**, **Date Added / DateTime Added**, **Preview**, Cover Art, а также нередактируемые Bitrate, Size, Length, Type, Filename, Location.

Подтверждённые механики:
- **Сортировка:** мультиколоночная, до трёх колонок; повторный клик — обратный порядок; клик по заголовку **Preview** = случайная сортировка; клик по **Key** сортирует по кругу квинт (Lancelot начинается с G#m = 1A). Цитата: «You can sort multiple columns by clicking up to three column headers».
- **Color:** «Assign a color to all selected tracks to indicate **mood, energy** etc.»
- **Rating:** «Rate tracks by hovering over the rating field and clicking the stars».
- **Сброс «проиграно»:** в меню Clear — «Play Count: Marks selected tracks as **not played in the current session** and sets their play counter to zero. The icon in the Played column changes.»
- **Preview Deck не портит статистику:** «Pre-listening to a track does not change its Played state as well as the play counter and is not logged in the History» (`chapters/user_interface`).
- **Обзорная волна:** «the part of the track that has already been played is **darkened**» (`chapters/user_interface`) — ровно та же идея, что оранжевая/серая заливка на скриншоте AIMP.

**Сбрасывается ли «played» за сессию — да, и это видно в исходнике**, `src/library/dao/trackdao.cpp`:

```
// clear out played information on exit
// crash prevention: if mixxx crashes, played information will be maintained
kLogger.debug() << "Clearing played information for this session";
... query.exec("UPDATE library SET played=0 where played>0")
```

Рядом в схеме отдельно живут `timesplayed` и `last_played_at` (`trackdao.cpp:465-466`, `642-644`). То есть в Mixxx **два разных поля**: сессионный флаг `played` (гаснет при выходе) и накопительный счётчик `timesplayed` + дата последнего проигрывания (не гаснут).

### 4.2 rekordbox (официальный manual 7.1.4)

- Поля отбора трека: «Search for a track by refining with **[BPM], [KEY], [RATING], [COLOR], and [MY TAG]**» (rb7 manual, раздел про сужение поиска; в тексте PDF встречается дважды).
- Колонки настраиваются: «Right-click the column on the header. The column list is displayed… Drag and drop the column on the header to move to the left or right».
- «Проиграно» — настройка `[Coloring of played tracks]`: «After playing the track, the color of the track information in the track list is changed. **You can set to reset the color when quitting/exiting rekordbox.** To reset the color immediately, click [RESET], and then click [OK].»
- История: `[Histories]` — «Use [Histories] to check played tracks and track orders»; в историю попадают треки, игравшие на оборудовании.

### 4.3 Serato DJ Pro

Официальная база знаний Serato (`support.serato.com`, статьи `223364427 Library + Display`, `202538290`, `202310644`) **отдаёт 403** и на WebFetch, и на curl — дословных цитат у меня нет. По сниппетам официальных страниц в выдаче: проигранный и выгруженный трек становится серым или синим (цвет выбирается в SETUP) и попадает в историю; в `Library + Display` есть кнопка `Reset Played Tracks` и чекбокс `Reset Played Tracks on Exit`; треки можно вручную пометить «played / unplayed». **Статус: не подтверждено дословно**, только как направление, совпадающее с rekordbox.

### 4.4 Что из этого имеет смысл для НАШЕГО продукта

Продукт — простой плеер для подготовки миксов, не DJ-станция. Поэтому ниже не решения, а предмет для вопросов (раздел 5). Факты, которые стоит держать в голове:

- Все три DJ-программы разводят **сессионный флаг «проиграно»** и **накопительную статистику**. AIMP делает наоборот: в плейлисте нет «проиграно» вообще, а счётчик живёт в фонотеке. Владелец просил «галочку "проиграно"» — в AIMP такой галочки нет, там галочка значит другое (см. 2.4). Это расхождение нужно снять вопросом, а не догадкой.
- BPM и Key присутствуют и в AIMP (поля `BPM`, `KEY`), и во всех трёх DJ-программах как основные поля отбора. Но AIMP их не показывает в плейлисте по умолчанию.
- Color/Rating в DJ-софте — это способ пометить энергию и настроение; в AIMP аналог — `Mark` (0..5) и `Mood`.
- Cue points есть у Mixxx/rekordbox/Serato, у AIMP в плейлисте их нет; для «простого плеера» это явный кандидат «вне скоупа», но решает владелец.

---

## 5. Вопросы владельцу

Каждый — с одной строкой «зачем спрашивать». Ни один не имеет ответа в источниках.

**Про галочку (главный вопрос раздела)**

1. В AIMP галочка в плейлисте означает «участвует в автопереключении»: снятый трек пропускается при автопереходе, его можно потом разом удалить командой «удалить снятые». Отметки «проиграно» в плейлисте AIMP нет вообще. Тебе нужна именно эта механика AIMP (отсев треков из автоперехода), или нужна другая — «я этот трек уже отслушал и отобрал»?
   *Зачем: от ответа зависит, одно это поле или два разных, и весь сценарий отбора.*
2. Если нужна отметка «отслушал» — она должна быть ручной (я сам ставлю галочку) или автоматической (трек доиграл до конца → пометился)?
   *Зачем: автоматическая требует правил «сколько секунд считается прослушиванием», ручная — нет.*
3. Отметка «проиграно» живёт до перезапуска плеера (как сессия у Mixxx/rekordbox/Serato) или сохраняется навсегда вместе с плейлистом?
   *Зачем: сессионный флаг не требует базы, постоянный требует хранилища и переживания переименований файлов.*
4. Нужна ли кнопка «сбросить все отметки» и «удалить все отмеченные из плейлиста»?
   *Зачем: у AIMP и Serato это отдельные команды; без них отбор превращается в ручную работу.*

**Про поля и колонки**

5. Плейлист делаем колоночным (заголовки, клик по заголовку сортирует), как у Mixxx/rekordbox, или как в AIMP — две строки текста по шаблону + длительность справа?
   *Зачем: это две разные архитектуры UI, переделка потом дорогая.*
6. Кроме длительности и года: нужны ли BPM и тональность (Key)? Они есть в тегах и их читают все DJ-программы; но их надо либо брать из тега, либо считать самим.
   *Зачем: «считать самим» — это анализатор, отдельный объём работы и отдельная библиотека.*
7. Нужна ли цветовая метка трека (как Color в Mixxx — «энергия/настроение») или оценка звёздами (как Mark 0..5 в AIMP)?
   *Зачем: это второй способ отбора помимо галочки; если не нужен — не городим.*
8. Нужен ли счётчик «сколько раз играл» и дата последнего проигрывания отдельно от галочки?
   *Зачем: это уже маленькая база данных, а не просто плейлист-файл.*

**Про волну**

9. На твоём скриншоте волна двухцветная: оранжевая до текущей позиции, серая после — это заливка прогресса, частоты в ней не участвуют (в API AIMP точка волны хранит только пики амплитуды). Когда ты говоришь «ЦВЕТНОЙ waveform», ты имеешь в виду именно такую заливку прогресса, или раскраску по частотам (басы/середина/верх разными цветами, как в Mixxx/Serato)?
   *Зачем: заливка прогресса — это рисование по пикам, раскраска по частотам — это FFT и совсем другая цена.*
10. Волна должна строиться заранее для всех треков плейлиста (чтобы листать мгновенно) или только для текущего при открытии?
    *Зачем: предрасчёт = фоновый анализ и кэш на диске, это заметный кусок работы.*
11. Нужны ли на волне метки (начало/конец, точки входа) или волна только для «увидеть структуру и промотать»?
    *Зачем: метки — это уже DJ-станция, и брифом продукт заявлен как простой плеер.*

**Про сортировку и порядок**

12. Сортировка по длительности — как отдельная команда меню (как в AIMP) или как клик по колонке? И нужна ли ручная перестановка треков мышью с сохранением порядка?
    *Зачем: ручной порядок и сортировка конфликтуют, нужно знать, что главнее.*
13. Нужна ли группировка (по папке/альбому/артисту) со сворачиванием, как на твоём скриншоте AIMP (строка «DJ Antiz  4 / 2:09:34»)?
    *Зачем: на скриншоте она есть, но в списке требований брифа её нет — уточнить, случайность это или требование.*

**Про рабочий процесс**

14. Куда ты перетаскиваешь файлы чаще всего — в Finder, в DAW, в Telegram? И нужно ли при перетаскивании нескольких треков сохранять порядок/нумерацию?
    *Зачем: от приёмника зависит формат перетаскивания, а нумерация требует переименования копий.*
15. Плейлист должен сохраняться в файл между запусками, и если да — в своём формате или в чём-то читаемом (m3u8)?
    *Зачем: отметки и галочки надо где-то хранить; m3u8 их не хранит, свой формат хранит (как AIMPPL4).*
