import CoreGraphics
import Testing

@testable import TranslateCore

struct TextStyleMeterTests {
    /// 그린 이미지를 실제 OCR로 읽고 문단마다 크기·굵기를 잰다 (문단은 위에서부터)
    private func measure(_ lines: [TextImage.Line], width: Int = 1400, height: Int = 400) async throws -> [TextStyle?] {
        let image = try #require(TextImage.render(lines, width: width, height: height))
        let recognized = try await TextRecognizer().recognize(image)
        let lineStyles = TextStyleMeter.measure(recognized, in: image)
        let blocks = TextBlockGrouper.group(recognized, styles: lineStyles).sorted {
            $0.boundingBox.minY < $1.boundingBox.minY
        }
        return TextStyleMeter.styles(of: blocks, lines: recognized, lineStyles: lineStyles)
    }

    @Test(arguments: [
        ("Helvetica", 28.0, "giving you a happy, guided journey"),
        ("Helvetica", 56.0, "The model was trained last March"),
        ("AppleSDGothicNeo-Regular", 40.0, "언제든지 해지할 수 있습니다"),
    ])
    func measuresFontSize(_ font: String, _ size: Double, _ text: String) async throws {
        let styles = try await measure([.init(text: text, x: 40, top: 60, size: size, font: font)])

        let style = try #require(styles.first ?? nil)
        let measured = style.pixelSize
        // 측정: Helvetica는 시스템 글꼴보다 글자 모양이 약 5% 커서 그만큼 크게 잰다
        #expect(abs(measured / size - 1) < 0.08)
    }

    @Test func sameSizeLinesMeasureAlikeWhateverTheirLetters() async throws {
        // 대문자만 있는 줄과 아래로 내려가는 글자가 있는 줄: 줄 상자 높이는 약 20% 달랐다
        let styles = try await measure([
            .init(text: "START FREE TODAY", x: 40, top: 40, size: 40),
            .init(text: "giving you a happy journey", x: 40, top: 200, size: 40),
        ])

        let sizes = styles.compactMap { $0?.pixelSize }
        #expect(sizes.count == 2)
        #expect(sizes.max()! / sizes.min()! < 1.05)
    }

