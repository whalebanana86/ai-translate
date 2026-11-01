import Testing

@testable import TranslateCore

struct TranslationTranscriptTests {
    @Test func keepsTranslationsInOrderAndSkipsOnesAlreadyRecorded() {
        var transcript = TranslationTranscript()

        transcript.record(source: "Hello there.", translation: "안녕하세요.", in: .korean)
        transcript.record(source: "How are you?", translation: "잘 지내요?", in: .korean)
        // 같은 자막이 계속 보이거나 인식이 문장부호·대소문자만 다르게 읽어도 다시 기록하지 않는다
        let repeated = transcript.record(source: "hello there", translation: "안녕.", in: .korean)

        #expect(!repeated)
        #expect(transcript.entries.map(\.translation) == ["안녕하세요.", "잘 지내요?"])
        #expect(transcript.text == "안녕하세요.\n잘 지내요?")
    }

    @Test func replacesLastEntryWhileAutoCaptionGrows() {
        var transcript = TranslationTranscript()

        // 자동 생성 자막: 단어가 하나씩 붙는다 → 기록 하나를 고쳐 쓴다
        transcript.record(source: "So today we", translation: "그래서 오늘 우리는", in: .korean)
        transcript.record(source: "So today we are going", translation: "그래서 오늘 우리는 갈 거예요", in: .korean)
        // 앞부분만 다시 보이면(인식이 늦게 따라옴) 넘긴다
        let shorter = transcript.record(source: "So today", translation: "그래서 오늘", in: .korean)

        #expect(!shorter)
        #expect(transcript.entries.count == 1)
        #expect(transcript.entries[0].source == "So today we are going")
        #expect(transcript.entries[0].translation == "그래서 오늘 우리는 갈 거예요")
    }

    @Test func recordsSameSourceAgainForAnotherLanguage() {
        var transcript = TranslationTranscript()

        transcript.record(source: "Hello there.", translation: "안녕하세요.", in: .korean)
        let japanese = transcript.record(source: "Hello there.", translation: "こんにちは。", in: .japanese)

        #expect(japanese)
        #expect(transcript.entries.count == 2)
    }

    @Test func skipsTextWithoutLettersAndDropsOldestBeyondCapacity() {
        var transcript = TranslationTranscript()

        let symbols = transcript.record(source: "...", translation: "...", in: .korean)
        for index in 0...TranslationTranscript.capacity {
            transcript.record(source: "Line \(index) ends", translation: "줄 \(index)", in: .korean)
        }

        #expect(!symbols)
        #expect(transcript.entries.count == TranslationTranscript.capacity)
        #expect(transcript.entries.first?.translation == "줄 1")
        // 지운 기록의 원문은 다시 기록할 수 있다
        let again = transcript.record(source: "Line 0 ends", translation: "줄 0", in: .korean)
        #expect(again)
    }
}
