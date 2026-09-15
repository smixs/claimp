# 02. Крупный цветной waveform всего трека (обзорная волна)

Дата: 2026-09-15 09:40. Тулчейн проверки: `Apple Swift version 6.3.3`, target `arm64-apple-macosx28.0`, Xcode 26.6, macOS 27.0 (вывод `swift --version` / `sw_vers`).
Клоны: `clones/<repo>` (`git clone --depth 1`; в этот репозиторий не входят). Все `path:line` ниже - внутри клонов.

Задача: обзорная волна всего трека (как AIMP на `research/aimp-reference.png`: сыгранное оранжевым, несыгранное серым),
желательно RGB-окраска по частотам (Serato/rekordbox). Прогресс + клик для перемотки. Треки 30-60 минут, 320 kbps MP3 и FLAC.

---

## 1. Таблица кандидатов

| Кандидат | Платформы (Package.swift) | UI-слой | Рендер | Цвет по частотам | Прогресс / клик | Собирается под macOS 27 / Swift 6.3 | Последний коммит | Лицензия | Вердикт |
|---|---|---|---|---|---|---|---|---|---|
| **aural-player** (модуль `Source/UI/Waveform`) | Xcode-проект, macOS-only приложение (Package.swift нет) | AppKit `NSView` | CoreGraphics / `CAShapeLayer` + маска | Нет (2 цвета: сыгранное/несыгранное) | **Да, оба** | Не проверял (не SPM-пакет) | 2025-06-22, репо **archived** | MIT | **Берём как основу** (вендорим модуль) |
| **DSWaveformImage** | `.iOS(.v15)`, `.macOS(.v12)` | SwiftUI + UIKit-вьюхи; на macOS - только рисование в `NSImage`/`Canvas` | CoreGraphics (`CGContext`), SwiftUI `Canvas` | **Да**, `.spectralTint(low:high:)` - 2-цветный градиент по спектральному центроиду | Нет ни того ни другого | **Да** (`Build complete! (8.23s)`) | 2026-05-17 | MIT | **Берём частично** (идея + код спектрального анализа), см. риски |
| **AudioKit/Waveform** | `.macOS(.v11)`, `.iOS(.v14)` | SwiftUI `NSViewRepresentable` → `MTKView` | **Metal** | Нет (один `float4 color`) | Нет (в демо есть минимап-драг) | **Да** (`Build complete! (12.04s)`, только warnings) | 2024-10-14 (GitHub `pushed_at` 2026-06-26) | MIT | **Нет** - грузит весь файл в RAM |
| **AudioKitUI** (`AudioFileWaveform`) | `.macOS(.v12)`, `.iOS(.v15)` | SwiftUI `Shape` | CoreGraphics (SwiftUI Path) | Нет (один `Color`) | Нет | **Да** (`Build complete! (38.38s)`) | 2026-04-15 | MIT | **Нет** - грузит весь файл в RAM, тянет AudioKit+Controls |
| **FDWaveformView** | `.iOS(.v15)`, `.visionOS(.v1)` - **macOS нет** | UIKit | CoreGraphics | Нет | Есть (iOS-жесты) | **Нет**: `error: no such module 'UIKit'` | 2026-05-05 | MIT | **Нет** - iOS-only (но это предок кода Aural) |
| **SFBAudioEngine** | `.macOS(.v11)`, `.iOS(.v15)`, `.tvOS(.v15)` | - | - | - | - | Не собирал (не нужен для этой задачи) | 2026-09-14 (живой) | MIT | **Waveform-компонента нет** - см. п.2 |
| **WaveformKit** (GRimAce11) | `.iOS(.v17)`, `.macOS(.v14)` | SwiftUI | SwiftUI `Canvas` | Нет (played/unplayed + градиенты) | **Да, оба** (`onSeek`, DragGesture) | **Да** (`Build complete! (6.72s)`) | 2026-05-19 | MIT | **Резерв** - хороший декодер и кэш, но 5 звёзд, один автор |
| **pixlwave/Waveform** | `.iOS(.v14)` только | SwiftUI | - | - | - | Не собирал (macOS в манифесте нет) | 2024-02-29 | (LICENSE есть) | **Нет** - iOS-only |
| **Cog** | Xcode-проект macOS | AppKit | - | - | - | - | 2026-09-09 | **GPL-2** | **Нет** - обзорной волны в проекте нет (см. п.2), плюс GPL |
| **EZAudio** | - | NSView/UIView | CoreGraphics | Нет | - | - | README: «EZAudio has recently been **deprecated** in favor of AudioKit» | NOASSERTION, 196 открытых issues | **Нет** |
| **Mixxx** | C++/Qt | - | OpenGL/GLSL | **Да, эталон алгоритма** | - | - | живой | GPL-2 | **Нет как код**, **да как референс алгоритма** |

