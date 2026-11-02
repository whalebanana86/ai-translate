import CoreGraphics
import Foundation
import Vision

/// OCR로 인식한 한 줄. `boundingBox`는 이미지 픽셀 좌표이며 원점은 왼쪽 위다.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect
    /// 공백으로 나눈 단어마다 영역(이미지 픽셀). OCR이 준 줄만 있다. 이모지를 잘못 읽은 글자를 찾는 데 쓴다(`EmojiFinder`)
    public var wordBoxes: [CGRect]
    /// 글 안 `EmojiFinder.marker`마다 원래 이모지 영역(이미지 픽셀), 글 순서. 렌즈가 그 부분 화면을 번역 글 안에 그린다
    public var emojis: [CGRect]

    public init(
        text: String, confidence: Float, boundingBox: CGRect, wordBoxes: [CGRect] = [], emojis: [CGRect] = []
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.wordBoxes = wordBoxes
        self.emojis = emojis
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
                // 앞뒤 공백을 뺀 글과 단어가 같다 (공백으로 나누면 앞뒤 공백은 단어가 되지 않는다)
                let wordBoxes = candidate.string.split(whereSeparator: \.isWhitespace).map { word in
                    candidate.boundingBox(for: word.startIndex..<word.endIndex)?.boundingBox
                        .toImageCoordinates(size, origin: .upperLeft) ?? .null
                }
                return RecognizedLine(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                    wordBoxes: wordBoxes
                )
            }
            .sorted { ($0.boundingBox.minY, $0.boundingBox.minX) < ($1.boundingBox.minY, $1.boundingBox.minX) }
    }
}
