#!/usr/bin/env swift

import AppKit
import ImageIO
import UniformTypeIdentifiers

private let canvas = CGSize(width: 980, height: 640)
private let frameDelay = 0.08
private let frameCount = 70
private let controlSourceSize = CGSize(width: 1016, height: 1192)
private let controlFrame = CGRect(x: 18, y: 18, width: 477, height: 560)
private let testingFrame = CGRect(x: 520, y: 66, width: 438, height: 456)

private var controlReferenceImage: NSImage?

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

private enum Palette {
    static let desktop = NSColor(hex: 0xf4f4f4)
    static let chrome = NSColor(hex: 0xebebeb)
    static let window = NSColor(hex: 0xececec)
    static let field = NSColor(hex: 0xffffff)
    static let disabled = NSColor(hex: 0xf5f5f5)
    static let stroke = NSColor(hex: 0xc7c7c7)
    static let subtleStroke = NSColor(hex: 0xd6d6d6)
    static let ink = NSColor(hex: 0x202124)
    static let muted = NSColor(hex: 0x777777)
    static let blue = NSColor(hex: 0x0a84ff)
    static let green = NSColor(hex: 0x18864b)
    static let red = NSColor(hex: 0xff5f57)
    static let yellow = NSColor(hex: 0xffbd2e)
    static let grayDot = NSColor(hex: 0xd9d9d9)
}

private func eased(_ value: CGFloat) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

private func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height - y - height, width: width, height: height)
}

private func topPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: x, y: canvas.height - y)
}

private func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private func strokeRounded(
    _ rect: NSRect,
    radius: CGFloat,
    color: NSColor,
    lineWidth: CGFloat = 2,
    dash: [CGFloat] = []
) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color.setStroke()
    path.lineWidth = lineWidth
    if !dash.isEmpty {
        path.setLineDash(dash, count: dash.count, phase: 0)
    }
    path.stroke()
}

private func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

private func drawText(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = Palette.ink,
    align: NSTextAlignment = .left,
    mono: Bool = false
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byTruncatingTail
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSAttributedString(string: text, attributes: attributes)
        .draw(with: topRect(x, y, width, height), options: [.usesLineFragmentOrigin, .usesFontLeading])
}

private func drawNativeButton(
    _ title: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    disabled: Bool = false,
    pressed: Bool = false
) {
    let fill = disabled ? Palette.disabled : (pressed ? NSColor(hex: 0xe3e3e3) : Palette.field)
    let text = disabled ? NSColor(hex: 0xb4b4b4) : Palette.ink
    fillRounded(topRect(x, y, width, height), radius: 7, color: fill, stroke: Palette.stroke)
    drawText(title, x: x, y: y + 7, width: width, height: height - 10, size: 13, weight: .regular, color: text, align: .center)
}

private func drawWindowChrome(title: String, frame: CGRect) {
    fillRounded(topRect(frame.minX, frame.minY, frame.width, frame.height), radius: 13, color: Palette.window, stroke: Palette.stroke)
    let clip = NSBezierPath(roundedRect: topRect(frame.minX, frame.minY, frame.width, frame.height), xRadius: 13, yRadius: 13)
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    Palette.chrome.setFill()
    topRect(frame.minX, frame.minY, frame.width, 36).fill()
    NSGraphicsContext.restoreGraphicsState()

    drawLine(from: topPoint(frame.minX, frame.minY + 36), to: topPoint(frame.maxX, frame.minY + 36), color: Palette.stroke)
    fillRounded(topRect(frame.minX + 14, frame.minY + 12, 10, 10), radius: 5, color: Palette.red, stroke: NSColor(hex: 0xd95049))
    fillRounded(topRect(frame.minX + 32, frame.minY + 12, 10, 10), radius: 5, color: Palette.yellow, stroke: NSColor(hex: 0xd39b21))
    fillRounded(topRect(frame.minX + 50, frame.minY + 12, 10, 10), radius: 5, color: Palette.grayDot, stroke: NSColor(hex: 0xb7b7b7))
    drawText(title, x: frame.minX, y: frame.minY + 7, width: frame.width, height: 20, size: 13, weight: .semibold, color: NSColor(hex: 0x3f3f3f), align: .center)
}

private func drawControlReference() {
    guard let image = controlReferenceImage else {
        fatalError("Missing control-window reference image.")
    }

    image.draw(
        in: topRect(controlFrame.minX, controlFrame.minY, controlFrame.width, controlFrame.height),
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1
    )
}

private func controlRect(sourceX: CGFloat, sourceY: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    let scaleX = controlFrame.width / controlSourceSize.width
    let scaleY = controlFrame.height / controlSourceSize.height
    return topRect(
        controlFrame.minX + sourceX * scaleX,
        controlFrame.minY + sourceY * scaleY,
        width * scaleX,
        height * scaleY
    )
}

