import Foundation

public struct LocalizationMissingEntry: Identifiable, Sendable, Equatable, Codable {
    public let id: String
    public let fileName: String
    public let key: String
    public let missingLanguages: [String]

    public init(fileName: String, key: String, missingLanguages: [String]) {
        self.id = "\(fileName)::\(key)"
        self.fileName = fileName
        self.key = key
        self.missingLanguages = missingLanguages
    }
}

public struct DerivedDataSummary: Sendable, Equatable {
    public let path: String
    public let totalBytes: Int64
    public let projectCount: Int

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public init(path: String, totalBytes: Int64, projectCount: Int) {
        self.path = path
        self.totalBytes = totalBytes
        self.projectCount = projectCount
    }
}

/// Provides native macOS utilities for UIKit/SwiftUI FE devs: Color Tokens, .xcstrings L10n, & DerivedData.
public struct XcodeUtilitiesService: Sendable {
    public init() {}

    public func generateColorTokenCode(name: String, hex: String) -> String {
        let symbolName = Self.sanitizeIdentifier(name)

        var cleanedHex = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        if cleanedHex.count == 3 {
            cleanedHex = cleanedHex.map { "\($0)\($0)" }.joined()
        }

        let isValidHex = cleanedHex.count == 6 && cleanedHex.allSatisfy { $0.isHexDigit }
        guard isValidHex else {
            return "// Invalid hex color '\(hex)'. Expected 3 or 6 hex digits (e.g. #38BDF8 or #FFF)."
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&rgbValue)

        let r = Double((rgbValue >> 16) & 0xFF) / 255.0
        let g = Double((rgbValue >> 8) & 0xFF) / 255.0
        let b = Double(rgbValue & 0xFF) / 255.0

        let rf = String(format: "%.3f", r)
        let gf = String(format: "%.3f", g)
        let bf = String(format: "%.3f", b)

        return """
        import UIKit
        import SwiftUI

        // Generated from Hex #\(cleanedHex)
        extension UIColor {
            static let \(symbolName) = UIColor(red: \(rf), green: \(gf), blue: \(bf), alpha: 1.0)
        }

        extension Color {
            static let \(symbolName) = Color(red: \(rf), green: \(gf), blue: \(bf))
        }
        """
    }

    private static func sanitizeIdentifier(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        var identifier = String(String.UnicodeScalarView(scalars))
        if identifier.isEmpty {
            return "brandAccent"
        }
        if let first = identifier.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            identifier = "_\(identifier)"
        }
        return identifier
    }

    public func scanMissingLocalizations(in xcstringsData: Data, fileName: String = "Localizable.xcstrings") -> [LocalizationMissingEntry] {
        guard
            let json = try? JSONSerialization.jsonObject(with: xcstringsData) as? [String: Any],
            let strings = json["strings"] as? [String: [String: Any]]
        else { return [] }

        var allLanguages: Set<String> = []
        for (_, entry) in strings {
            if let locs = entry["localizations"] as? [String: Any] {
                allLanguages.formUnion(locs.keys)
            }
        }
        guard !allLanguages.isEmpty else { return [] }

        var missing: [LocalizationMissingEntry] = []
        for key in strings.keys.sorted() {
            let locs = (strings[key]?["localizations"] as? [String: [String: Any]]) ?? [:]
            let missingLangs = allLanguages.filter { lang in
                guard let unit = locs[lang]?["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String
                else { return true }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.sorted()

            if !missingLangs.isEmpty {
                missing.append(LocalizationMissingEntry(fileName: fileName, key: key, missingLanguages: missingLangs))
            }
        }
        return missing
    }

    public func scanMissingLocalizationsInDirectory(at url: URL) -> [LocalizationMissingEntry] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [LocalizationMissingEntry] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "xcstrings",
                  let data = try? Data(contentsOf: fileURL)
            else { continue }
            results.append(contentsOf: scanMissingLocalizations(in: data, fileName: fileURL.lastPathComponent))
        }
        return results
    }

    public func scanDerivedDataSize() -> DerivedDataSummary {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DerivedDataSummary(path: dir.path, totalBytes: 0, projectCount: 0)
        }

        var total: Int64 = 0
        for item in contents {
            if let enumerator = FileManager.default.enumerator(at: item, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    total += Int64(size)
                }
            }
        }
        return DerivedDataSummary(path: dir.path, totalBytes: total, projectCount: contents.count)
    }

    public func cleanDerivedData() throws -> Int {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var removed = 0
        for item in contents {
            try FileManager.default.removeItem(at: item)
            removed += 1
        }
        return removed
    }
}
