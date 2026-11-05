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

    @Test(arguments: [true, false])
    func picksFirstColorWhenTwoColorsTie(redFirst: Bool) throws {
        // 반은 빨강, 반은 파랑(개수가 같다): 먼저 나온(왼쪽) 색이 바탕이다. 사전 순서로 고르면 읽을 때마다 바뀌었다 (TASK-079)
        let red = CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
        let blue = CGColor(srgbRed: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        let image = try #require(
            TextImage.render(
                [],
                shapes: [
                    .init(rect: CGRect(x: 0, y: 0, width: 50, height: 40), color: redFirst ? red : blue),
                    .init(rect: CGRect(x: 50, y: 0, width: 50, height: 40), color: redFirst ? blue : red),
                ], width: 100, height: 40))

        let backgrounds = (0..<50).compactMap { _ in
            BlockColors.sample(image, in: CGRect(x: 0, y: 0, width: 100, height: 40))?.background
        }

        #expect(backgrounds.count == 50)
        #expect(backgrounds.allSatisfy { ($0.red > 0.5) == redFirst })
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
