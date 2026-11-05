import CoreGraphics
import CoreText
import Foundation
import Synchronization

/// 원문 글자 굵기. 번역을 시스템 글꼴의 이 굵기로 그린다 (TASK-060)
public enum TextWeight: Int, Comparable, Sendable {
    case regular
    case semibold
    case bold

    public static func < (lhs: TextWeight, rhs: TextWeight) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 캡처에서 잰 원문 문단의 글자 크기·굵기·줄 간격. 길이는 이미지 픽셀(포인트는 화면 배율로 나눈다)
public struct TextStyle: Equatable, Sendable {
    /// 글자 크기
    public var pixelSize: CGFloat
    /// 글자가 작아 재지 못하면 nil (`TextStyleMeter.minimumWeightPixelSize`)
    public var weight: TextWeight?
    /// 줄 간격(기준선 사이 거리). 한 줄 문단이면 nil (TASK-062)
    public var lineHeight: CGFloat?

    public init(pixelSize: CGFloat, weight: TextWeight?, lineHeight: CGFloat? = nil) {
        self.pixelSize = pixelSize
        self.weight = weight
        self.lineHeight = lineHeight
    }
}

/// 캡처에서 잰 OCR 줄 하나의 글자 크기와 굵기. 문단 나누기(`TextBlockGrouper`)와 문단 크기·굵기에 쓴다
public struct LineStyle: Equatable, Sendable {
    /// 글자 크기(이미지 픽셀)
    public var pixelSize: CGFloat
    /// 획 두께 ÷ 글자 크기. 글자가 작으면 nil (`TextStyleMeter.minimumWeightPixelSize`)
    public var strokeRatio: CGFloat?
    /// 줄 하나로 본 굵기
    public var weight: TextWeight?
    /// 기준선(라틴) 또는 잉크 아래 끝(한글·한자)의 이미지 y. 문단 줄 간격을 재고, 문단을 묶는 데 쓴다
    public var baseline: CGFloat?

