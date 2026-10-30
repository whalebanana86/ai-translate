import Foundation

/// 기기에서 글을 생성하는 모델 (앱에서는 MLX). `prompt`는 모델 형식(특수 토큰 포함)에 맞춘 전체 문자열이다.
public protocol TextGenerating: Sendable {
    /// `onPartial`에는 지금까지 생성한 글 전체를 넘긴다
    func generate(prompt: String, maxTokens: Int, onPartial: @escaping @Sendable (String) -> Void) async throws
        -> String
}

extension TextGenerating {
    public func generate(prompt: String, maxTokens: Int) async throws -> String {
        try await generate(prompt: prompt, maxTokens: maxTokens) { _ in }
    }
}

/// 번역 전용 로컬 모델(Hy-MT2)로 문단을 하나씩 번역한다. 번역 전용 모델은 글 하나를 번역하도록 학습되어
/// JSON으로 묶어 보내지 않는다.
public struct LocalTranslationProvider: TranslationProvider {
    public let generator: any TextGenerating

    public init(generator: any TextGenerating) {
        self.generator = generator
    }

    /// 한 문단씩 보내 렌즈가 번역되는 대로 보여주게 한다
    public var preferredBatchSize: Int? { 1 }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await translate(request) { _, _ in }
    }

    public func translate(_ request: TranslationRequest, onPartial: @escaping @Sendable (Int, String) -> Void)
        async throws -> TranslationResult
    {
        var segments: [String] = []
        for (index, segment) in request.segments.enumerated() {
            try Task.checkCancellation()
            let output = try await generator.generate(
                prompt: HyMTPrompt.prompt(for: segment, target: request.target),
                maxTokens: HyMTPrompt.maxTokens(for: segment)
            ) { partial in
                onPartial(index, HyMTPrompt.clean(partial))
            }
            segments.append(HyMTPrompt.clean(output))
        }
        return TranslationResult(segments: segments)
    }
}

/// Hy-MT2 모델 카드의 번역 프롬프트와 채팅 형식.
public enum HyMTPrompt {
    static let begin = "<｜hy_begin▁of▁sentence｜>"
    static let user = "<｜hy_User｜>"
    static let assistant = "<｜hy_Assistant｜>"

    /// `target`은 영어 언어 이름 (`TargetLanguage.promptName`)
    public static func prompt(for text: String, target: String) -> String {
        begin + user + "Translate the following text into \(target). Note that you should only output the translated "
            + "result without any additional explanation:\n\n" + neutralized(text) + assistant
    }

    /// 페이지 글에 이 모델의 특수 토큰 문자열(`<｜hy_…｜>`)이 있으면 토크나이저가 진짜 특수 토큰으로 읽어 대화 형식을
    /// 바꿀 수 있다. 전각 세로줄(｜)을 보통 세로줄(|)로 바꿔 평범한 글자로 만든다
    static func neutralized(_ text: String) -> String {
        guard text.contains("<｜") else { return text }
        return text.replacing(#/<｜[^｜>]*｜>/#) { match in
            match.output.replacingOccurrences(of: "｜", with: "|")
        }
    }

    /// 번역이 원문보다 아주 길어지는 일은 없으므로 넉넉하게 잡고, 멈추지 않는 생성을 막는다
    public static func maxTokens(for text: String) -> Int {
        min(2048, max(64, text.count * 3))
    }

    /// 줄바꿈 앞에 마크다운식 공백 두 칸을 붙이는 버릇을 지운다
    public static func clean(_ output: String) -> String {
        output.replacingOccurrences(of: "  \n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalEngineError: Error, Equatable, LocalizedError {
    case modelNotInstalled

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "번역 모델을 아직 받지 않았습니다. 설정(⌘,)의 로컬 LLM에서 '모델 받기'를 누르세요."
        }
    }
}
