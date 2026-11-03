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
        /// 원문 글자 굵기 (TASK-060)
        var weight: TextWeight = .regular
        /// 원문의 바탕색·글자색. 번역을 이 색으로 그린다
        var colors: BlockColors
        /// 원문 이모지 그림. 번역 글의 이모지 표시(`EmojiFinder.marker`) 자리에 그린다
        var emojis: [CGImage] = []

        /// 원문 자리에 그릴 번역. 번역 전 문단은 가림 상자만, 번역할 필요가 없는 문단은 아무것도 그리지 않는다(원문이 보인다)
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
    /// 영상(계속 바뀌는 화면)을 보는 중. 자막 사이 빈 구간에 "텍스트를 찾지 못했습니다" 안내를 띄우지 않는다
    var isWatchingVideo = false
    /// 렌즈 옆 패널에 보여줄 번역 기록
    var transcript = TranslationTranscript()
    private(set) var language: TargetLanguage
    private(set) var isPeeking = false
    private(set) var isTranscriptVisible: Bool
    /// 번역 일시정지. 캡처·인식·번역을 멈추고 번역을 그리지 않아 원문이 보인다
    private(set) var isPaused = false
    /// 이중 자막: 영상 자막은 원문을 가리지 않고 번역을 원문 위(자리가 없으면 아래)에 함께 보여준다
    private(set) var showsSourceCaptions: Bool

    @ObservationIgnored var onLanguageChange: ((TargetLanguage) -> Void)?
    @ObservationIgnored var onPeekChange: ((Bool) -> Void)?
    @ObservationIgnored var onTranscriptVisibilityChange: ((Bool) -> Void)?
    @ObservationIgnored var onPauseChange: ((Bool) -> Void)?
    @ObservationIgnored var onShowsSourceCaptionsChange: ((Bool) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onMove: ((DragPhase) -> Void)?
    @ObservationIgnored var onResize: ((DragPhase) -> Void)?
    @ObservationIgnored var onTranscriptMove: ((DragPhase) -> Void)?
    @ObservationIgnored var onTranscriptResize: ((DragPhase) -> Void)?

    init(language: TargetLanguage, showsTranscript: Bool, showsSourceCaptions: Bool = true) {
        self.language = language
        isTranscriptVisible = showsTranscript
        self.showsSourceCaptions = showsSourceCaptions
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

    func setShowsSourceCaptions(_ shows: Bool) {
        guard shows != showsSourceCaptions else { return }
        showsSourceCaptions = shows
        onShowsSourceCaptionsChange?(shows)
    }

    func setTranscriptVisible(_ visible: Bool) {
        isTranscriptVisible = visible
        onTranscriptVisibilityChange?(visible)
    }

    /// 번역이 끝난 문단(번역할 필요 없는 문단은 원문)을 빈 줄로 이어 붙인 글
    var copyText: String {
        paragraphs.compactMap { paragraph in
            switch paragraph.content {
            case .translated(let text), .original(let text): EmojiFinder.removingMarkers(text)
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
    static let backingInset: CGFloat = 3
    /// 번역을 기다리며 가린 원문 줄 막대의 진하기 (글자색 대비)
    static let lineBarOpacity = 0.18

    let model: LensModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if !model.isOutdated {
                let canTranslate = if case .failed = model.status { false } else { true }
                // 이중 자막은 원문이 보이므로 번역이 나오기 전에는 아무것도 그리지 않는다
                let covered = model.paragraphs.filter {
                    $0.content.hidesOriginal(canTranslate: canTranslate)
                        && ($0.translation != nil || !$0.frame.showsSource)
                }
                LensParagraphLayout(coverInset: Self.backingInset) {
                    // 가림 상자를 먼저(아래), 번역 글을 나중에(위) 그린다
                    ForEach(covered, content: cover)
                    ForEach(covered.filter { $0.translation != nil }, content: translation)
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

    /// 원문 문단과 번역 글을 모두 덮는 원문 바탕색 상자. 번역이 원문보다 짧아도, 자막 번역을 기억한 자리에 그려도 원문 글자가
    /// 보이지 않는다 (자리는 `LensParagraphLayout`이 정한다). 번역을 기다리는 문단은 줄 막대를 그려 번역 중임을 보인다
    private func cover(_ paragraph: LensModel.Paragraph) -> some View {
        Rectangle()
            .fill(Color(paragraph.colors.background))
            .overlay {
                if paragraph.translation == nil {
                    lineBars(paragraph)
                }
            }
            .layoutValue(key: ParagraphFrameKey.self, value: paragraph.frame)
            .layoutValue(key: ParagraphPartKey.self, value: .cover(paragraph.id))
    }

    /// 번역 글. 이모지 표시 자리에 원문에서 오린 이모지를 그린다(TASK-052: 이모지는 번역하지 않고 그대로). 번역에서 표시가
    /// 빠졌으면 남은 이모지를 끝에 붙이고, 그림보다 많은 표시는 지운다
    private func translationText(_ paragraph: LensModel.Paragraph) -> Text {
        let text = paragraph.translation ?? ""
        guard text.contains(EmojiFinder.marker) || !paragraph.emojis.isEmpty else { return Text(verbatim: text) }
        var images = paragraph.emojis.makeIterator()
        let emoji = { (image: CGImage) in
            // 이모지 글리프는 글자 크기의 약 1.15배이고 기준선 아래로 조금 내려온다
            Text(Image(decorative: image, scale: CGFloat(image.height) / (paragraph.fontSize * 1.15)))
                .baselineOffset(-paragraph.fontSize * 0.2)
        }
        let parts = text.split(separator: EmojiFinder.marker, omittingEmptySubsequences: false)
        var result = Text(verbatim: String(parts[0]))
        for part in parts.dropFirst() {
            if let image = images.next() {
                result = Text("\(result)\(emoji(image))")
            }
            result = Text("\(result)\(Text(verbatim: String(part)))")
        }
        while let image = images.next() {
            result = Text("\(result) \(emoji(image))")
        }
        return result
    }

    /// 가린 원문 줄마다 흐린 막대. 여러 줄이면 마지막 줄을 짧게 그려 글처럼 보이게 한다
    private func lineBars(_ paragraph: LensModel.Paragraph) -> some View {
        let lines = max(paragraph.frame.sourceLineCount, 1)
        return GeometryReader { proxy in
            let rowHeight = proxy.size.height / CGFloat(lines)
            VStack(spacing: 0) {
                ForEach(0..<lines, id: \.self) { index in
                    Capsule()
                        .fill(Color(paragraph.colors.text).opacity(Self.lineBarOpacity))
                        .frame(
                            width: proxy.size.width * (lines > 1 && index == lines - 1 ? 0.6 : 1),
                            height: rowHeight * 0.45
                        )
                        .frame(
                            maxWidth: .infinity, maxHeight: .infinity,
                            alignment: paragraph.frame.isCentered ? .center : .leading)
                }
            }
        }
        .padding(Self.backingInset)
    }

    private func translation(_ paragraph: LensModel.Paragraph) -> some View {
        translationText(paragraph)
            .font(.system(size: paragraph.fontSize, weight: Font.Weight(paragraph.weight)))
            .foregroundStyle(Color(paragraph.colors.text))
            // 자막은 가운데 정렬 (자막마다 너비·줄 수가 달라도 번역 자리가 그대로)
            .multilineTextAlignment(paragraph.frame.isCentered ? .center : .leading)
            .minimumScaleFactor(Self.minimumTextScale)
            .layoutValue(key: ParagraphFrameKey.self, value: paragraph.frame)
            .layoutValue(key: ParagraphPartKey.self, value: .text(paragraph.id))
            .layoutValue(
                key: TextLineCountKey.self,
                value: (paragraph.translation ?? "").split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    @ViewBuilder private var placeholder: some View {
        if model.paragraphs.isEmpty {
            Group {
                if model.hasRecognized {
                    // 영상 자막 사이 빈 구간마다 화면 한가운데 뜨지 않게 한다
                    if !model.isWatchingVideo {
                        Text("렌즈 안에서 텍스트를 찾지 못했습니다.")
                    }
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

/// 문단마다 가림 상자와 번역 글 두 조각을 그린다
private enum ParagraphPart: Equatable {
    case cover(Int)
    case text(Int)
}

private struct ParagraphPartKey: LayoutValueKey {
    static let defaultValue = ParagraphPart.text(-1)
}

/// 번역 글의 강제 줄 수. 자막 번역의 한 줄 높이를 잴 때 쓴다
private struct TextLineCountKey: LayoutValueKey {
    static let defaultValue = 1
}

/// 문단을 원문 위치에 두고, 쓸 수 있는 자리(너비·최대 높이) 안에서 글을 배치한다. 다른 문단을 밀지 않는다.
/// 보통 문단은 왼쪽 위, 자막은 가운데·아래 끝에 맞추고 원문 줄 수만큼 고르게 나눈다. 가림 상자는 원문 문단과 놓인 번역 글을 모두 덮는다.
struct LensParagraphLayout: Layout {
    /// 가림 상자를 원문·번역 영역보다 넓히는 여백
    var coverInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var textRects: [Int: CGRect] = [:]
        for subview in subviews {
            guard case .text(let id) = subview[ParagraphPartKey.self] else { continue }
            let frame = subview[ParagraphFrameKey.self]
            let proposal = ProposedViewSize(width: textWidth(of: subview, in: frame), height: frame.maxHeight)
            let size = subview.sizeThatFits(proposal)
            // 자막: 자리의 가운데·아래 끝(원문 아래에 둔 이중 자막은 위 끝). 보통 문단: 왼쪽 위
            let origin =
                frame.isCentered
                ? CGPoint(
                    x: frame.origin.x + (frame.width - size.width) / 2,
                    y: frame.alignsTextToTop ? frame.origin.y : frame.origin.y + frame.maxHeight - size.height)
                : frame.origin
            textRects[id] = CGRect(origin: origin, size: size)
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading,
                proposal: proposal)
        }
        for subview in subviews {
            guard case .cover(let id) = subview[ParagraphPartKey.self] else { continue }
            let frame = subview[ParagraphFrameKey.self]
            // 이중 자막은 원문을 가리지 않고 번역 글만 자막 상자처럼 감싼다
            let covered =
                frame.showsSource
                ? (textRects[id] ?? .zero).insetBy(dx: -coverInset * 3, dy: -coverInset)
                : frame.sourceRect.union(textRects[id] ?? frame.sourceRect).insetBy(dx: -coverInset, dy: -coverInset)
            subview.place(
                at: CGPoint(x: bounds.minX + covered.minX, y: bounds.minY + covered.minY), anchor: .topLeading,
                proposal: ProposedViewSize(covered.size))
        }
    }

    /// 번역 글이 줄바꿈되는 너비. 자막은 원문 줄 수만큼 고르게 나누는 너비(`LensGeometry.balancedWidth`), 보통 문단은 자리 너비.
    /// 높이를 잴 때는 세로를 제한하지 않는다 (제한하면 글자를 줄여 맞춰 줄 수를 셀 수 없다)
    private func textWidth(of subview: LayoutSubview, in frame: ParagraphFrame) -> CGFloat {
        guard frame.isCentered else { return frame.width }
        let lineHeight = subview.sizeThatFits(.unspecified).height / CGFloat(max(subview[TextLineCountKey.self], 1))
        return LensGeometry.balancedWidth(
            lines: frame.sourceLineCount, sourceWidth: frame.sourceSize.width, maxWidth: frame.width,
            lineHeight: lineHeight
        ) { width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
    }
}

extension Font.Weight {
    init(_ weight: TextWeight) {
        switch weight {
        case .regular: self = .regular
        case .semibold: self = .semibold
        case .bold: self = .bold
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
            .help("번역할 언어")
            Button(
                model.isPaused ? "번역 다시 시작" : "번역 일시정지",
                systemImage: model.isPaused ? "play.fill" : "pause.fill"
            ) {
                model.setPaused(!model.isPaused)
            }
            .labelStyle(.iconOnly)
            .help(model.isPaused ? "번역 다시 시작" : "번역 일시정지 (원문 보기, 인식·번역 멈춤)")
            // 영상을 볼 때만 보인다 (자막에만 쓰는 설정)
            if model.isWatchingVideo {
                Toggle(
                    isOn: Binding(get: { model.showsSourceCaptions }, set: { model.setShowsSourceCaptions($0) })
                ) {
                    Label("원문 함께", systemImage: "captions.bubble")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help("영상 자막: 원문 위에 번역을 함께 보기 (끄면 원문을 번역으로 가림)")
            }
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
        case .recognizing:
            ProgressView().controlSize(.mini)
                .help("렌즈 아래 글을 인식하는 중")
        case .translating:
            ProgressView().controlSize(.mini)
                .help("번역하는 중")
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

/// 렌즈 옆 번역 기록. 나온 순서대로 쌓고 새 기록으로 따라 내려간다. 사용자가 위로 올려 읽는 중이면 그대로 둔다.
/// 머리글을 끌면 옮겨지고, 오른쪽 아래 모서리를 끌면 크기가 바뀐다.
struct LensTranscriptView: View {
    let model: LensModel
    @State private var position = ScrollPosition(edge: .bottom)
    /// 맨 아래를 보고 있는지. 사용자가 스크롤해 위치가 바뀌었을 때만 다시 판단한다
    @State private var isFollowing = true

    /// 따라가기 판단에 쓰는 스크롤 상태
    private struct ScrollState: Equatable {
        var contentHeight: CGFloat
        var isAtBottom: Bool
    }

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
            .contentShape(Rectangle())
            .help("끌어서 번역 기록 옮기기")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in model.onTranscriptMove?(.changed) }
                    .onEnded { _ in model.onTranscriptMove?(.ended) }
            )
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
        .overlay(alignment: .bottomTrailing) { resizeHandle }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help("끌어서 번역 기록 크기 바꾸기")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in model.onTranscriptResize?(.changed) }
                    .onEnded { _ in model.onTranscriptResize?(.ended) }
            )
            .padding(2)
    }

    private var entries: some View {
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
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .onScrollGeometryChange(for: ScrollState.self) { geometry in
            ScrollState(
                contentHeight: geometry.contentSize.height,
                isAtBottom: geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            )
        } action: { old, new in
            // 새 기록으로 내용이 길어진 변화는 넘긴다. 그것까지 보면 새 기록으로 내려가기 전에 맨 아래가 아니라고 판단해
            // 따라가기를 멈췄다 (TASK-036). 내용 높이가 같은데 위치가 바뀌었으면 스크롤한 것이다
            guard old.contentHeight == new.contentHeight else { return }
            isFollowing = new.isAtBottom
        }
        .onChange(of: model.transcript.entries.last) {
            guard isFollowing else { return }
            position.scrollTo(edge: .bottom)
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
        // 렌즈를 쓰는 동안 앱은 비활성 상태라(패널이 앱을 활성화하지 않음) 이것이 없으면 툴팁이 뜨지 않는다 (TASK-057)
        allowsToolTipsWhenApplicationIsInactive = true
        contentView = content
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
}

/// 활성화되지 않은 패널에서도 첫 클릭부터 버튼·끌기가 동작하게 한다.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
