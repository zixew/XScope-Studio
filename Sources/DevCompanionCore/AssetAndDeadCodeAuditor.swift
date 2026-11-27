import Foundation

public struct UnusedAssetItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let assetCatalog: String
    public let relativePath: String

    public init(name: String, assetCatalog: String, relativePath: String) {
        self.id = relativePath
        self.name = name
        self.assetCatalog = assetCatalog
        self.relativePath = relativePath
    }
}

public struct AssetAndDeadCodeAuditor: Sendable {
    public init() {}

    /// Scans `.xcassets` for `.imageset` folders whose names never appear in `.swift`/`.storyboard`/`.xib` files.
    public func findUnusedImageAssets(in projectURL: URL) -> [UnusedAssetItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var imageSets: [UnusedAssetItem] = []
        var sourceContents: [String] = []

        for case let url as URL in enumerator {
            let path = url.path
            if path.contains("/.build/") || path.contains("/DerivedData/") || path.contains("/Pods/") {
                enumerator.skipDescendants()
                continue
            }

            if url.pathExtension == "imageset" {
                let name = url.deletingPathExtension().lastPathComponent
                let catalog = url.deletingLastPathComponent().lastPathComponent
                let rel = path.replacingOccurrences(of: projectURL.path + "/", with: "")
                imageSets.append(UnusedAssetItem(name: name, assetCatalog: catalog, relativePath: rel))
                enumerator.skipDescendants()
            } else if ["swift", "storyboard", "xib", "m"].contains(url.pathExtension) {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    sourceContents.append(text)
                }
            }
        }

        guard !imageSets.isEmpty else { return [] }
        let combined = sourceContents.joined(separator: "\n")
        return imageSets.filter { item in
            !combined.contains("\"\(item.name)\"") && !combined.contains(".\(item.name)")
        }
        .sorted { $0.name < $1.name }
    }
}
