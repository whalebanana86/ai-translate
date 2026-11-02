import CoreGraphics
import Testing

@testable import TranslateCore

struct CaptionDetectorTests {
    /// 이미지 픽셀 좌표의 문단. 줄마다 (너비, 가운데 x) 또는 왼쪽 끝을 받는다. 줄 높이 40px, 아래 끝은 `bottom`
    private func block(_ text: String, lines: [(left: CGFloat, width: CGFloat)], bottom: CGFloat = 600) -> TextBlock {
        let top = bottom - CGFloat(lines.count) * 40
        let recognized = lines.enumerated().map { index, line in
            RecognizedLine(
                text: text, confidence: 1,
                boundingBox: CGRect(x: line.left, y: top + CGFloat(index) * 40, width: line.width, height: 40))
        }
        return TextBlock(
            lines: recognized, text: text,
            boundingBox: recognized.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) })
    }

    /// 가운데 x가 `center`인 줄
    private func centered(_ width: CGFloat, center: CGFloat = 800) -> (left: CGFloat, width: CGFloat) {
        (center - width / 2, width)
    }

    @Test func findsTwoCenteredCaptionLines() {
        var detector = CaptionDetector()

        let result = detector.detect([block("So the real question", lines: [centered(700), centered(520)])])

        #expect(result == [CaptionAnchor(centerX: 800, bottom: 600, lineHeight: 40)])
    }

    @Test func leftAlignedParagraphIsNotCaption() {
        var detector = CaptionDetector()

        let result = detector.detect([block("Start free and upgrade", lines: [(100, 700), (100, 520)])])

        #expect(result == [nil])
    }

    @Test func findsSingleLineCaptionsOnceNextCaptionKeepsCenter() {
        var detector = CaptionDetector()

        // 첫 한 줄 자막은 알 수 없다 → 다음 자막이 같은 가운데·다른 너비로 나오면 자막 → 그 자리의 다음 자막은 바로 자막
        let first = detector.detect([block("Thank you.", lines: [centered(300)])])
        let second = detector.detect([block("Let's look at the list together.", lines: [centered(900)])])
        _ = detector.detect([])
        let third = detector.detect([block("First, the offline mode.", lines: [centered(700)])])

        #expect(first == [nil])
        #expect(second.map { $0 != nil } == [true])
        #expect(third.map { $0 != nil } == [true])
    }

    @Test func leftAlignedLineThatChangesIsNotCaption() {
        var detector = CaptionDetector()

        // 왼쪽 끝이 같은 채 글만 바뀌는 줄(조회수, 시간 등)
        _ = detector.detect([block("12 views", lines: [(100, 200)])])
        let result = detector.detect([block("1,204 views", lines: [(100, 260)])])

        #expect(result == [nil])
    }

    @Test func forgetsCaptionSpotsAfterReset() {
        var detector = CaptionDetector()
        _ = detector.detect([block("So the real question", lines: [centered(700), centered(520)])])

        detector.reset()
        let result = detector.detect([block("Thank you.", lines: [centered(300)])])

        #expect(result == [nil])
    }

    @Test func keepsCaptionSpotDespiteSmallRecognitionDifferences() {
        var detector = CaptionDetector()
        let first = detector.detect([block("So the real question", lines: [centered(700), centered(520)])])

        // 같은 자리 다음 자막: 가운데 5px 옆, 아래로 내려가는 글자로 아래 끝 8px 아래, 줄 높이 15% 큼
        let wobbly = block("Let's look at the list together.", lines: [centered(900, center: 805)], bottom: 608)
        let tall = TextBlock(
            lines: wobbly.lines.map { line in
                RecognizedLine(
                    text: line.text, confidence: 1,
                    boundingBox: CGRect(
                        x: line.boundingBox.minX, y: line.boundingBox.minY - 6, width: line.boundingBox.width,
                        height: 46))
            }, text: wobbly.text, boundingBox: wobbly.boundingBox.insetBy(dx: 0, dy: -3).offsetBy(dx: 0, dy: -3))
        let next = detector.detect([tall])

        #expect(next == first)
    }

    @Test func movesCaptionSpotWhenCaptionReallyMovesOrResizes() {
        var detector = CaptionDetector()
        _ = detector.detect([block("So the real question", lines: [centered(700), centered(520)])])

        // 재생 막대가 나타나 자막이 줄 높이의 2배 남짓(90px) 올라감 → 같은 자리로 보되 아래 끝을 옮긴다
        let raised = detector.detect([block("Let's look at the list together.", lines: [centered(900)], bottom: 510)])
        // 전체 화면으로 바꿔 글자가 1.5배 커짐 → 줄 높이를 바꾼다
        let enlarged = block("First, the offline mode.", lines: [centered(1100)], bottom: 510)
        let bigger = TextBlock(
            lines: enlarged.lines.map { line in
                RecognizedLine(
                    text: line.text, confidence: 1,
                    boundingBox: CGRect(x: line.boundingBox.minX, y: 450, width: line.boundingBox.width, height: 60))
            }, text: enlarged.text, boundingBox: CGRect(x: enlarged.boundingBox.minX, y: 450, width: 1100, height: 60))
        let resized = detector.detect([bigger])

        #expect(raised == [CaptionAnchor(centerX: 800, bottom: 510, lineHeight: 40)])
        #expect(resized == [CaptionAnchor(centerX: 800, bottom: 510, lineHeight: 60)])
    }
}
