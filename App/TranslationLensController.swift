import AppKit
import OSLog
import SwiftUI
import TranslateCore

/// ⌘⇧1 → 권한·고지 → 영역 드래그 → 그 영역에 번역 렌즈를 띄운다. 렌즈는 한 번에 하나이며 새로 만들면 바꾼다.
@MainActor
final class TranslationLensController {
    private static let languageKey = "TargetLanguage"
    private static let transcriptVisibleKey = "TranscriptVisible"
    private static let transcriptSizeKey = "TranscriptSize"

    private let settings: EngineSettings
    private let overlay = SelectionOverlayController()
    private let capturer = ScreenCapturer()
    private let memoryStore = TranslationMemoryStore.standard
    private var lens: LensSession?
    private var isSelecting = false

    init(settings: EngineSettings) {
        self.settings = settings
    }

    private var language: TargetLanguage {
        get {
            UserDefaults.standard.string(forKey: Self.languageKey).flatMap(TargetLanguage.init(rawValue:))
                ?? TargetLanguage.preferred(from: Locale.preferredLanguages)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.languageKey) }
    }

    func start() {
        // 영역을 고르는 중에 다시 누르면 무시한다
        guard !isSelecting else { return }
        Task { await createLens() }
    }

    private func createLens() async {
        guard ScreenRecordingPermission.ensure(), DataTransmissionNotice.confirm(for: settings.engine ?? .claudeCode)
        else { return }
        isSelecting = true
        let selection = await overlay.selectRegion()
        isSelecting = false
        guard let selection else { return }

        lens?.close()
        let session = LensSession(
            frame: selection.globalRect, language: language,
            showsTranscript: UserDefaults.standard.bool(forKey: Self.transcriptVisibleKey),
            transcriptSize: Self.savedTranscriptSize, capturer: capturer,
            engine: settings.engine ?? .claudeCode, memoryStore: memoryStore
        ) { [settings] in try await settings.makeProvider() }
        session.onLanguageChange = { [weak self] language in self?.language = language }
        session.onTranscriptVisibilityChange = { visible in
            UserDefaults.standard.set(visible, forKey: Self.transcriptVisibleKey)
        }
        session.onTranscriptSizeChange = { size in
            UserDefaults.standard.set([Double(size.width), Double(size.height)], forKey: Self.transcriptSizeKey)
        }
        session.onClose = { [weak self, weak session] in
            if self?.lens === session {
                self?.lens = nil
            }
        }
        lens = session
        session.show()
    }

    /// 사용자가 마지막으로 바꾼 번역 기록 패널 크기
    private static var savedTranscriptSize: CGSize? {
        guard let size = UserDefaults.standard.array(forKey: transcriptSizeKey) as? [Double], size.count == 2 else {
            return nil
        }
        return CGSize(width: size[0], height: size[1])
    }

    /// 설정에서 엔진을 바꾸면 열린 렌즈가 새 엔진으로 다시 번역한다. 외부로 보내는 엔진이면 먼저 고지한다
    func engineDidChange() {
        guard let lens, let engine = settings.engine else { return }
        guard DataTransmissionNotice.confirm(for: engine) else {
            lens.close()
            return
        }
        lens.changeEngine(to: engine)
    }

    /// 앱을 끌 때 열린 렌즈의 번역 기억을 저장한다
    func saveMemory() {
        lens?.saveMemory()
    }

    /// 설정에서 번역 기억을 지우면 열린 렌즈의 기억도 비운다
    func memoryDidClear() {
        lens?.clearMemory()
    }
}

/// 떠 있는 렌즈 하나. 렌즈 아래 화면을 계속 보고, 바뀌면 다시 인식해 새 문단만 번역한다.
@MainActor
final class LensSession {
    private static let toolbarHeight: CGFloat = 34
    private static let handleSize: CGFloat = 18
    /// 마지막 스크롤 뒤 이만큼 지나야 스크롤이 멈춘 것으로 본다
    private static let scrollQuietPeriod: Duration = .milliseconds(500)
    private static let aboveLens = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    var onLanguageChange: ((TargetLanguage) -> Void)?
    var onTranscriptVisibilityChange: ((Bool) -> Void)?
    var onTranscriptSizeChange: ((CGSize) -> Void)?
    var onClose: (() -> Void)?

