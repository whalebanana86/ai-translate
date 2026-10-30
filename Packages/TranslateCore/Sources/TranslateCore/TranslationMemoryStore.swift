import Foundation

/// 번역 기억을 엔진별 파일로 저장한다. 같은 페이지를 다시 볼 때 바로 보여주기 위해서다.
///
/// 원문·번역 글이 기기 안에 남으므로 본인만 읽을 수 있게(0600) 저장하고, 설정에서 지울 수 있게 한다 (AGENTS.md 개인정보).
public struct TranslationMemoryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/AITranslate/TranslationMemory`
    public static var standard: TranslationMemoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TranslationMemoryStore(
            root: support.appending(path: "AITranslate/TranslationMemory", directoryHint: .isDirectory))
    }

    func file(for engine: TranslationEngine) -> URL {
        root.appending(path: "\(engine.rawValue).json")
    }

    /// 없거나 읽을 수 없으면 빈 기억
    public func load(_ engine: TranslationEngine) -> TranslationMemory {
        guard
            let data = try? Data(contentsOf: file(for: engine)),
            let entries = try? JSONDecoder().decode([TranslationMemory.Entry].self, from: data)
        else { return TranslationMemory() }
        return TranslationMemory(entries: entries)
    }

    public func save(_ memory: TranslationMemory, for engine: TranslationEngine) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = file(for: engine)
        try JSONEncoder().encode(memory.entries).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}
