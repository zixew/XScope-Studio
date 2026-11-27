import Foundation

public struct SwiftDependencyNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let typeName: String
    public let filePath: String
    public let relativePath: String
    public let methods: [String]
    public let protocols: [String]
    public let hopDepth: Int

    public init(
        typeName: String,
        filePath: String,
        relativePath: String,
        methods: [String],
        protocols: [String],
        hopDepth: Int
    ) {
        self.id = "\(typeName):\(filePath)"
        self.typeName = typeName
        self.filePath = filePath
        self.relativePath = relativePath
        self.methods = methods
        self.protocols = protocols
        self.hopDepth = hopDepth
    }
}

public struct UnitTestDependencyResolver: Sendable {
    private let studio: UnitTestStudio

    public init(studio: UnitTestStudio = UnitTestStudio()) {
        self.studio = studio
    }

    /// Indexes Swift types in `projectURL` and resolves 1-2 hop cross-file dependencies referenced by `source`.
    public func resolveDependencies(
        for source: String,
        excludingFilePath: String? = nil,
        in projectURL: URL,
        maxHops: Int = 2,
        maxNodes: Int = 24
    ) -> [SwiftDependencyNode] {
        let swiftFiles = collectSwiftFiles(in: projectURL)
        guard !swiftFiles.isEmpty else { return [] }

        var typeIndex: [String: (url: URL, rel: String, source: String, symbols: [ParsedSwiftSymbol])] = [:]
        for fileURL in swiftFiles {
            if let excluded = excludingFilePath, fileURL.path == excluded { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let symbols = studio.parseSymbols(from: content)
            let rel = fileURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
            for sym in symbols where !sym.typeName.isEmpty {
                typeIndex[sym.typeName] = (fileURL, rel, content, symbols)
            }
        }

        var visitedTypes: Set<String> = []
        var resolved: [SwiftDependencyNode] = []
        var frontierSources: [(text: String, depth: Int)] = [(source, 1)]

        while let current = frontierSources.first, current.depth <= maxHops, resolved.count < maxNodes {
            frontierSources.removeFirst()
            let tokens = extractIdentifierTokens(from: current.text)

            for (typeName, entry) in typeIndex where !visitedTypes.contains(typeName) && tokens.contains(typeName) {
                visitedTypes.insert(typeName)
                let matchingSymbols = entry.symbols.filter { $0.typeName == typeName }
                let methods = matchingSymbols.flatMap { $0.methods.map(\.name) }
                let protocols: [String] = []

                let node = SwiftDependencyNode(
                    typeName: typeName,
                    filePath: entry.url.path,
                    relativePath: entry.rel,
                    methods: Array(methods.prefix(12)),
                    protocols: protocols,
                    hopDepth: current.depth
                )
                resolved.append(node)
                if current.depth < maxHops {
                    frontierSources.append((entry.source, current.depth + 1))
                }
                if resolved.count >= maxNodes { break }
            }
        }

        return resolved.sorted { lhs, rhs in
            if lhs.hopDepth != rhs.hopDepth { return lhs.hopDepth < rhs.hopDepth }
            return lhs.typeName < rhs.typeName
        }
    }

    public static func formatDependencyContext(_ nodes: [SwiftDependencyNode]) -> String {
        guard !nodes.isEmpty else { return "" }
        return nodes.map { node in
            let funcs = node.methods.isEmpty ? "none" : node.methods.joined(separator: ", ")
            let protos = node.protocols.isEmpty ? "" : " : \(node.protocols.joined(separator: ", "))"
            return "- [Hop \(node.hopDepth)] \(node.typeName)\(protos) (\(node.relativePath)) -> methods: \(funcs)"
        }.joined(separator: "\n")
    }

    /// Walks up parent directories from `url` to automatically detect the enclosing Xcode/SwiftPM/Git project root.
    public static func detectProjectRoot(startingAt url: URL) -> URL? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        var current = isDir.boolValue ? url.standardizedFileURL : url.standardizedFileURL.deletingLastPathComponent()
        var fallbackCandidate: URL?

        for _ in 0..<12 {
            let path = current.path
            if path == "/" || path.isEmpty || current.lastPathComponent == "Users" { break }
            if let entries = try? fm.contentsOfDirectory(at: current, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                let hasXcodeContainer = entries.contains { ["xcworkspace", "xcodeproj"].contains($0.pathExtension) }
                let hasPackageSwift = entries.contains { $0.lastPathComponent == "Package.swift" }
                if hasXcodeContainer || hasPackageSwift {
                    return current
                }
            }
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            if fallbackCandidate == nil, isDir.boolValue {
                fallbackCandidate = current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return fallbackCandidate
    }

    /// Lists both Swift files and subdirectories relative to `projectURL` for the searchable Unit Test target picker.
    public func listProjectSwiftTargets(in projectURL: URL) -> [String] {
        let fm = FileManager.default
        let standardizedRoot = projectURL.standardizedFileURL
        let rootPrefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : (standardizedRoot.path + "/")
        guard let enumerator = fm.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let skippedDirs: Set<String> = [".build", "Pods", "DerivedData", ".git", ".swiftpm", "build", "dist", "Carthage", "node_modules"]
        let skippedExts: Set<String> = ["xcodeproj", "xcworkspace", "xcassets", "lproj", "bundle", "framework", "xcframework", "app"]
        var targets: [String] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let ext = url.pathExtension
            if skippedDirs.contains(name) || skippedExts.contains(ext) || name.hasSuffix("Tests") {
                enumerator.skipDescendants()
                continue
            }
            let standardizedPath = url.standardizedFileURL.path
            guard standardizedPath.hasPrefix(rootPrefix) else { continue }
            let rel = String(standardizedPath.dropFirst(rootPrefix.count))
            guard !rel.isEmpty else { continue }

            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if vals?.isDirectory == true {
                targets.append(rel)
            } else if vals?.isRegularFile == true && ext == "swift" && !name.hasSuffix("Tests.swift") {
                targets.append(rel)
            }
            if targets.count >= 2500 { break }
        }
        return targets.sorted()
    }

    /// Loads and combines Swift source code from one file, multiple files, or a directory.
    public func collectSwiftSources(from urls: [URL], maxFiles: Int = 25) -> (displayTitle: String, combinedSource: String, primaryFilePath: String?) {
        let fm = FileManager.default
        var collectedFiles: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let dirFiles = collectSwiftFiles(in: url)
                collectedFiles.append(contentsOf: dirFiles)
            } else if url.pathExtension == "swift" {
                collectedFiles.append(url)
            }
        }

