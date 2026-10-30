import CoreGraphics

/// 번역된 문단.
public struct TranslatedBlock: Equatable, Sendable {
    public var source: TextBlock
    public var translation: String

    public init(source: TextBlock, translation: String) {
        self.source = source
        self.translation = translation
    }
}

/// 캡처 이미지 → 문단 → 번역.
///
/// 원문을 먼저 보여주고, 대상 언어를 바꾸면 OCR 없이 다시 번역할 수 있도록 두 단계로 나눈다.
public struct RegionTranslator: Sendable {
    public var recognizer: TextRecognizer
    public var provider: any TranslationProvider

    public init(recognizer: TextRecognizer = TextRecognizer(), provider: any TranslationProvider) {
        self.recognizer = recognizer
        self.provider = provider
    }

    public func recognize(_ image: CGImage) async throws -> [TextBlock] {
        TextBlockGrouper.group(try await recognizer.recognize(image))
    }

    /// 문단을 번역한다. 번역할 글자가 없는 문단(숫자·기호·버튼)은 엔진에 보내지 않고 원문을 그대로 쓴다.
    /// 번역할 문단이 하나도 없으면 엔진을 부르지 않는다.
    public func translate(_ blocks: [TextBlock], to language: TargetLanguage) async throws -> [TranslatedBlock] {
        let translatable = blocks.filter(\.isTranslatable)
        guard !translatable.isEmpty else {
            return blocks.map { TranslatedBlock(source: $0, translation: $0.text) }
        }
        let request = TranslationRequest(target: language.promptName, segments: translatable.map(\.text))
        let result = try TranslationPayload.validate(try await provider.translate(request), for: request)
        var translations = result.segments.makeIterator()
        return blocks.map { block in
            let translation = block.isTranslatable ? translations.next() : nil
            return TranslatedBlock(source: block, translation: translation ?? block.text)
        }
    }
}
