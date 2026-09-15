# 03. Движок воспроизведения и чтение тегов/обложек

Дата: 2026-09-15. Стенд: macOS 27.0 (build 26A428), Apple Swift 6.3.3, Xcode 26.6, SDK MacOSX26.5, arm64
(`sw_vers`, `swift --version`, `xcodebuild -version`).
Клоны: `clones/<repo>` (`git clone --depth 1`; в этот репозиторий не входят). Замеры и пробы: `probe/`, `tagbench/` (тоже вне репозитория).

Всё, что ниже, получено из исходников клонов, заголовков macOS SDK и собственных прогонов на этой машине.
Где источника нет, стоит «не установлено».

---

## 0. Главный факт, который определяет всё остальное

**macOS 27 из коробки декодирует FLAC, Ogg Opus и Ogg Vorbis.** Проверено двумя способами.

1. Список читаемых контейнеров CoreAudio (`AudioFileGetGlobalInfo(kAudioFileGlobalInfo_ReadableTypes)`,
   мой прогон `probe/probe.swift`, 25 типов):

```
  Oggf  Ogg   [opus,ogg,oga]
  flac  FLAC  [flac]
  MPG3  MPEG Layer 3 [mp3,...]
  m4af  Apple MPEG-4 Audio [m4a,m4r]
  AIFF / AIFC / WAVE / BW64 / RF64 / W64f / adts / caff ...
```
   `afconvert -hf` подтверждает: `'Oggf' = Ogg (.opus, .ogg, .oga)  data_formats: 'opus' 'flac' 'vorb'`,
   `'flac' = FLAC (.flac)`.

2. `AVURLAsset.audiovisualTypes()` содержит `org.xiph.flac`, `org.xiph.ogg-audio`, `public.mp3`,
   `public.aiff-audio`, `com.apple.m4a-audio`, `com.microsoft.waveform-audio`, `public.aac-audio`,
   `com.sony.wave64`.

Живая проба на реальных файлах (`probe/probe2.swift`):

| файл | AVAudioFile | AVAudioPlayer | AVURLAsset.duration |
|---|---|---|---|
| tone.flac (FLAC 44.1/16) | OK, `flac … from 16-bit source` | OK 5.0 c | 5.0 |
| tone.m4a (AAC) | OK | OK 5.0 c | 5.0 |
| tone.wav / tone.aiff | OK | OK | 5.0 |
| beep.oga (Ogg **Vorbis** 24k) | OK, `vorb` | OK 0.2 c | 0.208 |
| telegram \*.ogg (**Opus** 48k) | OK, `opus` | OK 51.0135 c | 51.88 |
| id3v23.mp3 / id3v24.mp3 | OK, `.mp3` | OK 360.0 c | 360.0 |

Подтверждение из чужого кода: SFBAudioEngine README:1-33 — «FLAC, Ogg Opus, and MP3 are natively
supported by Core Audio, however SFBAudioEngine provides its own encoders and decoders for these formats».

Оговорки, которые надо знать:
- Публичной константы `kAudioFileOggType` в SDK **нет** (`AudioFile.h:79-101` — 21 константа, Ogg среди них
  отсутствует; `kAudioFileFLACType = 'flac'` есть). Тип `'Oggf'` существует в рантайме, но недокументирован.
  Через `AVAudioFile`/`AVURLAsset`/`AVAudioPlayer` (определение по UTI/расширению) всё открывается — проверено выше.
  Через `AudioFileOpenURL` надо передавать `0` (пусть CoreAudio сам определит) либо сырое `'Oggf'`.
- `kAudioFormatFLAC = 'flac'` и `kAudioFormatOpus = 'opus'` — публичные константы
  (`CoreAudioBaseTypes.h:431-432`).
- Для Opus длительность у `AVAudioFile` (51.0135 c по фреймам) и `AVURLAsset` (51.88 c) расходится на ~0.9 c —
  разная трактовка pre-skip/granule. Для курсора на волне брать один источник, не смешивать.
- Минимальная версия macOS, с которой появился `'Oggf'`, **не установлена** (в SDK-заголовках константы нет,
  аннотации availability проверить не по чему). Это открытый вопрос для выбора deployment target.
- Формата **OGG Vorbis/Opus на запись** нет: `afconvert -f Oggf -d opus` → `ExtAudioFileSetProperty ('cfmt') failed ('fmt?')`.
  Нам запись не нужна.

---

## (а) Движок воспроизведения

### Таблица кандидатов

