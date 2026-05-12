import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import Vision

enum AutomationMode: String, Codable {
    case live
    case paused

    var displayName: String {
        switch self {
        case .live:
            return "Live"
        case .paused:
            return "Paused"
        }
    }

    var shortStatus: String {
        switch self {
        case .live:
            return "VC Live"
        case .paused:
            return "VC Off"
        }
    }
}

struct VisionAutomationSettings: Codable {
    var mode: AutomationMode
    var targetLabel: String
    var pollingInterval: TimeInterval
    var confidenceThreshold: Double
    var telemetryEnabled: Bool
    var captureRegionQuartz: CGRect?

    init(
        mode: AutomationMode = .paused,
        targetLabel: String = "Run",
        pollingInterval: TimeInterval = 2.0,
        confidenceThreshold: Double = 0.20,
        telemetryEnabled: Bool = true,
        captureRegionQuartz: CGRect? = nil
    ) {
        self.mode = mode
        self.targetLabel = targetLabel
        self.pollingInterval = pollingInterval
        self.confidenceThreshold = confidenceThreshold
        self.telemetryEnabled = telemetryEnabled
        self.captureRegionQuartz = captureRegionQuartz
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case targetLabel
        case pollingInterval
        case confidenceThreshold
        case telemetryEnabled
        case captureRegionQuartz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultSettings = VisionAutomationSettings()

        mode = try container.decodeIfPresent(AutomationMode.self, forKey: .mode) ?? defaultSettings.mode
        targetLabel = try container.decodeIfPresent(String.self, forKey: .targetLabel) ?? defaultSettings.targetLabel
        pollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingInterval) ?? defaultSettings.pollingInterval
        confidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .confidenceThreshold) ?? defaultSettings.confidenceThreshold
        telemetryEnabled = try container.decodeIfPresent(Bool.self, forKey: .telemetryEnabled) ?? defaultSettings.telemetryEnabled
        captureRegionQuartz = try container.decodeIfPresent(CGRect.self, forKey: .captureRegionQuartz)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(targetLabel, forKey: .targetLabel)
        try container.encode(pollingInterval, forKey: .pollingInterval)
        try container.encode(confidenceThreshold, forKey: .confidenceThreshold)
        try container.encode(telemetryEnabled, forKey: .telemetryEnabled)
        try container.encodeIfPresent(captureRegionQuartz, forKey: .captureRegionQuartz)
    }
}

enum TargetLabelParser {
    static func labels(from text: String, fallback: String = "Run") -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n|")
        let rawLabels = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let labels = rawLabels.isEmpty ? [fallback] : rawLabels
        var seen = Set<String>()
        var uniqueLabels: [String] = []

        for label in labels {
            let key = label.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            uniqueLabels.append(label)
        }

        return uniqueLabels
    }

    static func canonicalText(from text: String, fallback: String = "Run") -> String {
        labels(from: text, fallback: fallback).joined(separator: ", ")
    }
}

final class VisionSettingsStore {
    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults?
    private let key = "vision-clicker.settings.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: "dev.agentautoaccept.app")
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
    }

    func load() -> VisionAutomationSettings {
        var settings = decode(from: defaults) ?? decode(from: legacyDefaults) ?? VisionAutomationSettings()

        if settings.captureRegionQuartz == nil, let legacyRegion = decode(from: legacyDefaults)?.captureRegionQuartz {
            settings.captureRegionQuartz = legacyRegion
        }

        return settings
    }

    func save(_ settings: VisionAutomationSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func decode(from defaults: UserDefaults?) -> VisionAutomationSettings? {
        guard
            let data = defaults?.data(forKey: key),
            let settings = try? decoder.decode(VisionAutomationSettings.self, from: data)
        else {
            return nil
        }

        return settings
    }
}

enum ScreenCapturePermission {
    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

enum DisplayCoordinateSpace {
    private struct ScreenMapping {
        let appKitFrame: CGRect
        let quartzBounds: CGRect
    }

    static func appKitToQuartz(point: CGPoint) -> CGPoint {
        guard let mapping = appKitMapping(containing: point) else {
            return legacyAppKitToQuartz(point: point)
        }

        return CGPoint(
            x: mapping.quartzBounds.minX + (point.x - mapping.appKitFrame.minX),
            y: mapping.quartzBounds.minY + (mapping.appKitFrame.maxY - point.y)
        )
    }

