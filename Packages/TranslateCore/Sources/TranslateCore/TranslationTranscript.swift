/// 렌즈가 번역해 보여준 글을 나온 순서대로 모은 기록. 영상을 보며 지나간 자막의 번역을 렌즈 옆에서 다시 읽는다.
///
/// 메모리에만 두고 렌즈를 닫으면 사라진다 (파일로 저장하지 않는다).
public struct TranslationTranscript: Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: Int
        public var source: String
        public var translation: String
    }

    /// 이보다 많으면 오래된 기록부터 지운다
    public static let capacity = 300

    public private(set) var entries: [Entry] = []
    private var nextID = 0
    /// `entries`와 같은 순서의 비교용 원문(언어 + 글자·숫자만 소문자로)
    private var keys: [String] = []

    public init() {}

    /// 복사할 글. 번역을 나온 순서대로 줄바꿈으로 잇는다
    public var text: String {
        entries.map(\.translation).joined(separator: "\n")
    }

    /// 화면의 원문과 맞는 번역을 기록한다. 이미 기록한 원문(대소문자·문장부호·공백 무시)은 넘긴다.
    /// 자동 생성 자막처럼 바로 앞 기록의 원문 뒤에 글이 이어 붙었으면 앞 기록을 바꾸고, 앞 기록 원문의 앞부분만 다시 보이면 넘긴다.
    /// - Returns: 기록이 바뀌었는지
    @discardableResult
    public mutating func record(source: String, translation: String, in language: TargetLanguage) -> Bool {
        let key = Self.key(source, in: language)
        guard !key.isEmpty, !keys.contains(key) else { return false }
        if let lastKey = keys.last {
            if lastKey.hasPrefix(key) {
                return false
            }
            if key.hasPrefix(lastKey) {
                keys[keys.count - 1] = key
                entries[entries.count - 1].source = source
                entries[entries.count - 1].translation = translation
                return true
            }
        }
        keys.append(key)
        entries.append(Entry(id: nextID, source: source, translation: translation))
        nextID += 1
        if entries.count > Self.capacity {
            keys.removeFirst()
            entries.removeFirst()
        }
        return true
    }

    private static func key(_ source: String, in language: TargetLanguage) -> String {
        let kept = source.lowercased().unicodeScalars.filter {
            $0.properties.isAlphabetic || $0.properties.numericType != nil
        }
        guard !kept.isEmpty else { return "" }
        return language.rawValue + "|" + String(String.UnicodeScalarView(kept))
    }
}
