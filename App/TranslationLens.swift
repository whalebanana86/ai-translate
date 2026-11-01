import AppKit
import SwiftUI
import TranslateCore

/// 번역 렌즈 화면 상태.
@MainActor
@Observable
final class LensModel {
    struct Paragraph: Identifiable, Equatable {
        var id: Int
        var content: BlockContent
        var frame: ParagraphFrame
        var fontSize: CGFloat
        /// 원문의 바탕색·글자색. 번역을 이 색으로 그린다
        var colors: BlockColors

        /// 원문 자리에 그릴 번역. 번역 전이거나 번역할 필요가 없는 문단은 그리지 않아 원문이 그대로 보인다
        var translation: String? {
            if case .translated(let text) = content { text } else { nil }
        }
    }

    enum Status: Equatable {
        case watching
        case recognizing
        case translating
        case failed(String)
    }

    enum DragPhase {
        case changed
        case ended
    }

    var paragraphs: [Paragraph] = []
    var status: Status = .recognizing
    /// 한 번이라도 인식을 마쳤는지. 마쳤는데 문단이 없으면 "텍스트 없음"을 보여준다
    var hasRecognized = false
    /// 보여주던 번역이 지금 화면과 맞지 않음(스크롤·이동 중). 다시 인식할 때까지 번역을 그리지 않는다
    var isOutdated = false
    /// 렌즈 옆 패널에 보여줄 번역 기록
    var transcript = TranslationTranscript()
    private(set) var language: TargetLanguage
    private(set) var isPeeking = false
    private(set) var isTranscriptVisible: Bool
    /// 번역 일시정지. 캡처·인식·번역을 멈추고 번역을 그리지 않아 원문이 보인다
    private(set) var isPaused = false

    @ObservationIgnored var onLanguageChange: ((TargetLanguage) -> Void)?
    @ObservationIgnored var onPeekChange: ((Bool) -> Void)?
    @ObservationIgnored var onTranscriptVisibilityChange: ((Bool) -> Void)?
    @ObservationIgnored var onPauseChange: ((Bool) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onMove: ((DragPhase) -> Void)?
    @ObservationIgnored var onResize: ((DragPhase) -> Void)?

    init(language: TargetLanguage, showsTranscript: Bool) {
        self.language = language
        isTranscriptVisible = showsTranscript
    }

    func select(_ language: TargetLanguage) {
        guard language != self.language else { return }
        self.language = language
        onLanguageChange?(language)
    }

    func setPeeking(_ peeking: Bool) {
        isPeeking = peeking
        onPeekChange?(peeking)
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        onPauseChange?(paused)
    }

    func setTranscriptVisible(_ visible: Bool) {
        isTranscriptVisible = visible
        onTranscriptVisibilityChange?(visible)
    }

    /// 번역이 끝난 문단(번역할 필요 없는 문단은 원문)을 빈 줄로 이어 붙인 글
    var copyText: String {
        paragraphs.compactMap { paragraph in
            switch paragraph.content {
            case .translated(let text), .original(let text): text
            case .pending: nil
            }
        }
        .joined(separator: "\n\n")
    }
}

// MARK: - 렌즈 본체

/// 번역을 원문 문단 위치에, 원문의 바탕색과 글자색으로 그린다. 번역 문단 밖은 투명해 페이지가 그대로 보인다.
/// 창은 마우스를 통과시키므로 스크롤·클릭은 아래 페이지로 간다.
struct LensBodyView: View {
    /// 번역이 쓸 수 있는 자리(`ParagraphFrame.maxHeight`)를 넘칠 때 글자를 줄이는 한도
    static let minimumTextScale = 0.6
    /// OCR 영역보다 이만큼 넓게 가려 글자 가장자리(아래로 내려가는 글자 등)도 보이지 않게 한다
    private static let backingInset: CGFloat = 3

    let model: LensModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if !model.isOutdated {
                LensParagraphLayout {
                    ForEach(model.paragraphs.filter { $0.translation != nil }, content: translation)
                }
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
        }
        .overlay(alignment: .bottom) { errorBanner }
    }

    private func translation(_ paragraph: LensModel.Paragraph) -> some View {
        let source = paragraph.frame.sourceSize
        return Text(paragraph.translation ?? "")
            .font(.system(size: paragraph.fontSize))
            .foregroundStyle(Color(paragraph.colors.text))
            .minimumScaleFactor(Self.minimumTextScale)
            .background(alignment: .topLeading) {
                // 번역이 원문보다 짧아도 원문 문단 자리는 다 가린다
                Rectangle()
                    .fill(Color(paragraph.colors.background))
                    .frame(
                        minWidth: source.width + Self.backingInset * 2,
                        minHeight: source.height + Self.backingInset * 2,
                        alignment: .topLeading
                    )
                    .padding(-Self.backingInset)
            }
            .layoutValue(key: ParagraphFrameKey.self, value: paragraph.frame)
    }

