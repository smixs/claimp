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

    @objc private func openDocument(_ sender: Any?) {
        mainController?.showOpenPanel()
    }

    /// Минимальное меню: ⌘Q, ⌘O, правки для поля поиска. Больше ничего в T4 нет.
    private func buildMenu() {
        let mainMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
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
