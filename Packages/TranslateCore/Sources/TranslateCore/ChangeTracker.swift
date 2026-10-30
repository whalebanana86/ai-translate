import CoreGraphics

/// 화면 변화 감지용 축소 지문. 64×64 회색조로 줄여 비교한다.
public struct ImageFingerprint: Equatable, Sendable {
    static let side = 64
    let pixels: [UInt8]

    public init?(_ image: CGImage) {
        var pixels = [UInt8](repeating: 0, count: Self.side * Self.side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: Self.side, height: Self.side, bitsPerComponent: 8,
                    bytesPerRow: Self.side, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
            return true
        }
        guard drawn else { return nil }
        self.pixels = pixels
    }

    /// 픽셀 밝기 차이의 평균 (0~1)
    public func difference(to other: ImageFingerprint) -> Double {
        let total = zip(pixels, other.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(pixels.count) / 255
    }
}

/// 렌즈 아래 화면이 바뀐 뒤 멈췄을 때만 OCR하도록 거르고, 보여주던 번역이 화면과 맞지 않게 됐는지 알려준다.
///
/// 스크롤하는 동안 매번 OCR하지 않고, 같은 화면으로 돌아오면 다시 처리하지 않는다.
public struct ChangeTracker: Sendable {
    /// 프레임 하나를 본 결과
    public enum Change: Equatable, Sendable {
        /// 마지막으로 처리한 화면과 거의 같다. 보여주던 번역이 맞다
        case unchanged
        /// 처리한 화면에서 크게 벗어났다(스크롤 등). 보여주던 번역이 더 이상 맞지 않는다
        case movedAway
        /// 바뀐 뒤 멈췄다. 이 화면을 처리한다
        case settled
    }

    /// 이보다 작은 차이는 같은 화면으로 본다. 측정값(64×64): 4px 스크롤 0.018, 단어 하나 변경 0.0010,
    /// 숫자 한 글자 변경 0.0002 → 스크롤과 단어 변경은 잡고 조회수 같은 숫자 변화는 무시한다
    public static let threshold = 0.0005
    /// 처리한 화면과 이보다 많이 다르면 보여주던 번역을 숨긴다. 스크롤(4px 0.018)은 잡고 단어 하나 변경(0.0010)은
    /// 넘기지 않는다: 단어가 바뀐 문단만 다시 번역하면 되고, 작게 움직이는 광고 등이 있어도 번역이 계속 보이게 한다
    public static let movedAwayThreshold = 0.005

    private var previous: ImageFingerprint?
    private var processed: ImageFingerprint?

    public init() {}

    /// 새 프레임을 받는다. 직전 프레임과 같고(멈춤) 마지막으로 처리한 화면과 다르면 `settled`이며, 이 화면을 처리한 것으로
    /// 기록한다. 아직 아무것도 처리하지 않았으면 보여주던 번역도 없으므로 `movedAway`다.
    public mutating func observe(_ frame: ImageFingerprint) -> Change {
        defer { previous = frame }
        let differsFromProcessed = processed.map { frame.difference(to: $0) >= Self.threshold } ?? true
        if differsFromProcessed, let previous, frame.difference(to: previous) < Self.threshold {
            processed = frame
            return .settled
        }
        let movedAway = processed.map { frame.difference(to: $0) >= Self.movedAwayThreshold } ?? true
        return movedAway ? .movedAway : .unchanged
    }

    /// 렌즈를 옮기거나 크기를 바꾸면 처음부터 다시 본다.
    public mutating func reset() {
        previous = nil
        processed = nil
    }
}
