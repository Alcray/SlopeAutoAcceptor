import AppKit

final class OCRDebugWindowController: NSWindowController {
    init(pngData: Data, result: VisionOCRDebugResult) throws {
        guard let image = NSImage(data: pngData) else {
            throw VisionModelError.invalidResponse
        }

        let imageSize = result.imageSize
        let viewSize = NSSize(
            width: max(imageSize.width, 1),
            height: max(imageSize.height, 1)
        )
        let contentSize = NSSize(
            width: min(max(viewSize.width + 260, 720), 1120),
            height: min(max(viewSize.height + 150, 640), 860)
        )

        let summary = Self.makeSummary(result)
        let overlayView = OCRDebugOverlayView(image: image, result: result)
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        let itemList = Self.makeItemList(result)
        let listHeight = min(max(CGFloat(result.items.count) * 17 + 30, 82), 170)

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OCR View"
        window.contentView = contentView
        contentView.addSubview(summary)
        contentView.addSubview(overlayView)
        contentView.addSubview(itemList)
        window.center()

        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            summary.topAnchor.constraint(equalTo: contentView.topAnchor),
            summary.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: summary.bottomAnchor),
            overlayView.bottomAnchor.constraint(equalTo: itemList.topAnchor),
            overlayView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            itemList.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            itemList.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            itemList.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            itemList.heightAnchor.constraint(equalToConstant: listHeight)
        ])

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private static func makeSummary(_ result: VisionOCRDebugResult) -> NSView {
        let matchCount = result.items.filter { $0.matchedLabel != nil }.count
        let labels = result.targetLabels.joined(separator: ", ")
        let text = "\(result.items.count) OCR item\(result.items.count == 1 ? "" : "s") | \(matchCount) target match\(matchCount == 1 ? "" : "es") | Labels: \(labels)"

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        container.addSubview(label)

        let legend = NSTextField(labelWithString: "Green boxes are current target matches. Gray boxes are OCR text that is visible but not clickable.")
        legend.translatesAutoresizingMaskIntoConstraints = false
        legend.font = .systemFont(ofSize: 12)
        legend.textColor = .secondaryLabelColor
        legend.lineBreakMode = .byTruncatingTail
        container.addSubview(legend)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            legend.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            legend.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            legend.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            legend.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private static func makeItemList(_ result: VisionOCRDebugResult) -> NSScrollView {
        let lines: [String]
        if result.items.isEmpty {
            lines = ["No OCR text found in the picked region."]
        } else {
            lines = result.items.enumerated().map { index, item in
                let marker = item.matchedLabel.map { "MATCH \($0)" } ?? "OCR"
                let scoreText = item.matchScore.map { String(format: " match %.2f", $0) } ?? ""
                let box = item.boundingBox
                return String(
                    format: "%02d  %-10@  ocr %.2f%@  box x:%.2f y:%.2f w:%.2f h:%.2f  %@",
                    index + 1,
                    marker as NSString,
                    item.confidence,
                    scoreText as NSString,
                    box.minX,
                    box.minY,
                    box.width,
                    box.height,
                    item.text as NSString
                )
            }
        }

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .secondaryLabelColor
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.string = lines.joined(separator: "\n")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        return scrollView
    }
}

private final class OCRDebugOverlayView: NSView {
    private let image: NSImage
    private let result: VisionOCRDebugResult

    init(image: NSImage, result: VisionOCRDebugResult) {
        self.image = image
        self.result = result
        super.init(frame: NSRect(origin: .zero, size: result.imageSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let imageRect = aspectFitRect(
            imageSize: result.imageSize,
            in: bounds.insetBy(dx: 12, dy: 12)
        )
        NSColor.textBackgroundColor.setFill()
        imageRect.fill()
        image.draw(in: imageRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)

        NSColor.separatorColor.setStroke()
        let imageBorder = NSBezierPath(rect: imageRect)
        imageBorder.lineWidth = 1
        imageBorder.stroke()

        for item in result.items {
            drawBox(for: item, in: imageRect)
        }
    }

    private func aspectFitRect(imageSize: CGSize, in container: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return container
        }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return NSRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func drawBox(for item: VisionOCRTextItem, in imageRect: NSRect) {
        let box = item.boundingBox
        let rect = NSRect(
            x: imageRect.minX + box.minX * imageRect.width,
            y: imageRect.minY + box.minY * imageRect.height,
            width: box.width * imageRect.width,
            height: box.height * imageRect.height
        )

        let isMatch = item.matchedLabel != nil
        let stroke = isMatch ? NSColor.systemGreen : NSColor.systemGray
        let fill = stroke.withAlphaComponent(isMatch ? 0.20 : 0.10)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = isMatch ? 2 : 1
        path.stroke()

        drawLabel(for: item, box: rect, color: stroke)
    }

    private func drawLabel(for item: VisionOCRTextItem, box: NSRect, color: NSColor) {
        let prefix = item.matchedLabel.map { "MATCH \($0)" } ?? "OCR"
        let score = item.matchScore ?? item.confidence
        let text = "\(prefix) \(String(format: "%.2f", score)): \(item.text)"
        let font = NSFont.systemFont(ofSize: 11, weight: item.matchedLabel == nil ? .regular : .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let measured = (text as NSString).size(withAttributes: attributes)
        let labelWidth = min(max(measured.width + 10, 54), max(bounds.width - 8, 54))
        let labelHeight: CGFloat = 18
        let x = min(max(box.minX - 2, bounds.minX + 4), bounds.maxX - labelWidth - 4)
        let y = min(max(box.maxY + 4, bounds.minY + 4), bounds.maxY - labelHeight - 4)
        let labelRect = NSRect(x: x, y: y, width: labelWidth, height: labelHeight)

        let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        color.withAlphaComponent(0.92).setFill()
        labelPath.fill()

        (text as NSString).draw(
            in: labelRect.insetBy(dx: 5, dy: 2),
            withAttributes: attributes
        )
    }
}
