import Testing

@testable import TranslateCore

struct CaptureScheduleTests {
    private let now = ContinuousClock.now

    @Test func capturesRightAfterScrollingStops() {
        let delay = CaptureSchedule.delay(isChanging: true, lastScroll: now - .milliseconds(50), now: now)

        #expect(delay == .milliseconds(100))
    }

    @Test func keepsMinimumDelayAtScrollQuietBoundary() {
        let delay = CaptureSchedule.delay(isChanging: false, lastScroll: now - .milliseconds(149), now: now)

        #expect(delay == .milliseconds(20))
    }

    @Test func capturesOftenWhileScreenIsChanging() {
        #expect(CaptureSchedule.delay(isChanging: true, lastScroll: nil, now: now) == .milliseconds(150))
        // 스크롤이 멈춘 지 오래됐으면 스크롤은 따지지 않는다
        #expect(
            CaptureSchedule.delay(isChanging: true, lastScroll: now - .seconds(2), now: now) == .milliseconds(150))
    }

    @Test func capturesSlowlyWhenIdle() {
        #expect(CaptureSchedule.delay(isChanging: false, lastScroll: nil, now: now) == .milliseconds(500))
    }
}
