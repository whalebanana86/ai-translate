import Foundation
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

    @Test func sendsTopParagraphsFirstOnNewScreen() {
        let missing = ["a", "b", "c", "d", "e"]

        #expect(
            TranslationScheduling.batch(
                missing, hasVisibleTranslation: false, preferredBatchSize: nil, firstBatchSize: 3) == ["a", "b", "c"])
        // 이미 보이는 번역이 있으면 남은 문단을 한 번에
        #expect(
            TranslationScheduling.batch(
                missing, hasVisibleTranslation: true, preferredBatchSize: nil, firstBatchSize: 3)
                == missing)
    }

    @Test func followsEngineBatchSizeAndDefaults() {
        let missing = ["a", "b", "c"]

        #expect(
            TranslationScheduling.batch(missing, hasVisibleTranslation: false, preferredBatchSize: 1, firstBatchSize: 3)
                == ["a"])
        #expect(
            TranslationScheduling.batch(
                missing, hasVisibleTranslation: false, preferredBatchSize: nil, firstBatchSize: nil) == missing)
    }

    @Test func claudeSplitsButCodexDoesNot() {
        #expect(ClaudeCodeProvider(executable: URL(fileURLWithPath: "/bin/echo")).firstBatchSize == 3)
        #expect(CodexProvider(executable: URL(fileURLWithPath: "/bin/echo")).firstBatchSize == nil)
    }
}
