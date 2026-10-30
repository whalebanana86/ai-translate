import Foundation

/// 받은 로컬 모델의 위치와 설치 상태. 받는 중에는 `<id>.partial`에 받고, 모두 확인되면 `<id>`로 옮긴다.
public struct ModelStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/AITranslate/Models`
    public static var standard: ModelStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModelStore(root: support.appending(path: "AITranslate/Models", directoryHint: .isDirectory))
    }

    public func directory(for model: LocalModel) -> URL {
        root.appending(path: model.id, directoryHint: .isDirectory)
    }

    func partialDirectory(for model: LocalModel) -> URL {
        root.appending(path: model.id + ".partial", directoryHint: .isDirectory)
    }

    /// 모든 파일이 정해진 크기로 있으면 설치된 것으로 본다. 해시는 받을 때 확인했으므로 여기서는 다시 읽지 않는다 (1GB)
    public func isInstalled(_ model: LocalModel) -> Bool {
        let directory = directory(for: model)
        return model.files.allSatisfy { file in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appending(path: file.name).path)
            return (attributes?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    /// 받은 모델과 받다 만 파일을 지운다
    public func remove(_ model: LocalModel) throws {
        for directory in [directory(for: model), partialDirectory(for: model)]
        where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
