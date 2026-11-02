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

    public init(
        origin: CGPoint, width: CGFloat, maxHeight: CGFloat, sourceSize: CGSize, sourceOrigin: CGPoint? = nil,
        isCentered: Bool = false
    ) {
        self.origin = origin
        self.width = width
        self.maxHeight = maxHeight
        self.sourceSize = sourceSize
        self.sourceOrigin = sourceOrigin ?? origin
        self.isCentered = isCentered
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
    public static let fontSizeRange: ClosedRange<CGFloat> = 11...24
    public static let minimumLensSize = CGSize(width: 160, height: 80)
    /// 렌즈가 좁아도 도구 막대 버튼이 다 보이는 너비
    public static let minimumToolbarWidth: CGFloat = 340

    /// 문단을 원문 위치(왼쪽 위)에 그대로 둔다. 번역이 길어도 다른 문단을 밀지 않는다.
    /// - 너비: 여러 줄 문단은 원문 너비(다단 레이아웃 유지). 한 줄 문단(제목·버튼)은 번역이 길어질 수 있으므로
    ///   오른쪽 이웃 앞이나 렌즈 끝까지. 문단 영역 안에서 시작하는 블록은 이웃으로 보지 않는다
    /// - 높이: 아래 블록 앞이나 렌즈 아래 끝까지 (원문 높이보다 작게 하지는 않는다)
    /// - 가운데 정렬 자막(`captions`, `CaptionDetector`): 번역을 자막 자리의 가운데·아래 끝에 맞춘다. 너비는 그 가운데를 중심으로
    ///   렌즈 안에서 넓힐 수 있는 만큼, 높이는 위 블록 앞이나 렌즈 위 끝까지 위로 쓴다. 자막이 바뀌어도 번역 자리가 그대로다
    public static func paragraphFrames(
        of blocks: [TextBlock], scale: CGFloat, lensSize: CGSize, captions: [CaptionAnchor?] = []
    ) -> [ParagraphFrame] {
        let boxes = blocks.map { block in
            let box = block.boundingBox
            return CGRect(
                x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale)
        }
        return zip(blocks, boxes).enumerated().map { index, item in
            let (block, box) = item
            if captions.indices.contains(index), let anchor = captions[index] {
                return captionFrame(of: box, at: anchor, scale: scale, among: boxes, lensSize: lensSize)
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
                origin: box.origin, width: width, maxHeight: max(box.height, bottom - box.minY), sourceSize: box.size)
        }
    }

    private static func captionFrame(
        of box: CGRect, at anchor: CaptionAnchor, scale: CGFloat, among boxes: [CGRect], lensSize: CGSize
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
            sourceSize: box.size, sourceOrigin: box.origin, isCentered: true)
    }

    /// 캡처 위·아래 끝에서 이만큼(픽셀) 안에 닿은 문단은 잘린 것으로 본다
    public static let edgeMargin: CGFloat = 6

    /// 렌즈 위·아래 끝에 걸쳐 일부만 보이는 문단인지. 스크롤할 때마다 보이는 글이 바뀌므로 번역을 뒤로 미룬다
    public static func isCutOff(_ block: TextBlock, imageHeight: CGFloat) -> Bool {
        block.boundingBox.minY <= edgeMargin || block.boundingBox.maxY >= imageHeight - edgeMargin
    }

    /// 원래 글자 크기에 맞춘 번역 글자 크기. OCR 줄 높이는 글자 크기와 비슷하다.
    /// 아래로 내려가는 글자(g, y 등)가 없는 줄은 낮게 잡히므로 문단에서 가장 높은 줄을 기준으로 한다.
    public static func fontSize(of block: TextBlock, scale: CGFloat) -> CGFloat {
        fontSize(lineHeight: block.lines.map(\.boundingBox.height).max() ?? 0, scale: scale)
    }

    /// 줄 높이(이미지 픽셀)에 맞춘 번역 글자 크기. 자막은 기억한 줄 높이(`CaptionAnchor.lineHeight`)로 정해 크기가 흔들리지 않게 한다
    public static func fontSize(lineHeight: CGFloat, scale: CGFloat) -> CGFloat {
        min(max(lineHeight / scale * 0.9, fontSizeRange.lowerBound), fontSizeRange.upperBound)
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
