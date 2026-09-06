import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = directory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 512, y: CGFloat(pixels) / 512)
        let bounds = NSRect(x: 28, y: 28, width: 456, height: 456)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 110, yRadius: 110)
        NSGradient(starting: NSColor(srgbRed: 0.90, green: 0.42, blue: 0.17, alpha: 1), ending: NSColor(srgbRed: 0.60, green: 0.19, blue: 0.10, alpha: 1))!.draw(in: path, angle: -45)
        context.saveGState()
        path.addClip()
        NSColor(srgbRed: 1, green: 0.94, blue: 0.80, alpha: 0.22).setStroke()
        for step in stride(from: 84, through: 428, by: 86) {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: step, y: 28)); line.line(to: NSPoint(x: step, y: 484))
            line.move(to: NSPoint(x: 28, y: step)); line.line(to: NSPoint(x: 484, y: step))
            line.lineWidth = 1.5; line.stroke()
        }
        context.restoreGState()
        NSColor(srgbRed: 1, green: 0.94, blue: 0.80, alpha: 1).setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 203, y: 203, width: 106, height: 106))
        circle.lineWidth = 8; circle.stroke()
        for n in 0..<12 {
            let a = Double(n) * .pi / 6
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: 256 + cos(a) * 83, y: 256 + sin(a) * 83))
            ray.line(to: NSPoint(x: 256 + cos(a) * 132, y: 256 + sin(a) * 132))
            ray.lineWidth = 8; ray.lineCapStyle = .round; ray.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", directory.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
