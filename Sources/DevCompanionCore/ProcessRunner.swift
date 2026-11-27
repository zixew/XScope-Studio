import Foundation

/// Result of executing a macOS developer toolchain command (`xcrun`, `xcodebuild`, etc.).
public struct CommandOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Async wrapper around `Foundation.Process` for invoking Xcode/Simulator CLI tools.
public protocol CommandExecuting: Sendable {
    func run(_ executable: String, arguments: [String], workingDirectory: URL?) async throws -> CommandOutput
}

private final class ProcessBox: @unchecked Sendable {
    let lock = NSLock()
    var process: Process?
    var finished = false
    var cancelled = false
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

public struct ProcessRunner: CommandExecuting {
    public let defaultTimeoutSeconds: Double

    public init(defaultTimeoutSeconds: Double = 60) {
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
    }

    public func run(
        _ executable: String,
        arguments: [String],
        workingDirectory: URL? = nil
    ) async throws -> CommandOutput {
        let box = ProcessBox()
        let timeout = defaultTimeoutSeconds

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    box.lock.lock()
                    let preCancelled = box.cancelled || Task.isCancelled
                    if preCancelled {
                        box.finished = true
                    }
                    box.lock.unlock()
                    if preCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    if let workingDirectory {
                        process.currentDirectoryURL = workingDirectory
                    }

                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    var timer: DispatchSourceTimer?

                    do {
                        try process.run()

                        box.lock.lock()
                        box.process = process
                        let cancelledDuringLaunch = box.cancelled || Task.isCancelled
                        box.lock.unlock()

                        if cancelledDuringLaunch, process.isRunning {
                            process.terminate()
                        }

                        let timeoutTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                        timeoutTimer.schedule(deadline: .now() + timeout)
                        timeoutTimer.setEventHandler {
                            box.lock.lock()
                            let isDone = box.finished
                            if !isDone {
                                box.finished = true
                                if process.isRunning {
                                    process.terminate()
                                }
                            }
                            box.lock.unlock()
                            if !isDone {
                                CompanionLog.process.warning("Timed out: \(executable, privacy: .public)")
                                continuation.resume(throwing: CompanionError.commandTimedOut(executable: executable, seconds: timeout))
                            }
                        }
                        timeoutTimer.resume()
                        timer = timeoutTimer

                        let group = DispatchGroup()
                        let stdoutBox = DataBox()
                        let stderrBox = DataBox()

                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            stdoutBox.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        group.enter()
                        DispatchQueue.global(qos: .userInitiated).async {
                            stderrBox.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                            group.leave()
                        }
                        group.wait()
                        process.waitUntilExit()

                        timeoutTimer.cancel()
                        box.lock.lock()
                        let alreadyResumed = box.finished
                        let wasCancelled = box.cancelled || Task.isCancelled
                        box.finished = true
                        box.lock.unlock()

                        guard !alreadyResumed else { return }
                        if wasCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        let stdout = String(data: stdoutBox.data, encoding: .utf8) ?? ""
                        let stderr = String(data: stderrBox.data, encoding: .utf8) ?? ""
                        continuation.resume(
                            returning: CommandOutput(
                                exitCode: process.terminationStatus,
                                stdout: stdout,
                                stderr: stderr
                            )
                        )
                    } catch {
                        timer?.cancel()
                        box.lock.lock()
                        let alreadyResumed = box.finished
                        let wasCancelled = box.cancelled || Task.isCancelled
                        box.finished = true
                        box.lock.unlock()
                        guard !alreadyResumed else { return }
                        if wasCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            box.lock.lock()
            box.cancelled = true
            if !box.finished, let process = box.process, process.isRunning {
                process.terminate()
            }
            box.lock.unlock()
        }
    }
}
