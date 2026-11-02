import CoreGraphics
import Testing

@testable import TranslateCore

struct TranslationMemoryTests {
    private func block(_ text: String) -> TextBlock {
        TextBlockGrouper.group([
            RecognizedLine(text: text, confidence: 1, boundingBox: CGRect(x: 0, y: 0, width: 400, height: 20))
        ])[0]
    }

    @Test func missingReturnsOnlyNewTranslatableTextsOnce() {
        var memory = TranslationMemory()
        memory.store("무료로 시작하세요.", of: "Start free.", in: .korean)
        let blocks = [block("Start free."), block("$19"), block("Cancel anytime."), block("Cancel anytime.")]

        #expect(memory.missing(in: blocks, for: .korean).map(\.text) == ["Cancel anytime."])
        #expect(memory.missing(in: blocks, for: .japanese).map(\.text) == ["Start free.", "Cancel anytime."])
    }

    @Test func contentIsTranslationOriginalOrPending() {
        var memory = TranslationMemory()
        memory.store("무료로 시작하세요.", of: "Start free.", in: .korean)

        #expect(memory.content(of: block("Start free."), in: .korean) == .translated("무료로 시작하세요."))
        #expect(memory.content(of: block("$19"), in: .korean) == .original("$19"))
        #expect(memory.content(of: block("Cancel anytime."), in: .korean) == .pending)
        #expect(memory.content(of: block("Start free."), in: .english) == .pending)
    }

    @Test func doesNotTranslateTextAlreadyInTargetLanguage() {
        let blocks = [block("답글 4개"), block("Cancel anytime.")]
        let memory = TranslationMemory()

        #expect(memory.missing(in: blocks, for: .korean).map(\.text) == ["Cancel anytime."])
        #expect(memory.content(of: block("답글 4개"), in: .korean) == .original("답글 4개"))
        // 다른 언어로는 번역한다
        #expect(memory.missing(in: blocks, for: .english).map(\.text) == ["답글 4개"])
    }

    @Test func hidesOriginalWhileTranslatingAndAfter() {
        #expect(BlockContent.translated("번역").hidesOriginal(canTranslate: true))
        #expect(BlockContent.pending.hidesOriginal(canTranslate: true))
        #expect(!BlockContent.original("$19").hidesOriginal(canTranslate: true))
        // 엔진이 실패하면 기다려도 번역이 오지 않으므로 원문을 보인다
        #expect(!BlockContent.pending.hidesOriginal(canTranslate: false))
        #expect(BlockContent.translated("번역").hidesOriginal(canTranslate: false))
    }

    @Test func forgetsOldestBeyondCapacity() {
        var memory = TranslationMemory(capacity: 2)
        memory.store("가", of: "a", in: .korean)
        memory.store("나", of: "b", in: .korean)
        memory.store("가2", of: "a", in: .korean)
        memory.store("다", of: "c", in: .korean)

        #expect(memory.translation(of: "a", in: .korean) == nil)
        #expect(memory.translation(of: "b", in: .korean) == "나")
        #expect(memory.translation(of: "c", in: .korean) == "다")
    }
}
