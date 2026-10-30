import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import TranslateCore

struct ModelDownloaderTests {
    private let store = ModelStore(
        root: FileManager.default.temporaryDirectory.appending(path: "ModelDownloaderTests-\(UUID().uuidString)"))

    /// 가짜 모델: 작은 파일(git 블롭 SHA-1)과 큰 파일 역할(SHA-256) 하나씩
    private func model(_ name: String, files: [String: Data]) -> LocalModel {
        LocalModel(
            id: "test-\(name)", displayName: "Test", repository: "test/\(name)-\(UUID().uuidString)", revision: "abc",
            files: files.sorted { $0.key < $1.key }.map { fileName, data in
                let digest: LocalModel.File.Digest =
                    fileName.hasSuffix(".safetensors")
                    ? .sha256(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
                    : .gitBlobSHA1(
                        Insecure.SHA1.hash(data: Data("blob \(data.count)\0".utf8) + data)
                            .map { String(format: "%02x", $0) }.joined())
                return LocalModel.File(name: fileName, size: Int64(data.count), digest: digest)
            })
    }

    private func serve(_ model: LocalModel, _ files: [String: Data]) {
        for file in model.files {
            StubURLProtocol.register(model.url(for: file), body: files[file.name]!)
        }
    }

    @Test func downloadsVerifiesAndInstalls() async throws {
        let files = ["config.json": Data("{\"a\":1}".utf8), "model.safetensors": Data(repeating: 7, count: 300_000)]
        let model = model("ok", files: files)
        serve(model, files)
        let reports = Mutex<[ModelDownloadProgress]>([])

        try await ModelDownloader(store: store, configuration: StubURLProtocol.configuration).download(model) {
            progress in reports.withLock { $0.append(progress) }
        }

        #expect(store.isInstalled(model))
        #expect(
            try Data(contentsOf: store.directory(for: model).appending(path: "config.json")) == files["config.json"])
        #expect(!FileManager.default.fileExists(atPath: store.partialDirectory(for: model).path))
        let fractions = reports.withLock { $0.map(\.fraction) }
        #expect(fractions.last == 1)
        #expect(fractions == fractions.sorted())
        try store.remove(model)
    }

    @Test func rejectsTamperedFileAndCleansUp() async throws {
        let files = ["config.json": Data("{\"a\":1}".utf8), "model.safetensors": Data(repeating: 7, count: 1000)]
        let model = model("tampered", files: files)
        var tampered = files
        tampered["model.safetensors"] = Data(repeating: 8, count: 1000)
        serve(model, tampered)

        await #expect(throws: ModelDownloadError.digestMismatch(file: "model.safetensors")) {
            try await ModelDownloader(store: store, configuration: StubURLProtocol.configuration).download(model)
        }
        #expect(!store.isInstalled(model))
        #expect(!FileManager.default.fileExists(atPath: store.partialDirectory(for: model).path))
    }

    @Test func reportsHTTPErrors() async throws {
        let model = model("missing", files: ["config.json": Data("{}".utf8)])
        // 등록하지 않은 URL은 404

        await #expect(throws: ModelDownloadError.badStatus(file: "config.json", status: 404)) {
            try await ModelDownloader(store: store, configuration: StubURLProtocol.configuration).download(model)
        }
        #expect(!store.isInstalled(model))
    }

    @Test func removeUninstalls() async throws {
        let files = ["config.json": Data("{}".utf8)]
        let model = model("remove", files: files)
        serve(model, files)
        try await ModelDownloader(store: store, configuration: StubURLProtocol.configuration).download(model)

        try store.remove(model)

        #expect(!store.isInstalled(model))
        #expect(!FileManager.default.fileExists(atPath: store.directory(for: model).path))
    }

    @Test func pinsHyMT2Files() {
        let model = LocalModel.hyMT2

        #expect(model.files.map(\.name).contains("model.safetensors"))
        #expect(model.totalSize > 1_000_000_000)
        #expect(
            model.url(for: model.files[0]).absoluteString
                == "https://huggingface.co/mlx-community/Hy-MT2-1.8B-4bit/resolve/"
                + "e5c6fe56c7b3bc77fae5ae92db31f2178f1e6912/LICENSE.txt")
    }
}
