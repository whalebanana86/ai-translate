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
        try await translate(blocks, to: language) { _, _ in }
    }

    /// 생성되는 대로 보여줄 수 있는 엔진이면 (원문 문단, 지금까지 나온 번역)을 알린다
    public func translate(
        _ blocks: [TextBlock], to language: TargetLanguage,
        onPartial: @escaping @Sendable (TextBlock, String) -> Void
    ) async throws -> [TranslatedBlock] {
        let translatable = blocks.filter(\.isTranslatable)
        guard !translatable.isEmpty else {
            return blocks.map { TranslatedBlock(source: $0, translation: $0.text) }
        }
        let request = TranslationRequest(target: language.promptName, segments: translatable.map(\.text))
        let response = try await provider.translate(request) { index, partial in
            guard translatable.indices.contains(index) else { return }
            onPartial(translatable[index], partial)
        }
        let result = try TranslationPayload.validate(response, for: request)
        var translations = result.segments.makeIterator()
        return blocks.map { block in
            let translation = block.isTranslatable ? translations.next() : nil
            return TranslatedBlock(source: block, translation: translation ?? block.text)
        }
    }
}
