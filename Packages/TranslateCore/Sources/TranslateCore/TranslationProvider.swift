/// 번역 엔진 공통 인터페이스.
///
/// UI와 다른 로직은 구체 엔진(Claude Code CLI, Codex CLI, API 키 엔진 등)이 아니라 이 프로토콜에만 의존한다.
public protocol TranslationProvider: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}
