import Testing

@testable import TranslateCore

struct TextSettlingTests {
    private let start = ContinuousClock.now

    /// `ms`초에 인식한 글을 알리고 번역할 문단을 고른다 (렌즈는 인식할 때마다 이렇게 부른다)
    private func recognize(
        _ texts: [String], missing: [String]? = nil, at ms: Int, settling: inout TextSettling
    ) -> [String] {
        let now = start + .milliseconds(ms)
        settling.observe(texts, at: now)
        return settling.ready(missing ?? texts, text: { $0 }, at: now)
    }

    @Test func waitsUntilCaptionStaysUnchanged() {
        var settling = TextSettling()

        // 인식 주기 약 0.35초: 처음 본 때 → 0.35초(아직) → 0.7초(0.5초 넘게 그대로)
        let first = recognize(["Let's look at the list together."], at: 0, settling: &settling)
        let second = recognize(["Let's look at the list together."], at: 350, settling: &settling)
        let third = recognize(["Let's look at the list together."], at: 700, settling: &settling)

        #expect(first.isEmpty)
        #expect(second.isEmpty)
        #expect(third == ["Let's look at the list together."])
    }

    @Test func sendsOnlySettledParagraphsWhenMixed() {
        var settling = TextSettling()
        _ = recognize(["Chapter one"], at: 0, settling: &settling)

        let result = recognize(["Chapter one", "So today"], at: 600, settling: &settling)

        #expect(result == ["Chapter one"])
    }

    @Test func sendsGrowingAutoCaptionEveryTwoSecondsThenWaitsAgain() {
        var settling = TextSettling()
        let words = ["So", "today", "we", "are", "going", "to", "talk", "about", "the", "new", "plan"]
        var results: [[String]] = []

        // 말이 쉬지 않고 이어져 0.35초마다 단어가 붙는다
        for count in 1...words.count {
            let caption = words.prefix(count).joined(separator: " ")
            results.append(recognize([caption], at: 350 * (count - 1), settling: &settling))
        }

        // 2.1초(7번째 인식)에 그때까지 나온 글을 보내고, 그다음부터 다시 2초를 기다린다
        let sentAt = results.map(\.isEmpty).firstIndex(of: false)
        let laterSent = results[7...].map(\.isEmpty).contains(false)
        #expect(sentAt == 6)
        #expect(results[6] == ["So today we are going to talk"])
        #expect(!laterSent)
    }

    @Test func restartsTimingForTextThatDisappearedAndCameBack() {
        var settling = TextSettling()
        _ = recognize(["Thank you."], at: 0, settling: &settling)
        _ = recognize([], at: 350, settling: &settling)

        let result = recognize(["Thank you."], at: 700, settling: &settling)

        #expect(result.isEmpty)
    }

    @Test func sendsCaptionAtOnceWhenNothingCoversItWhileWaiting() {
        var settling = TextSettling()
        let now = start + .milliseconds(0)
        settling.observe(["Thank you.", "So today we"], at: now)

        // 자막 사이 빈 구간 뒤 첫 자막: 이어 보여줄 지난 번역이 없으면 바로. 지난 번역으로 가려진 자막은 다 나오기를 기다린다
        let result = settling.ready(
            ["Thank you.", "So today we"], text: { $0 }, isCovered: { $0 == "So today we" }, at: now)

        #expect(result == ["Thank you."])
    }
}
