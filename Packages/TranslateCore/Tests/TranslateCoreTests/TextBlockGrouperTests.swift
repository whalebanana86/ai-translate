import CoreGraphics
import Testing

@testable import TranslateCore

struct TextBlockGrouperTests {
    private func line(
        _ text: String, x: CGFloat = 0, y: CGFloat, width: CGFloat = 400, height: CGFloat = 20,
        confidence: Float = 1
    ) -> RecognizedLine {
        RecognizedLine(
            text: text, confidence: confidence, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func joinsWrappedLinesIntoOneParagraph() {
        let blocks = TextBlockGrouper.group([
            line("Start free and", y: 0), line("upgrade when your", y: 26), line("team grows.", y: 52),
        ])

        #expect(blocks.map(\.text) == ["Start free and upgrade when your team grows."])
    }

    @Test func splitsParagraphsSeparatedByLargeGap() {
        // 간격 6(0.3배)은 같은 문단, 20(1.0배)은 다른 문단
        let blocks = TextBlockGrouper.group([
            line("First paragraph", y: 0), line("continues here.", y: 26), line("Second paragraph.", y: 66),
        ])

        #expect(blocks.map(\.text) == ["First paragraph continues here.", "Second paragraph."])
    }

    @Test func keepsInterleavedColumnsApart() {
        let blocks = TextBlockGrouper.group([
            line("Left one", x: 0, y: 0, width: 300), line("Right one", x: 400, y: 2, width: 300),
            line("left two", x: 0, y: 26, width: 300), line("right two", x: 400, y: 28, width: 300),
        ])

        #expect(blocks.map(\.text) == ["Left one left two", "Right one right two"])
    }

    @Test func separatesHeadingFromBodyBySize() {
        let blocks = TextBlockGrouper.group([
            line("Pricing", y: 0, height: 40), line("Start free.", y: 46, height: 20),
        ])

        #expect(blocks.map(\.text) == ["Pricing", "Start free."])
    }

    @Test func groupsUnsortedInput() {
        let blocks = TextBlockGrouper.group([
            line("team grows.", y: 52), line("Start free and", y: 0), line("upgrade when your", y: 26),
        ])

        #expect(blocks.map(\.text) == ["Start free and upgrade when your team grows."])
    }

    @Test(arguments: [
        (["언제든지 해지할", "수 있습니다."], "언제든지 해지할 수 있습니다."),
        (["料金プランを", "選択してください"], "料金プランを選択してください"),
        (["选择适合您的", "价格方案。"], "选择适合您的价格方案。"),
        (["Claude", "の翻訳"], "Claudeの翻訳"),
        (["Start free.", "Cancel anytime."], "Start free. Cancel anytime."),
    ])
    func joinsWithSpacesOnlyWhereTheScriptUsesThem(texts: [String], expected: String) {
        // 같은 너비의 줄이라 자동 줄바꿈으로 본다
        let lines = texts.enumerated().map { index, text in line(text, y: CGFloat(index) * 26) }

        #expect(TextBlockGrouper.join(lines) == expected)
    }

    // MARK: - 실제 웹페이지(X 타임라인)에서 나온 경우를 본뜬 데이터

    @Test func dropsLowConfidenceIconNoise() {
        let blocks = TextBlockGrouper.group([
            line("Cancel anytime.", y: 0),
            line("• 1", x: 0, y: 60, width: 56, confidence: 0.5),
            line("ıll 120", x: 700, y: 60, width: 94, confidence: 0.5),
            line("企", x: 990, y: 60, width: 44, confidence: 0.3),
            // 신뢰도가 낮아도 글자가 충분하면 남긴다
            line("Subscription", y: 120, confidence: 0.5),
        ])

        #expect(blocks.map(\.text) == ["Cancel anytime.", "Subscription"])
    }

    @Test func keepsButtonsAndNumbersOutOfParagraphs() {
        let blocks = TextBlockGrouper.group([
            line("G...", x: 1082, y: 484, width: 88, height: 32),
            line(
                "@OpenAI GPT-6.1 Terra: $1 per million input tokens, $5 output, about half", x: 134, y: 528,
                width: 1028, height: 34),
            line(
                "the old price. In peer-agent tests it took unauthorized actions in 13.75% of", x: 132, y: 570,
                width: 1012, height: 30),
            line("cases.", x: 134, y: 616, width: 90, height: 23),
            line("120", x: 134, y: 650, width: 40, height: 23),
        ])

        #expect(
            blocks.map(\.text) == [
                "G...",
                "@OpenAI GPT-6.1 Terra: $1 per million input tokens, $5 output, about half the old price. "
                    + "In peer-agent tests it took unauthorized actions in 13.75% of cases.",
                "120",
            ])
        #expect(blocks.map(\.isTranslatable) == [false, true, false])
    }

    // MARK: - 실제 웹페이지(어두운 안내 화면)에서 나온 경우를 본뜬 데이터

    @Test func keepsLinksInARowOutOfTheSentenceAbove() {
        let blocks = TextBlockGrouper.group([
            line(
                "This version needs macOS 26 or later. Update macOS in System Settings, then try again.", x: 110, y: 56,
                width: 1005, height: 31),
            line("Get help", x: 279, y: 104, width: 91, height: 24),
            line("Show details", x: 110, y: 104, width: 134, height: 22),
        ])

        #expect(
            blocks.map(\.text) == [
                "This version needs macOS 26 or later. Update macOS in System Settings, then try again.",
                "Show details", "Get help",
            ])
    }

