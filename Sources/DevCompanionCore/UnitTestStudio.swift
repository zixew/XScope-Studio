import Foundation

public enum TestFrameworkKind: String, CaseIterable, Sendable, Identifiable {
    case swiftTesting = "Swift Testing (@Test)"
    case xcTest = "XCTest (XCTestCase)"

    public var id: String { rawValue }
}

public struct ParsedSwiftSymbol: Sendable, Equatable {
    public let typeName: String
    public let isProtocol: Bool
    public let methods: [ParsedMethod]

    public init(typeName: String, isProtocol: Bool, methods: [ParsedMethod]) {
        self.typeName = typeName
        self.isProtocol = isProtocol
        self.methods = methods
    }
}

public struct ParsedMethod: Sendable, Equatable {
    public let name: String
    public let isAsync: Bool
    public let isThrowing: Bool
    public let returnType: String?

    public init(name: String, isAsync: Bool, isThrowing: Bool, returnType: String?) {
        self.name = name
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.returnType = returnType
    }
}

public struct XcodeProjectMetadata: Sendable, Equatable {
    public let projectName: String
    public let schemes: [String]
    public let targets: [String]

    public init(projectName: String, schemes: [String], targets: [String]) {
        self.projectName = projectName
        self.schemes = schemes
        self.targets = targets
    }
}

/// Parses Swift files to generate XCTest / Swift Testing + Mock Protocol suites and runs `xcodebuild test`.
public struct UnitTestStudio: Sendable {
    private let runner: any CommandExecuting

    public init(runner: any CommandExecuting = ProcessRunner(defaultTimeoutSeconds: 300)) {
        self.runner = runner
    }

