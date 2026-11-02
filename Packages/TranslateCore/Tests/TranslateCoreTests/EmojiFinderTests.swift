import CoreGraphics
import Testing

@testable import TranslateCore

struct EmojiFinderTests {
    /// 흰 바탕에 도형을 그린 이미지 (왼쪽 위 원점 좌표로 받는다)
    private struct Canvas {
        let context: CGContext
        let height: Int

        init(width: Int = 1000, height: Int = 200) {
            context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            self.height = height
            fill(CGRect(x: 0, y: 0, width: width, height: height), red: 1, green: 1, blue: 1)
        }

        func fill(_ rect: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat) {
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }

        /// 검은 글자 대신 검은 막대 (색이 없다)
        func word(_ rect: CGRect) {
            fill(rect.insetBy(dx: 2, dy: 6), red: 0, green: 0, blue: 0)
        }

        /// 여러 색 이모지 (네 칸)
        func emoji(_ rect: CGRect) {
            let half = rect.width / 2
            fill(CGRect(x: rect.minX, y: rect.minY, width: half, height: half), red: 1, green: 0.8, blue: 0)
            fill(CGRect(x: rect.minX + half, y: rect.minY, width: half, height: half), red: 0.9, green: 0.1, blue: 0.1)
            fill(CGRect(x: rect.minX, y: rect.minY + half, width: half, height: half), red: 0.1, green: 0.6, blue: 0.2)
            fill(
                CGRect(x: rect.minX + half, y: rect.minY + half, width: half, height: half), red: 0.1, green: 0.3,
                blue: 0.9)
        }

        /// 파란 글자: 가는 세로 획
        func blueWord(_ rect: CGRect) {
            for x in stride(from: rect.minX + 2, to: rect.maxX - 4, by: 10) {
                fill(
                    CGRect(x: x, y: rect.minY + 4, width: 4, height: rect.height - 8), red: 0.11, green: 0.6, blue: 0.94
                )
            }
        }

        var image: CGImage { context.makeImage()! }
    }

    /// 단어마다 (글, x, 너비), 줄 높이 30, 위 끝 `y`
    private func line(_ words: [(String, CGFloat, CGFloat)], y: CGFloat = 80) -> RecognizedLine {
        let boxes = words.map { CGRect(x: $0.1, y: y, width: $0.2, height: 30) }
        return RecognizedLine(
            text: words.map(\.0).joined(separator: " "), confidence: 1,
            boundingBox: boxes.reduce(CGRect.null) { $0.union($1) }, wordBoxes: boxes)
    }

    @Test func marksEmojiAfterLine() {
        let canvas = Canvas()
        let text = line([("This", 100, 60), ("is", 170, 30), ("amazing", 210, 120)])
        text.wordBoxes.forEach(canvas.word)
        canvas.emoji(CGRect(x: 345, y: 80, width: 30, height: 30))

        let result = EmojiFinder.apply(to: [text], in: canvas.image)

        #expect(result.map(\.text) == ["This is amazing 🟦"])
        #expect(result[0].emojis.count == 1)
        #expect(abs(result[0].emojis[0].minX - 345) <= 1 && abs(result[0].emojis[0].width - 30) <= 1)
        #expect(result[0].boundingBox.maxX >= 375)
    }

    @Test func marksEmojiFollowingAnotherEmoji() {
        let canvas = Canvas()
        let text = line([("This", 100, 60), ("is", 170, 30), ("amazing", 210, 120)])
        text.wordBoxes.forEach(canvas.word)
        // 둘째 이모지는 글 끝에서 줄 높이 1.5배(45)보다 멀지만 첫 이모지 바로 뒤다
        canvas.emoji(CGRect(x: 345, y: 80, width: 30, height: 30))
        canvas.emoji(CGRect(x: 385, y: 80, width: 30, height: 30))

        let result = EmojiFinder.apply(to: [text], in: canvas.image)

        #expect(result.map(\.text) == ["This is amazing 🟦 🟦"])
        #expect(result[0].emojis.count == 2)
    }

