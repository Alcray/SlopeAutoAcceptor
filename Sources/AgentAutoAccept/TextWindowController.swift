import AppKit

final class TextWindowController: NSWindowController {
    init(title: String, text: String) {
        let contentSize = NSSize(width: 760, height: 460)

        let contentView = FlippedDocumentView(frame: NSRect(origin: .zero, size: contentSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        let textField = NSTextField(wrappingLabelWithString: text)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.textColor = .labelColor
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.isEditable = false
        textField.isSelectable = true
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        contentView.addSubview(textField)

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = contentView

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            textField.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),
            textField.widthAnchor.constraint(equalToConstant: contentSize.width - 28)
        ])

        contentView.layoutSubtreeIfNeeded()
        let measuredHeight = textField.fittingSize.height + 28
        contentView.frame.size = NSSize(
            width: contentSize.width,
            height: max(contentSize.height, measuredHeight)
        )
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = scrollView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
