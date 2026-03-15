import Darwin
import Foundation

struct CLICommand: Sendable, Equatable {
    var executable: String
    var arguments: [String] = []
    var workingDirectoryURL: URL?
    var environment: [String: String] = [:]
    var timeout: TimeInterval = 15

    static let containerSystemVersion = CLICommand(
        executable: "container",
        arguments: ["system", "version"],
        timeout: 10
    )
}

struct CommandResult: Sendable, Equatable {
    let command: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let startedAt: Date
    let duration: TimeInterval
}

enum CommandOutputSource: String, Sendable {
    case stdout
    case stderr
}

struct CommandOutputChunk: Sendable {
    let source: CommandOutputSource
    let text: String
}

enum AppError: Error, LocalizedError, Sendable, Equatable {
    case commandLaunchFailed(command: String, reason: String)
    case commandTimedOut(command: String, timeout: TimeInterval)
    case commandCancelled(command: String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandLaunchFailed(let command, let reason):
            "Failed to launch command (\(command)): \(reason)"
        case .commandTimedOut(let command, let timeout):
            "Command timed out after \(Int(timeout))s: \(command)"
        case .commandCancelled(let command):
            "Command cancelled: \(command)"
        case .commandFailed(let command, let exitCode, let stderr):
            if stderr.isEmpty {
                "Command failed with exit code \(exitCode): \(command)"
            } else {
                "Command failed with exit code \(exitCode): \(command)\n\(stderr)"
            }
        }
    }
}

