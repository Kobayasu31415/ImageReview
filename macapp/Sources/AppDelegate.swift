import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// メニューバーに常駐し、Finder からのファイルとスクリーンショットをウインドウに振り分ける。
/// ウインドウがない間は Dock から消え、メニューバーのアイコンだけが残る。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var windows: [ReviewWindow] = []
    private let files = AppSchemeHandler(root: Bundle.main.resourceURL!.appendingPathComponent("web"))
    private let defaults = UserDefaults.standard
    private let shortcuts = ShortcutCenter.shared
    private(set) lazy var settings = SettingsWindowController()
    private(set) var statusItem: NSStatusItem!
    private var cascade = NSPoint.zero
    private var capturing = false
    private var openedAtLaunch = false

    // MARK: 起動と終了

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ImageReview")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        shortcuts.onPress = { [weak self] in self?.capture($0) }
        shortcuts.registerAll()

        // ログイン時の自動起動ではウインドウを出さず、裏で待機する。
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launch?.eventID == kAEOpenApplication
            && launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if atLogin || openedAtLaunch {
            if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
        } else {
            newDocument(nil)
        }
        #if TESTHOOKS
        runTestHooks()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if windows.isEmpty { newDocument(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if windows.isEmpty { return .terminateNow }
        Task { @MainActor in
            var unsaved = false
            for window in windows where !unsaved {
                unsaved = await window.hasUnsavedChanges()
            }
            var quit = true
            if unsaved {
                let alert = NSAlert()
                alert.messageText = "未保存の変更があります。保存せずに終了しますか？"
                alert.addButton(withTitle: "終了")
                alert.addButton(withTitle: "キャンセル")
                NSApp.activate(ignoringOtherApps: true)
                quit = alert.runModal() == .alertFirstButtonReturn
            }
            sender.reply(toApplicationShouldTerminate: quit)
        }
        return .terminateLater
    }

    // MARK: ウインドウ

    private func makeWindow() -> ReviewWindow {
        let window = ReviewWindow(files: files)
        window.onClose = { [weak self] closed in
            guard let self else { return }
            self.windows.removeAll { $0 === closed }
            if self.windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
        cascade = window.window.cascadeTopLeft(from: cascade)
        windows.append(window)
        return window
    }

    private func show(_ window: ReviewWindow) {
        NSApp.setActivationPolicy(.regular)
        window.window.makeKeyAndOrderFront(nil)
        window.window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var frontWindow: ReviewWindow? {
        windows.first { $0.window.isKeyWindow } ?? windows.first { $0.window.isMainWindow } ?? windows.last
    }

    /// ファイルを1件ずつウインドウで開く。作業中のウインドウは上書きせず、空きがなければ新しく作る。
    func open(_ urls: [URL], name: String? = nil, removeWhenDone: Bool = false) {
        Task { @MainActor in
            for url in urls {
                var target: ReviewWindow?
                for window in windows where target == nil {
                    if await window.isEmpty() { target = window }
                }
                let window = target ?? makeWindow()
                window.open(url, name: name, removeWhenDone: removeWhenDone)
                show(window)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        open(urls.filter(\.isFileURL))
    }

    @objc func newDocument(_ sender: Any?) {
        show(makeWindow())
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif, .bmp, .pdf, .json]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { open(panel.urls) }
    }

    @objc func printDocument(_ sender: Any?) {
        frontWindow?.printDocument()
    }

    // MARK: スクリーンショット

    @objc func captureFromMenu(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? CaptureMode else { return }
        // メニューが消えきってから撮る。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.capture(mode) }
    }

    func capture(_ mode: CaptureMode) {
        guard !capturing else { return }
        guard CGPreflightScreenCaptureAccess() else { return requestScreenCaptureAccess() }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "スクリーンショット \(stamp.string(from: Date())).png"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        switch mode {
        case .screen:
            // ポインターのある画面を撮る。
            let pointer = NSEvent.mouseLocation
            let index = NSScreen.screens.firstIndex { $0.frame.contains(pointer) } ?? 0
            process.arguments = ["-D", String(index + 1), file.path]
        case .area:
            // 標準の ⌘⇧4 と同じ操作。ドラッグで範囲を選び、esc で取り消す。
            process.arguments = ["-i", file.path]
        case .window:
            // ウインドウ選択の状態で始める。クリックしたウインドウを撮る。
            process.arguments = ["-i", "-W", file.path]
        }
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.capturing = false
                if FileManager.default.fileExists(atPath: file.path) {
                    self.open([file], name: name, removeWhenDone: true)
                }
            }
        }
        do {
            try process.run()
            capturing = true
        } catch {
            NSSound.beep()
        }
    }

    private func requestScreenCaptureAccess() {
        // 初回は macOS の許可ダイアログが出る。2回目以降は出ないので自前で案内する。
        if !defaults.bool(forKey: "askedScreenCapture") {
            defaults.set(true, forKey: "askedScreenCapture")
            if CGRequestScreenCaptureAccess() { return }
        }
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "システム設定の「プライバシーとセキュリティ › 画面収録とシステムオーディオ録音」で「ImageReview」をオンにしてから、このアプリを起動し直してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: ショートカットとログイン項目

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "ログイン時の起動を切り替えられませんでした"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: メニュー

    private func item(_ title: String, _ action: Selector?, key: String = "", checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = NSMenu(title: title)
        items.forEach { parent.submenu!.addItem($0) }
        return parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let captures = CaptureMode.allCases.map { mode in
            let entry = item(mode.title, #selector(captureFromMenu))
            entry.representedObject = mode
            // いま実際に効いているショートカットだけを右側に表示する。
            if shortcuts.isActive(mode) {
                let shortcut = shortcuts.shortcut(for: mode)
                entry.keyEquivalent = shortcut.menuKey
                entry.keyEquivalentModifierMask = shortcut.menuModifiers
            }
            return entry
        }
        menu.items = captures + [
            .separator(),
            item("新規ウインドウ", #selector(newDocument)),
            item("画像・PDFを開く…", #selector(openDocument)),
            .separator(),
            item("ショートカット設定…", #selector(showSettings)),
            item("ログイン時に起動", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled),
            .separator(),
            item("ImageReviewを終了", #selector(NSApplication.terminate)),
        ]
    }

    private func makeMainMenu() -> NSMenu {
        let hideOthers = item("ほかを隠す", #selector(NSApplication.hideOtherApplications), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        let redo = item("やり直す", Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]

        let main = NSMenu()
        main.items = [
            submenu("ImageReview", [
                item("ImageReviewについて", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
                .separator(),
                item("ショートカット設定…", #selector(showSettings), key: ","),
                .separator(),
                item("ImageReviewを隠す", #selector(NSApplication.hide), key: "h"),
                hideOthers,
                .separator(),
                item("ImageReviewを終了", #selector(NSApplication.terminate), key: "q"),
            ]),
            submenu("ファイル", [
                item("新規ウインドウ", #selector(newDocument), key: "n"),
                item("開く…", #selector(openDocument), key: "o"),
                .separator(),
                item("閉じる", #selector(NSWindow.performClose), key: "w"),
                .separator(),
                item("プリント…", #selector(printDocument), key: "p"),
            ]),
            submenu("編集", [
                item("取り消す", Selector(("undo:")), key: "z"),
                redo,
                .separator(),
                item("カット", #selector(NSText.cut), key: "x"),
                item("コピー", #selector(NSText.copy), key: "c"),
                item("ペースト", #selector(NSText.paste), key: "v"),
                item("すべてを選択", #selector(NSText.selectAll), key: "a"),
            ]),
            submenu("ウインドウ", [
                item("しまう", #selector(NSWindow.performMiniaturize), key: "m"),
                item("拡大／縮小", #selector(NSWindow.performZoom)),
            ]),
        ]
        NSApp.windowsMenu = main.items.last?.submenu
        return main
    }
}
