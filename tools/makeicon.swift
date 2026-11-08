// 產生 App 圖示（1024×1024 PNG）：深色圓角底＋薄荷綠紙飛機
// 用法：swift tools/makeicon.swift 輸出.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 圖示的安全範圍：四周留 100px
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1),
                    NSColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)])!.draw(in: bg, angle: -90)
NSColor(white: 1, alpha: 0.08).setStroke()
bg.lineWidth = 4
bg.stroke()

let mint = NSColor(red: 0.24, green: 0.86, blue: 0.71, alpha: 1)
let cfg = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [mint]))
if let sym = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2 - 10, y: (size - s.height) / 2 - 10, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("已輸出 \(out)")
