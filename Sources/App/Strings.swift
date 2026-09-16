import Core

/// Все видимые строки интерфейса в одном месте (решение владельца 2026-09-16: плеер
/// международный, русских слов в интерфейсе нет).
///
/// Локализации на этом шаге нет: один язык - английский, поэтому это простые константы,
/// а не `Localizable.strings`. Строки с подстановкой - функции: склейка живёт здесь, а не
/// в контроллерах. Сообщения об ошибках тоже здесь - их видит владелец в статусной строке.
enum Strings {
    // MARK: - Заголовки колонок плейлиста

    enum Column {
        /// Лампочка «сыграно»: заголовка как слова у неё нет, только точка.
        static let played = "●"
        static let number = "#"
        static let title = "Title"
        static let artist = "Artist"
        static let year = "Year"
        static let duration = "Length"
        static let bitrate = "kbps"
        static let bpm = "BPM"
        static let key = "Key"
        /// В настройках у номера есть место на пояснение, в заголовке таблицы - нет.
        static let numberInSettings = "# (number)"
    }

    // MARK: - Главное окно

    static let search = "Search"
    static let openPanelPrompt = "Open"

    /// Счётчик ошибок разбора в статусной строке: "155 tracks · 9:32:46 · analysis: 2 errors".
    static func analysisErrors(_ count: Int, summary: String) -> String {
        let word = count == 1 ? "error" : "errors"
        return "\(summary) · analysis: \(count) \(word)"
    }

    // MARK: - Меню

    static let menuCheckForUpdates = "Check for Updates…"
    static let menuSettings = "Settings…"
    static let menuOpen = "Open…"
    static let menuFile = "File"
    static let menuEdit = "Edit"
    static let menuCut = "Cut"
    static let menuCopy = "Copy"
    static let menuPaste = "Paste"
    static let menuSelectAll = "Select All"
    static func menuAbout(_ appName: String) -> String { "About \(appName)" }
    static func menuQuit(_ appName: String) -> String { "Quit \(appName)" }

    /// Контекстное меню строки плейлиста.
    static func analyzeTracks(count: Int) -> String {
        count == 1 ? "Analyze track" : "Analyze tracks"
    }

    static let removeFromPlaylist = "Remove from playlist"

    // MARK: - Окно настроек

    enum Settings {
        static let windowTitle = "Settings"
        static let groupPlaylist = "Playlist"
        static let groupAnalysis = "Analysis"
        static let groupWaveform = "Waveform"
        static let groupGeneral = "General"
        static let visibleColumns = "Visible columns. The played lamp is always shown."
        static let fontSize = "Font size"
        static let autoAnalyze = "Auto-analyze BPM and key"
        static let tempoRange = "BPM range"
        static let skipLongerThan = "Skip longer than"
        static let keyFormat = "Key format"
        static let palette = "Palette"
        static let unplayedBrightness = "Unplayed brightness"
        static let waveHeight = "Wave height"
        static let reset = "Reset settings"

        static func points(_ value: Int) -> String { "\(value) pt" }
        static func minutes(_ value: Int) -> String { "\(value) min" }
        static func percent(_ value: Int) -> String { "\(value) %" }

        /// Формат тональности в колонке Key.
        static func keyFormatTitle(_ format: KeyFormat) -> String {
            switch format {
            case .camelot: return "Camelot (8A)"
            case .note: return "Note (Am)"
            case .both: return "Both (8A · Am)"
            }
        }

        /// Палитра волны: спектр по полосам частот или один тон.
        static func paletteTitle(_ palette: WavePalette) -> String {
            switch palette {
            case .spectrum: return "Spectrum"
            case .single: return "Mono"
            }
        }
    }

    // MARK: - Ошибки, которые видит владелец

    enum Error {
        /// База лампочек не открылась: причина висит в статусной строке до выхода.
        static func storeUnavailable(_ reason: String) -> String {
            "Played marks and order are not saved: \(reason)"
        }

        static let storeMissing = "database is unavailable"
        static func storeNotOpened(_ reason: String) -> String { "database did not open (\(reason))" }

        static func playbackCannotOpen(_ file: String) -> String { "Playback error: \(file)" }
        static let playbackNotLoaded = "Playback error: track is not loaded"
        static let playbackFailedTitle = "Playback failed"

        static func waveCannotOpen(_ file: String) -> String { "Waveform did not open: \(file)" }
        static func waveCannotRead(_ file: String, frame: Int) -> String {
            "Waveform read failed: \(file), frame \(frame)"
        }
        static func waveBadCache(_ file: String) -> String { "Waveform cache is broken: \(file)" }
        static let waveCancelled = "Waveform: analysis cancelled"
        static func waveFailed(_ file: String, reason: String) -> String {
            "Waveform analysis failed: \(file) (\(reason))"
        }

        /// Строки в stderr: их читает не владелец, а тот, кто смотрит лог, но язык один.
        static func analysisSkipped(_ file: String, reason: String) -> String {
            "analysis skipped - \(file): \(reason)"
        }
        static func analysisFailed(_ file: String, reason: String) -> String {
            "analysis failed - \(file): \(reason)"
        }
    }
}
