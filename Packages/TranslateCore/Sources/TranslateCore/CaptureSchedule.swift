/// 렌즈가 다음 화면을 찍을 때까지 기다리는 시간.
///
/// 처리는 바뀐 화면이 한 번 더 같게 찍혀야(멈춤) 시작하므로, 바뀌는 동안은 자주 찍어 멈춤을 빨리 확인한다.
/// 0.5초 간격만 쓰면 스크롤을 멈추고 인식 시작까지 0.5~1.0초가 걸렸다 (TASK-019).
public enum CaptureSchedule {
    /// 화면이 그대로일 때
    public static let idleInterval: Duration = .milliseconds(500)
    /// 화면이 바뀌는 중일 때
    public static let activeInterval: Duration = .milliseconds(150)
    /// 스크롤 이벤트가 이만큼 없으면 스크롤이 멈춘 것으로 보고 바로 찍는다
    public static let scrollQuiet: Duration = .milliseconds(150)
    /// 포인터가 렌즈 위에서 움직이거나 누른 뒤 이 시간 동안은 화면이 그대로여도 바뀌는 중일 때 간격으로 찍는다.
    /// 메뉴는 포인터를 올리거나 누르면 열리고 닫히는데, 0.5초 간격이면 그만큼 열린 메뉴 위에 지난 번역이, 닫힌 메뉴 자리에
    /// 메뉴 번역이 남았다 (TASK-072)
    public static let pointerActivePeriod: Duration = .seconds(1)
    /// 너무 촘촘히 찍지 않는 하한
    static let minimumDelay: Duration = .milliseconds(20)

    public static func delay(
        isChanging: Bool, lastScroll: ContinuousClock.Instant?, lastPointerActivity: ContinuousClock.Instant? = nil,
        now: ContinuousClock.Instant
    ) -> Duration {
        if let lastScroll, now - lastScroll < scrollQuiet {
            return max(minimumDelay, lastScroll + scrollQuiet - now)
        }
        let isPointerActive = lastPointerActivity.map { now - $0 < pointerActivePeriod } ?? false
        return isChanging || isPointerActive ? activeInterval : idleInterval
    }
}
