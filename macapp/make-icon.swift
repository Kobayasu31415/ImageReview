// アプリアイコンの元画像（1024px PNG）を描く。使い方: swift make-icon.swift 出力.png
// 図柄は「画像に赤い番号タグを付ける」。深緑の地に、画像を表すカードと、右上に重ねた番号タグ。
import AppKit

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

// 図柄は 160×160 の升目で設計してある（左上が原点）。アイコンの台座（824px、キャンバス中央）に合わせて拡大する。
let tile = NSRect(x: 100, y: 100, width: 824, height: 824), unit = tile.width / 160
func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: tile.minX + x * unit, y: tile.maxY - y * unit) }
func disk(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: at(x, y).x - r * unit, y: at(x, y).y - r * unit, width: r * unit * 2, height: r * unit * 2))
}
func withShadow(blur: CGFloat, offset: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x06201a, alpha: alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -offset)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// 台座
let background = NSGradient(starting: color(0x2b6b5d), ending: color(0x1d4c42))!
let plate = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
background.draw(in: plate, angle: -90)

// 画像を表すカード（太陽と山）
let cardRect = NSRect(x: at(26, 126).x, y: at(26, 126).y, width: 100 * unit, height: 80 * unit)
let card = NSBezierPath(roundedRect: cardRect, xRadius: 12 * unit, yRadius: 12 * unit)
withShadow(blur: 36, offset: 14, alpha: 0.35) {
    color(0xfbf6ee).setFill()
    card.fill()
}
color(0xf3c178).setFill()
disk(52, 72, 9).fill()
NSGraphicsContext.saveGraphicsState()
card.addClip()
let hills = NSBezierPath()
hills.move(to: at(26, 126))
for (x, y) in [(60, 92), (78, 108), (92, 96), (126, 124), (126, 126)] as [(CGFloat, CGFloat)] { hills.line(to: at(x, y)) }
hills.close()
color(0x2f7566).setFill()
hills.fill()
NSGraphicsContext.restoreGraphicsState()

// 番号タグ。カードとの境目は、台座と同じ色の縁で抜く。
NSGraphicsContext.saveGraphicsState()
disk(118, 50, 28).addClip()
background.draw(in: plate, angle: -90)
NSGraphicsContext.restoreGraphicsState()
withShadow(blur: 22, offset: 8, alpha: 0.3) {
    color(0xc93235).setFill()
    disk(118, 50, 22).fill()
}
let one = NSBezierPath()
one.move(to: at(111, 44))
one.line(to: at(120, 37))
one.line(to: at(120, 64))
one.lineWidth = 6 * unit
one.lineCapStyle = .round
one.lineJoinStyle = .round
NSColor.white.setStroke()
one.stroke()

NSGraphicsContext.current?.flushGraphics()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