    public func parseSymbols(from source: String) -> [ParsedSwiftSymbol] {
        let lines = source.components(separatedBy: .newlines)
        var symbols: [ParsedSwiftSymbol] = []
        var currentName: String?
        var currentIsProtocol = false
        var currentMethods: [ParsedMethod] = []

        let typeRegex = try? NSRegularExpression(pattern: #"\b(class|struct|actor|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        let funcRegex = try? NSRegularExpression(pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(async\s*)?(throws\s*)?(->\s*([^\{\n]+))?"#)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//") else { continue }

            let nsLine = line as NSString
            if let match = typeRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                if let name = currentName {
                    symbols.append(ParsedSwiftSymbol(typeName: name, isProtocol: currentIsProtocol, methods: currentMethods))
                }
                let kind = nsLine.substring(with: match.range(at: 1))
                currentName = nsLine.substring(with: match.range(at: 2))
                currentIsProtocol = (kind == "protocol")
                currentMethods = []
                continue
            }

            if currentName != nil, let fMatch = funcRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let funcName = nsLine.substring(with: fMatch.range(at: 1))
                let isAsync = fMatch.range(at: 2).location != NSNotFound
                let isThrowing = fMatch.range(at: 3).location != NSNotFound
                let retRange = fMatch.range(at: 5)
                let retType = retRange.location != NSNotFound
                    ? nsLine.substring(with: retRange).trimmingCharacters(in: .whitespaces)
                    : nil

                currentMethods.append(
                    ParsedMethod(name: funcName, isAsync: isAsync, isThrowing: isThrowing, returnType: retType)
                )
            }
        }

        if let name = currentName {
            symbols.append(ParsedSwiftSymbol(typeName: name, isProtocol: currentIsProtocol, methods: currentMethods))
        }

        return symbols
    }

    public func generateTests(
        from source: String,
        moduleName: String = "AppModule",
        framework: TestFrameworkKind
    ) -> String {
        let symbols = parseSymbols(from: source)
        let protocols = symbols.filter { $0.isProtocol }
        let subjects = symbols.filter { !$0.isProtocol }

        var out: [String] = []
        switch framework {
        case .swiftTesting:
            out.append("import Testing")
        case .xcTest:
            out.append("import XCTest")
        }
        out.append("@testable import \(moduleName)")
        out.append("")

        // Generate Mocks for detected protocols
        for proto in protocols {
            out.append("final class Mock\(proto.typeName): \(proto.typeName) {")
            for method in proto.methods {
                out.append("    var \(method.name)CallCount = 0")
                let asyncKW = method.isAsync ? "async " : ""
                let throwsKW = method.isThrowing ? "throws " : ""
                let retClause = method.returnType.map { " -> \($0)" } ?? ""
                out.append("    func \(method.name)() \(asyncKW)\(throwsKW)\(retClause) {")
                out.append("        \(method.name)CallCount += 1")
                if let ret = method.returnType {
                    out.append("        fatalError(\"Provide stub return value for \(ret)\")")
                }
                out.append("    }")
            }
            out.append("}")
            out.append("")
        }

        if subjects.isEmpty {
            out.append("// Tidak ada class/struct/actor yang terdeteksi pada sumber Swift.")
            return out.joined(separator: "\n")
        }

        for subject in subjects {
            switch framework {
            case .swiftTesting:
                out.append("@Suite(\"\(subject.typeName) Tests\")")
                out.append("struct \(subject.typeName)Tests {")
                let methods = subject.methods.isEmpty
                    ? [ParsedMethod(name: "initialState", isAsync: false, isThrowing: false, returnType: nil)]
                    : subject.methods
                for method in methods {
                    let asyncKW = method.isAsync ? "async " : ""
                    let throwsKW = method.isThrowing ? "throws " : ""
                    let awaitKW = method.isAsync ? "await " : ""
                    let tryKW = method.isThrowing ? "try " : ""
                    out.append("    @Test(\"\(method.name) behaves as expected\")")
                    out.append("    func test_\(method.name)() \(asyncKW)\(throwsKW){")
                    out.append("        // Arrange")
                    out.append("        let sut = \(subject.typeName)()")
                    out.append("        // Act")
                    if subject.methods.isEmpty {
                        out.append("        _ = sut")
                    } else {
                        out.append("        _ = \(tryKW)\(awaitKW)sut.\(method.name)()")
                    }
                    out.append("        // Assert")
                    out.append("        #expect(true)")
                    out.append("    }")
                    out.append("")
                }
                out.append("}")
                out.append("")

            case .xcTest:
                out.append("final class \(subject.typeName)Tests: XCTestCase {")
                let methods = subject.methods.isEmpty
                    ? [ParsedMethod(name: "initialState", isAsync: false, isThrowing: false, returnType: nil)]
                    : subject.methods
                for method in methods {
                    let asyncKW = method.isAsync ? "async " : ""
                    let throwsKW = method.isThrowing ? "throws " : ""
                    let awaitKW = method.isAsync ? "await " : ""
                    let tryKW = method.isThrowing ? "try " : ""
                    out.append("    func test_\(method.name)() \(asyncKW)\(throwsKW){")
                    out.append("        // Arrange")
                    out.append("        let sut = \(subject.typeName)()")
                    out.append("        // Act")
                    if subject.methods.isEmpty {
                        out.append("        _ = sut")
                    } else {
                        out.append("        _ = \(tryKW)\(awaitKW)sut.\(method.name)()")
                    }
                    out.append("        // Assert")
                    out.append("        XCTAssertNotNil(sut)")
                    out.append("    }")
                    out.append("")
                }
                out.append("}")
                out.append("")
            }
        }

        return out.joined(separator: "\n")
    }

    public func discoverProjectMetadata(projectPath: String) async throws -> XcodeProjectMetadata? {
        let isWorkspace = projectPath.hasSuffix(".xcworkspace")
        let flag = isWorkspace ? "-workspace" : "-project"
        let out = try await runner.run(
            "/usr/bin/xcodebuild",
            arguments: ["-list", "-json", flag, projectPath],
            workingDirectory: nil
        )
        guard out.isSuccess, let data = out.stdout.data(using: .utf8) else { return nil }
        return Self.parseXcodeListJson(from: data)
    }

    static func parseXcodeListJson(from data: Data) -> XcodeProjectMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let project = json["project"] as? [String: Any] {
            let name = (project["name"] as? String) ?? "Project"
            let schemes = (project["schemes"] as? [String]) ?? []
            let targets = (project["targets"] as? [String]) ?? []
            return XcodeProjectMetadata(projectName: name, schemes: schemes, targets: targets)
        }
        if let workspace = json["workspace"] as? [String: Any] {
            let name = (workspace["name"] as? String) ?? "Workspace"
            let schemes = (workspace["schemes"] as? [String]) ?? []
            return XcodeProjectMetadata(projectName: name, schemes: schemes, targets: [])
        }
        return nil
    }

    public func runXcodeBuildTest(
        projectPath: String,
        scheme: String,
        destination: String
    ) async throws -> CommandOutput {
        let isWorkspace = projectPath.hasSuffix(".xcworkspace")
        let flag = isWorkspace ? "-workspace" : "-project"
        return try await runner.run(
            "/usr/bin/xcodebuild",
            arguments: [
                "test",
                flag, projectPath,
                "-scheme", scheme,
                "-destination", destination,
                "-enableCodeCoverage", "YES"
            ],
            workingDirectory: nil
        )
    }
}
