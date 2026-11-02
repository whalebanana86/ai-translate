/// 계속 바뀌는 화면(영상 자막)에서 글이 다 나온 뒤 번역하도록 번역할 문단을 고른다.
///
/// 자동 생성 자막은 단어가 하나씩 붙어, 바뀔 때마다 번역하면 문장 조각을 번역한다. 글이 `settleTime` 넘게 그대로인 문단만
/// 보내고, 말이 쉬지 않고 이어져 글이 계속 바뀌면 `maxWait`마다 그때까지 나온 글을 보낸다.
public struct TextSettling: Sendable {
    /// 글이 이만큼 넘게 그대로면 다 나온 것으로 본다. 인식은 약 0.35초마다라 실제로는 0.5~0.7초 뒤 번역한다
    public static let settleTime: Duration = .milliseconds(500)
    /// 다 나온 문단 없이 이만큼 기다렸으면 그때까지 나온 글을 보낸다
    public static let maxWait: Duration = .seconds(2)

    /// 지금 보이는 글이 처음 보인 때
    private var firstSeen: [String: ContinuousClock.Instant] = [:]
    /// 번역할 문단이 다 나오기를 기다리기 시작한 때
    private var waitingSince: ContinuousClock.Instant?

    public init() {}

    /// 인식할 때마다 지금 보이는 문단 글을 알린다. 보이지 않게 된 글은 잊는다 (다시 보이면 처음부터 잰다)
    public mutating func observe(_ texts: [String], at now: ContinuousClock.Instant) {
        var seen: [String: ContinuousClock.Instant] = [:]
        for text in texts {
            seen[text] = firstSeen[text] ?? now
        }
        firstSeen = seen
    }

    /// 번역할 문단을 고른다. 기다리는 동안 그 자리에 이어 보여줄 지난 번역이 없는 문단(`isCovered`가 false: 자막 사이 빈 구간
    /// 뒤 첫 자막, 렌즈를 띄운 뒤 첫 자막)은 기다려 봐야 원문만 보이므로 바로 고른다(TASK-039). 가려진 문단은 다 나온 것만,
    /// 다 나온 것이 없으면 기다린 지 `maxWait`가 지났을 때 모두. 고른 문단이 있으면 기다림을 끝내고 다음 문단부터 다시 기다린다.
    public mutating func ready<Element>(
        _ missing: [Element], text: (Element) -> String, isCovered: (Element) -> Bool = { _ in true },
        at now: ContinuousClock.Instant
    ) -> [Element] {
        let uncovered = missing.filter { !isCovered($0) }
        let covered = missing.filter(isCovered)
        guard !covered.isEmpty else {
            waitingSince = nil
            return uncovered
        }
        let settled = covered.filter { element in
            firstSeen[text(element)].map { now - $0 > Self.settleTime } ?? false
        }
        let waitStart = waitingSince ?? now
        guard !settled.isEmpty || now - waitStart >= Self.maxWait else {
            waitingSince = waitStart
            return uncovered
        }
        waitingSince = nil
        return uncovered + (settled.isEmpty ? covered : settled)
    }

    /// 평소 화면으로 돌아가면(스크롤 등) 기억을 지운다
    public mutating func reset() {
        firstSeen = [:]
        waitingSince = nil
    }
}
