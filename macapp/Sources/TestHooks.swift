#if TESTHOOKS
import AppKit
import WebKit

/// 動作確認用（`-DTESTHOOKS` でビルドしたときだけ入る）。環境変数で指定した操作を
/// 各ウインドウに対して実行し、結果を IRN_TEST_OUT に書き出して終了する。
extension AppDelegate {
    func runTestHooks() {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["IRN_TEST_OUT"] else { return }
        let dir = URL(fileURLWithPath: out)
        let delay = Double(env["IRN_TEST_DELAY"] ?? "") ?? 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                var log = "windows=\(self.windows.count) policy=\(NSApp.activationPolicy().rawValue)\n"
                if let menu = self.statusItem.menu {
                    self.menuNeedsUpdate(menu)
                    let titles = menu.items.map { ($0.state == .on ? "✓" : "") + $0.title + ($0.submenu.map { "[" + $0.items.map { ($0.state == .on ? "✓" : "") + $0.title }.joined(separator: ",") + "]" } ?? "") }
                    log += "menu=\(titles.joined(separator: " / "))\n"
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
                try? log.write(to: dir.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
                exit(0)
            }
        }
    }
}
#endif