| Кандидат | Язык / лиценз. | Последний коммит | ⭐/issues | Форматы | Gapless | Точный seek | Позиция для курсора | macOS в Package.swift | Swift 6.3 / macOS 27 | Вердикт |
|---|---|---|---|---|---|---|---|---|---|---|
| **SFBAudioEngine** (sbooth) | ObjC++/C++/Swift, **MIT** | 2026-09-14 | 706 / 20 | всё CoreAudio + Vorbis, Speex, Musepack, APE, WavPack, Shorten, TTA, DSD, libsndfile | **да**, встроенный (`SFBAudioPlayer.h:39`, `formatWillBeGaplessIfEnqueued:`) | `seek(time:)`, `seek(position:)` 0…1, `seek(frame:)` (`SFBAudioPlayer.h:240-254`) | `playbackPosition` (кадры), `playbackTime`, `progress` (`SFBPlaybackPosition.swift:39`) | `.macOS(.v11)` | **собрал сам: `swift build -c release` → Build complete! (33.55s), exit 0** | **БЕРЁМ** |
| **AVFoundation голый** (AVAudioEngine + AVAudioPlayerNode) | Apple, системный | — | — | см. раздел 0 (FLAC/Opus/Vorbis/MP3/M4A/WAV/AIFF — да) | руками: очередь `scheduleFile`/`scheduleSegment` на один `AVAudioPlayerNode` | `scheduleSegment(from:)` + рестарт ноды | `lastRenderTime`→`playerTime` | системный | да | **РЕЗЕРВ / фундамент** |
| AVAudioPlayer | Apple | — | — | те же | нет (один файл) | `currentTime` (сеттер) | `currentTime` | системный | да | **НЕТ** для главного тракта (нет очереди, нет тапа для эквалайзера/анализа), годится как аварийный запасной |
| AVPlayer | Apple | — | — | те же | нет для локальных плейлистов без `AVQueuePlayer` | `seek(to:toleranceBefore:.zero,after:.zero)` | `addPeriodicTimeObserver` | системный | да | **НЕТ** — это плеер для медиа-стриминга, лишний слой для локального DJ-плеера |
| **AudioKit** | Swift, **MIT** | 2026-07-26 | 11459 / 6 | ровно то же, что CoreAudio: `load(url:)` → `AVAudioFile(forReading:)` (`AudioPlayer.swift:305`) | нет очереди треков; `MultiSegmentAudioPlayer` планирует сегменты на одном `AVAudioPlayerNode` | `seek(time:)` — **относительный** сдвиг, не абсолютный (`AudioPlayer+Playback.swift:80`) | `currentTime`, `currentPosition` 0…1 (`AudioPlayer+Playback.swift:129-135`) | `.macOS(.v11)` | **собрал сам: Build complete! (19.55s), exit 0** | **РЕЗЕРВ** — ничего не даёт сверх AVFoundation по форматам, тащит DSP/MIDI/Sequencing, которые нам не нужны |
| **BASS** (un4seen) | C, **проприетарная, закрытые исходники** | — | — | нативно WAV/AIFF/MP3/OGG + MOD; FLAC только через add-on BASSFLAC, Opus — BASSOPUS | да | да | да | нет SPM | — | **НЕТ.** «BASS is free for non-commercial use… Single Commercial: €950», macOS −40% (un4seen.com/bass.html). Закрытый бинарник + плата, при том что macOS декодирует всё сам |
| **FFmpeg-обёртки**: aural-player (libav*.xcframework), CrescendoKit (CFFmpeg) | — | aural-player 2025-06-22 (MIT), CrescendoKit 2026-08-13 | — | всё, что умеет FFmpeg | реализуется вручную | вручную | вручную | aural-player — Xcode-проект, не SPM | — | **НЕТ** как база. FFmpeg — LGPL 2.1+ с требованием динамической линковки и заменяемости, ~60 МБ бинарей и свой ресемплер ради форматов, которые macOS уже умеет. FFmpegKit ретайрнут (репо архивирован 2025-06-23) |
| **CrescendoKit** (движок Petrichor) | **проприетарный бинарник** | 2026-08-13 | — | FFmpeg-набор | — | — | — | `.macOS(.v14)`, только `.binaryTarget` | — | **НЕТ.** Package.swift:5-9 прямо говорит: «a mixed-license artifact: the **proprietary** Crescendo binary with the TagLib metadata library statically embedded under the MPL 1.1». Исходников нет |