Данные GitHub API (`gh api repos/<repo>`) на 2026-09-15:
DSWaveformImage 1264★, 0 issues; AudioKit/Waveform 264★, 5; FDWaveformView 1307★, 5; AudioKitUI 261★, 15;
SFBAudioEngine 706★, 20; WaveformKit 5★, 0; aural-player 1074★, 13, **`"archived": true`**; EZAudio 4979★, 196, лицензия NOASSERTION.

---

## 2. Что проверено по коду (утверждения с опорой)

### aural-player - готовый модуль обзорной волны под AppKit

Модуль `Source/UI/Waveform` (1764 строки Swift, MIT) - это ровно то, что нарисовано на скриншоте AIMP:

- Два слоя + маска прогресса: базовый слой рисуется `systemColorScheme.inactiveControlColor`
  (`View/WaveformView.swift:238`), копия слоя - `activeControlColor` (`:320`), и маска шириной `imgWidth * progress`
  (`:326`) открывает «сыгранную» часть. `progress` - свойство 0…1 с клампом (`:135-148`).
- Клик = перемотка: `NSClickGestureRecognizer` (`View/WaveformView+GestureHandling.swift:44`),
  `percentage = tapLocation.x * 100 / bounds.width` → `playbackOrch.seekTo(percentage:)` (`:97-101`).
  Горизонтальный скролл тоже сеет (`:86-88`).
- Декодер потоковый, память константная: `AVAudioFile.read(into: pcmBuffer)` кусками
  `waveformDecodingChunkSize = 44100 * 10` (10 секунд, `RenderOperation/Decoders/WaveformDecoderProtocol.swift:15`),
  копирование через `cblas_scopy` (`Decoders/AVFWaveformDecoder.swift:75`).
- Даунсемплинг на Accelerate: `vDSP_vsmul` → `vDSP_vabs` → `vDSP_vdbcon` (в дБ) → `vDSP_vclip` до шумового пола −50 дБ
  → `vDSP_desamp` с FIR-усреднением (`RenderOperation/WaveformRenderOperation+Analysis.swift:254-278`, фильтр строится на `:56`).
- Второй декодер - FFmpeg (`Decoders/FFmpegWaveformDecoder.swift`), выбор по типу файла:
  `isNativelySupported → AVFWaveformDecoder`, иначе `FFmpegWaveformDecoder` (`View/WaveformView+FileIO.swift:64-69`).
- Кэш на диске: ключ (файл, размер картинки), данные - JSON с `[[Float]]`
  (`Caching/WaveformView+Caching.swift:67-87`, `Caching/WaveformCacheEntry.swift:69-72`), LRU по `lastOpenedTimestamp`.
- Отмена в процессе: `guard !isCancelled` в цикле чтения (`WaveformRenderOperation+Analysis.swift:92`), `NSOperation`.
- Прямо в коде указан источник: «This is based on ``FDWaveformView``» (`View/WaveformView.swift:25-27`).

Что мешает: репо **архивировано** 2025-06-22 (GitHub API), модуль завязан на глобальные объекты приложения.
Замер: 19 разных внешних символов - `player.`(8), `colorSchemesManager`(7), `redraw()`(6), `systemColorScheme`(5),
`FloatPointer`(4), `ConcurrentMap`(4), `ConcurrentArray`(3), `increment()`(3), `ExclusiveAccessSemaphore`(2),
`EventMonitor`(2), плюс по одному `playbackOrch`, `FilesAndPaths`, `GestureHandler`, `Destroyable`,
`System.numberOfActiveCores`, `appPersistentState`, `deepCopy`, `fastMax`, `isNativelySupported`/`isSupportedAudioFile`.
Все - тонкие утилиты, заменяются своими за несколько часов.

