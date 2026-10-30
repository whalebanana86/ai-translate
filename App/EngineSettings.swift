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
            prepare()
        }
    }
    private(set) var cliStatus: [TranslationEngine: CLIStatus] = [:]
    private(set) var modelState: ModelState

    @ObservationIgnored var onEngineChange: (() -> Void)?
    @ObservationIgnored var onMemoryClear: (() -> Void)?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    /// 엔진을 찾거나 모델을 불러오는 데 시간이 걸리므로 렌즈를 새로 만들어도 다시 쓴다
    @ObservationIgnored private var cachedProvider: (engine: TranslationEngine, provider: any TranslationProvider)?
    @ObservationIgnored private var preparing:
        (engine: TranslationEngine, task: Task<any TranslationProvider, any Error>)?

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
                cachedProvider = nil
                if engine == .local {
                    prepare()
                }
            } catch is CancellationError {
                modelState = .notInstalled
            } catch {
                modelState = .failed(
                    message: (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            downloadTask = nil
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

    // MARK: 번역 기억

    /// 디스크의 번역 기억(모든 엔진)과 열린 렌즈의 기억을 지운다
    func clearTranslationMemory() {
        try? TranslationMemoryStore.standard.removeAll()
        onMemoryClear?()
    }

    // MARK: 렌즈가 쓰는 번역 엔진

    /// 선택된 엔진을 미리 만들어 둔다 (로컬 모델 불러오기·예열 1~6초, CLI 찾기). 실패는 렌즈가 쓸 때 다시 보인다
    func prepare() {
        guard engine != nil else { return }
        Task { _ = try? await makeProvider() }
    }

    func makeProvider() async throws -> any TranslationProvider {
        let engine = engine ?? .claudeCode
        if let cachedProvider, cachedProvider.engine == engine {
            return cachedProvider.provider
        }
        // 미리 준비하는 중이면 같은 준비를 기다린다 (모델을 두 번 불러오지 않게)
        if let preparing, preparing.engine == engine {
            return try await preparing.task.value
        }
        let task = Task { try await Self.provider(for: engine, model: localModel, store: store) }
        preparing = (engine, task)
        defer {
            if preparing?.engine == engine {
                preparing = nil
            }
        }
        let provider = try await task.value
        // 준비하는 사이에 엔진이 바뀌었으면 기억하지 않는다
        if engine == (self.engine ?? .claudeCode) {
            cachedProvider = (engine, provider)
        }
        return provider
    }

    private static func provider(for engine: TranslationEngine, model: LocalModel, store: ModelStore) async throws
        -> any TranslationProvider
    {
        switch engine {
        case .claudeCode:
            return try await ClaudeCodeProvider.locate()
        case .codex:
            return try await CodexProvider.locate()
        case .local:
            guard store.isInstalled(model) else { throw LocalEngineError.modelNotInstalled }
            return LocalTranslationProvider(
                generator: try await LocalTextGenerator.load(directory: store.directory(for: model)))
        }
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
