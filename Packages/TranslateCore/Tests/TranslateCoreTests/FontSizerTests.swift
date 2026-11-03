import CoreGraphics
import Testing

@testable import TranslateCore

struct FontSizerTests {
    @Test func ignoresParagraphsThatAreNotDrawn() {
        var sizer = FontSizer()

        // 좋아요 줄 27·28px, 작성자 줄 29px(번역 안 함), 본문 30.5px (README 그림 장면처럼 작은 줄이 먼저 크기를 만든다)
        let sizes = sizer.fontSizes(for: [27, 28, 29, 30.5], drawn: [false, false, false, true], scale: 2)

        // 본문은 자기 크기 (예전에는 작은 줄과 묶인 28px 크기)
        #expect(abs(sizes[3] - LensGeometry.fontSize(pixelSize: 30.5, scale: 2)) < 0.001)
        #expect(sizes[0] == LensGeometry.fontSize(pixelSize: 27, scale: 2))
        // 그리지 않는 문단의 크기는 기억하지 않는다: 기억했다면 27~29px를 묶은 28px 크기를 다음 27px 문단이 받는다
        #expect(sizer.fontSizes(for: [27], scale: 2) == [LensGeometry.fontSize(pixelSize: 27, scale: 2)])
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
        // 캡처에서 재지 못했을 때 글자 크기
        #expect(abs(FontSizer.pixelSize(of: block) - 33 * 0.93) < 0.001)
    }

    @Test func drawsCommentsOfSameSizeAtOneSizeAndTitleLarger() {
        var sizer = FontSizer()

        // 유튜브 댓글 4개(같은 글자 크기, 잰 크기 ±4%)와 1.4배 큰 제목
        let sizes = sizer.fontSizes(for: [30, 29, 42, 31, 29.5], scale: 2)

        #expect(Set([sizes[0], sizes[1], sizes[3], sizes[4]]).count == 1)
        #expect(sizes[2] > sizes[0])
    }

    @Test func separatesSizesThatDifferByMoreThanTenPercent() {
        var sizer = FontSizer()

        // 본문 30px과 작은 소제목 26px (1.15배): 줄 상자 높이로 잴 때(1.2배 묶음)는 한 크기였다 (TASK-059)
        let sizes = sizer.fontSizes(for: [30, 26], scale: 2)

        #expect(sizes[0] > sizes[1])
    }

    @Test func keepsSizeUsedBeforeWhenSameTextIsRecognizedAgain() {
        var sizer = FontSizer()
        let first = sizer.fontSizes(for: [30], scale: 2)

        // 스크롤 뒤 같은 크기의 글이 조금 다르게 재짐 → 전에 쓴 크기 그대로. 1.1배를 넘으면 새 크기
        let again = sizer.fontSizes(for: [32, 28.5], scale: 2)
        let larger = sizer.fontSizes(for: [40], scale: 2)

        #expect(again == [first[0], first[0]])
        #expect(larger[0] > first[0])
    }

    @Test func doesNotDependOnParagraphOrder() {
        var forward = FontSizer()
        var backward = FontSizer()

        let one = forward.fontSizes(for: [29, 31, 30], scale: 2)
        let other = backward.fontSizes(for: [30, 31, 29], scale: 2)

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
