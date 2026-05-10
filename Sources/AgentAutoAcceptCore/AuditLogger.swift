import Foundation

public enum AuditAction: String, Codable, Equatable {
    case detectedDryRun
    case pressed
    case pressFailed
    case ignoredPaused
}

public struct AuditEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var appName: String
    public var bundleIdentifier: String
    public var windowTitle: String
    public var matchedRule: String
    public var mode: AutoAcceptMode
    public var action: AuditAction
    public var confidence: Double
    public var commandPreview: String
    public var dedupeKey: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        matchedRule: String,
        mode: AutoAcceptMode,
        action: AuditAction,
        confidence: Double,
        commandPreview: String,
        dedupeKey: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.matchedRule = matchedRule
        self.mode = mode
        self.action = action
        self.confidence = confidence
        self.commandPreview = commandPreview
        self.dedupeKey = dedupeKey
    }
}

public protocol AuditSink: AnyObject {
    func append(_ event: AuditEvent) throws
}

public final class JSONLAuditLogger: AuditSink {
    public let fileURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = JSONLAuditLogger.defaultFileURL()) throws {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    public static func defaultFileURL() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return support
            .appendingPathComponent("AgentAutoAccept", isDirectory: true)
            .appendingPathComponent("audit.jsonl")
    }

    public func append(_ event: AuditEvent) throws {
        var data = try encoder.encode(event)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    public func recentEvents(limit: Int = 50) -> [AuditEvent] {
        guard
            let content = try? String(contentsOf: fileURL, encoding: .utf8),
            !content.isEmpty
        else {
            return []
        }

        return content
            .split(separator: "\n")
            .suffix(limit)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(AuditEvent.self, from: data)
            }
    }
}

