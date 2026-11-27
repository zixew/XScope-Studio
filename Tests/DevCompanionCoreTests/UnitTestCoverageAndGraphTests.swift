import Foundation
import Testing
@testable import DevCompanionCore

@Suite("Unit Test Coverage & Dependency Graph Tests")
struct UnitTestCoverageAndGraphTests {
    @Test("UnitTestDependencyResolver resolves 1-2 hop cross-file Swift dependencies")
    func testCrossFileDependencyResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xscope_dep_graph_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoFile = root.appendingPathComponent("UserRepository.swift")
        try """
        protocol UserStoring {}
        final class UserRepository: UserStoring {
            func fetchUser(id: String) -> String { "User" }
            func saveUser(_ name: String) {}
        }
        """.write(to: repoFile, atomically: true, encoding: .utf8)

        let cacheFile = root.appendingPathComponent("SessionCache.swift")
        try """
        struct SessionCache {
            private let repo = UserRepository()
            func warmUp() { _ = repo.fetchUser(id: "1") }
        }
        """.write(to: cacheFile, atomically: true, encoding: .utf8)

        let entrySource = """
        final class ProfileViewModel {
            private let cache = SessionCache()
            func load() { cache.warmUp() }
        }
        """

        let resolver = UnitTestDependencyResolver()
        let nodes = resolver.resolveDependencies(for: entrySource, in: root, maxHops: 2)
        #expect(nodes.contains(where: { $0.typeName == "SessionCache" && $0.hopDepth == 1 }))
        #expect(nodes.contains(where: { $0.typeName == "UserRepository" && $0.hopDepth == 2 }))
    }

    @Test("CodeCoverageService parses xccov JSON and filters Per File / Per Directory / Whole Project")
    func testXccovParsingAndScopeFiltering() throws {
        let json = """
        {
          "targets": [
            {
              "name": "AppCore.framework",
              "files": [
                {
                  "path": "/repo/Sources/Auth/AuthManager.swift",
                  "coveredLines": 40,
                  "executableLines": 50,
                  "lineCoverage": 0.8,
                  "functions": [{"name": "logout()", "lineCoverage": 0.0}]
                },
                {
                  "path": "/repo/Sources/Billing/InvoiceService.swift",
                  "coveredLines": 10,
                  "executableLines": 50,
                  "lineCoverage": 0.2,
                  "functions": [{"name": "calculateTax()", "lineCoverage": 0.0}]
                }
              ]
            },
            {
              "name": "AppCoreTests.xctest",
              "files": [
                { "path": "/repo/Tests/AuthTests.swift", "coveredLines": 10, "executableLines": 10, "lineCoverage": 1.0 }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let parsed = CodeCoverageService.parseXccovReportJSON(data: json, projectRootPath: "/repo")
        #expect(parsed.count == 2)
        #expect(parsed.first?.fileName == "InvoiceService.swift")
        #expect(parsed.first?.uncoveredFunctions == ["calculateTax()"])

        let perFile = CodeCoverageService.filterFiles(parsed, scope: .file, selectedFilePath: "/repo/Sources/Auth/AuthManager.swift", selectedDirectoryPath: nil)
        #expect(perFile.count == 1)
        #expect(perFile.first?.fileName == "AuthManager.swift")

        let perDir = CodeCoverageService.filterFiles(parsed, scope: .directory, selectedFilePath: nil, selectedDirectoryPath: "/repo/Sources/Billing")
        #expect(perDir.count == 1)
        #expect(perDir.first?.fileName == "InvoiceService.swift")

        let whole = CodeCoverageService.filterFiles(parsed, scope: .project, selectedFilePath: nil, selectedDirectoryPath: nil)
        #expect(whole.count == 2)

        let emptyScope = CodeCoverageService.filterFiles(parsed, scope: .none, selectedFilePath: nil, selectedDirectoryPath: nil)
        #expect(emptyScope.isEmpty)
    }

    @Test("CodeCoverageService parses llvm-cov report output")
    func testLlvmCovReportParsing() {
        let report = """
        Filename                      Regions    Missed Regions     Cover   Functions  Missed Functions  Executed       Lines      Missed Lines     Cover
        ---------------------------------------------------------------------------------------------------------------------------------------------------
        Sources/Core/Engine.swift          20                 4    80.00%           5                 1    80.00%          50                10    80.00%
        TOTAL                              20                 4    80.00%           5                 1    80.00%          50                10    80.00%
        """
        let items = CodeCoverageService.parseLlvmCovReport(text: report, projectRootPath: "/repo")
        #expect(items.count == 1)
        #expect(items.first?.coveredLines == 40)
        #expect(items.first?.executableLines == 50)
        #expect(items.first?.lineCoveragePercent == 80.0)
    }

    @Test("UnitTestDependencyResolver auto-detects project root and collects multi-file/directory Swift sources")
    func testDetectProjectRootAndCollectMultiSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xscope_autodetect_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let deepDir = root.appendingPathComponent("Modules/Payment/Presentation", isDirectory: true)
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        try "// swift-tools-version: 6.0".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let fileA = deepDir.appendingPathComponent("PaymentVC.swift")
        let fileB = deepDir.appendingPathComponent("PaymentViewModel.swift")
        try "final class PaymentVC {}".write(to: fileA, atomically: true, encoding: .utf8)
        try "final class PaymentViewModel {}".write(to: fileB, atomically: true, encoding: .utf8)

        let detected = UnitTestDependencyResolver.detectProjectRoot(startingAt: fileA)
        #expect(detected?.standardizedFileURL.path == root.standardizedFileURL.path)

        let resolver = UnitTestDependencyResolver()
        let targets = resolver.listProjectSwiftTargets(in: root)
        #expect(targets.contains("Modules/Payment/Presentation/PaymentVC.swift"))
        #expect(targets.contains("Modules/Payment/Presentation"))

        let collectedDir = resolver.collectSwiftSources(from: [deepDir])
        #expect(collectedDir.combinedSource.contains("PaymentVC"))
        #expect(collectedDir.combinedSource.contains("PaymentViewModel"))
    }
}
