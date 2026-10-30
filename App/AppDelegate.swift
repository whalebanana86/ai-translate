import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 기본값 ⌘⇧1. 시스템 스크린샷 단축키(⌘⇧3·4·5)와 겹치지 않는다
    static let translateRegion = Self("translateRegion", initial: .init(.one, modifiers: [.command, .shift]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = EngineSettings()
    private lazy var lens = TranslationLensController(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyUp(for: .translateRegion) { [weak self] in
            self?.translateRegion()
        }
        settings.onEngineChange = { [weak self] in self?.lens.engineDidChange() }
        settings.onMemoryClear = { [weak self] in self?.lens.memoryDidClear() }
        // 처음 실행: 번역 엔진부터 고른다. 이미 골랐으면 렌즈를 열기 전에 엔진을 미리 준비한다
        if settings.engine == nil {
            settingsWindow.show(onboarding: true)
        } else {
            settings.prepare()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        lens.saveMemory()
    }

    func translateRegion() {
        guard settings.engine != nil else {
            settingsWindow.show(onboarding: true)
            return
        }
        lens.start()
    }

    func showSettings() {
        settingsWindow.show(onboarding: false)
    }
}
