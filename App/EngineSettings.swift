import Foundation
import Observation
import Synchronization
import TranslateCore

/// 번역 엔진 선택과 엔진별 상태. 설정 창과 렌즈가 함께 쓴다.
@MainActor
@Observable
final class EngineSettings {
    enum CLIStatus: Equatable {
        case checking
        case found(path: String)
        case missing
    }

    enum ModelState: Equatable {
        case notInstalled
        case downloading(fraction: Double)
        case installed
        case failed(message: String)
    }

    private static let engineKey = "TranslationEngine"

    let localModel = LocalModel.hyMT2
    private let store = ModelStore.standard

    /// nil이면 아직 고르지 않음 (처음 실행)
    var engine: TranslationEngine? {
        didSet {
            guard engine != oldValue else { return }
            UserDefaults.standard.set(engine?.rawValue, forKey: Self.engineKey)
            cachedProvider = nil
            onEngineChange?()
        }
    }
    private(set) var cliStatus: [TranslationEngine: CLIStatus] = [:]
    private(set) var modelState: ModelState

    @ObservationIgnored var onEngineChange: (() -> Void)?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    /// 엔진을 찾거나 모델을 불러오는 데 시간이 걸리므로 렌즈를 새로 만들어도 다시 쓴다
    @ObservationIgnored private var cachedProvider: (engine: TranslationEngine, provider: any TranslationProvider)?

    init() {
        engine = UserDefaults.standard.string(forKey: Self.engineKey).flatMap(TranslationEngine.init(rawValue:))
        modelState = ModelStore.standard.isInstalled(LocalModel.hyMT2) ? .installed : .notInstalled
    }

    // MARK: CLI 엔진

    func refreshCLIStatus() {
        for engine in TranslationEngine.allCases {
            guard let name = engine.executableName else { continue }
            cliStatus[engine] = .checking
            Task {
                let url = await CLILocator.locate(name, knownLocations: engine.knownLocations)
                cliStatus[engine] = url.map { .found(path: $0.path) } ?? .missing
            }
        }
    }

    // MARK: 로컬 모델 (사용자가 버튼으로 받는다)

    func downloadModel() {
        guard downloadTask == nil else { return }
        modelState = .downloading(fraction: 0)
        let downloader = ModelDownloader(store: store)
        let model = localModel
        let reporter = ProgressReporter { [weak self] fraction in
            guard let self, case .downloading = modelState else { return }
            modelState = .downloading(fraction: fraction)
        }
        downloadTask = Task {
            do {
                try await downloader.download(model) { reporter.report($0.fraction) }
                modelState = .installed
            } catch is CancellationError {
                modelState = .notInstalled
            } catch {
                modelState = .failed(
                    message: (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            downloadTask = nil
            cachedProvider = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteModel() {
        cancelDownload()
        try? store.remove(localModel)
        modelState = .notInstalled
        cachedProvider = nil
    }

    // MARK: 렌즈가 쓰는 번역 엔진

    func makeProvider() async throws -> any TranslationProvider {
        let engine = engine ?? .claudeCode
        if let cachedProvider, cachedProvider.engine == engine {
            return cachedProvider.provider
        }
        let provider: any TranslationProvider
        switch engine {
        case .claudeCode:
            provider = try await ClaudeCodeProvider.locate()
        case .codex:
            provider = try await CodexProvider.locate()
        case .local:
            guard store.isInstalled(localModel) else { throw LocalEngineError.modelNotInstalled }
            provider = LocalTranslationProvider(
                generator: try await LocalTextGenerator.load(directory: store.directory(for: localModel)))
        }
        // 찾는 사이에 엔진이 바뀌었으면 기억하지 않는다
        if engine == (self.engine ?? .claudeCode) {
            cachedProvider = (engine, provider)
        }
        return provider
    }
}

/// 받기 진행률을 0.5%마다만 메인 액터로 넘긴다 (세션 대리자는 다른 스레드에서 수십 KB마다 부른다)
private final class ProgressReporter: Sendable {
    private let last = Mutex(-1.0)
    private let update: @MainActor (Double) -> Void

    init(update: @escaping @MainActor (Double) -> Void) {
        self.update = update
    }

    func report(_ fraction: Double) {
        let shouldReport = last.withLock { last in
            guard fraction >= 1 || fraction - last >= 0.005 else { return false }
            last = fraction
            return true
        }
        guard shouldReport else { return }
        Task { @MainActor [update] in update(fraction) }
    }
}
