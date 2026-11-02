import CoreGraphics
import Testing

@testable import TranslateCore

struct FontSizerTests {
    @Test func ignoresParagraphsThatAreNotDrawn() {
        var sizer = FontSizer()

        // README 그림 장면: 좋아요 줄 26·29px, 작성자 줄 31px(번역 안 함), 17pt 본문 33px
        let sizes = sizer.fontSizes(for: [26, 29, 31, 33], drawn: [false, false, false, true], scale: 2)

        // 본문은 자기 줄 높이 크기 (예전에는 작은 줄과 묶여 13.2pt)
        #expect(abs(sizes[3] - LensGeometry.fontSize(lineHeight: 33, scale: 2)) < 0.001)
        #expect(sizes[0] == LensGeometry.fontSize(lineHeight: 26, scale: 2))
        // 그리지 않는 문단의 크기는 기억하지 않는다: 기억했다면 26~31px를 묶은 29px 크기를 다음 26px 문단이 받는다
        #expect(sizer.fontSizes(for: [26], scale: 2) == [LensGeometry.fontSize(lineHeight: 26, scale: 2)])
    }

    @Test func measuresLineWithoutAttachedEmoji() {
        // 글자 33px 줄 끝에 41px 이모지를 붙인 줄 (EmojiFinder 결과)
        let words = [CGRect(x: 0, y: 4, width: 80, height: 33), CGRect(x: 90, y: 4, width: 60, height: 33)]
        let emoji = CGRect(x: 160, y: 0, width: 40, height: 41)
        let line = RecognizedLine(
            text: "Mine runs 🟦", confidence: 1, boundingBox: CGRect(x: 0, y: 0, width: 200, height: 41),
            wordBoxes: words + [emoji], emojis: [emoji])
        let block = TextBlock(lines: [line], text: line.text, boundingBox: line.boundingBox)

        #expect(FontSizer.lineHeight(of: block) == 33)
    }

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
