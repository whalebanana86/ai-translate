import AppKit

/// 첫 번역 전에 한 번, 선택 영역의 텍스트가 외부 번역 엔진으로 전송된다는 사실을 알린다 (AGENTS.md 개인정보 규칙).
enum DataTransmissionNotice {
    private static let acceptedKey = "DataTransmissionNoticeAccepted"

    @MainActor
    static func confirm() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: acceptedKey) {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "선택한 영역의 텍스트가 번역을 위해 전송됩니다"
        alert.informativeText =
            "화면에서 인식한 텍스트는 이 Mac에 설치된 Claude Code를 통해 Anthropic으로 전송되어 번역됩니다. "
            + "캡처한 이미지는 전송하지 않으며, 텍스트 인식은 이 Mac 안에서만 처리합니다."
        alert.addButton(withTitle: "계속")
        alert.addButton(withTitle: "취소")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        defaults.set(true, forKey: acceptedKey)
        return true
    }
}