    private let model: LensModel
    private let capturer: ScreenCapturer
    /// 렌즈 영역. 전역 AppKit 좌표
    private var frame: CGRect
    private let bodyPanel: LensPanel
    private let toolbarPanel: LensPanel
    private let handlePanel: LensPanel
    /// 렌즈 옆 번역 기록 (도구 막대에서 켰을 때만 보인다)
    private let transcriptPanel: LensPanel
    private var transcript = TranslationTranscript()
    /// 사용자가 옮긴 번역 기록 패널의 렌즈 기준 자리(패널 원점 - 렌즈 원점). 없으면 렌즈 옆 기본 자리
    private var transcriptOffset: CGPoint?
    /// 사용자가 바꾼 번역 기록 패널 크기. 없으면 기본 크기
    private var transcriptSize: CGSize?
    /// 번역 기록 패널을 끄는 중이면 시작 시점의 마우스 위치와 패널 자리
    private var transcriptDrag: (mouse: CGPoint, frame: CGRect)?

    /// 선택된 번역 엔진을 만든다 (설정이 엔진별로 기억해 둔다)
    private let makeProvider: @MainActor () async throws -> any TranslationProvider
    private var tracker = ChangeTracker()
    private var memory: TranslationMemory
    /// 기억을 저장할 엔진 (엔진을 바꾸면 그 엔진의 기억으로 바꿔 끼운다)
    private var memoryEngine: TranslationEngine
    private let memoryStore: TranslationMemoryStore
    private var translator: RegionTranslator?
    /// 엔진 준비 (렌즈를 띄울 때 시작해 OCR과 함께 진행한다)
    private var translatorTask: Task<Void, Never>?
    /// 엔진 변경 번호. 엔진이 바뀐 뒤 늦게 끝난 준비를 버린다
    private var engineGeneration = 0
    private let recognizer = TextRecognizer()
    private var blocks: [TextBlock] = []
    /// `blocks`와 같은 순서의 원문 색
    private var colors: [BlockColors] = []
    private var scale: CGFloat = 2
    /// 마지막으로 인식한 캡처 이미지 높이(픽셀). 렌즈 끝에 걸친 문단을 가린다
    private var imageHeight: CGFloat = 0
    private var loopTask: Task<Void, Never>?
    private var translateTask: Task<Void, Never>?
    /// 진행 중인 요청의 원문. 화면이 지나가면 요청을 버리는 데 쓴다
    private var inFlightTexts: [String] = []
    /// 요청 번호. 버린 요청이 늦게 끝나도 새 요청 상태를 덮어쓰지 않게 한다
    private var translateGeneration = 0
    /// 생성 중인 번역(원문 → 지금까지 나온 글). 로컬 엔진이 생성하는 대로 대기 문단 자리에 그린다
    private var partials: [String: String] = [:]
    private var lastPartialRefresh: ContinuousClock.Instant?
    /// 계속 바뀌는 화면(자막)에서 새 번역이 나올 때까지 같은 자리의 번역을 이어 보여준다
    private var carryOver = CarryOver()
    /// 계속 바뀌는 화면(자막)에서 글이 다 나온 뒤 번역한다
    private var settling = TextSettling()
    /// 지난 번역을 이어 보여주고 있는 문단의 원문. 이어 보여줄 번역이 없는 문단은 다 나오기를 기다리지 않고 바로 번역한다
    private var carriedTexts: Set<String> = []
    /// 계속 바뀌는 화면에서 가운데 정렬 자막을 찾아 번역을 자막 자리의 가운데·아래에 맞춘다
    private var captionDetector = CaptionDetector()
    /// `blocks`와 같은 순서. 가운데 정렬 자막이면 번역을 그릴 자리
    private var captions: [CaptionAnchor?] = []
    /// 중간 글로 화면을 다시 그리는 최소 간격 (생성은 초당 약 100토큰)
    private static let partialRefreshInterval: Duration = .milliseconds(50)
    /// 이동·크기 조절 중이면 시작 시점의 마우스 위치와 렌즈 영역
    private var interaction: (mouse: CGPoint, frame: CGRect)?
    private var scrollMonitor: Any?
    /// 클릭·앱 전환 감시. 계속 바뀌는 화면(영상) 처리를 끝내는 데 쓴다
    private var clickMonitor: Any?
    private var appSwitchObserver: (any NSObjectProtocol)?
    /// 렌즈 아래가 다른 내용으로 바뀌었을 수 있는 마지막 사용자 동작(스크롤·클릭·앱 전환)
    private var lastUserAction: ContinuousClock.Instant?
    /// 렌즈 위에서 마지막으로 스크롤한 때
    private var lastScroll: ContinuousClock.Instant?
    /// 마지막 캡처에서 화면이 바뀌는 중이었는지. 그동안은 자주 찍어 멈춤을 빨리 확인한다 (`CaptureSchedule`)
    private var isScreenChanging = false
    /// 화면이 바뀌기 시작한 때(렌즈 생성·스크롤·큰 변화). 번역이 다 보일 때까지의 체감 시간을 잰다
    private var changeStartedAt: ContinuousClock.Instant?

