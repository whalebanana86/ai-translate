import CryptoKit
import Foundation

public struct ModelDownloadProgress: Equatable, Sendable {
    public var completedBytes: Int64
    public var totalBytes: Int64

    public var fraction: Double {
        totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
    }
}

public enum ModelDownloadError: Error, Equatable, LocalizedError {
    case badStatus(file: String, status: Int)
    case sizeMismatch(file: String)
    case digestMismatch(file: String)

    public var errorDescription: String? {
        switch self {
        case .badStatus(let file, let status):
            "모델 파일(\(file))을 받지 못했습니다 (HTTP \(status))."
        case .sizeMismatch(let file), .digestMismatch(let file):
            "받은 모델 파일(\(file))이 공개된 파일과 다릅니다. 다시 받아 주세요."
        }
    }
}

/// 로컬 모델 파일을 받는다. 파일마다 크기·해시를 확인하고, 모두 맞으면 설치 위치로 옮긴다.
/// 실패하거나 취소되면 받던 파일을 지운다 (다음 받기는 처음부터).
public struct ModelDownloader: Sendable {
    public let store: ModelStore
    /// 테스트에서 가짜 서버(`URLProtocol`)를 넣는다
    let configuration: URLSessionConfiguration

    public init(store: ModelStore, configuration: URLSessionConfiguration = .default) {
        self.store = store
        self.configuration = configuration
    }

    public func download(
        _ model: LocalModel, progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws {
        let partial = store.partialDirectory(for: model)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: partial)
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            var completed: Int64 = 0
            for file in model.files {
                let destination = partial.appending(path: file.name)
                let base = completed
                try await FileDownload.run(
                    URLRequest(url: model.url(for: file)), to: destination, fileName: file.name,
                    configuration: configuration
                ) { written in
                    progress(ModelDownloadProgress(completedBytes: base + written, totalBytes: model.totalSize))
                }
                try Self.verify(destination, as: file)
                completed += file.size
                progress(ModelDownloadProgress(completedBytes: completed, totalBytes: model.totalSize))
            }
            let target = store.directory(for: model)
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: partial, to: target)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    static func verify(_ url: URL, as file: LocalModel.File) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        guard size == file.size else { throw ModelDownloadError.sizeMismatch(file: file.name) }
        guard try digest(of: url, size: file.size, kind: file.digest) == file.digest else {
            throw ModelDownloadError.digestMismatch(file: file.name)
        }
    }

    /// 큰 파일도 메모리에 다 올리지 않게 나눠 읽으며 해시를 계산한다
    static func digest(of url: URL, size: Int64, kind: LocalModel.File.Digest) throws -> LocalModel.File.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func feed(_ update: (Data) -> Void) throws {
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                update(chunk)
            }
        }
        switch kind {
        case .sha256:
            var hasher = SHA256()
            try feed { hasher.update(data: $0) }
            return .sha256(hex(hasher.finalize()))
        case .gitBlobSHA1:
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(size)\0".utf8))
            try feed { hasher.update(data: $0) }
            return .gitBlobSHA1(hex(hasher.finalize()))
        }
    }

    private static func hex(_ digest: some Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// 파일 하나를 받는다. 진행률을 받으려고 세션 대리자를 쓴다 (async `download(for:)`는 진행률을 알려주지 않는다).
private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let fileName: String
    private let onProgress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var failure: (any Error)?

    private init(destination: URL, fileName: String, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.fileName = fileName
        self.onProgress = onProgress
    }

    static func run(
        _ request: URLRequest, to destination: URL, fileName: String, configuration: URLSessionConfiguration,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let delegate = FileDownload(destination: destination, fileName: fileName, onProgress: onProgress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.lock.withLock { delegate.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 임시 파일은 이 호출이 끝나면 지워지므로 여기서 옮긴다
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            guard status == 200 else { throw ModelDownloadError.badStatus(file: fileName, status: status) }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, failure) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.failure)
        }
        if let error = error as? URLError, error.code == .cancelled {
            continuation?.resume(throwing: CancellationError())
        } else if let error = error ?? failure {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}
