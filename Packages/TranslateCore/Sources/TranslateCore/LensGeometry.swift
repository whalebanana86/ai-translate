import CoreGraphics

/// 렌즈 안에서 번역 문단이 놓일 자리. 원문 문단의 왼쪽 위에서 시작한다.
public struct ParagraphFrame: Equatable, Sendable {
    public var origin: CGPoint
    /// 번역 글이 줄바꿈되는 너비
    public var width: CGFloat
    /// 번역 글이 쓸 수 있는 높이. 그래도 넘치면 화면에서 글자를 줄인다
    public var maxHeight: CGFloat
    /// 원문 문단 크기. 번역이 짧아도 이만큼은 가려야 원문 글자가 보이지 않는다
    public var sourceSize: CGSize
    /// 원문 문단 왼쪽 위. 보통 문단은 `origin`과 같고, 자막은 번역을 기억한 자리에 그리므로 다를 수 있다
    public var sourceOrigin: CGPoint
    /// 영상 자막처럼 가운데 정렬된 문단. 번역을 자리(`origin`·`width`·`maxHeight`)의 가운데·아래 끝에 맞춰 그린다
    public var isCentered: Bool
    /// 원문 문단 줄 수. 자막 번역을 원문처럼 이 줄 수로 나눈다(`LensGeometry.balancedWidth`)
    public var sourceLineCount: Int
    /// 이중 자막: 원문을 가리지 않고 번역을 자리(원문 위나 아래)에 따로 그린다
    public var showsSource: Bool
    /// 가운데 정렬 번역을 자리의 위 끝에 맞춘다(원문 아래에 둔 이중 자막). 아니면 아래 끝
    public var alignsTextToTop: Bool

    public init(
        origin: CGPoint, width: CGFloat, maxHeight: CGFloat, sourceSize: CGSize, sourceOrigin: CGPoint? = nil,
        isCentered: Bool = false, sourceLineCount: Int = 1, showsSource: Bool = false, alignsTextToTop: Bool = false
    ) {
        self.origin = origin
        self.width = width
        self.maxHeight = maxHeight
        self.sourceSize = sourceSize
        self.sourceOrigin = sourceOrigin ?? origin
        self.isCentered = isCentered
        self.sourceLineCount = sourceLineCount
        self.showsSource = showsSource
        self.alignsTextToTop = alignsTextToTop
    }

    /// 가려야 하는 원문 문단 영역
    public var sourceRect: CGRect {
        CGRect(origin: sourceOrigin, size: sourceSize)
    }
}

/// 번역 렌즈의 배치 계산.
///
/// - 렌즈 안 좌표: 렌즈 왼쪽 위 원점, 포인트 단위 (캡처 이미지 픽셀 ÷ 화면 배율)
/// - 창 좌표: 전역 AppKit 좌표 (주 화면 왼쪽 아래 원점, y 위로)
public enum LensGeometry {
    /// 번역 문단과 이웃 블록 사이 여백
    public static let spacing: CGFloat = 4
    /// 번역 글자 크기 범위. 원문 크기를 따르되 너무 작거나 큰 글자만 막는다 (24pt 상한은 전체 화면 자막·큰 제목을 작게 만들었다)
    public static let fontSizeRange: ClosedRange<CGFloat> = 9...72
    /// 글자 크기 ÷ OCR 줄 상자 높이. 알고 있는 크기로 그린 영어·한국어·일본어 문장 105회 인식의 중간값 (TASK-040).
    /// 캡처에서 잰 크기(`TextStyleMeter`)가 없을 때(자막, 잴 수 없는 줄)만 쓴다
    public static let fontSizePerLineHeight: CGFloat = 0.93
    public static let minimumLensSize = CGSize(width: 160, height: 80)
    /// 렌즈가 좁아도 도구 막대 버튼이 다 보이는 너비 (영상을 볼 때 나오는 "원문 함께" 버튼까지, 340에서는 "원문"이 "…"로 줄었다)
    public static let minimumToolbarWidth: CGFloat = 376

