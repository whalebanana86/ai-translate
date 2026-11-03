import CoreGraphics

/// 같은 크기의 원문은 같은 크기로 번역을 그리도록 문단마다 글자 크기를 정한다.
///
/// 문단마다 따로 크기를 정하면 인식이 흔들려 같은 크기의 댓글·메뉴 항목이 서로 다른 크기로, 같은 문단도 인식할 때마다 다른 크기로
/// 그려졌다(TASK-042). 크기가 비슷한 문단은 한 크기로 묶고, 전에 쓴 크기를 기억해 화면이 바뀌어도 같은 글은 같은 크기로 그린다.
/// 크기는 원문 글자 크기(이미지 픽셀): 캡처에서 잰 값(`TextStyleMeter`), 없으면 줄 높이 × 0.93(`pixelSize(of:)`)
public struct FontSizer: Sendable {
    /// 크기가 이 배수 안이면 같은 크기의 글로 본다. 잉크로 잰 크기의 흔들림(90% 구간 ±2~4%)을 덮는 폭이다. 줄 상자 높이로 잴 때는
    /// ±15% 흔들려 1.2배였고, 그보다 작은 실제 크기 차이(본문과 작은 소제목 등)를 구분하지 못했다 (TASK-059)
    static let sameSizeRatio: CGFloat = 1.1
    /// 기억하는 줄 높이 수
    static let memoryLimit = 8

    /// 전에 쓴 글자 크기(이미지 픽셀). 최근에 쓴 것이 뒤
    private var remembered: [CGFloat] = []

    public init() {}

    /// 문단마다 번역 글자 크기(포인트)를 정한다.
    /// - Parameter pixelSizes: 문단마다 원문 글자 크기(이미지 픽셀)
    public mutating func fontSizes(for pixelSizes: [CGFloat], scale: CGFloat) -> [CGFloat] {
        // 작은 것부터 정해 결과가 문단 순서에 따르지 않게 한다
        var chosen: [Int: CGFloat] = [:]
        for index in pixelSizes.indices.sorted(by: { pixelSizes[$0] < pixelSizes[$1] }) {
            let pixels = pixelSizes[index]
            let size = closestRemembered(to: pixels) ?? Self.median(pixelSizes.filter { Self.isSameSize($0, pixels) })
            remember(size)
            chosen[index] = size
        }
        return pixelSizes.indices.map { LensGeometry.fontSize(pixelSize: chosen[$0] ?? 0, scale: scale) }
    }

    /// 번역을 그리는 문단(`drawn`)만 크기를 묶고 기억한다. 그리지 않는 문단(숫자·버튼·작성자 줄·이미 대상 언어)은 자기 줄 높이로
    /// 정한다: 작은 좋아요 줄·작성자 줄이 작은 크기를 먼저 만들고 1.2배 안의 본문이 그 크기로 끌려가 작게 그려졌다 (TASK-056)
    public mutating func fontSizes(for pixelSizes: [CGFloat], drawn: [Bool], scale: CGFloat) -> [CGFloat] {
        let indices = pixelSizes.indices.filter { drawn.indices.contains($0) && drawn[$0] }
        var sizes = pixelSizes.map { LensGeometry.fontSize(pixelSize: $0, scale: scale) }
        for (index, size) in zip(indices, fontSizes(for: indices.map { pixelSizes[$0] }, scale: scale)) {
            sizes[index] = size
        }
        return sizes
    }

    /// 캡처에서 재지 못했을 때 문단의 글자 크기(이미지 픽셀): 대표 줄 높이 × 0.93 (`LensGeometry.fontSizePerLineHeight`)
    public static func pixelSize(of block: TextBlock) -> CGFloat {
        lineHeight(of: block) * LensGeometry.fontSizePerLineHeight
    }

    /// 문단의 대표 줄 높이: 줄 높이의 중간값 (아래로 내려가는 글자가 있는 줄과 없는 줄이 섞여도 한쪽으로 쏠리지 않게).
    /// 이모지를 붙인 줄은 이모지를 뺀 단어 영역 높이로 잰다: 이모지가 글자보다 높아 줄 영역으로 재면 글자가 커졌다 (TASK-055)
    public static func lineHeight(of block: TextBlock) -> CGFloat {
        median(block.lines.map(textHeight(of:)))
    }

    private static func textHeight(of line: RecognizedLine) -> CGFloat {
        guard !line.emojis.isEmpty else { return line.boundingBox.height }
        let words = line.wordBoxes.filter { !line.emojis.contains($0) && !$0.isNull }
        return words.isEmpty ? line.boundingBox.height : words.reduce(CGRect.null) { $0.union($1) }.height
    }

    private func closestRemembered(to size: CGFloat) -> CGFloat? {
        remembered.filter { Self.isSameSize($0, size) }.min { abs($0 - size) < abs($1 - size) }
    }

    private mutating func remember(_ size: CGFloat) {
        remembered.removeAll { $0 == size }
        remembered = Array((remembered + [size]).suffix(Self.memoryLimit))
    }

    private static func isSameSize(_ first: CGFloat, _ second: CGFloat) -> Bool {
        guard first > 0, second > 0 else { return first == second }
        return max(first, second) / min(first, second) <= sameSizeRatio
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