private func controlPoint(sourceX: CGFloat, sourceY: CGFloat) -> CGPoint {
    let scaleX = controlFrame.width / controlSourceSize.width
    let scaleY = controlFrame.height / controlSourceSize.height
    return CGPoint(
        x: controlFrame.minX + sourceX * scaleX,
        y: controlFrame.minY + sourceY * scaleY
    )
}

private func drawTestingGround(phase: Int, progress: CGFloat) {
    let opacity: CGFloat = phase == 0 ? 0.38 + eased(progress) * 0.34 : 1
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.cgContext.setAlpha(opacity)

    let x = testingFrame.minX
    let y = testingFrame.minY
    drawWindowChrome(title: "Vision Clicker Testing Ground", frame: testingFrame)

    let sidebarX = x + 18
    let workspaceX = x + 132
    let contentTop = y + 58
    drawText("Mock Agent", x: sidebarX, y: contentTop, width: 94, height: 22, size: 14, weight: .semibold)
    let items = ["New Agent", "Marketplace", "Project setup", "Review branch", "Smoke tests", "Release notes"]
    for (index, item) in items.enumerated() {
        drawText(
            item,
            x: sidebarX,
            y: contentTop + 36 + CGFloat(index * 24),
            width: 94,
            height: 18,
            size: 11,
            weight: item == "Review branch" ? .semibold : .regular,
            color: item == "Review branch" ? Palette.ink : Palette.muted
        )
    }
    drawLine(from: topPoint(x + 112, y + 36), to: topPoint(x + 112, y + testingFrame.height), color: Palette.subtleStroke)

    drawText("Smoke test request", x: workspaceX, y: y + 58, width: 180, height: 22, size: 15, weight: .semibold)
    drawNativeButton("Shuffle", x: x + 312, y: y + 55, width: 54, height: 28)
    drawNativeButton("Next Case", x: x + 372, y: y + 55, width: 68, height: 28)
    drawText(
        "Please run the final smoke test and tell me if the web app still answers.",
        x: workspaceX,
        y: y + 100,
        width: 280,
        height: 36,
        size: 12,
        color: Palette.ink
    )

    fillRounded(topRect(workspaceX, y + 152, 276, 46), radius: 6, color: NSColor(hex: 0xf8f8f8), stroke: Palette.subtleStroke)
    drawText("$ npm --prefix apps/web run smoke", x: workspaceX + 12, y: y + 167, width: 250, height: 16, size: 10.5, color: Palette.ink, mono: true)

    drawText("Running", x: workspaceX, y: y + 220, width: 80, height: 18, size: 11, color: Palette.muted)
    drawText("Auto-Run", x: workspaceX, y: y + 244, width: 80, height: 18, size: 11, color: Palette.muted)
    drawText("rerun", x: workspaceX, y: y + 268, width: 80, height: 18, size: 11, color: Palette.muted)

    let card = approvalCardRect()
    fillRounded(topRect(card.minX, card.minY, card.width, card.height), radius: 8, color: NSColor(hex: 0xf3f3f3), stroke: Palette.stroke)
    drawText("Ask Every Time", x: card.minX + 14, y: card.minY + 13, width: 120, height: 18, size: 11, weight: .medium, color: Palette.muted)

    let primary = primaryButtonRect()
    let title = phase == 5 && progress > 0.5 ? "Fetch" : "Run"
    drawNativeButton(title, x: primary.minX, y: primary.minY, width: primary.width, height: primary.height, pressed: phase == 4 && progress > 0.66)
    drawNativeButton("Skip", x: primary.minX - 62, y: primary.minY, width: 54, height: primary.height)

    let status = phase == 4 && progress > 0.68 ? "Clicked Run 1 time." : "OCR target candidate: \(title)"
    drawText(status, x: card.minX + 14, y: card.minY + 82, width: 180, height: 16, size: 10.5, color: phase == 4 && progress > 0.68 ? Palette.green : Palette.muted)

    NSGraphicsContext.restoreGraphicsState()
}

private func approvalCardRect() -> CGRect {
    CGRect(x: testingFrame.minX + 180, y: testingFrame.minY + 304, width: 236, height: 108)
}

private func primaryButtonRect() -> CGRect {
    let card = approvalCardRect()
    return CGRect(x: card.minX + 154, y: card.minY + 43, width: 58, height: 30)
}

private func scanRegionRect() -> CGRect {
    let card = approvalCardRect()
    return CGRect(x: card.minX - 14, y: card.minY - 14, width: card.width + 28, height: card.height + 28)
}

