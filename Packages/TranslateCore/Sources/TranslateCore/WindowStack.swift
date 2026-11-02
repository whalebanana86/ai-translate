import CoreGraphics

/// 화면의 창 하나. 좌표는 창 목록 좌표(주 화면 왼쪽 위 원점, y는 아래로)
public struct WindowInfo: Equatable, Sendable {
    public var number: Int
    public var bounds: CGRect

    public init(number: Int, bounds: CGRect) {
        self.number = number
        self.bounds = bounds
    }
}

/// 앞에서부터 놓인 창 목록에서 어떤 점 위에 있는 창을 찾는다.
/// 렌즈 밖에서 스크롤해도 렌즈 아래와 같은 창이면 렌즈 아래 내용이 움직이므로 번역을 바로 숨기는 데 쓴다.
public enum WindowStack {
    /// 점을 덮는 가장 앞 창 번호
    public static func topmost(at point: CGPoint, in windows: [WindowInfo]) -> Int? {
        windows.first { $0.bounds.contains(point) }?.number
    }

    /// 두 점이 같은 창 위에 있는지. 어느 쪽이든 창이 없으면 false
    public static func sameWindow(_ first: CGPoint, _ second: CGPoint, in windows: [WindowInfo]) -> Bool {
        guard let window = topmost(at: first, in: windows) else { return false }
        return topmost(at: second, in: windows) == window
    }
}