    /// 문단을 원문 위치(왼쪽 위)에 그대로 둔다. 번역이 길어도 다른 문단을 밀지 않는다.
    /// - 너비: 여러 줄 문단은 원문 너비(다단 레이아웃 유지). 한 줄 문단(제목·버튼)은 번역이 길어질 수 있으므로
    ///   오른쪽 이웃 앞이나 렌즈 끝까지. 문단 영역 안에서 시작하는 블록은 이웃으로 보지 않는다
    /// - 높이: 아래 블록 앞이나 렌즈 아래 끝까지 (원문 높이보다 작게 하지는 않는다)
    /// - 가운데 정렬 자막(`captions`, `CaptionDetector`): 번역을 자막 자리의 가운데·아래 끝에 맞춘다. 너비는 그 가운데를 중심으로
    ///   렌즈 안에서 넓힐 수 있는 만큼, 높이는 위 블록 앞이나 렌즈 위 끝까지 위로 쓴다. 자막이 바뀌어도 번역 자리가 그대로다
    /// - `showsSourceCaptions`(이중 자막): 자막은 원문을 가리지 않고 번역을 원문 위나 아래에 둔다(`bilingualCaptionFrame`)
    public static func paragraphFrames(
        of blocks: [TextBlock], scale: CGFloat, lensSize: CGSize, captions: [CaptionAnchor?] = [],
        showsSourceCaptions: Bool = false
    ) -> [ParagraphFrame] {
        let boxes = blocks.map { block in
            let box = block.boundingBox
            return CGRect(
                x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale)
        }
        return zip(blocks, boxes).enumerated().map { index, item in
            let (block, box) = item
            if captions.indices.contains(index), let anchor = captions[index] {
                if showsSourceCaptions,
                    let frame = bilingualCaptionFrame(
                        of: box, lines: block.lines.count, at: anchor, scale: scale, among: boxes, lensSize: lensSize)
                {
                    return frame
                }
                return captionFrame(
                    of: box, lines: block.lines.count, at: anchor, scale: scale, among: boxes, lensSize: lensSize)
            }
            let rightNeighbor = boxes.filter { other in
                other.minX >= box.maxX && other.minY < box.maxY && other.maxY > box.minY
            }
            .map(\.minX).min()
            let right = min(rightNeighbor.map { $0 - spacing } ?? lensSize.width, lensSize.width)
            let width = block.lines.count > 1 ? box.width : max(box.width, right - box.minX)
            let below = boxes.filter { other in
                other.minY > box.minY && other.minX < box.minX + width && other.maxX > box.minX
            }
            .map(\.minY).min()
            let bottom = min(below.map { $0 - spacing } ?? lensSize.height, lensSize.height)
            return ParagraphFrame(
                origin: box.origin, width: width, maxHeight: max(box.height, bottom - box.minY), sourceSize: box.size,
                sourceLineCount: block.lines.count)
        }
    }

    private static func captionFrame(
        of box: CGRect, lines: Int, at anchor: CaptionAnchor, scale: CGFloat, among boxes: [CGRect], lensSize: CGSize
    ) -> ParagraphFrame {
        let centerX = anchor.centerX / scale
        let bottom = anchor.bottom / scale
        let halfWidth = max(box.width / 2, min(centerX, lensSize.width - centerX) - spacing)
        let left = centerX - halfWidth
        let above = boxes.filter { other in
            other.maxY <= box.minY && other.minX < left + halfWidth * 2 && other.maxX > left
        }
        .map(\.maxY).max()
        let top = max(above.map { $0 + spacing } ?? 0, 0)
        let maxHeight = max(box.height, bottom - top)
        return ParagraphFrame(
            origin: CGPoint(x: left, y: bottom - maxHeight), width: halfWidth * 2, maxHeight: maxHeight,
            sourceSize: box.size, sourceOrigin: box.origin, isCentered: true, sourceLineCount: lines)
    }

    /// 이중 자막 번역과 원문 자막 사이 간격
    static let bilingualGap: CGFloat = 6

