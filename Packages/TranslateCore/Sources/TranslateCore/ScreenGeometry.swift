import CoreGraphics

/// 화면 영역 선택과 캡처에 쓰는 좌표 계산. 좌표 변환은 이 타입에서만 한다.
///
/// - 전역 좌표: AppKit 기준. 주 화면 왼쪽 아래가 원점이고 y는 위로 증가한다 (`NSScreen.frame`, `NSEvent` 위치)
/// - 디스플레이 로컬 좌표: 각 디스플레이 왼쪽 위가 원점이고 y는 아래로 증가하는 포인트 단위
///   (ScreenCaptureKit `SCStreamConfiguration.sourceRect`)
public enum ScreenGeometry {
    /// 실수로 클릭한 것과 구분하기 위한 최소 선택 크기(포인트)
    public static let minimumSelectionSide: CGFloat = 8

    /// 드래그 시작점과 끝점으로 만든 사각형. 드래그 방향과 관계없이 너비·높이가 양수다.
    public static func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x),
            height: abs(end.y - start.y))
    }

    public static func isSelectable(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelectionSide && rect.height >= minimumSelectionSide
    }

    /// 선택 영역을 화면 안으로 자른다. 화면과 겹치지 않으면 nil.
    public static func clamp(_ rect: CGRect, to screenFrame: CGRect) -> CGRect? {
        let clipped = rect.intersection(screenFrame)
        return clipped.isNull || clipped.isEmpty ? nil : clipped
    }

    /// 전역 좌표의 영역을 그 화면의 디스플레이 로컬 좌표로 바꾼다.
    public static func displayLocalRect(_ globalRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: globalRect.minX - screenFrame.minX, y: screenFrame.maxY - globalRect.maxY,
            width: globalRect.width, height: globalRect.height)
    }

    /// 포인트 영역의 픽셀 크기. 경계가 잘리지 않게 올림한다.
    public static func pixelSize(of rect: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((rect.width * scale).rounded(.up)), Int((rect.height * scale).rounded(.up)))
    }
}
