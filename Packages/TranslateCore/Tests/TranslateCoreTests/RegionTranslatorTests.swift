import CoreGraphics
import Testing

@testable import TranslateCore

/// 받은 요청을 기록하고 정해 둔 번역을 돌려주는 가짜 엔진. 번역이 nil이면 로그인 안 됨 에러를 던진다.
private actor RecordingProvider: TranslationProvider {
    private(set) var requests: [TranslationRequest] = []
    private let translations: [String]?

    init(translations: [String]?) {
        self.translations = translations
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        guard let translations else { throw TranslationEngineError.notLoggedIn }
        return TranslationResult(segments: translations)
    }
}

struct RegionTranslatorTests {
    private let blocks = TextBlockGrouper.group([
        RecognizedLine(text: "Start free and", confidence: 1, boundingBox: CGRect(x: 0, y: 0, width: 400, height: 20)),
        RecognizedLine(text: "upgrade later.", confidence: 1, boundingBox: CGRect(x: 0, y: 26, width: 400, height: 20)),
        RecognizedLine(
            text: "Cancel anytime.", confidence: 1, boundingBox: CGRect(x: 0, y: 80, width: 400, height: 20)),
    ])

    @Test func sendsParagraphTextsWithTargetLanguageName() async throws {
        let provider = RecordingProvider(translations: ["무료로 시작하고 나중에 업그레이드하세요.", "언제든지 해지할 수 있습니다."])
        let translator = RegionTranslator(provider: provider)

        let translated = try await translator.translate(blocks, to: .korean)

        let requests = await provider.requests
        #expect(
            requests == [
                TranslationRequest(target: "Korean", segments: ["Start free and upgrade later.", "Cancel anytime."])
            ])
        #expect(translated.map(\.source) == blocks)
        #expect(translated.map(\.translation) == ["무료로 시작하고 나중에 업그레이드하세요.", "언제든지 해지할 수 있습니다."])
    }

    @Test func skipsEngineWhenThereIsNoText() async throws {
        let provider = RecordingProvider(translations: [])
        let translator = RegionTranslator(provider: provider)

        #expect(try await translator.translate([], to: .korean).isEmpty)
        #expect(await provider.requests.isEmpty)
    }

    private func line(_ text: String, y: CGFloat) -> RecognizedLine {
        RecognizedLine(text: text, confidence: 1, boundingBox: CGRect(x: 0, y: y, width: 400, height: 20))
    }

    @Test func sendsOnlyBlocksWithLettersAndPassesOthersThrough() async throws {
        let blocks = TextBlockGrouper.group([line("$19", y: 0), line("Cancel anytime.", y: 60), line("...", y: 120)])
        let provider = RecordingProvider(translations: ["언제든지 해지할 수 있습니다."])

        let translated = try await RegionTranslator(provider: provider).translate(blocks, to: .korean)

        #expect(await provider.requests.map(\.segments) == [["Cancel anytime."]])
        #expect(translated.map(\.translation) == ["$19", "언제든지 해지할 수 있습니다.", "..."])
    }

    @Test func skipsEngineWhenNothingNeedsTranslation() async throws {
        let blocks = TextBlockGrouper.group([line("$19", y: 0), line("120", y: 60)])
        let provider = RecordingProvider(translations: [])

        let translated = try await RegionTranslator(provider: provider).translate(blocks, to: .korean)

        #expect(await provider.requests.isEmpty)
        #expect(translated.map(\.translation) == ["$19", "120"])
    }

    @Test func propagatesEngineErrors() async {
        let translator = RegionTranslator(provider: RecordingProvider(translations: nil))

        await #expect(throws: TranslationEngineError.notLoggedIn) {
            try await translator.translate(blocks, to: .korean)
        }
    }

    @Test func rejectsTranslationsThatDoNotMatchParagraphs() async {
        let translator = RegionTranslator(provider: RecordingProvider(translations: ["하나만"]))

        await #expect(throws: TranslationPayloadError.segmentCountMismatch(expected: 2, actual: 1)) {
            try await translator.translate(blocks, to: .korean)
        }
    }

    @Test func recognizesImageIntoParagraphs() async throws {
        let image = try #require(
            TextImage.render([
                .init(text: "Start free and upgrade when your", x: 40, top: 40),
                .init(text: "team grows. Cancel anytime.", x: 40, top: 76),
            ]))
        let translator = RegionTranslator(provider: RecordingProvider(translations: []))

        let recognized = try await translator.recognize(image)

        #expect(recognized.map(\.text) == ["Start free and upgrade when your team grows. Cancel anytime."])
    }
}
