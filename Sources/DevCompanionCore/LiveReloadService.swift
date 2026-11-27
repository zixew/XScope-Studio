import Foundation

/// Watches `.swift` files inside an Xcode project directory (skipping build artifacts) and emits changed file URLs.
public actor ProjectFileWatcher {
    private var snapshot: [String: Date] = [:]
    private let skipDirs: Set<String> = [".build", "Pods", "DerivedData", ".git"]

    public init() {}

    public func detectChanges(in rootURL: URL) -> [URL] {
        var current: [String: Date] = [:]
        var changed: [URL] = []

        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if skipDirs.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "swift" else { continue }
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                current[url.path] = mtime
                if let prev = snapshot[url.path] {
                    if mtime > prev {
                        changed.append(url)
                    }
                } else if !snapshot.isEmpty {
                    changed.append(url)
                }
            }
        }

        snapshot = current
        return changed
    }

    public func reset() {
        snapshot = [:]
    }
}

/// Runs incremental `xcodebuild` + `xcrun simctl install` + `launch` for Flutter-like save-to-refresh on Simulator.
public struct LiveReloadService: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner(defaultTimeoutSeconds: 300)) {
        self.runner = runner
    }

    public func incrementalBuildAndLaunch(
        projectPath: String,
        scheme: String,
        simulatorUDID: String,
        destination: String
    ) async throws -> CommandOutput {
        let flag = projectPath.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        let buildOut = try await runner.run(
            "/usr/bin/xcodebuild",
            arguments: [flag, projectPath, "-scheme", scheme, "-destination", destination, "-configuration", "Debug", "build"],
            workingDirectory: nil
        )
        guard buildOut.isSuccess else { return buildOut }

        let settingsOut = try await runner.run(
            "/usr/bin/xcodebuild",
            arguments: [flag, projectPath, "-scheme", scheme, "-destination", destination, "-configuration", "Debug", "-showBuildSettings"],
            workingDirectory: nil
        )
        guard settingsOut.isSuccess,
              let appPath = Self.extractBuildSetting("TARGET_BUILD_DIR", from: settingsOut.stdout)
                .flatMap({ dir in
                    Self.extractBuildSetting("FULL_PRODUCT_NAME", from: settingsOut.stdout).map { "\(dir)/\($0)" }
                }),
              let bundleID = Self.extractBuildSetting("PRODUCT_BUNDLE_IDENTIFIER", from: settingsOut.stdout)
        else {
            return buildOut
        }

        let installOut = try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "install", simulatorUDID, appPath],
            workingDirectory: nil
        )
        guard installOut.isSuccess else { return installOut }

        return try await runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "launch", simulatorUDID, bundleID],
            workingDirectory: nil
        )
    }

    static func extractBuildSetting(_ key: String, from stdout: String) -> String? {
        let prefix = "\(key) ="
        for line in stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
