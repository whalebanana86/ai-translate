import NaturalLanguage
import Synchronization

/// 이미 대상 언어로 쓰인 글인지 판단한다. 그런 문단은 엔진에 보내지 않고 원문을 그대로 보여준다.
///
/// 한국어 유튜브 화면은 댓글마다 "@아이디 1년 전", "답글 4개", "자세히 알아보기"까지 하나씩 엔진에 보내 본문 번역이 그만큼 늦게
/// 나왔다(TASK-045). 잘못 건너뛰면 외국어가 번역되지 않은 채 남으므로 확실할 때만 대상 언어로 본다 (반대로 틀리면 엔진을 한 번 더
/// 부를 뿐이다).
/// - 아이디("@이름")는 빼고 본다: 아이디가 섞이면 판별이 흔들렸다("@ JetpackGamer456 6년 전(수정됨)" → 영어 0.21)
/// - 대상 언어 문자가 아닌 글자가 `maxForeignShare` 이하: 판별기는 "정말 좋은 노래네요 I love it"도 한국어 1.00으로 본다.
///   글자 하나짜리 다른 문자 단어(아이콘을 잘못 읽은 "V")는 세지 않는다
/// - macOS 언어 판별(`NLLanguageRecognizer`)이 대상 언어일 확률이 `minimumConfidence` 이상. 한·중·일은 짧아도 1.00이고
///   간체·번체를 가린다. 라틴 문자 언어는 문장만 확실하다("Reply" → 영어 0.22)
public enum LanguageDetection {
    static let minimumConfidence = 0.9
    static let maxForeignShare = 0.25
    /// 기억하는 판단 수. 넘으면 비운다
    static let cacheLimit = 2000

    private struct Key: Hashable, Sendable {
        var text: String
        var language: TargetLanguage
    }

    /// 판별기는 한 번에 약 0.4ms라, 번역이 흘러나오는 동안 0.05초마다 다시 그릴 때마다 부르면 무겁다
    private static let cache = Mutex<[Key: Bool]>([:])

    public static func isWritten(_ text: String, in language: TargetLanguage) -> Bool {
        let key = Key(text: text, language: language)
        if let known = cache.withLock({ $0[key] }) {
            return known
        }
        let result = judge(text, in: language)
        cache.withLock { cache in
            if cache.count >= cacheLimit {
                cache.removeAll()
            }
            cache[key] = result
        }
        return result
    }

    private static func judge(_ text: String, in language: TargetLanguage) -> Bool {
        let words = withoutHandles(text)
        let scripts = language.scripts
        var native = 0
        var foreign = 0
        for word in words {
            let letters = word.filter(\.isLetter).map(Script.init)
            let foreignLetters = letters.filter { !scripts.contains($0) }.count
            native += letters.count - foreignLetters
            if letters.count >= 2 {
                foreign += foreignLetters
            }
        }
        guard native > 0, Double(foreign) <= Double(native + foreign) * maxForeignShare else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(words.joined(separator: " "))
        let confidence = recognizer.languageHypotheses(withMaximum: 3)[language.naturalLanguage] ?? 0
        return confidence >= minimumConfidence
    }

    /// "@이름" 단어와, OCR이 "@" 뒤를 띄어 읽은 "@ 이름"의 다음 단어를 뺀다
    private static func withoutHandles(_ text: String) -> [Substring] {
        var words: [Substring] = []
        var skipsNext = false
        for word in text.split(whereSeparator: \.isWhitespace) {
            if skipsNext {
                skipsNext = false
            } else if word.hasPrefix("@") {
                skipsNext = word == "@"
            } else {
                words.append(word)
            }
        }
        return words
    }

    enum Script {
        case hangul, kana, han, latin, other

        init(_ character: Character) {
            switch character.unicodeScalars.first?.value ?? 0 {
            case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F: self = .hangul
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: self = .kana
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: self = .han
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: self = .latin
            default: self = .other
            }
        }
    }
}

extension TargetLanguage {
    /// 이 언어를 쓰는 문자
    var scripts: Set<LanguageDetection.Script> {
        switch self {
        case .korean: [.hangul]
        case .japanese: [.kana, .han]
        case .simplifiedChinese, .traditionalChinese: [.han]
        case .english, .spanish, .french, .german: [.latin]
        }
    }

    var naturalLanguage: NLLanguage {
        switch self {
        case .korean: .korean
        case .english: .english
        case .japanese: .japanese
        case .simplifiedChinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        case .spanish: .spanish
        case .french: .french
        case .german: .german
        }
    }
}

extension TextBlock {
    /// 엔진에 보내 번역할 문단인지: 번역할 글자가 있고(`isTranslatable`) 이미 대상 언어로 쓰여 있지 않다
    public func needsTranslation(to language: TargetLanguage) -> Bool {
        isTranslatable && !LanguageDetection.isWritten(text, in: language)
    }
}
