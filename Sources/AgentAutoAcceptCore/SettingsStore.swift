import Foundation

public final class SettingsStore {
    private enum Keys {
        static let mode = "mode.v1"
        static let profiles = "profiles.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var mode: AutoAcceptMode {
        get {
            guard
                let raw = defaults.string(forKey: Keys.mode),
                let mode = AutoAcceptMode(rawValue: raw)
            else {
                return .dryRun
            }

            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.mode)
        }
    }

    public var profiles: [AppProfile] {
        get {
            guard
                let data = defaults.data(forKey: Keys.profiles),
                let decoded = try? decoder.decode([AppProfile].self, from: data),
                !decoded.isEmpty
            else {
                return AppProfile.bundledDefaults
            }

            return mergeBundledProfiles(with: decoded)
        }
        set {
            guard let data = try? encoder.encode(newValue) else {
                return
            }

            defaults.set(data, forKey: Keys.profiles)
        }
    }

    public func setProfileEnabled(_ id: UUID, isEnabled: Bool) {
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == id }) else {
            return
        }

        updated[index].isEnabled = isEnabled
        profiles = updated
    }

    public func addProfile(displayName: String, bundleIdentifier: String) {
        var updated = profiles
        updated.append(
            AppProfile(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                appNameHints: [displayName],
                rules: [.codexApprovalV1]
            )
        )
        profiles = updated
    }

    public func resetProfiles() {
        defaults.removeObject(forKey: Keys.profiles)
    }

    private func mergeBundledProfiles(with stored: [AppProfile]) -> [AppProfile] {
        var merged = stored
        let existingBundleIDs = Set(
            stored.map { $0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        for profile in AppProfile.bundledDefaults {
            let bundleID = profile.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !existingBundleIDs.contains(bundleID) {
                merged.append(profile)
            }
        }

        return merged
    }
}
