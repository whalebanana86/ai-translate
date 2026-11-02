import Foundation

/// 앱 화면 언어 (TASK-058). 시스템 설정을 따르거나(기본) 한국어·영어로 고정한다. 번역 대상 언어(`TargetLanguage`)와는 다르다.
///
/// macOS 앱별 언어(시스템 설정 > 일반 > 언어 및 지역 > 앱)와 같은 값, 앱 도메인의 `AppleLanguages`를 쓴다.
/// 화면 글은 앱이 시작할 때 정해지므로 바꾸면 다시 시작해야 적용된다
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case korean = "ko"
    case english = "en"

    public var id: String { rawValue }

    static let defaultsKey = "AppleLanguages"

    /// 앱 도메인(`domain`)에 저장된 언어. 전역 값(시스템 언어)은 보지 않는다
    public static func current(in defaults: UserDefaults, domain: String) -> AppLanguage {
        guard let first = (defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String])?.first else {
            return .system
        }
        let code = Locale.Language(identifier: first).languageCode?.identifier
        return allCases.first { $0 != .system && $0.rawValue == code } ?? .system
    }

    public func apply(to defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set([rawValue], forKey: Self.defaultsKey)
        }
    }

    /// 시스템 선호 언어. 앱 언어를 고정하면 `Locale.preferredLanguages`가 그 언어만 돌려주므로 전역 값을 읽는다
    /// (번역 대상 언어 기본값은 앱 언어가 아니라 시스템 언어를 따른다)
    public static func systemLanguages(in defaults: UserDefaults = .standard) -> [String] {
        defaults.persistentDomain(forName: UserDefaults.globalDomain)?[defaultsKey] as? [String]
            ?? Locale.preferredLanguages
    }
}
