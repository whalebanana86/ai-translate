import CoreGraphics
import Testing

@testable import TranslateCore

struct CarryOverTests {
    private let start = ContinuousClock.now
    /// 화면 아래쪽 자막 자리와 위쪽 다른 자리
    private let caption = CGRect(x: 300, y: 140, width: 600, height: 80)
    private let elsewhere = CGRect(x: 40, y: 10, width: 300, height: 40)

    @Test func keepsShowingTranslationInSameSpotUntilNewOneArrives() {
        var carryOver = CarryOver()
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start)

        // 자막 글이 바뀌어 번역을 기다리는 동안 같은 자리의 번역을 보여주고, 새 번역이 오면 그것을 보여준다
        let waiting = carryOver.apply(
            to: [.pending], boxes: [caption.offsetBy(dx: 40, dy: 0)], at: start + .milliseconds(400))
        let arrived = carryOver.apply(to: [.translated("둘째 자막")], boxes: [caption], at: start + .milliseconds(800))

        #expect(waiting == [.translated("첫 자막")])
        #expect(arrived == [.translated("둘째 자막")])
    }

    @Test func carriesOnlyIntoOverlappingSpot() {
        var carryOver = CarryOver()
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start)

        let result = carryOver.apply(to: [.pending], boxes: [elsewhere], at: start + .milliseconds(400))

        #expect(result == [.pending])
    }

    @Test func stopsCarryingAfterLifetime() {
        var carryOver = CarryOver()
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start)

        // 이어 보여준 번역도 처음 맞았던 때부터 2초까지만 보여준다 (느린 엔진에서 지난 자막 번역이 계속 남지 않게)
        let carried = carryOver.apply(to: [.pending], boxes: [caption], at: start + .seconds(1))
        let expired = carryOver.apply(to: [.pending], boxes: [caption], at: start + .milliseconds(2500))

        #expect(carried == [.translated("첫 자막")])
        #expect(expired == [.pending])
    }

    @Test func usesEachTranslationForOneParagraphOnly() {
        var carryOver = CarryOver()
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start)
        let upper = CGRect(x: 300, y: 140, width: 600, height: 40)
        let lower = CGRect(x: 300, y: 165, width: 600, height: 55)

        // 한 문단이 두 문단으로 나뉘어 인식되면 더 많이 겹치는 문단에만 잇는다
        let result = carryOver.apply(to: [.pending, .pending], boxes: [upper, lower], at: start + .milliseconds(400))

        #expect(result == [.pending, .translated("첫 자막")])
    }

    @Test func leavesUntranslatableParagraphsAndForgetsAfterReset() {
        var carryOver = CarryOver()
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start)

        let original = carryOver.apply(to: [.original("12:04")], boxes: [caption], at: start + .milliseconds(400))
        _ = carryOver.apply(to: [.translated("첫 자막")], boxes: [caption], at: start + .milliseconds(800))
        carryOver.reset()
        let afterReset = carryOver.apply(to: [.pending], boxes: [caption], at: start + .seconds(1))

        #expect(original == [.original("12:04")])
        #expect(afterReset == [.pending])
    }
}
