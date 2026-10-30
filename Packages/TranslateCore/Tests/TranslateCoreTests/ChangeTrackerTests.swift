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

    @Test func resetStartsOver() throws {
        let first = try fingerprint(page)
        var tracker = ChangeTracker()
        _ = changes([first, first], tracker: &tracker)

        tracker.reset()

        #expect(changes([first, first], tracker: &tracker) == [.movedAway, .settled])
    }
}
