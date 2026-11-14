import AppKit
import Carbon.HIToolbox

/// 注釈入りの画像を渡せる AI アプリ。
/// 画像は URL では渡せないのでクリップボードに入れ、相手を（新規チャットなら指示文を入力済みで）開いてから
/// ⌘V を送って貼り付ける。キー入力を送るには「アクセシビリティ」の許可が要り、ない間は貼り付けだけ手動になる。
///
/// アプリを開く URL は各アプリの内部仕様で、公開されたものではない（2026-11 時点の Claude 5.11 / ChatGPT 26.11 で確認）。
/// アップデートで変わったら、ここの route(fresh:prompt:) を直す。
enum AIDestination: String, CaseIterable {
    case claude, claudeCode, chatgpt

    var name: String {
        switch self {
        case .claude: "Claude（チャット）"
        case .claudeCode: "Claude Code"
        case .chatgpt: "ChatGPT"
        }
    }

    private static func app(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
    private static var claudeApp: URL? { app("com.anthropic.claudefordesktop") }
    private static var chatGPTApp: URL? { app("com.openai.codex") }        // 現行の ChatGPT アプリ（codex:// に対応）
    private static var chatGPTClassicApp: URL? { app("com.openai.chat") }  // 旧来の ChatGPT アプリ（開き方が分からないので前面に出すだけ）

    /// この Mac で送り先に出せるか。Claude と ChatGPT はアプリがなくてもブラウザーで開ける。
    var isAvailable: Bool { self != .claudeCode || Self.claudeApp != nil }

    /// 新規チャットを、指示文を入力済みの状態で開けるか。
    var canPrefill: Bool { self != .chatgpt || Self.chatGPTApp != nil || Self.chatGPTClassicApp == nil }

    private static func link(_ base: String, _ query: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: base)
        let items = query.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !items.isEmpty { components?.queryItems = items }
        // URLComponents は + をそのまま残すが、受け取る側は空白として読むことがある。
        let query = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components?.percentEncodedQuery = query
        return components?.url
    }

    /// 開く先。URL（アプリのディープリンクか Web）か、前面に出すだけのアプリのどちらか。
    func route(fresh: Bool, prompt: String) -> (url: URL?, app: URL?) {
        switch self {
        case .claude:
            guard let app = Self.claudeApp else {
                return (fresh ? Self.link("https://claude.ai/new", ["q": prompt]) : Self.link("https://claude.ai/"), nil)
            }
            return fresh ? (Self.link("claude://claude.ai/new", ["surface": "chat", "q": prompt]), nil) : (nil, app)
        case .claudeCode:
            return (fresh ? Self.link("claude://code/new", ["q": prompt]) : Self.link("claude://code/continue", ["session": "last"]), nil)
        case .chatgpt:
            if let app = Self.chatGPTApp {
                return fresh ? (Self.link("codex://threads/new", ["prompt": prompt]), nil) : (nil, app)
            }
            if let app = Self.chatGPTClassicApp { return (nil, app) }
            return (fresh ? Self.link("https://chatgpt.com/", ["q": prompt]) : Self.link("https://chatgpt.com/"), nil)
        }
    }

    /// 編集画面に渡す送り先の一覧（JavaScript のオブジェクトリテラル）。
    static var catalogScript: String {
        let entries = allCases.filter(\.isAvailable).map { "\"\($0.rawValue)\":{\"name\":\"\($0.name)\",\"prefill\":\($0.canPrefill)}" }
        return "window.imageReviewAI={\(entries.joined(separator: ","))};"
    }

    #if TESTHOOKS
    static var recordForTesting: ((_ summary: String, _ png: Data) -> Void)?
    #endif

