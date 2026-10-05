import AppKit
import Foundation

// Render the app's own waveform mark offscreen. No borrowed brand artwork.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        NSColor(red: 0.105, green: 0.115, blue: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 464, height: 464), xRadius: 108, yRadius: 108).fill()
        NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1).setFill()
        let heights: [CGFloat] = [72, 140, 220, 284, 196, 116, 60]
        for (i, height) in heights.enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 108 + CGFloat(i) * 44, y: (512 - height) / 2, width: 28, height: height), xRadius: 14, yRadius: 14).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
