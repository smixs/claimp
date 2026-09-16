<p align="center">
  <img src="https://claimp.app/assets/github-banner.png" alt="Claimp" width="520">
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
  <img src="https://claimp.app/assets/github-window.webp" alt="Claimp window" width="520">
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

## Build

```bash
swift build
swift test
```

Swift 6.4 with the macOS 27 SDK (Command Line Tools). Four SwiftPM targets:
`Core` (library, tags, SQLite), `Playback`, `Waveform`, `Analysis` (BPM and key via
MusicUnderstanding), `TagWriter` (TagLib) and the AppKit `App`.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Copyright 2026 Sergey Shima.
Third-party components and their licenses are listed in [NOTICE](NOTICE).