Слабое место кэша: ключ включает **размер картинки** (`lookUpCache(forFile:matchingImageSize:)`,
`Caching/WaveformView+Caching.swift:89-91`), поэтому при ресайзе окна волна пересчитывается с нуля
(`viewDidEndLiveResize` → `resetState` + `analyzeAudioFile`, `View/WaveformView.swift:198-204`). Это чинится:
кэшировать 3840-4096 колонок один раз и ресемплить под ширину (см. п.5).

### DSWaveformImage - единственный из пакетов, кто умеет цвет по частотам

- `Waveform.Style.spectralTint(low: DSColor, high: DSColor)` - цвет колонки интерполируется между `low`
  (бас) и `high` (верх) по нормализованному спектральному центроиду
  (`Sources/DSWaveformImage/WaveformImageTypes.swift:189-195`).
- Анализ: `WaveformAnalyzer.analyze(fromAudioAt:count:bandsPerOctave:minFrequency:...)` возвращает
  `SpectralAnalysis { amplitudes, spectralCentroids }` (`Sources/DSWaveformImage/WaveformAnalyzer.swift:106-133`).
  По умолчанию `bandsPerOctave: 4`, `minFrequency: 50`.
- Чтение PCM: `AVAssetReader` + `AVAssetReaderTrackOutput` (`WaveformAnalyzer.swift:77,116,177`),
  выходной формат - **16-bit int, interleaved** (`WaveformAnalyzer.swift:507-516`), даунсемплинг `vDSP_desamp` (`:376`).
- Есть macOS-рисовалка `waveformImage(from:with:renderer:position:)` → `NSImage`
  (`Sources/DSWaveformImage/WaveformImageDrawer+macOS.swift:11-27`) и SwiftUI `WaveformView` с macOS 12+
  (`Sources/DSWaveformImageViews/SwiftUI/WaveformView.swift:4`). Есть тесты (4 файла в `Tests/`).

**Чего нет:** прогресса и перемотки. `grep -rni "progress|playhead|seek|onTap" Sources/` - ноль совпадений.

**Риски по скорости на 60-минутном треке (по коду, не по замеру):**
1. На каждые 4096 сэмплов создаётся новый объект `TempiFFT`, а его `init` вызывает `vDSP_create_fftsetup`
   и `deinit` - `vDSP_destroy_fftsetup` (`Sources/DSWaveformImage/TempiFFT.swift:107,124-125`).
   Для часа при 44.1 кГц это ~38 800 создаваемых и уничтожаемых FFT-setup'ов.
2. Все объекты `TempiFFT` копятся в массиве `ffts` до конца файла (`WaveformAnalyzer.swift:381,397`) -
   память растёт линейно по длине трека.
3. Внутри цикла FFT - `processingBuffer.removeFirst(samplesPerFFT)` (`WaveformAnalyzer.swift:404`),
   то есть сдвиг массива на каждой итерации (квадратичное поведение на большом буфере).
Насколько это критично в секундах - **не установлено**, замера на 60-минутном файле я не делал (приложение не строим).

### AudioKit/Waveform (Metal) - красиво, но не про длинные треки

- Metal-пайплайн честный: `MTKView` + `NSViewRepresentable` для macOS (`Sources/Waveform/Waveform.swift:7-65`),
  шейдер с фичерингом краёв (`Sources/Waveform/Waveform.metal:42-73`).
- Цвет ровно один: `struct Constants { float4 color; }` (`Waveform.metal:38-40`, `Sources/Waveform/Renderer.swift:11-21`).
- Вход - `SampleBuffer(samples: [Float])`, то есть **весь трек в оперативке**
  (`Sources/Waveform/SampleBuffer.swift:6-12`). Загрузка - `AVAudioFile.toAVAudioPCMBuffer()` с
  `frameCapacity: AVAudioFrameCount(length)` (`Sources/Waveform/AVAudio+FloatData.swift:41`), затем
  поэлементный Swift-цикл `result[channel][sampleIndex] = ...` (`:27-32`).
