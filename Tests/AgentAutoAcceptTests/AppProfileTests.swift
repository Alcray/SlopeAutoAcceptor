import AgentAutoAcceptCore

func runAppProfileTests(_ suite: TestSuite) {
    suite.run("bundle id profiles do not match helper apps by name") {
        let profile = AppProfile.cursorDefault
        let cursor = RunningAppInfo(
            name: "Cursor",
            bundleIdentifier: " com.todesktop.230313mzl4w4u92 ",
            processIdentifier: 76
        )
        let helper = RunningAppInfo(
            name: "CursorUIViewService",
            bundleIdentifier: "com.apple.TextInputUI.xpc.CursorUIViewService",
            processIdentifier: 77
        )

        suite.expect(profile.matches(cursor), "Cursor profile should match exact bundle id with whitespace")
        suite.expect(!profile.matches(helper), "Cursor profile should not scan helper apps with Cursor in the name")
    }

    suite.run("name hints are used only when no bundle id is configured") {
        let profile = AppProfile(
            displayName: "Custom Agent",
            bundleIdentifier: "",
            appNameHints: ["custom agent"],
            rules: [.codexApprovalV1]
        )
        let app = RunningAppInfo(
            name: "Custom Agent Nightly",
            bundleIdentifier: "dev.example.agent",
            processIdentifier: 88
        )

        suite.expect(profile.matches(app), "custom name-only profiles should still match by app name hint")
    }
}
