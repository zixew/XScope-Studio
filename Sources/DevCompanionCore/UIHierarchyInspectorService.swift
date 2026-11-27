import Foundation
import Vision
import ImageIO

public struct UIComponentNode: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, CaseIterable, Codable {
        case window = "Window / Root"
        case navigationBar = "Navigation / Header"
        case banner = "Hero / Image Banner"
        case cardContainer = "Section / Card"
        case actionGrid = "Menu / Grid"
        case button = "Button / CTA"
        case label = "Text / Label"
        case inputField = "Input / Field"

        public var defaultZLayer: Int {
            switch self {
            case .window: return 0
            case .cardContainer, .banner: return 1
            case .navigationBar, .actionGrid: return 2
            case .button, .label, .inputField: return 3
            }
        }

        public var iconName: String {
            switch self {
            case .window: return "macwindow"
            case .navigationBar: return "menubar.rectangle"
            case .banner: return "photo"
            case .cardContainer: return "rectangle.on.rectangle"
            case .actionGrid: return "square.grid.2x2"
            case .button: return "hand.tap"
            case .label: return "textformat"
            case .inputField: return "character.cursor.ibeam"
            }
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind
    public var zLayer: Int
    public var normalizedX: Double
    public var normalizedY: Double
    public var normalizedWidth: Double
    public var normalizedHeight: Double
    public var fileName: String
    public var filePath: String?
    public var lineNumber: Int
    public var codeSnippet: String

    // Live editable visual properties
    public var displayText: String
    public var accentHex: String
    public var cornerRadius: Double
    public var fontSize: Double
    public var opacity: Double
    public var isHidden: Bool
    public var isEdited: Bool

    public init(
        id: String? = nil,
        name: String,
        kind: Kind,
        zLayer: Int? = nil,
        normalizedX: Double,
        normalizedY: Double,
        normalizedWidth: Double,
        normalizedHeight: Double,
        fileName: String,
        filePath: String? = nil,
        lineNumber: Int,
        codeSnippet: String,
        displayText: String = "",
        accentHex: String = "#0A84FF",
        cornerRadius: Double = 12,
        fontSize: Double = 14,
        opacity: Double = 1.0,
        isHidden: Bool = false,
        isEdited: Bool = false
    ) {
        self.id = id ?? "\(fileName):\(lineNumber):\(name)"
        self.name = name
        self.kind = kind
        self.zLayer = zLayer ?? kind.defaultZLayer
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.fileName = fileName
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.codeSnippet = codeSnippet
        self.displayText = displayText.isEmpty ? name : displayText
        self.accentHex = accentHex
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.opacity = opacity
        self.isHidden = isHidden
        self.isEdited = isEdited
    }

    public var locationLabel: String {
        "\(fileName):\(lineNumber)"
    }
}

/// Inspects running Simulator/Device app screens and maps UIKit/SwiftUI view components to interactive 2D/3D layers with live source patching.
public struct UIHierarchyInspectorService: Sendable {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var screenFileIndexCache: [String: [URL]] = [:]

    public init() {}

    /// Pre-crops all component textures once off the main thread so 3D SceneKit & 2D overlays never crop during UI interaction.
    public static func preCropTextures(from fullImage: CGImage, nodes: [UIComponentNode]) -> [String: CGImage] {
        let imgW = CGFloat(fullImage.width)
        let imgH = CGFloat(fullImage.height)
        guard imgW > 1, imgH > 1 else { return [:] }

        var result: [String: CGImage] = [:]
        result.reserveCapacity(nodes.count)
        for node in nodes where node.kind != .window {
            let cropRect = CGRect(
                x: max(0, CGFloat(node.normalizedX) * imgW),
                y: max(0, CGFloat(node.normalizedY) * imgH),
                width: max(8, CGFloat(node.normalizedWidth) * imgW),
                height: max(8, CGFloat(node.normalizedHeight) * imgH)
            ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
            if !cropRect.isNull, cropRect.width >= 4, cropRect.height >= 4,
               let cropped = fullImage.cropping(to: cropRect) {
                result[node.id] = cropped
            }
        }
        return result
    }

    public static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        guard !inter.isNull else { return 0 }
        let interArea = Double(inter.width * inter.height)
        let unionArea = Double(a.width * a.height + b.width * b.height) - interArea
        guard unionArea > 0 else { return 0 }
        return interArea / unionArea
    }