    public init(pixelSize: CGFloat, strokeRatio: CGFloat?, weight: TextWeight?, baseline: CGFloat? = nil) {
        self.pixelSize = pixelSize
        self.strokeRatio = strokeRatio
        self.weight = weight
        self.baseline = baseline
    }
}

/// 캡처 픽셀에서 원문 글자 크기와 굵기를 잰다 (TASK-059·060, 사용자 요청: 원문 글자 크기·굵기 그대로).
///
/// 크기: OCR 줄 상자 높이는 글 내용(대문자·아래로 내려가는 글자)·글꼴·굵기에 따라 달랐다(TASK-040). 줄의 잉크 높이(바탕색에서
/// 글자색 쪽으로 덮인 정도)를 재고, 같은 글을 시스템 글꼴로 그렸을 때의 글리프 높이와 비교한다. 라틴 글은 기준선 위만 비교한다.
/// 측정(같은 글꼴 안 흔들림 90% 구간, 지금 식 → 줄 상자 식):
/// - CoreText로 그린 1274줄(글꼴 9개·굵기·12~88px·영어·한국어·일본어): ±1.8%(24px 이상)·±3.6%(12~20px) ← ±17~20%
/// - Chrome으로 그린 389줄(글꼴 8개, 2배·1배 화면): ±2.2%(2배)·±4.3%(1배), 가장 큰 오차 6.8%·11.7% ← ±36~40%, 가장 큰 오차 2배.
///   줄 상자 식은 한국어·일본어를 15~21% 크게 그렸다(지금 -1~+3%)
/// 글꼴마다 남는 차이(Georgia +5%, Avenir Next +13% 등)는 글자 모양이 커서 생기므로 둔다(보이는 글자 높이가 같아진다).
///
/// 굵기: 줄 가운데 띠에서 가로로 이어진 잉크 폭(대개 세로 획 두께)의 중간값을 글자 크기로 나눠 시스템 글꼴의 굵기별 값과 비교한다.
/// 두 측정에서 보통 글꼴을 굵게(semibold 이상)로, 굵은 글꼴을 보통으로 본 줄이 없다(26px 이상). 글자가 작으면 재지 않는다
public enum TextStyleMeter {
    /// 이보다 작은 글자(이미지 픽셀, 2배 화면의 13pt)는 굵기를 재지 않는다. 측정: 12~20px는 이웃 획이 번져 붙어 보통 글꼴의 10~20%가
    /// 굵게 값으로 나왔고, 24px에서도 어두운 바탕의 밝은 보통 글자 4줄이 semibold로 나왔다
    public static let minimumWeightPixelSize: CGFloat = 26
    /// 화면 글자는 글리프 윤곽보다 약 0.75px 높게 그려진다(시스템 글꼴을 같은 글꼴과 비교한 측정 중간값, 크기와 무관)
    static let renderingSpread: CGFloat = 0.75
    /// 기준 글을 그리는 크기
    static let referenceSize: CGFloat = 100
    /// 잉크를 찾는 범위: 줄 상자 위아래로 줄 높이의 이 배수
    static let searchMargin: CGFloat = 0.5
    /// 잉크가 끊긴 줄이 줄 높이의 이 배수보다 길게 이어지면 그 줄의 잉크 끝으로 본다 (i의 점처럼 떨어진 부분은 넘는다)
    static let maxGapRatio: CGFloat = 0.12
    /// 픽셀 하나의 이만큼이 덮인 줄부터 잉크가 있는 줄로 본다
    static let minimumRowInk: Float = 0.25
    /// 글자색: 줄 상자 안에서 바탕과 이 비율보다 먼 픽셀들. 작은 글자는 문단 글자색 뽑기(`BlockColors`)가 흐린 가장자리색이나
    /// 검정 대체값이 되어 잉크를 절반으로 쟀다(회색 12px)
    static let inkPercentile = 0.995
    /// 바탕과 글자색 거리(0~255 RGB)가 이보다 가까우면 재지 않는다
    static let minimumInkDistance: Float = 40
    /// 잰 크기가 줄 상자 높이의 이 범위 밖이면 잘못 잰 것으로 본다(바탕이 그림인 글 등). OCR 줄 상자는 굵은 글에서 글자 크기의
    /// 1.8배까지 높았고(Chrome 측정, 잰 크기 ÷ 상자 0.28~2.02, 그래도 오차 19% 이하), 0.6 아래를 버렸을 때 굵은 줄 22개를 잃었다
    static let plausibleSizeRatio: ClosedRange<CGFloat> = 0.25...2.5
    /// 이 비율보다 많은 픽셀이 반 넘게 덮인 가로줄은 글자가 아니라 밑줄이나 이웃한 색 영역(구분선, 강조 줄)으로 보고 거기서 잉크
    /// 찾기를 멈춘다. 멈추지 않으면 링크 밑줄까지 잉크로 세어 11% 크게 쟀다(테스트)
    static let solidRowFill: Float = 0.8
    /// 세로 선(그래프 축, 표 테두리)으로 보는 덮임과 길이(줄 상자 높이 배수, `Pixels.removingVerticalRules`). 글자 획은 글자 크기의
    /// 1.3배 안이고 OCR 줄 상자는 글자 크기의 0.5배 넘게 높다(Chrome 측정, 잰 크기 ÷ 상자 2.02 이하)
    static let ruleCoverage: Float = 0.3
    static let ruleLengthRatio: CGFloat = 3
    /// 세로 선으로 보는 최대 폭(줄 상자 높이 배수). 그래프 축·표 테두리는 1~2pt
    static let ruleWidthRatio: CGFloat = 0.25

    /// 줄마다 잰 크기·굵기·기준선. 잴 수 없으면 nil. 바탕색은 줄 상자에서 가장 많은 색
    public static func measure(_ lines: [RecognizedLine], in image: CGImage) -> [LineStyle?] {
        guard let pixels = Pixels(image) else { return lines.map { _ in nil } }
        return lines.map { line in
            guard let background = pixels.dominantColor(in: line.boundingBox) else { return nil }
            return measure(line, background: background, limits: limits(of: line, among: lines), in: pixels)
        }
    }