        var seen: Set<String> = []
        let uniqueFiles = collectedFiles.filter { seen.insert($0.standardizedFileURL.path).inserted }.prefix(maxFiles)
        guard !uniqueFiles.isEmpty else { return ("", "", nil) }

        var chunks: [String] = []
        for fileURL in uniqueFiles {
            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                if uniqueFiles.count > 1 {
                    chunks.append("// MARK: - \(fileURL.lastPathComponent)\n" + text)
                } else {
                    chunks.append(text)
                }
            }
        }

        let displayTitle: String
        if urls.count == 1 {
            let first = urls[0]
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: first.path, isDirectory: &isDir)
            displayTitle = isDir.boolValue ? "\(first.lastPathComponent)/ (\(uniqueFiles.count) files)" : first.lastPathComponent
        } else {
            displayTitle = "\(uniqueFiles.count) Swift files (\(urls[0].lastPathComponent) + \(uniqueFiles.count - 1))"
        }

        return (displayTitle, chunks.joined(separator: "\n\n"), uniqueFiles.first?.path)
    }

    private func collectSwiftFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let path = url.path
            if path.contains("/.build/") || path.contains("/DerivedData/") || path.contains("/Pods/") || path.contains("Tests/") {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "swift" {
                files.append(url)
                if files.count >= 400 { break }
            }
        }
        return files
    }

    private func extractIdentifierTokens(from source: String) -> Set<String> {
        let pattern = #"\b[A-Z][A-Za-z0-9_]{1,64}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: min(nsText.length, 150_000)))
        var result: Set<String> = []
        for match in matches {
            result.insert(nsText.substring(with: match.range))
        }
        return result
    }
}