    public func buildHierarchy(
        for process: SimulatorProcessInfo,
        in projectURL: URL?
    ) -> [UIComponentNode] {
        buildHierarchy(for: process, screenshotURL: nil, in: projectURL)
    }

    /// Builds a real-time 2D/3D UI hierarchy directly from the live captured iPhone/Simulator screenshot using Apple Vision OCR & Rectangle Detection,
    /// then matches each visible element back to its Swift source file & line in `projectURL`.
    public func buildHierarchy(
        for process: SimulatorProcessInfo,
        screenshotURL: URL?,
        in projectURL: URL?
    ) -> [UIComponentNode] {
        if let screenshotURL,
           let liveNodes = extractLiveNodesFromScreenshot(at: screenshotURL, appName: process.name, in: projectURL),
           !liveNodes.isEmpty {
            return liveNodes
        }

        var nodes: [UIComponentNode] = []
        if let projectURL {
            nodes = scanProjectUIComponents(in: projectURL, appName: process.name)
        }
        if nodes.isEmpty {
            nodes = Self.defaultHierarchy(for: process.name)
        }
        return nodes
    }

    private func extractLiveNodesFromScreenshot(
        at screenshotURL: URL,
        appName: String,
        in projectURL: URL?
    ) -> [UIComponentNode]? {
        guard let source = CGImageSourceCreateWithURL(screenshotURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.maximumObservations = 32
        rectRequest.minimumConfidence = 0.40
        rectRequest.minimumSize = 0.04

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, rectRequest])

        let textObs = textRequest.results ?? []
        let rectObs = rectRequest.results ?? []

        // Collect all visible text tokens to locate the exact active ViewController / SwiftUI View across the entire project
        let visibleTexts = textObs.compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        let screenContext = projectURL.map { resolveActiveScreenContext(visibleTexts: visibleTexts, in: $0) }
        let fallbackMatch: ScreenSourceMatch? = if screenContext?.primaryMatch == nil, let projectURL,
                                                   let scannedFirst = scanProjectUIComponents(in: projectURL, appName: appName).first(where: { $0.filePath != nil }) {
            ScreenSourceMatch(
                fileName: scannedFirst.fileName,
                filePath: scannedFirst.filePath ?? "",
                lineNumber: scannedFirst.lineNumber,
                snippet: scannedFirst.codeSnippet
            )
        } else {
            nil
        }
        let primaryMatch = screenContext?.primaryMatch ?? fallbackMatch
        let textSourceMatches = screenContext?.textMatches ?? [:]
        var unusedSwiftSymbols = screenContext?.swiftComponents ?? []

        func claimSwiftSymbol(for kind: UIComponentNode.Kind, matchingText: String? = nil) -> ParsedSwiftUIComponent? {
            if let matchingText,
               let idx = unusedSwiftSymbols.firstIndex(where: {
                   $0.name.localizedCaseInsensitiveContains(matchingText) || $0.snippet.localizedCaseInsensitiveContains(matchingText)
               }) {
                return unusedSwiftSymbols.remove(at: idx)
            }
            if let idx = unusedSwiftSymbols.firstIndex(where: { $0.kind == kind }) {
                return unusedSwiftSymbols.remove(at: idx)
            }
            return nil
        }

        var nodes: [UIComponentNode] = [
            UIComponentNode(
                id: "live-z0-root",
                name: primaryMatch.map { "\($0.fileName.replacingOccurrences(of: ".swift", with: "")) Root" } ?? "\(appName) Live Screen",
                kind: .window,
                zLayer: 0,
                normalizedX: 0.0,
                normalizedY: 0.0,
                normalizedWidth: 1.0,
                normalizedHeight: 1.0,
                fileName: primaryMatch?.fileName ?? "\(appName)Window.swift",
                filePath: primaryMatch?.filePath,
                lineNumber: primaryMatch?.lineNumber ?? 1,
                codeSnippet: primaryMatch?.snippet ?? "UIWindow(frame: UIScreen.main.bounds) // Live Screen (\(appName))",
                displayText: appName,
                accentHex: "#38BDF8",
                cornerRadius: 24,
                fontSize: 14
            )
        ]

