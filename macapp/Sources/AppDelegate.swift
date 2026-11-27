import AppKit
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

/// メニューバーに常駐し、Finder からのファイルとスクリーンショットをウインドウに振り分ける。
/// ウインドウがない間は Dock から消え、メニューバーのアイコンだけが残る。
///
/// ⌘Q や Dock の「終了」でもアプリは終わらず、ウインドウを閉じて裏で動き続ける（ショートカットを
/// いつでも使えるようにするため）。本当に終わらせるのは、メニューバーの「完全に終了」だけ。
/// 待機中のメモリを抑えるため、ウインドウを閉じてしばらくたつと、編集画面（WebKit）を
/// 読み込んでいないまっさらなプロセスに入れ替わる（slimDown）。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// ウインドウを出さず、裏で待機する状態で起動されたか。
    static let startsInBackground = CommandLine.arguments.contains("--background")

    private(set) var windows: [ReviewWindow] = []
    private let files = AppSchemeHandler(root: Bundle.main.resourceURL!.appendingPathComponent("web"))
    private let shortcuts = ShortcutCenter.shared
    private(set) lazy var settings = SettingsWindowController()
    private(set) var statusItem: NSStatusItem!
    private var cascade = NSPoint.zero
    private var capturing = false
    private var openedAtLaunch = false
    private var quitsCompletely = false
    private var hasLoadedEditor = false      // このプロセスで編集画面（WebKit）を一度でも使ったか
    private var slimDownTimer: Timer?
    private var terminationSignal: DispatchSourceSignal?

    // MARK: 起動と終了

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ImageReview"   // プロセスが入れ替わっても、メニューバーでの位置を保つ
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ImageReview")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        shortcuts.onPress = { [weak self] in self?.capture($0) }
        shortcuts.registerAll()
        // 作り直したあとも許可が残っているかを後から確かめられるよう、起動時の状態を残す。
        Log.write("launch accessibility=\(Paster.isAllowed) screenCapture=\(CGPreflightScreenCaptureAccess())")

        // ログイン時の自動起動ではウインドウを出さず、裏で待機する。
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launch?.eventID == kAEOpenApplication
            && launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if atLogin || openedAtLaunch || Self.startsInBackground {
            if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
        } else {
            newDocument(nil)
        }

        // kill（SIGTERM）は「完全に終了」として扱う。未保存の確認も通る。ビルドスクリプトが入れ替えの前に使う。
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        // ここ（メインキューの処理の中）から直接終了を始めると、未保存の確認を待つ間メインキューが塞がり、
        // 確認の処理そのものが進まなくなる。いったん抜けて、通常のイベント処理から始める。
        source.setEventHandler { [weak self] in
            self?.perform(#selector(AppDelegate.quitCompletely(_:)), with: nil, afterDelay: 0)
        }
        source.resume()
        terminationSignal = source
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
        // ログアウト・再起動・システム終了のときは、理由つきの終了要求が届く。
        let bySystem = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: kAEQuitReason) != nil
        guard quitsCompletely || bySystem else {
            retireToBackground()
            return .terminateCancel
        }
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
            if !quit { quitsCompletely = false }
            sender.reply(toApplicationShouldTerminate: quit)
        }
        return .terminateLater
    }

    @objc func quitCompletely(_ sender: Any?) {
        quitsCompletely = true
        Log.write("quit completely requested (windows=\(windows.count))")
        NSApp.terminate(nil)
    }

    // MARK: 裏での待機

    /// ⌘Q や Dock の「終了」。ウインドウを閉じて（未保存があれば 1 枚ずつ確認して）、メニューバーで動き続ける。
    private func retireToBackground() {
        windows.forEach { $0.window.performClose(nil) }
        guard !UserDefaults.standard.bool(forKey: "explainedBackground") else { return }
        UserDefaults.standard.set(true, forKey: "explainedBackground")
        let alert = NSAlert()
        alert.messageText = "ImageReview はメニューバーで動き続けます"
        alert.informativeText = "ウインドウを閉じても、ショートカットでの撮影はそのまま使えます。完全に終了するには、メニューバーのアイコンから「ImageReview を完全に終了」を選んでください。"
        alert.addButton(withTitle: "OK")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Mac の起動時にも自動で開始する"
        alert.suppressionButton?.state = .on
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if alert.suppressionButton?.state == .on, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    /// ウインドウがなくなってしばらくしたら、身軽なプロセスに入れ替わる。
    private func scheduleSlimDown() {
        slimDownTimer?.invalidate()
        guard hasLoadedEditor else { return }
        slimDownTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.slimDown() }
    }

    /// 編集画面を一度使うと、ウインドウを閉じても WebKit の補助プロセスなどが残り、100MB 前後を使い続ける。
    /// そこで、裏で待機するだけの新しいプロセス（WebKit を読み込まない）を起動して、自分は終了する。
    private func slimDown() {
        guard windows.isEmpty else { return }
        let isBusy = capturing || statusItem.button?.isHighlighted == true || NSApp.modalWindow != nil
            || NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) && !$0.className.contains("StatusBar") }
        guard !isBusy else { return scheduleSlimDown() }   // 設定を開いている間などは、あとでやり直す

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--background"]
        configuration.activates = false
        configuration.addsToRecentItems = false
        shortcuts.suspend()   // 同じショートカットを、新しいプロセスが登録できるように手放す
        Log.write("slim down: relaunching in background")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil { exit(0) }
                Log.write("slim down failed: \(error!.localizedDescription)")
                self.shortcuts.resume()
            }
        }
    }

    // MARK: ウインドウ

    private func makeWindow() -> ReviewWindow {
        let window = ReviewWindow(files: files)
        window.onClose = { [weak self] closed in
            guard let self else { return }
            self.windows.removeAll { $0 === closed }
            if self.windows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
                self.scheduleSlimDown()
            }
        }
        hasLoadedEditor = true
        slimDownTimer?.invalidate()
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
                    // 撮った直後に貼り付けられるようにする。
                    // 番号タグや手書きを足した画像は「クリップボードにコピー」で入れ直す。
                    if let png = try? Data(contentsOf: file) { Paster.copy(image: png) }
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
        // 初めてのときは macOS の確認が出て、そこから設定画面へ進める。こちらの案内は重ねない
        // （重ねると、設定で許可したあとに macOS の確認だけが画面に取り残される）。
        let key = "requestedScreenCapture"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            CGRequestScreenCaptureAccess()
            return
        }
        let alert = NSAlert()
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = """
            システム設定の「プライバシーとセキュリティ › 画面収録とシステムオーディオ録音」で「ImageReview」をオンにしてから、このアプリを起動し直してください。

            すでにオンなのにこの表示が出るときは、以前のバージョンに出した許可が残っています。一覧の ImageReview を「−」で削除してから、もう一度オンにしてください。
            """
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 一覧に載っていなければ、ここで macOS が登録する（初回は macOS の確認も出る）。
        // 一覧から削除したあとに載せ直せるよう、毎回呼ぶ。
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: ショートカットとログイン項目

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    @objc func allowAutoPaste(_ sender: Any?) {
        Paster.requestPermission()
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
        ] + (Paster.isAllowed ? [] : [
            // 「AIに送る」で貼り付けまで自動にするための許可。まだのときだけ出す。
            item("AIへの自動貼り付けを許可…", #selector(allowAutoPaste)),
        ]) + [
            .separator(),
            item("ImageReview を完全に終了", #selector(quitCompletely)),
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
                item("ウインドウを閉じて裏で待機", #selector(NSApplication.terminate), key: "q"),
                item("ImageReview を完全に終了", #selector(quitCompletely)),
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
                // 引数つきの形（copy(_:) など）で書くこと。#selector(NSText.copy) と書くと、編集の「コピー」ではなく
                // NSObject の copy()（オブジェクトの複製）を指してしまい、⌘C を押した瞬間にアプリが異常終了する。
                item("カット", #selector(NSText.cut(_:)), key: "x"),
                item("コピー", #selector(NSText.copy(_:)), key: "c"),
                item("ペースト", #selector(NSText.paste(_:)), key: "v"),
                item("すべてを選択", #selector(NSText.selectAll(_:)), key: "a"),
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
