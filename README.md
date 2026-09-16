<p align="center">
  <img src="docs/screenshots/claimp-banner.webp" alt="Claimp" width="800">
</p>

<p align="center"><b>A minimal waveform player for building DJ sets and compilations in the studio.</b></p>

<p align="center">
  <a href="https://github.com/smixs/claimp/releases"><img src="https://img.shields.io/github/v/release/smixs/claimp?style=flat-square&color=FE6776" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-2B2F3A?style=flat-square" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Swift-6.4-FFD166?style=flat-square" alt="Swift 6.4">
  <img src="https://img.shields.io/badge/license-Apache--2.0-5CE1E6?style=flat-square" alt="Apache-2.0">
</p>

<p align="center">
  <img src="docs/screenshots/claimp-window.webp" alt="Claimp window" width="520">
</p>

## Three things it does

**Spectral waveform.** The whole track at a glance: height is loudness, colour is
spectrum, from red bass to violet highs. You see the intro, the drop, the breakdown
before you hear them. Click anywhere to jump.

**Drag the file into your DAW.** Grab a row or the cover art and drop it into Ableton,
Bitwig, Finder, anywhere that takes files. No export, no dialogs, the real file lands
on the timeline.

**A list built for selection.** Year, duration, sort by any column, filter by typing a
couple of letters, drag any column border to the width you want, and a lamp you switch
on when a track is already in the mix. The
shuffle button in the transport makes the next track a random one.

**BPM and key, on-device.** Right-click the selected tracks and pick "Проанализировать
треки": Apple's MusicUnderstanding framework works them out in the background, two at a
time, cached in the library database, and written straight into the file's tags (TBPM/TKEY
and their equivalents), the way DJ software does it. Nothing is analysed behind your back
unless you turn automatic analysis on in settings. Key shows as Camelot (8A) with the note on hover. No cloud, no extra install.

**Settings (⌘,).** One column of groups, no tabs: which playlist columns are visible,
playlist font size (8-16 pt, the row stays as tight as the glyphs), automatic BPM/key
analysis with its tempo range and length limit, key format (Camelot / note / both), and
the waveform palette. Everything applies live, no restart.

## Updates

Claimp updates itself: Sparkle checks the appcast once a day and offers the new version
when there is one. To ask right away, use **Claimp → Check for Updates…**.

## Install

