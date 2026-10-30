import CoreGraphics
import Testing

@testable import TranslateCore

struct ScreenGeometryTests {
    @Test(arguments: [
        (CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 70)),
        (CGPoint(x: 110, y: 70), CGPoint(x: 10, y: 20)),
        (CGPoint(x: 10, y: 70), CGPoint(x: 110, y: 20)),
        (CGPoint(x: 110, y: 20), CGPoint(x: 10, y: 70)),
    ])
    func selectionRectIsSameForAnyDragDirection(start: CGPoint, end: CGPoint) {
        #expect(ScreenGeometry.selectionRect(from: start, to: end) == CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    @Test func rejectsSelectionsSmallerThanMinimum() {
        #expect(!ScreenGeometry.isSelectable(CGRect(x: 0, y: 0, width: 7.9, height: 100)))
        #expect(!ScreenGeometry.isSelectable(CGRect(x: 0, y: 0, width: 100, height: 0)))
        #expect(ScreenGeometry.isSelectable(CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    @Test func clampsSelectionToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

        #expect(
            ScreenGeometry.clamp(CGRect(x: 1400, y: 900, width: 300, height: 200), to: screen)
                == CGRect(x: 1400, y: 900, width: 112, height: 82))
        #expect(ScreenGeometry.clamp(CGRect(x: 1600, y: 0, width: 100, height: 100), to: screen) == nil)
        #expect(ScreenGeometry.clamp(CGRect(x: 1512, y: 0, width: 100, height: 100), to: screen) == nil)
    }

    @Test func convertsPrimaryDisplayToTopLeftLocalPoints() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // 화면 위에서 100pt 아래, 왼쪽에서 100pt
        let global = CGRect(x: 100, y: 682, width: 300, height: 200)

        #expect(
            ScreenGeometry.displayLocalRect(global, screenFrame: screen)
                == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test func convertsSecondaryDisplayAbovePrimary() {
        // 주 화면 위쪽에 왼쪽으로 치우쳐 놓인 외장 모니터
        let screen = CGRect(x: -524, y: 982, width: 2560, height: 1440)
        let global = CGRect(x: -424, y: 2222, width: 400, height: 100)

        #expect(
            ScreenGeometry.displayLocalRect(global, screenFrame: screen)
                == CGRect(x: 100, y: 100, width: 400, height: 100))
    }

    @Test func convertsDisplayWithNegativeOrigin() {
        // 주 화면 왼쪽 아래로 내려간 모니터
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let global = CGRect(x: -1820, y: 680, width: 200, height: 100)

        #expect(
            ScreenGeometry.displayLocalRect(global, screenFrame: screen)
                == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func pixelSizeUsesScaleAndRoundsUp() {
        let rect = CGRect(x: 0, y: 0, width: 100.5, height: 50.25)

        #expect(ScreenGeometry.pixelSize(of: rect, scale: 2) == (201, 101))
        #expect(ScreenGeometry.pixelSize(of: rect, scale: 1) == (101, 51))
    }
}