    static func quartzToAppKit(point: CGPoint) -> CGPoint {
        guard let mapping = quartzMapping(containing: point) else {
            return legacyQuartzToAppKit(point: point)
        }

        return CGPoint(
            x: mapping.appKitFrame.minX + (point.x - mapping.quartzBounds.minX),
            y: mapping.appKitFrame.maxY - (point.y - mapping.quartzBounds.minY)
        )
    }

    static func appKitToQuartz(rect: CGRect) -> CGRect {
        let rect = rect.standardized
        guard let mapping = appKitMapping(for: rect) else {
            return legacyAppKitToQuartz(rect: rect)
        }

        return CGRect(
            x: mapping.quartzBounds.minX + (rect.minX - mapping.appKitFrame.minX),
            y: mapping.quartzBounds.minY + (mapping.appKitFrame.maxY - rect.maxY),
            width: rect.width,
            height: rect.height
        )
    }

    static func quartzToAppKit(rect: CGRect) -> CGRect {
        let rect = rect.standardized
        guard let mapping = quartzMapping(for: rect) else {
            return legacyQuartzToAppKit(rect: rect)
        }

        return CGRect(
            x: mapping.appKitFrame.minX + (rect.minX - mapping.quartzBounds.minX),
            y: mapping.appKitFrame.maxY - ((rect.minY - mapping.quartzBounds.minY) + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    static func normalizedQuartz(rect: CGRect) -> CGRect {
        let rect = rect.standardized
        if quartzMapping(for: rect) != nil {
            return rect
        }

        let legacyAppKitRect = legacyQuartzToAppKit(rect: rect)
        return appKitToQuartz(rect: legacyAppKitRect)
    }

    static func isQuartzRectOnAnyDisplay(_ rect: CGRect) -> Bool {
        quartzMapping(for: rect.standardized) != nil
    }

    private static var legacyMaxGlobalY: CGFloat {
        let values = NSScreen.screens.map(\.frame.maxY)
        if let maxValue = values.max() {
            return maxValue
        }
        return NSScreen.main?.frame.maxY ?? 0
    }

    private static var mappings: [ScreenMapping] {
        NSScreen.screens.compactMap { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            return ScreenMapping(
                appKitFrame: screen.frame,
                quartzBounds: CGDisplayBounds(displayID)
            )
        }
    }

    private static func appKitMapping(containing point: CGPoint) -> ScreenMapping? {
        mappings.first { $0.appKitFrame.contains(point) } ?? mappings.max { first, second in
            squaredDistance(from: point, to: first.appKitFrame) > squaredDistance(from: point, to: second.appKitFrame)
        }
    }

    private static func quartzMapping(containing point: CGPoint) -> ScreenMapping? {
        mappings.first { $0.quartzBounds.contains(point) } ?? mappings.max { first, second in
            squaredDistance(from: point, to: first.quartzBounds) > squaredDistance(from: point, to: second.quartzBounds)
        }
    }

    private static func appKitMapping(for rect: CGRect) -> ScreenMapping? {
        mapping(for: rect, using: \.appKitFrame)
    }

    private static func quartzMapping(for rect: CGRect) -> ScreenMapping? {
        mapping(for: rect, using: \.quartzBounds)
    }

    private static func mapping(
        for rect: CGRect,
        using keyPath: KeyPath<ScreenMapping, CGRect>
    ) -> ScreenMapping? {
        let candidates = mappings
            .map { mapping in
                (mapping, area(mapping[keyPath: keyPath].intersection(rect)))
            }
            .filter { $0.1 > 0 }

        return candidates.max { first, second in
            first.1 < second.1
        }?.0
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return 0
        }
        return rect.width * rect.height
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }

    private static func legacyAppKitToQuartz(point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: legacyMaxGlobalY - point.y)
    }

    private static func legacyQuartzToAppKit(point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: legacyMaxGlobalY - point.y)
    }

    private static func legacyAppKitToQuartz(rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: legacyMaxGlobalY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func legacyQuartzToAppKit(rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: legacyMaxGlobalY - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }
}

enum MousePermission {
    static var hasAccess: Bool {
        AXIsProcessTrusted()
    }

