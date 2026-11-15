import AppKit
import WebKit

/// 修正ノート1件分のウインドウ。編集画面（web/ をビルドしたもの）を WKWebView で表示し、
/// ブラウザーなら標準で付いてくる機能（ファイル選択・確認ダイアログ・保存・印刷）を橋渡しする。
final class ReviewWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    let window: NSWindow
    let webView: WKWebView
    var onClose: ((ReviewWindow) -> Void)?
    #if TESTHOOKS
    var saveDestinationForTesting: URL?
    #endif

    private let files: AppSchemeHandler
    private var ready = false
    private var whenReady: [() -> Void] = []
    private var pendingOpens = 0
    private var titleObservation: NSKeyValueObservation?

    init(files: AppSchemeHandler) {
        self.files = files
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(files, forURLScheme: AppSchemeHandler.scheme)
        // WKWebView では window.print() が何もしないので、ネイティブの印刷に差し替える。
        // あわせて、この Mac で使える AI の送り先を編集画面に知らせる。
        config.userContentController.addUserScript(WKUserScript(
            source: "window.print=()=>webkit.messageHandlers.native.postMessage('print');" + AIDestination.catalogScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 860), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        config.userContentController.add(self, name: "native")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.title = "ImageReview"
        window.contentView = webView
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        titleObservation = webView.observe(\.title) { [weak self] view, _ in
            if let title = view.title, !title.isEmpty { self?.window.title = title }
        }
        webView.load(URLRequest(url: AppSchemeHandler.entry))
    }

    // MARK: ページとのやり取り

    private func page(_ script: String, _ arguments: [String: Any] = [:]) async -> Any? {
        try? await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page)
    }

    /// まだ何も開いておらず、新しいファイルを受け取れる状態か。
    func isEmpty() async -> Bool {
        if pendingOpens > 0 { return false }
        if !ready { return true }
        return await page("return window.imageReview.isEmpty()") as? Bool ?? false
    }

    func hasUnsavedChanges() async -> Bool {
        ready ? await page("return window.imageReview.isDirty()") as? Bool ?? false : false
    }

    func hasDocument() async -> Bool {
        ready ? await page("return window.imageReview.hasDocument()") as? Bool ?? false : false
    }

    /// ファイルをページに渡して開く。`.json` は保存済みノートとして扱う。
    func open(_ file: URL, name: String? = nil, removeWhenDone: Bool = false) {
        pendingOpens += 1
        let run = { [self] in
            let script = """
            try {
              const response = await fetch('/__open/' + id);
              if (!response.ok) throw Error();
              await window.imageReview.open(new File([await response.blob()], name, {type}), project);
            } catch {
              window.imageReview.notify('読み込めませんでした。ファイルを開けるか確認してください。');
            }
            """
            let arguments: [String: Any] = [
                "id": files.offer(file),
                "name": name ?? file.lastPathComponent,
                "type": AppSchemeHandler.mimeType(for: file),
                "project": file.pathExtension.lowercased() == "json",
            ]
            Task { @MainActor in
                _ = await self.page(script, arguments)
                self.pendingOpens -= 1
                if removeWhenDone { try? FileManager.default.removeItem(at: file) }
            }
        }
        if ready { run() } else { whenReady.append(run) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        let queued = whenReady
        whenReady = []
        queued.forEach { $0() }
    }

    // MARK: 印刷

    func makePrintOperation() -> NSPrintOperation {
        // ページの印刷レイアウトは A4 横・余白 10mm 前提（index.html の @page と同じ）。
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let margin = 10 / 25.4 * 72.0
        info.paperSize = NSSize(width: 841.89, height: 595.28)
        info.orientation = .landscape
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let operation = webView.printOperation(with: info)
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        return operation
    }

    func printDocument() {
        Task { @MainActor in
            guard await hasDocument() else { return }
            makePrintOperation().runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "print" { return printDocument() }
        // 「AIに送る」: 編集画面が作った注釈入りの画像（PNG の data URL）と指示文を受け取る。
        guard let body = message.body as? [String: Any], body["type"] as? String == "send",
              let destination = AIDestination(rawValue: body["target"] as? String ?? ""),
              let image = Self.decode(body["image"]) else { return }
        destination.send(image: image, imageWithNotes: Self.decode(body["imageWithNotes"]),
                         fresh: body["fresh"] as? Bool ?? true, prompt: body["prompt"] as? String ?? "")
    }

    /// data URL（data:image/png;base64,…）の中身を取り出す。
    private static func decode(_ dataURL: Any?) -> Data? {
        guard let text = dataURL as? String, let comma = text.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(text[text.index(after: comma)...]))
    }

    // MARK: ノート保存（ページ側の a[download] をネイティブの保存ダイアログへ）

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload {
            decisionHandler(.download)
        } else if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        // WKDownload は既存ファイルがあると失敗するので、上書きが決まった時点で先に消す。
        let accept = { (url: URL) in
            try? FileManager.default.removeItem(at: url)
            completionHandler(url)
        }
        #if TESTHOOKS
        if let url = saveDestinationForTesting { return accept(url) }
        #endif
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url { accept(url) } else { completionHandler(nil) }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ノートを保存できませんでした"
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }

    // MARK: ダイアログ

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        confirm(message, action: "OK", then: completionHandler)
    }

    private func confirm(_ message: String, action: String, then: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "キャンセル")
        alert.beginSheetModal(for: window) { then($0 == .alertFirstButtonReturn) }
    }

    // MARK: ウインドウ

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            guard await hasUnsavedChanges() else { return sender.close() }
            confirm("未保存の変更があります。保存せずに閉じますか？", action: "閉じる") { if $0 { sender.close() } }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        titleObservation = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        onClose?(self)
    }
}