    /// 문단마다 크기(줄 크기의 중간값)와 굵기(줄 획 비율의 중간값). 잰 줄이 없으면 nil
    /// - Parameters:
    ///   - lines: `measure(_:in:)`에 넘긴 줄
    ///   - lineStyles: `measure(_:in:)` 결과
    public static func styles(of blocks: [TextBlock], lines: [RecognizedLine], lineStyles: [LineStyle?]) -> [TextStyle?]
    {
        blocks.map { block in
            let measured = block.lines.compactMap { line in
                lines.firstIndex(of: line).flatMap { lineStyles.indices.contains($0) ? lineStyles[$0] : nil }
            }
            guard !measured.isEmpty else { return nil }
            let size = median(measured.map(\.pixelSize))
            let strokes = measured.compactMap(\.strokeRatio)
            // 문단 줄은 위에서부터다. 이웃 줄 기준선 사이 거리 중 그럴듯한 것(글자 크기의 0.9~3배)
            let baselines = measured.compactMap(\.baseline)
            let pitches = zip(baselines, baselines.dropFirst()).map { $1 - $0 }.filter {
                plausibleLineHeight.contains($0 / size)
            }
            return TextStyle(
                pixelSize: size,
                weight: strokes.isEmpty ? nil : weight(strokeRatio: median(strokes), script: script(of: block.text)),
                lineHeight: pitches.isEmpty ? nil : median(pitches))
        }
    }

    /// 줄 간격 ÷ 글자 크기가 이 범위 밖이면 이웃 줄이 아닌 것으로 본다 (문단 안 빈 줄 등)
    static let plausibleLineHeight: ClosedRange<CGFloat> = 0.9...3

    // MARK: 굵기

    enum Script {
        case latin, hangul, cjk
    }

    /// 시스템 글꼴(라틴 SF, 한글 Apple SD Gothic Neo, 일본어 Hiragino Sans)의 굵기별 획 두께 ÷ 글자 크기 (24~88px 측정 중간값).
    /// 다른 글꼴: 보통 0.077(Avenir Next)~0.102, 굵게 0.148~0.162. 한글 글꼴은 획이 가늘어 따로 본다.
    /// 중간 굵기(medium)는 두지 않는다: 보통 글꼴의 7%가 medium으로 나와 본문 번역 굵기가 문단마다 달라졌다
    static let strokeRatios: [Script: [(TextWeight, CGFloat)]] = [
        .latin: [(.regular, 0.102), (.semibold, 0.137), (.bold, 0.155)],
        .hangul: [(.regular, 0.090), (.semibold, 0.115), (.bold, 0.130)],
        // Hiragino Sans W3(보통), W6(시스템 글꼴 semibold·bold)
        .cjk: [(.regular, 0.089), (.semibold, 0.142)],
    ]

    /// 가장 가까운 굵기 (비율로 비교)
    static func weight(strokeRatio: CGFloat, script: Script) -> TextWeight {
        let candidates = strokeRatios[script] ?? []
        return candidates.min { abs(log($0.1 / strokeRatio)) < abs(log($1.1 / strokeRatio)) }?.0 ?? .regular
    }

    /// 문단 글자가 가장 많은 문자. 글자 수가 같으면 라틴 → 한글 → 한자·가나 순 (사전 순서로 고르면 읽을 때마다 바뀌었다, TASK-079)
    static func script(of text: String) -> Script {
        var counts: [Script: Int] = [:]
        for character in text where character.isLetter {
            switch LanguageDetection.Script(character) {
            case .hangul: counts[.hangul, default: 0] += 1
            case .kana, .han: counts[.cjk, default: 0] += 1
            case .latin: counts[.latin, default: 0] += 1
            case .other: break
            }
        }
        return [Script.latin, .hangul, .cjk].max { counts[$0, default: 0] < counts[$1, default: 0] } ?? .latin
    }

