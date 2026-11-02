import Foundation

/// 번역 엔진에 표준 입력으로 보내는 요청.
///
/// 캡처한 텍스트는 신뢰할 수 없는 입력이므로 일반 텍스트가 아니라 항상 이 JSON 형태로 감싸서 보낸다.
public struct TranslationRequest: Codable, Equatable, Sendable {
    public var target: String
    public var segments: [String]
    /// 문체 지시(영어 문장). 앱이 정하며 페이지 글이 아니다. nil이면 엔진 기본 문체이고 JSON에도 넣지 않는다
    public var style: String?

    public init(target: String, segments: [String], style: String? = nil) {
        self.target = target
        self.segments = segments
        self.style = style
    }
}

/// 번역 엔진의 출력. 세그먼트 개수와 순서는 요청과 같아야 한다.
public struct TranslationResult: Codable, Equatable, Sendable {
    public var segments: [String]

    public init(segments: [String]) {
        self.segments = segments
    }
}

public enum TranslationPayloadError: Error, Equatable {
    case segmentCountMismatch(expected: Int, actual: Int)
}

extension TranslationPayloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .segmentCountMismatch:
            String(localized: "번역 결과가 원문과 맞지 않습니다. 다시 시도하세요.", bundle: .module)
        }
    }
}

public enum TranslationPayload {
    /// 엔진 출력이 따라야 하는 JSON 스키마. Claude는 `--json-schema`, Codex는 `--output-schema`로 전달한다.
    public static let outputSchema =
        #"{"type":"object","properties":{"segments":{"type":"array","items":{"type":"string"}}},"#
        + #""required":["segments"],"additionalProperties":false}"#

    public static func encode(_ request: TranslationRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(request)
    }

    /// 엔진 출력을 디코딩하고 세그먼트 개수가 요청과 같은지 검증한다.
    public static func decodeResult(_ data: Data, for request: TranslationRequest) throws -> TranslationResult {
        try validate(JSONDecoder().decode(TranslationResult.self, from: data), for: request)
    }

    /// 세그먼트 개수가 요청과 같은지 검증한다.
    public static func validate(_ result: TranslationResult, for request: TranslationRequest) throws
        -> TranslationResult
    {
        guard result.segments.count == request.segments.count else {
            throw TranslationPayloadError.segmentCountMismatch(
                expected: request.segments.count,
                actual: result.segments.count
            )
        }
        return result
    }
}