        // Z1: Detected rectangular UI containers, hero banners, cards & buttons from live pixels (deduplicated by IoU)
        var acceptedRects: [CGRect] = []
        for (idx, rect) in rectObs.enumerated() {
            let box = rect.boundingBox
            let x = max(0.01, min(0.95, Double(box.origin.x)))
            let y = max(0.01, min(0.95, Double(1.0 - box.origin.y - box.height)))
            let w = max(0.05, min(0.98 - x, Double(box.width)))
            let h = max(0.03, min(0.98 - y, Double(box.height)))
            guard w * h < 0.82, y >= 0.048 else { continue }

            let candidateBox = CGRect(x: x, y: y, width: w, height: h)
            guard !acceptedRects.contains(where: { Self.intersectionOverUnion($0, candidateBox) > 0.45 }) else {
                continue
            }
            acceptedRects.append(candidateBox)

            let kind: UIComponentNode.Kind = if h > 0.22 {
                .banner
            } else if y > 0.72 && h < 0.14 {
                .button
            } else {
                .cardContainer
            }
            let zLayer = kind == .button ? 3 : 1
            let matchedSymbol = claimSwiftSymbol(for: kind)
            let fallbackName = kind == .banner ? "HeroImageView" : (kind == .button ? "ActionButton" : "ContainerCardView")

            nodes.append(
                UIComponentNode(
                    id: "live-rect-\(idx)",
                    name: matchedSymbol?.name ?? fallbackName,
                    kind: kind,
                    zLayer: zLayer,
                    normalizedX: x,
                    normalizedY: y,
                    normalizedWidth: w,
                    normalizedHeight: h,
                    fileName: matchedSymbol?.fileName ?? primaryMatch?.fileName ?? "\(appName)View.swift",
                    filePath: matchedSymbol?.filePath ?? primaryMatch?.filePath,
                    lineNumber: matchedSymbol?.lineNumber ?? primaryMatch?.lineNumber ?? 1,
                    codeSnippet: matchedSymbol?.snippet ?? primaryMatch?.snippet ?? "let \(fallbackName) = UIView() // (\(Int(x*100))%, \(Int(y*100))%)",
                    displayText: matchedSymbol?.name ?? fallbackName,
                    accentHex: kind == .button ? "#007AFF" : "#6366F1",
                    cornerRadius: 12,
                    fontSize: 12
                )
            )
            if acceptedRects.count >= 10 { break }
        }

        // Z2/Z3: All visible text & interactive CTA buttons recognized from the live iPhone/Simulator screen (excluding iOS status bar y < 0.048)
        for (idx, obs) in textObs.enumerated() {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let box = obs.boundingBox
            let padX = 0.015
            let padY = 0.010
            let x = max(0.01, Double(box.origin.x) - padX)
            let y = max(0.01, Double(1.0 - box.origin.y - box.height) - padY)
            guard y >= 0.045 else { continue } // skip iOS status-bar clock/battery noise
            let w = max(0.08, min(0.98 - x, Double(box.width) + padX * 2))
            let h = max(0.035, min(0.98 - y, Double(box.height) + padY * 2))

            let lower = text.lowercased()
            let isNav = y < 0.14
            let isButton = (y > 0.75) || lower.contains("login") || lower.contains("masuk") || lower.contains("kontak") || lower.contains("submit") || lower.contains("daftar")
            let kind: UIComponentNode.Kind = isNav ? .navigationBar : (isButton ? .button : .label)
            let zLayer = isNav ? 2 : 3
            let sourceMatch = textSourceMatches[text] ?? primaryMatch
            let matchedSymbol = claimSwiftSymbol(for: kind, matchingText: text)
            let displayTitle = matchedSymbol.map { "\(text) (\($0.name))" } ?? text

            nodes.append(
                UIComponentNode(
                    id: "live-ocr-\(idx)-\(text.prefix(12))",
                    name: displayTitle,
                    kind: kind,
                    zLayer: zLayer,
                    normalizedX: x,
                    normalizedY: y,
                    normalizedWidth: w,
                    normalizedHeight: h,
                    fileName: matchedSymbol?.fileName ?? sourceMatch?.fileName ?? "\(appName)View.swift",
                    filePath: matchedSymbol?.filePath ?? sourceMatch?.filePath,
                    lineNumber: matchedSymbol?.lineNumber ?? sourceMatch?.lineNumber ?? 1,
                    codeSnippet: matchedSymbol?.snippet ?? sourceMatch?.snippet ?? "// Live UI Element: \"\(text)\"",
                    displayText: text,
                    accentHex: isButton ? "#0A84FF" : (isNav ? "#34D399" : "#F59F00"),
                    cornerRadius: isButton ? 12 : 8,
                    fontSize: isButton ? 14 : 12
                )
            )
        }

