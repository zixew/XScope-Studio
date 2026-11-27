import Foundation
import Vision
import ImageIO

public struct ComponentConstraints: Sendable, Equatable, Codable {
    public var leading: Double?
    public var trailing: Double?
    public var top: Double?
    public var bottom: Double?
    public var width: Double?
    public var height: Double?
    public var centerX: Double?
    public var centerY: Double?

    public init(
        leading: Double? = nil,
        trailing: Double? = nil,
        top: Double? = nil,
        bottom: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        centerX: Double? = nil,
        centerY: Double? = nil
    ) {
        self.leading = leading
        self.trailing = trailing
        self.top = top
        self.bottom = bottom
        self.width = width
        self.height = height
        self.centerX = centerX
        self.centerY = centerY
    }
}

public struct ComponentActionBinding: Identifiable, Sendable, Equatable, Codable {
    public enum ActionKind: String, Sendable, Codable {
        case ibAction = "@IBAction"
        case addTarget = "addTarget (#selector)"
        case gesture = "Gesture Recognizer"
        case swiftUIButton = "SwiftUI Action"
    }

    public let id: String
    public let name: String
    public let kind: ActionKind
    public let selectorName: String
    public let lineNumber: Int
    public let bodySnippet: String

    public init(
        name: String,
        kind: ActionKind,
        selectorName: String,
        lineNumber: Int,
        bodySnippet: String
    ) {
        self.id = "\(kind.rawValue)::\(selectorName):\(lineNumber)"
        self.name = name
        self.kind = kind
        self.selectorName = selectorName
        self.lineNumber = lineNumber
        self.bodySnippet = bodySnippet
    }
}

public struct UIComponentNode: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, CaseIterable, Codable {
        case window = "Window / Root"
        case navigationBar = "Navigation / Header"
        case tabBar = "Tab Bar"
        case tableView = "UITableView / List"
        case collectionView = "UICollectionView / Grid"
        case scrollView = "UIScrollView / Scroll"
        case stackView = "UIStackView / Stack"
        case cell = "Table / Collection Cell"
        case banner = "Hero / Image Banner"
        case imageView = "UIImageView / Image"
        case cardContainer = "Section / Card"
        case actionGrid = "Menu / Grid"
        case button = "Button / CTA"
        case label = "Text / Label"
        case inputField = "Input / Field"
        case control = "Control / Toggle"

        public var defaultZLayer: Int {
            switch self {
            case .window: return 0
            case .scrollView, .tableView, .collectionView, .cardContainer, .banner: return 1
            case .stackView, .cell, .navigationBar, .tabBar, .actionGrid: return 2
            case .button, .label, .inputField, .imageView, .control: return 3
            }
        }

        public var iconName: String {
            switch self {
            case .window: return "macwindow"
            case .navigationBar: return "menubar.rectangle"
            case .tabBar: return "dock.rectangle"
            case .tableView: return "list.bullet.rectangle"
            case .collectionView: return "square.grid.3x3"
            case .scrollView: return "scroll"
            case .stackView: return "square.stack.3d.up"
            case .cell: return "rectangle.split.3x1"
            case .banner: return "photo"
            case .imageView: return "photo.artframe"
            case .cardContainer: return "rectangle.on.rectangle"
            case .actionGrid: return "square.grid.2x2"
            case .button: return "hand.tap"
            case .label: return "textformat"
            case .inputField: return "character.cursor.ibeam"
            case .control: return "slider.horizontal.3"
            }
        }

