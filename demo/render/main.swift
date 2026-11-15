// demo/demo.html をコマ送りで撮影して動画にする。
//   render <プロジェクトのルート> <出力.mp4>
//   render <プロジェクトのルート> --stills <出力フォルダ> <秒,秒,...>   … 確認用に指定した時刻の静止画だけ書き出す
// 先に編集画面をビルドしておく（npm --prefix web run build）。台本は web/dist を読み込む。
// ビルド: swiftc -O demo/render/main.swift macapp/Sources/AppSchemeHandler.swift -o render
import AppKit
import AVFoundation
import WebKit

let width = 1920, height = 1080
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: render <root> <out.mp4> | render <root> --stills <dir> <sec,sec,...>")
    exit(2)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// アプリと同じ仕組みで、プロジェクトのフォルダを 1 つのオリジンとして配信する（デモから編集画面を操作するため）。
let configuration = WKWebViewConfiguration()
configuration.setURLSchemeHandler(AppSchemeHandler(root: URL(fileURLWithPath: arguments[1])), forURLScheme: AppSchemeHandler.scheme)
// 編集画面の「AIに送る」の段は、Mac アプリの中（送り先の一覧と受け口があるとき）にだけ出る。
// 撮影でも同じ画面になるよう、中身のない受け口と送り先の一覧を、読み込む全フレームに用意する。
final class MessageSink: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
}
configuration.userContentController.add(MessageSink(), name: "native")
configuration.userContentController.addUserScript(WKUserScript(
    source: #"window.imageReviewAI={"claude":{"name":"Claude（チャット）","prefill":true},"claudeCode":{"name":"Claude Code","prefill":true},"chatgpt":{"name":"ChatGPT","prefill":true}};"#,
    injectionTime: .atDocumentStart, forMainFrameOnly: false))
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: height),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = web
// 動画は、撮影する Mac の設定に関係なくライトモードで撮る（暗い背景の上で画面がはっきり見える）。
web.appearance = NSAppearance(named: .aqua)
window.appearance = NSAppearance(named: .aqua)
window.orderBack(nil)
web.load(URLRequest(url: URL(string: "irn://app/demo/demo.html")!))

@MainActor func script(_ body: String, _ values: [String: Any] = [:]) async throws -> Any? {
    try await web.callAsyncJavaScript(body, arguments: values, in: nil, contentWorld: .page)
}

@MainActor func snapshot() async throws -> CGImage {
    let options = WKSnapshotConfiguration()
    options.snapshotWidth = NSNumber(value: width)
    let image = try await web.takeSnapshot(configuration: options)
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw CocoaError(.fileWriteUnknown) }
    return cgImage
}

@MainActor func run() async throws {
    while try await script("return !!window.demo") as? Bool != true {
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    guard let frames = try await script("await window.demo.ready; return window.demo.frames") as? Int,
          let fps = try await script("return window.demo.fps") as? Int else { throw CocoaError(.fileReadCorruptFile) }

    if arguments[2] == "--stills" {
        let directory = URL(fileURLWithPath: arguments[3])
        let wanted = Set(arguments[4].split(separator: ",").compactMap { Double($0) }.map { Int(($0 * Double(fps)).rounded()) })
        for frame in 0...min(frames - 1, wanted.max() ?? 0) {
            _ = try await script("await window.demo.step(frame)", ["frame": frame])
            guard wanted.contains(frame) else { continue }
            let png = NSBitmapImageRep(cgImage: try await snapshot()).representation(using: .png, properties: [:])!
            try png.write(to: directory.appendingPathComponent(String(format: "t%05.1f.png", Double(frame) / Double(fps))))
        }
        return
    }

    let output = URL(fileURLWithPath: arguments[2])
    try? FileManager.default.removeItem(at: output)
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_700_000, AVVideoMaxKeyFrameIntervalKey: fps * 4,
                                          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)

    let colors = CGColorSpace(name: CGColorSpace.sRGB)!
    for frame in 0..<frames {
        _ = try await script("await window.demo.step(frame)", ["frame": frame])
        let image = try await snapshot()
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colors,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        if frame % (fps * 5) == 0 { print("\(frame / fps) / \(frames / fps) 秒") }
    }
    input.markAsFinished()
    await writer.finishWriting()
    if let error = writer.error { throw error }
    print("書き出しました: \(output.path)")
}

Task { @MainActor in
    do {
        try await run()
        exit(0)
    } catch {
        print("失敗: \(error)")
        exit(1)
    }
}
application.run()
