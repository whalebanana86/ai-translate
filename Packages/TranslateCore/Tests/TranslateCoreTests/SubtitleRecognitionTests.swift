import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import TranslateCore

/// 유튜브 자막처럼 영상 위에 반투명 검은 상자와 흰 글자로 그린 자막을 인식한다.
struct SubtitleRecognitionTests {
    /// 영상 장면 대신 색이 다른 도형을 겹쳐 그린 배경 위에, 줄마다 가운데 정렬한 자막 상자를 그린다
    static func render(_ lines: [String], width: Int = 1200, height: Int = 260, size: CGFloat = 34) -> CGImage? {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.35, green: 0.55, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let shapes: [(CGRect, CGColor)] = [
            (CGRect(x: 0, y: 0, width: 500, height: 140), CGColor(srgbRed: 0.85, green: 0.75, blue: 0.6, alpha: 1)),
            (CGRect(x: 420, y: 60, width: 380, height: 200), CGColor(srgbRed: 0.2, green: 0.25, blue: 0.5, alpha: 1)),
            (CGRect(x: 760, y: 0, width: 440, height: 120), CGColor(srgbRed: 0.95, green: 0.95, blue: 0.9, alpha: 1)),
        ]
        for (rect, color) in shapes {
            context.setFillColor(color)
            context.fillEllipse(in: rect)
        }

        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                srgbRed: 1, green: 1, blue: 1, alpha: 1),
        ]
        let lineHeight = (size * 1.35).rounded()
        let padding = (size * 0.25).rounded()
        // 아래에서 위로 쌓는다 (CGContext는 왼쪽 아래 원점)
        let bottom = CGFloat(30)
        for (index, text) in lines.reversed().enumerated() {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let textWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            let box = CGRect(
                x: (CGFloat(width) - textWidth) / 2 - padding, y: bottom + CGFloat(index) * lineHeight,
                width: textWidth + padding * 2, height: lineHeight)
            context.setFillColor(CGColor(srgbRed: 0.03, green: 0.03, blue: 0.03, alpha: 0.75))
            context.fill(box)
            context.textPosition = CGPoint(x: box.minX + padding, y: box.minY + (lineHeight - size) / 2 + size * 0.2)
            CTLineDraw(ctLine, context)
        }
        return context.makeImage()
    }

    @Test func recognizesTwoCenteredCaptionLinesAsOneParagraph() async throws {
        let image = try #require(
            Self.render(["So the real question is whether we can", "make this work before the deadline"]))

        let blocks = TextBlockGrouper.group(try await TextRecognizer().recognize(image))

        // 한 문장이 두 줄에 걸쳐 있으므로 한 문단으로 번역한다
        try #require(blocks.count == 1)
        #expect(blocks[0].text == "So the real question is whether we can make this work before the deadline")
        // 번역은 자막 상자처럼 어두운 바탕에 흰 글자로 그린다
        let colors = try #require(BlockColors.sample(image, in: blocks[0].boundingBox))
        #expect(colors.background.luminance < 0.05)
        #expect(colors.text.luminance > 0.9)
    }
}
