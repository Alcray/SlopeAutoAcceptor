import Foundation

struct AppVersion {
    static let current = AppVersion(bundle: .main)

    let version: String
    let build: String
    let commit: String
    let branch: String

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2-dev"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        commit = bundle.object(forInfoDictionaryKey: "VisionClickerBuildCommit") as? String ?? "dev"
        branch = bundle.object(forInfoDictionaryKey: "VisionClickerBuildBranch") as? String ?? "dev"
    }

    var displayText: String {
        if commit == "unknown" || commit == "dev" {
            return "v\(version) build \(build)"
        }

        return "v\(version) (\(commit))"
    }

    var detailedText: String {
        var parts = ["v\(version)", "build \(build)"]

        if commit != "unknown", commit != "dev" {
            parts.append("commit \(commit)")
        }

        if branch != "unknown", branch != "dev" {
            parts.append("branch \(branch)")
        }

        return parts.joined(separator: ", ")
    }
}
