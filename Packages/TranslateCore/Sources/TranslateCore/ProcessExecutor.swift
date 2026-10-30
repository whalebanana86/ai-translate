import Foundation

/// 외부 프로세스 실행 결과.
struct ProcessOutput: Sendable {
    var exitStatus: Int32
    var stdout: Data
    var stderr: Data
    var timedOut: Bool
}

enum ProcessExecutor {
    /// 프로세스를 실행하고 종료까지 기다린다.
    ///
    /// 시간 제한을 넘기거나 호출한 Task가 취소되면 프로세스를 종료한다 (SIGTERM, 2초 뒤에도 살아 있으면 SIGKILL).
    /// 실행 파일을 시작하지 못하면 에러를 던진다.
    static func run(
        _ executable: URL,
        arguments: [String],
        input: Data = Data(),
        workingDirectory: URL? = nil,
        timeout: Duration
    ) async throws -> ProcessOutput {
        let job = ProcessJob(executable: executable, arguments: arguments, workingDirectory: workingDirectory)
        try job.start(input: input, timeout: timeout)
        return await withTaskCancellationHandler {
            await job.waitForExit()
        } onCancel: {
            job.terminate(timedOut: false)
        }
    }
}

/// Process는 Sendable이 아니므로 여러 스레드에서 접근하는 상태를 lock으로 보호한다.
private final class ProcessJob: @unchecked Sendable {
    private let process = Process()
    private let exited = DispatchGroup()
    private let drained = DispatchGroup()
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var timedOut = false

    init(executable: URL, arguments: [String], workingDirectory: URL?) {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
    }

    func start(input: Data, timeout: Duration) throws {
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        exited.enter()
        process.terminationHandler = { [exited] _ in exited.leave() }
        try process.run()

        // 출력은 따로 읽어야 파이프 버퍼(64KB)가 차서 자식과 서로 기다리는 일이 없다
        collect(stdoutPipe.fileHandleForReading, isStdout: true)
        collect(stderrPipe.fileHandleForReading, isStdout: false)

        // 자식이 입력을 다 읽기 전에 종료해도 SIGPIPE로 앱이 죽지 않게 한다
        let writer = stdinPipe.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global().async {
            try? writer.write(contentsOf: input)
            try? writer.close()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
            self?.terminate(timedOut: true)
        }
    }

    func terminate(timedOut: Bool) {
        let pid: Int32? = lock.withLock {
            guard process.isRunning else { return nil }
            if timedOut {
                self.timedOut = true
            }
            process.terminate()
            return process.processIdentifier
        }
        guard let pid else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    func waitForExit() async -> ProcessOutput {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exited.notify(queue: .global()) { continuation.resume() }
        }
        // 손자 프로세스가 파이프를 쥐고 있으면 EOF가 오지 않으므로 출력 수집은 잠깐만 더 기다린다
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async { [drained] in
                _ = drained.wait(timeout: .now() + 2)
                continuation.resume()
            }
        }
        return lock.withLock {
            ProcessOutput(exitStatus: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: timedOut)
        }
    }

    private func collect(_ handle: FileHandle, isStdout: Bool) {
        drained.enter()
        DispatchQueue.global().async {
            let data = (try? handle.readToEnd()) ?? Data()
            self.lock.withLock {
                if isStdout {
                    self.stdout = data
                } else {
                    self.stderr = data
                }
            }
            self.drained.leave()
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
