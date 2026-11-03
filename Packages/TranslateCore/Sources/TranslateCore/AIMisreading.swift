import NaturalLanguage

/// OCR이 "AI"를 "Al"(소문자 L)로 읽은 것을 앞뒤 글로 판단해 고친다 (TASK-066, 사용자 보고: "AI"가 "알"로 번역됐다).
///
/// SF·Helvetica·Arial은 대문자 I와 소문자 l의 높이가 같고 폭 차이가 글자 크기의 1% 안이라, Vision이 이 글꼴의 "AI"를 늘 "Al"로
/// 읽었다(세리프 글꼴은 맞게 읽었고, 단어 힌트 `customWords`는 효과가 없었다). 로컬 모델은 "Al"을 이름으로 보고 "알"로 옮겼다
/// ("Al" → "알" 5/5, "Generative Al" → "생성형 알고리즘" 5/5). 글자 모양으로는 가릴 수 없으므로:
/// - 소문자 바로 뒤 "Al"("OpenAl", "GenAl", "xAl")은 늘 고친다
/// - 따로 쓴 "Al"도 고친다. 다음 단어가 대문자 + 소문자로 시작하면("Al Gore", "Al-Nassr") 사람·단체 이름으로 보고 둔다.
///   단어마다 대문자로 쓰는 제목("Google Launches New Al Model")에서는 대문자가 이름 표시가 아니므로 고친다
/// - "Al"이 보통 낱말인 언어("Al final del día")와 알루미늄 글("Aluminium (Al)"), 아이디("@Al")에서는 따로 쓴 "Al"을 둔다
///
/// macOS 이름 찾기(`NLTagger` nameType)는 쓰지 않는다: "Al Pacino"를 놓치고 "Al tools"의 "Al"을 사람 이름으로 봤다.
/// 대가: 제목이 아닌 글에서 대문자 단어 앞 "AI"("Use Al Studio", "Al Overviews")는 고치지 못한다
enum AIMisreading {
    /// "Al"이 보통 낱말인 언어 (스페인어·카탈루냐어 a + el, 이탈리아어 a + il, 루마니아어 소유 관사)
    static let languagesUsingAl: Set<NLLanguage> = [.spanish, .catalan, .italian, .romanian]
    /// 언어 판별에서 이 언어들의 확률 합이 이 값 이상이면 그 언어 글로 본다. 가장 높은 언어 하나만 보면 짧은 글이 틀렸다:
    /// "Al"만 있는 글은 루마니아어(0.33), "Al tools"는 카탈루냐어(0.31)가 가장 높다. 합은 "Al" 0.85·"Al tools" 0.64,
    /// "Al final"·"Al revés"·"Al menos" 0.94~0.97, 문장은 1.00
    static let languageShare = 0.9
    /// 제목으로 보는 대문자 단어 비율(이 값 초과)과, 그 판단에 셀 단어(라틴 글자 4개 이상)의 최소 수
    static let titleCaseShare = 0.75
    static let titleCaseMinimumWords = 2

    static func corrected(_ text: String) -> String {
        guard text.contains("Al") else { return text }
        var characters = Array(text)
        // 언어 판별(약 0.4ms)은 따로 쓴 "Al"이 있을 때만 한 번 한다
        var keepsStandalone: Bool?
        for index in characters.indices.dropLast() where characters[index] == "A" && characters[index + 1] == "l" {
            let next = index + 2
            if next < characters.count, isLatinOrDigit(characters[next]) {
                continue
            }
            let before = index > 0 ? characters[index - 1] : nil
            if let before, before.isLowercase, isLatin(before) {
                characters[index + 1] = "I"
                continue
            }
            if let before, isLatinOrDigit(before) || before == "@" {
                continue
            }
            if keepsStandalone == nil {
                keepsStandalone = usesAlAsWord(text)
            }
            if keepsStandalone == false, !startsName(at: next, in: characters) || isTitleCase(text) {
                characters[index + 1] = "I"
            }
        }
        return String(characters)
    }

    /// `index`에 빈칸이나 하이픈이 있고 그 뒤 단어가 대문자 + 소문자로 시작하는지 ("Al Gore", "Al-Nassr")
    private static func startsName(at index: Int, in characters: [Character]) -> Bool {
        guard index + 2 < characters.count, characters[index].isWhitespace || characters[index] == "-" else {
            return false
        }
        let first = characters[index + 1]
        let second = characters[index + 2]
        return isLatin(first) && first.isUppercase && isLatin(second) && second.isLowercase
    }

    /// 단어마다 대문자로 쓰는 제목인지. 짧은 기능어("of", "for", "and")는 제목에서도 소문자라 라틴 글자 4개 이상 단어만 센다
    private static func isTitleCase(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace || $0 == "-" }.map { $0.filter(isLatin) }.filter { $0.count >= 4 }
        guard words.count >= titleCaseMinimumWords else { return false }
        let capitalized = words.filter { $0.first?.isUppercase == true }.count
        return Double(capitalized) > Double(words.count) * titleCaseShare
    }

    private static func usesAlAsWord(_ text: String) -> Bool {
        if text.localizedCaseInsensitiveContains("alumin") {
            return true
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 20)
        return hypotheses.filter { languagesUsingAl.contains($0.key) }.values.reduce(0, +) >= languageShare
    }

    private static func isLatin(_ character: Character) -> Bool {
        LanguageDetection.Script(character) == .latin
    }

    private static func isLatinOrDigit(_ character: Character) -> Bool {
        isLatin(character) || character.isNumber
    }
}
