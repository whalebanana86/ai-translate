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