    // MARK: 줄 하나

    /// 위아래 이웃 줄(가로로 겹치는 줄)과의 가운데까지만 잉크를 찾는다
    static func limits(of line: RecognizedLine, among lines: [RecognizedLine]) -> ClosedRange<CGFloat> {
        let box = line.boundingBox
        var top = box.minY - box.height * searchMargin
        var bottom = box.maxY + box.height * searchMargin
        for other in lines where other != line {
            let neighbor = other.boundingBox
            guard neighbor.maxX > box.minX, neighbor.minX < box.maxX else { continue }
            if neighbor.midY < box.midY {
                top = max(top, min((neighbor.maxY + box.minY) / 2, box.minY))
            } else {
                bottom = min(bottom, max((neighbor.minY + box.maxY) / 2, box.maxY))
            }
        }
        return top...bottom
    }

    static func measure(
        _ line: RecognizedLine, background: [Float], limits: ClosedRange<CGFloat>, in pixels: Pixels
    ) -> LineStyle? {
        let box = line.boundingBox
        let x0 = max(Int(box.minX.rounded(.down)), 0)
        let x1 = min(Int(box.maxX.rounded(.up)), pixels.width)
        let top = max(Int(limits.lowerBound.rounded(.down)), 0)
        let bottom = min(Int(limits.upperBound.rounded(.up)), pixels.height)
        guard box.height >= 4, x1 - x0 >= 2, bottom - top >= 4 else { return nil }
        guard let ink = pixels.inkColor(in: box, background: background, excluding: line.emojis) else { return nil }
        let region = pixels.removingVerticalRules(
            from: pixels.coverage(
                x: x0..<x1, y: top..<bottom, background: background, ink: ink, excluding: line.emojis),
            x: x0..<x1, y: top..<bottom, background: background, ink: ink,
            longerThan: Int(box.height * ruleLengthRatio), narrowerThan: max(Int(box.height * ruleWidthRatio), 1))
        guard let rows = inkRows(region, center: Int(box.midY) - top, lineHeight: box.height) else { return nil }

        let text = EmojiFinder.removingMarkers(line.text)
        let reference = reference(of: text)
        let size: CGFloat
        let baselineY: CGFloat
        if script(of: text) == .latin, let baseline = baselineRow(region, rows: rows) {
            // 라틴 글은 기준선 위만 비교한다: OCR이 아래로 내려가는 글자를 빼고 읽으면("anytime" → "antime") 기준 글이 낮아져
            // 26% 크게 쟀다 (Chrome 측정에서 OCR이 틀린 줄 22%)
            let partial = min(region.rowSum[baseline] / max(region.rowSum[baseline - 1], 1), 1)
            let above = (rows.lowerBound..<baseline).reduce(Float(0)) { $0 + region.rowMax[$1] } + partial
            size = (CGFloat(above) - renderingSpread) / reference.ascent * referenceSize
            baselineY = CGFloat(top + baseline) + CGFloat(partial)
        } else {
            let height = CGFloat(rows.reduce(Float(0)) { $0 + region.rowMax[$1] }) - renderingSpread
            size = height / reference.height * referenceSize
            baselineY = CGFloat(top + rows.upperBound) + CGFloat(region.rowMax[rows.upperBound])
        }
        guard size > 0, reference.height > 0, reference.ascent > 0, plausibleSizeRatio.contains(size / box.height)
        else { return nil }
        // 획 두께: 잉크 높이 35~65% 띠(라틴은 x 높이 안, 한글·한자는 글자 가운데)
        let band = rows.lowerBound + rows.count * 35 / 100...rows.lowerBound + rows.count * 65 / 100
        guard let stroke = region.medianRun(rows: band) else { return nil }
        let strokeRatio = size >= minimumWeightPixelSize ? CGFloat(stroke) / size : nil
        return LineStyle(
            pixelSize: size, strokeRatio: strokeRatio,
            weight: strokeRatio.map { weight(strokeRatio: $0, script: script(of: text)) }, baseline: baselineY)
    }

