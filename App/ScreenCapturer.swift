import Foundation
import ScreenCaptureKit
import TranslateCore

/// 선택한 영역을 ScreenCaptureKit으로 원본 픽셀 해상도로 캡처한다.
struct ScreenCapturer {
    enum CaptureError: LocalizedError {
        case displayNotFound

        var errorDescription: String? {
            "선택한 화면을 찾을 수 없습니다. 모니터 연결이 바뀌었다면 다시 시도하세요."
        }
    }

    func capture(_ selection: ScreenSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // 이 앱의 창(오버레이·결과창)은 캡처에서 뺀다
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        let size = ScreenGeometry.pixelSize(of: selection.rect, scale: selection.scale)
        configuration.sourceRect = selection.rect
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
