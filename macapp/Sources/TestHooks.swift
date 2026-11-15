#if TESTHOOKS
import AppKit
import WebKit

/// 動作確認用（`-DTESTHOOKS` でビルドしたときだけ入る）。環境変数で指定した操作を
/// 各ウインドウに対して実行し、結果を IRN_TEST_OUT に書き出して終了する。
extension AppDelegate {
    func runTestHooks() {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["IRN_TEST_OUT"] else { return }
        if env["IRN_TEST_LIGHT"] != nil { NSApp.appearance = NSAppearance(named: .aqua) }   // ライトモードの見た目を確認する
        let dir = URL(fileURLWithPath: out)
        let delay = Double(env["IRN_TEST_DELAY"] ?? "") ?? 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                var log = "windows=\(self.windows.count) policy=\(NSApp.activationPolicy().rawValue)\n"
                var sent = [String]()
                AIDestination.recordForTesting = { route, png in
                    sent.append("\(route) png=\(png.count)B")
                    try? png.write(to: dir.appendingPathComponent("sent-\(sent.count).png"))
                }
                defer { _ = sent }
                let center = ShortcutCenter.shared
                @MainActor func menuLog() -> String {
                    guard let menu = self.statusItem.menu else { return "" }
                    self.menuNeedsUpdate(menu)
                    let mods = { (m: NSEvent.ModifierFlags) in (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "") }
                    return "menu=" + menu.items.map { ($0.state == .on ? "✓" : "") + $0.title + ($0.keyEquivalent.isEmpty ? "" : " <\(mods($0.keyEquivalentModifierMask))\($0.keyEquivalent)>") }.joined(separator: " / ") + "\n"
                }
                @MainActor func states() -> String {
                    CaptureMode.allCases.map { "\($0.rawValue)=\(center.shortcut(for: $0).label) on=\(center.isEnabled($0)) active=\(center.isActive($0))" }.joined(separator: ", ") + "\n"
                }
                @MainActor func recorders(_ view: NSView) -> [ShortcutRecorder] {
                    (view as? ShortcutRecorder).map { [$0] } ?? view.subviews.flatMap(recorders)
                }
                @MainActor func snapshot(_ name: String) {
                    guard let view = self.settings.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                    // ウインドウの地色は写らないので、同じ外観の背景色を先に塗る。
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    view.effectiveAppearance.performAsCurrentDrawingAppearance {
                        NSColor.windowBackgroundColor.setFill()
                        NSRect(origin: .zero, size: view.bounds.size).fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                }
                @MainActor func press(_ recorder: ShortcutRecorder, _ flags: NSEvent.ModifierFlags, _ chars: String, _ code: Int) -> Bool {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: self.settings.window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
                    return recorder.performKeyEquivalent(with: event)
                }
                log += menuLog()
                if env["IRN_TEST_SETTINGS"] != nil {
                    center.resetAll()
                    log += "defaults: " + states()
                    self.settings.show()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let fields = recorders(self.settings.window.contentView!)
                    log += "recorders=\(fields.count) titles=\(fields.map(\.title))\n"
                    snapshot("settings-1.png")
                    // 2行目（範囲）を記録状態にして、1行目と同じ ⇧⌘7 を押す → 重複で拒否されるはず
                    fields[1].performClick(nil)
                    log += "recording=\(fields[1].isRecording) title=\(fields[1].title) while recording: " + states()
                    snapshot("settings-2.png")
                    log += "plain key handled=\(press(fields[1], [], "a", 0)) stillRecording=\(fields[1].isRecording)\n"
                    log += "dup handled=\(press(fields[1], [.command, .shift], "7", 26)) " + states()
                    snapshot("settings-3.png")
                    // 3行目（ウインドウ）を ⌃⌥⌘W に変更 → 通るはず
                    fields[2].performClick(nil)
                    log += "change handled=\(press(fields[2], [.control, .option, .command], "w", 13)) " + states()
                    // esc で取り消し
                    fields[0].performClick(nil)
                    log += "esc handled=\(press(fields[0], [], "\u{1B}", 53)) recording=\(fields[0].isRecording) " + states()
                    // 1行目（全画面）をオフ
                    center.setEnabled(false, for: .screen)
                    self.settings.show()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    log += "screen off: " + states()
                    snapshot("settings-4.png")
                    log += menuLog()
                    center.resetAll()
                    log += "reset: " + states()
                }
                if env["IRN_TEST_CLOSE"] != nil {
                    self.windows.forEach { $0.window.performClose(nil) }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    log += "after close: windows=\(self.windows.count) policy=\(NSApp.activationPolicy().rawValue)\n"
                }
                for (i, window) in self.windows.enumerated() {
                    log += "[\(i)] title=\(window.window.title) active=\(NSApp.isActive) visible=\(window.window.occlusionState.contains(.visible)) activeSpace=\(window.window.isOnActiveSpace) key=\(window.window.isKeyWindow)\n"
                    window.saveDestinationForTesting = dir.appendingPathComponent("saved-\(i).json")
                    if let js = env["IRN_TEST_JS"] {
                        do {
                            let value = try await window.webView.callAsyncJavaScript(js, arguments: [:], in: nil, contentWorld: .page)
                            log += "[\(i)] js=\(String(describing: value))\n"
                        } catch {
                            log += "[\(i)] js error=\(error)\n"
                        }
                    }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if let image = try? await window.webView.takeSnapshot(configuration: nil),
                       let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: dir.appendingPathComponent("snap-\(i).png"))
                    }
                }
                if env["IRN_TEST_PRINT"] != nil, let window = self.windows.first {
                    let operation = window.makePrintOperation()
                    operation.printInfo.jobDisposition = .save
                    operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = dir.appendingPathComponent("print.pdf")
                    operation.showsPrintPanel = false
                    operation.showsProgressPanel = false
                    operation.runModal(for: window.window, delegate: nil, didRun: nil, contextInfo: nil)
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                }
                if let hold = Double(env["IRN_TEST_HOLD"] ?? "") {   // 終了せずに待つ（常駐中のメモリを外から測るため）
                    try? log.write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
                    try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                }
                log += sent.map { "sent: \($0)\n" }.joined()
                try? log.write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
                exit(0)
            }
        }
    }
}
#endif