    static func request() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

struct CapturedRegionImage {
    let pngData: Data
    let pixelSize: CGSize
}

enum ScreenCaptureError: LocalizedError {
    case noPermission
    case invalidRegion
    case noImage
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Screen Recording permission is required."
        case .invalidRegion:
            return "Capture region is not valid."
        case .noImage:
            return "Could not capture the selected region."
        case .pngEncodingFailed:
            return "Could not encode the captured region."
        }
    }
}

final class ScreenCaptureService {
    func capturePNG(inQuartzRect rect: CGRect, maxSide: CGFloat = 1800) throws -> CapturedRegionImage {
        guard ScreenCapturePermission.hasAccess else {
            throw ScreenCaptureError.noPermission
        }

        let clippedRect = rect.standardized.integral
        guard clippedRect.width >= 6, clippedRect.height >= 6 else {
            throw ScreenCaptureError.invalidRegion
        }

        guard
            let image = CGWindowListCreateImage(
                clippedRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
        else {
            throw ScreenCaptureError.noImage
        }

        let processed = resizedImageIfNeeded(image, maxSide: maxSide) ?? image
        let nsImage = NSImage(
            cgImage: processed,
            size: NSSize(width: processed.width, height: processed.height)
        )

        guard
            let tiff = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ScreenCaptureError.pngEncodingFailed
        }

        return CapturedRegionImage(
            pngData: pngData,
            pixelSize: CGSize(width: processed.width, height: processed.height)
        )
    }

    private func resizedImageIfNeeded(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longestSide = max(width, height)
        guard longestSide > maxSide, longestSide > 0 else {
            return nil
        }

        let scale = maxSide / longestSide
        let newWidth = max(1, Int((width * scale).rounded()))
        let newHeight = max(1, Int((height * scale).rounded()))

        guard
            let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}

struct VisionTargetDecision {
    let isFound: Bool
    let x: Double
    let y: Double
    let confidence: Double
    let note: String
}

struct OCRTextItem: Codable {
    let text: String
    let confidence: Double
    let boundingBox: TelemetryRect
}

struct OCRTextSnapshot: Codable {
    let items: [OCRTextItem]

    var displayText: String {
        items.map(\.text).joined(separator: " ")
    }

    var normalizedSignature: String {
        displayText
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    var preview: String {
        items
            .prefix(10)
            .map { item in
                "\"\(item.text)\" \(String(format: "%.2f", item.confidence))"
            }
            .joined(separator: ", ")
    }
}

struct VisionTargetAnalysis {
    let decision: VisionTargetDecision
    let textSnapshot: OCRTextSnapshot
}

private struct ResolvedTargetCoordinates {
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let source: String
}

enum VisionModelError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Model response was not valid."
        }
    }
}

final class VisionModelClient {
    func analyzeTarget(
        pngData: Data,
        targetLabel: String
    ) async throws -> VisionTargetAnalysis {
        try locateTargetWithAppleOCR(
            pngData: pngData,
            targetLabel: targetLabel
        )
    }

    private func locateTargetWithAppleOCR(
        pngData: Data,
        targetLabel: String
    ) throws -> VisionTargetAnalysis {
        guard
            let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw VisionModelError.invalidResponse
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.01

        let targets = TargetLabelParser.labels(from: targetLabel)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let textSnapshot = OCRTextSnapshot(
            items: (request.results ?? []).compactMap { observation -> OCRTextItem? in
                guard let recognized = observation.topCandidates(1).first else {
                    return nil
                }

                return OCRTextItem(
                    text: recognized.string,
                    confidence: Double(recognized.confidence),
                    boundingBox: TelemetryRect(observation.boundingBox)
                )
            }
        )

        let normalizedTargets = targets.map { label in
            (
                label: label,
                normalized: normalizedOCRText(label)
            )
        }.filter { !$0.normalized.isEmpty }

        let recognizedItems = (request.results ?? []).compactMap { observation -> (VNRecognizedTextObservation, VNRecognizedText)? in
            guard let recognized = observation.topCandidates(1).first else {
                return nil
            }

            return (observation, recognized)
        }

        let matches = recognizedItems.compactMap { observation, recognized -> (VisionTargetDecision, Double)? in
            let normalizedText = normalizedOCRText(recognized.string)
            guard let matchedTarget = normalizedTargets.first(where: { target in
                normalizedText == target.normalized || normalizedText.contains(target.normalized)
            }) else {
                return nil
            }

            let box = observation.boundingBox
            let decision = VisionTargetDecision(
                isFound: true,
                x: Double(box.midX),
                y: Double(1 - box.midY),
                confidence: Double(recognized.confidence),
                note: "OCR fuzzy matched \"\(recognized.string)\" as \"\(matchedTarget.label)\""
            )
            return (decision, Double(recognized.confidence))
        }

        if let best = matches.max(by: { $0.1 < $1.1 })?.0 {
            return VisionTargetAnalysis(decision: best, textSnapshot: textSnapshot)
        }

        let decision = VisionTargetDecision(
            isFound: false,
            x: 0,
            y: 0,
            confidence: 0,
            note: textSnapshot.preview.isEmpty
                ? "OCR saw no text in the selected region."
                : "OCR saw: \(textSnapshot.preview)"
        )
        return VisionTargetAnalysis(decision: decision, textSnapshot: textSnapshot)
    }

