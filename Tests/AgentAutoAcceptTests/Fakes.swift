import AgentAutoAcceptCore
import Foundation

final class FakeAccessibilityElement: AccessibilityElement, MouseClickableAccessibilityElement {
    var accessibilityIdentity: Int {
        ObjectIdentifier(self).hashValue
    }

    var role: String?
    var roleDescription: String?
    var title: String?
    var valueText: String?
    var descriptionText: String?
    var identifier: String?
    var canPress: Bool
    private var storedChildren: [any AccessibilityElement]
    var childrenReadCount = 0
    private(set) var pressCount = 0
    private(set) var mouseClickCount = 0
    var pressResult = true
    var mouseClickResult = true

    var children: [any AccessibilityElement] {
        get {
            childrenReadCount += 1
            return storedChildren
        }
        set {
            storedChildren = newValue
        }
    }

    init(
        role: String? = nil,
        roleDescription: String? = nil,
        title: String? = nil,
        valueText: String? = nil,
        descriptionText: String? = nil,
        identifier: String? = nil,
        canPress: Bool = false,
        children: [any AccessibilityElement] = []
    ) {
        self.role = role
        self.roleDescription = roleDescription
        self.title = title
        self.valueText = valueText
        self.descriptionText = descriptionText
        self.identifier = identifier
        self.canPress = canPress
        self.storedChildren = children
    }

    @discardableResult
    func performPress() -> Bool {
        pressCount += 1
        return pressResult
    }

    @discardableResult
    func performMouseClick() -> Bool {
        mouseClickCount += 1
        return mouseClickResult
    }
}

final class RecordingAuditSink: AuditSink {
    private(set) var events: [AuditEvent] = []

    func append(_ event: AuditEvent) throws {
        events.append(event)
    }
}

final class ThrowingAuditSink: AuditSink {
    func append(_ event: AuditEvent) throws {
        throw NSError(
            domain: "AgentAutoAcceptTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic audit failure"]
        )
    }
}
