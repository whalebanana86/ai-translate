import CoreGraphics
import Testing

@testable import TranslateCore

struct BlockColorsTests {
    private let box = CGRect(x: 10, y: 10, width: 500, height: 60)

    private func render(background: SRGBColor, text: SRGBColor?) -> CGImage? {
        func color(_ color: SRGBColor) -> CGColor {
            CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
        let lines = text == nil ? [] : [TextImage.Line(text: "Prepare your Mac", x: 20, top: 20, size: 40)]
        return TextImage.render(
            lines, width: 600, height: 100, background: color(background), foreground: color(text ?? background))
    }

    private func isClose(_ lhs: SRGBColor, _ rhs: SRGBColor, within tolerance: Double) -> Bool {
        abs(lhs.red - rhs.red) <= tolerance && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
    }

    @Test(arguments: [
        // 밝은 페이지: 흰 바탕, 검은 글자
        (SRGBColor.white, SRGBColor.black),
        // 어두운 페이지: 짙은 회색 바탕, 흰 글자 (실제 페이지 #1C1D20)
        (SRGBColor(red: 0.11, green: 0.114, blue: 0.125), SRGBColor(red: 0.95, green: 0.95, blue: 0.95)),
        // 어두운 바탕의 금색 글자 ("STEP 1 OF 3")
        (SRGBColor(red: 0.11, green: 0.114, blue: 0.125), SRGBColor(red: 0.88, green: 0.69, blue: 0.25)),
    ])
    func findsBackgroundAndTextColors(background: SRGBColor, text: SRGBColor) throws {
        let image = try #require(render(background: background, text: text))

        let colors = try #require(BlockColors.sample(image, in: box))

        #expect(isClose(colors.background, background, within: 0.01))
        #expect(isClose(colors.text, text, within: 0.06))
    }

    @Test func picksReadableTextColorWhenThereIsNoText() throws {
        let dark = try #require(render(background: SRGBColor(red: 0.11, green: 0.114, blue: 0.125), text: nil))
        let light = try #require(render(background: SRGBColor(red: 0.97, green: 0.97, blue: 0.97), text: nil))

        let darkColors = try #require(BlockColors.sample(dark, in: box))
        let lightColors = try #require(BlockColors.sample(light, in: box))

        #expect(darkColors.text == SRGBColor.white)
        #expect(lightColors.text == SRGBColor.black)
    }

    @Test func picksReadableTextColorWhenContrastIsTooLow() throws {
        // 회색 바탕에 거의 같은 회색 글자: 글자색 대신 검정·흰색 중 대비가 큰 쪽
        let image = try #require(
            render(
                background: SRGBColor(red: 0.5, green: 0.5, blue: 0.5), text: SRGBColor(red: 0.6, green: 0.6, blue: 0.6)
            ))

        let colors = try #require(BlockColors.sample(image, in: box))

        #expect(colors.text == SRGBColor.black)
    }

    @Test func clipsBoxToImageAndRejectsBoxOutside() throws {
        let image = try #require(render(background: .white, text: .black))

        let clipped = BlockColors.sample(image, in: CGRect(x: 500, y: 50, width: 400, height: 400))

        #expect(clipped?.background == SRGBColor.white)
        #expect(BlockColors.sample(image, in: CGRect(x: 700, y: 0, width: 50, height: 50)) == nil)
    }
}