    private func normalizedOCRText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum MouseClickError: LocalizedError {
    case noAccessibility
    case eventSourceMissing
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .noAccessibility:
            return "Accessibility permission is required to click."
        case .eventSourceMissing:
            return "Could not create event source."
        case .eventCreationFailed:
            return "Could not create click events."
        }
    }
}

struct MouseActionTrace {
    let originalPoint: CGPoint?
    let targetPoint: CGPoint
    let preClickPoint: CGPoint?
    let postActionPoint: CGPoint?
    let restoredPoint: CGPoint?
}

struct TelemetryPoint: Codable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }
}

struct TelemetrySize: Codable {
    let width: Double
    let height: Double

    init(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }
}

struct TelemetryRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = Double(rect.minX)
        y = Double(rect.minY)
        width = Double(rect.width)
        height = Double(rect.height)
    }
}

private struct TelemetryDecision: Codable {
    let found: Bool
    let x: Double
    let y: Double
    let confidence: Double
    let note: String

    init(_ decision: VisionTargetDecision) {
        found = decision.isFound
        x = decision.x
        y = decision.y
        confidence = decision.confidence
        note = decision.note
    }
}

private struct TelemetryMouseTrace: Codable {
    let originalPoint: TelemetryPoint?
    let targetPoint: TelemetryPoint
    let preClickPoint: TelemetryPoint?
    let postActionPoint: TelemetryPoint?
    let restoredPoint: TelemetryPoint?

    init(_ trace: MouseActionTrace) {
        originalPoint = trace.originalPoint.map(TelemetryPoint.init)
        targetPoint = TelemetryPoint(trace.targetPoint)
        preClickPoint = trace.preClickPoint.map(TelemetryPoint.init)
        postActionPoint = trace.postActionPoint.map(TelemetryPoint.init)
        restoredPoint = trace.restoredPoint.map(TelemetryPoint.init)
    }
}

private struct ClickTelemetrySample: Codable {
    let schemaVersion: Int
    let id: String
    let timestamp: String
    let classification: String
    let classificationReason: String
    let targetLabels: String
    let confidenceThreshold: Double
    let beforeImage: String
    let afterImage: String
    let capturePixelSize: TelemetrySize
    let regionQuartz: TelemetryRect
    let regionAppKit: TelemetryRect
    let clickLocal: TelemetryPoint
    let clickQuartz: TelemetryPoint
    let clickAppKit: TelemetryPoint
    let beforeDecision: TelemetryDecision
    let afterDecision: TelemetryDecision
    let mouseTrace: TelemetryMouseTrace
    let beforeText: [OCRTextItem]
    let afterText: [OCRTextItem]
}

