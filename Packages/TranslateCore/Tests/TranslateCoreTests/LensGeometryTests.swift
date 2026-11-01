import CoreGraphics
import Testing

@testable import TranslateCore

struct LensGeometryTests {
    /// 이미지 픽셀 좌표의 문단. 줄 높이 30px, `lines`줄
    private func block(x: CGFloat, y: CGFloat = 100, width: CGFloat = 200, lineHeight: CGFloat = 30, lines: Int = 1)
        -> TextBlock
    {
        let recognized = (0..<lines).map { index in
            RecognizedLine(
                text: "Start free.", confidence: 1,
                boundingBox: CGRect(x: x, y: y + CGFloat(index) * (lineHeight + 4), width: width, height: lineHeight))
        }
        return TextBlock(
            lines: recognized, text: "Start free.",
            boundingBox: recognized.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) })
    }

    private let lens = CGSize(width: 500, height: 300)

    @Test func multiLineParagraphStaysAtOriginalPositionAndWidth() {
        let frames = LensGeometry.paragraphFrames(of: [block(x: 200, width: 400, lines: 2)], scale: 2, lensSize: lens)

        // 원문 크기: 두 줄(30px + 간격 4px + 30px)을 배율 2로 나눈 포인트. 아래에 블록이 없으면 렌즈 끝까지 쓸 수 있다
        #expect(
            frames == [
                ParagraphFrame(
                    origin: CGPoint(x: 100, y: 50), width: 200, maxHeight: 300 - 50,
                    sourceSize: CGSize(width: 200, height: 32))
            ])
    }

    @Test func singleLineParagraphExtendsToRightNeighborOrLensEdge() {
        let frames = LensGeometry.paragraphFrames(of: [block(x: 20), block(x: 600)], scale: 2, lensSize: lens)

        #expect(frames.map(\.origin) == [CGPoint(x: 10, y: 50), CGPoint(x: 300, y: 50)])
        #expect(frames.map(\.width) == [CGFloat(300 - 4 - 10), CGFloat(500 - 300)])
    }

    @Test func ignoresBlocksStartingInsideItsOwnArea() {
        // 영역이 겹친 OCR 결과: 오른쪽 블록이 문단 오른쪽 끝보다 왼쪽에서 시작하면 이웃이 아니다
        let frames = LensGeometry.paragraphFrames(
            of: [block(x: 0, width: 600), block(x: 200, y: 110, width: 100)], scale: 2, lensSize: lens)

        #expect(frames[0].width == 500)
    }

    @Test func limitsHeightToBlockBelow() {
        let frames = LensGeometry.paragraphFrames(
            of: [
                block(x: 0, y: 100, width: 100),
                // 첫 문단의 원래 너비 밖이지만, 한 줄 문단이라 늘어난 너비 아래에 있으므로 높이를 막는다
                block(x: 400, y: 200, width: 100),
                // 둘째 문단과 가로로 겹치지 않으므로 둘째 문단 높이와는 상관없다
                block(x: 0, y: 250, width: 100),
            ], scale: 2, lensSize: lens)

        #expect(frames[0].maxHeight == CGFloat(100 - 4 - 50))
        #expect(frames[1].maxHeight == CGFloat(300 - 100))
    }

    @Test func keepsAtLeastSourceHeight() {
        // 아래 블록이 문단 영역 안에서 시작해도 원문 높이만큼은 쓴다
        let frames = LensGeometry.paragraphFrames(
            of: [block(x: 0, y: 100, width: 400, lines: 2), block(x: 0, y: 120, width: 100)], scale: 2,
            lensSize: lens)

        #expect(frames[0].maxHeight == 32)
    }

    @Test func matchesFontSizeToOriginalLineHeight() {
        #expect(LensGeometry.fontSize(of: block(x: 0, lineHeight: 30), scale: 2) == CGFloat(13.5))
        #expect(LensGeometry.fontSize(of: block(x: 0, lineHeight: 10), scale: 2) == CGFloat(11))
        #expect(LensGeometry.fontSize(of: block(x: 0, lineHeight: 100), scale: 1) == CGFloat(24))
    }

    @Test func usesTallestLineForFontSize() {
        // 첫 줄("Al this week:")은 아래로 내려가는 글자가 없어 낮게 잡힌 경우
        let lines = [
            RecognizedLine(
                text: "Al this week:", confidence: 1, boundingBox: CGRect(x: 0, y: 0, width: 176, height: 24)),
            RecognizedLine(
                text: "Monday: GPT-6.1 Terra", confidence: 1, boundingBox: CGRect(x: 0, y: 38, width: 324, height: 30)),
        ]
        let block = TextBlock(lines: lines, text: "", boundingBox: CGRect(x: 0, y: 0, width: 324, height: 68))

        #expect(LensGeometry.fontSize(of: block, scale: 2) == CGFloat(13.5))
    }

    @Test func putsToolbarAboveLensOrInsideWhenNoRoom() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)

        #expect(
            LensGeometry.toolbarFrame(height: 34, for: CGRect(x: 100, y: 500, width: 400, height: 300), in: screen)
                == CGRect(x: 100, y: 800, width: 400, height: 34))
        #expect(
            LensGeometry.toolbarFrame(height: 34, for: CGRect(x: 100, y: 640, width: 400, height: 300), in: screen)
                == CGRect(x: 100, y: 906, width: 400, height: 34))
    }

    @Test func keepsToolbarWideEnoughForNarrowLens() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 950)

        #expect(
            LensGeometry.toolbarFrame(height: 34, for: CGRect(x: 100, y: 500, width: 200, height: 100), in: screen)
                .width == LensGeometry.minimumToolbarWidth)
    }

    @Test func resizesFromBottomRightKeepingTopLeft() {
        let lens = CGRect(x: 100, y: 500, width: 400, height: 300)

        // 오른쪽으로 50, 아래로 40 끌기 (AppKit 좌표라 dy는 음수)
        #expect(
            LensGeometry.resized(lens, by: CGSize(width: 50, height: -40))
                == CGRect(x: 100, y: 460, width: 450, height: 340))
        #expect(
            LensGeometry.resized(lens, by: CGSize(width: -1000, height: 1000))
                == CGRect(x: 100, y: 720, width: 160, height: 80))
    }

    @Test func detectsParagraphsCutAtLensEdges() {
        // 이미지 높이 600px, 줄 높이 30px
        #expect(LensGeometry.isCutOff(block(x: 0, y: 3), imageHeight: 600))
        #expect(LensGeometry.isCutOff(block(x: 0, y: 566), imageHeight: 600))
        #expect(!LensGeometry.isCutOff(block(x: 0, y: 100, lines: 2), imageHeight: 600))
    }

    // MARK: 번역 기록 패널

    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func placesTranscriptRightOfLensAndRaisesItBesideThinSubtitleLens() {
        let lens = CGRect(x: 200, y: 100, width: 800, height: 100)

        #expect(LensGeometry.transcriptFrame(for: lens, in: screen) == CGRect(x: 1008, y: 100, width: 320, height: 260))
    }

    @Test func placesTranscriptLeftOfLensWhenRightSideIsFull() {
        let lens = CGRect(x: 700, y: 100, width: 800, height: 400)

        #expect(LensGeometry.transcriptFrame(for: lens, in: screen) == CGRect(x: 372, y: 100, width: 320, height: 400))
    }

    @Test func placesTranscriptInsideScreenEdgeWhenBothSidesAreFull() {
        // 전체 화면 영상의 자막처럼 화면 너비를 거의 다 쓰는 렌즈
        let lens = CGRect(x: 100, y: 60, width: 1400, height: 90)

        #expect(LensGeometry.transcriptFrame(for: lens, in: screen) == CGRect(x: 1280, y: 60, width: 320, height: 260))
    }

    @Test func keepsTranscriptOnScreenAndClearOfWideToolbar() {
        // 화면 위쪽 렌즈: 위로 넘치지 않게 내린다
        let top = CGRect(x: 200, y: 900, width: 600, height: 80)
        // 좁은 렌즈: 렌즈보다 넓은 도구 막대(340) 오른쪽에 둔다
        let narrow = CGRect(x: 200, y: 100, width: 200, height: 100)

        #expect(LensGeometry.transcriptFrame(for: top, in: screen) == CGRect(x: 808, y: 740, width: 320, height: 260))
        #expect(LensGeometry.transcriptFrame(for: narrow, in: screen).minX == 548)
    }
}
