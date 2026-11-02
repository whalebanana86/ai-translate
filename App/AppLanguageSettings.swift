import AppKit
import Observation
import TranslateCore

/// 앱 화면 언어 고르기 (TASK-058, 설정 창). 화면 글은 앱이 시작할 때 정해지므로 바꾸면 다시 시작해야 적용된다
@MainActor
@Observable
final class AppLanguageSettings {
    /// 이번 실행의 화면 언어 (앱이 시작할 때 `Bundle.main`이 고른 것)
    private let launchedLocalization = Bundle.main.preferredLocalizations.first

    var language = AppLanguage.current(in: .standard, domain: Bundle.main.bundleIdentifier ?? "") {
        didSet { language.apply(to: .standard) }
    }

    /// 고른 언어가 지금 화면 언어와 다르다 (시스템 언어가 한국어면 시스템 설정 → 한국어는 다시 시작하지 않아도 된다)
    var needsRestart: Bool {
        let preferences = language == .system ? AppLanguage.systemLanguages() : [language.rawValue]
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences).first
            != launchedLocalization
    }

    /// 이 앱이 끝나기를 기다렸다가 다시 연다. 같은 앱 둘이 함께 뜨면 메뉴바 아이콘과 단축키가 겹친다
    func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c", #"while kill -0 "$0" 2>/dev/null; do sleep 0.1; done; open "$1""#,
            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
        ]
        guard (try? process.run()) != nil else { return }
        NSApp.terminate(nil)
    }
}
