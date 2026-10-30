/// 이미 번역한 문단을 기억한다. 렌즈 아래를 스크롤해도 본 문단은 엔진을 다시 부르지 않는다.
public struct TranslationMemory: Sendable {
    private struct Key: Hashable, Sendable {
        var text: String
        var language: TargetLanguage
    }

    public let capacity: Int
    private var entries: [Key: String] = [:]
    /// 오래된 것부터. 용량을 넘으면 앞에서부터 지운다
    private var order: [Key] = []

    public init(capacity: Int = 500) {
        self.capacity = capacity
    }

    public func translation(of text: String, in language: TargetLanguage) -> String? {
        entries[Key(text: text, language: language)]
    }

    public mutating func store(_ translation: String, of text: String, in language: TargetLanguage) {
        let key = Key(text: text, language: language)
        if entries.updateValue(translation, forKey: key) == nil {
            order.append(key)
        }
        while order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    /// 번역해야 하는데 아직 기억에 없는 문단. 같은 글은 하나만 돌려준다.
    public func missing(in blocks: [TextBlock], for language: TargetLanguage) -> [TextBlock] {
        var seen = Set<String>()
        return blocks.filter { block in
            block.isTranslatable && translation(of: block.text, in: language) == nil && seen.insert(block.text).inserted
        }
    }

    /// 렌즈에 보여줄 문단 상태.
    public func content(of block: TextBlock, in language: TargetLanguage) -> BlockContent {
        guard block.isTranslatable else { return .original(block.text) }
        return translation(of: block.text, in: language).map { .translated($0) } ?? .pending
    }
}

/// 렌즈에 보여줄 문단 상태.
public enum BlockContent: Equatable, Sendable {
    /// 번역됨. 원문 자리에 번역을 그린다
    case translated(String)
    /// 번역을 기다리는 중. 그리지 않아 원문이 그대로 보인다
    case pending
    /// 숫자·기호처럼 번역할 필요가 없다. 그리지 않고 복사할 때만 원문을 넣는다
    case original(String)
}
