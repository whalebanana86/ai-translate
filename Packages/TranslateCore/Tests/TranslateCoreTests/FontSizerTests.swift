import CoreGraphics
import Testing

@testable import TranslateCore

struct FontSizerTests {
    @Test func drawsCommentsOfSameSizeAtOneSizeAndTitleLarger() {
        var sizer = FontSizer()

        // 유튜브 댓글 4개(같은 글자 크기, 인식된 줄 높이 ±10%)와 1.4배 큰 제목
        let sizes = sizer.fontSizes(for: [30, 27, 42, 33, 29], scale: 2)

        #expect(Set([sizes[0], sizes[1], sizes[3], sizes[4]]).count == 1)
        #expect(sizes[2] > sizes[0])
    }

    @Test func keepsSizeUsedBeforeWhenSameTextIsRecognizedAgain() {
        var sizer = FontSizer()
        let first = sizer.fontSizes(for: [30], scale: 2)

        // 스크롤 뒤 같은 크기의 글이 조금 다르게 인식됨 → 전에 쓴 크기 그대로. 1.2배를 넘으면 새 크기
        let again = sizer.fontSizes(for: [34, 26], scale: 2)
        let larger = sizer.fontSizes(for: [40], scale: 2)

        #expect(again == [first[0], first[0]])
        #expect(larger[0] > first[0])
    }

    @Test func doesNotDependOnParagraphOrder() {
        var forward = FontSizer()
        var backward = FontSizer()

        let one = forward.fontSizes(for: [27, 33, 30], scale: 2)
        let other = backward.fontSizes(for: [30, 33, 27], scale: 2)

        #expect(Set(one) == Set(other))
        #expect(Set(one).count == 1)
    }

    @Test func usesMedianLineHeightOfParagraph() {
        let lines = [24, 30, 29].enumerated().map { index, height in
            RecognizedLine(
                text: "line", confidence: 1,
                boundingBox: CGRect(x: 0, y: CGFloat(index) * 40, width: 300, height: CGFloat(height)))
        }
        let block = TextBlock(lines: lines, text: "", boundingBox: CGRect(x: 0, y: 0, width: 300, height: 110))

        #expect(FontSizer.lineHeight(of: block) == 29)
    }
}