Download `Claimp-<version>.dmg` from the
[Releases page](https://github.com/smixs/claimp/releases), open it and drag **Claimp**
into **Applications**. The app is signed with a Developer ID certificate and notarized
by Apple, so it opens without a Gatekeeper warning.

Prefer the zip? `Claimp-<version>.zip` on the same page holds the same notarized
bundle.

## Requirements

- macOS 27 or newer (`Package.swift`: `.macOS("27.0")`) - the BPM/key analysis runs on
  Apple's system `MusicUnderstanding` framework, which ships in macOS 27
- Swift 6.4 toolchain with the macOS 27 SDK, Swift 6 language mode. On this machine it
  lives in the Command Line Tools, so every build sets
  `DEVELOPER_DIR=/Library/Developer/CommandLineTools`; `make build` / `make test` do it
  for you and fail with a clear message if the SDK has no `MusicUnderstanding.framework`
- Build verified on Apple Silicon with Swift 6.4

## Build and run

```bash
make build     # debug build (swift build)
make test      # tests (swift-testing)
make app       # release build + build/Claimp.app with Info.plist, ad-hoc signed
make run       # build the .app and launch it
make clean     # remove .build and build/
```

Distribution (needs the project's Developer ID certificate and a notarization profile
in the Keychain, so this is for the maintainer):

```bash
make dist      # Developer ID + hardened runtime -> build/Claimp.app, zip, styled DMG
make notarize  # notarize the app, staple it, rebuild + notarize + staple the DMG
make verify    # codesign / stapler / spctl checks on the result
make appcast   # sign the notarized zip and write appcast.xml (the update feed)
make release   # dist -> notarize -> appcast -> verify
```

Bump **both** `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env` before a release:
Sparkle compares `CFBundleVersion`, and installed copies ignore an update whose build
number did not grow. The EdDSA signing key is a one-off `make sparkle-keys` - the private
half stays in the login Keychain, the public half is committed as
`Resources/sparkle-public-key.txt`.

The same steps without `make`:

```bash
swift build
swift test
scripts/build-app.sh release   # prints the bundle path it wrote
scripts/run.sh                 # build and open
```

`build-app.sh`
always prints the path it wrote.

## Architecture

Four SwiftPM targets, one direction of dependencies (`App` → `Playback`/`Waveform` →
`Core`):

| Module | Responsibility |
|---|---|
| `Sources/Core` | Track model, library scanner (SFBAudioEngine + TagLib metadata), played flags and playlist order in SQLite (GRDB), filter/sort/navigation logic |
| `Sources/Playback` | `PlayerEngine` (SFBAudioEngine playback, seek, gapless queue) and `NowPlayingBridge` (media keys, Now Playing) |
| `Sources/Waveform` | `PCMReader` → `BandSplitter` → `WaveformAnalyzer` → `WaveformCache` → `WaveformView`/`WaveformResampler`; every visual and analysis constant lives in `WaveformStyle` |
| `Sources/App` | AppKit window, header (cover, transport, vertical volume fader), playlist table, waveform view, drag-out/drop; every colour and size token lives in `Theme.swift` |

Documents: `SPEC.md` is the behaviour contract (sections 4–8 are the UI, data and
acceptance contracts), `PLAN.md` is the work plan, `research/` holds the source-based
survey of the components the player is assembled from, `AGENTS.md` is the engineering
runbook (test-first, per-task worktrees, gate checks). These documents are written in
Russian; the code and this README are in English.

## Third-party code and licenses

Claimp is assembled from open-source components. Full attribution, per-component
usage notes and license texts (where required) are in **[NOTICE](NOTICE)**:

| Component | Used for | License |
|---|---|---|
| [Aural Player](https://github.com/kartik-venugopal/aural-player) | waveform module, folder drop | MIT |
| [Bòcan](https://github.com/bocan/bocan-music) | playlist table, file drag-out, media keys | Apache-2.0 |
| [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) | playback and metadata | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | auto-update | MIT |
| TagLib (inside SFBAudioEngine) | tag reading | LGPL 2.1 / MPL 1.1 |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite storage | MIT |
| [swift-property-based](https://github.com/x-sheep/swift-property-based) | tests only | MIT |
| [WaveformKit](https://github.com/GRimAce11/WaveformKit) | cache key scheme only, no code copied | MIT |
| [Mixxx](https://github.com/mixxxdj/mixxx) | spectral waveform algorithm only, no code copied | GPL-2.0 |

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright 2026 Sergey Shima.

---

## По-русски

**Claimp** — нативный macOS-плеер для подготовки DJ-микса. Открываешь папку с треками,
видишь спектральную волну всего трека, слушаешь, отмечаешь лампочкой нужное и
перетаскиваешь настоящий файл прямо в DAW.

- Волна всего трека: высота столбика — громкость (RMS с мягкой компрессией), цвет —
  спектр частот (как у Serato: красный на низах, через жёлтый и зелёный к
  фиолетовому на верхах). Клик и протяжка по волне — перемотка.
- Drag-out файла из двух мест: строка плейлиста и обложка. Файл принимают
  Ableton Live, Bitwig, Finder, Telegram и всё остальное, что умеет drop файлов.
- Плейлист с нужными для микса колонками: лампочка, номер, название, исполнитель,
  **год**, **длительность**; сортировка кликом по заголовку, фильтр по паре букв.
- Лампочка «сыграно» живёт в SQLite и переживает перезапуск; порядок плейлиста и
  текущий трек тоже восстанавливаются.
- BPM и тональность: у треков без тегов считаются на устройстве через системный
  MusicUnderstanding, по два одновременно. Результат пишется в теги самого файла
  (TBPM/TKEY и аналоги), а база остаётся кэшем. Тональность в Camelot (8A), при наведении нота.
- Настройки (⌘,): видимость колонок, кегль плейлиста, автоанализ с диапазоном темпа,
  формат тональности, палитра волны. Применяется сразу.
- Папку можно бросить на окно или на иконку в Dock; медиаклавиши и Now Playing
  работают при неактивном окне.
- Обновляется сам: Sparkle раз в сутки смотрит фид и предлагает новую версию,
  вручную - меню «Claimp → Check for Updates…».

**Требования:** macOS 27+ (анализ BPM и тональности работает на системном фреймворке
MusicUnderstanding, он появился в macOS 27), Swift 6.4 с SDK macOS 27 - на этой машине
он в Command Line Tools, поэтому сборка идёт с
`DEVELOPER_DIR=/Library/Developer/CommandLineTools` (его выставляют `make build` и
`make test` сами). Сборка проверена на Apple Silicon.

```bash
make build     # debug-сборка
make test      # тесты
make app       # release + build/Claimp.app (ad-hoc подпись)
make run       # собрать .app и запустить
make release   # дистрибутив: Developer ID, нотаризация, DMG (нужен сертификат)
```

**Установка из релиза:** скачать `Claimp-<версия>.dmg` со [страницы релизов](https://github.com/smixs/claimp/releases),
открыть и перетащить Claimp в Applications. Подписано Developer ID и нотаризовано
Apple — Gatekeeper не ругается.

Архитектура: четыре модуля — `Core` (модель, сканер, SQLite), `Playback`
(воспроизведение, медиаклавиши), `Waveform` (анализ и отрисовка волны), `App`
(AppKit-интерфейс). Документы проекта (`SPEC.md`, `PLAN.md`, `research/`, `AGENTS.md`)
на русском, код и README — на английском.

**Статус:** ранний личный инструмент, без обещаний поддержки.

**Лицензия:** Apache License 2.0 (`LICENSE`), Copyright 2026 Sergey Shima. Сторонний
код и его лицензии — в `NOTICE`.
**Website:** [claimp.app](https://claimp.app)