    /// 이중 자막(TASK-050): 원문 자막을 가리지 않고 번역을 그 위에, 위에 자리가 없으면 아래에 둔다. 위 자리는 이 자막 자리에 나온
    /// 가장 높은 자막(`CaptionAnchor.height`) 위에 고정해 자막이 한 줄·두 줄로 바뀌어도 번역이 움직이지 않는다.
    /// 그 높이만큼 위·아래 모두 자리가 없으면 위에 한 줄 자리라도 있을 때 위(글자를 줄인다), 그것도 없으면 nil (원문을 가리고 그린다:
    /// 자막 띠만 덮은 얇은 렌즈)
    private static func bilingualCaptionFrame(
        of box: CGRect, lines: Int, at anchor: CaptionAnchor, scale: CGFloat, among boxes: [CGRect], lensSize: CGSize
    ) -> ParagraphFrame? {
        let centerX = anchor.centerX / scale
        let bottom = anchor.bottom / scale
        let reserved = max(anchor.height / scale, box.height)
        let halfWidth = max(box.width / 2, min(centerX, lensSize.width - centerX) - spacing)
        let left = centerX - halfWidth
        let overlaps = { (other: CGRect) in other.minX < left + halfWidth * 2 && other.maxX > left }
        let aboveTop = max(
            boxes.filter { $0.maxY <= box.minY && overlaps($0) }.map(\.maxY).max().map { $0 + spacing } ?? 0, 0)
        let aboveBottom = bottom - reserved - bilingualGap
        let belowTop = bottom + bilingualGap
        let belowBottom = min(
            boxes.filter { $0.minY >= box.maxY && overlaps($0) }.map(\.minY).min().map { $0 - spacing }
                ?? lensSize.height, lensSize.height)
        let frame = { (top: CGFloat, bottom: CGFloat, alignsTextToTop: Bool) in
            ParagraphFrame(
                origin: CGPoint(x: left, y: top), width: halfWidth * 2, maxHeight: bottom - top, sourceSize: box.size,
                sourceOrigin: box.origin, isCentered: true, sourceLineCount: lines, showsSource: true,
                alignsTextToTop: alignsTextToTop)
        }
        if aboveBottom - aboveTop >= reserved {
            return frame(aboveTop, aboveBottom, false)
        }
        if belowBottom - belowTop >= reserved {
            return frame(belowTop, belowBottom, true)
        }
        if aboveBottom - aboveTop >= anchor.lineHeight / scale {
            return frame(aboveTop, aboveBottom, false)
        }
        return nil
    }

