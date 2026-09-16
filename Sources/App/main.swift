import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainController: MainWindowController?
    /// Папка пришла раньше, чем построилось окно (запуск через «Открыть с помощью»):
    /// придержим, иначе первый запуск тихо терял то, что открывали.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let controller = MainWindowController()
        mainController = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
        if Self.shouldOpenSettingsAtLaunch() { controller.showSettings() }
        guard !pendingURLs.isEmpty else { return }
        controller.loadURLs(pendingURLs)
        pendingURLs = []
    }

    /// Дроп папки/файлов на иконку в Dock и «Открыть с помощью».
    /// Реализован ровно openFiles, не application(_:open:) - иначе AppKit вызовет не тот.
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard let mainController else {
            pendingURLs += urls
            return
        }
        mainController.loadURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Выход из приложения: незавершённый разбор BPM/тональности отменяется, а не досчитывается
    /// в фоне уже закрытого окна.
    func applicationWillTerminate(_ notification: Notification) {
        mainController?.cancelAnalysis()
    }

    @objc private func openDocument(_ sender: Any?) {
        mainController?.showOpenPanel()
    }

    @objc private func showSettings(_ sender: Any?) {
        mainController?.showSettings()
    }

    /// Отладочный ключ: окно настроек открывается сразу после запуска, без клавиатуры
    /// (`Claimp --open-settings` или `CLAIMP_OPEN_SETTINGS=1`). Нужен для снимков и проверок.
    private static func shouldOpenSettingsAtLaunch() -> Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("--open-settings")
            || info.environment["CLAIMP_OPEN_SETTINGS"] == "1"
    }

    /// Минимальное меню: ⌘Q, ⌘O, правки для поля поиска. Больше ничего в T4 нет.
    private func buildMenu() {
        let mainMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: Strings.menuAbout(appName),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: Strings.menuSettings, action: #selector(showSettings(_:)), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: Strings.menuQuit(appName),
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: Strings.menuFile)
        fileMenu.addItem(NSMenuItem(
            title: Strings.menuOpen, action: #selector(openDocument(_:)), keyEquivalent: "o"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: Strings.menuEdit)
        for (title, action, key) in [
            (Strings.menuCut, #selector(NSText.cut(_:)), "x"),
            (Strings.menuCopy, #selector(NSText.copy(_:)), "c"),
            (Strings.menuPaste, #selector(NSText.paste(_:)), "v"),
            (Strings.menuSelectAll, #selector(NSText.selectAll(_:)), "a"),
        ] as [(String, Selector, String)] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