        public var isStructuralContainer: Bool {
            switch self {
            case .window, .cardContainer, .tableView, .collectionView, .scrollView, .stackView, .cell, .navigationBar, .tabBar:
                return true
            case .banner, .imageView, .actionGrid, .button, .label, .inputField, .control:
                return false
            }
        }
    }

    public let id: String
    public var parentID: String?
    public var depth: Int
    public var planeIndex: Int
    public var childCount: Int
    public var className: String
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
    public var backgroundHex: String
    public var borderHex: String
    public var borderWidth: Double
    public var cornerRadius: Double
    public var fontSize: Double
    public var fontWeight: String
    public var opacity: Double
    public var isHidden: Bool
    public var clipsToBounds: Bool
    public var isUserInteractionEnabled: Bool
    public var constraints: ComponentConstraints
    public var actions: [ComponentActionBinding]
    public var isEdited: Bool

    public init(
        id: String? = nil,
        parentID: String? = nil,
        depth: Int = 0,
        planeIndex: Int = 0,
        childCount: Int = 0,
        className: String? = nil,
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
        backgroundHex: String = "#161B26",
        borderHex: String = "#334155",
        borderWidth: Double = 0,
        cornerRadius: Double = 12,
        fontSize: Double = 14,
        fontWeight: String = "Regular",
        opacity: Double = 1.0,
        isHidden: Bool = false,
        clipsToBounds: Bool = true,
        isUserInteractionEnabled: Bool = true,
        constraints: ComponentConstraints = ComponentConstraints(),
        actions: [ComponentActionBinding] = [],
        isEdited: Bool = false
    ) {
        self.id = id ?? "\(fileName):\(lineNumber):\(name)"
        self.parentID = parentID
        self.depth = depth
        self.planeIndex = planeIndex
        self.childCount = childCount
        self.className = className ?? kind.rawValue
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
        self.backgroundHex = backgroundHex
        self.borderHex = borderHex
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.opacity = opacity
        self.isHidden = isHidden
        self.clipsToBounds = clipsToBounds
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.constraints = constraints
        self.actions = actions
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

    /// Eagerly decodes an image file into RAM (`CGImageSourceCreateWithData` + `kCGImageSourceShouldCacheImmediately`)
    /// so SceneKit textures remain valid even after the temporary screenshot file is shredded from disk.
    public static func decodeImageInMemory(from url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary)
    }

    /// Pre-crops all component textures once off the main thread so 3D SceneKit & 2D overlays never crop during UI interaction.
    public static func preCropTextures(from fullImage: CGImage, nodes: [UIComponentNode]) -> [String: CGImage] {
        let imgW = CGFloat(fullImage.width)
        let imgH = CGFloat(fullImage.height)
        guard imgW > 1, imgH > 1 else { return [:] }

        var result: [String: CGImage] = [:]
        result.reserveCapacity(nodes.count)
        for node in nodes where !node.kind.isStructuralContainer || node.kind == .navigationBar || node.kind == .tabBar || node.kind == .cell {
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

    private static let springBoardHomeLabels: [String] = [
        "find my", "shortcuts", "files", "contacts", "settings", "app store",
        "safari", "photos", "camera", "clock", "calendar", "google calendar",
        "whatsapp", "instagram", "tiktok", "shopee", "chatgpt", "discord",
        "telegram", "music", "video", "wallet", "weather", "notes",
        "reminders", "mail", "testflight", "maps", "podcasts", "health",
        "fitness", "tips", "bca mobile", "mybca", "mytelkomsel",
        "access by kai", "mobile legends", "duolingo", "vysor",
        "tokopedia", "grab", "gojek", "dana", "ovo", "lazada", "blibli",
        "spotify", "youtube", "netflix", "gmail", "chrome", "facebook",
        "indomaret poinku", "qita by bri", "authenticator", "threads", "linkedin"
    ]

    /// Computes the full UIKit/SwiftUI class inheritance chain for the Xcode Object Inspector.
    public static func classInheritanceChain(for kind: UIComponentNode.Kind, className: String) -> [String] {
        let base = className.isEmpty ? "UIView" : className
        switch kind {
        case .window:
            return [base, "UIWindow", "UIView", "UIResponder", "NSObject"]
        case .button:
            return [base, "UIButton", "UIControl", "UIView", "UIResponder", "NSObject"]
        case .control:
            return [base, "UIControl", "UIView", "UIResponder", "NSObject"]
        case .inputField:
            return [base, "UITextField", "UIControl", "UIView", "UIResponder", "NSObject"]
        case .label:
            return [base, "UILabel", "UIView", "UIResponder", "NSObject"]
        case .imageView, .banner:
            return [base, "UIImageView", "UIView", "UIResponder", "NSObject"]
        case .tableView:
            return [base, "UITableView", "UIScrollView", "UIView", "UIResponder", "NSObject"]
        case .collectionView:
            return [base, "UICollectionView", "UIScrollView", "UIView", "UIResponder", "NSObject"]
        case .scrollView:
            return [base, "UIScrollView", "UIView", "UIResponder", "NSObject"]
        case .stackView:
            return [base, "UIStackView", "UIView", "UIResponder", "NSObject"]
        case .navigationBar:
            return [base, "UINavigationBar", "UIView", "UIResponder", "NSObject"]
        case .tabBar:
            return [base, "UITabBar", "UIView", "UIResponder", "NSObject"]
        case .cell:
            return [base, "UITableViewCell", "UIView", "UIResponder", "NSObject"]
        case .cardContainer, .actionGrid:
            return [base, "UIView", "UIResponder", "NSObject"]
        }
    }

    /// Converts normalized coordinates into iOS point-space Frame and Bounds for the Xcode Size Inspector.
    public static func pointFrameAndBounds(
        for node: UIComponentNode,
        screenWidthPt: Double = 390,
        screenHeightPt: Double = 844
    ) -> (frame: CGRect, bounds: CGRect) {
        let x = (node.normalizedX * screenWidthPt).rounded()
        let y = (node.normalizedY * screenHeightPt).rounded()
        let w = max(1, (node.normalizedWidth * screenWidthPt).rounded())
        let h = max(1, (node.normalizedHeight * screenHeightPt).rounded())
        return (CGRect(x: x, y: y, width: w, height: h), CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// Collects the IDs of `rootID` and all its descendants for Xcode-style "Focus on View" subtree isolation.
    public static func subtreeNodeIDs(rootedAt rootID: String, in nodes: [UIComponentNode]) -> Set<String> {
        var result: Set<String> = [rootID]
        var added = true
        while added {
            added = false
            for node in nodes {
                if let pid = node.parentID, result.contains(pid), result.insert(node.id).inserted {
                    added = true
                }
            }
        }
        return result
    }

    /// Detects whether the captured device screen is currently on the iOS Home Screen (`SpringBoard`) rather than inside an opened app.
    public static func isSpringBoardHomeScreen(visibleTexts: [String]) -> Bool {
        var matchedHomeIcons: Set<String> = []
        for raw in visibleTexts {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: "\n", with: " ")
            guard clean.count >= 2 else { continue }
            for label in springBoardHomeLabels {
                if clean == label || clean.contains(label) || (label.contains(clean) && clean.count >= 4) {
                    matchedHomeIcons.insert(label)
                    break
                }
            }
        }
        return matchedHomeIcons.count >= 2
    }

    /// Builds a real-time 2D/3D UI hierarchy directly from the live captured iPhone/Simulator screenshot using Apple Vision OCR & Rectangle Detection,
    /// then matches each visible element back to its Swift source file & line in `projectURL`.
    public func buildHierarchy(
        for process: SimulatorProcessInfo,
        screenshotURL: URL?,
        in projectURL: URL?
    ) -> [UIComponentNode] {
        if let screenshotURL,
           let liveNodes = extractLiveNodesFromScreenshot(at: screenshotURL, appName: process.name, in: projectURL) {
            return liveNodes
        }

        var nodes: [UIComponentNode] = []
        if let projectURL {
            nodes = scanProjectUIComponents(in: projectURL, appName: process.name)
        }
        if nodes.isEmpty {
            nodes = Self.defaultHierarchy(for: process.name)
        }
        return Self.buildHierarchyTree(from: nodes)
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

        // If the device is sitting on the iOS Home Screen (SpringBoard), no app is actively open in the foreground!
        if Self.isSpringBoardHomeScreen(visibleTexts: visibleTexts) {
            try? FileManager.default.removeItem(at: screenshotURL)
            return []
        }

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
            guard let matchingText, matchingText.count >= 3 else { return nil }
            if let idx = unusedSwiftSymbols.firstIndex(where: {
                $0.name.localizedCaseInsensitiveContains(matchingText) || $0.snippet.localizedCaseInsensitiveContains(matchingText)
            }) {
                return unusedSwiftSymbols.remove(at: idx)
            }
            return nil
        }

        var nodes: [UIComponentNode] = [
            UIComponentNode(
                id: "live-z0-root",
                className: "UIWindow",
                name: primaryMatch.map { "\($0.fileName.replacingOccurrences(of: ".swift", with: "")) Window" } ?? "\(appName) Window",
                kind: .window,
                zLayer: 0,
                normalizedX: 0.0,
                normalizedY: 0.0,
                normalizedWidth: 1.0,
                normalizedHeight: 1.0,
                fileName: primaryMatch?.fileName ?? "\(appName)Window.swift",
                filePath: primaryMatch?.filePath,
                lineNumber: primaryMatch?.lineNumber ?? 1,
                codeSnippet: primaryMatch?.snippet ?? "UIWindow(frame: UIScreen.main.bounds)",
                displayText: appName,
                accentHex: "#38BDF8",
                cornerRadius: 24,
                fontSize: 14
            ),
            UIComponentNode(
                id: "live-z1-rootview",
                parentID: "live-z0-root",
                className: "UIView",
                name: primaryMatch.map { "\($0.fileName.replacingOccurrences(of: ".swift", with: "")) View" } ?? "\(appName) Root View",
                kind: .banner,
                zLayer: 1,
                normalizedX: 0.0,
                normalizedY: 0.0,
                normalizedWidth: 1.0,
                normalizedHeight: 1.0,
                fileName: primaryMatch?.fileName ?? "\(appName)View.swift",
                filePath: primaryMatch?.filePath,
                lineNumber: primaryMatch?.lineNumber ?? 1,
                codeSnippet: primaryMatch?.snippet ?? "override func viewDidLoad()",
                displayText: appName,
                accentHex: "#38BDF8",
                cornerRadius: 22,
                fontSize: 13
            )
        ]

        // Pre-extract clean, deduplicated OCR boxes first so rectangles know whether they are leaf banners or parent cards containing text
        struct OCRItem {
            let text: String
            let rect: CGRect
        }
        var ocrItems: [OCRItem] = []
        for obs in textObs {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else { continue }
            let box = obs.boundingBox
            let padX = 0.012
            let padY = 0.008
            let x = max(0.01, Double(box.origin.x) - padX)
            let y = max(0.01, Double(1.0 - box.origin.y - box.height) - padY)
            guard y >= 0.048 else { continue }
            let w = max(0.06, min(0.98 - x, Double(box.width) + padX * 2))
            let h = max(0.032, min(0.98 - y, Double(box.height) + padY * 2))
            let candidateRect = CGRect(x: x, y: y, width: w, height: h)
            let isDup = ocrItems.contains { existing in
                Self.intersectionOverUnion(existing.rect, candidateRect) > 0.32
                    || (existing.text.caseInsensitiveCompare(text) == .orderedSame && abs(existing.rect.midY - candidateRect.midY) < 0.06)
            }
            if !isDup {
                ocrItems.append(OCRItem(text: text, rect: candidateRect))
            }
        }

        // Merge overlapping or fragmented Vision rectangles (e.g. hero banner strips)
        var mergedRects: [CGRect] = []
        for rect in rectObs {
            let box = rect.boundingBox
            let x = max(0.02, min(0.95, Double(box.origin.x)))
            let y = max(0.05, min(0.95, Double(1.0 - box.origin.y - box.height)))
            let w = max(0.08, min(0.96 - x, Double(box.width)))
            let h = max(0.04, min(0.96 - y, Double(box.height)))
            guard w * h < 0.78, w * h > 0.012 else { continue }
            let candidate = CGRect(x: x, y: y, width: w, height: h)

            if let mergeIdx = mergedRects.firstIndex(where: { existing in
                let inter = existing.intersection(candidate)
                let interArea = inter.isNull ? 0 : (inter.width * inter.height)
                let minArea = min(existing.width * existing.height, candidate.width * candidate.height)
                let sameHeroBand = (existing.minY < 0.50 && candidate.minY < 0.50 && abs(existing.midX - candidate.midX) < 0.22 && abs(existing.midY - candidate.midY) < 0.18)
                return Self.intersectionOverUnion(existing, candidate) > 0.18 || (minArea > 0 && interArea / minArea > 0.45) || sameHeroBand
            }) {
                mergedRects[mergeIdx] = mergedRects[mergeIdx].union(candidate)
            } else if mergedRects.count < 6 {
                mergedRects.append(candidate)
            }
        }

        for (idx, box) in mergedRects.enumerated() {
            let containedTexts = ocrItems.filter { item in
                box.insetBy(dx: -0.02, dy: -0.02).contains(CGPoint(x: item.rect.midX, y: item.rect.midY))
            }
            // If a rectangle contains multiple child labels/buttons (e.g. Fast Menu card with QRIS/BRIZZI/E Wallet/BRIVA),
            // it MUST be a structural `.cardContainer` (translucent backing frame) so its screenshot isn't duplicated behind its children!
            let kind: UIComponentNode.Kind = if containedTexts.count >= 3 || (box.width > 0.68 && box.height > 0.14) {
                .cardContainer
            } else if box.height > 0.16 && box.minY < 0.60 {
                .banner
            } else if box.minY > 0.74 && box.height < 0.13 {
                .button
            } else {
                .cardContainer
            }
            let zLayer = kind == .button ? 3 : 1
            let fallbackName = kind == .banner ? "HeroBannerImageView" : (kind == .button ? "PrimaryActionButton" : "SectionCardContainer")

            nodes.append(
                UIComponentNode(
                    id: "live-rect-\(idx)",
                    className: kind == .banner ? "UIImageView" : (kind == .button ? "UIButton" : "UIView"),
                    name: fallbackName,
                    kind: kind,
                    zLayer: zLayer,
                    normalizedX: box.origin.x,
                    normalizedY: box.origin.y,
                    normalizedWidth: box.size.width,
                    normalizedHeight: box.size.height,
                    fileName: primaryMatch?.fileName ?? "\(appName)View.swift",
                    filePath: primaryMatch?.filePath,
                    lineNumber: primaryMatch?.lineNumber ?? 1,
                    codeSnippet: primaryMatch?.snippet ?? "let \(fallbackName) = UIView()",
                    displayText: fallbackName,
                    accentHex: kind == .button ? "#007AFF" : "#6366F1",
                    cornerRadius: 12,
                    fontSize: 12
                )
            )
        }

        for (idx, item) in ocrItems.enumerated() {
            let text = item.text
            let r = item.rect
            let lower = text.lowercased()
            let isNav = r.minY < 0.13
            let isButton = (r.minY > 0.75) || lower == "login" || lower == "masuk" || lower.contains("fast menu")
            let kind: UIComponentNode.Kind = isNav ? .label : (isButton ? .button : .label)
            let zLayer = isNav ? 2 : 3
            let sourceMatch = textSourceMatches[text] ?? primaryMatch
            let matchedSymbol = claimSwiftSymbol(for: kind, matchingText: text)
            let cleanTitle = matchedSymbol.map { "\(text) (\($0.name))" } ?? text

            nodes.append(
                UIComponentNode(
                    id: "live-ocr-\(idx)-\(text.prefix(12))",
                    className: isButton ? "UIButton" : "UILabel",
                    name: cleanTitle,
                    kind: kind,
                    zLayer: zLayer,
                    normalizedX: r.origin.x,
                    normalizedY: r.origin.y,
                    normalizedWidth: r.size.width,
                    normalizedHeight: r.size.height,
                    fileName: matchedSymbol?.fileName ?? sourceMatch?.fileName ?? "\(appName)View.swift",
                    filePath: matchedSymbol?.filePath ?? sourceMatch?.filePath,
                    lineNumber: matchedSymbol?.lineNumber ?? sourceMatch?.lineNumber ?? 1,
                    codeSnippet: matchedSymbol?.snippet ?? sourceMatch?.snippet ?? "view.text = \"\(text)\"",
                    displayText: text,
                    accentHex: isButton ? "#0A84FF" : (isNav ? "#34D399" : "#F59F00"),
                    cornerRadius: isButton ? 12 : 8,
                    fontSize: isButton ? 14 : 12
                )
            )
        }

        return Self.buildHierarchyTree(from: nodes)
    }

    /// Assembles a root-to-leaf parent-child tree from flat nodes using containment geometry and zLayer order.
    public static func buildHierarchyTree(from flatNodes: [UIComponentNode]) -> [UIComponentNode] {
        guard !flatNodes.isEmpty else { return [] }
        var nodes = flatNodes
        let rootIdx = nodes.firstIndex(where: { $0.kind == .window }) ?? 0
        let rootID = nodes[rootIdx].id

        func area(_ n: UIComponentNode) -> Double {
            max(0.0001, n.normalizedWidth * n.normalizedHeight)
        }

        func contains(_ outer: UIComponentNode, _ inner: UIComponentNode) -> Bool {
            let tol = 0.03
            return inner.normalizedX >= outer.normalizedX - tol
                && inner.normalizedY >= outer.normalizedY - tol
                && (inner.normalizedX + inner.normalizedWidth) <= (outer.normalizedX + outer.normalizedWidth + tol)
                && (inner.normalizedY + inner.normalizedHeight) <= (outer.normalizedY + outer.normalizedHeight + tol)
        }

        for i in nodes.indices {
            if i == rootIdx {
                nodes[i].parentID = nil
                continue
            }
            if let explicitParent = nodes[i].parentID, nodes.contains(where: { $0.id == explicitParent }) {
                continue
            }
            let child = nodes[i]
            let candidates = nodes.indices.filter { pIdx in
                guard pIdx != i else { return false }
                let parent = nodes[pIdx]
                if parent.zLayer > child.zLayer { return false }
                if area(parent) <= area(child) * 1.05 { return false }
                return contains(parent, child)
            }
            if let bestParentIdx = candidates.min(by: { area(nodes[$0]) < area(nodes[$1]) }) {
                nodes[i].parentID = nodes[bestParentIdx].id
            } else {
                nodes[i].parentID = rootID
            }
        }

        var childrenMap: [String: [Int]] = [:]
        for i in nodes.indices {
            if let pid = nodes[i].parentID {
                childrenMap[pid, default: []].append(i)
            }
        }

        var ordered: [UIComponentNode] = []
        var visited: Set<String> = []
        func dfs(_ idx: Int, depth: Int) {
            let id = nodes[idx].id
            guard visited.insert(id).inserted else { return }
            var node = nodes[idx]
            node.depth = depth
            let childIndices = childrenMap[id] ?? []
            node.childCount = childIndices.count
            ordered.append(node)
            for cIdx in childIndices {
                dfs(cIdx, depth: depth + 1)
            }
        }
        dfs(rootIdx, depth: 0)
        for i in nodes.indices where !visited.contains(nodes[i].id) {
            dfs(i, depth: 1)
        }

        // Assign distinct stepped 3D plane indices:
        // Structural containers (UIWindow, ViewController, UITableView, UIStackView, etc.) each step along their own backing planes (0..C-1),
        // and foreground leaf elements step across planes C..N by depth so nothing clumps or z-fights.
        var nextContainerPlane = 0
        for i in ordered.indices where ordered[i].kind.isStructuralContainer {
            ordered[i].planeIndex = nextContainerPlane
            nextContainerPlane += 1
        }
        let baseLeafPlane = max(1, nextContainerPlane)
        var leafCounter = 0
        for i in ordered.indices where !ordered[i].kind.isStructuralContainer {
            ordered[i].planeIndex = baseLeafPlane + ordered[i].depth + (leafCounter / 3)
            leafCounter += 1
        }
        return ordered
    }

    public static func ancestorBreadcrumb(for nodeID: String?, in nodes: [UIComponentNode]) -> [UIComponentNode] {
        guard let nodeID, !nodes.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var chain: [UIComponentNode] = []
        var visited: Set<String> = []
        var cursor = byID[nodeID]
        while let current = cursor, visited.insert(current.id).inserted {
            chain.append(current)
            if let pid = current.parentID {
                cursor = byID[pid]
            } else {
                cursor = nil
            }
        }
        return chain.reversed()
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
        var bestScreenFile: (url: URL, score: Int, content: String)?

        // Pass 1: Score all candidate screen files using non-comment code lines to identify the true active ViewController/View.
        for fileURL in screenFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            var score = 0
            let codeLines = content.components(separatedBy: .newlines).filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("//") && !t.hasPrefix("/*") && !t.hasPrefix("*")
            }
            let codeBody = codeLines.joined(separator: "\n")
            for needle in needles {
                if codeBody.localizedCaseInsensitiveContains("\"\(needle)\"") {
                    score += 3
                } else if codeBody.localizedCaseInsensitiveContains(needle) {
                    score += 1
                }
            }
            if score > 0, bestScreenFile == nil || score > bestScreenFile!.score {
                bestScreenFile = (fileURL, score, content)
            }
        }

        var primaryMatch: ScreenSourceMatch?
        var textMatches: [String: ScreenSourceMatch] = [:]
        var parsedComponents: [ParsedSwiftUIComponent] = []

        // Pass 2: Scope textMatches strictly to `bestScreenFile` and its same-folder/feature subviews/cells.
        if let best = bestScreenFile {
            let bestLines = best.content.components(separatedBy: .newlines)
            let classLineIdx = bestLines.firstIndex(where: { $0.contains("class ") || $0.contains("struct ") }) ?? 0
            primaryMatch = ScreenSourceMatch(
                fileName: best.url.lastPathComponent,
                filePath: best.url.path,
                lineNumber: classLineIdx + 1,
                snippet: bestLines[classLineIdx].trimmingCharacters(in: .whitespaces)
            )

            let bestDir = best.url.deletingLastPathComponent().standardizedFileURL.path
            let scopedFiles: [(url: URL, lines: [String])] = [(best.url, bestLines)] + screenFiles.compactMap { url in
                guard url != best.url else { return nil }
                let dir = url.deletingLastPathComponent().standardizedFileURL.path
                guard dir == bestDir || dir.hasPrefix(bestDir + "/") else { return nil }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (url, content.components(separatedBy: .newlines))
            }

            for needle in needles {
                var matched: ScreenSourceMatch?
                for file in scopedFiles {
                    if let lineIdx = file.lines.firstIndex(where: { line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !t.hasPrefix("//"), !t.hasPrefix("/*"), !t.hasPrefix("*") else { return false }
                        return t.localizedCaseInsensitiveContains("\"\(needle)\"")
                    }) ?? file.lines.firstIndex(where: { line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty, !t.hasPrefix("//"), !t.hasPrefix("/*"), !t.hasPrefix("*") else { return false }
                        return t.localizedCaseInsensitiveContains(needle)
                    }) {
                        matched = ScreenSourceMatch(
                            fileName: file.url.lastPathComponent,
                            filePath: file.url.path,
                            lineNumber: lineIdx + 1,
                            snippet: file.lines[lineIdx].trimmingCharacters(in: .whitespaces)
                        )
                        break
                    }
                }
                if let matched {
                    textMatches[needle] = matched
                }
            }

            for (idx, rawLine) in bestLines.enumerated() {
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
        if line.contains("UITableViewCell") || line.contains("UICollectionViewCell") {
            let name = extractIdentifier(from: line) ?? "TableOrCollectionCell"
            return (name, .cell)
        }
        if line.contains("UITableView") || line.contains("List(") || line.contains("List {") {
            let name = extractIdentifier(from: line) ?? "TableView"
            return (name, .tableView)
        }
        if line.contains("UICollectionView") || line.contains("LazyVGrid") || line.contains("LazyHGrid") {
            let name = extractIdentifier(from: line) ?? "CollectionView"
            return (name, .collectionView)
        }
        if line.contains("UIScrollView") || line.contains("ScrollView") {
            let name = extractIdentifier(from: line) ?? "ScrollView"
            return (name, .scrollView)
        }
        if line.contains("UIStackView") || line.contains("VStack") || line.contains("HStack") || line.contains("ZStack") {
            let name = extractIdentifier(from: line) ?? "StackView"
            return (name, .stackView)
        }
        if line.contains("UITabBar") || line.contains("TabView") {
            let name = extractIdentifier(from: line) ?? "TabBar"
            return (name, .tabBar)
        }
        if line.contains("UISwitch") || line.contains("UISlider") || line.contains("UISegmentedControl") || line.contains("Toggle(") || line.contains("Picker(") {
            let name = extractIdentifier(from: line) ?? "Control"
            return (name, .control)
        }
        if line.contains("UIButton") || line.contains("Button(") || line.localizedCaseInsensitiveContains("loginButton") || line.localizedCaseInsensitiveContains("submitButton") {
            let name = extractIdentifier(from: line) ?? "ActionButton"
            return (name, .button)
        }
        if line.contains("UINavigationBar") || line.contains("navigationTitle(") || line.contains(".toolbar") || line.localizedCaseInsensitiveContains("headerView") {
            let name = extractIdentifier(from: line) ?? "NavigationHeader"
            return (name, .navigationBar)
        }
        if line.contains("UIImageView") || line.contains("Image(") || line.localizedCaseInsensitiveContains("banner") || line.localizedCaseInsensitiveContains("avatar") {
            let name = extractIdentifier(from: line) ?? "ImageView"
            return (name, .imageView)
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

    /// Generates an updated Swift line/snippet reflecting the user's XIB & constraint edits so it can be patched directly into the source file.
    public func buildCodePatch(for node: UIComponentNode) -> (oldSnippet: String, newSnippet: String) {
        let old = node.codeSnippet
        var updated = old

        if let existingLiteral = Self.extractQuotedString(from: old),
           !node.displayText.isEmpty,
           existingLiteral != node.displayText {
            updated = updated.replacingOccurrences(of: "\"\(existingLiteral)\"", with: "\"\(node.displayText)\"")
        }

        updated = Self.replaceNumericArg(in: updated, label: "cornerRadius", value: node.cornerRadius)
        updated = Self.replaceNumericArg(in: updated, label: "borderWidth", value: node.borderWidth)
        updated = Self.replaceNumericArg(in: updated, label: "alpha", value: node.opacity, decimals: 2)
        updated = Self.replaceBoolArg(in: updated, label: "isHidden", value: node.isHidden)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "leadingAnchor", value: node.constraints.leading)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "trailingAnchor", value: node.constraints.trailing)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "topAnchor", value: node.constraints.top)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "bottomAnchor", value: node.constraints.bottom)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "widthAnchor", value: node.constraints.width)
        updated = Self.replaceConstraintConstant(in: updated, anchor: "heightAnchor", value: node.constraints.height)

        if updated == old {
            var extras: [String] = []
            if node.cornerRadius > 0 { extras.append("radius=\(Int(node.cornerRadius))") }
            if node.borderWidth > 0 { extras.append("border=\(String(format: "%.1f", node.borderWidth))") }
            if let l = node.constraints.leading { extras.append("leading=\(Int(l))") }
            if let t = node.constraints.top { extras.append("top=\(Int(t))") }
            if let w = node.constraints.width { extras.append("w=\(Int(w))") }
            if let h = node.constraints.height { extras.append("h=\(Int(h))") }
            let summary = extras.isEmpty ? "text=\"\(node.displayText)\", color=\(node.accentHex)" : extras.joined(separator: ", ")
            updated = "\(old) // [XScope XIB: \(summary)]"
        }
        return (old, updated)
    }

    public func loadSurroundingSource(filePath: String?, lineNumber: Int, radius: Int = 18) -> String? {
        guard let filePath,
              let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }
        let start = max(1, lineNumber - radius)
        let end = min(lines.count, lineNumber + radius)
        guard start <= end else { return nil }
        return lines[(start - 1)...(end - 1)].joined(separator: "\n")
    }

    public func parseConstraints(in source: String, aroundLine: Int? = nil) -> ComponentConstraints {
        var result = ComponentConstraints()
        let lines = source.components(separatedBy: .newlines)
        let window: ArraySlice<String>
        if let line = aroundLine, line > 0 {
            let s = max(0, line - 25)
            let e = min(lines.count, line + 35)
            window = lines[s..<e]
        } else {
            window = lines[0..<lines.count]
        }

        for raw in window {
            if let val = Self.extractConstraintConstant(in: raw, anchor: "leadingAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "leading") {
                result.leading = result.leading ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "trailingAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "trailing") {
                result.trailing = result.trailing ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "topAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "top") {
                result.top = result.top ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "bottomAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "bottom") {
                result.bottom = result.bottom ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "widthAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "width") {
                result.width = result.width ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "heightAnchor") ?? Self.extractSnapKitConstant(in: raw, edge: "height") {
                result.height = result.height ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "centerXAnchor") {
                result.centerX = result.centerX ?? val
            }
            if let val = Self.extractConstraintConstant(in: raw, anchor: "centerYAnchor") {
                result.centerY = result.centerY ?? val
            }
        }
        return result
    }

    public func generateLiveComponentCode(for node: UIComponentNode) -> String {
        let topStr = node.constraints.top.map { "\(Int($0.rounded()))" } ?? "nil"
        let leadStr = node.constraints.leading.map { "\(Int($0.rounded()))" } ?? "nil"
        let trailStr = node.constraints.trailing.map { "\(Int($0.rounded()))" } ?? "nil"
        let botStr = node.constraints.bottom.map { "\(Int($0.rounded()))" } ?? "nil"
        let wStr = node.constraints.width.map { "\(Int($0.rounded()))" } ?? "nil"
        let hStr = node.constraints.height.map { "\(Int($0.rounded()))" } ?? "nil"

        return """
        // Component: \(node.name) (\(node.className))
        // Source: \(node.locationLabel)
        \(node.codeSnippet)

        // Editable Live Properties (Preview in 2D/3D & Apply to Xcode):
        view.text = "\(node.displayText)"
        view.accentHex = "\(node.accentHex)"
        view.backgroundHex = "\(node.backgroundHex)"
        view.layer.cornerRadius = \(Int(node.cornerRadius.rounded()))
        view.layer.borderWidth = \(String(format: "%.1f", node.borderWidth))
        view.font = .systemFont(ofSize: \(Int(node.fontSize.rounded())))
        view.alpha = \(String(format: "%.2f", node.opacity))
        view.isHidden = \(node.isHidden)
        view.clipsToBounds = \(node.clipsToBounds)
        view.isUserInteractionEnabled = \(node.isUserInteractionEnabled)

        // Editable AutoLayout Constants (pt or nil):
        constraint.top = \(topStr)
        constraint.leading = \(leadStr)
        constraint.trailing = \(trailStr)
        constraint.bottom = \(botStr)
        constraint.width = \(wStr)
        constraint.height = \(hStr)
        """
    }

    public func applyLiveComponentCode(_ code: String, to node: UIComponentNode) -> UIComponentNode {
        var updated = node
        for raw in code.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//"), !line.isEmpty else { continue }

            if line.contains("view.text"), let str = Self.extractQuotedString(from: line) {
                updated.displayText = str
            } else if line.contains("view.accentHex"), let str = Self.extractQuotedString(from: line) {
                updated.accentHex = str
            } else if line.contains("view.backgroundHex"), let str = Self.extractQuotedString(from: line) {
                updated.backgroundHex = str
            } else if line.contains("cornerRadius"), let val = Self.extractTrailingNumber(in: line) {
                updated.cornerRadius = val
            } else if line.contains("borderWidth"), let val = Self.extractTrailingNumber(in: line) {
                updated.borderWidth = val
            } else if line.contains("ofSize:"), let val = Self.extractNumberAfter("ofSize:", in: line) {
                updated.fontSize = val
            } else if line.contains("view.alpha"), let val = Self.extractTrailingNumber(in: line) {
                updated.opacity = max(0.05, min(1.0, val))
            } else if line.contains("view.isHidden") {
                updated.isHidden = line.contains("true")
            } else if line.contains("view.clipsToBounds") {
                updated.clipsToBounds = line.contains("true")
            } else if line.contains("view.isUserInteractionEnabled") {
                updated.isUserInteractionEnabled = line.contains("true")
            } else if line.hasPrefix("constraint.top") {
                updated.constraints.top = Self.extractTrailingNumber(in: line)
            } else if line.hasPrefix("constraint.leading") {
                updated.constraints.leading = Self.extractTrailingNumber(in: line)
            } else if line.hasPrefix("constraint.trailing") {
                updated.constraints.trailing = Self.extractTrailingNumber(in: line)
            } else if line.hasPrefix("constraint.bottom") {
                updated.constraints.bottom = Self.extractTrailingNumber(in: line)
            } else if line.hasPrefix("constraint.width") {
                updated.constraints.width = Self.extractTrailingNumber(in: line)
            } else if line.hasPrefix("constraint.height") {
                updated.constraints.height = Self.extractTrailingNumber(in: line)
            }
        }
        return updated
    }

    private static func extractTrailingNumber(in line: String) -> Double? {
        guard !line.contains("nil") else { return nil }
        guard let eq = line.range(of: "=") else { return nil }
        let rhs = line[eq.upperBound...].trimmingCharacters(in: .whitespaces)
        return Double(rhs)
    }

    private static func extractNumberAfter(_ prefix: String, in line: String) -> Double? {
        guard let r = line.range(of: prefix) else { return nil }
        let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = rest.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(digits)
    }

    public func discoverActions(
        in source: String,
        componentName: String? = nil,
        displayText: String? = nil,
        kind: UIComponentNode.Kind? = nil
    ) -> [ComponentActionBinding] {
        // Non-interactive views (labels, images, banners, containers) should NEVER inherit unrelated ViewController actions!
        let interactiveKinds: Set<UIComponentNode.Kind> = [.button, .control, .actionGrid, .cell]
        if let kind, !interactiveKinds.contains(kind) {
            return []
        }

        let lines = source.components(separatedBy: .newlines)
        var found: [ComponentActionBinding] = []
        var seen: Set<String> = []

        let tokens: [String] = [componentName, displayText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && $0 != "ActionButton" && $0 != "PrimaryActionButton" }

        for (idx, raw) in lines.enumerated() {
            let lineNo = idx + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            let matchesComponent: Bool = if tokens.isEmpty {
                true
            } else {
                tokens.contains { tok in
                    trimmed.localizedCaseInsensitiveContains(tok)
                }
            }

            // 1. @IBAction func foo(_ sender: Any)
            if trimmed.contains("@IBAction"), let fn = Self.extractFuncName(in: trimmed), matchesComponent {
                let snippet = Self.sliceFunctionBody(lines: lines, startIndex: idx)
                let key = "ib::\(fn)"
                if seen.insert(key).inserted {
                    found.append(ComponentActionBinding(name: fn, kind: .ibAction, selectorName: fn, lineNumber: lineNo, bodySnippet: snippet))
                }
            }

            // 2. .addTarget(..., action: #selector(foo))
            if trimmed.contains("addTarget("), let sel = Self.extractSelectorName(in: trimmed), matchesComponent {
                let key = "target::\(sel)"
                if seen.insert(key).inserted {
                    found.append(ComponentActionBinding(name: sel, kind: .addTarget, selectorName: sel, lineNumber: lineNo, bodySnippet: trimmed))
                }
            }

            // 3. UITapGestureRecognizer(target: ..., action: #selector(foo))
            if trimmed.contains("GestureRecognizer"), let sel = Self.extractSelectorName(in: trimmed), matchesComponent {
                let key = "gesture::\(sel)"
                if seen.insert(key).inserted {
                    found.append(ComponentActionBinding(name: sel, kind: .gesture, selectorName: sel, lineNumber: lineNo, bodySnippet: trimmed))
                }
            }

            // 4. SwiftUI Button(action: ...) or Button("Title") { ... }
            if (trimmed.hasPrefix("Button(") || trimmed.contains(" Button(")), matchesComponent {
                let snippet = Self.sliceFunctionBody(lines: lines, startIndex: idx)
                let label = Self.extractQuotedString(from: trimmed) ?? componentName ?? "Button Action"
                let key = "swiftui::\(lineNo)::\(label)"
                if seen.insert(key).inserted {
                    found.append(ComponentActionBinding(name: label, kind: .swiftUIButton, selectorName: label, lineNumber: lineNo, bodySnippet: snippet))
                }
            }
        }
        return found
    }

    private static func replaceNumericArg(in code: String, label: String, value: Double, decimals: Int = 0) -> String {
        let formatted = decimals == 0 ? "\(Int(value.rounded()))" : String(format: "%.\(decimals)f", value)
        let pattern = "(\(label)\\s*=\\s*)(-?[0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return code }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return regex.stringByReplacingMatches(in: code, range: range, withTemplate: "$1\(formatted)")
    }

    private static func replaceBoolArg(in code: String, label: String, value: Bool) -> String {
        let pattern = "(\(label)\\s*=\\s*)(true|false)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return code }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return regex.stringByReplacingMatches(in: code, range: range, withTemplate: "$1\(value ? "true" : "false")")
    }

    private static func replaceConstraintConstant(in code: String, anchor: String, value: Double?) -> String {
        guard let value, code.contains(anchor) else { return code }
        let pattern = "(\(anchor)[^\\n]*?(?:equalToConstant|constant):\\s*)(-?[0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return code }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return regex.stringByReplacingMatches(in: code, range: range, withTemplate: "$1\(Int(value.rounded()))")
    }

    private static func extractConstraintConstant(in line: String, anchor: String) -> Double? {
        guard line.contains(anchor) else { return nil }
        let pattern = "(?:equalToConstant|constant):\\s*(-?[0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[r])
    }

    private static func extractSnapKitConstant(in line: String, edge: String) -> Double? {
        guard line.contains(".\(edge).") else { return nil }
        let pattern = "(?:equalTo|offset|inset)\\((-?[0-9]+(?:\\.[0-9]+)?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return Double(line[r])
    }

    private static func extractFuncName(in line: String) -> String? {
        let pattern = #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
    }

    private static func extractSelectorName(in line: String) -> String? {
        let pattern = #"#selector\((?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_:]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
    }

    private static func sliceFunctionBody(lines: [String], startIndex: Int) -> String {
        let end = min(lines.count - 1, startIndex + 7)
        return lines[startIndex...end].joined(separator: "\n")
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
