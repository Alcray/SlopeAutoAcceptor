import AgentAutoAcceptCore
import Foundation

func runSettingsStoreTests(_ suite: TestSuite) {
    suite.run("settings default to monitor mode and bundled profiles") {
        let defaults = isolatedDefaults()
        defer { removeDefaults(defaults) }
        let settings = SettingsStore(defaults: defaults)

        suite.expect(settings.mode == .dryRun, "fresh settings should default to Monitor")
        suite.expect(settings.mode.displayName == "Monitor", "dryRun display name should be Monitor")
        suite.expect(settings.profiles.contains { $0.bundleIdentifier == AppProfile.codexDefault.bundleIdentifier }, "bundled Codex profile should exist")
        suite.expect(settings.profiles.contains { $0.bundleIdentifier == AppProfile.cursorDefault.bundleIdentifier }, "bundled Cursor profile should exist")
    }

    suite.run("settings persist mode and merge bundled profiles") {
        let defaults = isolatedDefaults()
        defer { removeDefaults(defaults) }
        let settings = SettingsStore(defaults: defaults)

        settings.mode = .live
        suite.expect(SettingsStore(defaults: defaults).mode == .live, "mode should persist")

        let custom = AppProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            displayName: "Claude Code",
            bundleIdentifier: "dev.example.claude",
            appNameHints: ["Claude Code"],
            rules: [.codexApprovalV1]
        )
        settings.profiles = [custom]

        let merged = settings.profiles
        suite.expect(merged.contains(custom), "stored custom profile should persist")
        suite.expect(merged.contains { $0.bundleIdentifier == AppProfile.codexDefault.bundleIdentifier }, "Codex bundled profile should be merged back")
        suite.expect(merged.contains { $0.bundleIdentifier == AppProfile.cursorDefault.bundleIdentifier }, "Cursor bundled profile should be merged back")
    }

    suite.run("settings can disable add and reset profiles") {
        let defaults = isolatedDefaults()
        defer { removeDefaults(defaults) }
        let settings = SettingsStore(defaults: defaults)

        let cursorID = settings.profiles.first { $0.bundleIdentifier == AppProfile.cursorDefault.bundleIdentifier }?.id
        guard let cursorID else {
            suite.expect(false, "Cursor profile should exist")
            return
        }

        settings.setProfileEnabled(cursorID, isEnabled: false)
        suite.expect(settings.profiles.first { $0.id == cursorID }?.isEnabled == false, "profile enabled flag should persist")

        settings.addProfile(displayName: "Extra Agent", bundleIdentifier: "dev.example.extra")
        suite.expect(settings.profiles.contains { $0.bundleIdentifier == "dev.example.extra" }, "added profile should persist")

        settings.resetProfiles()
        suite.expect(!settings.profiles.contains { $0.bundleIdentifier == "dev.example.extra" }, "reset should remove custom profiles")
        suite.expect(settings.profiles.contains { $0.bundleIdentifier == AppProfile.cursorDefault.bundleIdentifier }, "reset should restore bundled profiles")
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "AgentAutoAcceptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "__suiteName")
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__suiteName")
    return defaults
}

private func removeDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__suiteName") else {
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
}
