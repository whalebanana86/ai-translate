import Foundation

/// 번역 기억을 엔진·모델별 파일로 저장한다. 같은 페이지를 다시 볼 때 바로 보여주기 위해서다.
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

    /// 엔진의 기본 모델(Claude Haiku, Codex 기본값)은 모델을 고르기 전과 같은 `<엔진>.json`, 다른 모델은 `<엔진>-<모델>.json`.
    /// 모델을 바꾸면 전 모델의 번역이 그대로 나오지 않게 따로 둔다 (TASK-053)
    func file(for engine: TranslationEngine, model: String? = nil) -> URL {
        let isDefault = model == nil || (engine == .claudeCode && model == ClaudeCodeProvider.defaultModel)
        guard let model, !isDefault else { return root.appending(path: "\(engine.rawValue).json") }
        let safe = String(model.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return root.appending(path: "\(engine.rawValue)-\(safe).json")
    }

    /// 없거나 읽을 수 없으면 빈 기억
    public func load(_ engine: TranslationEngine, model: String? = nil) -> TranslationMemory {
        guard
            let data = try? Data(contentsOf: file(for: engine, model: model)),
            let entries = try? JSONDecoder().decode([TranslationMemory.Entry].self, from: data)
        else { return TranslationMemory() }
        return TranslationMemory(entries: entries)
    }

    public func save(_ memory: TranslationMemory, for engine: TranslationEngine, model: String? = nil) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = file(for: engine, model: model)
        try JSONEncoder().encode(memory.entries).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func removeAll() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}
