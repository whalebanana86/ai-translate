import Foundation
import Testing

@testable import TranslateCore

struct AppLanguageTests {
    /// 테스트마다 빈 도메인
    private func makeDefaults() -> (UserDefaults, String) {
        let domain = "AppLanguageTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: domain)!, domain)
    }

    @Test func defaultsToSystemLanguage() {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }

        #expect(AppLanguage.current(in: defaults, domain: domain) == .system)
    }

    @Test func storesChoiceAsAppleLanguagesAndClearsItForSystem() {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }

        AppLanguage.english.apply(to: defaults)
        #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["en"])
        #expect(AppLanguage.current(in: defaults, domain: domain) == .english)

        AppLanguage.korean.apply(to: defaults)
        #expect(AppLanguage.current(in: defaults, domain: domain) == .korean)

        AppLanguage.system.apply(to: defaults)
        #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
        #expect(AppLanguage.current(in: defaults, domain: domain) == .system)
    }

    @Test func readsRegionalCodesFromSystemSettings() {
        // 시스템 설정의 앱별 언어는 지역이 붙은 값으로 저장될 수 있다
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }

        defaults.set(["en-GB"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(in: defaults, domain: domain) == .english)
        defaults.set(["ja"], forKey: "AppleLanguages")
        #expect(AppLanguage.current(in: defaults, domain: domain) == .system)
    }

    @Test func systemLanguagesIgnoreTheAppChoice() {
        let (defaults, domain) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }

        AppLanguage.english.apply(to: defaults)
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"]
        #expect(AppLanguage.systemLanguages(in: defaults) == (global as? [String] ?? Locale.preferredLanguages))
    }
}
