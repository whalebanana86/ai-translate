import CoreGraphics

/// 계속 바뀌는 화면(영상 자막)에서 새 문단의 번역이 나올 때까지, 같은 자리에 보이던 번역을 이어서 보여준다.
///
/// 자막은 문장이 바뀌거나(직접 올린 자막) 단어가 하나씩 붙어(자동 생성 자막) 0.3~3초마다 글이 바뀐다. 글이 바뀔 때마다
/// 번역 전으로 돌아가면 원문이 드러났다가 번역이 다시 나타나기를 되풀이한다.
public struct CarryOver: Sendable {
    /// 화면의 원문과 맞는 번역을 마지막으로 보여준 뒤 이만큼 지나면 더 이어 보여주지 않는다.
    /// 엔진이 자막보다 느리면(CLI 엔진) 지난 자막의 번역이 계속 남지 않게 한다. 자막이 다 나오기를 최대 2초 기다리고
    /// 번역에 약 0.35초가 더 걸리므로(`TextSettling`) 그동안 원문이 드러나지 않게 3초로 둔다
    public static let lifetime: Duration = .seconds(3)

    private struct Shown {
        /// 원문 문단 영역. 이미지 픽셀 좌표
        var box: CGRect
        var translation: String
        /// 이 번역이 화면의 원문과 맞았던 마지막 때
        var matchedAt: ContinuousClock.Instant
    }

    private var shown: [Shown] = []

    public init() {}

    /// 문단마다 보여줄 내용을 정한다. 번역을 기다리는 문단은 지난번에 보여준 번역 가운데 같은 자리에 있던 것을 이어 보여준다.
    /// 지난번 번역 하나는 문단 하나에만 쓰고, 겹치는 넓이가 큰 짝부터 정한다. 이번에 보여준 번역을 다음번을 위해 기억한다.
    ///
    /// - Parameters:
    ///   - contents: `boxes`와 같은 순서의 문단 상태
    ///   - boxes: 문단 영역 (이미지 픽셀 좌표)
    public mutating func apply(
        to contents: [BlockContent], boxes: [CGRect], at now: ContinuousClock.Instant
    ) -> [BlockContent] {
        let candidates = shown.filter { now - $0.matchedAt <= Self.lifetime }
        var carried: [Int: Shown] = [:]
        var used = Set<Int>()
        for pair in Self.overlaps(of: contents, boxes: boxes, with: candidates)
        where carried[pair.block] == nil && !used.contains(pair.candidate) {
            carried[pair.block] = candidates[pair.candidate]
            used.insert(pair.candidate)
        }

        var next: [Shown] = []
        let result = zip(contents, boxes).enumerated().map { index, item -> BlockContent in
            let (content, box) = item
            if case .translated(let translation) = content {
                next.append(Shown(box: box, translation: translation, matchedAt: now))
                return content
            }
            guard let previous = carried[index] else { return content }
            next.append(Shown(box: box, translation: previous.translation, matchedAt: previous.matchedAt))
            return .translated(previous.translation)
        }
        shown = next
        return result
    }

    /// 화면이 평소처럼 바뀌었거나(스크롤 등) 언어·엔진이 바뀌면 지난 번역을 잇지 않는다
    public mutating func reset() {
        shown = []
    }

    /// 번역을 기다리는 문단과 지난번 번역의 짝 가운데 세로로 작은 쪽 높이의 절반 이상 겹치는 것. 겹치는 넓이가 큰 순서
    private static func overlaps(
        of contents: [BlockContent], boxes: [CGRect], with candidates: [Shown]
    ) -> [(block: Int, candidate: Int)] {
        var pairs: [(block: Int, candidate: Int, area: CGFloat)] = []
        for (block, item) in zip(contents, boxes).enumerated() where item.0 == .pending {
            for (candidate, other) in candidates.enumerated() {
                let overlap = item.1.intersection(other.box)
                guard !overlap.isNull, overlap.width > 0, overlap.height >= min(item.1.height, other.box.height) * 0.5
                else { continue }
                pairs.append((block, candidate, overlap.width * overlap.height))
            }
        }
        return pairs.sorted { $0.area > $1.area }.map { ($0.block, $0.candidate) }
    }
}
