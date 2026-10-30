import AppKit
import TranslateCore

/// 외부 번역 엔진으로 처음 번역하기 전에 한 번, 선택 영역의 텍스트가 어디로 전송되는지 알린다 (AGENTS.md 개인정보 규칙).
/// 엔진마다 전송 대상이 다르므로 엔진별로 한 번씩 묻는다. 로컬 엔진은 전송하지 않으므로 묻지 않는다.
enum DataTransmissionNotice {
    /// Claude Code는 엔진 선택이 생기기 전부터 쓰던 키를 그대로 쓴다
    private static func acceptedKey(for engine: TranslationEngine) -> String {
        engine == .claudeCode ? "DataTransmissionNoticeAccepted" : "DataTransmissionNoticeAccepted.\(engine.rawValue)"
    }

    @MainActor
    static func confirm(for engine: TranslationEngine) -> Bool {
        guard let destination = engine.transmissionDestination else { return true }
        let defaults = UserDefaults.standard
        let key = acceptedKey(for: engine)
        if defaults.bool(forKey: key) {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "선택한 영역의 텍스트가 번역을 위해 전송됩니다"
        alert.informativeText =
            "화면에서 인식한 텍스트는 이 Mac에 설치된 \(destination)으로 전송되어 번역됩니다. "
            + "캡처한 이미지는 전송하지 않으며, 텍스트 인식은 이 Mac 안에서만 처리합니다."
        alert.addButton(withTitle: "계속")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        defaults.set(true, forKey: key)
        return true
    }
}