private final class ClickTelemetryRecorder {
    private let rootURL: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let prettyEncoder = JSONEncoder()
    private let jsonlEncoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        rootURL = supportDirectory.appendingPathComponent("VisionClicker/Telemetry", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("samples.jsonl")
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func record(
        settings: VisionAutomationSettings,
        regionQuartz: CGRect,
        capturePixelSize: CGSize,
        beforePNGData: Data,
        afterPNGData: Data,
        beforeAnalysis: VisionTargetAnalysis,
        afterAnalysis: VisionTargetAnalysis,
        localPoint: CGPoint,
        clickQuartz: CGPoint,
        clickAppKit: CGPoint,
        trace: MouseActionTrace
    ) throws -> ClickTelemetrySample {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let id = "\(timestamp.replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString)"
        let sampleDirectory = rootURL.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: sampleDirectory, withIntermediateDirectories: true)

        let beforeImageURL = sampleDirectory.appendingPathComponent("before.png")
        let afterImageURL = sampleDirectory.appendingPathComponent("after.png")
        try beforePNGData.write(to: beforeImageURL, options: .atomic)
        try afterPNGData.write(to: afterImageURL, options: .atomic)

        let classification = classify(
            beforeAnalysis: beforeAnalysis,
            afterAnalysis: afterAnalysis
        )

        let sample = ClickTelemetrySample(
            schemaVersion: 1,
            id: id,
            timestamp: timestamp,
            classification: classification.value,
            classificationReason: classification.reason,
            targetLabels: settings.targetLabel,
            confidenceThreshold: settings.confidenceThreshold,
            beforeImage: beforeImageURL.path,
            afterImage: afterImageURL.path,
            capturePixelSize: TelemetrySize(capturePixelSize),
            regionQuartz: TelemetryRect(regionQuartz),
            regionAppKit: TelemetryRect(DisplayCoordinateSpace.quartzToAppKit(rect: regionQuartz).standardized),
            clickLocal: TelemetryPoint(localPoint),
            clickQuartz: TelemetryPoint(clickQuartz),
            clickAppKit: TelemetryPoint(clickAppKit),
            beforeDecision: TelemetryDecision(beforeAnalysis.decision),
            afterDecision: TelemetryDecision(afterAnalysis.decision),
            mouseTrace: TelemetryMouseTrace(trace),
            beforeText: beforeAnalysis.textSnapshot.items,
            afterText: afterAnalysis.textSnapshot.items
        )

        let metadataURL = sampleDirectory.appendingPathComponent("metadata.json")
        try prettyEncoder.encode(sample).write(to: metadataURL, options: .atomic)
        try appendToIndex(sample)
        return sample
    }

    private func classify(
        beforeAnalysis: VisionTargetAnalysis,
        afterAnalysis: VisionTargetAnalysis
    ) -> (value: String, reason: String) {
        let beforeSignature = beforeAnalysis.textSnapshot.normalizedSignature
        let afterSignature = afterAnalysis.textSnapshot.normalizedSignature
        let sameText = !beforeSignature.isEmpty && beforeSignature == afterSignature
        let sameTargetStillVisible = afterAnalysis.decision.isFound
            && abs(beforeAnalysis.decision.x - afterAnalysis.decision.x) <= 0.08
            && abs(beforeAnalysis.decision.y - afterAnalysis.decision.y) <= 0.08

        if sameText {
            return ("incorrect", "after OCR text matched before OCR text")
        }

        if sameTargetStillVisible {
            return ("incorrect", "target still visible near clicked location")
        }

        return ("correct", "after OCR text changed and target was not visible near clicked location")
    }

    private func appendToIndex(_ sample: ClickTelemetrySample) throws {
        let data = try jsonlEncoder.encode(sample) + Data("\n".utf8)
        if fileManager.fileExists(atPath: indexURL.path) {
            let handle = try FileHandle(forWritingTo: indexURL)
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: indexURL, options: .atomic)
        }
    }
}

