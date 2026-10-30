import Testing

@testable import TranslateCore

struct TranslationEngineTests {
    @Test func keepsStoredRawValues() {
        // UserDefaults에 저장하는 값이므로 바뀌면 사용자 선택이 사라진다
        #expect(TranslationEngine.allCases.map(\.rawValue) == ["claude-code", "codex", "local"])
    }

    @Test func onlyLocalEngineKeepsTextOnDevice() {
        #expect(TranslationEngine.claudeCode.transmissionDestination != nil)
        #expect(TranslationEngine.codex.transmissionDestination != nil)
        #expect(TranslationEngine.local.transmissionDestination == nil)
    }

    @Test func cliEnginesNameTheirExecutables() {
        #expect(TranslationEngine.claudeCode.executableName == "claude")
        #expect(TranslationEngine.codex.executableName == "codex")
        #expect(TranslationEngine.local.executableName == nil)
        #expect(TranslationEngine.codex.knownLocations.contains("~/.volta/bin/codex"))
    }
}