### Почему SFBAudioEngine, а не голый AVFoundation

Что реально даёт SFB поверх системы (по коду, не по README):

1. **Gapless из коробки.** `SFBAudioPlayer.h:39`: «`SFBAudioPlayer` supports gapless playback for audio with
   the same sample rate and number of channels. For audio with different sample rates or channels, the audio
   processing graph is automatically reconfigured». Плюс `- (BOOL)formatWillBeGaplessIfEnqueued:(AVAudioFormat *)format;`
   (`SFBAudioPlayer.h:129-130`) — можно заранее спросить, будет ли стык бесшовным. На голом `AVAudioPlayerNode`
   это пишется руками и это самая грязная часть такого плеера.
2. **Готовый API перемотки под клик по волне.** `seekToPosition:(double)position` — доля 0…1
   (`SFBAudioPlayer.h:249`), ровно то, что даёт клик по waveform. Плюс `seekToFrame:`, `seekToTime:`,
   `supportsSeeking` (`SFBAudioPlayer.h:254-257`) и колбэк `didSeek:` в делегате (`SFBAudioPlayer.h:389-395`).
3. **Готовая отдача позиции для курсора.** `playbackPosition` (`framePosition`/`frameLength`),
   `getPlaybackPosition:andTime:` одним вызовом (`SFBAudioPlayer.h:200-216`), и в Swift —
   `progress: Double?` = `framePosition / frameLength` (`Sources/SFBAudioEngine/SFBPlaybackPosition.swift:39`),
   `current`, `total`, `remaining`. Это буквально контракт для waveform-курсора.
4. **Тот же объект читает теги** — см. раздел (б). Один пакет вместо двух.
5. **Под капотом всё равно `AVAudioEngine`** (`SFBAudioPlayer.h:36-37`: «An audio player using an
   `AVAudioEngine` processing graph for playback», блок `SFBAudioPlayerAVAudioEngineBlock` даёт доступ к самому
   engine). То есть SFB не уводит нас с нативного стека, а надстраивает его — соскочить на голый AVFoundation
   можно в любой момент.
6. **14 видов событий делегата** (`SFBAudioPlayer.h:45-60`): decoding started/complete, rendering
   will start/started/will complete/complete, now playing changed, playback state changed, end of audio,
   seek complete и т.д. — готовые точки, чтобы ставить галочку «проиграно» и двигать курсор.

### Риски SFBAudioEngine

- **Зависимостей много**: 21 пакет в `Package.swift:26-62`, из них 11 — предсобранные `*-binary-xcframework`
  (ogg, flac, opus, vorbis, wavpack, lame, mpc, mpg123, sndfile, tta-cpp) от того же автора. Пакет тянет
  десяток чужих релизов с GitHub; для офлайн/воспроизводимой сборки нужен `Package.resolved` в репо
  (он в клоне есть).
