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
        _ frames: [ImageFingerprint], tracker: inout ChangeTracker, lastScroll: Duration? = nil,
        from start: ContinuousClock.Instant = .now
    ) -> [ChangeTracker.Change] {
        frames.enumerated().map { index, frame in
            tracker.observe(frame, at: start + .milliseconds(150 * index), lastScroll: lastScroll.map { start + $0 })
        }
    }

    /// 영상처럼 찍을 때마다 다른 화면
    private func playing(_ count: Int) throws -> [ImageFingerprint] {
        let frames = [try fingerprint(page), try fingerprint(page.map { ($0.0, $0.1 - 20) })]
        return (0..<count).map { frames[$0 % 2] }
    }

    @Test func processesScreenThatKeepsChangingWithoutWaitingForItToSettle() throws {
        var tracker = ChangeTracker()

        // 0.6초 동안은 바뀌는 중으로 보고 기다린다 → 0.6초에 처리 → 그 뒤 0.4초마다 처리하고 그사이 번역을 숨기지 않는다
        let results = timedChanges(try playing(8), tracker: &tracker)

        #expect(
            results == [
                .movedAway, .movedAway, .movedAway, .movedAway, .keepsChanging, .unchanged, .unchanged, .keepsChanging,
            ])
        #expect(tracker.isKeepingUp)
    }

    @Test func waitsUntilScrollingStopsBeforeProcessingScreenThatKeepsChanging() throws {
        var tracker = ChangeTracker()

        // 0.45초에 마지막으로 스크롤 → 그 뒤 0.6초가 지난 1.05초에 처리
        let results = timedChanges(try playing(9), tracker: &tracker, lastScroll: .milliseconds(450))

        #expect(Array(results.prefix(7)) == Array(repeating: .movedAway, count: 7))
        #expect(Array(results.suffix(2)) == [.keepsChanging, .unchanged])
    }

    @Test func scrollingWhileKeepingUpHidesTranslationsAgain() throws {
        let frames = try playing(6)
        let start = ContinuousClock.now
        var tracker = ChangeTracker()
        _ = timedChanges(Array(frames.prefix(5)), tracker: &tracker, from: start)

        // 0.6초에 처리한 뒤 0.7초에 스크롤 → 0.75초 프레임은 지난 번역과 맞지 않는다
        let afterScroll = tracker.observe(
            frames[5], at: start + .milliseconds(750), lastScroll: start + .milliseconds(700))

        #expect(afterScroll == .movedAway)
        #expect(!tracker.isKeepingUp)
    }

    @Test func returnsToWaitingForStillScreenOnceScreenStopsChanging() throws {
        let frames = try playing(5)
        var tracker = ChangeTracker()

        // 0.6초에 처리한 화면에서 영상이 멈춤 → 0.6초 동안 멈춰 있으면 평소대로 바뀌면 숨긴다
        let results = timedChanges(frames + Array(repeating: frames[4], count: 5) + [frames[1]], tracker: &tracker)

        #expect(results[4] == .keepsChanging)
        #expect(Array(results[5...9]) == Array(repeating: .unchanged, count: 5))
        #expect(results[10] == .movedAway)
        #expect(!tracker.isKeepingUp)
    }

    @Test func processesPausedFrameWhileKeepingUp() throws {
        let frames = try playing(5)
        let paused = try fingerprint(page.map { ($0.0, $0.1 - 40) })
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
