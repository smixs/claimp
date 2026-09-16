<p align="center">
  <img src="docs/screenshots/claimp-banner.png" alt="Claimp" width="520">
</p>

<p align="center"><b>The waveform player for building DJ sets on macOS.</b><br>
<a href="https://claimp.app">claimp.app</a></p>

<p align="center">
  <a href="https://github.com/smixs/claimp/releases"><img src="https://img.shields.io/github/v/release/smixs/claimp?style=flat-square&color=FE6776" alt="Release"></a>
  <img src="https://img.shields.io/badge/macOS-27%2B-2B2F3A?style=flat-square" alt="macOS 27+">
  <img src="https://img.shields.io/badge/Swift-6.4-FFD166?style=flat-square" alt="Swift 6.4">
  <img src="https://img.shields.io/badge/license-Apache--2.0-5CE1E6?style=flat-square" alt="Apache-2.0">
</p>

<p align="center">
  <img src="docs/screenshots/claimp-window.webp" alt="Claimp window" width="520">
</p>

## Install

Download the latest release from **[claimp.app](https://claimp.app/download)**, open the DMG
and drag **Claimp** into **Applications**. Signed with a Developer ID certificate and
notarized by Apple; updates arrive inside the app. Requires macOS 27 or newer.

Homebrew:

```bash
brew install smixs/claimp/claimp
```

Releases and zips: [github.com/smixs/claimp/releases](https://github.com/smixs/claimp/releases).

## What it does

**Spectral waveform.** The whole track at a glance: height is loudness, colour is
spectrum, from red bass to violet highs. You see the intro, the drop, the breakdown
before you hear them. Click anywhere to jump. Wave height is a slider in Settings.

**Drag the real file into your DAW.** Grab a row or the cover art and drop it into Ableton,
Bitwig, Finder, anywhere that takes files. No export, no dialogs.

**BPM and key, on-device.** Select tracks, right-click, "Analyze tracks": tempo and key are
computed by the MusicUnderstanding framework built into macOS 27 and written back into the
file tags (TBPM / TKEY, BPM / INITIALKEY). Key shows as Camelot ("8A"), note on hover.
Automatic analysis of every new track is a switch in Settings.

**A playlist built for selection.** Year, length, kbps, BPM, Key; sort by any column, drag
column headers to reorder, drag borders to resize, filter by typing a couple of letters,
a lamp you switch on when a track is already in the mix, Random mode, and the playing
row always highlighted. Drop a folder on the window or the Dock icon and it plays.

**Stays current.** Claimp checks for updates on launch (Sparkle) and installs them in place.

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

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright 2026 Sergey Shima.
Third-party components and their licenses are listed in [NOTICE](NOTICE).
