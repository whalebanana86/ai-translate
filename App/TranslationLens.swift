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
    private(set) var language: TargetLanguage
    private(set) var isPeeking = false

    @ObservationIgnored var onLanguageChange: ((TargetLanguage) -> Void)?
    @ObservationIgnored var onPeekChange: ((Bool) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onMove: ((DragPhase) -> Void)?
    @ObservationIgnored var onResize: ((DragPhase) -> Void)?

    init(language: TargetLanguage) {
        self.language = language
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