    /// 자막 번역을 원문처럼 `lines`줄로 고르게 나누는 너비. 자막 자리는 렌즈 너비만큼 넓어 두 줄 자막의 번역이 한 줄로 펴졌다(TASK-046).
    /// - 원문 너비(`sourceWidth`) 안에 원문 줄 수로 들어가면 원문 너비 (짧은 번역은 나누지 않는다)
    /// - 아니면 원문 줄 수로 들어가는 가장 좁은 너비라 줄 길이가 고르다. 최대 너비에서도 줄이 더 필요하면 그 줄 수로
    /// - `height(w)`: 너비 w로 줄바꿈했을 때 글 높이, `lineHeight`: 한 줄 높이
    public static func balancedWidth(
        lines: Int, sourceWidth: CGFloat, maxWidth: CGFloat, lineHeight: CGFloat, height: (CGFloat) -> CGFloat
    ) -> CGFloat {
        guard lineHeight > 0 else { return maxWidth }
        // 높이는 줄 높이의 배수이므로 반 줄 여유를 두고 비교한다
        let allowed = max(height(maxWidth), CGFloat(lines) * lineHeight) + lineHeight / 2
        var low = min(sourceWidth, maxWidth)
        guard height(low) > allowed else { return low }
        var high = maxWidth
        while high - low > 1 {
            let middle = (low + high) / 2
            if height(middle) <= allowed {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    /// 캡처 위·아래 끝에서 이만큼(픽셀) 안에 닿은 문단은 잘린 것으로 본다
    public static let edgeMargin: CGFloat = 6

    /// 렌즈 위·아래 끝에 걸쳐 일부만 보이는 문단인지. 스크롤할 때마다 보이는 글이 바뀌므로 번역을 뒤로 미룬다
    public static func isCutOff(_ block: TextBlock, imageHeight: CGFloat) -> Bool {
        block.boundingBox.minY <= edgeMargin || block.boundingBox.maxY >= imageHeight - edgeMargin
    }

    /// 원래 글자 크기에 맞춘 번역 글자 크기. OCR 줄 높이는 글자 크기와 비슷하다(`fontSizePerLineHeight`).
    /// 아래로 내려가는 글자(g, y 등)가 없는 줄은 낮게 잡히므로 문단에서 가장 높은 줄을 기준으로 한다.
    public static func fontSize(of block: TextBlock, scale: CGFloat) -> CGFloat {
        fontSize(lineHeight: block.lines.map(\.boundingBox.height).max() ?? 0, scale: scale)
    }

    /// 줄 높이(이미지 픽셀)에 맞춘 번역 글자 크기. 자막은 기억한 줄 높이(`CaptionAnchor.lineHeight`)로 정해 크기가 흔들리지 않게 한다
    public static func fontSize(lineHeight: CGFloat, scale: CGFloat) -> CGFloat {
        fontSize(pixelSize: lineHeight * fontSizePerLineHeight, scale: scale)
    }

    /// 원문 글자 크기(이미지 픽셀)를 번역 글자 크기(포인트)로
    public static func fontSize(pixelSize: CGFloat, scale: CGFloat) -> CGFloat {
        min(max(pixelSize / scale, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// 도구 막대 위치. 렌즈 바로 위에 두고, 화면 위쪽에 공간이 없으면 렌즈 안 위쪽에 둔다.
    public static func toolbarFrame(height: CGFloat, for lens: CGRect, in visibleFrame: CGRect) -> CGRect {
        let y = lens.maxY + height <= visibleFrame.maxY ? lens.maxY : lens.maxY - height
        return CGRect(x: lens.minX, y: y, width: max(lens.width, minimumToolbarWidth), height: height)
    }

    /// 번역 기록 패널 크기와 렌즈와의 간격
    public static let transcriptWidth: CGFloat = 320
    public static let minimumTranscriptHeight: CGFloat = 260
    /// 사용자가 줄일 수 있는 번역 기록 패널 최소 크기
    public static let minimumTranscriptSize = CGSize(width: 220, height: 160)
    static let transcriptGap: CGFloat = 8

    /// 번역 기록 패널 자리. 렌즈(도구 막대가 더 넓으면 도구 막대) 오른쪽, 공간이 없으면 렌즈 왼쪽, 둘 다 없으면 화면 오른쪽
    /// 안쪽(렌즈와 겹침). 아래를 렌즈 아래와 맞추고 위로 렌즈 높이(최소 `minimumTranscriptHeight`)만큼 둔다: 자막 렌즈는
    /// 얇으므로 패널이 영상 옆으로 올라간다. 사용자가 크기를 바꿨으면(`size`) 그 크기로 둔다. 화면 안으로 자른다.
    public static func transcriptFrame(for lens: CGRect, in visibleFrame: CGRect, size: CGSize? = nil) -> CGRect {
        let width = min(size?.width ?? transcriptWidth, visibleFrame.width)
        let height = min(size?.height ?? max(lens.height, minimumTranscriptHeight), visibleFrame.height)
        let right = max(lens.maxX, lens.minX + minimumToolbarWidth) + transcriptGap
        let left = lens.minX - transcriptGap - width
        let x =
            if right + width <= visibleFrame.maxX {
                right
            } else if left >= visibleFrame.minX {
                left
            } else {
                visibleFrame.maxX - width
            }
        let y = min(max(lens.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// 오른쪽 아래 모서리를 끌어 크기를 바꾼다(렌즈, 번역 기록 패널). 왼쪽 위는 고정하고 최소 크기를 지킨다.
    /// `drag`는 전역 AppKit 좌표의 마우스 이동량이라 아래로 끌면 dy가 음수다.
    public static func resized(_ rect: CGRect, by drag: CGSize, minimum: CGSize = minimumLensSize) -> CGRect {
        let width = max(minimum.width, rect.width + drag.width)
        let height = max(minimum.height, rect.height - drag.height)
        return CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
    }
}
