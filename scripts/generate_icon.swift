#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root
    .appendingPathComponent("Packaging", isDirectory: true)
    .appendingPathComponent("AgentAutoAccept.iconset", isDirectory: true)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(filename: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for size in sizes {
    let image = drawIcon(pixelSize: size.pixels)
    try writePNG(image, to: iconsetURL.appendingPathComponent(size.filename))
}

func drawIcon(pixelSize: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    let scale = pixelSize / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let bounds = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    NSColor.clear.setFill()
    bounds.fill()

    let outer = NSBezierPath(
        roundedRect: bounds.insetBy(dx: s(48), dy: s(48)),
        xRadius: s(220),
        yRadius: s(220)
    )
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = s(28)
    shadow.shadowOffset = NSSize(width: 0, height: -s(14))
    shadow.set()
    NSColor(calibratedRed: 0.045, green: 0.052, blue: 0.066, alpha: 1).setFill()
    outer.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.21, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1)
    ])
    gradient?.draw(in: outer, angle: 310)

    let terminalRect = NSRect(x: s(170), y: s(262), width: s(684), height: s(500))
    let terminal = NSBezierPath(roundedRect: terminalRect, xRadius: s(62), yRadius: s(62))
    NSColor(calibratedRed: 0.012, green: 0.016, blue: 0.023, alpha: 0.92).setFill()
    terminal.fill()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    terminal.lineWidth = s(5)
    terminal.stroke()

    let dotColors = [
        NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.26, alpha: 1),
        NSColor(calibratedRed: 0.29, green: 0.86, blue: 0.43, alpha: 1)
    ]

    for (index, color) in dotColors.enumerated() {
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: s(228 + CGFloat(index) * 58),
                y: s(674),
                width: s(30),
                height: s(30)
            )
        ).fill()
    }

    drawPromptGlyph(scale: scale)
    drawApprovalMark(scale: scale)

    image.unlockFocus()
    return image
}

func drawPromptGlyph(scale: CGFloat) {
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: s(258), y: s(545)))
    prompt.line(to: NSPoint(x: s(370), y: s(488)))
    prompt.line(to: NSPoint(x: s(258), y: s(430)))
    NSColor(calibratedRed: 0.29, green: 0.82, blue: 1.0, alpha: 1).setStroke()
    prompt.lineWidth = s(40)
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    prompt.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: s(430), y: s(430)))
    cursor.line(to: NSPoint(x: s(600), y: s(430)))
    NSColor(calibratedRed: 0.84, green: 0.92, blue: 1.0, alpha: 0.92).setStroke()
    cursor.lineWidth = s(36)
    cursor.lineCapStyle = .round
    cursor.stroke()
}

func drawApprovalMark(scale: CGFloat) {
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let ringRect = NSRect(x: s(542), y: s(286), width: s(286), height: s(286))
    let ring = NSBezierPath(ovalIn: ringRect)
    NSColor(calibratedRed: 0.05, green: 0.69, blue: 0.44, alpha: 1).setFill()
    ring.fill()

    NSColor.white.withAlphaComponent(0.22).setStroke()
    ring.lineWidth = s(6)
    ring.stroke()

    let check = NSBezierPath()
    check.move(to: NSPoint(x: s(612), y: s(426)))
    check.line(to: NSPoint(x: s(674), y: s(365)))
    check.line(to: NSPoint(x: s(766), y: s(488)))
    NSColor.white.setStroke()
    check.lineWidth = s(38)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "AgentAutoAcceptIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not render PNG for \(url.lastPathComponent)"]
        )
    }

    try png.write(to: url)
}
