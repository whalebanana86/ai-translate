import AppKit
import SwiftUI

/// 설정 창. 엔진을 아직 고르지 않았으면(처음 실행) 같은 화면을 시작 안내로 띄운다.
/// 메뉴바 앱(LSUIElement)은 창을 띄울 때 앱을 활성화해야 앞으로 나온다.
@MainActor
final class SettingsWindowController {
    private let settings: EngineSettings
    private var window: NSWindow?

    init(settings: EngineSettings) {
        self.settings = settings
    }

    func show(onboarding: Bool) {
        window?.close()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = onboarding ? "AI Translate 시작하기" : "설정"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SettingsView(settings: settings, isOnboarding: onboarding) { [weak window] in
                window?.close()
            })
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
