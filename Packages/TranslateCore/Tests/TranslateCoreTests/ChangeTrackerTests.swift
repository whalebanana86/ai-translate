import CoreGraphics
import Testing

@testable import TranslateCore

struct ChangeTrackerTests {
    private let page: [(String, CGFloat)] = [
        ("Start free. Upgrade when your team grows.", 40), ("Cancel anytime, no questions asked.", 100),
        ("Pricing plans are billed monthly.", 160), ("Annual billing saves 20 percent.", 220),
    ]

    private func fingerprint(_ lines: [(String, CGFloat)]) throws -> ImageFingerprint {
        let image = try #require(TextImage.render(lines.map { .init(text: $0.0, x: 40, top: $0.1) }))
        return try #require(ImageFingerprint(image))
    }

    @Test func sameScreenHasSameFingerprint() throws {
        #expect(try fingerprint(page).difference(to: fingerprint(page)) == 0)
    }

    @Test func scrollingAndWordChangesExceedThreshold() throws {
        let original = try fingerprint(page)
        let scrolled = try fingerprint(page.map { ($0.0, $0.1 - 4) })
        var edited = page
        edited[2].0 = "Pricing plans are billed yearly."

        #expect(original.difference(to: scrolled) > ChangeTracker.threshold)
        #expect(try original.difference(to: fingerprint(edited)) > ChangeTracker.threshold)
    }

    @Test func scrollingMovesAwayButWordChangeDoesNot() throws {
        let original = try fingerprint(page)
        let scrolled = try fingerprint(page.map { ($0.0, $0.1 - 4) })
        var edited = page
        edited[2].0 = "Pricing plans are billed yearly."

        #expect(original.difference(to: scrolled) > ChangeTracker.movedAwayThreshold)
        #expect(try original.difference(to: fingerprint(edited)) < ChangeTracker.movedAwayThreshold)
    }

    /// 프레임을 차례로 넣고 결과를 돌려준다
    private func changes(_ frames: [ImageFingerprint], tracker: inout ChangeTracker) -> [ChangeTracker.Change] {
        frames.map { tracker.observe($0) }
    }

    @Test func processesOnceAfterScreenSettles() throws {
        let first = try fingerprint(page)
        let second = try fingerprint(page.map { ($0.0, $0.1 - 20) })
        var tracker = ChangeTracker()

        // 처음 화면: 한 번 멈춘 뒤 처리하고 그대로면 다시 처리하지 않음.
        // 스크롤: 움직이는 동안은 번역을 숨기고 기다렸다가 멈추면 처리
        let results = changes([first, first, first, second, second, second], tracker: &tracker)

        #expect(results == [.movedAway, .settled, .unchanged, .movedAway, .settled, .unchanged])
    }

    @Test func returnsToProcessedStateWithoutProcessingAgain() throws {
        let first = try fingerprint(page)
        let moving = try fingerprint(page.map { ($0.0, $0.1 - 20) })
        var tracker = ChangeTracker()

        // 처리한 뒤 멈추지 않고 스크롤했다가 원래 자리로 돌아옴: 숨겼던 번역을 다시 보여주고 다시 처리하지 않음
        let results = changes([first, first, moving, first, first], tracker: &tracker)

        #expect(results == [.movedAway, .settled, .movedAway, .unchanged, .unchanged])
    }

    @Test func keepsTranslationsWhileAWordChangesThenProcessesIt() throws {
        let first = try fingerprint(page)
        var edited = page
        edited[2].0 = "Pricing plans are billed yearly."
        let changed = try fingerprint(edited)
        var tracker = ChangeTracker()

        let results = changes([first, first, changed, changed, changed], tracker: &tracker)

        #expect(results == [.movedAway, .settled, .unchanged, .settled, .unchanged])
    }

    /// 0.15초 간격으로 프레임을 넣는다 (렌즈가 화면이 바뀌는 동안 찍는 간격)
    private func timedChanges(
        _ frames: [ImageFingerprint], tracker: inout ChangeTracker, lastUserAction: Duration? = nil,
        from start: ContinuousClock.Instant = .now
    ) -> [ChangeTracker.Change] {
        frames.enumerated().map { index, frame in
            tracker.observe(
                frame, at: start + .milliseconds(150 * index), lastUserAction: lastUserAction.map { start + $0 })
        }
    }

