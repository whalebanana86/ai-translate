import AppKit
import SwiftUI
import TranslateCore

/// 번역 엔진 선택 화면. 처음 실행 때(`isOnboarding`)와 설정 창이 같이 쓴다.
struct SettingsView: View {
    @Bindable var settings: EngineSettings
    var isOnboarding: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isOnboarding {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Translate를 시작합니다").font(.title2.bold())
                    Text("번역에 쓸 엔진을 고르세요. 나중에 설정(⌘,)에서 바꿀 수 있습니다.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("번역 엔진").font(.headline)
            }
            ForEach(TranslationEngine.allCases) { engine in
                EngineCard(settings: settings, engine: engine)
            }
            if !isOnboarding {
                MemorySection(settings: settings)
            }
            HStack {
                Text("⌘⇧1을 누르고 영역을 드래그하면 번역 렌즈가 생깁니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if isOnboarding {
                    Button("시작하기", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .disabled(settings.engine == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .task { settings.refreshCLIStatus() }
    }
}

/// 엔진 하나. 눌러서 고르고, 엔진별 상태(CLI 설치 여부, 로컬 모델)를 보여준다.
private struct EngineCard: View {
    let settings: EngineSettings
    let engine: TranslationEngine

    private var isSelected: Bool { settings.engine == engine }
    private var isSupported: Bool { engine.isSupported(onAppleSilicon: EngineSettings.isAppleSilicon) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text(engine.displayName).font(.headline)
                Text(engine.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isSupported {
                    Label("Apple Silicon(M1 이상) Mac에서만 쓸 수 있습니다.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if engine == .local {
                    LocalModelStatus(settings: settings)
                } else {
                    CLIStatusLine(status: settings.cliStatus[engine], name: engine.executableName ?? "")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .opacity(isSupported ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSupported {
                settings.engine = engine
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct CLIStatusLine: View {
    let status: EngineSettings.CLIStatus?
    let name: String

    var body: some View {
        switch status {
        case .found(let path):
            Label("설치됨 · \(path)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .missing:
            Label("\(name) CLI를 찾을 수 없습니다. 설치하고 터미널에서 로그인하세요.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .checking, nil:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("설치 확인 중…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 로컬 모델 받기·지우기. 받기는 사용자가 버튼을 눌러야 시작한다
private struct LocalModelStatus: View {
    let settings: EngineSettings

    private var size: String {
        ByteCountFormatter.string(fromByteCount: settings.localModel.totalSize, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch settings.modelState {
            case .notInstalled:
                HStack {
                    Button("모델 받기 (\(size))") { settings.downloadModel() }
                    Text("Hy-MT2 1.8B · Apache-2.0 · Hugging Face").font(.caption).foregroundStyle(.secondary)
                }
            case .downloading(let fraction):
                HStack {
                    ProgressView(value: fraction).frame(width: 220)
                    Text("\(Int(fraction * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("취소") { settings.cancelDownload() }
                }
            case .installed:
                HStack {
                    Label("설치됨 · \(size)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Button("지우기", role: .destructive) { settings.deleteModel() }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 받기") { settings.downloadModel() }
            }
        }
        .controlSize(.small)
    }
}

/// 번역 기억: 같은 글은 다시 번역하지 않도록 이 Mac에 저장한다. 원문이 남으므로 지울 수 있게 한다
private struct MemorySection: View {
    let settings: EngineSettings
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("번역 기억").font(.headline)
            Text("번역한 글(원문과 번역)을 이 Mac에만 저장해, 같은 글을 다시 볼 때 바로 보여줍니다. 엔진마다 최근 500개까지.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("번역 기억 지우기") {
                    settings.clearTranslationMemory()
                    cleared = true
                }
                if cleared {
                    Label("지웠습니다", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .controlSize(.small)
        }
    }
}
