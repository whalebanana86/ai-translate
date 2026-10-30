import SwiftUI

@main
struct AITranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AI Translate", systemImage: "character.bubble") {
            Button("번역 렌즈 만들기") {
                appDelegate.translateRegion()
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("설정…") {
                appDelegate.showSettings()
            }
            .keyboardShortcut(",")
            Divider()
            Button("종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