    @Test func toleratesOcrDroppingADescender() async throws {
        // OCR이 "anytime"을 "antime"으로 읽은 줄 (Chrome 측정에서 실제로 나왔다). 줄 전체 높이로 비교하면 기준 글에 y가 없어
        // 26% 크게 쟀다. 라틴 글은 기준선 위만 비교한다
        let image = try #require(
            TextImage.render([.init(text: "Start free. Cancel anytime.", x: 40, top: 60, size: 40)], width: 1400))
        let recognized = try #require(try await TextRecognizer().recognize(image).first)
        let misread = RecognizedLine(
            text: "Start free. Cancel antime.", confidence: 1, boundingBox: recognized.boundingBox,
            wordBoxes: recognized.wordBoxes)
        let style = try #require(TextStyleMeter.measure([misread], in: image).first ?? nil)
        #expect(abs(style.pixelSize / 40 - 1) < 0.08)
    }

    @Test func ignoresUnderline() async throws {
        let plain = try await measure([.init(text: "Read the full release notes", x: 40, top: 60, size: 40)])
        let linked = try await measure([
            .init(text: "Read the full release notes", x: 40, top: 60, size: 40, underline: true)
        ])

        let plainSize = try #require(plain.first ?? nil).pixelSize
        let linkedSize = try #require(linked.first ?? nil).pixelSize
        #expect(abs(linkedSize / plainSize - 1) < 0.03)
    }

    @Test func tellsBoldFromRegular() async throws {
        let styles = try await measure(
            [
                .init(text: "Start free. Cancel anytime.", x: 40, top: 40, size: 40),
                .init(text: "Start free. Cancel anytime.", x: 40, top: 160, size: 40, font: "Helvetica-Bold"),
                .init(text: "언제든지 해지할 수 있습니다", x: 40, top: 280, size: 40, font: "AppleSDGothicNeo-Regular"),
            ], height: 520)
        let bold = try await measure([
            .init(text: "언제든지 해지할 수 있습니다", x: 40, top: 60, size: 40, font: "AppleSDGothicNeo-Bold")
        ])

        // Helvetica Bold 획은 시스템 글꼴 semibold와 bold 사이(측정 0.149)라 둘 중 하나로 그린다
        #expect(styles.count == 3)
        #expect(styles[0]?.weight == .regular)
        #expect((styles[1]?.weight ?? .regular) >= .semibold)
        #expect(styles[2]?.weight == .regular)
        let boldWeight = try #require((bold.first ?? nil)?.weight)
        #expect(boldWeight >= .semibold)
    }

    @Test func leavesWeightOfSmallTextUnmeasured() async throws {
        // 글자가 작으면 이웃 획이 번져 붙어 굵게 값으로 나올 수 있다
        let styles = try await measure([.init(text: "Start free. Cancel anytime.", x: 40, top: 60, size: 16)])

        let style = try #require(styles.first ?? nil)
        #expect(style.weight == nil)
        #expect(abs(style.pixelSize / 16 - 1) < 0.12)
    }

    @Test func givesUpWithoutContrast() throws {
        let image = try #require(
            TextImage.render(
                [.init(text: "faint", x: 40, top: 40)], background: CGColor(gray: 1, alpha: 1),
                foreground: CGColor(gray: 0.95, alpha: 1)))
        let line = RecognizedLine(
            text: "faint", confidence: 1, boundingBox: CGRect(x: 38, y: 36, width: 80, height: 32))

        #expect(TextStyleMeter.measure([line], in: image) == [nil])
    }

    @Test func splitsHeadingFromBodyRightBelowIt() async throws {
        // 굵은 제목 바로 아래 같은 크기의 본문: 위치로만 묶으면 한 문단이 되어 제목도 보통 굵기로 그렸다
        let lines: [TextImage.Line] = [
            .init(text: "What changed in this release", x: 40, top: 40, size: 40, font: "Helvetica-Bold"),
            .init(text: "Battery life looks better too, and the", x: 40, top: 92, size: 40),
        ]
        let image = try #require(TextImage.render(lines, width: 1400, height: 200))
        #expect(TextBlockGrouper.group(try await TextRecognizer().recognize(image)).count == 1)

        let styles = try await measure(lines, height: 200)

        #expect(styles.count == 2)
        #expect((styles.first??.weight ?? .regular) >= .semibold)
        #expect(styles.last??.weight == .regular)
    }

    @Test(arguments: [("Helvetica", 1.5), ("AppleSDGothicNeo-Regular", 1.8)])
    func measuresLineHeightOfParagraph(_ font: String, _ ratio: Double) async throws {
        let pitch = 32 * ratio
        let texts =
            font == "Helvetica"
            ? [
                "The new offline mode keeps your drafts on", "the device and syncs them later when you",
                "are back online again.",
            ]
            : ["오프라인 모드는 초안을 기기에 보관했다가", "다시 연결되면 나중에 동기화합니다.", "배터리도 더 오래갑니다."]
        let lines = texts.enumerated().map {
            TextImage.Line(text: $1, x: 40, top: 40 + CGFloat($0) * pitch, size: 32, font: font)
        }

        let styles = try await measure(lines, height: 300)

        #expect(styles.count == 1)
        let measured = try #require(styles.first??.lineHeight)
        #expect(abs(measured / pitch - 1) < 0.03)
    }

    @Test func singleLineHasNoLineHeight() async throws {
        let styles = try await measure([.init(text: "Start free. Cancel anytime.", x: 40, top: 60, size: 40)])

        #expect(styles.first??.lineHeight == nil)
    }

    @Test func keepsLinesOfOneParagraphTogether() {
        let size = LineStyle(pixelSize: 30, strokeRatio: 0.10, weight: .regular)
        // 같은 문단 줄의 측정 흔들림, 재지 못한 줄
        #expect(!TextBlockGrouper.differInStyle(size, LineStyle(pixelSize: 31.5, strokeRatio: 0.11, weight: .regular)))
        #expect(!TextBlockGrouper.differInStyle(size, nil))
        #expect(!TextBlockGrouper.differInStyle(size, LineStyle(pixelSize: 30, strokeRatio: nil, weight: nil)))
        // 목록 항목이 넘친 짧은 줄 "version": 굵기 이름은 경계를 넘었지만(semibold) 획 비율은 1.16배라 같은 문단
        #expect(
            !TextBlockGrouper.differInStyle(
                LineStyle(pixelSize: 33.5, strokeRatio: 0.103, weight: .regular),
                LineStyle(pixelSize: 29.9, strokeRatio: 0.119, weight: .semibold)))
        // 문단 끝 줄의 파란 링크: 대비가 낮아 획을 가늘게 재지만 둘 다 보통
        #expect(
            !TextBlockGrouper.differInStyle(
                LineStyle(pixelSize: 33.3, strokeRatio: 0.104, weight: .regular),
                LineStyle(pixelSize: 31.3, strokeRatio: 0.075, weight: .regular)))
        // 1.25배 넘게 큰 줄, 굵은 줄
        #expect(TextBlockGrouper.differInStyle(size, LineStyle(pixelSize: 38, strokeRatio: 0.10, weight: .regular)))
        #expect(TextBlockGrouper.differInStyle(size, LineStyle(pixelSize: 30, strokeRatio: 0.15, weight: .bold)))
    }

    @Test func picksClosestSystemWeight() {
        #expect(TextStyleMeter.weight(strokeRatio: 0.10, script: .latin) == .regular)
        #expect(TextStyleMeter.weight(strokeRatio: 0.135, script: .latin) == .semibold)
        #expect(TextStyleMeter.weight(strokeRatio: 0.16, script: .latin) == .bold)
        // 한글 글꼴은 획이 가늘다: 라틴이면 보통인 0.13이 한글에서는 굵게
        #expect(TextStyleMeter.weight(strokeRatio: 0.13, script: .hangul) == .bold)
        #expect(TextStyleMeter.weight(strokeRatio: 0.13, script: .latin) == .semibold)
        #expect(TextStyleMeter.script(of: "언제든지 해지 OK") == .hangul)
        #expect(TextStyleMeter.script(of: "料金プラン") == .cjk)
        #expect(TextStyleMeter.script(of: "Start free") == .latin)
    }

    @Test func remembersFirstWeightOfSameText() {
        var memory = TextWeightMemory()

        #expect(memory.weight(for: "Title", measured: nil) == .regular)
        #expect(memory.weight(for: "Title", measured: .bold) == .bold)
        // 스크롤 뒤 두 굵기 가운데쯤으로 재도 처음 굵기
        #expect(memory.weight(for: "Title", measured: .semibold) == .bold)
        #expect(memory.weight(for: "Body", measured: .regular) == .regular)
    }
}
