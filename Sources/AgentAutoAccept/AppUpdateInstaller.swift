import Darwin
import Foundation

enum AppUpdateInstallError: LocalizedError {
    case missingDownloadURL
    case unsupportedAsset(URL)
    case currentBundleIsNotApp(URL)
    case targetDirectoryNotWritable(URL)
    case downloadHTTPStatus(Int)
    case extractionFailed(Int32)
    case noAppBundleFound
    case invalidBundleIdentifier(String?)
    case installerLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDownloadURL:
            return "The GitHub release does not include a downloadable app archive."
        case let .unsupportedAsset(url):
            return "Automatic updates only support .zip app archives. This release asset is \(url.lastPathComponent)."
        case let .currentBundleIsNotApp(url):
            return "Vision Clicker is not running from an app bundle: \(url.path)"
        case let .targetDirectoryNotWritable(url):
            return "Vision Clicker does not have permission to replace apps in \(url.path)."
        case let .downloadHTTPStatus(statusCode):
            return "Update download failed with HTTP \(statusCode)."
        case let .extractionFailed(status):
            return "Could not extract the update archive. ditto exited with status \(status)."
        case .noAppBundleFound:
            return "The update archive did not contain a Vision Clicker app bundle."
        case let .invalidBundleIdentifier(bundleIdentifier):
            return "The downloaded app bundle identifier did not match Vision Clicker: \(bundleIdentifier ?? "unknown")."
        case let .installerLaunchFailed(message):
            return "Could not launch the update installer: \(message)"
        }
    }
}

final class AppUpdateInstaller {
    private let session: URLSession
    private let fileManager: FileManager

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func install(update: AvailableUpdate) async throws {
        guard let downloadURL = update.downloadURL else {
            throw AppUpdateInstallError.missingDownloadURL
        }

        guard downloadURL.pathExtension.lowercased() == "zip" else {
            throw AppUpdateInstallError.unsupportedAsset(downloadURL)
        }

        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard currentAppURL.pathExtension == "app" else {
            throw AppUpdateInstallError.currentBundleIsNotApp(currentAppURL)
        }

        let targetDirectory = currentAppURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: targetDirectory.path) else {
            throw AppUpdateInstallError.targetDirectoryNotWritable(targetDirectory)
        }

        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("VisionClickerUpdate-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = workDirectory.appendingPathComponent(downloadURL.lastPathComponent)
        let extractURL = workDirectory.appendingPathComponent("extracted", isDirectory: true)

        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractURL, withIntermediateDirectories: true)

        let (temporaryDownloadURL, response) = try await session.download(from: downloadURL)
        if
            let httpResponse = response as? HTTPURLResponse,
            !(200..<300).contains(httpResponse.statusCode)
        {
            throw AppUpdateInstallError.downloadHTTPStatus(httpResponse.statusCode)
        }

        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.moveItem(at: temporaryDownloadURL, to: archiveURL)

        let extractStatus = runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractURL.path]
        )
        guard extractStatus == 0 else {
            throw AppUpdateInstallError.extractionFailed(extractStatus)
        }

        guard let updateAppURL = findAppBundle(in: extractURL) else {
            throw AppUpdateInstallError.noAppBundleFound
        }

        try validateDownloadedApp(at: updateAppURL)
        try launchInstallScript(
            updateAppURL: updateAppURL,
            targetAppURL: currentAppURL,
            workDirectory: workDirectory
        )
    }

    private func validateDownloadedApp(at url: URL) throws {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let downloadedBundleIdentifier = Bundle(url: url)?.bundleIdentifier
        guard
            let currentBundleIdentifier,
            downloadedBundleIdentifier == currentBundleIdentifier
        else {
            throw AppUpdateInstallError.invalidBundleIdentifier(downloadedBundleIdentifier)
        }
    }

    private func findAppBundle(in directory: URL) -> URL? {
        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        var appBundles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "app" {
            appBundles.append(url)
            enumerator.skipDescendants()
        }

        return appBundles.first { $0.lastPathComponent == "Vision Clicker.app" } ?? appBundles.first
    }

    private func launchInstallScript(
        updateAppURL: URL,
        targetAppURL: URL,
        workDirectory: URL
    ) throws {
        let scriptURL = workDirectory.appendingPathComponent("install-update.sh")
        let logURL = updateLogURL()
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail

        exec >> "$VISION_CLICKER_UPDATE_LOG" 2>&1
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') Starting Vision Clicker update install."

        NEW_APP="$VISION_CLICKER_NEW_APP"
        TARGET_APP="$VISION_CLICKER_TARGET_APP"
        OLD_PID="$VISION_CLICKER_OLD_PID"
        WORK_DIR="$VISION_CLICKER_WORK_DIR"
        BACKUP_APP="$(dirname "$TARGET_APP")/.Vision Clicker.app.update-backup.$$"

        restore_backup() {
            if [[ -d "$BACKUP_APP" ]]; then
                rm -rf "$TARGET_APP"
                mv "$BACKUP_APP" "$TARGET_APP"
            fi
        }
        trap restore_backup ERR

        for _ in {1..120}; do
            if ! kill -0 "$OLD_PID" >/dev/null 2>&1; then
                break
            fi
            sleep 0.25
        done

        if kill -0 "$OLD_PID" >/dev/null 2>&1; then
            echo "Timed out waiting for old Vision Clicker process $OLD_PID to exit."
            exit 1
        fi

        rm -rf "$BACKUP_APP"
        if [[ -e "$TARGET_APP" ]]; then
            mv "$TARGET_APP" "$BACKUP_APP"
        fi

        /usr/bin/ditto "$NEW_APP" "$TARGET_APP"
        if [[ ! -d "$TARGET_APP" ]]; then
            echo "Updated app was not copied to $TARGET_APP."
            exit 1
        fi
        rm -rf "$BACKUP_APP"

        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \\
            -f "$TARGET_APP" >/dev/null 2>&1 || true
        /usr/bin/open "$TARGET_APP"
        rm -rf "$WORK_DIR"
        echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') Vision Clicker update install complete."
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "VISION_CLICKER_NEW_APP": updateAppURL.path,
                "VISION_CLICKER_TARGET_APP": targetAppURL.path,
                "VISION_CLICKER_OLD_PID": "\(getpid())",
                "VISION_CLICKER_WORK_DIR": workDirectory.path,
                "VISION_CLICKER_UPDATE_LOG": logURL.path
            ],
            uniquingKeysWith: { _, new in new }
        )

        do {
            try process.run()
        } catch {
            throw AppUpdateInstallError.installerLaunchFailed(error.localizedDescription)
        }
    }

    private func updateLogURL() -> URL {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser

        return supportDirectory
            .appendingPathComponent("VisionClicker", isDirectory: true)
            .appendingPathComponent("update-install.log")
    }

    private func runProcess(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}
