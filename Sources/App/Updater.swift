import AppKit
import Sparkle

/// Владелец Sparkle на весь срок жизни процесса (создаётся один раз в `AppDelegate`).
///
/// Своих проверок версии в Claimp нет и быть не должно: расписание, разбор фида, сравнение
/// версий, скачивание, проверку подписи и установку ведёт Sparkle. Обёртка отдаёт наружу
/// ровно то, что нужно пункту меню «Check for Updates…».
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController

    /// `startingUpdater: true` - апдейтер запускается сразу и сам, при первой проверке,
    /// спросит у владельца разрешение на автоматические обновления (штатное поведение
    /// Sparkle, не отключаем). Адрес фида и публичный ключ берутся из Info.plist бандла.
    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Пока Sparkle занят проверкой или установкой, пункт меню серый.
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        // Проверку запускают из меню, но окно Claimp в этот момент может быть неактивным:
        // без активации окно Sparkle открывается позади фронтового приложения.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