    /// 기준선 줄: 잉크 아래쪽 절반에서 덮임 합이 가장 크게 줄어드는 줄(x 높이 띠의 바닥, 아래로 내려가는 글자는 듬성하다)
    static func baselineRow(_ region: Coverage, rows: ClosedRange<Int>) -> Int? {
        let middle = rows.lowerBound + rows.count / 2
        guard middle > rows.lowerBound else { return nil }
        return (middle...rows.upperBound).max { first, second in
            func drop(_ row: Int) -> Float { region.rowSum[row] - (row < rows.upperBound ? region.rowSum[row + 1] : 0) }
            return drop(first) < drop(second)
        }
    }

    /// 줄 가운데에서 위아래로 잉크가 있는 줄을 찾는다. 밑줄·이웃한 색 영역에서 멈춘다
    static func inkRows(_ region: Coverage, center: Int, lineHeight: CGFloat) -> ClosedRange<Int>? {
        let rowCount = region.rowSum.count
        let start = min(max(center, 0), rowCount - 1)
        let maxGap = max(Int(lineHeight * maxGapRatio), 1)
        let solid = Float(region.width) * solidRowFill
        func edge(_ step: Int) -> Int? {
            var row = start
            var last: Int?
            var gap = 0
            while row >= 0, row < rowCount, Float(region.rowFilled[row]) <= solid {
                if region.rowSum[row] > minimumRowInk {
                    last = row
                    gap = 0
                } else {
                    gap += 1
                    if gap > maxGap { break }
                }
                row += step
            }
            return last
        }
        guard let first = edge(-1) ?? edge(1), let last = edge(1) ?? edge(-1), first <= last else { return nil }
        return first...last
    }

    // MARK: 기준 글

    /// 같은 글을 시스템 글꼴(`referenceSize`)로 그렸을 때 글리프 윤곽
    struct Reference {
        /// 맨 위에서 맨 아래까지
        var height: CGFloat
        /// 기준선 위
        var ascent: CGFloat
    }

    /// 기준 글은 글마다 같으므로 기억한다 (CoreText 한 줄 약 0.05~0.1ms)
    private static let referenceCache = Mutex<[String: Reference]>([:])
    private static let referenceCacheLimit = 2_000

    static func reference(of text: String) -> Reference {
        if let known = referenceCache.withLock({ $0[text] }) {
            return known
        }
        let font = CTFontCreateUIFontForLanguage(.system, referenceSize, nil)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font as Any]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let reference = Reference(height: bounds.height, ascent: bounds.maxY)
        referenceCache.withLock { cache in
            if cache.count >= referenceCacheLimit {
                cache.removeAll()
            }
            cache[text] = reference
        }
        return reference
    }

    // MARK: 픽셀

