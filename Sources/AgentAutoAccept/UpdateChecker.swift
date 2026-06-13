import Foundation

struct AvailableUpdate {
    let version: String
    let tagName: String
    let name: String
    let htmlURL: URL
    let downloadURL: URL?
    let releaseNotes: String

    var actionURL: URL {
        downloadURL ?? htmlURL
    }
}

enum UpdateCheckResult {
    case updateAvailable(AvailableUpdate)
    case upToDate(latestVersion: String)
    case noPublishedVersions
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingReleaseURL
    case unparsableVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case let .httpStatus(statusCode):
            return "GitHub update check failed with HTTP \(statusCode)."
        case .missingReleaseURL:
            return "The latest GitHub release did not include a release URL."
        case let .unparsableVersion(version):
            return "Could not compare version \"\(version)\"."
        }
    }
}

final class GitHubReleaseUpdateChecker {
    private let latestReleaseURL: URL
    private let tagsURL: URL
    private let repositoryURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(
        owner: String = "Alcray",
        repository: String = "SlopeAutoAcceptor",
        session: URLSession = .shared
    ) {
        latestReleaseURL = URL(
            string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest"
        )!
        tagsURL = URL(
            string: "https://api.github.com/repos/\(owner)/\(repository)/tags"
        )!
        repositoryURL = URL(string: "https://github.com/\(owner)/\(repository)")!
        self.session = session
    }

    func checkForUpdate(currentVersion: String) async throws -> UpdateCheckResult {
        let (releaseData, releaseResponse) = try await data(for: latestReleaseURL)

        if releaseResponse.statusCode == 404 {
            return try await checkTagsForUpdate(currentVersion: currentVersion)
        }

        guard (200..<300).contains(releaseResponse.statusCode) else {
            throw UpdateCheckError.httpStatus(releaseResponse.statusCode)
        }

        let release = try decoder.decode(GitHubRelease.self, from: releaseData)
        guard let htmlURL = URL(string: release.htmlURL) else {
            throw UpdateCheckError.missingReleaseURL
        }

        return try compare(
            currentVersion: currentVersion,
            latestVersion: release.tagName,
            update: AvailableUpdate(
                version: release.tagName,
                tagName: release.tagName,
                name: release.name?.isEmpty == false ? release.name! : release.tagName,
                htmlURL: htmlURL,
                downloadURL: release.primaryDownloadURL,
                releaseNotes: release.body ?? ""
            )
        )
    }

    private func checkTagsForUpdate(currentVersion: String) async throws -> UpdateCheckResult {
        let (tagData, tagResponse) = try await data(for: tagsURL)
        guard (200..<300).contains(tagResponse.statusCode) else {
            throw UpdateCheckError.httpStatus(tagResponse.statusCode)
        }

        let tags = try decoder.decode([GitHubTag].self, from: tagData)
        let versionedTags = tags.compactMap { tag -> (GitHubTag, ReleaseVersion)? in
            guard let version = ReleaseVersion(tag.name) else {
                return nil
            }

            return (tag, version)
        }

        guard let latestTag = versionedTags.max(by: { $0.1 < $1.1 }) else {
            return .noPublishedVersions
        }

        var tagPathAllowedCharacters = CharacterSet.urlPathAllowed
        tagPathAllowedCharacters.remove(charactersIn: "/")
        let escapedTag = latestTag.0.name.addingPercentEncoding(withAllowedCharacters: tagPathAllowedCharacters)
            ?? latestTag.0.name
        var tagURLComponents = URLComponents(url: repositoryURL, resolvingAgainstBaseURL: false)
        tagURLComponents?.percentEncodedPath = "\(repositoryURL.path)/tree/\(escapedTag)"
        let tagURL = tagURLComponents?.url ?? repositoryURL

        return try compare(
            currentVersion: currentVersion,
            latestVersion: latestTag.0.name,
            update: AvailableUpdate(
                version: latestTag.1.displayText,
                tagName: latestTag.0.name,
                name: "GitHub tag \(latestTag.0.name)",
                htmlURL: tagURL,
                downloadURL: nil,
                releaseNotes: ""
            )
        )
    }

    private func compare(
        currentVersion: String,
        latestVersion: String,
        update: AvailableUpdate
    ) throws -> UpdateCheckResult {
        guard let current = ReleaseVersion(currentVersion) else {
            throw UpdateCheckError.unparsableVersion(currentVersion)
        }
        guard let latest = ReleaseVersion(latestVersion) else {
            throw UpdateCheckError.unparsableVersion(latestVersion)
        }

        guard latest > current else {
            return .upToDate(latestVersion: latestVersion)
        }

        return .updateAvailable(update)
    }

    private func data(for url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("VisionClicker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        return (data, httpResponse)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case assets
    }

    var primaryDownloadURL: URL? {
        let preferredAsset = assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".zip")
        } ?? assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".dmg")
                || name.hasSuffix(".pkg")
        } ?? assets.first

        guard let rawURL = preferredAsset?.browserDownloadURL else {
            return nil
        }

        return URL(string: rawURL)
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct GitHubTag: Decodable {
    let name: String
}

private struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstDigit = trimmed.firstIndex(where: { $0.isNumber }) else {
            return nil
        }

        let versionText = trimmed[firstDigit...]
        var parsedComponents: [Int] = []
        var currentNumber = ""

        for character in versionText {
            if character.isNumber {
                currentNumber.append(character)
                continue
            }

            if character == "." {
                guard !currentNumber.isEmpty, let value = Int(currentNumber) else {
                    return nil
                }
                parsedComponents.append(value)
                currentNumber = ""
                continue
            }

            break
        }

        if !currentNumber.isEmpty, let value = Int(currentNumber) {
            parsedComponents.append(value)
        }

        guard !parsedComponents.isEmpty else {
            return nil
        }

        components = parsedComponents
    }

    var displayText: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)

        for index in 0..<componentCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}
