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
    /// 너무 촘촘히 찍지 않는 하한
    static let minimumDelay: Duration = .milliseconds(20)

    public static func delay(
        isChanging: Bool, lastScroll: ContinuousClock.Instant?, now: ContinuousClock.Instant
    ) -> Duration {
        if let lastScroll, now - lastScroll < scrollQuiet {
            return max(minimumDelay, lastScroll + scrollQuiet - now)
        }
        return isChanging ? activeInterval : idleInterval
    }
}