private func drawHighlights(phase: Int, progress: CGFloat) {
    switch phase {
    case 0:
        let rect = controlRect(sourceX: 660, sourceY: 1036, width: 196, height: 45)
        strokeRounded(rect.insetBy(dx: -3, dy: -3), radius: 8, color: Palette.blue, lineWidth: 2)
    case 1:
        let rect = controlRect(sourceX: 36, sourceY: 1038, width: 184, height: 44)
        strokeRounded(rect.insetBy(dx: -3, dy: -3), radius: 8, color: Palette.blue, lineWidth: 2)
    case 2:
        let region = scanRegionRect()
        let pad = (1 - eased(progress)) * 26
        strokeRounded(
            topRect(region.minX + pad, region.minY + pad, region.width - pad * 2, region.height - pad * 2),
            radius: 9,
            color: Palette.blue,
            lineWidth: 3,
            dash: [8, 5]
        )
    case 3:
        let region = scanRegionRect()
        strokeRounded(topRect(region.minX, region.minY, region.width, region.height), radius: 9, color: Palette.blue, lineWidth: 2)
        let scanY = region.minY + 10 + (region.height - 20) * progress
        drawLine(from: topPoint(region.minX + 8, scanY), to: topPoint(region.maxX - 8, scanY), color: Palette.green, width: 3)
        let primary = primaryButtonRect()
        fillRounded(topRect(primary.minX - 5, primary.minY - 5, primary.width + 10, primary.height + 10), radius: 8, color: Palette.green.withAlphaComponent(0.12), stroke: Palette.green, lineWidth: 2)
        fillRounded(topRect(primary.minX - 22, primary.maxY + 10, 100, 24), radius: 6, color: Palette.green)
        drawText("OCR: Run 0.92", x: primary.minX - 22, y: primary.maxY + 15, width: 100, height: 14, size: 10.5, weight: .semibold, color: .white, align: .center)
    case 4:
        let runOnce = controlRect(sourceX: 36, sourceY: 1105, width: 160, height: 43)
        if progress < 0.48 {
            strokeRounded(runOnce.insetBy(dx: -3, dy: -3), radius: 8, color: Palette.blue, lineWidth: 2)
        } else {
            let primary = primaryButtonRect()
            let pulse = sin(min(max((progress - 0.48) / 0.52, 0), 1) * .pi)
            strokeRounded(
                topRect(primary.minX - 8 - pulse * 8, primary.minY - 8 - pulse * 8, primary.width + 16 + pulse * 16, primary.height + 16 + pulse * 16),
                radius: 10,
                color: Palette.green.withAlphaComponent(0.75),
                lineWidth: 3
            )
        }
    case 5:
        let live = controlRect(sourceX: 36, sourceY: 313, width: 248, height: 43)
        strokeRounded(live.insetBy(dx: -3, dy: -3), radius: 8, color: Palette.green, lineWidth: 2)
        let primary = primaryButtonRect()
        fillRounded(topRect(primary.minX - 5, primary.minY - 5, primary.width + 10, primary.height + 10), radius: 8, color: Palette.green.withAlphaComponent(0.10), stroke: Palette.green, lineWidth: 2)
    default:
        break
    }
}

private func drawCursor(phase: Int, progress: CGFloat) {
    let testGround = controlPoint(sourceX: 760, sourceY: 1059)
    let pickRegion = controlPoint(sourceX: 128, sourceY: 1059)
    let runOnce = controlPoint(sourceX: 116, sourceY: 1127)
    let primary = primaryButtonRect()
    let primaryCenter = CGPoint(x: primary.midX + 5, y: primary.midY + 7)

    let position: CGPoint?
    let clickCenter: CGPoint?

    switch phase {
    case 0:
        position = interpolate(from: CGPoint(x: 120, y: 130), to: testGround, progress: eased(progress))
        clickCenter = progress > 0.68 ? testGround : nil
    case 1:
        position = interpolate(from: testGround, to: pickRegion, progress: eased(progress))
        clickCenter = progress > 0.72 ? pickRegion : nil
    case 4:
        if progress < 0.48 {
            let localProgress = progress / 0.48
            position = interpolate(from: pickRegion, to: runOnce, progress: eased(localProgress))
            clickCenter = progress > 0.34 ? runOnce : nil
        } else {
            let localProgress = (progress - 0.48) / 0.52
            position = interpolate(from: runOnce, to: primaryCenter, progress: eased(localProgress))
            clickCenter = progress > 0.76 ? primaryCenter : nil
        }
    default:
        position = nil
        clickCenter = nil
    }

    if let clickCenter {
        let local = phase == 4 ? (phase == 4 && progress < 0.48 ? progress / 0.48 : (progress - 0.48) / 0.52) : progress
        drawClickRipple(center: clickCenter, progress: local)
    }
    if let position {
        drawPointer(at: position)
    }
}

private func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
    CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
}

