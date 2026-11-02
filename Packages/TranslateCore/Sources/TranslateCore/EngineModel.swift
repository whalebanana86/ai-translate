import Foundation

/// CLI 엔진에서 고를 수 있는 모델 (TASK-053)
public struct EngineModel: Equatable, Hashable, Sendable, Identifiable {
    /// CLI에 넘기는 이름 (Claude Code 별칭, Codex 모델 이름)
    public var id: String
    public var displayName: String
    public var summary: String

    public init(id: String, displayName: String, summary: String) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
    }
}

extension ClaudeCodeProvider {
    /// Claude Code가 그때의 최신 모델로 바꿔 주는 별칭 (`claude --help`: "an alias for the latest model"). 지금은 Haiku 5.5,
    /// Sonnet 5.5, Opus 5.5, Fable 5.1. 아래로 갈수록 정확하지만 느리고 요금제 사용량이 많다
    public static let models: [EngineModel] = [
        EngineModel(id: "haiku", displayName: "Haiku", summary: "가장 빠르고 사용량이 적습니다 (기본)"),
        EngineModel(id: "sonnet", displayName: "Sonnet", summary: "품질과 속도의 균형"),
        EngineModel(id: "opus", displayName: "Opus", summary: "더 정확하지만 느리고 사용량이 많습니다"),
        EngineModel(id: "fable", displayName: "Fable", summary: "가장 뛰어나지만 가장 느리고 사용량이 가장 많습니다"),
    ]

    /// 모델별 시간 제한. Haiku는 측정(문단 28개 21초)으로 60초, 나머지는 측정하지 않았지만 더 느리므로 넉넉하게 둔다
    public static func timeout(for model: String) -> Duration {
        model == defaultModel ? defaultTimeout : .seconds(180)
    }
}

/// Codex가 받아 두는 모델 목록(`~/.codex/models_cache.json`). 고를 수 있는 모델은 계정·버전마다 달라 앱에 고정하지 않는다.
/// 파일이 없거나 형식이 바뀌어 읽지 못하면 빈 목록이다 (그때는 Codex 기본 모델만 고를 수 있다)
public enum CodexModelCatalog {
    public static var cacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/models_cache.json")
    }

    private struct Cache: Decodable {
        struct Model: Decodable {
            var slug: String
            var displayName: String?
            var description: String?
            var visibility: String?
            var priority: Int?

            enum CodingKeys: String, CodingKey {
                case slug, description, visibility, priority
                case displayName = "display_name"
            }
        }
        var models: [Model]
    }

    /// 목록에 보이는 모델(visibility "list")만 Codex 우선순위 순서로
    public static func models(fromCache data: Data) -> [EngineModel] {
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }
        return
            cache.models
            .filter { $0.visibility == "list" }
            .sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            .map { EngineModel(id: $0.slug, displayName: $0.displayName ?? $0.slug, summary: $0.description ?? "") }
    }

    public static func load(from file: URL = cacheFile) -> [EngineModel] {
        (try? Data(contentsOf: file)).map(models(fromCache:)) ?? []
    }
}
