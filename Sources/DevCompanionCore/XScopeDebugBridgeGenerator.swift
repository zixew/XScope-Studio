import Foundation

public struct DebugBridgeActionPayload: Sendable, Codable {
    public let selectorName: String
    public let targetName: String
    public init(selectorName: String, targetName: String) {
        self.selectorName = selectorName
        self.targetName = targetName
    }
}

public struct DebugBridgeMutationPayload: Sendable, Codable {
    public let componentName: String
    public let displayText: String
    public let backgroundHex: String
    public let accentHex: String
    public let cornerRadius: Double
    public let borderWidth: Double
    public let borderHex: String
    public let opacity: Double
    public let isHidden: Bool
    public let leadingConstant: Double?
    public let topConstant: Double?
    public let widthConstant: Double?
    public let heightConstant: Double?

    public init(from node: UIComponentNode) {
        self.componentName = node.name
        self.displayText = node.displayText
        self.backgroundHex = node.backgroundHex
        self.accentHex = node.accentHex
        self.cornerRadius = node.cornerRadius
        self.borderWidth = node.borderWidth
        self.borderHex = node.borderHex
        self.opacity = node.opacity
        self.isHidden = node.isHidden
        self.leadingConstant = node.constraints.leading
        self.topConstant = node.constraints.top
        self.widthConstant = node.constraints.width
        self.heightConstant = node.constraints.height
    }
}

/// Generates and communicates with an optional 1-file `#if DEBUG` in-app bridge for live UIKit/SwiftUI mutation & selector invocation.
public struct XScopeDebugBridgeService: Sendable {
    public static let defaultPort: UInt16 = 49876

    public init() {}

