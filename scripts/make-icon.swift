import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = folder.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let rect = NSRect(x: 65, y: 65, width: 894, height: 894)
        let background = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(red: 0.04, green: 0.64, blue: 0.66, alpha: 1),
                   ending: NSColor(red: 0.01, green: 0.31, blue: 0.39, alpha: 1))!.draw(in: background, angle: -80)
        let track = NSBezierPath()
        track.appendArc(withCenter: NSPoint(x: 512, y: 475), radius: 258, startAngle: 210, endAngle: -30, clockwise: true)
        track.lineWidth = 61; track.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.22).setStroke(); track.stroke()
        let progress = NSBezierPath()
        progress.appendArc(withCenter: NSPoint(x: 512, y: 475), radius: 258, startAngle: 210, endAngle: 18, clockwise: true)
        progress.lineWidth = 61; progress.lineCapStyle = .round
        NSColor.white.setStroke(); progress.stroke()
        let needle = NSBezierPath(); needle.move(to: NSPoint(x: 512, y: 475)); needle.line(to: NSPoint(x: 645, y: 615))
        needle.lineWidth = 43; needle.lineCapStyle = .round; needle.stroke()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 474, y: 437, width: 76, height: 76)).fill()
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: NSRect(x: 392, y: 288, width: 240, height: 28), xRadius: 14, yRadius: 14).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", folder.appendingPathComponent("AppIcon.icns").path, iconset.path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(1) }
