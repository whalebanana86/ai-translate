import CoreGraphics
import Testing

@testable import TranslateCore

struct TextRecognizerTests {
    private let recognizer = TextRecognizer()

    @Test func recognizesEnglishKoreanAndJapaneseLines() async throws {
        let image = try #require(
            TextImage.render([
                .init(text: "Start free. Upgrade when your team grows.", x: 40, top: 40),
                .init(text: "언제든지 해지할 수 있습니다.", x: 40, top: 120),
                .init(text: "料金プランを選択してください", x: 40, top: 200),
            ]))

        let lines = try await recognizer.recognize(image)

        #expect(
            lines.map(\.text) == [
                "Start free. Upgrade when your team grows.", "언제든지 해지할 수 있습니다.", "料金プランを選択してください",
            ])
        #expect(lines.allSatisfy { $0.confidence > 0.5 })
    }

    @Test func reportsTopLeftPixelCoordinatesInReadingOrder() async throws {
        // 일부러 아래 줄부터 그린다
        let image = try #require(
            TextImage.render([
                .init(text: "Second line of text", x: 300, top: 250),
                .init(text: "First line of text", x: 60, top: 50),
            ]))

        let lines = try await recognizer.recognize(image)

        try #require(lines.count == 2)
        #expect(lines.map(\.text) == ["First line of text", "Second line of text"])
        #expect(abs(lines[0].boundingBox.minX - 60) <= 8)
        #expect(abs(lines[0].boundingBox.minY - 50) <= 8)
        #expect(abs(lines[1].boundingBox.minX - 300) <= 8)
        #expect(abs(lines[1].boundingBox.minY - 250) <= 8)
    }

    @Test func returnsNoLinesForBlankImage() async throws {
        let image = try #require(TextImage.render([]))

        #expect(try await recognizer.recognize(image).isEmpty)
    }

    @Test func groupsRecognizedLinesIntoParagraphs() async throws {
        let image = try #require(
            TextImage.render([
                .init(text: "Start free and upgrade when your", x: 40, top: 40),
                .init(text: "team grows. Cancel anytime.", x: 40, top: 76),
                .init(text: "언제든지 해지할 수 있습니다.", x: 40, top: 180),
            ]))

        let blocks = TextBlockGrouper.group(try await recognizer.recognize(image))

        #expect(
            blocks.map(\.text) == [
                "Start free and upgrade when your team grows. Cancel anytime.", "언제든지 해지할 수 있습니다.",
            ])
    }
}
