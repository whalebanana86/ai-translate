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
/// 영상처럼 멈추지 않는 화면은 잠시 기다린 뒤 바뀌는 중에도 일정 간격으로 처리한다.
public struct ChangeTracker: Sendable {
    /// 프레임 하나를 본 결과
    public enum Change: Equatable, Sendable {
        /// 마지막으로 처리한 화면과 거의 같다. 보여주던 번역이 맞다
        case unchanged
        /// 처리한 화면에서 크게 벗어났다(스크롤 등). 보여주던 번역이 더 이상 맞지 않는다
        case movedAway
        /// 바뀐 뒤 멈췄다. 이 화면을 처리한다
        case settled
        /// 영상처럼 멈추지 않고 계속 바뀐다. 멈추기를 기다리지 않고 이 화면을 처리한다
        case keepsChanging
    }

    /// 이보다 작은 차이는 같은 화면으로 본다. 측정값(64×64): 4px 스크롤 0.018, 단어 하나 변경 0.0010,
    /// 숫자 한 글자 변경 0.0002 → 스크롤과 단어 변경은 잡고 조회수 같은 숫자 변화는 무시한다
    public static let threshold = 0.0005
    /// 처리한 화면과 이보다 많이 다르면 보여주던 번역을 숨긴다. 스크롤(4px 0.018)은 잡고 단어 하나 변경(0.0010)은
    /// 넘기지 않는다: 단어가 바뀐 문단만 다시 번역하면 되고, 작게 움직이는 광고 등이 있어도 번역이 계속 보이게 한다
    public static let movedAwayThreshold = 0.005
    /// 사용자 동작 없이 이만큼 계속 바뀌면 멈추지 않는 화면(영상·움직이는 광고)으로 본다. 스크롤은 이벤트로 따로 기다리므로
    /// 마지막 사용자 동작 뒤부터 잰다
    public static let keepsChangingAfter: Duration = .milliseconds(600)
    /// 계속 바뀌는 화면을 다시 처리하는 간격. 자막처럼 글이 바뀌면 이 간격 안에 다시 인식한다.
    /// 0.4초에서는 주기가 약 0.5초라 자막이 바뀐 뒤 알아채기까지 원문이 보였다 (TASK-031)
    public static let keepsChangingInterval: Duration = .milliseconds(250)

    private var previous: ImageFingerprint?
    private var processed: ImageFingerprint?
    /// 프레임이 직전 프레임과 계속 다르기 시작한 때
    private var changingSince: ContinuousClock.Instant?
    /// 계속 바뀌는 화면을 마지막으로 처리한 때. 그 뒤 사용자 동작이 있으면 지운다
    private var lastKeptUp: ContinuousClock.Instant?

    public init() {}

    /// 계속 바뀌는 화면을 따라 처리하는 중인지. 이때는 화면이 바뀌어도 다음 처리까지 보여주던 번역을 그대로 둔다
    public var isKeepingUp: Bool { lastKeptUp != nil }

    /// 새 프레임을 받는다. 직전 프레임과 같고(멈춤) 마지막으로 처리한 화면과 다르면 `settled`이며, 이 화면을 처리한 것으로
    /// 기록한다. 아직 아무것도 처리하지 않았으면 보여주던 번역도 없으므로 `movedAway`다.
    /// 사용자 동작 없이 `keepsChangingAfter` 동안 멈추지 않으면 `keepsChanging`으로 처리하고, 그 뒤로는
    /// `keepsChangingInterval`마다 처리한다. 영상 장면이 멈췄다 다시 움직여도(자막만 바뀌는 장면 등) 이 판단을 유지한다.
    ///
    /// - Parameter lastUserAction: 화면이 다른 내용으로 바뀌었을 수 있는 마지막 사용자 동작(스크롤·클릭·앱 전환).
    ///   이 동작 뒤에는 평소 동작(바뀌면 숨기고 멈춘 뒤 처리)으로 돌아간다
    public mutating func observe(
        _ frame: ImageFingerprint, at now: ContinuousClock.Instant = .now,
        lastUserAction: ContinuousClock.Instant? = nil
    ) -> Change {
        defer { previous = frame }
        let isStill = previous.map { frame.difference(to: $0) < Self.threshold } ?? false
        changingSince = isStill ? nil : changingSince ?? now
        if let lastKeptUp, let lastUserAction, lastUserAction > lastKeptUp {
            self.lastKeptUp = nil
        }

        let differsFromProcessed = processed.map { frame.difference(to: $0) >= Self.threshold } ?? true
        if differsFromProcessed, isStill {
            processed = frame
            if isKeepingUp {
                lastKeptUp = now
            }
            return .settled
        }
        if differsFromProcessed, isDueToKeepUp(at: now, lastUserAction: lastUserAction) {
            processed = frame
            lastKeptUp = now
            return .keepsChanging
        }
        if isKeepingUp {
            return .unchanged
        }
        let movedAway = processed.map { frame.difference(to: $0) >= Self.movedAwayThreshold } ?? true
        return movedAway ? .movedAway : .unchanged
    }

    private func isDueToKeepUp(at now: ContinuousClock.Instant, lastUserAction: ContinuousClock.Instant?) -> Bool {
        if let lastKeptUp {
            return now - lastKeptUp >= Self.keepsChangingInterval
        }
        guard let changingSince else { return false }
        let waitStart = max(changingSince, lastUserAction ?? changingSince)
        return now - waitStart >= Self.keepsChangingAfter
    }

    /// 렌즈를 옮기거나 크기를 바꾸면 처음부터 다시 본다.
    public mutating func reset() {
        previous = nil
        processed = nil
        changingSince = nil
        lastKeptUp = nil
    }
}
