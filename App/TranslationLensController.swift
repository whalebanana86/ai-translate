import AppKit
import OSLog
import SwiftUI
import TranslateCore

/// ⌘⇧1 → 권한·고지 → 영역 드래그 → 그 영역에 번역 렌즈를 띄운다. 렌즈는 한 번에 하나이며 새로 만들면 바꾼다.
@MainActor
final class TranslationLensController {
    private static let languageKey = "TargetLanguage"

    private let settings: EngineSettings
    private let overlay = SelectionOverlayController()
    private let capturer = ScreenCapturer()
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
        let session = LensSession(frame: selection.globalRect, language: language, capturer: capturer) {
            [settings] in try await settings.makeProvider()
        }
        session.onLanguageChange = { [weak self] language in self?.language = language }
        session.onClose = { [weak self, weak session] in
            if self?.lens === session {
                self?.lens = nil
            }
        }
        lens = session
        session.show()
    }

    /// 설정에서 엔진을 바꾸면 열린 렌즈가 새 엔진으로 다시 번역한다. 외부로 보내는 엔진이면 먼저 고지한다
    func engineDidChange() {
        guard let lens, let engine = settings.engine else { return }
        guard DataTransmissionNotice.confirm(for: engine) else {
            lens.close()
            return
        }
        lens.changeEngine()
    }
}

/// 떠 있는 렌즈 하나. 렌즈 아래 화면을 계속 보고, 바뀌면 다시 인식해 새 문단만 번역한다.
@MainActor
final class LensSession {
    private static let toolbarHeight: CGFloat = 34
    private static let handleSize: CGFloat = 18
    private static let captureInterval: Duration = .milliseconds(500)
    /// 마지막 스크롤 뒤 이만큼 지나야 스크롤이 멈춘 것으로 본다
    private static let scrollQuietPeriod: Duration = .milliseconds(500)
    private static let aboveLens = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    var onLanguageChange: ((TargetLanguage) -> Void)?
    var onClose: (() -> Void)?

    private let model: LensModel
    private let capturer: ScreenCapturer
    /// 렌즈 영역. 전역 AppKit 좌표
    private var frame: CGRect
    private let bodyPanel: LensPanel
    private let toolbarPanel: LensPanel
    private let handlePanel: LensPanel

    /// 선택된 번역 엔진을 만든다 (설정이 엔진별로 기억해 둔다)
    private let makeProvider: @MainActor () async throws -> any TranslationProvider
    private var tracker = ChangeTracker()
    private var memory = TranslationMemory()
    private var translator: RegionTranslator?
    private var blocks: [TextBlock] = []
    /// `blocks`와 같은 순서의 원문 색
    private var colors: [BlockColors] = []
    private var scale: CGFloat = 2
    private var loopTask: Task<Void, Never>?
    private var translateTask: Task<Void, Never>?
    /// 이동·크기 조절 중이면 시작 시점의 마우스 위치와 렌즈 영역
    private var interaction: (mouse: CGPoint, frame: CGRect)?
    private var scrollMonitor: Any?
    /// 렌즈 위에서 마지막으로 스크롤한 때
    private var lastScroll: ContinuousClock.Instant?
    /// 화면이 바뀌기 시작한 때(렌즈 생성·스크롤·큰 변화). 번역이 다 보일 때까지의 체감 시간을 잰다
    private var changeStartedAt: ContinuousClock.Instant?

    /// 단계별 시간 기록. 숫자와 엔진 이름만 남기고 글 내용은 남기지 않는다 (AGENTS.md 개인정보).
    /// info 단계라 디스크에 저장되지 않고 `log stream`으로 볼 때만 보인다
    private static let log = Logger(subsystem: "com.example.AITranslate", category: "pipeline")

