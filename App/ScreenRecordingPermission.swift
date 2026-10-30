import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    private static let requestedKey = "ScreenRecordingPermissionRequested"
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// 화면 기록 권한이 있으면 true.
    ///
    /// 처음에는 시스템 요청만 띄운다 (시스템 창과 겹치지 않게). 그 뒤에도 권한이 없으면 시스템 설정으로 안내한다.
    /// 권한을 허용한 뒤에는 앱을 다시 실행해야 적용된다.
    @MainActor
    static func ensure() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: requestedKey) {
            defaults.set(true, forKey: requestedKey)
            return CGRequestScreenCaptureAccess()
        }

        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText =
            "시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹화에서 AI Translate를 허용한 뒤 앱을 다시 실행하세요."
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
        return false
    }
}
