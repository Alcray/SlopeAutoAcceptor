import AppKit
import CoreGraphics
import Foundation

struct AutoRegionPickResult {
    let quartzRect: CGRect
    let appKitRect: CGRect
    let label: String?
    let confidence: Double?
    let reason: String?
    let rawResponse: String
    let screenshotPixelSize: CGSize
    let desktopQuartzRect: CGRect
}

enum AutoRegionPickError: LocalizedError {
    case invalidOllamaURL(String)
    case invalidModelResponse(String)
    case noRegionFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidOllamaURL(url):
            return "Auto-region Ollama URL is invalid: \(url)"
        case let .invalidModelResponse(response):
            return "VLM response did not contain a usable region: \(response)"
        case let .noRegionFound(reason):
            return "VLM did not find a target region. \(reason)"
        }
    }
}

final class AutoRegionPickerService {
    private let captureService = ScreenCaptureService()
    private let modelClient = OllamaAutoRegionClient()

    func pickRegion(settings: VisionAutomationSettings) async throws -> AutoRegionPickResult {
        let baseURLText = settings.autoRegionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: baseURLText), baseURL.scheme != nil else {
            throw AutoRegionPickError.invalidOllamaURL(settings.autoRegionURL)
        }

        let model = settings.autoRegionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "moondream"
            : settings.autoRegionModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let desktopCapture = try captureService.captureDesktopPNG(maxSide: 1800)
        let modelRegion = try await modelClient.locateRegion(
            desktopCapture: desktopCapture,
            baseURL: baseURL,
            model: model,
            targetLabels: TargetLabelParser.labels(from: settings.targetLabel)
        )

        guard modelRegion.found else {
            throw AutoRegionPickError.noRegionFound(modelRegion.reason ?? modelRegion.rawResponse)
        }

        let quartzRect = convertToQuartzRect(
            modelRegion: modelRegion,
            desktopCapture: desktopCapture
        )

        guard quartzRect.width >= 8, quartzRect.height >= 8 else {
            throw AutoRegionPickError.invalidModelResponse(modelRegion.rawResponse)
        }

        let clamped = clamp(quartzRect, to: desktopCapture.quartzRect)
        return AutoRegionPickResult(
            quartzRect: clamped,
            appKitRect: DisplayCoordinateSpace.quartzToAppKit(rect: clamped).standardized,
            label: modelRegion.label,
            confidence: modelRegion.confidence,
            reason: modelRegion.reason,
            rawResponse: modelRegion.rawResponse,
            screenshotPixelSize: desktopCapture.pixelSize,
            desktopQuartzRect: desktopCapture.quartzRect
        )
    }

    private func convertToQuartzRect(
        modelRegion: OllamaAutoRegionClient.RegionResponse,
        desktopCapture: CapturedDesktopImage
    ) -> CGRect {
        let xScale = desktopCapture.quartzRect.width / max(desktopCapture.pixelSize.width, 1)
        let yScale = desktopCapture.quartzRect.height / max(desktopCapture.pixelSize.height, 1)

        let baseRect = CGRect(
            x: desktopCapture.quartzRect.minX + CGFloat(modelRegion.x) * xScale,
            y: desktopCapture.quartzRect.minY + CGFloat(modelRegion.y) * yScale,
            width: CGFloat(modelRegion.width) * xScale,
            height: CGFloat(modelRegion.height) * yScale
        ).standardized

        let horizontalPadding = max(24, baseRect.width * 0.55)
        let verticalPadding = max(14, baseRect.height * 0.85)
        return baseRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let intersection = rect.standardized.intersection(bounds.standardized)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return rect.standardized
        }
        return intersection.integral
    }
}

final class OllamaAutoRegionClient {
    struct RegionResponse {
        let found: Bool
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let label: String?
        let confidence: Double?
        let reason: String?
        let rawResponse: String
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let images: [String]
        let stream: Bool
        let format: String
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    func locateRegion(
        desktopCapture: CapturedDesktopImage,
        baseURL: URL,
        model: String,
        targetLabels: [String]
    ) async throws -> RegionResponse {
        var endpoint = baseURL
        endpoint.appendPathComponent("api")
        endpoint.appendPathComponent("generate")

        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = GenerateRequest(
            model: model,
            prompt: prompt(
                targetLabels: targetLabels,
                screenshotPixelSize: desktopCapture.pixelSize
            ),
            images: [desktopCapture.pngData.base64EncodedString()],
            stream: false,
            format: "json"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return try parseRegionResponse(decoded.response)
    }

    private func prompt(targetLabels: [String], screenshotPixelSize: CGSize) -> String {
        let labels = targetLabels.isEmpty ? "Run" : targetLabels.joined(separator: ", ")
        return """
        You are locating an approval button in a full desktop screenshot for a macOS automation tool.
        Target labels: \(labels).
        Ignore the Vision Clicker control window, Activity Log window, menu bar, and Dock.
        Prefer coding-agent UI approval buttons such as Run, Fetch, Retry, Continue, Approve, Smoke Test, or similar controls.
        Return one tight rectangle around the best target button, with a little surrounding button-row context.
        Coordinates must be pixels in the screenshot image, origin at the top-left.
        Screenshot size: \(Int(screenshotPixelSize.width))x\(Int(screenshotPixelSize.height)).
        Return only JSON shaped exactly like:
        {"found":true,"x":123,"y":456,"width":90,"height":32,"label":"Run","confidence":0.72,"reason":"short reason"}
        If no target is visible, return:
        {"found":false,"x":0,"y":0,"width":0,"height":0,"label":"","confidence":0,"reason":"short reason"}
        """
    }

    private func parseRegionResponse(_ rawResponse: String) throws -> RegionResponse {
        let jsonText = extractJSONObject(from: rawResponse)
        guard
            let data = jsonText.data(using: .utf8),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AutoRegionPickError.invalidModelResponse(rawResponse)
        }

        let found = boolValue(object["found"]) ?? true
        let reason = object["reason"] as? String
        guard found else {
            return RegionResponse(
                found: false,
                x: 0,
                y: 0,
                width: 0,
                height: 0,
                label: object["label"] as? String,
                confidence: doubleValue(object["confidence"]),
                reason: reason,
                rawResponse: rawResponse
            )
        }

        guard
            let x = doubleValue(object["x"] ?? object["left"]),
            let y = doubleValue(object["y"] ?? object["top"]),
            let width = doubleValue(object["width"] ?? object["w"]),
            let height = doubleValue(object["height"] ?? object["h"])
        else {
            throw AutoRegionPickError.invalidModelResponse(rawResponse)
        }

        return RegionResponse(
            found: true,
            x: x,
            y: y,
            width: width,
            height: height,
            label: object["label"] as? String,
            confidence: doubleValue(object["confidence"]),
            reason: reason,
            rawResponse: rawResponse
        )
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start ... end])
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }

        return nil
    }
}
