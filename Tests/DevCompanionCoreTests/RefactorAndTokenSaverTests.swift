import Foundation
import Testing
@testable import DevCompanionCore

@Suite("Refactor Engine & AI Token Saver Tests")
struct RefactorAndTokenSaverTests {
    @Test("RefactorEngine detects missing final, long function, deep nesting, and GCD blocks")
    func detectsRefactorOpportunities() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RefactorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var bodyLines: [String] = []
        bodyLines.append("class SampleCoordinator {")
        bodyLines.append("    func handleHugeFlow() {")
        bodyLines.append("        if true {")
        bodyLines.append("            if true {")
        bodyLines.append("                if true {")
        bodyLines.append("                    if true {")
        bodyLines.append("                        DispatchQueue.global().async { }")
        bodyLines.append("                    }")
        bodyLines.append("                }")
        bodyLines.append("            }")
        bodyLines.append("        }")
        for i in 0..<40 {
            bodyLines.append("        let v\(i) = \(i)")
        }
        bodyLines.append("    }")
        bodyLines.append("}")

        let fileURL = tmpDir.appendingPathComponent("SampleCoordinator.swift")
        try bodyLines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let engine = RefactorEngine()
        let items = engine.analyze(directoryURL: tmpDir)

        #expect(items.contains(where: { $0.rule == .missingFinal && $0.hasLocalFix }))
        #expect(items.contains(where: { $0.rule == .longFunction }))
        #expect(items.contains(where: { $0.rule == .deepNesting }))
        #expect(items.contains(where: { $0.rule == .dispatchQueueToAsync }))

        let longFn = try #require(items.first(where: { $0.rule == .longFunction }))
        let (prompt, budget) = engine.buildCompactRefactorPrompt(opportunity: longFn)
        #expect(prompt.contains("SampleCoordinator.swift"))
        #expect(prompt.contains("Unified diff only") || prompt.contains("unified diff only"))
        #expect(budget.compactTokens < budget.verboseTokens)
        #expect(budget.savedPercent > 0)
    }

    @Test("AgentService compact realtime leaks & hangs prompt filters local fixes and deduplicates")
    func compactRealtimeLeaksAndHangsPrompt() {
        let service = AgentService()
        let findings: [CodeReviewFinding] = [
            // Solvable locally for 0 tokens via [weak self]
            CodeReviewFinding(
                fileName: "LoginVC.swift",
                lineNumber: 12,
                severity: .critical,
                category: .memoryLeak,
                title: "Missing [weak self]",
                detail: "Closure captures self strongly",
                codeSnippet: "service.fetch { self.reload() }"
            ),
            // Duplicate AI finding 1
            CodeReviewFinding(
                fileName: "HomeVC.swift",
                lineNumber: 40,
                severity: .critical,
                category: .mainThread,
                title: "Main thread disk I/O",
                detail: "Blocking read",
                codeSnippet: "let d = try? Data(contentsOf: url)"
            ),
            // Duplicate AI finding 2 (same file + title)
            CodeReviewFinding(
                fileName: "HomeVC.swift",
                lineNumber: 55,
                severity: .critical,
                category: .mainThread,
                title: "Main thread disk I/O",
                detail: "Blocking read",
                codeSnippet: "let d2 = try? Data(contentsOf: url2)"
            )
        ]

        let freezes: [FreezeLagEvent] = [
            FreezeLagEvent(durationSeconds: 1.5, peakCPUPercent: 98, memoryMB: 180, culpritSymbol: "render()", fileName: "ListVC.swift", lineNumber: 100),
            FreezeLagEvent(durationSeconds: 1.2, peakCPUPercent: 95, memoryMB: 175, culpritSymbol: "render()", fileName: "ListVC.swift", lineNumber: 100)
        ]

        let (prompt, stats) = service.buildCompactRealtimeLeaksSummaryPrompt(
            findings: findings,
            freezes: freezes,
            crash: nil,
            snippet: nil
        )

        #expect(stats.localFixCount == 1)
        #expect(stats.deduplicatedCount == 2)
        #expect(stats.compactTokens < stats.verboseTokens)
        #expect(stats.savedPercent > 20)
        #expect(prompt.contains("F|HomeVC.swift:40"))
        #expect(!prompt.contains("LoginVC.swift"))
        #expect(prompt.contains("H|ListVC.swift:100"))
    }
}
