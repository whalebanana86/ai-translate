/// 번역 엔진 공통 인터페이스.
///
/// UI와 다른 로직은 구체 엔진(Claude Code CLI, Codex CLI, API 키 엔진 등)이 아니라 이 프로토콜에만 의존한다.
public protocol TranslationProvider: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    /// 한 번에 보낼 문단 수. nil이면 모두 한 번에 (CLI 엔진은 실행 비용이 커서 묶어 보낸다)
    var preferredBatchSize: Int? { get }
}

extension TranslationProvider {
    public var preferredBatchSize: Int? { nil }
}