    /// 단계별 시간 기록. 숫자와 엔진 이름만 남기고 글 내용은 남기지 않는다 (AGENTS.md 개인정보).
    /// info 단계라 디스크에 저장되지 않고 `log stream`으로 볼 때만 보인다
    private static let log = Logger(subsystem: "com.example.AITranslate", category: "pipeline")

    init(
        frame: CGRect, language: TargetLanguage, showsTranscript: Bool, transcriptSize: CGSize?,
        capturer: ScreenCapturer,
        engine: TranslationEngine, memoryStore: TranslationMemoryStore,
        makeProvider: @escaping @MainActor () async throws -> any TranslationProvider
    ) {
        self.frame = frame
        self.transcriptSize = transcriptSize
        self.capturer = capturer
        self.makeProvider = makeProvider
        self.memoryStore = memoryStore
        memoryEngine = engine
        memory = memoryStore.load(engine)
        let model = LensModel(language: language, showsTranscript: showsTranscript)
        self.model = model
        bodyPanel = LensPanel(
            content: Self.hosting(LensBodyView(model: model)), level: .floating, passesMouseThrough: true)
        // 본체는 번역 문단 밖이 투명하다. 그림자를 두면 문단마다 그림자가 생긴다
        bodyPanel.hasShadow = false
        toolbarPanel = LensPanel(
            content: Self.hosting(LensToolbarView(model: model)), level: Self.aboveLens, passesMouseThrough: false)
        handlePanel = LensPanel(
            content: Self.hosting(LensResizeHandleView(model: model)), level: Self.aboveLens, passesMouseThrough: false)
        transcriptPanel = LensPanel(
            content: Self.hosting(LensTranscriptView(model: model)), level: Self.aboveLens, passesMouseThrough: false)

        model.onLanguageChange = { [weak self] language in self?.changeLanguage(to: language) }
        model.onPeekChange = { [weak self] peeking in self?.bodyPanel.alphaValue = peeking ? 0 : 1 }
        model.onTranscriptVisibilityChange = { [weak self] visible in self?.showTranscript(visible) }
        model.onPauseChange = { [weak self] paused in self?.pauseDidChange(paused) }
        model.onTranscriptMove = { [weak self] phase in
            self?.dragTranscript(phase, resizing: false) { start, drag in
                start.offsetBy(dx: drag.width, dy: drag.height)
            }
        }
        model.onTranscriptResize = { [weak self] phase in
            self?.dragTranscript(phase, resizing: true) { start, drag in
                LensGeometry.resized(start, by: drag, minimum: LensGeometry.minimumTranscriptSize)
            }
        }
        model.onClose = { [weak self] in self?.close() }
        model.onMove = { [weak self] phase in
            self?.interact(phase) { start, drag in start.offsetBy(dx: drag.width, dy: drag.height) }
        }
        model.onResize = { [weak self] phase in
            self?.interact(phase) { start, drag in LensGeometry.resized(start, by: drag) }
        }
    }