    @ViewBuilder private var placeholder: some View {
        if model.paragraphs.isEmpty {
            Group {
                if model.hasRecognized {
                    Text("렌즈 안에서 텍스트를 찾지 못했습니다.")
                } else if case .failed = model.status {
                    EmptyView()
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("텍스트를 인식하는 중…")
                    }
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if case .failed(let message) = model.status {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(6)
        }
    }
}

private struct ParagraphFrameKey: LayoutValueKey {
    static let defaultValue = ParagraphFrame(origin: .zero, width: 0, maxHeight: 0, sourceSize: .zero)
}

/// 문단을 원문 위치에 두고, 쓸 수 있는 자리(너비·최대 높이) 안에서 글을 배치한다. 다른 문단을 밀지 않는다.
struct LensParagraphLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let frame = subview[ParagraphFrameKey.self]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y), anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.maxHeight))
        }
    }
}

extension Color {
    init(_ color: SRGBColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}

// MARK: - 도구 막대와 크기 조절 손잡이

/// 렌즈 위의 도구 막대. 빈 곳을 끌면 렌즈가 함께 움직인다.
struct LensToolbarView: View {
    @Bindable var model: LensModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("끌어서 렌즈 옮기기")
            status
            Spacer(minLength: 4)
            Picker("번역 언어", selection: Binding(get: { model.language }, set: { model.select($0) })) {
                ForEach(TargetLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button(
                model.isPaused ? "번역 다시 시작" : "번역 일시정지",
                systemImage: model.isPaused ? "play.fill" : "pause.fill"
            ) {
                model.setPaused(!model.isPaused)
            }
            .labelStyle(.iconOnly)
            .help(model.isPaused ? "번역 다시 시작" : "번역 일시정지 (원문 보기, 인식·번역 멈춤)")
            Toggle(
                isOn: Binding(get: { model.isTranscriptVisible }, set: { model.setTranscriptVisible($0) })
            ) {
                Label("번역 기록", systemImage: "list.bullet.rectangle")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("번역 기록을 렌즈 옆에 보기")
            Toggle("원문", isOn: Binding(get: { model.isPeeking }, set: { model.setPeeking($0) }))
                .toggleStyle(.button)
                .help("렌즈를 잠시 걷어 원문 보기")
            Button("복사", systemImage: "doc.on.doc", action: copy)
                .labelStyle(.iconOnly)
                .help("번역 복사")
            Button("닫기", systemImage: "xmark") { model.onClose?() }
                .labelStyle(.iconOnly)
                .help("렌즈 닫기")
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in model.onMove?(.changed) }
                .onEnded { _ in model.onMove?(.ended) }
        )
    }

    @ViewBuilder private var status: some View {
        if model.isPaused {
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
                .help("번역 일시정지됨")
        } else {
            activity
        }
    }

    @ViewBuilder private var activity: some View {
        switch model.status {
        case .recognizing, .translating:
            ProgressView().controlSize(.mini)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(message)
        case .watching:
            Image(systemName: "character.bubble")
                .foregroundStyle(.secondary)
                .help("렌즈 아래 내용이 바뀌면 자동으로 번역합니다")
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.copyText, forType: .string)
    }
}

/// 렌즈 옆 번역 기록. 나온 순서대로 쌓고, 맨 아래를 보고 있으면 새 기록을 따라간다 (위로 올려 읽는 중에는 그대로 둔다).
struct LensTranscriptView: View {
    let model: LensModel
    /// 맨 아래를 보고 있는지. 이때만 새 기록으로 따라 내려간다
    @State private var isFollowing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("번역 기록").font(.headline)
                Spacer()
                Button("전체 복사", systemImage: "doc.on.doc", action: copy)
                    .help("번역 기록 전체 복사")
                    .disabled(model.transcript.entries.isEmpty)
                Button("닫기", systemImage: "xmark") { model.setTranscriptVisible(false) }
                    .help("번역 기록 닫기")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            if model.transcript.entries.isEmpty {
                Text("번역한 내용이 여기에 차례로 쌓입니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                entries
            }
        }
        .controlSize(.small)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var entries: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.transcript.entries) { entry in
                        Text(entry.translation)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding(10)
                .textSelection(.enabled)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, atBottom in
                isFollowing = atBottom
            }
            .onChange(of: model.transcript.entries.last) { _, last in
                guard isFollowing, let last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onAppear {
                if let last = model.transcript.entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.transcript.text, forType: .string)
    }
}

/// 렌즈 오른쪽 아래 모서리. 끌면 크기가 바뀐다.
struct LensResizeHandleView: View {
    let model: LensModel

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .help("끌어서 렌즈 크기 바꾸기")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in model.onResize?(.changed) }
                    .onEnded { _ in model.onResize?(.ended) }
            )
    }
}

// MARK: - 창

/// 렌즈를 이루는 창. 앱을 활성화하지 않아 원래 앱의 포커스를 빼앗지 않는다.
final class LensPanel: NSPanel {
    /// - Parameter passesMouseThrough: true면 클릭·스크롤이 아래 창으로 간다 (렌즈 본체)
    init(content: NSView, level: NSWindow.Level, passesMouseThrough: Bool) {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        self.level = level
        // 렌즈를 띄운 데스크톱(전체 화면 앱 포함)에만 둔다. 모든 데스크톱에 두면 데스크톱을 바꿀 때마다 따라온다
        collectionBehavior = [.fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = passesMouseThrough
        contentView = content
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
}

/// 활성화되지 않은 패널에서도 첫 클릭부터 버튼·끌기가 동작하게 한다.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
