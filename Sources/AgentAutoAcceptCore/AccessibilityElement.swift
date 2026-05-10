import ApplicationServices
import Foundation

public protocol AccessibilityElement: AnyObject {
    var accessibilityIdentity: Int { get }
    var role: String? { get }
    var roleDescription: String? { get }
    var title: String? { get }
    var valueText: String? { get }
    var descriptionText: String? { get }
    var identifier: String? { get }
    var canPress: Bool { get }
    var children: [any AccessibilityElement] { get }

    @discardableResult
    func performPress() -> Bool
}

public protocol MouseClickableAccessibilityElement: AnyObject {
    @discardableResult
    func performMouseClick() -> Bool
}

public final class SystemAccessibilityElement: AccessibilityElement, MouseClickableAccessibilityElement {
    private static let messagingTimeout: Float = 0.2

    private let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
    }

    public static func application(pid: pid_t) -> SystemAccessibilityElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return SystemAccessibilityElement(app)
    }

    public static func windows(forPID pid: pid_t) -> [SystemAccessibilityElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        let attributes = [
            kAXWindowsAttribute,
            kAXFocusedWindowAttribute,
            kAXMainWindowAttribute
        ]

        var seen = Set<CFHashCode>()
        var output: [AXUIElement] = []

        for attribute in attributes {
            for window in Self.elementListAttribute(attribute, from: app) {
                let hash = CFHash(window)
                guard !seen.contains(hash) else {
                    continue
                }

                seen.insert(hash)
                output.append(window)
            }
        }

        return output.map(SystemAccessibilityElement.init)
    }

    public static func focusedElement(forPID pid: pid_t) -> SystemAccessibilityElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return elementAttribute(kAXFocusedUIElementAttribute, from: app)
            .map(SystemAccessibilityElement.init)
    }

    public static func sampledVisibleElements(forPID pid: pid_t) -> [SystemAccessibilityElement] {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var seen = Set<CFHashCode>()
        var output: [AXUIElement] = []
        var anchors: [AXUIElement] = []
        let maxOutput = 220

        for bounds in visibleWindowBounds(forPID: pid).prefix(4) {
            for point in samplePoints(in: bounds) {
                guard output.count < maxOutput else {
                    return output.prefix(maxOutput).map(SystemAccessibilityElement.init)
                }

                var value: AXUIElement?
                guard
                    AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &value) == .success,
                    let element = value
                else {
                    continue
                }

                appendElementAndParents(
                    element,
                    expectedPID: pid,
                    seen: &seen,
                    output: &output,
                    anchors: &anchors,
                    maxOutput: maxOutput
                )
            }
        }

        for anchor in anchors {
            guard output.count < maxOutput else {
                break
            }

            appendDirectChildren(
                of: anchor,
                expectedPID: pid,
                seen: &seen,
                output: &output,
                maxOutput: maxOutput
            )
        }

        return output.prefix(maxOutput).map(SystemAccessibilityElement.init)
    }

    public var accessibilityIdentity: Int {
        Int(bitPattern: CFHash(element))
    }

    public var role: String? {
        stringAttribute(kAXRoleAttribute)
    }

    public var roleDescription: String? {
        stringAttribute(kAXRoleDescriptionAttribute)
    }

    public var title: String? {
        stringAttribute(kAXTitleAttribute)
    }

    public var valueText: String? {
        stringAttribute(kAXValueAttribute)
    }

    public var descriptionText: String? {
        stringAttribute(kAXDescriptionAttribute)
    }

    public var identifier: String? {
        stringAttribute(kAXIdentifierAttribute)
    }

    public var children: [any AccessibilityElement] {
        Self.childElements(from: element).map(SystemAccessibilityElement.init)
    }

    public var canPress: Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success else {
            return false
        }

        return (actions as? [String])?.contains(kAXPressAction as String) ?? false
    }

    @discardableResult
    public func performPress() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    public func performMouseClick() -> Bool {
        guard
            let frame = frame(),
            frame.width > 1,
            frame.height > 1,
            let source = CGEventSource(stateID: .hidSystemState)
        else {
            return false
        }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        usleep(40_000)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    private func stringAttribute(_ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let attributed = value as? NSAttributedString {
            return attributed.string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private func frame() -> CGRect? {
        guard
            let origin = pointAttribute(kAXPositionAttribute),
            let size = sizeAttribute(kAXSizeAttribute)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func pointAttribute(_ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
            let raw = value,
            CFGetTypeID(raw) == AXValueGetTypeID(),
            AXValueGetType(raw as! AXValue) == .cgPoint
        else {
            return nil
        }

        let axValue = raw as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
            let raw = value,
            CFGetTypeID(raw) == AXValueGetTypeID(),
            AXValueGetType(raw as! AXValue) == .cgSize
        else {
            return nil
        }

        let axValue = raw as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private static func elementArrayAttribute(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }

    private static func elementAttribute(_ name: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }

        guard
            let raw = value,
            CFGetTypeID(raw) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (raw as! AXUIElement)
    }

    private static func elementListAttribute(_ name: String, from element: AXUIElement) -> [AXUIElement] {
        if let single = elementAttribute(name, from: element) {
            return [single]
        }

        return elementArrayAttribute(name, from: element)
    }

    private static func childElements(from element: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXChildrenAttribute,
            "AXChildrenInNavigationOrder",
            "AXVisibleChildren",
            "AXContents",
            "AXTabs",
            "AXSelectedChildren",
            "AXTitleUIElement",
            "AXHeader"
        ]

        var seen = Set<CFHashCode>()
        var output: [AXUIElement] = []

        for attribute in attributes {
            for child in elementListAttribute(attribute, from: element) {
                let hash = CFHash(child)
                guard !seen.contains(hash) else {
                    continue
                }

                seen.insert(hash)
                output.append(child)
            }
        }

        return output
    }

    private static func visibleWindowBounds(forPID pid: pid_t) -> [CGRect] {
        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return windows.compactMap { info -> CGRect? in
            guard
                (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                (info[kCGWindowLayer as String] as? Int) == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds),
                rect.width > 80,
                rect.height > 80
            else {
                return nil
            }

            return rect
        }
    }

    private static func samplePoints(in rect: CGRect) -> [CGPoint] {
        let fractions: [(CGFloat, CGFloat)] = [
            (0.97, 0.74),
            (0.95, 0.74),
            (0.93, 0.74),
            (0.97, 0.70),
            (0.95, 0.70),
            (0.97, 0.66),
            (0.95, 0.62),
            (0.92, 0.58),
            (0.97, 0.54),
            (0.94, 0.50),
            (0.97, 0.46),
            (0.94, 0.42),
            (0.97, 0.38),
            (0.94, 0.34),
            (0.88, 0.74),
            (0.84, 0.66),
            (0.90, 0.66),
            (0.82, 0.60),
            (0.74, 0.48),
            (0.92, 0.88),
            (0.88, 0.76),
            (0.66, 0.36),
            (0.52, 0.72),
            (0.50, 0.50),
            (0.32, 0.52)
        ]

        return fractions.map { x, y in
            CGPoint(
                x: rect.minX + rect.width * x,
                y: rect.minY + rect.height * y
            )
        }
    }

    private static func appendElementAndParents(
        _ element: AXUIElement,
        expectedPID: pid_t,
        seen: inout Set<CFHashCode>,
        output: inout [AXUIElement],
        anchors: inout [AXUIElement],
        maxOutput: Int
    ) {
        var current: AXUIElement? = element

        for _ in 0..<10 {
            guard output.count < maxOutput else {
                return
            }

            guard
                let item = current,
                elementBelongsToExpectedPID(item, expectedPID)
            else {
                return
            }

            let hash = CFHash(item)
            if seen.insert(hash).inserted {
                output.append(item)
                anchors.append(item)
            }

            current = elementAttribute(kAXParentAttribute, from: item)
        }
    }

    private static func appendDirectChildren(
        of element: AXUIElement,
        expectedPID: pid_t,
        seen: inout Set<CFHashCode>,
        output: inout [AXUIElement],
        maxOutput: Int
    ) {
        let attributes = [
            kAXChildrenAttribute,
            "AXChildrenInNavigationOrder",
            "AXVisibleChildren",
            "AXContents"
        ]
        var appendedForParent = 0

        for attribute in attributes {
            for child in elementListAttribute(attribute, from: element) {
                guard output.count < maxOutput, appendedForParent < 16 else {
                    return
                }
                guard elementBelongsToExpectedPID(child, expectedPID) else {
                    continue
                }

                let hash = CFHash(child)
                if seen.insert(hash).inserted {
                    output.append(child)
                    appendedForParent += 1
                }
            }
        }
    }

    private static func elementBelongsToExpectedPID(_ element: AXUIElement, _ expectedPID: pid_t) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return false
        }

        return pid == expectedPID
    }
}