final class MouseClickService {
    func click(atQuartzPoint point: CGPoint, restorePointer: Bool) throws -> MouseActionTrace {
        guard MousePermission.hasAccess else {
            throw MouseClickError.noAccessibility
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let source else {
            throw MouseClickError.eventSourceMissing
        }

        let originalPoint = CGEvent(source: nil)?.location
        warpCursor(to: point)
        let preClickPoint = CGEvent(source: nil)?.location
        try postClick(atQuartzPoint: point, source: source)
        let postActionPoint = CGEvent(source: nil)?.location

        guard restorePointer, let originalPoint else {
            return MouseActionTrace(
                originalPoint: originalPoint,
                targetPoint: point,
                preClickPoint: preClickPoint,
                postActionPoint: postActionPoint,
                restoredPoint: nil
            )
        }

        usleep(35_000)
        warpCursor(to: originalPoint)
        let restoredPoint = CGEvent(source: nil)?.location
        return MouseActionTrace(
            originalPoint: originalPoint,
            targetPoint: point,
            preClickPoint: preClickPoint,
            postActionPoint: postActionPoint,
            restoredPoint: restoredPoint
        )
    }

    func activateAndPressReturn(atQuartzPoint point: CGPoint, restorePointer: Bool) throws -> MouseActionTrace {
        guard MousePermission.hasAccess else {
            throw MouseClickError.noAccessibility
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let source else {
            throw MouseClickError.eventSourceMissing
        }

        let originalPoint = CGEvent(source: nil)?.location
        warpCursor(to: point)
        let preClickPoint = CGEvent(source: nil)?.location
        try postClick(atQuartzPoint: point, source: source)
        usleep(90_000)
        try postReturnKey(source: source)
        let postActionPoint = CGEvent(source: nil)?.location

        guard restorePointer, let originalPoint else {
            return MouseActionTrace(
                originalPoint: originalPoint,
                targetPoint: point,
                preClickPoint: preClickPoint,
                postActionPoint: postActionPoint,
                restoredPoint: nil
            )
        }

        usleep(35_000)
        warpCursor(to: originalPoint)
        let restoredPoint = CGEvent(source: nil)?.location
        return MouseActionTrace(
            originalPoint: originalPoint,
            targetPoint: point,
            preClickPoint: preClickPoint,
            postActionPoint: postActionPoint,
            restoredPoint: restoredPoint
        )
    }

    private func warpCursor(to point: CGPoint) {
        _ = CGWarpMouseCursorPosition(point)
        usleep(70_000)
    }

    private func postClick(atQuartzPoint point: CGPoint, source: CGEventSource) throws {
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
            throw MouseClickError.eventCreationFailed
        }

        mouseDown.post(tap: .cghidEventTap)
        usleep(45_000)
        mouseUp.post(tap: .cghidEventTap)
    }

    private func postReturnKey(source: CGEventSource) throws {
        let returnKeyCode: CGKeyCode = 36
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)
        else {
            throw MouseClickError.eventCreationFailed
        }

        keyDown.post(tap: .cghidEventTap)
        usleep(35_000)
        keyUp.post(tap: .cghidEventTap)
    }
}

