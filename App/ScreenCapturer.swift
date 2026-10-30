import Foundation
import ScreenCaptureKit
import TranslateCore

/// 선택한 영역을 ScreenCaptureKit으로 원본 픽셀 해상도로 캡처한다.
///
/// 렌즈는 0.15~0.5초마다 캡처하므로, 화면의 창 목록 조회(`SCShareableContent`)와 필터는 화면별로 잠깐 재사용한다.
@MainActor
final class ScreenCapturer {
    enum CaptureError: LocalizedError {
        case displayNotFound

        var errorDescription: String? {
            "선택한 화면을 찾을 수 없습니다. 모니터 연결이 바뀌었다면 다시 시도하세요."
        }
    }

    /// 필터를 다시 쓰는 시간. 이 앱의 창은 앱 단위로 빼므로 새로 뜬 렌즈 창도 계속 빠진다
    private static let filterLifetime: Duration = .seconds(5)

    private var cached: (displayID: CGDirectDisplayID, filter: SCContentFilter, fetchedAt: ContinuousClock.Instant)?

    func capture(_ selection: ScreenSelection) async throws -> CGImage {
        let filter = try await filter(for: selection.displayID)
        let configuration = SCStreamConfiguration()
        let size = ScreenGeometry.pixelSize(of: selection.rect, scale: selection.scale)
        configuration.sourceRect = selection.rect
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            // 화면 구성이 바뀌었을 수 있으니 다음에는 다시 조회한다
            cached = nil
            throw error
        }
    }

    private func filter(for displayID: CGDirectDisplayID) async throws -> SCContentFilter {
        if let cached, cached.displayID == displayID, ContinuousClock.now - cached.fetchedAt < Self.filterLifetime {
            return cached.filter
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        // 이 앱의 창(오버레이·렌즈)은 캡처에서 뺀다
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        cached = (displayID, filter, .now)
        return filter
    }
}
