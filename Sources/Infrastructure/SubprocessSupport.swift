import Darwin
import Domain
import Foundation

/// Cancellation-aware, bounded Foundation.Process runner for non-interactive probes.
enum SubprocessSupport {
    static let defaultOutputLimit = 1 << 20

    enum ExecutionError: LocalizedError {
        case timedOut(TimeInterval)

        var errorDescription: String? {
            switch self {
            case .timedOut(let seconds):
                "Command timed out after \(seconds) seconds"
            }
        }
    }

    struct Output: Sendable {
        let standardOutput: String
        let standardError: String
        let exitCode: Int32
        let wasTruncated: Bool

        var isSuccess: Bool { exitCode == 0 }
    }

    static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        input: String? = nil,
        outputLimit: Int = defaultOutputLimit,
        timeout: TimeInterval? = nil,
        qualityOfService: QualityOfService = ProbeExecutionContext.qualityOfService
    ) async throws -> Output {
        let execution = ProcessExecution(
            executablePath: executablePath,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            input: input,
            outputLimit: max(0, outputLimit),
            timeout: timeout,
            qualityOfService: qualityOfService
        )
        return try await withTaskCancellationHandler {
            try await execution.value()
        } onCancel: {
            execution.cancel()
        }
    }
}

private final class ProcessExecution: @unchecked Sendable {
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let stdin: Pipe?
    private let outputLimit: Int
    private let timeout: TimeInterval?
    private let qualityOfService: QualityOfService
    private let lock = NSLock()

    private var standardOutput = Data()
    private var standardError = Data()
    private var capturedBytes = 0
    private var wasTruncated = false
    private var processGroupCreated = false
    private var terminalError: Error?
    private var continuation: CheckedContinuation<SubprocessSupport.Output, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var hasFinished = false

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: String?,
        input: String?,
        outputLimit: Int,
        timeout: TimeInterval?,
        qualityOfService: QualityOfService
    ) {
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.standardOutput = stdout
        process.standardError = stderr
        if let input {
            let pipe = Pipe()
            stdin = pipe
            process.standardInput = pipe
            self.input = Data(input.utf8)
        } else {
            stdin = nil
            self.input = nil
        }
        self.outputLimit = outputLimit
        self.timeout = timeout
        self.qualityOfService = qualityOfService
    }

    private let input: Data?

    func value() async throws -> SubprocessSupport.Output {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            start()
        }
    }

    func cancel() {
        terminate(with: CancellationError())
    }

    private func start() {
        let queue = DispatchQueue.global(qos: Self.qos(from: qualityOfService))
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.capture(handle.availableData, isStandardOutput: true)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.capture(handle.availableData, isStandardOutput: false)
        }
        process.terminationHandler = { [weak self] process in
            self?.finish(exitCode: process.terminationStatus)
        }

        queue.async { [self] in
            do {
                try process.run()
                processGroupCreated = setpgid(process.processIdentifier, process.processIdentifier) == 0
                writeInput(on: queue)
                scheduleTimeout(on: queue)
            } catch {
                finish(error: error)
            }
        }
    }

    private func writeInput(on queue: DispatchQueue) {
        guard let stdin else { return }
        queue.async { [input] in
            if let input, !input.isEmpty {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
            }
            try? stdin.fileHandleForWriting.close()
        }
    }

    private func scheduleTimeout(on queue: DispatchQueue) {
        guard let timeout, timeout > 0 else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.terminate(with: SubprocessSupport.ExecutionError.timedOut(timeout))
        }
        lock.withLock { timeoutWorkItem = workItem }
        queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func capture(_ data: Data, isStandardOutput: Bool) {
        guard !data.isEmpty else { return }
        lock.withLock {
            let remaining = max(0, outputLimit - capturedBytes)
            let accepted = min(remaining, data.count)
            if accepted > 0 {
                if isStandardOutput {
                    standardOutput.append(data.prefix(accepted))
                } else {
                    standardError.append(data.prefix(accepted))
                }
                capturedBytes += accepted
            }
            if accepted < data.count { wasTruncated = true }
        }
    }

    private func terminate(with error: Error) {
        let pid: pid_t? = lock.withLock {
            guard !hasFinished else { return nil }
            if terminalError == nil { terminalError = error }
            return process.isRunning ? process.processIdentifier : nil
        }
        guard let pid else {
            if !process.isRunning { finish(error: error) }
            return
        }

        if processGroupCreated {
            kill(-pid, SIGTERM)
        } else {
            kill(pid, SIGTERM)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.process.isRunning else { return }
            if self.processGroupCreated {
                kill(-pid, SIGKILL)
            } else {
                kill(pid, SIGKILL)
            }
        }
    }

    private func finish(exitCode: Int32) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        capture(stdout.fileHandleForReading.availableData, isStandardOutput: true)
        capture(stderr.fileHandleForReading.availableData, isStandardOutput: false)

        let completion: (CheckedContinuation<SubprocessSupport.Output, Error>, Error?, SubprocessSupport.Output)? = lock.withLock {
            guard !hasFinished, let continuation else { return nil }
            hasFinished = true
            self.continuation = nil
            timeoutWorkItem?.cancel()
            let output = SubprocessSupport.Output(
                standardOutput: String(decoding: standardOutput, as: UTF8.self),
                standardError: String(decoding: standardError, as: UTF8.self),
                exitCode: exitCode,
                wasTruncated: wasTruncated
            )
            return (continuation, terminalError, output)
        }
        guard let completion else { return }
        if let error = completion.1 {
            completion.0.resume(throwing: error)
        } else {
            completion.0.resume(returning: completion.2)
        }
    }

    private func finish(error: Error) {
        let continuation: CheckedContinuation<SubprocessSupport.Output, Error>? = lock.withLock {
            guard !hasFinished, let continuation = self.continuation else { return nil }
            hasFinished = true
            self.continuation = nil
            timeoutWorkItem?.cancel()
            return continuation
        }
        continuation?.resume(throwing: error)
    }

    private static func qos(from quality: QualityOfService) -> DispatchQoS.QoSClass {
        switch quality {
        case .userInteractive: .userInteractive
        case .userInitiated: .userInitiated
        case .utility: .utility
        case .background: .background
        default: .default
        }
    }
}
