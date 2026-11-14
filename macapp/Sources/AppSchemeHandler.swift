import UniformTypeIdentifiers
import WebKit

/// `irn://app/…` でアプリ本体（Resources/web）を配信する。
/// Finder やスクリーンショットから渡されたファイルも `/__open/<id>` として同じオリジンで
/// 1回だけ配信し、ページ側が fetch して通常の「開く」と同じ経路で読み込めるようにする。
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "irn"
    static let entry = URL(string: "irn://app/index.html")!

    private let root: URL
    private var handoffs: [String: URL] = [:]

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// ページに渡すファイルを登録し、取得用のIDを返す。
    func offer(_ file: URL) -> String {
        let id = UUID().uuidString
        handoffs[id] = file
        return id
    }

    static func mimeType(for file: URL) -> String {
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return mime.hasPrefix("text/") ? mime + "; charset=utf-8" : mime
    }

    private func resolve(_ url: URL) -> URL? {
        let path = url.path
        if path.hasPrefix("/__open/") {
            return handoffs.removeValue(forKey: String(path.dropFirst("/__open/".count)))
        }
        let file = root.appendingPathComponent(path == "/" ? "index.html" : String(path.dropFirst())).standardizedFileURL
        return file.path.hasPrefix(root.path + "/") ? file : nil
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        var status = 404, data = Data(), type = "text/plain"
        if let file = resolve(url), let body = try? Data(contentsOf: file, options: .mappedIfSafe) {
            status = 200
            data = body
            type = Self.mimeType(for: file)
        }
        let headers = ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