    public func pingBridge(port: UInt16 = defaultPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.8
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func fetchHierarchy(port: UInt16 = defaultPort) async -> [UIComponentNode]? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/hierarchy") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.2
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let rawItems = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }
            let nodes: [UIComponentNode] = rawItems.enumerated().map { idx, item in
                let cls = (item["className"] as? String) ?? "UIView"
                let name = (item["name"] as? String) ?? cls
                let kind = Self.kind(forClassName: cls)
                return UIComponentNode(
                    id: (item["id"] as? String) ?? "bridge-\(idx)",
                    parentID: item["parentID"] as? String,
                    depth: (item["depth"] as? Int) ?? 0,
                    childCount: (item["childCount"] as? Int) ?? 0,
                    className: cls,
                    name: name,
                    kind: kind,
                    zLayer: min(3, (item["depth"] as? Int) ?? kind.defaultZLayer),
                    normalizedX: (item["normalizedX"] as? Double) ?? 0,
                    normalizedY: (item["normalizedY"] as? Double) ?? 0,
                    normalizedWidth: (item["normalizedWidth"] as? Double) ?? 1,
                    normalizedHeight: (item["normalizedHeight"] as? Double) ?? 1,
                    fileName: "LiveBridge.swift",
                    lineNumber: 1,
                    codeSnippet: "// Live \(cls) (\(name))",
                    displayText: (item["displayText"] as? String) ?? name,
                    cornerRadius: (item["cornerRadius"] as? Double) ?? 0,
                    opacity: (item["opacity"] as? Double) ?? 1.0,
                    isHidden: (item["isHidden"] as? Bool) ?? false
                )
            }
            return UIHierarchyInspectorService.buildHierarchyTree(from: nodes)
        } catch {
            return nil
        }
    }

    private static func kind(forClassName cls: String) -> UIComponentNode.Kind {
        let lower = cls.lowercased()
        if lower.contains("window") { return .window }
        if lower.contains("tableviewcell") || lower.contains("collectionviewcell") { return .cell }
        if lower.contains("tableview") { return .tableView }
        if lower.contains("collectionview") { return .collectionView }
        if lower.contains("scrollview") { return .scrollView }
        if lower.contains("stackview") { return .stackView }
        if lower.contains("navigationbar") { return .navigationBar }
        if lower.contains("tabbar") { return .tabBar }
        if lower.contains("imageview") { return .imageView }
        if lower.contains("button") { return .button }
        if lower.contains("label") { return .label }
        if lower.contains("textfield") || lower.contains("textview") { return .inputField }
        if lower.contains("switch") || lower.contains("slider") || lower.contains("segmented") { return .control }
        return .cardContainer
    }

    public func sendMutation(node: UIComponentNode, port: UInt16 = defaultPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/mutate"),
              let body = try? JSONEncoder().encode(DebugBridgeMutationPayload(from: node)) else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func invokeAction(selectorName: String, targetName: String, port: UInt16 = defaultPort) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/invoke"),
              let body = try? JSONEncoder().encode(DebugBridgeActionPayload(selectorName: selectorName, targetName: targetName)) else {
            return false
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public static func generateBridgeSwiftSource(port: UInt16 = defaultPort) -> String {
        """
        #if DEBUG
        import Foundation
        import Network
        import UIKit

        /// Drop-in XScope Studio Debug Bridge for live UIKit/SwiftUI mutation & #selector invocation.
        @MainActor
        public final class XScopeDebugBridge {
            public static let shared = XScopeDebugBridge()
            private var listener: NWListener?

            public func start(port: UInt16 = \(port)) {
                guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
                guard let listener = try? NWListener(using: .tcp, on: nwPort) else { return }
                listener.newConnectionHandler = { [weak self] conn in
                    conn.start(queue: .main)
                    self?.receive(on: conn)
                }
                listener.start(queue: .main)
                self.listener = listener
            }

            private func receive(on conn: NWConnection) {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
                    guard let data, let raw = String(data: data, encoding: .utf8) else {
                        conn.cancel()
                        return
                    }
                    Task { @MainActor in
                        self?.handleHTTP(raw, on: conn)
                    }
                }
            }

            private func handleHTTP(_ raw: String, on conn: NWConnection) {
                let parts = raw.components(separatedBy: "\\r\\n\\r\\n")
                let header = parts.first ?? ""
                let bodyData = (parts.dropFirst().first ?? "").data(using: .utf8) ?? Data()

                if header.contains("GET /health") {
                    respond("200 OK", body: "ok", on: conn)
                    return
                }
                if header.contains("GET /hierarchy") {
                    let dump = dumpWindowHierarchyJSON()
                    respond("200 OK", body: dump, on: conn)
                    return
                }
                if header.contains("POST /invoke"),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let selName = json["selectorName"] as? String {
                    let ok = invokeSelector(named: selName)
                    respond(ok ? "200 OK" : "404 Not Found", body: ok ? "invoked" : "missing", on: conn)
                    return
                }
                if header.contains("POST /mutate"),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    applyMutation(json)
                    respond("200 OK", body: "mutated", on: conn)
                    return
                }
                respond("400 Bad Request", body: "unsupported", on: conn)
            }

            private func invokeSelector(named selectorName: String) -> Bool {
                let sel = NSSelectorFromString(selectorName)
                guard let root = activeRootViewController() else { return false }
                var stack: [UIViewController] = [root]
                while let vc = stack.popLast() {
                    if vc.responds(to: sel) {
                        _ = vc.perform(sel, with: nil)
                        return true
                    }
                    stack.append(contentsOf: vc.children)
                    if let presented = vc.presentedViewController { stack.append(presented) }
                }
                return false
            }

            private func applyMutation(_ json: [String: Any]) {
                guard let name = json["componentName"] as? String,
                      let rootView = activeRootViewController()?.view else { return }
                guard let target = findView(named: name, in: rootView) else { return }
                if let opacity = json["opacity"] as? Double { target.alpha = opacity }
                if let hidden = json["isHidden"] as? Bool { target.isHidden = hidden }
                if let radius = json["cornerRadius"] as? Double { target.layer.cornerRadius = radius }
                if let borderW = json["borderWidth"] as? Double { target.layer.borderWidth = borderW }
                if let text = json["displayText"] as? String {
                    (target as? UILabel)?.text = text
                    (target as? UIButton)?.setTitle(text, for: .normal)
                }
            }

            private func findView(named name: String, in root: UIView) -> UIView? {
                if root.accessibilityIdentifier == name || String(describing: type(of: root)) == name {
                    return root
                }
                for sub in root.subviews {
                    if let hit = findView(named: name, in: sub) { return hit }
                }
                return nil
            }

            private func activeRootViewController() -> UIViewController? {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?.rootViewController
            }

            private func dumpWindowHierarchyJSON() -> String {
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) else { return "[]" }
                let winBounds = window.bounds.size
                let winW = max(1, winBounds.width)
                let winH = max(1, winBounds.height)
                var items: [[String: Any]] = []

                func walk(_ view: UIView, parentID: String?, depth: Int) {
                    let nodeID = "\\(ObjectIdentifier(view).hashValue)"
                    let frameInWin = view.convert(view.bounds, to: window)
                    let cls = String(describing: type(of: view))
                    let label = view.accessibilityIdentifier ?? (view as? UILabel)?.text ?? (view as? UIButton)?.title(for: .normal) ?? cls
                    items.append([
                        "id": nodeID,
                        "parentID": parentID as Any,
                        "depth": depth,
                        "childCount": view.subviews.count,
                        "className": cls,
                        "name": label,
                        "displayText": label,
                        "normalizedX": Double(frameInWin.origin.x / winW),
                        "normalizedY": Double(frameInWin.origin.y / winH),
                        "normalizedWidth": Double(frameInWin.size.width / winW),
                        "normalizedHeight": Double(frameInWin.size.height / winH),
                        "opacity": Double(view.alpha),
                        "isHidden": view.isHidden,
                        "cornerRadius": Double(view.layer.cornerRadius)
                    ])
                    for sub in view.subviews {
                        walk(sub, parentID: nodeID, depth: depth + 1)
                    }
                }
                walk(window, parentID: nil, depth: 0)
                guard let data = try? JSONSerialization.data(withJSONObject: items),
                      let json = String(data: data, encoding: .utf8) else { return "[]" }
                return json
            }

            private func respond(_ status: String, body: String, on conn: NWConnection) {
                let res = "HTTP/1.1 \\(status)\\r\\nContent-Length: \\(body.utf8.count)\\r\\n\\r\\n\\(body)"
                conn.send(content: res.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        #endif
        """
    }
}