    func show() {
        changeStartedAt = .now
        prepareTranslator()
        layoutPanels()
        for panel in [bodyPanel, toolbarPanel, handlePanel] {
            panel.orderFrontRegardless()
        }
        if model.isTranscriptVisible {
            transcriptPanel.orderFrontRegardless()
        }
        // 렌즈 본체는 마우스를 통과시키므로 스크롤은 아래 앱으로 간다. 전역 모니터로 보고 지난 번역을 바로 숨긴다.
        // 마우스 이벤트 모니터는 손쉬운 사용 권한이 필요 없다 (키 이벤트만 필요)
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            MainActor.assumeIsolated { self?.didScroll() }
        }
        // 링크를 누르거나 다른 앱으로 바꾸면 영상 위에서처럼 번역을 계속 보여주지 않고 평소대로 숨긴다
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.didAct() }
        }
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didAct() }
        }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                let delay = self?.nextCaptureDelay() ?? CaptureSchedule.idleInterval
                try? await Task.sleep(for: delay)
            }
        }
    }

    func close() {
        loopTask?.cancel()
        translateTask?.cancel()
        translatorTask?.cancel()
        saveMemory()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
        }
        appSwitchObserver = nil
        for panel in [bodyPanel, toolbarPanel, handlePanel, transcriptPanel] {
            panel.orderOut(nil)
        }
        onClose?()
    }

    // MARK: 감시와 인식

    private func tick() async {
        // 렌즈는 띄운 데스크톱에만 있다. 다른 데스크톱을 보는 동안에는 그 화면을 캡처하지 않는다
        guard interaction == nil, !model.isPaused, bodyPanel.isOnActiveSpace, let selection = currentSelection() else {
            return
        }
        let started = ContinuousClock.now
        do {
            let image = try await capturer.capture(selection)
            let captured = ContinuousClock.now
            guard interaction == nil, !model.isPaused, bodyPanel.isOnActiveSpace,
                let fingerprint = ImageFingerprint(image)
            else {
                return
            }
            let change = tracker.observe(fingerprint, at: captured, lastUserAction: lastUserAction)
            isScreenChanging = change == .movedAway || tracker.isKeepingUp
            switch change {
            case .unchanged:
                // 스크롤했지만 화면이 그대로인 경우(페이지 끝 등). 스크롤이 멈추면 다시 보여준다
                if !scrolled(since: .now - Self.scrollQuietPeriod) {
                    model.isOutdated = false
                }
                return
            case .movedAway:
                markChange()
                model.isOutdated = true
                return
            case .settled, .keepsChanging:
                break
            }
            // 계속 바뀌는 화면(영상)은 0.4초마다 다시 인식하므로 진행 표시를 깜빡이지 않는다
            if translateTask == nil, change == .settled || !model.hasRecognized {
                model.status = .recognizing
            }
            // 엔진 준비를 기다리지 않고 바로 인식한다 (준비는 `prepareTranslator`가 따로 한다)
            let settled = ContinuousClock.now
            let recognized = TextBlockGrouper.group(try await recognizer.recognize(image))
            let ocred = ContinuousClock.now
            let sampled = await Task.detached {
                recognized.map { BlockColors.sample(image, in: $0.boundingBox) ?? .plain }
            }
            .value
            let colored = ContinuousClock.now
            // 인식하는 사이에 옮겼거나 일시정지했다면 버리고 다음 화면을 기다린다
            guard interaction == nil, !model.isPaused else { return }
            blocks = recognized
            colors = sampled
            if tracker.isKeepingUp {
                settling.observe(recognized.map(\.text), at: .now)
                captions = captionDetector.detect(recognized)
            } else {
                settling.reset()
                captionDetector.reset()
                captions = []
            }
            if model.isWatchingVideo != tracker.isKeepingUp {
                model.isWatchingVideo = tracker.isKeepingUp
            }
            scale = selection.scale
            imageHeight = CGFloat(image.height)
            model.hasRecognized = true
            refreshParagraphs()
            abandonTranslationIfPassed()
            let missing = memory.missing(in: blocks, for: model.language).count
            let timings = (
                capture: Self.ms(captured - started), ocr: Self.ms(ocred - settled),
                colors: Self.ms(colored - ocred), layout: Self.ms(.now - colored), sinceChange: sinceChange(),
                sinceScroll: lastScroll.map { Self.ms(.now - $0) } ?? -1
            )
            let trigger = change == .keepsChanging ? "계속 바뀜" : "멈춤"
            Self.log.info(
                """
                인식(\(trigger, privacy: .public)): 캡처 \(timings.capture, privacy: .public)ms · \
                OCR \(timings.ocr, privacy: .public)ms · 색 \(timings.colors, privacy: .public)ms · \
                배치 \(timings.layout, privacy: .public)ms · 문단 \(recognized.count, privacy: .public)개 \
                (번역 필요 \(missing, privacy: .public)개) · 변화 후 \(timings.sinceChange, privacy: .public)ms · \
                마지막 스크롤 후 \(timings.sinceScroll, privacy: .public)ms
                """)
            // 인식하는 사이에 또 스크롤했다면 숨긴 채로 다음 화면을 기다린다
            if !scrolled(since: started) {
                model.isOutdated = false
            }
            // 엔진 준비가 실패했으면 화면이 바뀔 때마다 다시 준비한다
            prepareTranslator()
            translateIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            model.status = .failed(Self.message(for: error))
        }
    }

    private func didScroll() {
        guard bodyPanel.isOnActiveSpace, frame.contains(NSEvent.mouseLocation) else { return }
        markChange()
        lastScroll = .now
        lastUserAction = .now
        model.isOutdated = true
    }

    private func didAct() {
        guard bodyPanel.isOnActiveSpace else { return }
        lastUserAction = .now
    }

    private func nextCaptureDelay() -> Duration {
        CaptureSchedule.delay(isChanging: isScreenChanging, lastScroll: lastScroll, now: .now)
    }

    private func markChange() {
        if changeStartedAt == nil {
            changeStartedAt = .now
        }
    }

    /// 화면이 바뀌기 시작한 뒤 지난 시간(ms). 바뀐 적이 없으면 -1
    private func sinceChange() -> Int {
        changeStartedAt.map { Self.ms(.now - $0) } ?? -1
    }

    private static func ms(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func scrolled(since instant: ContinuousClock.Instant) -> Bool {
        lastScroll.map { $0 > instant } ?? false
    }

    private func currentSelection() -> ScreenSelection? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard
            let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
            let clamped = ScreenGeometry.clamp(frame, to: screen.frame),
            let displayID = screen.displayID
        else { return nil }
        return ScreenSelection(
            displayID: displayID, rect: ScreenGeometry.displayLocalRect(clamped, screenFrame: screen.frame),
            scale: screen.backingScaleFactor, globalRect: clamped)
    }

    /// 번역 엔진을 준비한다. 준비되면 기다리던 문단을 번역한다. 이미 있거나 준비 중이면 아무것도 하지 않는다
    private func prepareTranslator() {
        guard translator == nil, translatorTask == nil else { return }
        let generation = engineGeneration
        let started = ContinuousClock.now
        translatorTask = Task { [weak self] in
            guard let self else { return }
            do {
                let provider = try await makeProvider()
                guard engineGeneration == generation else { return }
                translator = RegionTranslator(recognizer: recognizer, provider: provider)
                translatorTask = nil
                let engine = String(describing: type(of: provider))
                Self.log.info("엔진 준비: \(engine, privacy: .public) \(Self.ms(.now - started), privacy: .public)ms")
                translateIfNeeded()
            } catch {
                guard engineGeneration == generation else { return }
                translatorTask = nil
                model.status = .failed(Self.message(for: error))
            }
        }
    }

    /// 엔진이 바뀌면 진행 중 요청을 멈추고, 지금 기억을 저장한 뒤 새 엔진의 기억으로 바꿔 지금 보이는 문단을 다시 번역한다
    func changeEngine(to engine: TranslationEngine) {
        cancelTranslation()
        translatorTask?.cancel()
        translatorTask = nil
        engineGeneration += 1
        translator = nil
        saveMemory()
        memoryEngine = engine
        memory = memoryStore.load(engine)
        refreshParagraphs()
        if !blocks.isEmpty {
            model.status = .translating
        }
        prepareTranslator()
    }

    // MARK: 번역

    /// 기억에 없는 문단을 번역한다. 요청은 동시에 하나만 보내고, 끝나면 그사이 새로 생긴 문단을 이어서 보낸다.
    /// 엔진이 원하면(로컬 엔진은 1개) 나눠 보내 번역되는 대로 보여준다. 실패하면 다음 화면 변화나 언어 변경 때 다시 시도한다.
    private func translateIfNeeded() {
        guard translateTask == nil, !model.isPaused, let translator else { return }
        let language = model.language
        let height = imageHeight
        let missing = TranslationScheduling.prioritized(memory.missing(in: blocks, for: language)) {
            LensGeometry.isCutOff($0, imageHeight: height)
        }
        // 자막처럼 글이 바뀌는 화면에서는 글이 다 나온 뒤 번역한다. 기다리는 동안은 같은 자리의 지난 번역을 이어 보여주고,
        // 다음 인식 때 다시 고른다
        let ready =
            tracker.isKeepingUp
            ? settling.ready(missing, text: \.text, isCovered: { carriedTexts.contains($0.text) }, at: .now) : missing
        guard !missing.isEmpty else {
            model.status = .watching
            if changeStartedAt != nil, !model.isOutdated {
                Self.log.info("모두 표시: 변화 후 \(self.sinceChange(), privacy: .public)ms")
                changeStartedAt = nil
            }
            return
        }
        guard !ready.isEmpty else { return }
        let hasVisibleTranslation = blocks.contains { memory.translation(of: $0.text, in: language) != nil }
        let batch = TranslationScheduling.batch(
            ready, hasVisibleTranslation: hasVisibleTranslation,
            preferredBatchSize: translator.provider.preferredBatchSize,
            firstBatchSize: translator.provider.firstBatchSize)
        model.status = .translating
        let requested = ContinuousClock.now
        translateGeneration += 1
        let generation = translateGeneration
        inFlightTexts = batch.map(\.text)
        let showPartial: @MainActor (String, String) -> Void = { [weak self] text, partial in
            self?.showPartial(partial, for: text, language: language, generation: generation)
        }
        translateTask = Task { [weak self] in
            do {
                let translated = try await translator.translate(batch, to: language) { block, partial in
                    Task { @MainActor in showPartial(block.text, partial) }
                }
                let engine = String(describing: type(of: translator.provider))
                let elapsed = Self.ms(.now - requested)
                Self.log.info(
                    "번역: \(engine, privacy: .public) 문단 \(batch.count, privacy: .public)개 \(elapsed, privacy: .public)ms"
                )
                guard let self else { return }
                // 버린 요청이라도 번역은 기억해 둔다 (다시 스크롤해 올라오면 바로 보인다)
                for block in translated {
                    self.memory.store(block.translation, of: block.source.text, in: language)
                    self.partials[block.source.text] = nil
                }
                guard self.translateGeneration == generation else { return }
                self.translateTask = nil
                self.refreshParagraphs()
                self.translateIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.translateGeneration == generation else { return }
                self.translateTask = nil
                self.model.status = .failed(Self.message(for: error))
            }
        }
    }

    /// 진행 중인 요청의 문단이 대부분 화면에서 지나갔으면 요청을 버리고 지금 화면부터 번역하게 한다.
    /// 계속 바뀌는 화면(자막)에서는 버리지 않는다: 글이 번역보다 빨리 바뀌면 번역이 하나도 끝나지 않는다
    private func abandonTranslationIfPassed() {
        guard translateTask != nil, !tracker.isKeepingUp,
            TranslationScheduling.shouldAbandon(inFlight: inFlightTexts, visible: Set(blocks.map(\.text)))
        else { return }
        Self.log.info("지나간 화면 번역 취소: 문단 \(self.inFlightTexts.count, privacy: .public)개")
        cancelTranslation()
    }

    /// 생성 중인 번역을 그린다. 이미 끝났거나 버린 요청·바뀐 언어의 중간 글은 무시한다
    private func showPartial(_ partial: String, for text: String, language: TargetLanguage, generation: Int) {
        guard translateGeneration == generation, model.language == language,
            memory.translation(of: text, in: language) == nil
        else { return }
        partials[text] = partial
        let now = ContinuousClock.now
        if let lastPartialRefresh, now - lastPartialRefresh < Self.partialRefreshInterval {
            return
        }
        lastPartialRefresh = now
        refreshParagraphs()
    }

    func saveMemory() {
        do {
            try memoryStore.save(memory, for: memoryEngine)
        } catch {
            Self.log.error("번역 기억 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearMemory() {
        cancelTranslation()
        memory = TranslationMemory()
        refreshParagraphs()
        translateIfNeeded()
    }

    private func cancelTranslation() {
        translateTask?.cancel()
        translateTask = nil
        translateGeneration += 1
        inFlightTexts = []
        partials = [:]
        // 언어·엔진이 바뀌었거나 기억을 지웠으면 지난 번역을 잇지 않는다
        carryOver.reset()
    }

    private func changeLanguage(to language: TargetLanguage) {
        onLanguageChange?(language)
        cancelTranslation()
        refreshParagraphs()
        translateIfNeeded()
    }

    private func refreshParagraphs() {
        let frames = LensGeometry.paragraphFrames(of: blocks, scale: scale, lensSize: frame.size, captions: captions)
        var contents = blocks.map { memory.content(of: $0, in: model.language) }
        recordTranscript(contents)
        // 계속 바뀌는 화면에서만 잇는다. 스크롤한 페이지에서 이으면 다른 문단의 번역이 보인다.
        // 이을 번역이 있으면 생성 중 번역보다 먼저 보여준다 (자막 글이 바뀔 때마다 번역이 처음부터 다시 써지지 않게)
        if tracker.isKeepingUp {
            let carried = carryOver.apply(to: contents, boxes: blocks.map(\.boundingBox), at: .now)
            carriedTexts = Set(
                zip(blocks, zip(contents, carried)).compactMap { block, pair in
                    pair.0 == .pending && pair.1 != .pending ? block.text : nil
                })
            contents = carried
        } else {
            carryOver.reset()
            carriedTexts = []
        }
        model.paragraphs = zip(blocks, frames).enumerated().map { index, pair in
            let (block, paragraphFrame) = pair
            var content = contents[index]
            if case .pending = content, let partial = partials[block.text], !partial.isEmpty {
                content = .translated(partial)
            }
            // 자막은 기억한 줄 높이로 글자 크기를 정한다 (인식마다 줄 높이가 달라 글자 크기가 흔들렸다)
            let caption = captions.indices.contains(index) ? captions[index] : nil
            return LensModel.Paragraph(
                id: index, content: content, frame: paragraphFrame,
                fontSize: caption.map { LensGeometry.fontSize(lineHeight: $0.lineHeight, scale: scale) }
                    ?? LensGeometry.fontSize(of: block, scale: scale),
                colors: colors.indices.contains(index) ? colors[index] : .plain)
        }
    }

    /// 원문과 맞는 번역(이어 보여주기·생성 중 글 제외)을 번역 기록에 더한다. 바뀌었을 때만 화면에 알린다
    private func recordTranscript(_ contents: [BlockContent]) {
        var changed = false
        for (block, content) in zip(blocks, contents) {
            if case .translated(let translation) = content,
                transcript.record(source: block.text, translation: translation, in: model.language)
            {
                changed = true
            }
        }
        if changed {
            model.transcript = transcript
        }
    }

    // MARK: 이동과 크기 조절

    /// 끄는 동안 렌즈를 바꾸고, 놓으면 처음부터 다시 본다. 끄는 동안에는 캡처하지 않는다.
    private func interact(_ phase: LensModel.DragPhase, transform: (CGRect, CGSize) -> CGRect) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            let start = interaction ?? (mouse, frame)
            interaction = start
            // 지난 번역이 다른 내용 위로 같이 움직이므로 숨긴다
            model.isOutdated = true
            frame = transform(start.frame, CGSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y))
            layoutPanels()
            refreshParagraphs()
        case .ended:
            interaction = nil
            tracker.reset()
            model.status = .recognizing
        }
    }

    private func layoutPanels() {
        let visibleFrame =
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.visibleFrame ?? frame
        bodyPanel.setFrame(frame, display: true)
        toolbarPanel.setFrame(
            LensGeometry.toolbarFrame(height: Self.toolbarHeight, for: frame, in: visibleFrame), display: true)
        handlePanel.setFrame(
            CGRect(
                x: frame.maxX - Self.handleSize - 2, y: frame.minY + 2, width: Self.handleSize, height: Self.handleSize),
            display: true)
        transcriptPanel.setFrame(transcriptFrame(in: visibleFrame), display: true)
    }

    /// 사용자가 옮겼으면 렌즈 기준 그 자리, 아니면 렌즈 옆 기본 자리
    private func transcriptFrame(in visibleFrame: CGRect) -> CGRect {
        guard let transcriptOffset else {
            return LensGeometry.transcriptFrame(for: frame, in: visibleFrame, size: transcriptSize)
        }
        let size = transcriptSize ?? transcriptPanel.frame.size
        return CGRect(
            x: frame.minX + transcriptOffset.x, y: frame.minY + transcriptOffset.y, width: size.width,
            height: size.height)
    }

    /// 번역 기록 패널 옮기기·크기 바꾸기. 끝나면 렌즈 기준 자리를 기억해 렌즈를 옮겨도 같은 간격으로 따라가게 하고,
    /// 크기를 바꿨으면 그 크기를 기억한다 (옮기기만 했으면 기본 크기를 그대로 둔다)
    private func dragTranscript(
        _ phase: LensModel.DragPhase, resizing: Bool, transform: (CGRect, CGSize) -> CGRect
    ) {
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            let start = transcriptDrag ?? (mouse, transcriptPanel.frame)
            transcriptDrag = start
            let moved = transform(start.frame, CGSize(width: mouse.x - start.mouse.x, height: mouse.y - start.mouse.y))
            transcriptPanel.setFrame(moved, display: true)
        case .ended:
            guard transcriptDrag != nil else { return }
            transcriptDrag = nil
            let panel = transcriptPanel.frame
            transcriptOffset = CGPoint(x: panel.minX - frame.minX, y: panel.minY - frame.minY)
            if resizing {
                transcriptSize = panel.size
                onTranscriptSizeChange?(panel.size)
            }
        }
    }

    /// 일시정지하면 진행 중 요청을 멈추고 번역을 숨긴다. 다시 시작하면 지금 화면부터 다시 인식한다 (기억한 번역은 바로 보인다)
    private func pauseDidChange(_ paused: Bool) {
        if paused {
            cancelTranslation()
            model.isOutdated = true
            model.status = .watching
        } else {
            tracker.reset()
            changeStartedAt = .now
            model.status = .recognizing
        }
    }

    private func showTranscript(_ visible: Bool) {
        if visible {
            transcriptPanel.orderFrontRegardless()
        } else {
            transcriptPanel.orderOut(nil)
        }
        onTranscriptVisibilityChange?(visible)
    }

    private static func hosting(_ view: some View) -> NSView {
        let hosting = FirstMouseHostingView(rootView: view)
        // 창 크기는 렌즈가 정한다. 내용이 창 크기를 바꾸지 않게 한다
        hosting.sizingOptions = []
        return hosting
    }

    private static func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
