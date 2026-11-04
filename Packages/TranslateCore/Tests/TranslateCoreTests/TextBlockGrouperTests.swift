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

    // MARK: - 실제 웹페이지(유튜브 댓글, 한국어 화면, 배율 2)에서 나온 경우를 본뜬 데이터

    @Test func keepsCommentBylineOutOfCommentBody() {
        let blocks = TextBlockGrouper.group([
            // 본문이 짧아 머리줄이 가장 넓은 줄: 예전에는 자동 줄바꿈으로 보고 공백으로 이었다
            line("@GabrielsEpicLifeofGoals 6년 전(수정됨)", x: 34, y: 854, width: 432, height: 30),
            line("Legend.", x: 34, y: 901, width: 104, height: 30),
            // 여러 줄 본문
            line("@ JetpackGamer456 6년 전(수정됨)", x: 34, y: 1313, width: 374, height: 30),
            line("Ok let's be honest here", x: 34, y: 1360, width: 287, height: 30),
            line("Rick rolling is the one meme that will never die", x: 34, y: 1401, width: 580, height: 34),
        ])

        #expect(
            blocks.map(\.text) == [
                "@GabrielsEpicLifeofGoals 6년 전(수정됨)", "Legend.", "@ JetpackGamer456 6년 전(수정됨)",
                "Ok let's be honest here\nRick rolling is the one meme that will never die",
            ])
    }

    @Test(arguments: [
        "@candycake9531 6년 전", "@OjaswiThapa-v8f 13시간 전", "@user-kx9pq2 2일전", "@user 1개월 전(수정됨)",
        "@user 2 days ago", "@user 1 year ago (edited)", "@ユーザー 3日前", "@ユーザー 6 年前（編集済み）", "@用户 5小时前",
        "u/someone · 3 hours ago",
        // X 게시물 머리줄 (첫 줄은 실제 화면 OCR 결과: "17분"을 "17₽"로 읽었다)
        "Sylvester Osemudiamen Prosper @Sylvester070783 • 17₽", "Sylvester Osemudiamen Prosper @SylvesterO70783 · 17분",
        "Jane Doe @jane · Nov 2, 2023", "김철수 @chulsoo · 11월 2일", "山田太郎 @yamada · 3時間", "Jane Doe @ jane · 2h",
        // OCR이 "·"를 빠뜨리거나 붙여 읽은 X 머리줄 (재현 화면 OCR 결과·사용자 화면, TASK-070. "455"는 "45초")
        "Margarete @BoernieMargarete 10초", "Theo @theo_onchain 11월 2일", "Kai @kai_writes 455", "Jane Doe @jane Nov 2",
        "山田太郎 @yamada・3時間", "@yui_dev・17分",
        // 아이디만 있는 줄 (답글 대상 줄이 나뉘어 "님과"를 "&Z"로 읽었다)
        "@NorthwindLab&Z", "@jane @bob", "@ jane",
    ])
    func recognizesBylines(text: String) {
        #expect(TextBlockGrouper.isByline(line(text, y: 0)))
    }

    @Test(arguments: [
        "Rick rolling is the one meme that will never die", "답글 4개", "2026년 전시회 일정",
        "I have been listening to this song every day since 2 years ago",
        // X 본문: 아이디가 있어도 뒤가 시각이 아니다
        "Thanks @bob. 2 more things", "Thanks @bob . 2 more things",
        "@OpenAI GPT-6.1 Terra: $1 per million input tokens",
        "cc @jane", "Jane Doe @jane · 방금",
        // 구분점이 없으면 시각 모양을 좁게 본다
        "Meet @john at 5", "Ask @bob 2 questions about it", "@jane thanks for the 2 tips", "Say hi to @john tomorrow",
    ])
    func doesNotTakeOtherLinesForBylines(text: String) {
        #expect(!TextBlockGrouper.isByline(line(text, y: 0)))
    }

    @Test func doesNotTranslateBylines() {
        let blocks = TextBlockGrouper.group([
            line("Sylvester Osemudiamen Prosper @Sylvester070783 • 17₽", x: 117, y: 49, width: 827, height: 34),
            line("@user 2 days ago", y: 120),
            line("Great thread, thanks for sharing.", y: 180),
        ])

        // 이름·아이디는 번역 대상이 아니다 (이름이 한글 발음으로 바뀌었다)
        #expect(blocks.map(\.isTranslatable) == [false, false, true])
    }

    @Test func keepsXHeaderWithoutSeparatorOutOfBody() {
        // 재현 화면(Chrome 2배)의 OCR 줄: 머리줄 "·"가 빠졌고, 답글 대상 줄은 둘로 나뉘었다
        let blocks = TextBlockGrouper.group([
            line("Theo @theo_onchain 11월 2일", x: 128, y: 677, width: 424, height: 41),
            line("Short note about the new build and what changed this week.", x: 128, y: 722, width: 600, height: 30),
            line("@NorthwindLab&Z", x: 137, y: 870, width: 252, height: 28),
            line("@river_onchain님께 보내는 답글", x: 403, y: 868, width: 392, height: 35),
            line(
                "So when does an assistant actually start coordinating work, rather than just", x: 135, y: 914,
                width: 951),
        ])

        #expect(blocks.count == 5)
        #expect(blocks.map(\.isTranslatable) == [false, true, true, false, true])
        #expect(blocks.last?.text == "So when does an assistant actually start coordinating work, rather than just")
    }

    @Test func joinsSidebarParagraphBesideFarByline() {
        // 다른 단(사이드바) 문단은 같은 높이에 작성자 줄이 있어도 잇는다
        let blocks = TextBlockGrouper.group([
            line("Theo @theo_onchain · 11월 2일", x: 128, y: 0, width: 424, height: 30),
            line("우리가 함께한다면 무엇도 두렵지 않을 거야 같이 갈", x: 1460, y: 0, width: 510, height: 30),
            line("준비됐지?", x: 1460, y: 38, width: 120, height: 30),
        ])

        #expect(blocks.map(\.text) == ["Theo @theo_onchain · 11월 2일", "우리가 함께한다면 무엇도 두렵지 않을 거야 같이 갈 준비됐지?"])
    }

    @Test func joinsWrappedBodyLineEndingWithRelativeTime() {
        let blocks = TextBlockGrouper.group([
            line("I have been listening to this song every day since 2 years ago", y: 0, width: 800),
            line("and it never gets old.", y: 26, width: 270),
        ])

        #expect(
            blocks.map(\.text) == [
                "I have been listening to this song every day since 2 years ago and it never gets old."
            ])
    }

    @Test func keepsLikeCountRowOutOfCommentBody() {
        let blocks = TextBlockGrouper.group([
            line("Ok let's be honest here", x: 34, y: 1360, width: 287, height: 30),
            line("Rick rolling is the one meme that will never die", x: 34, y: 1401, width: 580, height: 34),
            // 엄지 아이콘을 "C"로 읽었다. 같은 줄의 "답글"은 신뢰도가 낮아 잡음으로 버려진다
            line("C 42만", x: 34, y: 1458, width: 101, height: 34),
            line("답글", x: 236, y: 1461, width: 57, height: 27, confidence: 0.5),
        ])

        #expect(
            blocks.map(\.text) == [
                "Ok let's be honest here\nRick rolling is the one meme that will never die", "C 42만",
            ])
        #expect(blocks.map(\.isTranslatable) == [true, false])
    }

    @Test(arguments: ["C 42만", "§ 116", "2 7.2만 77", "6 29만", "42K"])
    func doesNotTranslateRowsWithoutWords(text: String) {
        #expect(TextBlockGrouper.group([line(text, y: 0)]).map(\.isTranslatable) == [false])
    }

    @Test(arguments: ["답글 4개", "OK", "月額", "Go"])
    func translatesShortWords(text: String) {
        #expect(TextBlockGrouper.group([line(text, y: 0)]).map(\.isTranslatable) == [true])
    }

    @Test func keepsReadMoreLinkOutOfCommentBody() {
        let blocks = TextBlockGrouper.group([
            line(
                "WOW! I can't believe it! One billion views!! This is a very special moment for me. God bless you all, "
                    + "and hope there's more billions of", x: 34, y: 979, width: 1622, height: 30),
            line("views in the future!..", x: 30, y: 1019, width: 256, height: 30),
            line("자세히 알아보기", x: 34, y: 1067, width: 179, height: 30),
        ])

        #expect(
            blocks.map(\.text) == [
                "WOW! I can't believe it! One billion views!! This is a very special moment for me. God bless you all, "
                    + "and hope there's more billions of views in the future!..",
                "자세히 알아보기",
            ])
    }

    @Test(arguments: ["자세히 알아보기", "자세히알아보기", "더보기", "Read more", "Read more…", "Show less", "もっと見る", "展开"])
    func recognizesExpandLinks(text: String) {
        #expect(TextBlockGrouper.isExpandLink(line(text, y: 0)))
    }

    @Test(arguments: ["Read more about our pricing plans", "more", "자세히 알아보기 전에 확인하세요"])
    func doesNotTakeSentencesForExpandLinks(text: String) {
        #expect(!TextBlockGrouper.isExpandLink(line(text, y: 0)))
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

    @Test func joinsLinesByMeasuredBaselinesWhenOcrBoxesDisagree() {
        // 28px 글자 세 줄(기준선 사이 42px)인데 OCR 상자 높이가 15·37·22px로 들쭉날쭉하다 (Chrome 측정에서 실제로 나왔다).
        // 상자로 보면 높이 비율·간격 규칙에 걸려 나뉜다
        let lines = [
            RecognizedLine(
                text: "The new offline mode keeps", confidence: 1,
                boundingBox: CGRect(x: 40, y: 47, width: 500, height: 15)),
            RecognizedLine(
                text: "your drafts on the device", confidence: 1,
                boundingBox: CGRect(x: 40, y: 72, width: 480, height: 37)),
            RecognizedLine(
                text: "and syncs them later.", confidence: 1, boundingBox: CGRect(x: 40, y: 124, width: 400, height: 22)
            ),
        ]
        let styles = [0, 1, 2].map {
            LineStyle(pixelSize: 28, strokeRatio: 0.1, weight: .regular, baseline: 66 + CGFloat($0) * 42)
        }

        #expect(TextBlockGrouper.group(lines).count > 1)
        #expect(TextBlockGrouper.group(lines, styles: styles).count == 1)
        // 기준선 사이가 글자 크기 두 배를 넘으면(문단 사이) 잇지 않는다
        var apart = styles
        apart[2].baseline = 66 + 42 + 60
        #expect(TextBlockGrouper.group(lines, styles: apart).count == 2)
    }

    @Test func joinsWordBrokenAfterItsHyphenWithoutSpace() {
        let first = RecognizedLine(
            text: "truly terrible idiocracy-", confidence: 1, boundingBox: CGRect(x: 40, y: 40, width: 700, height: 30))
        let second = RecognizedLine(
            text: "grade content. I'm sure", confidence: 1, boundingBox: CGRect(x: 40, y: 88, width: 400, height: 30))
        let dash = RecognizedLine(
            text: "the same tired topics -", confidence: 1, boundingBox: CGRect(x: 40, y: 40, width: 700, height: 30))

        #expect(TextBlockGrouper.separator(between: first, and: second, blockRight: 740) == "")
        // 단어 뒤가 아닌 줄표는 띄어 쓴다
        #expect(TextBlockGrouper.separator(between: dash, and: second, blockRight: 740) == " ")
    }
}
