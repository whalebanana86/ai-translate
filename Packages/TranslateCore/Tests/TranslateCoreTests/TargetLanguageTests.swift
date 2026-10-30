import Testing

@testable import TranslateCore

struct TargetLanguageTests {
    @Test(arguments: [
        (["ko-KR"], TargetLanguage.korean),
        (["fr-CA", "en-US"], .french),
        (["it-IT", "ja-JP"], .japanese),
        (["zh-Hans-CN"], .simplifiedChinese),
        (["zh-CN"], .simplifiedChinese),
        (["zh-Hant-TW"], .traditionalChinese),
        (["zh-TW"], .traditionalChinese),
        (["zh-HK"], .traditionalChinese),
        (["it-IT"], .english),
        ([], .english),
    ])
    func picksFirstSupportedPreferredLanguage(identifiers: [String], expected: TargetLanguage) {
        #expect(TargetLanguage.preferred(from: identifiers) == expected)
    }

    @Test func everyLanguageHasPromptAndDisplayNames() {
        for language in TargetLanguage.allCases {
            #expect(!language.promptName.isEmpty)
            #expect(!language.displayName.isEmpty)
        }
        #expect(TargetLanguage.korean.promptName == "Korean")
        #expect(TargetLanguage.korean.displayName == "한국어")
    }
}