        return nodes
    }

    private struct ScreenSourceMatch {
        let fileName: String
        let filePath: String
        let lineNumber: Int
        let snippet: String
    }

    private struct ParsedSwiftUIComponent {
        let name: String
        let kind: UIComponentNode.Kind
        let fileName: String
        let filePath: String
        let lineNumber: Int
        let snippet: String
    }

    private struct ActiveScreenContext {
        let primaryMatch: ScreenSourceMatch?
        let textMatches: [String: ScreenSourceMatch]
        let swiftComponents: [ParsedSwiftUIComponent]
    }

    private func cachedScreenFiles(in projectURL: URL) -> [URL] {
        let key = projectURL.path
        Self.cacheLock.lock()
        if let cached = Self.screenFileIndexCache[key] {
            Self.cacheLock.unlock()
            return cached
        }
        Self.cacheLock.unlock()

        let skippedDirs: Set<String> = [".build", "Pods", "DerivedData", ".git", "Tests", "Carthage", ".swiftpm"]
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var screenURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            if skippedDirs.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension == "swift" else { continue }
            let lowerName = fileURL.lastPathComponent.lowercased()
            if lowerName.contains("constant") || lowerName.contains("strings") || lowerName.contains("theme") || lowerName.contains("test") {
                continue
            }
            if lowerName.contains("vc") || lowerName.contains("controller") || lowerName.contains("view") || lowerName.contains("screen") || lowerName.contains("page") {
                screenURLs.append(fileURL)
            }
        }