final class VisionAutomationEngine {
    var onEvent: ((String) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    private let captureService = ScreenCaptureService()
    private let modelClient = VisionModelClient()
    private let clickService = MouseClickService()
    private let telemetryRecorder = ClickTelemetryRecorder()

    private var settings = VisionAutomationSettings()
    private var timer: Timer?
    private var inFlight = false

    func apply(settings: VisionAutomationSettings) {
        self.settings = settings
        rebuildTimer()
    }

    func triggerManualRun() {
        queueRun(trigger: "manual")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rebuildTimer() {
        timer?.invalidate()
        timer = nil

        guard settings.mode == .live else {
            onRunningChanged?(false)
            return
        }

        let interval = max(0.75, settings.pollingInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.queueRun(trigger: "timer")
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        queueRun(trigger: "start")
    }

    private func queueRun(trigger: String) {
        guard settings.mode == .live || trigger == "manual" else {
            if trigger == "manual" {
                emit("Run Once ignored because Vision Clicker is paused.")
            }
            return
        }

        guard !inFlight else {
            if trigger == "manual" {
                emit("Run Once skipped because a scan is already in progress.")
            }
            return
        }
        inFlight = true
        onRunningChanged?(true)

        let snapshot = settings
        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            defer {
                Task { @MainActor [weak self] in
                    self?.inFlight = false
                    self?.onRunningChanged?(false)
                }
            }

            do {
                try await self.runCycle(settings: snapshot, trigger: trigger)
            } catch {
                self.emit("Cycle failed: \(error.localizedDescription)")
            }
        }
    }

    private func runCycle(settings: VisionAutomationSettings, trigger: String) async throws {
        guard let storedRegion = settings.captureRegionQuartz else {
            emit("No capture region selected yet.")
            return
        }

        let region = DisplayCoordinateSpace.normalizedQuartz(rect: storedRegion)
        if !DisplayCoordinateSpace.isQuartzRectOnAnyDisplay(storedRegion) {
            emit("Migrated selected region to current display coordinates.")
        }

        let capture = try captureService.capturePNG(inQuartzRect: region)
        emit("Captured \(Int(capture.pixelSize.width))x\(Int(capture.pixelSize.height)) [\(trigger), Apple OCR].")

        let beforeAnalysis = try await modelClient.analyzeTarget(
            pngData: capture.pngData,
            targetLabel: settings.targetLabel
        )
        let decision = beforeAnalysis.decision

        guard decision.isFound else {
            emit("Target \"\(settings.targetLabel)\" not found. \(decision.note)")
            return
        }

        guard decision.confidence >= settings.confidenceThreshold else {
            emit("Target confidence too low (\(String(format: "%.2f", decision.confidence))). \(decision.note)")
            return
        }

        let resolved = resolveCoordinates(
            decision: decision,
            capturePixelSize: capture.pixelSize,
            region: region
        )
        emit(
            "Decision for \"\(settings.targetLabel)\": raw=(\(format(decision.x)),\(format(decision.y))) \(resolved.source), confidence \(format(decision.confidence)).\(decision.note.isEmpty ? "" : " \(decision.note)")"
        )

        let localPoint = CGPoint(
            x: resolved.normalizedX * region.width,
            y: resolved.normalizedY * region.height
        )
        let clickPoint = CGPoint(
            x: region.minX + localPoint.x,
            y: region.minY + localPoint.y
        )

        let trace = try clickService.click(atQuartzPoint: clickPoint, restorePointer: true)
        let appKitPoint = DisplayCoordinateSpace.quartzToAppKit(point: clickPoint)
        emit("Clicked \"\(settings.targetLabel)\" local \(format(localPoint)) -> screen \(format(appKitPoint)) app, \(format(clickPoint)) quartz.")
        emit("Mouse trace: \(format(trace)).")

        if settings.telemetryEnabled {
            await recordTelemetry(
                settings: settings,
                region: region,
                capture: capture,
                beforeAnalysis: beforeAnalysis,
                localPoint: localPoint,
                clickPoint: clickPoint,
                appKitPoint: appKitPoint,
                trace: trace
            )
        }
    }

    private func recordTelemetry(
        settings: VisionAutomationSettings,
        region: CGRect,
        capture: CapturedRegionImage,
        beforeAnalysis: VisionTargetAnalysis,
        localPoint: CGPoint,
        clickPoint: CGPoint,
        appKitPoint: CGPoint,
        trace: MouseActionTrace
    ) async {
        do {
            try await Task.sleep(nanoseconds: 700_000_000)
            let afterCapture = try captureService.capturePNG(inQuartzRect: region)
            let afterAnalysis = try await modelClient.analyzeTarget(
                pngData: afterCapture.pngData,
                targetLabel: settings.targetLabel
            )
            let sample = try telemetryRecorder.record(
                settings: settings,
                regionQuartz: region,
                capturePixelSize: capture.pixelSize,
                beforePNGData: capture.pngData,
                afterPNGData: afterCapture.pngData,
                beforeAnalysis: beforeAnalysis,
                afterAnalysis: afterAnalysis,
                localPoint: localPoint,
                clickQuartz: clickPoint,
                clickAppKit: appKitPoint,
                trace: trace
            )
            emit("Telemetry saved: \(sample.classification) (\(sample.classificationReason)) id \(sample.id).")
        } catch {
            emit("Telemetry failed: \(error.localizedDescription)")
        }
    }

    private func emit(_ message: String) {
        Task { @MainActor [weak self] in
            self?.onEvent?(message)
        }
    }

    private func resolveCoordinates(
        decision: VisionTargetDecision,
        capturePixelSize: CGSize,
        region: CGRect
    ) -> ResolvedTargetCoordinates {
        if (0 ... 1).contains(decision.x), (0 ... 1).contains(decision.y) {
            return ResolvedTargetCoordinates(
                normalizedX: CGFloat(decision.x),
                normalizedY: CGFloat(decision.y),
                source: "normalized"
            )
        }

        if
            capturePixelSize.width > 0,
            capturePixelSize.height > 0,
            (0 ... Double(capturePixelSize.width)).contains(decision.x),
            (0 ... Double(capturePixelSize.height)).contains(decision.y)
        {
            return ResolvedTargetCoordinates(
                normalizedX: CGFloat(decision.x) / capturePixelSize.width,
                normalizedY: CGFloat(decision.y) / capturePixelSize.height,
                source: "image-pixel"
            )
        }

        if
            region.width > 0,
            region.height > 0,
            (0 ... Double(region.width)).contains(decision.x),
            (0 ... Double(region.height)).contains(decision.y)
        {
            return ResolvedTargetCoordinates(
                normalizedX: CGFloat(decision.x) / region.width,
                normalizedY: CGFloat(decision.y) / region.height,
                source: "region-point"
            )
        }

        return ResolvedTargetCoordinates(
            normalizedX: CGFloat(min(max(decision.x, 0), 1)),
            normalizedY: CGFloat(min(max(decision.y, 0), 1)),
            source: "clamped"
        )
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func format(_ point: CGPoint) -> String {
        "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
    }

    private func format(_ trace: MouseActionTrace) -> String {
        let original = trace.originalPoint.map(format) ?? "unknown"
        let preClick = trace.preClickPoint.map(format) ?? "unknown"
        let postAction = trace.postActionPoint.map(format) ?? "unknown"
        let restored = trace.restoredPoint.map(format) ?? "not restored"
        return "\(original) -> \(preClick) -> \(postAction) -> \(restored)"
    }
}

final class ScreenRegionSelector {
    private var overlays: [RegionSelectionOverlayWindow] = []
    private var monitor: Any?
    private var completion: ((CGRect?) -> Void)?
    private var isFinishing = false

    func beginSelection(completion: @escaping (CGRect?) -> Void) {
        finish(with: nil, shouldCallCompletion: false)
        self.completion = completion
        isFinishing = false

        let windows = NSScreen.screens.map { screen -> RegionSelectionOverlayWindow in
            let window = RegionSelectionOverlayWindow(screen: screen)
            window.onSelectionFinished = { [weak self] rect in
                self?.finish(with: rect, shouldCallCompletion: true)
            }
            return window
        }
        overlays = windows
        windows.forEach { $0.orderFrontRegardless() }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }

            self?.finish(with: nil, shouldCallCompletion: true)
            return nil
        }
    }

    private func finish(with result: CGRect?, shouldCallCompletion: Bool) {
        guard !isFinishing else {
            return
        }
        isFinishing = true

        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        let callback = completion
        completion = nil

        if shouldCallCompletion {
            callback?(result)
        }
    }
}

final class ScreenRegionHighlighter {
    private var windows: [RegionHighlightWindow] = []

