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
    /// 문단 하나를 번역하는 시간 제한 (기본 `HyMTPrompt.timeLimit(for:)`)
    let timeLimit: @Sendable (String) -> Duration

    public init(generator: any TextGenerating) {
        self.init(generator: generator) { HyMTPrompt.timeLimit(for: $0) }
    }

    init(generator: any TextGenerating, timeLimit: @escaping @Sendable (String) -> Duration) {
        self.generator = generator
        self.timeLimit = timeLimit
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
            let output = try await Self.generate(within: timeLimit(segment)) { [generator] in
                try await generator.generate(
                    prompt: HyMTPrompt.prompt(for: segment, target: request.target, style: request.style),
                    maxTokens: HyMTPrompt.maxTokens(for: segment)
                ) { partial in
                    onPartial(index, HyMTPrompt.clean(partial))
                }
            }
            segments.append(HyMTPrompt.clean(output))
        }
        return TranslationResult(segments: segments)
    }

    /// `limit` 안에 생성이 끝나지 않으면 생성을 취소하고 `timedOut`을 던진다. 요청은 동시에 하나라 멈춘 생성이 뒤 문단을 막지 않게 한다
    /// (AGENTS.md 4장: 모든 엔진 호출에 시간 제한). 생성기는 취소되면 멈춰야 한다(MLX 생성은 토큰마다 취소를 확인한다)
    static func generate(
        within limit: Duration, _ operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: limit)
                throw TranslationEngineError.timedOut
            }
            defer { group.cancelAll() }
            guard let output = try await group.next() else { throw CancellationError() }
            return output
        }
    }
}

/// Hy-MT2 모델 카드의 번역 프롬프트와 채팅 형식.
public enum HyMTPrompt {
    static let begin = "<｜hy_begin▁of▁sentence｜>"
    static let user = "<｜hy_User｜>"
    static let assistant = "<｜hy_Assistant｜>"
    /// 채팅 형식에서 시스템 메시지 끝 (모델의 chat_template)
    static let systemEnd = "<｜hy_place▁holder▁no▁3｜>"

    /// `target`은 영어 언어 이름 (`TargetLanguage.promptName`). 문체(`style`)는 시스템 메시지로 준다: 번역 프롬프트에 지시를
    /// 더하면 짧은 글("Um", "No.")을 대화로 알아듣고 지시에 답하거나 지시를 번역해 내놓았다. 시스템 메시지로 주면 평서문 50개가
    /// 모두 합니다체였고 새어 나온 적이 없었다 (TASK-048 측정)
    public static func prompt(for text: String, target: String, style: String? = nil) -> String {
        begin + (style.map { $0 + systemEnd } ?? "") + user
            + "Translate the following text into \(target). Note that you "
            + "should only output the translated result without any additional explanation:\n\n" + neutralized(text)
            + assistant
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

    /// 문단 하나의 시간 제한. 정상 생성은 끊지 않도록 생성 길이 상한을 초당 10토큰으로 다 만드는 시간에 10초를 더한다
    /// (M5 측정 초당 101~112토큰. "OK" 16.4초, 긴 문단 2048토큰 214.8초). 멈춘 생성만 끊는다
    public static func timeLimit(for text: String) -> Duration {
        .seconds(10) + .milliseconds(100) * maxTokens(for: text)
    }

    /// 줄바꿈 앞에 마크다운식 공백 두 칸을 붙이는 버릇을 지운다
    public static func clean(_ output: String) -> String {
        output.replacingOccurrences(of: "  \n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LocalEngineError: Error, Equatable, LocalizedError {
    case modelNotInstalled
    case unsupportedMac

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            String(localized: "번역 모델을 아직 받지 않았습니다. 설정(⌘,)의 로컬 LLM에서 '모델 받기'를 누르세요.", bundle: .module)
        case .unsupportedMac:
            String(localized: "로컬 LLM은 Apple Silicon(M1 이상) Mac에서만 쓸 수 있습니다. 설정(⌘,)에서 다른 엔진을 고르세요.", bundle: .module)
        }
    }
}
