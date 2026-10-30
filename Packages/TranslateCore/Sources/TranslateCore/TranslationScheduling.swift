/// 렌즈의 번역 요청 순서·취소 판단.
public enum TranslationScheduling {
    /// 진행 중인 요청의 문단 가운데 지금 화면에 남은 것이 절반 미만이면 요청을 버린다.
    /// 스크롤로 지나간 화면을 번역하느라 새 화면이 기다리지 않게 한다 (Claude 16문단 요청이 20초 넘게 걸린 측정, TASK-019)
    public static func shouldAbandon(inFlight: [String], visible: Set<String>) -> Bool {
        guard !inFlight.isEmpty else { return false }
        let remaining = inFlight.filter(visible.contains).count
        return remaining * 2 < inFlight.count
    }
}