    /// 相手を開き、指示文と画像を渡す。
    /// - image: 番号タグと手書きを焼き込んだ画像。imageWithNotes はその下に指示文も入れたもの（指示文がなければ nil）。
    func send(image: Data, imageWithNotes: Data?, fresh: Bool, prompt: String) {
        let prefill = fresh && canPrefill && prompt.count <= 3000       // 指示文を URL に載せて入力済みにできる
        let route = route(fresh: fresh, prompt: prefill ? prompt : "")
        let desktopApp = route.app ?? route.url.flatMap { ["http", "https"].contains($0.scheme ?? "") ? nil : NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let bundleID = desktopApp.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let autoPaste = bundleID != nil && Paster.isAllowed             // ブラウザーで開く場合は読み込みを待てないので手動
        let pasteText = autoPaste && !prefill && !prompt.isEmpty        // 入力済みにできない指示文は、文字として貼る
        // 指示文を文字で渡せないときだけ、画像の中に入れたものを使う。
        let picture = prefill || pasteText ? image : imageWithNotes ?? image
        #if TESTHOOKS
        if let record = Self.recordForTesting {
            return record("\(rawValue) fresh=\(fresh) prefill=\(prefill) autoPaste=\(autoPaste) pasteText=\(pasteText) notesInImage=\(picture != image) url=\(route.url?.absoluteString ?? "-") app=\(route.app?.lastPathComponent ?? "-")", picture)
        }
        #endif
        let wasRunning = bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        Log.write("send \(rawValue) fresh=\(fresh) prefill=\(prefill) allowed=\(Paster.isAllowed) autoPaste=\(autoPaste) pasteText=\(pasteText) target=\(bundleID ?? "browser") running=\(wasRunning)")
        Paster.copy(image: picture)
        if let url = route.url {
            NSWorkspace.shared.open(url)
        } else if let app = route.app {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }

        let manual = "画像をコピーしました。⌘V で貼り付けてください"
        guard autoPaste, let bundleID else {
            // 許可がなくて自動で貼れないときは、そうと分かるように伝える（黙って手動に落とさない）。
            Toast.show(bundleID != nil ? manual + "（自動貼り付けは未許可）" : manual)
            if bundleID != nil { Paster.offerPermissionOnce() }
            return
        }
        // 起動直後は画面ができるまで時間がかかるので長めに待つ。
        Paster.whenFrontmost(bundleID, settle: wasRunning ? 1.2 : 4.0) { ready in
            Log.write("frontmost \(bundleID) ready=\(ready) → \(ready ? (pasteText ? "paste text, then image" : "paste image") : "manual")")
            guard ready else { return Toast.show(manual) }
            if pasteText {
                Paster.copy(text: prompt)
                Paster.pressPaste()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    Paster.copy(image: picture)
                    Paster.pressPaste()
                    Toast.show("\(self.name) に指示文と画像を貼り付けました")
                }
            } else {
                Paster.pressPaste()
                Toast.show("\(self.name) に画像を貼り付けました")
            }
        }
    }
}

/// クリップボードへのコピーと、前面のアプリへの ⌘V。
enum Paster {
    /// ほかのアプリにキー入力を送る許可（システム設定の「アクセシビリティ」）があるか。
    /// AXIsProcessTrusted は設定を変えた直後から反映される。CGPreflightPostEventAccess だけだと、
    /// 許可をオンにしても起動し直すまで false のままになることがある。
    static var isAllowed: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    /// 自動貼り付けを使うかどうかを一度だけ尋ねる。断られたら、以後は案内（トースト）だけにする。
    static func offerPermissionOnce() {
        let key = "offeredAutoPaste"
        guard !isAllowed, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "貼り付けまで自動で行いますか？"
        alert.informativeText = "「アクセシビリティ」を許可すると、送り先を開いたあとの ⌘V を ImageReview が代わりに行います。あとからメニューバーのアイコン →「AIへの自動貼り付けを許可…」でも設定できます。"
        alert.addButton(withTitle: "許可する…")
        alert.addButton(withTitle: "あとで")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { requestPermission() }
    }

    /// macOS の確認を出す（アプリを一覧に登録し、設定画面へ案内するのは macOS の確認に任せる）。
    /// こちらでも設定画面を開くと、設定で許可したあとに macOS の確認だけが画面に取り残される。
    static func requestPermission() {
        Log.write("request accessibility (allowed=\(isAllowed))")
        guard !isAllowed else { return Toast.show("自動貼り付けは、すでに許可されています") }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        // 許可されたら知らせる（設定は切り替えた直後から反映される）。
        var remaining = 180
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            remaining -= 1
            if isAllowed {
                timer.invalidate()
                Log.write("accessibility granted")
                Toast.show("自動貼り付けが使えるようになりました")
            } else if remaining <= 0 {
                timer.invalidate()
            }
        }
    }

    static func copy(image png: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    static func copy(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func pressPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    /// 指定のアプリが前面に来るのを待ち、画面が落ち着く時間をおいてから続きを実行する。来なければ false。
    static func whenFrontmost(_ bundleID: String, settle: TimeInterval, _ then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(10)
        func isFront() -> Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID }
        func poll() {
            if isFront() {
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) { then(isFront()) }
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
            } else {
                then(false)
            }
        }
        poll()
    }
}

/// 「AIに送る」の経過を ~/Library/Logs/ImageReview.log に残す。相手のアプリ側で何が起きたかは
/// こちらから見えないので、うまく渡らなかったときに判断と待ち時間を後から確かめるためのもの。指示文や画像は書かない。
enum Log {
    private static let file = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/ImageReview.log")

    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 200_000 {
            try? FileManager.default.removeItem(at: file)   // 溜まりすぎたら作り直す
        }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}

/// ほかのアプリが前面にいても見える、数秒で消える案内。
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String) {
        panel?.close()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 48, height: label.frame.height + 26)
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.9).cgColor
        box.layer?.cornerRadius = size.height / 2
        label.setFrameOrigin(NSPoint(x: 24, y: 13))
        box.addSubview(label)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let toast = NSPanel(contentRect: NSRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 48, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.level = .statusBar
        toast.ignoresMouseEvents = true
        toast.isReleasedWhenClosed = false
        toast.collectionBehavior = [.canJoinAllSpaces, .transient]
        toast.contentView = box
        toast.orderFrontRegardless()
        panel = toast

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard panel === toast else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; toast.animator().alphaValue = 0 }) {
                toast.close()
                if panel === toast { panel = nil }
            }
        }
    }
}