    /// 이미지 RGBA. 화면을 한 번 읽어 줄마다 쓴다
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            let (width, height) = (image.width, image.height)
            guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.width = width
            self.height = height
            self.bytes = bytes
        }

        /// 영역에서 가장 많은 색(채널마다 상위 5비트로 묶어 센 뒤 그 묶음의 평균). 넓으면 건너뛰며 2000개쯤 본다.
        /// 개수가 같으면 먼저 나온(위·왼쪽) 묶음: 사전 순서로 고르면 같은 화면도 읽을 때마다 바탕이 바뀌었다 (TASK-079)
        func dominantColor(in box: CGRect) -> [Float]? {
            let area = box.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !area.isEmpty else { return nil }
            let step = max(Int((area.width * area.height / 2_000).squareRoot()), 1)
            // 묶음마다 (개수, 빨강 합, 초록 합, 파랑 합, 처음 나온 순서)
            var counts: [Int: (Int, Int, Int, Int, Int)] = [:]
            bytes.withUnsafeBufferPointer { bytes in
                for y in stride(from: Int(area.minY), to: Int(area.maxY), by: step) {
                    for x in stride(from: Int(area.minX), to: Int(area.maxX), by: step) {
                        let index = (y * width + x) * 4
                        let (red, green, blue) = (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
                        let key = (red >> 3) << 10 | (green >> 3) << 5 | blue >> 3
                        let entry = counts[key] ?? (0, 0, 0, 0, counts.count)
                        counts[key] = (entry.0 + 1, entry.1 + red, entry.2 + green, entry.3 + blue, entry.4)
                    }
                }
            }
            guard let top = counts.values.max(by: { ($0.0, $1.4) < ($1.0, $0.4) }) else { return nil }
            let count = Float(top.0)
            return [Float(top.1) / count, Float(top.2) / count, Float(top.3) / count]
        }

        /// 줄 상자 안에서 바탕과 가장 먼 쪽 픽셀들(`inkPercentile` 이상)의 평균색
        func inkColor(in box: CGRect, background: [Float], excluding excluded: [CGRect]) -> [Float]? {
            let area = box.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard !area.isEmpty else { return nil }
            let (x0, x1, y0, y1) = (Int(area.minX), Int(area.maxX), Int(area.minY), Int(area.maxY))
            let (backRed, backGreen, backBlue) = (background[0], background[1], background[2])
            // 거리(0~441)를 1 단위로 센다. 픽셀마다 거리를 기억해 두 번째 훑기에 쓴다
            var histogram = [Int](repeating: 0, count: 443)
            var distances = [UInt16](repeating: UInt16.max, count: (x1 - x0) * (y1 - y0))
            var total = 0
            bytes.withUnsafeBufferPointer { bytes in
                for y in y0..<y1 {
                    for x in x0..<x1 where excluded.isEmpty || !excluded.contains(where: { $0.contains(x, y) }) {
                        let index = (y * width + x) * 4
                        let red = Float(bytes[index]) - backRed
                        let green = Float(bytes[index + 1]) - backGreen
                        let blue = Float(bytes[index + 2]) - backBlue
                        let distance = Int((red * red + green * green + blue * blue).squareRoot())
                        histogram[distance] += 1
                        distances[(y - y0) * (x1 - x0) + x - x0] = UInt16(distance)
                        total += 1
                    }
                }
            }
            guard total > 0 else { return nil }
            var remaining = Int(Double(total) * (1 - TextStyleMeter.inkPercentile)) + 1
            var threshold = histogram.count - 1
            while threshold > 0, remaining > histogram[threshold] {
                remaining -= histogram[threshold]
                threshold -= 1
            }
            guard Float(threshold) >= TextStyleMeter.minimumInkDistance else { return nil }
            var (sumRed, sumGreen, sumBlue, count): (Float, Float, Float, Float) = (0, 0, 0, 0)
            bytes.withUnsafeBufferPointer { bytes in
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let distance = distances[(y - y0) * (x1 - x0) + x - x0]
                        guard distance != UInt16.max, Int(distance) >= threshold else { continue }
                        let index = (y * width + x) * 4
                        sumRed += Float(bytes[index])
                        sumGreen += Float(bytes[index + 1])
                        sumBlue += Float(bytes[index + 2])
                        count += 1
                    }
                }
            }
            return count > 0 ? [sumRed / count, sumGreen / count, sumBlue / count] : nil
        }

        /// 픽셀마다 바탕(0)에서 글자색(1) 쪽으로 덮인 정도
        func coverage(
            x columns: Range<Int>, y rows: Range<Int>, background: [Float], ink: [Float], excluding excluded: [CGRect]
        ) -> Coverage {
            let (backRed, backGreen, backBlue) = (background[0], background[1], background[2])
            let (axisRed, axisGreen, axisBlue) = (ink[0] - backRed, ink[1] - backGreen, ink[2] - backBlue)
            let scale = 1 / max(axisRed * axisRed + axisGreen * axisGreen + axisBlue * axisBlue, 1)
            let columnCount = columns.count
            var values = [Float](repeating: 0, count: columnCount * rows.count)
            values.withUnsafeMutableBufferPointer { values in
                bytes.withUnsafeBufferPointer { bytes in
                    for (row, y) in rows.enumerated() {
                        var index = (y * width + columns.lowerBound) * 4
                        let start = row * columnCount
                        for column in 0..<columnCount {
                            let dot =
                                (Float(bytes[index]) - backRed) * axisRed + (Float(bytes[index + 1]) - backGreen)
                                * axisGreen + (Float(bytes[index + 2]) - backBlue) * axisBlue
                            values[start + column] = min(max(dot * scale, 0), 1)
                            index += 4
                        }
                    }
                }
            }
            for rect in excluded {
                let clipped = rect.integral.intersection(
                    CGRect(x: columns.lowerBound, y: rows.lowerBound, width: columnCount, height: rows.count))
                guard !clipped.isEmpty else { continue }
                for y in Int(clipped.minY)..<Int(clipped.maxY) {
                    for x in Int(clipped.minX)..<Int(clipped.maxX) {
                        values[(y - rows.lowerBound) * columnCount + x - columns.lowerBound] = 0
                    }
                }
            }
            return Coverage(width: columnCount, values: values)
        }

        /// 세로 선(그래프 축, 표 테두리)을 지운 덮임. 찾는 범위 위나 아래 끝에서 이어진 덮인 열을 범위 밖까지 따라가 `length`보다
        /// 길고, 그런 열이 `maxWidth` 폭 안이면 범위 안 그 부분을 지운다. 지우지 않으면 축이 지나는 줄마다 잉크가 축 끝까지 이어져 글자를 크게 쟀다(TASK-078: 막대그래프
        /// 이름 24.6px를 33~40px로 재 아래 줄과 한 문단이 됐다). 범위 안만 보면 줄 상자가 글자보다 작은 줄에서 "l" 획도 범위 끝에 닿았다
        func removingVerticalRules(
            from region: Coverage, x columns: Range<Int>, y rows: Range<Int>, background: [Float], ink: [Float],
            longerThan length: Int, narrowerThan maxWidth: Int
        ) -> Coverage {
            let count = rows.count
            guard region.width == columns.count, count > 0, region.values.count == region.width * count else {
                return region
            }
            let (backRed, backGreen, backBlue) = (background[0], background[1], background[2])
            let (axisRed, axisGreen, axisBlue) = (ink[0] - backRed, ink[1] - backGreen, ink[2] - backBlue)
            let scale = 1 / max(axisRed * axisRed + axisGreen * axisGreen + axisBlue * axisBlue, 1)
            let threshold = TextStyleMeter.ruleCoverage
            var values = region.values
            var changed = false
            // 열마다 지울 줄 범위
            var rules = [[Range<Int>]](repeating: [], count: region.width)
            bytes.withUnsafeBufferPointer { bytes in
                func covered(_ x: Int, _ y: Int) -> Bool {
                    let index = (y * width + x) * 4
                    let dot =
                        (Float(bytes[index]) - backRed) * axisRed + (Float(bytes[index + 1]) - backGreen) * axisGreen
                        + (Float(bytes[index + 2]) - backBlue) * axisBlue
                    return dot * scale > threshold
                }
                for column in 0..<region.width {
                    func inRegion(_ row: Int) -> Bool { values[row * region.width + column] > threshold }
                    guard inRegion(0) || inRegion(count - 1) else { continue }
                    let x = columns.lowerBound + column
                    var fromTop = 0
                    while fromTop < count, inRegion(fromTop) { fromTop += 1 }
                    var fromBottom = 0
                    while fromBottom < count, inRegion(count - 1 - fromBottom) { fromBottom += 1 }
                    var above = 0
                    while fromTop > 0, above < length, rows.lowerBound - 1 - above >= 0,
                        covered(x, rows.lowerBound - 1 - above)
                    {
                        above += 1
                    }
                    var below = 0
                    while fromBottom > 0, below < length, rows.upperBound + below < height,
                        covered(x, rows.upperBound + below)
                    {
                        below += 1
                    }
                    rules[column] =
                        fromTop == count
                        ? (above + count + below > length ? [0..<count] : [])
                        : (above + fromTop > length ? [0..<fromTop] : [])
                            + (fromBottom + below > length ? [(count - fromBottom)..<count] : [])
                }
            }
            // 가는 선만 지운다. 넓게 이어진 열은 선이 아니라 이웃한 색 영역(자막 상자 밖 페이지)이고, 지우면 그 줄이 꽉 찬 줄로 보이지 않아
            // 잉크 찾기가 멈추지 않았다(자막 25px → 44px)
            var column = 0
            while column < region.width {
                guard !rules[column].isEmpty else {
                    column += 1
                    continue
                }
                let start = column
                while column < region.width, !rules[column].isEmpty { column += 1 }
                guard column - start <= maxWidth else { continue }
                for rule in start..<column {
                    for row in rules[rule].joined() {
                        values[row * region.width + rule] = 0
                    }
                }
                changed = true
            }
            return changed ? Coverage(width: region.width, values: values) : region
        }
    }

    /// 줄 영역의 덮임 (가로 `width`, 줄마다 이어 붙임)
    struct Coverage {
        let width: Int
        let values: [Float]
        /// 줄마다 덮임 합, 가장 많이 덮인 픽셀, 반 넘게 덮인 픽셀 수
        let rowSum: [Float]
        let rowMax: [Float]
        let rowFilled: [Int]

        init(width: Int, values: [Float]) {
            self.width = width
            self.values = values
            let rows = width > 0 ? values.count / width : 0
            var sum = [Float](repeating: 0, count: rows)
            var maximum = [Float](repeating: 0, count: rows)
            var filled = [Int](repeating: 0, count: rows)
            values.withUnsafeBufferPointer { values in
                for row in 0..<rows {
                    var (rowSum, rowMax, rowFilled): (Float, Float, Int) = (0, 0, 0)
                    for index in row * width..<(row + 1) * width {
                        let value = values[index]
                        rowSum += value
                        rowMax = max(rowMax, value)
                        if value > 0.5 { rowFilled += 1 }
                    }
                    sum[row] = rowSum
                    maximum[row] = rowMax
                    filled[row] = rowFilled
                }
            }
            rowSum = sum
            rowMax = maximum
            rowFilled = filled
        }

        /// 가로로 이어진 잉크(덮임 0.1 초과) 구간마다 덮임 합의 중간값. 덮임을 더하므로 번진 가장자리도 획 두께에 맞게 들어간다
        func medianRun(rows: ClosedRange<Int>) -> Float? {
            var runs: [Float] = []
            for row in rows where row >= 0 && row < rowSum.count {
                var run: Float = 0
                for index in row * width..<(row + 1) * width {
                    let value = values[index]
                    if value > 0.1 {
                        run += value
                    } else if run > 0 {
                        runs.append(run)
                        run = 0
                    }
                }
                if run > 0 { runs.append(run) }
            }
            guard !runs.isEmpty else { return nil }
            return runs.sorted()[runs.count / 2]
        }
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

extension CGRect {
    fileprivate func contains(_ x: Int, _ y: Int) -> Bool {
        contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
    }
}

/// 같은 글은 같은 굵기로 그린다 (TASK-060). 굵기 값이 두 굵기 가운데쯤이면 스크롤로 픽셀 위치가 바뀔 때마다 다르게 잴 수 있다
public struct TextWeightMemory: Sendable {
    static let limit = 500
    private var weights: [String: TextWeight] = [:]

    public init() {}

    /// 처음 잰 굵기를 기억해 쓴다. 재지 못했고 기억도 없으면 보통
    public mutating func weight(for text: String, measured: TextWeight?) -> TextWeight {
        if let known = weights[text] {
            return known
        }
        guard let measured else { return .regular }
        if weights.count >= Self.limit {
            weights.removeAll()
        }
        weights[text] = measured
        return measured
    }
}