        Self.cacheLock.lock()
        Self.screenFileIndexCache[key] = screenURLs
        Self.cacheLock.unlock()
        return screenURLs
    }

    /// Searches the cached View/ViewController index for the screen matching the most visible on-screen texts (<5ms per refresh).
    private func resolveActiveScreenContext(visibleTexts: [String], in projectURL: URL) -> ActiveScreenContext {
        let needles = Array(Set(visibleTexts.filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }))
        guard !needles.isEmpty else {
            return ActiveScreenContext(primaryMatch: nil, textMatches: [:], swiftComponents: [])
        }

        let screenFiles = cachedScreenFiles(in: projectURL)
        var textMatches: [String: ScreenSourceMatch] = [:]
        var bestScreenFile: (url: URL, score: Int, content: String)?

        for fileURL in screenFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var hitCount = 0
            for needle in needles {
                if content.localizedCaseInsensitiveContains("\"\(needle)\"") || content.localizedCaseInsensitiveContains(needle) {
                    hitCount += 1
                    if textMatches[needle] == nil {
                        let lines = content.components(separatedBy: .newlines)
                        if let lineIdx = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains(needle) }) {
                            textMatches[needle] = ScreenSourceMatch(
                                fileName: fileURL.lastPathComponent,
                                filePath: fileURL.path,
                                lineNumber: lineIdx + 1,
                                snippet: lines[lineIdx].trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }
                }
            }

            if hitCount > 0 {
                if bestScreenFile == nil || hitCount > bestScreenFile!.score {
                    bestScreenFile = (fileURL, hitCount, content)
                }
            }
        }

        var primaryMatch: ScreenSourceMatch?
        var parsedComponents: [ParsedSwiftUIComponent] = []

        if let best = bestScreenFile {
            let lines = best.content.components(separatedBy: .newlines)
            let classLineIdx = lines.firstIndex(where: { $0.contains("class ") || $0.contains("struct ") }) ?? 0
            primaryMatch = ScreenSourceMatch(
                fileName: best.url.lastPathComponent,
                filePath: best.url.path,
                lineNumber: classLineIdx + 1,
                snippet: lines[classLineIdx].trimmingCharacters(in: .whitespaces)
            )
            for (idx, rawLine) in lines.enumerated() {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.isEmpty else { continue }
                if let detected = Self.classifyComponentLine(trimmed) {
                    parsedComponents.append(
                        ParsedSwiftUIComponent(
                            name: detected.name,
                            kind: detected.kind,
                            fileName: best.url.lastPathComponent,
                            filePath: best.url.path,
                            lineNumber: idx + 1,
                            snippet: trimmed
                        )
                    )
                }
            }
        }

        return ActiveScreenContext(primaryMatch: primaryMatch, textMatches: textMatches, swiftComponents: parsedComponents)
    }

    private func scanProjectUIComponents(in projectURL: URL, appName: String) -> [UIComponentNode] {
        let skippedDirs: Set<String> = [".build", "Pods", "DerivedData", ".git", "Tests"]
        guard let enumerator = FileManager.default.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidateFiles: [(url: URL, mtime: Date, score: Int)] = []
        var scanned = 0
        for case let fileURL as URL in enumerator {
            guard scanned < 350 else { break }
            if skippedDirs.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension == "swift" else { continue }
            scanned += 1
            let name = fileURL.lastPathComponent
            let lower = name.lowercased()
            var score = 0
            if lower.contains("view") || lower.contains("vc") || lower.contains("controller") || lower.contains("screen") || lower.contains("cell") || lower.contains("banner") || lower.contains("login") || lower.contains("home") || lower.contains("dashboard") {
                score += 10
            }
            if lower.contains(appName.lowercased()) {
                score += 6
            }
            if score > 0 {
                let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                candidateFiles.append((fileURL, mtime, score))
            }
        }

        let prioritized = candidateFiles.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.mtime > $1.mtime
        }.prefix(18)

        var extracted: [UIComponentNode] = []

        // Always add Z0 Root Window node from the primary view file
        if let firstFile = prioritized.first?.url {
            extracted.append(
                UIComponentNode(
                    id: "root-window-\(firstFile.lastPathComponent)",
                    name: "\(appName) Root Window",
                    kind: .window,
                    zLayer: 0,
                    normalizedX: 0.02,
                    normalizedY: 0.02,
                    normalizedWidth: 0.96,
                    normalizedHeight: 0.96,
                    fileName: firstFile.lastPathComponent,
                    filePath: firstFile.path,
                    lineNumber: 1,
                    codeSnippet: "UIWindow / Root Container (\(appName))",
                    displayText: appName,
                    accentHex: "#0A84FF",
                    cornerRadius: 24,
                    fontSize: 15
                )
            )
        }

        let slotLayouts: [(x: Double, y: Double, w: Double, h: Double, color: String)] = [
            (0.06, 0.06, 0.88, 0.09, "#0A84FF"), // Top Navigation Bar
            (0.08, 0.17, 0.84, 0.32, "#1C7ED6"), // Hero / Profile Image Banner
            (0.06, 0.52, 0.88, 0.18, "#20C997"), // Fast Menu / Action Grid
            (0.08, 0.73, 0.66, 0.10, "#007AFF"), // Primary Login / CTA Button
            (0.77, 0.73, 0.15, 0.10, "#339AF0"), // Biometric / Secondary Button
            (0.08, 0.86, 0.84, 0.09, "#F59F00"), // Bottom Card / Footer Label
            (0.12, 0.22, 0.76, 0.08, "#FF6B6B"), // Title / Header Label
            (0.10, 0.55, 0.38, 0.12, "#51CF66")  // Sub-Card / Cell Component
        ]

        var slotIndex = 0
        for item in prioritized {
            guard extracted.count < 11,
                  let source = try? String(contentsOf: item.url, encoding: .utf8)
            else { continue }

            let lines = source.components(separatedBy: .newlines)
            for (idx, rawLine) in lines.enumerated() {
                guard extracted.count < 11 else { break }
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.isEmpty else { continue }

                if let detected = Self.classifyComponentLine(trimmed) {
                    let layout = slotLayouts[slotIndex % slotLayouts.count]
                    slotIndex += 1
                    let literalText = Self.extractQuotedString(from: trimmed) ?? detected.name
                    extracted.append(
                        UIComponentNode(
                            name: detected.name,
                            kind: detected.kind,
                            zLayer: detected.kind.defaultZLayer,
                            normalizedX: layout.x,
                            normalizedY: layout.y,
                            normalizedWidth: layout.w,
                            normalizedHeight: layout.h,
                            fileName: item.url.lastPathComponent,
                            filePath: item.url.path,
                            lineNumber: idx + 1,
                            codeSnippet: trimmed,
                            displayText: literalText,
                            accentHex: layout.color,
                            cornerRadius: detected.kind == .button ? 14 : 10,
                            fontSize: detected.kind == .label ? 15 : 13
                        )
                    )
                }
            }
        }

        return extracted
    }

    private static func classifyComponentLine(_ line: String) -> (name: String, kind: UIComponentNode.Kind)? {
        if line.contains("UIButton") || line.contains("Button(") || line.localizedCaseInsensitiveContains("loginButton") || line.localizedCaseInsensitiveContains("submitButton") {
            let name = extractIdentifier(from: line) ?? "ActionButton"
            return (name, .button)
        }
        if line.contains("UINavigationBar") || line.contains("navigationTitle(") || line.contains(".toolbar") || line.localizedCaseInsensitiveContains("headerView") {
            let name = extractIdentifier(from: line) ?? "NavigationHeader"
            return (name, .navigationBar)
        }
        if line.contains("UIImageView") || line.contains("Image(") || line.localizedCaseInsensitiveContains("banner") || line.localizedCaseInsensitiveContains("avatar") {
            let name = extractIdentifier(from: line) ?? "HeroBannerImage"
            return (name, .banner)
        }
        if line.contains("UICollectionView") || line.contains("LazyVGrid") || line.contains("UIStackView") || line.localizedCaseInsensitiveContains("fastMenu") {
            let name = extractIdentifier(from: line) ?? "FastMenuGrid"
            return (name, .actionGrid)
        }
        if line.contains("UITextField") || line.contains("TextField(") || line.contains("SecureField(") {
            let name = extractIdentifier(from: line) ?? "InputTextField"
            return (name, .inputField)
        }
        if line.contains("UILabel") || line.contains("Text(") {
            let name = extractIdentifier(from: line) ?? "TitleLabel"
            return (name, .label)
        }
        if (line.contains("class ") || line.contains("struct ")) && (line.contains("ViewController") || line.contains(": View")) {
            let name = extractIdentifier(from: line) ?? "ScreenContainer"
            return (name, .cardContainer)
        }
        return nil
    }

    private static func extractIdentifier(from line: String) -> String? {
        let patterns = [
            #"(?:var|let)\s+([A-Za-z0-9_]+)"#,
            #"(?:class|struct)\s+([A-Za-z0-9_]+)"#,
            #"Button\(\s*"([^"]+)""#,
            #"Text\(\s*"([^"]+)""#
        ]
        let ignoredKeywords: Set<String> = ["weak", "unowned", "private", "fileprivate", "public", "internal", "var", "let", "lazy", "static"]
        let ns = line as NSString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2 {
                let candidate = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty && !ignoredKeywords.contains(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func extractQuotedString(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #""([^"]{1,36})""#) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// Generates an updated Swift line/snippet reflecting the user's live component edits (text, cornerRadius, opacity, hidden) so it can be patched directly into the source file.
    public func buildCodePatch(for node: UIComponentNode) -> (oldSnippet: String, newSnippet: String) {
        let old = node.codeSnippet
        var updated = old

        if let existingLiteral = Self.extractQuotedString(from: old),
           !node.displayText.isEmpty,
           existingLiteral != node.displayText {
            updated = updated.replacingOccurrences(of: "\"\(existingLiteral)\"", with: "\"\(node.displayText)\"")
        }

        if updated == old {
            updated = "\(old) // [Live UI Edit: text=\"\(node.displayText)\", color=\(node.accentHex), radius=\(Int(node.cornerRadius)), font=\(Int(node.fontSize)), opacity=\(String(format: "%.2f", node.opacity))]"
        }
        return (old, updated)
    }

    public static func defaultHierarchy(for appName: String) -> [UIComponentNode] {
        [
            UIComponentNode(
                id: "z0-window",
                name: "\(appName) Window",
                kind: .window,
                zLayer: 0,
                normalizedX: 0.02,
                normalizedY: 0.02,
                normalizedWidth: 0.96,
                normalizedHeight: 0.96,
                fileName: "AppDelegate.swift",
                lineNumber: 18,
                codeSnippet: "window = UIWindow(frame: UIScreen.main.bounds)",
                displayText: appName,
                accentHex: "#0A84FF",
                cornerRadius: 24
            ),
            UIComponentNode(
                id: "z2-navbar",
                name: "TopBarHeaderView",
                kind: .navigationBar,
                zLayer: 2,
                normalizedX: 0.06,
                normalizedY: 0.06,
                normalizedWidth: 0.88,
                normalizedHeight: 0.09,
                fileName: "HomeViewController.swift",
                lineNumber: 34,
                codeSnippet: "private let topBarHeaderView = TopBarHeaderView()",
                displayText: "\(appName) Header",
                accentHex: "#1C7ED6",
                cornerRadius: 12
            ),
            UIComponentNode(
                id: "z1-banner",
                name: "HeroPromoBannerView",
                kind: .banner,
                zLayer: 1,
                normalizedX: 0.08,
                normalizedY: 0.18,
                normalizedWidth: 0.84,
                normalizedHeight: 0.34,
                fileName: "HomeViewController.swift",
                lineNumber: 58,
                codeSnippet: "private let heroBannerImageView = UIImageView()",
                displayText: "Featured Banner",
                accentHex: "#339AF0",
                cornerRadius: 16
            ),
            UIComponentNode(
                id: "z2-fastmenu",
                name: "FastMenuCollectionView",
                kind: .actionGrid,
                zLayer: 2,
                normalizedX: 0.06,
                normalizedY: 0.56,
                normalizedWidth: 0.88,
                normalizedHeight: 0.17,
                fileName: "FastMenuSectionView.swift",
                lineNumber: 22,
                codeSnippet: "let fastMenuGrid = UICollectionView(frame: .zero, collectionViewLayout: layout)",
                displayText: "QRIS • BRIZZI • E-Wallet • BRIVA",
                accentHex: "#20C997",
                cornerRadius: 14
            ),
            UIComponentNode(
                id: "z3-loginbtn",
                name: "PrimaryLoginButton",
                kind: .button,
                zLayer: 3,
                normalizedX: 0.08,
                normalizedY: 0.77,
                normalizedWidth: 0.66,
                normalizedHeight: 0.10,
                fileName: "LoginViewController.swift",
                lineNumber: 112,
                codeSnippet: "loginButton.setTitle(\"Login\", for: .normal)",
                displayText: "Login",
                accentHex: "#007AFF",
                cornerRadius: 14
            ),
            UIComponentNode(
                id: "z3-biometric",
                name: "FaceIDQuickButton",
                kind: .button,
                zLayer: 3,
                normalizedX: 0.77,
                normalizedY: 0.77,
                normalizedWidth: 0.15,
                normalizedHeight: 0.10,
                fileName: "LoginViewController.swift",
                lineNumber: 128,
                codeSnippet: "biometricButton.setImage(UIImage(systemName: \"faceid\"), for: .normal)",
                displayText: "Face ID",
                accentHex: "#0A84FF",
                cornerRadius: 14
            )
        ]
    }
}
