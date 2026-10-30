/// 번역 엔진 공통 인터페이스.
///
/// UI와 다른 로직은 구체 엔진(Claude Code CLI, Codex CLI, API 키 엔진 등)이 아니라 이 프로토콜에만 의존한다.
public protocol TranslationProvider: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
    /// 번역하면서 (문단 번호, 지금까지 나온 번역)을 알린다. 생성되는 대로 보여줄 수 있는 엔진(로컬)만 구현한다
    func translate(_ request: TranslationRequest, onPartial: @escaping @Sendable (Int, String) -> Void) async throws
        -> TranslationResult
    /// 한 번에 보낼 문단 수. nil이면 모두 한 번에 (CLI 엔진은 실행 비용이 커서 묶어 보낸다)
    var preferredBatchSize: Int? { get }
    /// 새 화면(보이는 번역이 없을 때) 첫 요청의 문단 수. 위쪽 문단을 먼저 보여준다. nil이면 나누지 않는다
    var firstBatchSize: Int? { get }
}

extension TranslationProvider {
    public func translate(_ request: TranslationRequest, onPartial: @escaping @Sendable (Int, String) -> Void)
        async throws -> TranslationResult
    {
        try await translate(request)
    }

    public var preferredBatchSize: Int? { nil }
    public var firstBatchSize: Int? { nil }
}
