import Foundation

/// 번역 엔진 에러. 사용자에게 무엇을 하면 되는지 안내할 수 있는 단위로 나눈다.
public enum TranslationEngineError: Error, Equatable, Sendable {
    /// CLI 실행 파일을 찾거나 시작할 수 없음
    case executableNotFound(name: String)
    case timedOut
    case notLoggedIn
    case usageLimitReached
    /// 그 밖에 엔진이 보고한 에러. 메시지는 엔진 출력의 앞부분만 담는다
    case engineFailed(message: String)
    /// 엔진 응답 형식이 예상과 다름
    case invalidOutput

    /// 엔진 에러 메시지를 안내 가능한 종류로 분류한다.
    static func classify(_ message: String) -> TranslationEngineError {
        let lowered = message.lowercased()
        let loginHints = ["not logged in", "/login", "codex login", "invalid api key", "authentication", "oauth token"]
        let limitHints = ["usage limit", "hit your limit", "limit reached", "rate limit", "rate_limit"]
        if loginHints.contains(where: { lowered.contains($0) }) {
            return .notLoggedIn
        }
        if limitHints.contains(where: { lowered.contains($0) }) {
            return .usageLimitReached
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return .engineFailed(message: String(trimmed.prefix(300)))
    }
}

extension TranslationEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "\(name) CLI를 찾을 수 없습니다. 설치 여부와 설정의 CLI 경로를 확인하세요."
        case .timedOut:
            "번역 시간이 초과됐습니다. 다시 시도하세요."
        case .notLoggedIn:
            "번역 엔진에 로그인되어 있지 않습니다. 터미널에서 로그인한 뒤 다시 시도하세요."
        case .usageLimitReached:
            "번역 엔진 사용량 한도에 도달했습니다. 잠시 후 다시 시도하세요."
        case .engineFailed(let message):
            "번역 엔진 오류: \(message)"
        case .invalidOutput:
            "번역 엔진의 응답을 해석할 수 없습니다."
        }
    }
}
