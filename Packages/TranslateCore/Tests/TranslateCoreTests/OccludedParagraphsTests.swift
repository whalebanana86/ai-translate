import CoreGraphics
import Testing

@testable import TranslateCore

struct OccludedParagraphsTests {
    /// 이미지 픽셀(2배) 줄. 지어낸 웹페이지에서 OCR이 준 자리와 비슷하게 둔다
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 44) -> RecognizedLine {
        RecognizedLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    private func block(_ lines: RecognizedLine...) -> TextBlock {
        TextBlock(
            lines: lines, text: lines.map(\.text).joined(separator: " "),
            boundingBox: lines.map(\.boundingBox).reduce(lines[0].boundingBox) { $0.union($1) })
    }

    // 메뉴가 열리기 전에 읽은 문단
    private var heading: TextBlock {
        block(
            line("Search API for agents", x: 135, y: 390, width: 780, height: 60),
            line("From $4 /1k requests", x: 135, y: 466, width: 700, height: 60))
    }
    private var talk: TextBlock { block(line("Talk to sales", x: 359, y: 656, width: 178)) }
    private var tryNow: TextBlock { block(line("Try now", x: 162, y: 655, width: 124)) }

    @Test func findsParagraphsCutByMenu() {
        let menuItem = block(
            line("Search API", x: 614, y: 208, width: 150),
            line("Accurate real-time web search", x: 614, y: 246, width: 355))
        let fragments = OccludedParagraphs.find(
            in: [
                block(
                    line("Search AF", x: 135, y: 390, width: 359, height: 60),
                    line("From $4 /", x: 135, y: 466, width: 345, height: 60)),
                block(line("Talk to si", x: 355, y: 656, width: 131)),
                tryNow, menuItem,
            ], reference: [heading, talk, tryNow])

        #expect(fragments == [0: heading, 1: talk])
    }

    @Test func removesFragmentsAndKeepsOccludedParagraphsForNextRecognition() {
        let fragment = block(line("Talk to si", x: 355, y: 656, width: 131))

        let opened = OccludedParagraphs.removingFragments(from: [fragment, tryNow], reference: [talk, tryNow])
        // 메뉴가 열린 채 다시 인식: 지난 문단에는 조각이 없지만 넘겨받은 원래 문단으로 알아본다
        let again = OccludedParagraphs.removingFragments(
            from: [fragment, tryNow], reference: opened.blocks + opened.occluded)
        // 메뉴가 닫힘: 원래 문단이 다시 보인다
        let closed = OccludedParagraphs.removingFragments(
            from: [talk, tryNow], reference: again.blocks + again.occluded)

        #expect(opened.blocks == [tryNow])
        #expect(opened.occluded == [talk])
        #expect(again.blocks == [tryNow])
        #expect(again.occluded == [talk])
        #expect(closed.blocks == [talk, tryNow])
        #expect(closed.occluded.isEmpty)
    }

    @Test func findsLineCutOnTheLeft() {
        let cost = block(line("Lowest latency and cost", x: 1706, y: 371, width: 313))

        let fragments = OccludedParagraphs.find(
            in: [block(line("atency and cost", x: 1800, y: 371, width: 219))], reference: [cost])

        #expect(fragments == [0: cost])
    }

    @Test func findsWholeLinesOfParagraphSplitAroundCutLine() {
        let paragraph = block(
            line("Adaptive search type that picks the best", x: 100, y: 500, width: 800),
            line("mode for each query. The best general", x: 100, y: 550, width: 780),
            line("purpose default for most agents.", x: 100, y: 600, width: 640))

        // 툴팁이 가운데 줄 오른쪽을 덮어 OCR이 세 문단으로 나눠 읽었다
        let fragments = OccludedParagraphs.find(
            in: [
                block(line("Adaptive search type that picks the best", x: 100, y: 500, width: 800)),
                block(line("mode for each qu", x: 100, y: 550, width: 330)),
                block(line("purpose default for most agents.", x: 100, y: 600, width: 640)),
            ], reference: [paragraph])

        #expect(fragments == [0: paragraph, 1: paragraph, 2: paragraph])
    }

    @Test func keepsParagraphThatOnlyReflowed() {
        // 창 너비가 바뀌어 줄바꿈만 달라짐: 글이 짧아지지 않았다
        let fragments = OccludedParagraphs.find(
            in: [
                block(
                    line("Search API for agents", x: 135, y: 390, width: 780, height: 60),
                    line("From $4 /1k", x: 135, y: 466, width: 380, height: 60),
                    line("requests", x: 135, y: 542, width: 300, height: 60))
            ], reference: [heading])

        #expect(fragments.isEmpty)
    }

    @Test func keepsLineShortenedWithEllipsis() {
        let comment = block(line("This comment goes on and on about the weather", x: 100, y: 300, width: 900))

        let fragments = OccludedParagraphs.find(
            in: [block(line("This comment goes on…", x: 100, y: 300, width: 420))], reference: [comment])

        #expect(fragments.isEmpty)
    }

    @Test func keepsLineWhoseWordChanged() {
        let plan = block(line("Pricing plans are billed monthly.", x: 100, y: 300, width: 600))

        let fragments = OccludedParagraphs.find(
            in: [block(line("Pricing plans are billed yearly.", x: 100, y: 300, width: 560))], reference: [plan])

        #expect(fragments.isEmpty)
    }

    @Test func keepsShorterTextAtAnotherPlace() {
        // 같은 높이지만 왼쪽 끝도 오른쪽 끝도 맞지 않는다
        let fragments = OccludedParagraphs.find(
            in: [block(line("Talk to", x: 420, y: 656, width: 90))], reference: [talk])

        #expect(fragments.isEmpty)
    }

    @Test func listsOccludedParagraphsInFragmentOrder() {
        // 원래 문단 목록을 조각 위치 순으로 모은다(같은 문단은 한 번). 사전 순서로 모으면 읽을 때마다 순서가 바뀌었다 (TASK-079)
        let sources = (0..<8).map { TextBlock(lines: [], text: "문단 \($0)", boundingBox: .zero) }
        var fragments: [Int: TextBlock] = [:]
        for (index, source) in sources.enumerated() {
            fragments[index * 2] = source
            fragments[index * 2 + 1] = source
        }

        #expect(OccludedParagraphs.sources(of: fragments) == sources)
    }

    @Test func findsHeadingCutByPopupInRecognizedImage() async throws {
        let page: [TextImage.Line] = [
            .init(text: "Search API for agents", x: 40, top: 60, size: 40),
            .init(text: "Lowest latency and cost", x: 40, top: 260),
        ]
        let menu = TextImage.Popup(
            rect: CGRect(x: 300, y: 30, width: 560, height: 180),
            lines: [
                .init(text: "Contents API", x: 330, top: 130, size: 22),
                .init(text: "Token efficient page extracts", x: 330, top: 165, size: 22),
            ])
        let closed = try #require(TextImage.render(page))
        let opened = try #require(TextImage.render(page, popups: [menu]))
        let before = TextBlockGrouper.group(try await TextRecognizer().recognize(closed))
        let after = TextBlockGrouper.group(try await TextRecognizer().recognize(opened))

        let fragments = OccludedParagraphs.find(in: after, reference: before)

        let heading = try #require(before.first { $0.text == "Search API for agents" })
        #expect(Array(fragments.values) == [heading])
        let fragment = try #require(fragments.keys.first)
        #expect(after[fragment].text.hasPrefix("Search API"))
        #expect(after.contains { $0.text == "Lowest latency and cost" })
    }
}