    /// 영상처럼 찍을 때마다 다른 화면
    private func playing(_ count: Int) throws -> [ImageFingerprint] {
        let frames = try [0, 20, 40].map { shift in try fingerprint(page.map { ($0.0, $0.1 - CGFloat(shift)) }) }
        return (0..<count).map { frames[$0 % frames.count] }
    }

    @Test func processesScreenThatKeepsChangingWithoutWaitingForItToSettle() throws {
        var tracker = ChangeTracker()

        // 0.6초 동안은 바뀌는 중으로 보고 기다린다 → 0.6초에 처리 → 그 뒤 0.25초마다 처리하고 그사이 번역을 숨기지 않는다
        let results = timedChanges(try playing(8), tracker: &tracker)

        #expect(
            results == [
                .movedAway, .movedAway, .movedAway, .movedAway, .keepsChanging, .unchanged, .keepsChanging, .unchanged,
            ])
        #expect(tracker.isKeepingUp)
    }

    @Test func waitsAfterUserActionBeforeProcessingScreenThatKeepsChanging() throws {
        var tracker = ChangeTracker()

        // 0.45초에 마지막으로 스크롤 → 그 뒤 0.6초가 지난 1.05초에 처리
        let results = timedChanges(try playing(9), tracker: &tracker, lastUserAction: .milliseconds(450))

        #expect(Array(results.prefix(7)) == Array(repeating: .movedAway, count: 7))
        #expect(Array(results.suffix(2)) == [.keepsChanging, .unchanged])
    }

    @Test func userActionWhileKeepingUpHidesTranslationsAgain() throws {
        let frames = try playing(6)
        let start = ContinuousClock.now
        var tracker = ChangeTracker()
        _ = timedChanges(Array(frames.prefix(5)), tracker: &tracker, from: start)

        // 0.6초에 처리한 뒤 0.7초에 클릭(링크 이동 등) → 0.75초 프레임은 지난 번역과 맞지 않는다
        let afterAction = tracker.observe(
            frames[5], at: start + .milliseconds(750), lastUserAction: start + .milliseconds(700))

        #expect(afterAction == .movedAway)
        #expect(!tracker.isKeepingUp)
    }

    @Test func keepsUpWhenVideoSceneStaysStillThenChanges() throws {
        let frames = try playing(5)
        var tracker = ChangeTracker()

        // 0.6초에 처리한 뒤 영상 장면이 1.5초 멈췄다가 바뀜(자막 변경 등) → 숨기지 않고 바로 처리한다.
        // 멈췄다고 평소 동작으로 돌아가면 숨긴 채 0.6초를 다시 기다려 원문이 보였다 (TASK-031)
        let results = timedChanges(frames + Array(repeating: frames[4], count: 10) + [frames[0]], tracker: &tracker)

        #expect(results[4] == .keepsChanging)
        #expect(Array(results[5...14]) == Array(repeating: .unchanged, count: 10))
        #expect(results[15] == .keepsChanging)
        #expect(tracker.isKeepingUp)
    }

    @Test func processesPausedFrameWhileKeepingUp() throws {
        let frames = try playing(5)
        let paused = try fingerprint(page.map { ($0.0, $0.1 - 60) })
        var tracker = ChangeTracker()

        // 계속 바뀌던 화면이 새 화면에서 멈추면 간격을 기다리지 않고 바로 처리한다
        let results = timedChanges(frames + [paused, paused], tracker: &tracker)

        #expect(Array(results.suffix(3)) == [.keepsChanging, .unchanged, .settled])
    }

    @Test func resetStartsOver() throws {
        let first = try fingerprint(page)
        var tracker = ChangeTracker()
        _ = changes([first, first], tracker: &tracker)

        tracker.reset()

        #expect(changes([first, first], tracker: &tracker) == [.movedAway, .settled])
    }
}
