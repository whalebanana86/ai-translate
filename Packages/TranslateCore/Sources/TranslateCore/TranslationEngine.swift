/// 사용자가 고르는 번역 엔진. 처음 실행 때와 설정에서 고른다.
public enum TranslationEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case local

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .local: "로컬 LLM (Hy-MT2)"
        }
    }

    public var summary: String {
        switch self {
        case .claudeCode:
            "이 Mac에 설치된 Claude Code(haiku)로 번역합니다. 품질이 가장 좋고 한 번에 3~6초 걸립니다. "
                + "Claude 요금제 사용량이 쓰입니다."
        case .codex:
            "이 Mac에 설치된 Codex CLI로 번역합니다. 한 번에 7~9초 걸리고 ChatGPT 요금제 사용량이 쓰입니다."
        case .local:
            "이 Mac 안에서 번역합니다. 가장 빠르고(문단당 0.1~1초) 글이 밖으로 나가지 않습니다. "
                + "번역 모델(약 1GB)을 받아야 합니다."
        }
    }

    /// 선택 영역에서 인식한 글이 기기 밖 번역 서비스로 나가는 곳. 로컬 엔진은 nil
    public var transmissionDestination: String? {
        switch self {
        case .claudeCode: "Claude Code를 통해 Anthropic"
        case .codex: "Codex CLI를 통해 OpenAI"
        case .local: nil
        }
    }

    /// CLI로 실행하는 엔진의 실행 파일 이름
    public var executableName: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .local: nil
        }
    }

    /// CLI 실행 파일을 찾는 알려진 위치
    public var knownLocations: [String] {
        switch self {
        case .claudeCode: CLILocator.claudeKnownLocations
        case .codex: CLILocator.codexKnownLocations
        case .local: []
        }
    }

    /// 이 Mac에서 쓸 수 있는지. 로컬 엔진(MLX)은 Apple Silicon(M1 이상)에서만 돈다
    public func isSupported(onAppleSilicon: Bool) -> Bool {
        self != .local || onAppleSilicon
    }
}
