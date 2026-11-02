import CoreGraphics

/// 영상 자막의 자리. 번역을 이 자리의 가운데·아래 끝에, 이 줄 높이에 맞는 글자 크기로 그린다. 이미지 픽셀 좌표
public struct CaptionAnchor: Equatable, Sendable {
    public var centerX: CGFloat
    public var bottom: CGFloat
    public var lineHeight: CGFloat

    public init(centerX: CGFloat, bottom: CGFloat, lineHeight: CGFloat) {
        self.centerX = centerX
        self.bottom = bottom
        self.lineHeight = lineHeight
    }
}

/// 영상 자막처럼 가운데 정렬된 문단을 찾고, 자막마다 번역을 그릴 자리를 정한다.
///
/// 자막은 문장마다 너비가 달라 왼쪽 끝이 움직이고, 한 줄·두 줄이 바뀌면 위쪽 끝이 움직인다. 번역을 원문의 왼쪽 위에 맞춰 그리면
/// 자막이 바뀔 때마다 번역이 흔들리므로, 이런 문단은 번역을 가운데·아래 끝에 맞춘다(TASK-035). 그 자리와 줄 높이도 인식할 때마다
/// 조금씩 달라(상자 가장자리, 아래로 내려가는 글자) 번역이 흔들렸으므로, 같은 자리의 작은 차이는 기억한 값을 그대로 쓴다(TASK-038).
/// 계속 바뀌는 화면(영상)에서만 쓴다.
public struct CaptionDetector: Sendable {
    /// 기억하는 자막 자리 수
    static let maxAnchors = 4
    /// 기억한 자리와 가운데·아래 끝 차이가 줄 높이의 이 배수 이하면 기억한 값을 쓴다. 인식마다 상자 가장자리가 수 px 다르고,
    /// 아래로 내려가는 글자(g, y, p)가 있으면 아래 끝이 줄 높이의 약 0.2배 내려간다
    static let jitterRatio: CGFloat = 0.35
    /// 줄 높이가 기억한 값의 이 범위 안이면 기억한 값을 쓴다 (아래로 내려가는 글자 차이 약 20%는 흡수, 전체 화면 전환 등은 반영)
    static let lineHeightRange: ClosedRange<CGFloat> = 0.75...1.25

    private var anchors: [CaptionAnchor] = []
    private var previous: [TextBlock] = []

    public init() {}

    /// 새로 인식한 문단마다 가운데 정렬 자막이면 그 자리를, 아니면 nil을 돌려준다.
    /// - 두 줄 이상: 줄마다 가운데가 문단 가운데와 맞고 왼쪽 끝은 다르다
    /// - 한 줄: 직전 인식의 같은 자리 문단과 글이 다르고, 가운데는 같은데 왼쪽 끝이 다르다
    /// - 그렇게 찾은 자리(가운데·아래 끝)에 나온 다음 문단도 자막으로 본다
    public mutating func detect(_ blocks: [TextBlock]) -> [CaptionAnchor?] {
        let result = blocks.map { block -> CaptionAnchor? in
            let lineHeight = block.lines.map(\.boundingBox.height).max() ?? 0
            let tolerance = max(lineHeight * 0.6, 4)
            let box = block.boundingBox
            if let index = anchors.firstIndex(where: { Self.matches($0, box, tolerance: tolerance) }) {
                anchors[index] = Self.settled(anchors[index], box: box, lineHeight: lineHeight)
                return anchors[index]
            }
            guard hasCenteredLines(block, tolerance: tolerance) || changedAroundSameCenter(block, tolerance: tolerance)
            else { return nil }
            let anchor = CaptionAnchor(centerX: box.midX, bottom: box.maxY, lineHeight: lineHeight)
            anchors = Array((anchors + [anchor]).suffix(Self.maxAnchors))
            return anchor
        }
        previous = blocks
        return result
    }

    /// 평소 화면으로 돌아가면(스크롤 등) 잊는다
    public mutating func reset() {
        anchors = []
        previous = []
    }

    /// 기억한 자리를 이번 상자에 맞춘다. 작은 차이는 기억한 값을 그대로 둔다
    private static func settled(_ anchor: CaptionAnchor, box: CGRect, lineHeight: CGFloat) -> CaptionAnchor {
        var settled = anchor
        let jitter = anchor.lineHeight * jitterRatio
        if abs(box.midX - anchor.centerX) > jitter {
            settled.centerX = box.midX
        }
        if abs(box.maxY - anchor.bottom) > jitter {
            settled.bottom = box.maxY
        }
        if anchor.lineHeight > 0, !lineHeightRange.contains(lineHeight / anchor.lineHeight) {
            settled.lineHeight = lineHeight
        }
        return settled
    }

    private func hasCenteredLines(_ block: TextBlock, tolerance: CGFloat) -> Bool {
        let lines = block.lines.map(\.boundingBox)
        guard lines.count >= 2, let minLeft = lines.map(\.minX).min(), let maxLeft = lines.map(\.minX).max() else {
            return false
        }
        let centerX = block.boundingBox.midX
        return lines.allSatisfy { abs($0.midX - centerX) <= tolerance } && maxLeft - minLeft > tolerance
    }

    private func changedAroundSameCenter(_ block: TextBlock, tolerance: CGFloat) -> Bool {
        let box = block.boundingBox
        return previous.contains { other in
            let spot = CaptionAnchor(centerX: other.boundingBox.midX, bottom: other.boundingBox.maxY, lineHeight: 0)
            return other.text != block.text && abs(other.boundingBox.minX - box.minX) > tolerance
                && Self.matches(spot, box, tolerance: tolerance)
        }
    }

    /// 가운데가 같고 아래 끝이 줄 높이의 3배(허용 차이의 5배) 안이면 같은 자리. 유튜브는 재생 막대가 나타나면 자막을 줄 높이의
    /// 2배 남짓 올린다 (화면 기록 28.6초, TASK-038)
    private static func matches(_ anchor: CaptionAnchor, _ box: CGRect, tolerance: CGFloat) -> Bool {
        abs(anchor.centerX - box.midX) <= tolerance && abs(anchor.bottom - box.maxY) <= tolerance * 5
    }
}
