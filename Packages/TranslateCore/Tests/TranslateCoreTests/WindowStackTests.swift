import CoreGraphics
import Testing

@testable import TranslateCore

struct WindowStackTests {
    /// 앞에서부터: 작은 대화상자, 브라우저 창, 그 뒤 편집기 창
    private let windows = [
        WindowInfo(number: 3, bounds: CGRect(x: 500, y: 300, width: 300, height: 200)),
        WindowInfo(number: 1, bounds: CGRect(x: 0, y: 25, width: 1200, height: 900)),
        WindowInfo(number: 2, bounds: CGRect(x: 1000, y: 25, width: 700, height: 900)),
    ]

    @Test func findsFrontmostWindowUnderPoint() {
        #expect(WindowStack.topmost(at: CGPoint(x: 600, y: 400), in: windows) == 3)
        #expect(WindowStack.topmost(at: CGPoint(x: 100, y: 400), in: windows) == 1)
        // 브라우저와 편집기가 겹친 곳은 앞에 있는 브라우저
        #expect(WindowStack.topmost(at: CGPoint(x: 1100, y: 400), in: windows) == 1)
        #expect(WindowStack.topmost(at: CGPoint(x: 1500, y: 400), in: windows) == 2)
        #expect(WindowStack.topmost(at: CGPoint(x: 1800, y: 400), in: windows) == nil)
    }

    @Test func tellsWhetherScrollHappensInWindowUnderLens() {
        let lensCenter = CGPoint(x: 300, y: 600)

        // 렌즈 밖이지만 같은 브라우저 창 → 렌즈 아래 내용이 움직인다
        #expect(WindowStack.sameWindow(lensCenter, CGPoint(x: 900, y: 800), in: windows))
        // 다른 창(편집기, 대화상자) 또는 창 없는 곳
        #expect(!WindowStack.sameWindow(lensCenter, CGPoint(x: 1500, y: 400), in: windows))
        #expect(!WindowStack.sameWindow(lensCenter, CGPoint(x: 600, y: 400), in: windows))
        #expect(!WindowStack.sameWindow(CGPoint(x: 1800, y: 10), CGPoint(x: 1800, y: 10), in: windows))
    }

    @Test func convertsGlobalPointToWindowListCoordinates() {
        // 주 화면 높이 1117: 전역 좌표(왼쪽 아래 원점) y 1017 → 창 목록 좌표(왼쪽 위 원점) y 100
        #expect(
            ScreenGeometry.windowListPoint(CGPoint(x: 40, y: 1017), mainScreenHeight: 1117) == CGPoint(x: 40, y: 100))
    }
}