    init(
        frame: CGRect, language: TargetLanguage, capturer: ScreenCapturer,
        makeProvider: @escaping @MainActor () async throws -> any TranslationProvider
    ) {
        self.frame = frame
        self.capturer = capturer
        self.makeProvider = makeProvider
        let model = LensModel(language: language)
        self.model = model
        bodyPanel = LensPanel(
            content: Self.hosting(LensBodyView(model: model)), level: .floating, passesMouseThrough: true)
        // 본체는 번역 문단 밖이 투명하다. 그림자를 두면 문단마다 그림자가 생긴다
        bodyPanel.hasShadow = false
        toolbarPanel = LensPanel(
            content: Self.hosting(LensToolbarView(model: model)), level: Self.aboveLens, passesMouseThrough: false)
        handlePanel = LensPanel(
            content: Self.hosting(LensResizeHandleView(model: model)), level: Self.aboveLens, passesMouseThrough: false)

        model.onLanguageChange = { [weak self] language in self?.changeLanguage(to: language) }
        model.onPeekChange = { [weak self] peeking in self?.bodyPanel.alphaValue = peeking ? 0 : 1 }
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
        layoutPanels()
        for panel in [bodyPanel, toolbarPanel, handlePanel] {
            panel.orderFrontRegardless()
        }
        // 렌즈 본체는 마우스를 통과시키므로 스크롤은 아래 앱으로 간다. 전역 모니터로 보고 지난 번역을 바로 숨긴다.
        // 마우스 이벤트 모니터는 손쉬운 사용 권한이 필요 없다 (키 이벤트만 필요)
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            MainActor.assumeIsolated { self?.didScroll() }
        }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.captureInterval)
            }
        }
    }

    func close() {
        loopTask?.cancel()
        translateTask?.cancel()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
        for panel in [bodyPanel, toolbarPanel, handlePanel] {
            panel.orderOut(nil)
        }
        onClose?()
    }

    // MARK: 감시와 인식

    private func tick() async {
        guard interaction == nil, let selection = currentSelection() else { return }
        let started = ContinuousClock.now
        do {
            let image = try await capturer.capture(selection)
            let captured = ContinuousClock.now
            guard interaction == nil, let fingerprint = ImageFingerprint(image) else { return }
            switch tracker.observe(fingerprint) {
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
            case .settled:
                break
            }
            if translateTask == nil {
                model.status = .recognizing
            }
            let settled = ContinuousClock.now
            let translator = try await locateTranslator()
            let prepared = ContinuousClock.now
            let recognized = try await translator.recognize(image)
            let ocred = ContinuousClock.now
            let sampled = await Task.detached {
                recognized.map { BlockColors.sample(image, in: $0.boundingBox) ?? .plain }
            }
            .value
            let colored = ContinuousClock.now
            // 인식하는 사이에 옮겼다면 버리고 다음 화면을 기다린다
            guard interaction == nil else { return }
            blocks = recognized
            colors = sampled
            scale = selection.scale
            model.hasRecognized = true
            refreshParagraphs()
            let missing = memory.missing(in: blocks, for: model.language).count
            let timings = (
                capture: Self.ms(captured - started), prepare: Self.ms(prepared - settled),
                ocr: Self.ms(ocred - prepared),
                colors: Self.ms(colored - ocred), layout: Self.ms(.now - colored), sinceChange: sinceChange()
            )
            Self.log.info(
                """
                인식: 캡처 \(timings.capture, privacy: .public)ms · 엔진 준비 \(timings.prepare, privacy: .public)ms · \
                OCR \(timings.ocr, privacy: .public)ms · 색 \(timings.colors, privacy: .public)ms · \
                배치 \(timings.layout, privacy: .public)ms · 문단 \(recognized.count, privacy: .public)개 \
                (번역 필요 \(missing, privacy: .public)개) · 변화 후 \(timings.sinceChange, privacy: .public)ms
                """)
            // 인식하는 사이에 또 스크롤했다면 숨긴 채로 다음 화면을 기다린다
            if !scrolled(since: started) {
                model.isOutdated = false
            }
            translateIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            model.status = .failed(Self.message(for: error))
        }
    }

    private func didScroll() {
        guard frame.contains(NSEvent.mouseLocation) else { return }
        markChange()
        lastScroll = .now
        model.isOutdated = true
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

    private func locateTranslator() async throws -> RegionTranslator {
        if let translator {
            return translator
        }
        let located = RegionTranslator(provider: try await makeProvider())
        translator = located
        return located
    }

    /// 엔진이 바뀌면 진행 중 요청을 멈추고, 기억한 번역을 비워 지금 보이는 문단을 새 엔진으로 다시 번역한다
    func changeEngine() {
        translateTask?.cancel()
        translateTask = nil
        translator = nil
        memory = TranslationMemory()
        refreshParagraphs()
        guard !blocks.isEmpty else { return }
        model.status = .translating
        Task { [weak self] in
            do {
                _ = try await self?.locateTranslator()
                self?.translateIfNeeded()
            } catch {
                self?.model.status = .failed(Self.message(for: error))
            }
        }
    }

    // MARK: 번역

    /// 기억에 없는 문단을 번역한다. 요청은 동시에 하나만 보내고, 끝나면 그사이 새로 생긴 문단을 이어서 보낸다.
    /// 엔진이 원하면(로컬 엔진은 1개) 나눠 보내 번역되는 대로 보여준다. 실패하면 다음 화면 변화나 언어 변경 때 다시 시도한다.
    private func translateIfNeeded() {
        guard translateTask == nil, let translator else { return }
        let language = model.language
        let missing = memory.missing(in: blocks, for: language)
        guard !missing.isEmpty else {
            model.status = .watching
            if changeStartedAt != nil, !model.isOutdated {
                Self.log.info("모두 표시: 변화 후 \(self.sinceChange(), privacy: .public)ms")
                changeStartedAt = nil
            }
            return
        }
        let batch = translator.provider.preferredBatchSize.map { Array(missing.prefix($0)) } ?? missing
        model.status = .translating
        let requested = ContinuousClock.now
        translateTask = Task { [weak self] in
            do {
                let translated = try await translator.translate(batch, to: language)
                let engine = String(describing: type(of: translator.provider))
                let elapsed = Self.ms(.now - requested)
                Self.log.info(
                    "번역: \(engine, privacy: .public) 문단 \(batch.count, privacy: .public)개 \(elapsed, privacy: .public)ms"
                )
                guard let self else { return }
                for block in translated {
                    self.memory.store(block.translation, of: block.source.text, in: language)
                }
                self.translateTask = nil
                self.refreshParagraphs()
                self.translateIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                self?.translateTask = nil
                self?.model.status = .failed(Self.message(for: error))
            }
        }
    }

    private func changeLanguage(to language: TargetLanguage) {
        onLanguageChange?(language)
        translateTask?.cancel()
        translateTask = nil
        refreshParagraphs()
        translateIfNeeded()
    }

    private func refreshParagraphs() {
        let frames = LensGeometry.paragraphFrames(of: blocks, scale: scale, lensSize: frame.size)
        model.paragraphs = zip(blocks, frames).enumerated().map { index, pair in
            let (block, paragraphFrame) = pair
            return LensModel.Paragraph(
                id: index, content: memory.content(of: block, in: model.language), frame: paragraphFrame,
                fontSize: LensGeometry.fontSize(of: block, scale: scale),
                colors: colors.indices.contains(index) ? colors[index] : .plain)
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