actor CommandRunner {
    private var runningProcesses: [UUID: Process] = [:]

    func run(_ command: CLICommand) async throws -> CommandResult {
        try await runInternal(command, failOnNonZeroExit: true)
    }

    func runAllowingFailure(_ command: CLICommand) async throws -> CommandResult {
        try await runInternal(command, failOnNonZeroExit: false)
    }

    func runStreaming(
        _ command: CLICommand,
        onOutput: @escaping @Sendable (CommandOutputChunk) async -> Void
    ) async throws -> CommandResult {
        try await runInternal(
            command,
            failOnNonZeroExit: true,
            onOutput: onOutput
        )
    }

    private func runInternal(
        _ command: CLICommand,
        failOnNonZeroExit: Bool,
        onOutput: (@Sendable (CommandOutputChunk) async -> Void)? = nil
    ) async throws -> CommandResult {
        try Task.checkCancellation()

        let commandInvocation = invocation(for: command)
        let processID = UUID()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let startedAt = Date()
        let streamingBuffer = StreamingBuffer()

        if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = nil

        if let workingDirectoryURL = command.workingDirectoryURL {
            process.currentDirectoryURL = workingDirectoryURL
        }

        if !command.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, newValue in
                newValue
            }
        }

        do {
            try process.run()
        } catch {
            cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw AppError.commandLaunchFailed(
                command: commandInvocation,
                reason: error.localizedDescription
            )
        }

        runningProcesses[processID] = process

        defer {
            runningProcesses.removeValue(forKey: processID)
            cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        }

        if let onOutput {
            stdoutPipe.fileHandleForReading.readabilityHandler = streamingHandler(
                for: .stdout,
                buffer: streamingBuffer,
                onOutput: onOutput
            )
            stderrPipe.fileHandleForReading.readabilityHandler = streamingHandler(
                for: .stderr,
                buffer: streamingBuffer,
                onOutput: onOutput
            )
        }

        do {
            let exitCode = try await withTaskCancellationHandler {
                try await waitForExit(process: process, timeout: command.timeout, command: commandInvocation)
            } onCancel: {
                if process.isRunning {
                    process.terminate()
                }
            }

            if Task.isCancelled {
                throw AppError.commandCancelled(command: commandInvocation)
            }

            let stdout: String
            let stderr: String

            if onOutput != nil {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if !remainingStdout.isEmpty {
                    streamingBuffer.append(remainingStdout, source: .stdout)
                    let text = String(bytes: remainingStdout, encoding: .utf8) ?? ""
                    if !text.isEmpty, let onOutput {
                        await onOutput(CommandOutputChunk(source: .stdout, text: text))
                    }
                }
                if !remainingStderr.isEmpty {
                    streamingBuffer.append(remainingStderr, source: .stderr)
                    let text = String(bytes: remainingStderr, encoding: .utf8) ?? ""
                    if !text.isEmpty, let onOutput {
                        await onOutput(CommandOutputChunk(source: .stderr, text: text))
                    }
                }

                let snapshot = streamingBuffer.snapshot()
                stdout = snapshot.stdout
                stderr = snapshot.stderr
            } else {
                stdout = String(bytes: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                stderr = String(bytes: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            }

            let result = CommandResult(
                command: commandInvocation,
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr,
                startedAt: startedAt,
                duration: Date().timeIntervalSince(startedAt)
            )

            guard !failOnNonZeroExit || exitCode == 0 else {
                throw AppError.commandFailed(
                    command: result.command,
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
            }

            return result
        } catch let error as AppError {
            if case .commandTimedOut = error {
                await terminateProcessIfNeeded(process)
            }
            throw error
        } catch is CancellationError {
            await terminateProcessIfNeeded(process)
            throw AppError.commandCancelled(command: commandInvocation)
        } catch {
            await terminateProcessIfNeeded(process)
            throw AppError.commandLaunchFailed(
                command: commandInvocation,
                reason: error.localizedDescription
            )
        }
    }

    func cancelAll() {
        for process in runningProcesses.values where process.isRunning {
            process.terminate()
        }
        runningProcesses.removeAll()
    }

    private func waitForExit(
        process: Process,
        timeout: TimeInterval,
        command: String
    ) async throws -> Int32 {
        let pollIntervalNanoseconds: UInt64 = 50_000_000
        let timeoutNanoseconds = UInt64(max(timeout, 0.1) * 1_000_000_000)
        var elapsedNanoseconds: UInt64 = 0

        while process.isRunning {
            try Task.checkCancellation()
            if elapsedNanoseconds >= timeoutNanoseconds {
                throw AppError.commandTimedOut(command: command, timeout: timeout)
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            elapsedNanoseconds += pollIntervalNanoseconds
        }

        return process.terminationStatus
    }

    private func terminateProcessIfNeeded(_ process: Process) async {
        guard process.isRunning else { return }

        process.terminate()
        let graceDeadline = Date().addingTimeInterval(1.5)

        while process.isRunning && Date() < graceDeadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        guard process.isRunning else { return }

        kill(process.processIdentifier, SIGKILL)
        let killDeadline = Date().addingTimeInterval(1.0)
        while process.isRunning && Date() < killDeadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func cleanup(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }

    private func invocation(for command: CLICommand) -> String {
        ([command.executable] + sanitizedArgumentsForDisplay(command.arguments)).joined(separator: " ")
    }

    private func sanitizedArgumentsForDisplay(_ arguments: [String]) -> [String] {
        let sensitiveFlags = Set([
            "--env", "-e",
            "--password", "--token", "--secret", "--credential", "--credentials",
        ])

        var sanitized: [String] = []
        var redactNext = false

        for argument in arguments {
            if redactNext {
                if argument.contains("=") {
                    let key = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                    sanitized.append(key.isEmpty ? "<redacted>" : "\(key)=<redacted>")
                } else {
                    sanitized.append("<redacted>")
                }
                redactNext = false
                continue
            }

            if sensitiveFlags.contains(argument) {
                sanitized.append(argument)
                redactNext = true
                continue
            }

            if argument.hasPrefix("--env=") {
                let value = String(argument.dropFirst("--env=".count))
                if value.contains("=") {
                    let key = value.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                    sanitized.append("--env=\(key)=<redacted>")
                } else {
                    sanitized.append("--env=<redacted>")
                }
                continue
            }

            sanitized.append(argument)
        }

        if redactNext {
            sanitized.append("<redacted>")
        }

        return sanitized
    }

    private func streamingHandler(
        for source: CommandOutputSource,
        buffer: StreamingBuffer,
        onOutput: @escaping @Sendable (CommandOutputChunk) async -> Void
    ) -> (@Sendable (FileHandle) -> Void) {
        { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }

            buffer.append(data, source: source)
            let text = String(bytes: data, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }

            Task {
                await onOutput(CommandOutputChunk(source: source, text: text))
            }
        }
    }
}

private final class StreamingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func append(_ data: Data, source: CommandOutputSource) {
        lock.lock()
        defer { lock.unlock() }

        switch source {
        case .stdout:
            stdoutData.append(data)
        case .stderr:
            stderrData.append(data)
        }
    }

    func snapshot() -> (stdout: String, stderr: String) {
        lock.lock()
        defer { lock.unlock() }

        return (
            String(bytes: stdoutData, encoding: .utf8) ?? "",
            String(bytes: stderrData, encoding: .utf8) ?? ""
        )
    }
}
