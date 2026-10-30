import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 기본값 ⌘⇧1. 시스템 스크린샷 단축키(⌘⇧3·4·5)와 겹치지 않는다
    static let translateRegion = Self("translateRegion", initial: .init(.one, modifiers: [.command, .shift]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lens = TranslationLensController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyUp(for: .translateRegion) { [weak self] in
            self?.translateRegion()
        }
    }

    func translateRegion() {
        lens.start()
    }
}