    @Test func joinsLinesSplitByEmoji() {
        let canvas = Canvas()
        let before = line([("오늘", 100, 60), ("날씨", 170, 60), ("좋다", 240, 60)])
        let after = line([("산책", 350, 60), ("가자", 420, 60)])
        (before.wordBoxes + after.wordBoxes).forEach(canvas.word)
        canvas.emoji(CGRect(x: 310, y: 80, width: 30, height: 30))

        let result = EmojiFinder.apply(to: [before, after], in: canvas.image)

        #expect(result.map(\.text) == ["오늘 날씨 좋다 🟦 산책 가자"])
        #expect(result[0].wordBoxes.count == 6)
    }

    @Test func dropsCharactersMisreadFromEmoji() {
        let canvas = Canvas()
        // 🎉를 "然"으로 읽은 줄 (영어 줄의 한자), 🤡를 "®"로 읽은 줄
        let party = line([("Congrats!!", 100, 150), ("然", 260, 40), ("You", 310, 50), ("deserve", 370, 100)])
        let clown = line([("first", 100, 70), ("try", 180, 40), ("®", 230, 30)], y: 140)
        for box in party.wordBoxes + clown.wordBoxes where ![260, 230].contains(box.minX) {
            canvas.word(box)
        }
        canvas.emoji(CGRect(x: 262, y: 80, width: 36, height: 30))
        canvas.emoji(CGRect(x: 230, y: 140, width: 30, height: 30))

        let result = EmojiFinder.apply(to: [party, clown], in: canvas.image)

        #expect(result.map(\.text) == ["Congrats!! 🟦 You deserve", "first try 🟦"])
    }

    @Test func dropsShortWordOverMulticoloredEmojiButKeepsBlueWord() {
        let canvas = Canvas()
        // 🎉를 "it"으로 읽은 줄, 파란 해시태그 "#AI"를 "Al"로 읽은 줄
        let party = line([("Congrats!!", 100, 150), ("it", 260, 36), ("You", 310, 50)])
        let hashtag = line([("Follow", 100, 90), ("Al", 200, 40), ("now", 250, 50)], y: 140)
        canvas.word(party.wordBoxes[0])
        canvas.word(party.wordBoxes[2])
        canvas.emoji(CGRect(x: 260, y: 80, width: 36, height: 30))
        canvas.word(hashtag.wordBoxes[0])
        canvas.blueWord(hashtag.wordBoxes[1])
        canvas.word(hashtag.wordBoxes[2])

        let result = EmojiFinder.apply(to: [party, hashtag], in: canvas.image)

        #expect(result.map(\.text) == ["Congrats!! 🟦 You", "Follow Al now"])
        #expect(result[1].emojis.isEmpty)
    }

    @Test func leavesLinkTextProfilePictureAndFarEmojiAlone() {
        let canvas = Canvas()
        let link = line([("Follow", 100, 90), ("OpenAI", 200, 100)])
        let name = line([("Sylvester", 120, 120), ("Prosper", 250, 100)], y: 140)
        canvas.word(link.wordBoxes[0])
        canvas.blueWord(link.wordBoxes[1])
        name.wordBoxes.forEach(canvas.word)
        // 글줄보다 훨씬 큰 프로필 사진, 줄에서 멀리 떨어진 이모지
        canvas.fill(CGRect(x: 40, y: 120, width: 70, height: 70), red: 0.95, green: 0.5, blue: 0.1)
        canvas.emoji(CGRect(x: 700, y: 80, width: 30, height: 30))

        let result = EmojiFinder.apply(to: [link, name], in: canvas.image)

        #expect(result == [link, name])
    }

    @Test func removesMarkersForPlainText() {
        #expect(EmojiFinder.removingMarkers("Congrats!! 🟦 You deserve it 🟦") == "Congrats!! You deserve it")
        #expect(EmojiFinder.removingMarkers("🟦 Launching today") == "Launching today")
        #expect(EmojiFinder.removingMarkers("정말 축하해요!🟦") == "정말 축하해요!")
    }

    // MARK: 실제 OCR

    @Test func marksEmojiRecognizedByVision() async throws {
        let image = try #require(
            TextImage.render([
                .init(text: "This is amazing 😂🔥", x: 40, top: 40),
                .init(text: "오늘 날씨 좋다 😊 산책 가자", x: 40, top: 140),
            ]))

        let lines = EmojiFinder.apply(to: try await TextRecognizer().recognize(image), in: image)

        #expect(lines.map(\.text) == ["This is amazing 🟦", "오늘 날씨 좋다 🟦 산책 가자"])
        #expect(lines.map(\.emojis.count) == [1, 1])
    }
}