- Сверх того `makeBuffers` строит пирамиду mip-уровней, копируя массив дважды (min и max) и деля пополам до 2
  (`Sources/Waveform/Renderer.swift:160-176`), то есть суммарно ещё ~4× от исходного массива в MTLBuffer'ах.
Арифметика: 60 мин × 44100 × 2 канала × 4 байта ≈ 1.27 ГБ только на исходные сэмплы. **Дисквалификация.**

### AudioKitUI - та же болезнь

`AudioFileWaveform` → `AudioHelpers.getRMSValues` (`Sources/AudioKitUI/Visualizations/AudioFileWaveform.swift:17`)
→ `AudioHelpers.getRMSValues(url:windowSize:)` (`Sources/AudioKitUI/Helpers/AudioKitUIHelpers.swift:78-87`)
→ `loadAudioSignal(audioURL:)` из AudioKit 5.7.2, который делает
`AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(file.length))` и `file.read(into: buffer)` целиком
(`.build/checkouts/AudioKit/Sources/AudioKit/Internals/Utilities/AudioKitHelpers.swift:353-368`).
Плюс `createRMSAnalysisArray` копирует каждое окно через `Array(signal[start..<end])`
(`AudioKitUIHelpers.swift:105-118`). Резолвится AudioKit 5.7.2 + Controls 1.1.4 (`Package.resolved`).

### SFBAudioEngine - waveform там нет

`grep -rli waveform Sources/` даёт только упоминания формата WAVE, например
`Sources/CSFBAudioEngine/include/SFBAudioEngine/SFBAudioEncoder.h:425: /// MS WAVE with WAVEFORMATEX`.
Публичные заголовки: `SFBAudioDecoder.h`, `SFBAudioPlayer.h`, `SFBReplayGainAnalyzer.h` и т.п. - визуализации нет.
Это кандидат в **декодеры** (FLAC, APE, WavPack, Musepack, Shorten, TrueAudio - папка `Decoders/`), не в рендер. Репо живое (коммит 2026-09-14).

### Cog - обзорной волны нет

В `Visualization/` только `SpectrumViewCG/SpectrumViewSK/SCView/SpectrumWindowController` - реал-тайм спектроанализатор.
`find . -ipath '*waveform*' -not -path './Frameworks/*' -not -path './Plugins/*'` - пусто.
Плюс лицензия **GPL-2** (`COPYING`), то есть код оттуда брать в закрытый продукт нельзя.

### WaveformKit - аккуратный резерв

- `AudioDecoder.summarize(url:targetBars:onProgress:)` - `AVAssetReader` + `AVAssetReaderTrackOutput` с
  `alwaysCopiesSampleData = false` и **float32 non-interleaved** выходом
  (`Sources/WaveformKit/Audio/AudioDecoder.swift:43-54`), RMS через `vDSP_rmsqv` (`:92`),
  `try Task.checkCancellation()` на каждом чанке (`:70`).
- Кэш на диске с честным ключом «имя+размер+mtime+число баров+версия формата»
  (`Sources/WaveformKit/Audio/WaveformCache.swift:26-33`) - **лучше, чем у Aural** (не зависит от ширины вьюхи).
- Прогресс и перемотка встроены: `movement: .progress`, `seekGesture`, `onSeek`
  (`Sources/WaveformKit/View/WaveformView.swift:333-366`).
- Цвет: только `played` / `unplayed` + опциональные градиенты (`Models/WaveformColors.swift:3-8`). По частотам - нет.
- Риск: 5 звёзд, один автор, один день коммитов; это не «проверенная временем» библиотека.

### Mixxx - эталон алгоритма RGB-волны (брать алгоритм, не код; GPL-2)

Полный рецепт, который и даёт «серато-подобную» картинку:

1. Три фильтра Бесселя 4-го порядка на границах **600 Гц** и **4000 Гц**:
   `EngineFilterBessel4Low(sampleRate, kLowMidFreqHz)`, `...Band(600, 4000)`, `...High(4000)`
   (`src/analyzer/analyzerwaveform.cpp:179-183`, константы `:18,20`).
