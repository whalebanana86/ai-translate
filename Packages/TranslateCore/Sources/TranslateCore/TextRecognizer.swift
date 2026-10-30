import CoreGraphics
import Foundation
import Vision

/// OCR로 인식한 한 줄. `boundingBox`는 이미지 픽셀 좌표이며 원점은 왼쪽 위다.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Vision으로 이미지의 텍스트를 줄 단위로 인식한다. 기기 안에서만 처리하며 네트워크를 쓰지 않는다.
public struct TextRecognizer: Sendable {
    /// 언어 자동 감지에 주는 힌트.
    ///
    /// Vision 기본값은 en-US 하나라 한국어가 인식되지 않고, 자동 감지 없이 여러 언어를 지정하면 일본어 줄이 빠졌다.
    /// 자동 감지와 힌트를 함께 써야 세 언어가 모두 인식된다 (macOS 26.3 확인).
    public static let defaultLanguageHints = ["en-US", "ko-KR", "ja-JP", "zh-Hans", "zh-Hant"]

    public var languageHints: [String]

    public init(languageHints: [String] = defaultLanguageHints) {
        self.languageHints = languageHints
    }

    /// 빈 줄을 뺀 인식 결과를 위→아래(같으면 왼쪽→오른쪽) 순서로 돌려준다.
    public func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = languageHints.map { Locale.Language(identifier: $0) }

        let size = CGSize(width: image.width, height: image.height)
        let observations = try await request.perform(on: image)
        return
            observations
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedLine(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
                )
            }
            .sorted { ($0.boundingBox.minY, $0.boundingBox.minX) < ($1.boundingBox.minY, $1.boundingBox.minX) }
    }
}