private func drawPointer(at position: CGPoint) {
    let path = NSBezierPath()
    path.move(to: topPoint(position.x, position.y))
    path.line(to: topPoint(position.x + 2, position.y + 26))
    path.line(to: topPoint(position.x + 10, position.y + 20))
    path.line(to: topPoint(position.x + 17, position.y + 35))
    path.line(to: topPoint(position.x + 25, position.y + 31))
    path.line(to: topPoint(position.x + 18, position.y + 17))
    path.line(to: topPoint(position.x + 30, position.y + 17))
    path.close()
    NSColor.white.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(0.72).setStroke()
    path.lineWidth = 1.4
    path.stroke()
}

private func drawClickRipple(center: CGPoint, progress: CGFloat) {
    let normalized = min(max((progress - 0.62) / 0.32, 0), 1)
    guard normalized > 0 else {
        return
    }
    let radius = 8 + normalized * 24
    let alpha = 0.45 * (1 - normalized)
    let path = NSBezierPath(ovalIn: topRect(center.x - radius, center.y - radius, radius * 2, radius * 2))
    Palette.blue.withAlphaComponent(alpha).setStroke()
    path.lineWidth = 3
    path.stroke()
}

private func drawCaption(phase: Int) {
    let captions = [
        ("Open Test Ground", "Use the real controls to bring up mock approval prompts."),
        ("Pick Region", "Draw around the approval area you want Vision Clicker to watch."),
        ("Save The Target Area", "The selected rectangle stays tight around the action buttons."),
        ("OCR Finds Run", "Apple Vision reads the selected region and scores matching labels."),
        ("Run Once", "The app clicks the detected button and leaves the workflow visible."),
        ("Switch To Live", "The same scan can repeat for new prompts such as Run or Fetch.")
    ]
    let (title, detail) = captions[min(phase, captions.count - 1)]
    let x: CGFloat = 74
    let y: CGFloat = 580
    fillRounded(topRect(x, y, 832, 44), radius: 10, color: NSColor.white.withAlphaComponent(0.88), stroke: Palette.subtleStroke)
    fillRounded(topRect(x + 16, y + 12, 20, 20), radius: 10, color: phase >= 4 ? Palette.green : Palette.blue)
    drawText("\(phase + 1)", x: x + 16, y: y + 15, width: 20, height: 12, size: 10.5, weight: .bold, color: .white, align: .center)
    drawText(title, x: x + 50, y: y + 8, width: 190, height: 18, size: 13, weight: .semibold)
    drawText(detail, x: x + 50, y: y + 26, width: 610, height: 14, size: 11, color: Palette.muted)

    let dotsX = x + 734
    for index in 0..<captions.count {
        let active = index == phase
        fillRounded(topRect(dotsX + CGFloat(index * 16), y + 18, active ? 18 : 8, 8), radius: 4, color: active ? Palette.blue : Palette.subtleStroke)
    }
}

private func phaseAndProgress(for frame: Int) -> (Int, CGFloat) {
    let lengths = [10, 11, 13, 14, 14, 8]
    var offset = frame
    for (phase, length) in lengths.enumerated() {
        if offset < length {
            return (phase, CGFloat(offset) / CGFloat(max(length - 1, 1)))
        }
        offset -= length
    }
    return (5, 1)
}

private func renderFrame(index: Int) -> CGImage {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create bitmap context for frame \(index)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    Palette.desktop.setFill()
    NSRect(origin: .zero, size: canvas).fill()

    let (phase, progress) = phaseAndProgress(for: index)
    drawControlReference()
    drawTestingGround(phase: phase, progress: progress)
    drawHighlights(phase: phase, progress: progress)
    drawCursor(phase: phase, progress: progress)
    drawCaption(phase: phase)

    guard let cgImage = bitmap.cgImage else {
        fatalError("Could not create CGImage for frame \(index)")
    }
    return cgImage
}

private func writeGIF(to outputURL: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.gif.identifier as CFString,
        frameCount,
        nil
    ) else {
        fatalError("Could not create GIF destination at \(outputURL.path)")
    }

    let gifProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ]
    CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay
        ]
    ]

    for frame in 0..<frameCount {
        CGImageDestinationAddImage(destination, renderFrame(index: frame), frameProperties as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not finalize GIF at \(outputURL.path)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let outputPath = arguments.first ?? "docs/assets/vision-clicker-demo.gif"
let referencePath = arguments.dropFirst().first ?? "docs/assets/vision-clicker-control.png"
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputURL = URL(fileURLWithPath: outputPath, relativeTo: cwd).standardizedFileURL
let referenceURL = URL(fileURLWithPath: referencePath, relativeTo: cwd).standardizedFileURL

guard let reference = NSImage(contentsOf: referenceURL) else {
    fatalError("Could not load control-window reference at \(referenceURL.path)")
}

controlReferenceImage = reference
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
writeGIF(to: outputURL)
print("Wrote \(outputURL.path)")