2. На каждый «страйд» (колонку) берётся **максимум модуля**, а не среднее, отдельно по каждой полосе и по каналам:
   `storeIfGreater(&m_stride.m_filteredData[Left][Low], clow[Left])` и т.д.
   (`src/analyzer/analyzerwaveform.cpp:253-261`). Закомментированный вариант с усреднением там же (`:245-252`).
3. Результат пакуется в 4 байта на колонку на канал: `filtered.all/low/mid/high`, каждый
   `min(255, 255 * value + 0.5)` (`src/analyzer/analyzerwaveform.h:50-61`, структура `WaveformData` в `src/waveform/waveform.h:29-32`).
4. Разрешение: детальная волна - `mainWaveformSampleRate = 441` визуальных сэмпла в секунду;
   **обзорная (то, что нам нужно) - `summaryWaveformSamples = 2 * 1920 = 3840` колонок на весь трек, независимо от длины**
   (`src/analyzer/analyzerwaveform.cpp:61-72`).
5. Цвет колонки:
   ```
   red   = maxLow*low_r + maxMid*mid_r + maxHigh*high_r
   green = maxLow*low_g + maxMid*mid_g + maxHigh*high_g
   blue  = maxLow*low_b + maxMid*mid_b + maxHigh*high_b
   // нормировка на максимальную компоненту
   ```
   (`src/waveform/renderers/allshader/waveformrendererrgb.cpp:182-213`).
6. Обзорная картинка рисуется отдельной функцией `waveformOverviewRenderer::render(...)` с тремя режимами
   `RGB / Filtered / HSV` и нормировкой по пику (`src/waveform/renderers/waveformoverviewrenderer.cpp:14-76`).

Арифметика кэша по схеме Mixxx: 3840 колонок × 2 канала × 4 байта ≈ **30 КБ на трек**. Тысяча треков - 30 МБ.

Что это значит для нас: цвет по частотам считается **тремя IIR-фильтрами, без FFT**. У Apple это закрывается
`vDSP_biquad` / `vDSP_deq22` из Accelerate - то есть в 3 прохода фильтра + пиковая редукция, дешевле, чем 38 800 FFT.