    func show(appKitRect: CGRect, duration: TimeInterval = 1.8) {
        hide()

        let highlightWindows = NSScreen.screens.compactMap { screen -> RegionHighlightWindow? in
            let intersection = screen.frame.intersection(appKitRect)
            guard !intersection.isNull, intersection.width > 1, intersection.height > 1 else {
                return nil
            }

            return RegionHighlightWindow(screen: screen, globalRect: intersection)
        }

        windows = highlightWindows
        highlightWindows.forEach { $0.orderFrontRegardless() }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.hide()
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private final class RegionHighlightWindow: NSWindow {
    init(screen: NSScreen, globalRect: CGRect) {
        let view = RegionHighlightView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.setFrame(screen.frame, display: false)
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = true
        self.contentView = view
        self.isReleasedWhenClosed = false

        let localRect = CGRect(
            x: globalRect.minX - screen.frame.minX,
            y: globalRect.minY - screen.frame.minY,
            width: globalRect.width,
            height: globalRect.height
        )
        view.highlightRect = localRect
    }
}

private final class RegionHighlightView: NSView {
    var highlightRect: CGRect = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        bounds.fill()

        guard highlightRect.width > 1, highlightRect.height > 1 else {
            return
        }

        NSColor.systemYellow.withAlphaComponent(0.20).setFill()
        NSBezierPath(rect: highlightRect).fill()

        NSColor.systemYellow.setStroke()
        let border = NSBezierPath(rect: highlightRect.insetBy(dx: 1, dy: 1))
        border.lineWidth = 4
        border.stroke()
    }
}

private final class RegionSelectionOverlayWindow: NSWindow {
    var onSelectionFinished: ((CGRect?) -> Void)?

    init(screen: NSScreen) {
        let frame = screen.frame
        let view = RegionSelectionOverlayView(frame: CGRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.setFrame(frame, display: false)
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.contentView = view
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false

        view.onSelectionFinished = { [weak self] localRect in
            guard let self else {
                return
            }

            guard let localRect else {
                self.onSelectionFinished?(nil)
                return
            }

            let globalRect = self.convertToScreen(localRect)
            self.onSelectionFinished?(globalRect.standardized)
        }
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class RegionSelectionOverlayView: NSView {
    var onSelectionFinished: ((CGRect?) -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true

        guard let rect = selectionRect, rect.width > 5, rect.height > 5 else {
            onSelectionFinished?(nil)
            return
        }

        onSelectionFinished?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let overlayPath = NSBezierPath(rect: bounds)
        if let rect = selectionRect {
            overlayPath.appendRect(rect)
            overlayPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.28).setFill()
        overlayPath.fill()

        if let rect = selectionRect {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()
        }
    }

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else {
            return nil
        }

        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
