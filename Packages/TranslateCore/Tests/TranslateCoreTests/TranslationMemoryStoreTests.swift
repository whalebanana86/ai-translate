import Foundation
import Testing

@testable import TranslateCore

struct TranslationMemoryStoreTests {
    private let store = TranslationMemoryStore(
        root: FileManager.default.temporaryDirectory.appending(path: "TranslationMemoryStoreTests-\(UUID().uuidString)")
    )

    @Test func savesAndLoadsPerEngineKeepingOrder() throws {
        var memory = TranslationMemory()
        memory.store("무료로 시작하세요.", of: "Start free.", in: .korean)
        memory.store("無料で始める", of: "Start free.", in: .japanese)
        try store.save(memory, for: .local)

        let loaded = store.load(.local)

        #expect(loaded.entries == memory.entries)
        #expect(loaded.translation(of: "Start free.", in: .korean) == "무료로 시작하세요.")
        // 엔진마다 따로
        #expect(store.load(.claudeCode).entries.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.file(for: .local).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try store.removeAll()
    }

    @Test func keepsMemoryPerModelUsingOldFileForDefaultModel() throws {
        var memory = TranslationMemory()
        memory.store("무료로 시작하세요.", of: "Start free.", in: .korean)
        try store.save(memory, for: .claudeCode, model: "opus")

        // 기본 모델은 모델을 고르기 전 파일을 그대로 쓴다
        #expect(store.file(for: .claudeCode, model: "haiku") == store.file(for: .claudeCode))
        #expect(store.file(for: .codex, model: nil).lastPathComponent == "codex.json")
        #expect(store.file(for: .claudeCode, model: "opus").lastPathComponent == "claude-code-opus.json")
        #expect(store.file(for: .codex, model: "gpt-6.1-sol").lastPathComponent == "codex-gpt-6.1-sol.json")
        #expect(store.file(for: .codex, model: "../x").lastPathComponent == "codex-.._x.json")
        #expect(store.load(.claudeCode, model: "opus").entries == memory.entries)
        #expect(store.load(.claudeCode).entries.isEmpty)
        try store.removeAll()
    }

    @Test func keepsNewestEntriesWithinCapacity() {
        let entries = (0..<5).map { TranslationMemory.Entry(text: "t\($0)", language: .korean, translation: "번역\($0)") }

        let memory = TranslationMemory(capacity: 3, entries: entries)

        #expect(memory.entries.map(\.text) == ["t2", "t3", "t4"])
    }

    @Test func treatsCorruptedFileAsEmpty() throws {
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.file(for: .codex))

        #expect(store.load(.codex).entries.isEmpty)
        try store.removeAll()
    }

    @Test func removeAllDeletesFiles() throws {
        try store.save(TranslationMemory(), for: .local)

        try store.removeAll()

        #expect(!FileManager.default.fileExists(atPath: store.root.path))
    }
}