- **LGPL-хвост.** README.md:151-153: «In order to maintain compatibility with the LGPL used by libsndfile,
  mpg123, libtta-cpp, lame, and the Musepack encoder **dynamic linking is required**». Для нашего личного
  инструмента не проблема (xcframework'и и так динамические), но если раздавать бинарник — надо не ломать
  динамическую линковку и приложить тексты лицензий.
- Отключить LGPL-куски выборочно нельзя: все декодеры сидят в одном таргете `CSFBAudioEngine`
  (`Package.swift:64-112`). **Не установлено**, есть ли в проекте флаги сборки «без LGPL».
- Внешний вид API — Objective-C (`NS_SWIFT_NAME` всюду), в Swift это выглядит нормально
  (`AudioPlayer`, `AudioFile`, `AudioMetadata`), но Swift Concurrency/Sendable из коробки нет:
  сборка прошла без ошибок под Swift 6.3, но **строгую изоляцию акторов я не проверял — не установлено**.

---

## (б) Теги, свойства и обложки

### Ключевой результат: `AVAsset.commonMetadata` для года НЕ годится

Прогон `probe/probe2.swift` на файлах, которые я собрал сам с контролируемыми тегами
(генератор: `probe` — ID3v2.3 с TIT2/TPE1/TALB/**TYER=1994**/TDAT=1503/APIC; ID3v2.4 с
**TDRC=1994-03-15**/TDOR=1991; FLAC с Vorbis comments **DATE=1994-03-15**/ORIGINALDATE/RATING +
METADATA_BLOCK_PICTURE; M4A с **©day=1994-03-15**):

| формат | что вернул `commonMetadata` | что вернул `metadata` (сырой) |
|---|---|---|
| MP3 ID3v2.3 | title, **creationDate = `id3/TDAT` = «1503»** (это день/месяц, а не год!), albumName, artist, artwork | TIT2, TPE1, TALB, **TYER=1994**, TDAT=1503, APIC |
| MP3 ID3v2.4 | title, albumName, artist, artwork — **даты нет вообще** | TIT2, TPE1, TALB, **TDRC=1994-03-15**, TDOR=1991, APIC |
| FLAC | **0 элементов** (ни названия, ни артиста, ни обложки) | `vorb/TITLE`, `vorb/ARTIST`, `vorb/ALBUM`, **`vorb/DATE=1994-03-15`**, `vorb/ORIGINALDATE`, `vorb/RATING`, `vorb/METADATA_BLOCK_PICTURE` |
| M4A | title, albumName, artist, software — **даты нет** | `itsk/©nam`, `itsk/©ART`, `itsk/©alb`, **`itsk/©day=1994-03-15`**, `itsk/©too` |

Выводы:
1. `AVMetadataKey.commonKeyCreationDate` на MP3 ID3v2.3 отдаёт **TDAT (ДДММ)**, а не TYER. Это ловушка:
   в плейлисте появится «год 1503».
2. На ID3v2.4, FLAC и M4A commonKey даты нет вовсе.
3. На **FLAC `commonMetadata` пуст полностью** — придётся вручную разбирать keySpace `vorb`.
4. Значит: если строить на AVFoundation, нужно писать свой маппер на три keySpace (`org.id3`, `vorb`, `itsk`)
   и самому знать про TYER/TDRC/TDOR/DATE/ORIGINALDATE/©day. Это ровно та работа, которую нам делать не надо.

Косвенное подтверждение из чужого кода: Petrichor (MIT, 1676⭐, коммит сегодня) для года держит регулярку
по строке даты — `Petrichor/Core/Metadata/MetadataMapping.swift:14-27`, `year(fromDateString:)`,
паттерн `\b(19|20)\d{2}\b`. То есть год в реальном мире достают из произвольной строки даты, а не из «поля год».

### TagLib решает это за нас

`TagLib::Tag::year()` нормализует год во всех четырёх случаях. Проверено прогоном
`tagbench/bench.cpp` на тех же файлах: сумма `year()` по 4 тегированным файлам = 7976 = 1994 × 4
(ID3v2.3 TYER, ID3v2.4 TDRC, FLAC DATE, M4A ©day).

Механика, по исходникам TagLib 2.3.2 (`clones/CXXTagLib`):
- ID3v2.3 → 2.4 конвертация фреймов на чтении:
  `Sources/taglib/mpeg/id3v2/id3v2framefactory.cpp:544-547` — `frameConversion3 { ("TORY","TDOR"), ("TYER","TDRC"), ("IPLS","TIPL") }`.
  ID3v2.2 → 2.4: там же `:498` `("TOR","TDOR")`, `:520` `("TYE","TDRC")`.
  То есть **TYER и TORY автоматически становятся TDRC и TDOR** ещё до того, как мы их увидим.
- Лицензия TagLib — **двойная**: LGPL 2.1 **или** MPL 1.1 (шапка каждого файла, напр.
  `Sources/taglib/tag.cpp:6-23`: «Alternatively, this file is available under the Mozilla Public License
  Version 1.1»). Для закрытого приложения берём ветку MPL 1.1 — статическая линковка разрешена,
  копилефт только на изменённые файлы TagLib.

### Как это выглядит в SFBAudioEngine

SFB бандлит TagLib через `sbooth/CXXTagLib` (`Package.swift:37` — `.package(url: ".../CXXTagLib", from: "2.3.2")`,
таргет-продукт `taglib` подключён к `CSFBAudioEngine` в `Package.swift:75`). CXXTagLib — TagLib 2.3.2,
коммит 2026-09-10 («Update TagLib to version 2.3.2»).

Что даёт API (`Sources/CSFBAudioEngine/include/SFBAudioEngine/SFBAudioMetadata.h`):

- `title`, `artist`, `albumTitle`, `albumArtist`, `genre`, `comment` — `:129-138`
- **`releaseDate` (NSString)** — `:148`
- `trackNumber`/`trackTotal`, `discNumber`/`discTotal`, `composer`, `bpm`, `rating` — `:171-172` и далее
- `attachedPictures` (`NSSet<SFBAttachedPicture *>`), `attachedPicturesOfType:` — `:269-282`

Свойства (`SFBAudioProperties.h:17-62`): `formatName`, `frameLength`, `channelCount`, `bitDepth`,
**`sampleRate`**, **`duration`** (сек), **`bitrate`** (KiB/s). Ровно то, что нужно колонкам плейлиста.

Как заполняется год по форматам (это важно, потому что реализации разные):
- ID3v2: `SFBAudioMetadata+TagLibID3v2Tag.mm:43-58` — `releaseDate` берётся из фрейма **`TDRC`**
  (а TYER туда попадает автоматически конвертацией TagLib, см. выше), плюс `TDOR` разбирается отдельно.
- Общий путь для всех тегов: `SFBAudioMetadata+TagLibTag.mm:22-25` — `if (auto year = tag->year(); year != 0)
  self.releaseDate = @(year).stringValue;` — то есть fallback на нормализованный TagLib-год.
- Vorbis comments (FLAC/Ogg): `SFBAudioMetadata+TagLibXiphComment.mm`, MP4: `…+TagLibMP4Tag.mm`,
  APE: `…+TagLibAPETag.mm`, ID3v1: `…+TagLibID3v1Tag.mm` — по файлу на формат тега.
- MP3-путь целиком: `Sources/CSFBAudioEngine/Metadata/SFBMP3File.mm:64-135` — открывает
  `TagLib::MPEG::File`, читает APE + ID3v1 + ID3v2, свойства через
  `sfb::addAudioPropertiesToDictionary` (`AddAudioPropertiesToDictionary.mm:12-31` → duration, channels,
  sampleRate, bitrate), и отдельно подменяет `frameLength` на `xingHeader()->totalFrames()`, если Xing есть
  (`SFBMP3File.mm:113-115`).

### Скорость сканирования 2–5 тысяч файлов (мои замеры)

Корпус: 2000 копий MP3 3 МБ с ID3v2.3 и Xing/Info-заголовком (создан и удалён в `corpus`).
Второй корпус: 300 копий того же MP3 с **затёртым** Xing/Info (эмуляция «VBR без Xing»).
Замеры — `tagbench/bench` (C++ поверх TagLib) и `probe/scan` (Swift/AVFoundation).

| способ | что читает | 2000 файлов с Xing | 300 файлов без Xing | экстраполяция на 5000 |
|---|---|---|---|---|
| **TagLib `FileRef`, ReadStyle=Average** (теги + duration + bitrate + год) | заголовок + Xing; без Xing — первый и последний кадр | 0.399 c холодно / **0.081 c** тепло = **0.04–0.20 мс/файл** | 0.017 c = **0.056 мс/файл** | **0.2–1.0 c** |
| TagLib ReadStyle=Fast | то же, без оценки VBR | 0.080 c | — | ~0.2 c |
| TagLib ReadStyle=Accurate | то же | — | 0.021 c (0.069 мс/файл) | ~0.35 c |
| **AVURLAsset** `load(.duration)` + `load(.metadata)` | контейнер + все теги | 1.30 / 1.23 c = **0.62–0.65 мс/файл** | 0.219 c = 0.73 мс/файл | **3.1–3.7 c** |
| **AVAudioFile** `.length` (только длительность, тегов нет) | — | 0.341 c = 0.17 мс/файл | **1.567 c = 5.22 мс/файл** ⚠️ | **0.9 c с Xing / 26 c без Xing** |

Ответ на вопрос брифа «что читает только заголовок, а что декодирует весь файл»:

- **Ничто из проверенного не декодирует весь файл.** Даже `Accurate` у TagLib для MP3 не сканирует все кадры.
- **TagLib** на MP3: если есть Xing/VBRI — длительность и битрейт берутся прямо из заголовка, читается
  один кадр (`mpegproperties.cpp:161-180`). Если Xing нет и это не ADTS — TagLib **считает файл CBR**:
  битрейт = битрейт первого кадра, длина = `streamLength * 8 / bitrate`
  (`mpegproperties.cpp:232-260`). Читаются первый и последний кадр, ничего больше. Быстро,
  но **для настоящего VBR без Xing длительность будет неверной** — это цена, а не скорость.
  Полный обход кадров TagLib делает только для ADTS (`mpegproperties.cpp:196-230`), и даже там
  `Average` останавливается, когда средний размер кадра стабилен 10 кадров подряд.
- **AVAudioFile.length** — единственное узкое место: без Xing ему приходится строить packet table,
  и цена растёт с 0.17 мс до **5.2 мс на файл** (в 30 раз). На 5000 файлов это 26 секунд против секунды.
  Для сканирования папки `AVAudioFile` использовать нельзя.
- **AVURLAsset** дал корректные 74.99 c на файле без Xing (TagLib — 75.02 c) за 0.73 мс. То есть
  AVURLAsset — хороший арбитр для подозрительных MP3.

Это ровно та стратегия, которую применяет Petrichor:
`Petrichor/Core/Metadata/MetadataMapping.swift:55-83`, `validatedDuration(_:codec:url:sourceName:)` —
комментарий в коде: «TagLib-backed readers can report unreliable MPEG durations for files with missing
VBR headers. Only pay the AVFoundation cost when the value is obviously suspicious», и дальше
падение на `AVURLAsset.load(.duration)` только если `duration <= 0 || isNaN || isInfinite || < 1.0`.

### Таблица кандидатов на теги

| Кандидат | Лиценз. | Последний коммит | ⭐/issues | Форматы | Год | Обложка | duration/bitrate/sr | macOS в Package.swift | Вердикт |
|---|---|---|---|---|---|---|---|---|---|
| **SFBAudioEngine `AudioFile`/`AudioMetadata`** (TagLib 2.3.2 внутри) | MIT + TagLib LGPL2.1/**MPL1.1** | 2026-09-14 | 706 / 20 | MP3, FLAC, Ogg (Vorbis/Opus/Speex/FLAC), MP4/M4A, AIFF, WAVE, APE, WavPack, Musepack, TTA, DSF/DSDIFF, Shorten, модули | **да, единый `releaseDate`** для TYER/TDRC/DATE/©day | `attachedPictures`, `attachedPicturesOfType:` | да, `SFBAudioProperties` | `.macOS(.v11)` | **БЕРЁМ** |
| AVAsset / AVURLAsset metadata | системный | — | — | всё, что декодирует CoreAudio | **нет единого ключа**: commonKey creationDate врёт (TDAT) или отсутствует; нужен свой маппер по `org.id3` / `vorb` / `itsk` | на FLAC commonKey artwork **отсутствует**, нужен разбор `vorb/METADATA_BLOCK_PICTURE` | duration — да; bitrate — только `estimatedDataRate` у трека, на FLAC/WAV/AIFF/Ogg вернул **0.0** | системный | **РЕЗЕРВ** — как арбитр длительности для «подозрительных» MP3 |
| **sbooth/CXXTagLib** (чистый TagLib для SPM) | LGPL2.1 / MPL1.1 | 2026-09-10 | 12 / 0 | все форматы TagLib | да | да | да | platforms не заданы (собирается везде) | **РЕЗЕРВ.** Работает (я собрал: `swift build -c release` → 15.13 s), **но напрямую из Swift API TagLib не вызывается**: `TagLib::FileRef(std.string, …)` не биндится (`error: cannot convert value of type 'std.string' … to expected argument type 'OpaquePointer'`), `TagLib.AudioProperties` не импортируется как тип. Нужен свой C++/ObjC++ шим — это и есть то, что уже написано в SFBAudioEngine |
| Anywhere-Music-Player/**SwiftTagLib.cpp** | MPL-2.0 | 2026-01-13 | 35 / 4 | AIFF, DSDIFF, DSF, FLAC, MP3, MP4, APE, Musepack, OggFLAC/Opus/Speex/Vorbis, TTA, WAVE, WavPack | да (устройство скопировано с SFB) | да | да | `.macOS(.v14)`, `.iOS(.v17)` | **НЕТ.** В пакете только `.binaryTarget` на три `.xcframework` (`Package.swift:22-26`), исходников в репо нет; TagLib внутри — v2.0.2, старее нашей 2.3.2; автор сам пишет в `Differences-from-SFBAudioEngine…md`: «This file is somewhat outdated!» |
| Phisto/**swift-taglib** | **LGPL-3.0** | 2025-05-24 | 5 / 1 | TagLib 2.0.2 | да | да | да | `.macOS(.v13)`, tools 6.1, Cxx-интероп | **НЕТ.** LGPL-3.0 на обёртке хуже, чем родная двойная лицензия TagLib; год без обновлений |
| **ID3TagEditor** (chicio) | MIT | 2026-01-17 | 274 / 11 | **только MP3** (`Source/Mp3`) | `recordingYear`, `recordingDateTime` (`Source/Frame/FrameName.swift:50-53`) | `ID3FrameAttachedPicture` | **нет** (нет разбора аудио-свойств вообще) | platforms не заданы, tools 6.0 | **НЕТ как ридер библиотеки.** Резерв только если понадобится *писать* ID3 в MP3 без TagLib. POPM/PCNT **не поддерживает** (в `Source/` нет ни одного упоминания POPM/PCNT/Popularimeter) |
| CrescendoKit (TagLib внутри) | проприетарный бинарник | 2026-08-13 | — | — | — | — | — | `.macOS(.v14)` | **НЕТ** — см. (а) |

---

## (в) Где хранить «проиграно» и play count

### Тег в файле (POPM / PCNT / Vorbis `RATING`)

Что реально доступно:
- TagLib читает и пишет **POPM** (rating 0–255): `SFBAudioMetadata+TagLibID3v2Tag.mm:81-86` (чтение,
  `PopularimeterFrame::rating()`), `:386-391` (запись, `removeFrames("POPM")` + `setRating`).
- В Vorbis comments и APE SFB кладёт это в ключ **`RATING`**:
  `SFBAudioMetadata+TagLibXiphComment.mm:76` и `:208`, `SFBAudioMetadata+TagLibAPETag.mm:68` и `:214`.
- В публичном API SFB это единственное поле — **`rating` (`NSNumber`)**, `SFBAudioMetadata.h:171-172`.
- **`PCNT` (play counter) в SFBAudioEngine не поддерживается вообще** — grep по `Sources/` даёт ноль
  совпадений `PCNT`/`PlayCount`/`playCount`. Счётчик POPM (`counter`) тоже не читается: код берёт только
  `popularimeter->rating()`.

Нормализация POPM, если понадобится: Petrichor делает 1–255 → 1–5 порогами 31/95/159/223
(`Petrichor/Core/Metadata/MetadataMapping.swift:31-55`, `normalizedRating(fromRaw:)`).

Минусы записи в файл, по фактам:
- **Каждая отметка «проиграно» = перезапись аудиофайла.** Для 2–5 тысяч треков и DJ-сценария (слушаешь
  подряд, отмечаешь) это постоянный ввод-вывод по многомегабайтным файлам, смена mtime (ломает инкрементальный
  скан по дате), риск повредить файл при сбое.
- У нас смешанные форматы: ID3v2 (POPM), Vorbis (`RATING`), MP4 (`rate`/`rtng`) — три разных механизма,
  и «счётчика проигрываний» из них нативно нет нигде, кроме `PCNT`, который SFB не читает.
- Из коробки писать `PCNT` нечем: ни SFBAudioEngine, ни ID3TagEditor его не умеют. Пришлось бы лезть в
  TagLib напрямую через свой C++-шим.

Плюс ровно один: метка едет вместе с файлом в другую программу/на другую машину.

### Своя база

| Вариант | Лиценз. | Последний коммит | ⭐/issues | macOS | Вердикт |
|---|---|---|---|---|---|
| **GRDB.swift** (SQLite) | MIT | 2026-08-08 | 8647 / 15 | `.macOS(.v10_15)`, tools 6.1, `swiftLanguageModes: [.v6]`, FTS5 включён (`Package.swift:16`) | **БЕРЁМ** |
| SwiftData | Apple | — | — | `@available(macOS 14, …)` (SwiftData.swiftinterface:12) | **РЕЗЕРВ.** Плюс — ноль зависимостей; минусы по производительности на 5k строк и по фоновому сканированию **не установлены**, я их не мерил |
| Core Data | Apple | — | — | системный | **НЕТ** — при живом SwiftData/GRDB нет причин |
| plist/JSON рядом с приложением | — | — | — | — | **НЕТ** — при 2–5k треков нужен индексированный поиск и сортировка по длительности/году |

Прецедент по коду: **Petrichor хранит именно в SQLite через GRDB**. В схеме есть колонки
`play_count` и `last_played_date` с индексами под конкретные экраны:
`Petrichor/Managers/Database/DatabaseMigration.swift:236-256` — `idx_tracks_last_played_date`,
`idx_tracks_duplicate_last_played`, `idx_tracks_duplicate_play_count` (комментарий в коде: «Fresh Music
selects play_count = 0 at random; without this it scans»). Обновление — одним апдейтом:
`Petrichor/Managers/Database/DMTrackUpdate.swift:22-28`, `updatePlayingTrackMetadata(trackId:playCount:lastPlayedDate:)`.
Зависимости Petrichor (`.pbxproj`): CrescendoKit, **groue/GRDB.swift**, Sparkle.

### Рекомендация по (в)

**Своя SQLite-база на GRDB — основное хранилище.** Ключ — не путь (файлы переезжают), а пара
(`inode`+`device`) или хеш первых N КБ + размер; путь хранить как атрибут. Туда же кладём кэш waveform
(самое дорогое, что мы считаем) и кэш обложек, чтобы не перечитывать теги при каждом запуске.

**Запись в тег — опциональный экспорт по кнопке, не рабочий режим.** Если владелец захочет, чтобы отметки
ехали в другую программу: писать `rating` через `SFBAudioMetadata.rating` (POPM / Vorbis `RATING`) пакетно
и только по явной команде. `PCNT` не трогать — нечем.

---

## Рекомендуемая связка

```
Playback   : SFBAudioEngine.AudioPlayer         (MIT, gapless, seek(position:), playbackPosition)
Fallback   : AVAudioEngine + AVAudioPlayerNode  (если SFB где-то не подойдёт — тот же стек этажом ниже)
Tags       : SFBAudioEngine.AudioFile/AudioMetadata (TagLib 2.3.2 внутри) — title/artist/album/releaseDate/
             attachedPictures/duration/bitrate/sampleRate
Duration   : TagLib из SFB; для MP3 с подозрительной длительностью (<=0, NaN, <1 c) — арбитраж через
             AVURLAsset.load(.duration), как в Petrichor
Library DB : GRDB.swift (SQLite) — played/playCount/lastPlayed + кэш waveform и обложек
Не берём   : BASS (платно, закрыто), FFmpeg-обёртки (LGPL-хвост ради форматов, которые macOS уже умеет),
             CrescendoKit (проприетарный бинарник), ID3TagEditor (MP3-only, нет свойств), AudioKit (лишний слой)
```

Ожидаемая скорость: скан 5000 файлов (теги + год + длительность + битрейт) — **меньше секунды** на тёплом
кэше, порядка 1–2 с на холодном. Обложки и waveform считать лениво, после того как список уже показан.

---

## Открытые вопросы владельцу

1. **Минимальная версия macOS.** Ogg/Opus/Vorbis нативно работают на macOS 27 (проверено), но когда это
   появилось — не установлено, публичной константы для контейнера Ogg в SDK нет. Если поставить
   deployment target = macOS 26 или 15, .opus/.ogg могут не открыться, и тогда нужен SFB-декодер Ogg
   (он у SFB свой, независимый от системы). Ставим `macOS 26+`, `macOS 27+` или закладываем SFB-декодеры
   и не зависим от версии?
2. **Раздача приложения.** Только для себя или отдавать людям? От этого зависит, надо ли возиться с
   LGPL-требованиями (libsndfile/mpg123/lame внутри SFBAudioEngine — динамическая линковка обязательна,
   плюс тексты лицензий в About).
3. **Отметка «проиграно» — куда именно.** По умолчанию делаю в своей базе (как Petrichor). Нужна ли
   дополнительно запись рейтинга в сам файл (POPM), чтобы отметки было видно в AIMP/foobar/DAW? Учти:
   это перезапись файла и смена даты изменения.
4. **Какие форматы реально лежат в библиотеке.** Если там есть APE, WavPack, Musepack, TTA, DSD —
   SFBAudioEngine закрывает всё; если только MP3/FLAC/WAV/AIFF/M4A — можно рассмотреть и голый AVFoundation.
   Прислать вывод команды по папке с треками?

---

## Приложение: как воспроизвести замеры

- `probe/probe.swift` — список читаемых типов CoreAudio и `AVURLAsset.audiovisualTypes()`.
- `probe/probe2.swift` — открытие файла тремя API + дамп `commonMetadata` и `metadata`.
- `probe/scan.swift` — сканер папки (`asset` | `audiofile`).
- `tagbench/bench.cpp` — сканер на TagLib; сборка:
  `swift build -c release` в `tagbench` (тянет локальный `../clones/CXXTagLib`), затем
  `xcrun --sdk macosx clang++ -std=c++20 -O2 bench.cpp $(find .build -name '*.o') -I<taglib includes> -lz -o bench`.
- Тестовые корпуса (`corpus`, `corpus2`) создавались и удалялись скриптами из отчёта;
  сейчас их на диске нет.