Для справки, как это читают диджеи (вторичный источник, официальный support AlphaTheta / FAQ Pioneer):
низ - синий, верх - белый, середина - оранжевый ([AlphaTheta Help Center](https://support.alphatheta.com/en-US/articles/8113178546201?product=9366984218137)).
Точные пороги частот rekordbox/Serato **не установлены** - вендоры их не публикуют; берём границы Mixxx (600 / 4000 Гц).

---

## 3. Извлечение PCM: AVAssetReader vs AVAudioFile vs ExtAudioFile

По официальной документации Apple (JSON-эндпоинт `developer.apple.com/tutorials/data/documentation/...`):

| API | Что говорит Apple | Статус | Введён |
|---|---|---|---|
| `AVAssetReader` | «An object that reads media data from an asset.» | не deprecated | macOS 10.7 |
| `AVAssetReaderTrackOutput` | «An object that reads media data from a single track of an asset… A track output produces uncompressed output.» | не deprecated | macOS 10.7 |
| `AVAudioFile` | «Regardless of the file format, you read and write using objects… **Reads and writes are always sequential.** Random access is possible by setting the property.» | не deprecated | macOS 10.10 |
| `AVAudioFile.read(into:)` | «Reads an entire audio buffer… the method attempts to fill the buffer to its capacity. On return, the buffer's property indicates the number of sample frames it successfully reads.» | не deprecated | macOS 10.10 |
| `ExtAudioFileOpen` | «**Deprecated.** Use the function instead.» (замена - `ExtAudioFileOpenURL`) | deprecated с **macOS 10.6** | macOS 10.4 |

Вывод по API: **ExtAudioFile отпадает** - это C-API 2004 года, часть его уже помечена deprecated, а обёртки
над ним (`AVAudioFile`) дают то же самое на Swift. Остаются два реальных варианта, и оба используются в проверенных
кодовых базах: `AVAssetReader` (DSWaveformImage, WaveformKit) и `AVAudioFile.read(into:)` (aural-player, AudioKit).

**Что известно точно (по коду):** оба варианта работают потоково и с константной памятью, если читать чанками.
`AVAssetReader` дополнительно позволяет попросить готовый выходной формат (float32/int16, interleaved или нет)
одним словарём `outputSettings` и выключить копирование через `alwaysCopiesSampleData = false`
(`WaveformKit/Sources/WaveformKit/Audio/AudioDecoder.swift:43-51`). У `AVAudioFile` формат задаётся `processingFormat`,
а нужный чанк приходит уже раскиданным по каналам (`floatChannelData`).

**Что не установлено:** какой из двух быстрее на 60-минутном 320 kbps MP3 и на FLAC. Я не делал замера
(по брифу приложение не строим). В сети есть жалоба на медленный `AVAudioFile.read` **после seek** в MP3/FLAC
(Apple Developer Forums, thread 819924) - но это про случайный доступ, а мы читаем строго последовательно,
так что к нашему сценарию она напрямую не относится. Рекомендую отдельный микрозамер на реальном 60-минутном миксе
как первый шаг реализации (см. открытые вопросы).

**Что известно про форматы:** AVFoundation не открывает APE/WavPack/Musepack/Shorten/Opus в контейнерах вне Apple.
Поэтому нужен второй декодер: либо FFmpeg, как в Aural (`FFmpegWaveformDecoder`), либо **SFBAudioEngine**
(живое MIT-репо, `Sources/CSFBAudioEngine/Decoders/`: FLAC, MonkeysAudio, Musepack, Shorten, TrueAudio, libsndfile).

---

## 4. Вердикт

**Берём:**
1. **aural-player `Source/UI/Waveform`** (MIT) - вендорим как основу. Это единственный найденный готовый
   AppKit-компонент обзорной волны с прогрессом, кликом-перемоткой, потоковым декодером, vDSP-даунсемплингом,
   дисковым кэшем и отменяемой операцией. Репо архивировано - значит форкаем и живём своей жизнью, апдейтов не ждём.
2. **Mixxx `analyzerwaveform` + `waveformrendererrgb`** - как **алгоритм** (не код, GPL-2): 3 полосы 600/4000 Гц,
   пик на колонку, 3840 колонок на трек, линейная смесь RGB с нормировкой.
3. **DSWaveformImage** - как референс того, как выглядит спектральная окраска в Swift, и как запасной готовый
   рендер `NSImage`, если свой рисовать не захотим. Его FFT-путь в продакшн на 60 минут не берём (см. риски).

**Резерв:**
- **WaveformKit** - если решим стартовать с SwiftUI, а не AppKit. У него лучший из увиденных дисковый кэш
  (ключ по mtime+размеру, а не по ширине вьюхи) и уже готовый `onSeek`.
- **SFBAudioEngine** - второй декодер под форматы, которые не открывает AVFoundation.

**Нет:** AudioKit/Waveform и AudioKitUI (полная загрузка трека в RAM, ~1.27 ГБ на час), FDWaveformView
(нет macOS-таргета, не компилируется), pixlwave/Waveform (iOS-only), Cog (нет волны + GPL), EZAudio (deprecated автором).

---

## 5. Рекомендуемая связка «декодер → анализ → рендер»

```
ФАЙЛ
 │
 ├─ ДЕКОДЕР (потоково, чанк 10 сек, память константная)
 │    AVAudioFile.read(into:) — из aural-player/AVFWaveformDecoder.swift
 │      ИЛИ AVAssetReader + outputSettings(float32) — из WaveformKit/AudioDecoder.swift
 │    для неподдерживаемых форматов: SFBAudioEngine (SFBAudioDecoder)
 │
 ├─ АНАЛИЗ (Accelerate, один проход, БЕЗ FFT)
 │    3 IIR-фильтра (vDSP_biquad / vDSP_deq22): low <600 Гц, band 600–4000, high >4000  ← алгоритм Mixxx
 │    на колонку: max|x| по каждой полосе + по общему сигналу (vDSP_maxmgv)
 │    фикс. 4096 колонок на весь трек (Mixxx берёт 3840), независимо от длины и от ширины окна
 │    ⇒ ~64 КБ на трек (4096 × 2 канала × 4 байта: all/low/mid/high)
 │
 ├─ КЭШ (на диске, ключ = путь + размер + mtime + версия формата — схема WaveformKit/WaveformCache.swift)
 │    хранить сырые 4096 колонок бинарно (не JSON!), ресемплить под текущую ширину при отрисовке
 │    ⇒ ресайз окна НЕ вызывает переанализ (чиним слабое место aural-player)
 │
 └─ РЕНДЕР (AppKit NSView, слоями — схема aural-player/WaveformView.swift)
      цвет колонки: r = low*low_r + mid*mid_r + high*high_r … нормировка на max(r,g,b)  ← алгоритм Mixxx
      слой 1: приглушённая версия (несыгранное)
      слой 2: полная яркость + CALayer-маска шириной width*progress (сыгранное) — как в AIMP
      клик/драг: NSClickGestureRecognizer → seekTo(percentage:) — из WaveformView+GestureHandling.swift
      если 4096 колонок × CAShapeLayer окажется медленно: тот же расчёт уходит в Metal-фрагментный шейдер
      по образцу AudioKit/Waveform/Waveform.metal (но с буфером low/mid/high вместо одного цвета)
```

Почему без FFT: 3 прохода IIR-фильтра по потоку - это линейная стоимость, сравнимая со стоимостью самого
декодирования MP3. FFT-путь DSWaveformImage на часе даёт ~38 800 созданий `vDSP_create_fftsetup`, удержание
всех фреймов в памяти и `removeFirst` в цикле (`TempiFFT.swift:107`, `WaveformAnalyzer.swift:381,404`).

Почему фиксированные 4096 колонок, а не «по ширине вьюхи»: так кэш переживает ресайз окна и смену режима
(Mixxx делает ровно так: `summaryWaveformSamples = 2 * 1920`, `analyzerwaveform.cpp:65`).

---

## 6. Открытые вопросы владельцу

1. 🔴 **Какая волна нужна: 2 цвета как в AIMP на скриншоте (оранжевое сыгранное / серое несыгранное) или RGB
   по частотам как в Serato/rekordbox?** На присланном скриншоте AIMP волна одноцветная. RGB - это +3 IIR-фильтра
   в анализе и другая палитра; красиво, но «сыгранное/несыгранное» тогда показывается яркостью, а не цветом.
   Оба варианта можно сделать переключателем - надо ли?
2. 🔴 **Какие форматы файлов реально в библиотеке, кроме MP3 и FLAC?** Если только MP3/M4A/WAV/AIFF/FLAC -
   хватает встроенного AVFoundation, никаких внешних библиотек. Если есть APE / WavPack / Musepack / Opus в OGG -
   нужен второй декодер (SFBAudioEngine), это +зависимость и +время.
3. **Сколько треков в библиотеке и надо ли считать волны заранее, фоном для всего плейлиста?**
   От этого зависит, нужен ли фоновый воркер с очередью или считаем по одному при открытии трека.
4. **Нужны ли на волне метки (загрузка, cue-точки, «здесь бит меняется»)** или чистая волна + курсор?

**Не установлено и требует замера (моя работа, не владельца):** реальное время построения волны для
60-минутного 320 kbps MP3 и для FLAC, и что быстрее - `AVAudioFile.read(into:)` или `AVAssetReader`.
Первый шаг реализации - микрозамер на настоящем миксе, а не на тестовом файле.

---

Sources (веб, для утверждений вне кода):
- [AVAssetReader | Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avassetreader)
- [AVAssetReaderTrackOutput | Apple Developer Documentation](https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput)
- [AVAudioFile | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudiofile)
- [AVAudioFile.read(into:) | Apple Developer Documentation](https://developer.apple.com/documentation/avfaudio/avaudiofile/read(into:))
- [ExtAudioFileOpen | Apple Developer Documentation](https://developer.apple.com/documentation/audiotoolbox/extaudiofileopen)
- [AVAudioFile.read extremely slow after seeking in FLAC and MP3 files | Apple Developer Forums](https://developer.apple.com/forums/thread/819924)
- [What is the color of the waveform (BLUE/RGB/3Band)… | AlphaTheta Help Center](https://support.alphatheta.com/en-US/articles/8113178546201?product=9366984218137)
- [EZAudio README (deprecated)](https://github.com/syedhali/EZAudio)
