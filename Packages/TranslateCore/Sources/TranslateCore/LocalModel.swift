import Foundation

/// 기기에서 실행하는 번역 모델. 받을 파일과 확인할 해시를 리비전째 고정해, 받은 파일이 공개된 것과 같은지 확인한다.
public struct LocalModel: Identifiable, Equatable, Sendable {
    public struct File: Equatable, Sendable {
        /// Hugging Face가 공개하는 해시. LFS 파일은 SHA-256, 그 밖은 git 블롭 SHA-1
        public enum Digest: Equatable, Sendable {
            case sha256(String)
            case gitBlobSHA1(String)
        }

        public var name: String
        public var size: Int64
        public var digest: Digest

        public init(name: String, size: Int64, digest: Digest) {
            self.name = name
            self.size = size
            self.digest = digest
        }
    }

    public var id: String
    public var displayName: String
    /// Hugging Face 저장소 (`조직/이름`)
    public var repository: String
    public var revision: String
    public var files: [File]

    public init(id: String, displayName: String, repository: String, revision: String, files: [File]) {
        self.id = id
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.files = files
    }

    public var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    public func url(for file: File) -> URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.name)")!
    }

    /// Tencent Hy-MT2 1.8B의 MLX 4비트 변환판 (Apache-2.0). 받을 때 쓰는 파일만 고른다 (설명서·이미지 제외)
    public static let hyMT2 = LocalModel(
        id: "hy-mt2-1.8b-4bit",
        displayName: "Hy-MT2 1.8B",
        repository: "mlx-community/Hy-MT2-1.8B-4bit",
        revision: "e5c6fe56c7b3bc77fae5ae92db31f2178f1e6912",
        files: [
            File(name: "LICENSE.txt", size: 11629, digest: .gitBlobSHA1("360c110713e627c7dc239ce547ae466a734b30d7")),
            File(
                name: "chat_template.jinja", size: 654,
                digest: .gitBlobSHA1("11f06996e3fdef5fc75a350af36dc9862e34cbde")),
            File(name: "config.json", size: 1688, digest: .gitBlobSHA1("5b7ad52309baff705d9a473ebfad419f96c819e0")),
            File(
                name: "generation_config.json", size: 221,
                digest: .gitBlobSHA1("791446b3a90e4fbfe804053cdef60dd8d3f0fd06")),
            File(
                name: "model.safetensors.index.json", size: 57380,
                digest: .gitBlobSHA1("c2689fc5a6705e470f129aa8e8fd8321d5aef3a5")),
            File(
                name: "tokenizer.json", size: 9_527_287,
                digest: .gitBlobSHA1("bc8fca20a7f6dbb3c6a6d9e814c6efc999ec80fe")),
            File(
                name: "tokenizer_config.json", size: 359,
                digest: .gitBlobSHA1("901bbaf491820cabebc5d6c840489f18fbf89feb")),
            File(
                name: "model.safetensors", size: 1_007_776_125,
                digest: .sha256("a9cecbc77050b86b2fa3df3a8941d34ed3585cdbcce07bd64b3da289d50537c6")),
        ])
}
