import Foundation

public enum TextNormalizer {
    private static let keyHintTokens: Set<String> = [
        "enter",
        "return",
        "↩",
        "↵",
        "⏎"
    ]

    public static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func normalizedButtonLabel(_ text: String) -> String {
        let normalized = normalizedText(text)
            .replacingOccurrences(of: "↩", with: " ")
            .replacingOccurrences(of: "↵", with: " ")
            .replacingOccurrences(of: "⏎", with: " ")

        let tokens = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !keyHintTokens.contains($0) }

        return tokens.joined(separator: " ")
    }

    public static func isRunButtonLabel(_ text: String) -> Bool {
        normalizedButtonLabel(text) == "run"
    }

    public static func commandPreview(from fragments: [String], limit: Int = 240) -> String {
        let combined = normalizedPreviewText(fragments.joined(separator: " "))

        guard combined.count > limit else {
            return combined
        }

        let index = combined.index(combined.startIndex, offsetBy: limit)
        return String(combined[..<index]) + "..."
    }

    public static func promptDedupeSignature(from fragments: [String], limit: Int = 360) -> String {
        var signature = normalizedText(fragments.joined(separator: " "))
            .replacingOccurrences(of: "↩", with: " ")
            .replacingOccurrences(of: "↵", with: " ")
            .replacingOccurrences(of: "⏎", with: " ")

        for pattern in [
            "\\bpressed \\d+ times?\\b",
            "\\bauto[- ]run in sandbox\\b",
            "\\bskip\\b"
        ] {
            signature = signature.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        signature = normalizedText(signature)

        guard signature.count > limit else {
            return signature
        }

        let index = signature.index(signature.startIndex, offsetBy: limit)
        return String(signature[..<index])
    }

    public static func stableFingerprint(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325

        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        return String(format: "%016llx", hash)
    }

    public static func normalizedPreviewText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
