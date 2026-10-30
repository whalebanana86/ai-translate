import Foundation

/// 번역 대상 언어.
public enum TargetLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case korean = "ko"
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    public var id: String { rawValue }

    /// 모델에 보내는 영어 이름
    public var promptName: String {
        switch self {
        case .korean: "Korean"
        case .english: "English"
        case .japanese: "Japanese"
        case .simplifiedChinese: "Simplified Chinese"
        case .traditionalChinese: "Traditional Chinese"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }

    /// 화면에 보이는 자국어 이름
    public var displayName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        case .japanese: "日本語"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        }
    }

    /// 선호 언어 목록(`Locale.preferredLanguages` 형식)에서 처음으로 지원하는 언어. 없으면 영어.
    public static func preferred(from identifiers: [String]) -> TargetLanguage {
        for identifier in identifiers {
            let language = Locale.Language(identifier: identifier)
            guard let code = language.languageCode?.identifier else { continue }
            if code == "zh" {
                // 스크립트가 없으면 지역으로 추정한다 (zh-TW, zh-HK → 번체)
                return language.maximalIdentifier.contains("-Hant") ? .traditionalChinese : .simplifiedChinese
            }
            if let match = allCases.first(where: { $0.rawValue == code }) {
                return match
            }
        }
        return .english
    }
}
