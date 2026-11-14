// アプリアイコンの元画像（1024px PNG）を描く。使い方: swift make-icon.swift 出力.png
import AppKit

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: Int) -> NSColor {
    NSColor(deviceRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

// index.html のヘッダーと同じ、深緑の地に金色のチェック。
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(starting: color(0x2b6b5d), ending: color(0x1d4c42))!.draw(in: tile, angle: -90)

let check = NSBezierPath()
check.move(to: NSPoint(x: 272, y: 482))
check.line(to: NSPoint(x: 422, y: 332))
check.line(to: NSPoint(x: 752, y: 692))
check.lineWidth = 84
check.lineCapStyle = .round
check.lineJoinStyle = .round
color(0xf3c178).setStroke()
check.stroke()

NSGraphicsContext.current?.flushGraphics()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
