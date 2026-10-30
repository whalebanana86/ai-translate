import Testing

@testable import TranslateCore

struct TranslationSchedulingTests {
    @Test func abandonsRequestWhenScreenMovedPastIt() {
        #expect(TranslationScheduling.shouldAbandon(inFlight: ["a", "b", "c"], visible: ["x", "y"]))
        // 셋 중 하나만 남음
        #expect(TranslationScheduling.shouldAbandon(inFlight: ["a", "b", "c"], visible: ["c", "x"]))
    }

    @Test func keepsRequestWhileMostOfItIsVisible() {
        #expect(!TranslationScheduling.shouldAbandon(inFlight: ["a", "b"], visible: ["b", "x"]))
        #expect(!TranslationScheduling.shouldAbandon(inFlight: ["a", "b", "c"], visible: ["a", "b", "c"]))
    }

    @Test func keepsNothingWhenNoRequest() {
        #expect(!TranslationScheduling.shouldAbandon(inFlight: [], visible: ["a"]))
    }
}