    @Test func keepsParagraphLinesThatSitNextToOtherColumns() {
        let blocks = TextBlockGrouper.group([
            line("Prepare your Mac", x: 141, y: 340, width: 210, height: 26),
            line("Sign in to Steam", x: 710, y: 340, width: 193, height: 26),
            line("We'll install Steam and the components", x: 141, y: 384, width: 416, height: 24),
            line("Use your own account in the Steam window.", x: 710, y: 384, width: 463, height: 24),
            line("your game needs.", x: 141, y: 418, width: 191, height: 24),
        ])

        #expect(
            blocks.map(\.text) == [
                "Prepare your Mac\nWe'll install Steam and the components your game needs.",
                "Sign in to Steam\nUse your own account in the Steam window.",
            ])
    }

    @Test func keepsHardLineBreaksOfShortLines() {
        let texts = [
            "Al this week:", "Monday: GPT-6.1 Terra", "Wednesday: Gemini 4 Carbon",
            "Thursday: Mistral drops 1T open weights", "Next week: Qwen4, apparently",
            "Me: still halfway through evals for a model from September.", "Labs ship weekly.",
            "I benchmark geologically.",
        ]
        let widths: [CGFloat] = [176, 324, 410, 554, 424, 812, 244, 352]
        let lines = zip(texts, widths).enumerated().map { index, pair in
            line(pair.0, x: 134, y: 54 + CGFloat(index) * 40, width: pair.1, height: 30)
        }

        let blocks = TextBlockGrouper.group(lines)

        // 가장 긴 줄 다음은 남은 공간을 알 수 없어 자동 줄바꿈으로 본다
        #expect(
            blocks.map(\.text) == [
                "Al this week:\nMonday: GPT-6.1 Terra\nWednesday: Gemini 4 Carbon\n"
                    + "Thursday: Mistral drops 1T open weights\nNext week: Qwen4, apparently\n"
                    + "Me: still halfway through evals for a model from September. Labs ship weekly.\n"
                    + "I benchmark geologically."
            ])
    }

    @Test func keepsHardLineBreaksInJapanese() {
        let blocks = TextBlockGrouper.group([
            line("料金プランを選択してください", x: 0, y: 0, width: 400),
            line("月額", x: 0, y: 26, width: 60),
            line("年額でお得に", x: 0, y: 52, width: 170),
        ])

        // 첫 줄은 가장 길어 자동 줄바꿈, 둘째 줄은 짧게 끝나 강제 줄바꿈
        #expect(blocks.map(\.text) == ["料金プランを選択してください月額\n年額でお得に"])
    }

    @Test func blockBoundingBoxIsUnionOfLines() {
        let blocks = TextBlockGrouper.group([
            line("Start free and", x: 0, y: 0, width: 400), line("upgrade.", x: 10, y: 26, width: 200),
        ])

        #expect(blocks.first?.boundingBox == CGRect(x: 0, y: 0, width: 400, height: 46))
        #expect(blocks.first?.lines.count == 2)
    }

    @Test func returnsNoBlocksForNoLines() {
        #expect(TextBlockGrouper.group([]).isEmpty)
    }
}
