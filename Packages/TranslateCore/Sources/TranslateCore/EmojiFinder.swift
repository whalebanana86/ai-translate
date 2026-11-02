import CoreGraphics

/// 글줄 안팎의 이모지를 찾아 번역에 그대로 남긴다 (TASK-052).
///
/// Vision은 이모지를 글자로 읽지 못한다. 대부분 빼고 읽지만 엉뚱한 글자로 읽기도 하고(🎉 → "it"·"然", 🤡 → "®", 🚀 → "*"),
/// 문장 가운데 이모지에서 줄을 둘로 나누기도 한다. 번역 상자는 이모지까지 덮어 이모지가 사라졌다.
/// - OCR 줄과 같은 높이 띠에서 색 있는 덩어리를 찾는다. 띠 밖으로 크게 넘치는 덩어리(프로필 사진)는 뺀다
/// - 진짜 단어 영역과 겹치는 덩어리는 색 글자(파란 링크, 빨간 제목)다. 이모지와 겹친 엉뚱한 글자는 뺀다
/// - 이모지 자리에 `marker`를 넣고 영역을 `RecognizedLine.emojis`에 둔다. 렌즈는 그 자리에 캡처에서 오린 이모지를 그린다
public enum EmojiFinder {
    /// 번역할 글에서 이모지 자리. OCR은 이모지를 내놓지 않으므로 원문 글과 겹치지 않고, 로컬 번역 모델이 번역 뒤에도 그대로 남긴다
    /// (측정 36/36)
    public static let marker: Character = "🟦"

    /// 색 있는 픽셀: 가장 큰 RGB 성분과 가장 작은 성분의 차이 (검정·회색·흰 글자와 바탕은 0에 가깝다)
    static let minimumChroma = 60
    /// 줄 높이 띠에서 색 있는 픽셀이 이 비율 이상인 열이 이어지면 덩어리
    static let columnDensity = 0.15
    /// 덩어리 안 이 비율(줄 높이 대비)까지의 빈 열은 잇는다 (이모지 안 흰 부분)
    static let gapRatio = 0.2
    /// 덩어리 너비·높이 최소 (줄 높이 대비)
    static let minimumSizeRatio = 0.4
    /// 위·아래로 이만큼(줄 높이 대비) 넘게 띠 밖으로 이어지면 이모지가 아니다 (프로필 사진, 영상 화면)
    static let overflowRatio = 0.25
    /// 줄 끝·앞에서 이만큼(줄 높이 대비) 안의 이모지만 그 줄에 붙인다. 두 줄 사이 이모지는 양쪽 다 이 안이면 두 줄을 잇는다
    static let reachRatio = 1.5
    /// 두 글자 이하 단어를 이모지를 잘못 읽은 글자로 볼 덩어리 색 퍼짐 (가장 많은 색상 구간 밖 비율). 파란 링크 "Al" 0.00, 🎉 0.42
    static let junkSpread = 0.25
    /// 두 글자 이하 단어를 잘못 읽은 글자로 볼 덩어리 채움(색 있는 픽셀 ÷ 너비×줄 높이). 한 가지 색 이모지(👍 → "de")를 잡는다.
    /// 측정: 이모지 0.31~0.75(😂🔥❤️😊 0.6 이상), 파란·빨간 글자 0.25~0.38 (TASK-055)
    static let junkFill = 0.45

    /// 이모지 자리에 표시를 넣고 잘못 읽은 글자를 뺀 줄. 바뀌지 않은 줄은 그대로 돌려준다
    public static func apply(to lines: [RecognizedLine], in image: CGImage) -> [RecognizedLine] {
        guard !lines.isEmpty, let pixels = Pixels(image) else { return lines }
        return rows(of: lines).flatMap { row -> [RecognizedLine] in
            let blobs = pixels.blobs(around: row).filter { !isColoredText($0, in: row) }
            guard !blobs.isEmpty else { return row }
            return place(blobs, in: row)
        }
        .sorted { ($0.boundingBox.minY, $0.boundingBox.minX) < ($1.boundingBox.minY, $1.boundingBox.minX) }
    }

    /// 번역 기록·복사처럼 그림을 넣을 수 없는 곳에 쓸 글: 표시와 그 앞(없으면 뒤) 공백 하나를 지운다
    public static func removingMarkers(_ text: String) -> String {
        let marker = String(marker)
        return text.replacing(" " + marker, with: "").replacing(marker + " ", with: "").replacing(marker, with: "")
    }

    // MARK: 줄 묶기

    /// 세로로 절반 넘게 겹치는 줄끼리(같은 높이의 글줄) 묶는다. 묶음 안은 왼쪽부터
    static func rows(of lines: [RecognizedLine]) -> [[RecognizedLine]] {
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { $0.boundingBox.minY < $1.boundingBox.minY }) {
            let box = line.boundingBox
            if let index = rows.firstIndex(where: { row in
                row.contains { other in
                    let overlap = min(other.boundingBox.maxY, box.maxY) - max(other.boundingBox.minY, box.minY)
                    return overlap >= min(other.boundingBox.height, box.height) * 0.5
                }
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }

    // MARK: 덩어리

    /// 색 있는 덩어리. `spread`는 색상 퍼짐(가장 많은 60도 구간 밖 비율), `fill`은 줄 높이 띠 안 채움
    struct Blob: Equatable {
        var box: CGRect
        var spread: Double
        var fill: Double
    }

    /// 단어 하나. 이모지는 `isEmoji`
    struct Word {
        var text: String
        var box: CGRect
        var isEmoji = false
    }

    /// 줄의 단어. 단어 영역이 없거나 맞지 않으면 줄 전체를 한 단어로 본다
    static func words(of line: RecognizedLine) -> [Word] {
        let texts = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard texts.count == line.wordBoxes.count, !line.wordBoxes.contains(where: \.isNull) else {
            return [Word(text: line.text, box: line.boundingBox)]
        }
        return zip(texts, line.wordBoxes).map { Word(text: $0, box: $1) }
    }

    /// 덩어리가 진짜 단어(잘못 읽은 글자가 아닌)와 절반 넘게 겹치면 색 글자다
    static func isColoredText(_ blob: Blob, in row: [RecognizedLine]) -> Bool {
        let covered = row.flatMap { line in
            words(of: line).filter { !isMisread($0, over: blob, in: line) }
        }
        .reduce(0) { $0 + max(0, min($1.box.maxX, blob.box.maxX) - max($1.box.minX, blob.box.minX)) }
        return covered >= blob.box.width * 0.5
    }

    /// 이모지를 잘못 읽은 글자: 덩어리와 절반 넘게 겹치고, 글자가 없거나(®, *), 줄의 다른 단어와 문자가 다르거나(영어 줄의 然),
    /// 두 글자 이하이면서 덩어리 색이 여러 가지거나(🎉 → "it") 꽉 찼다(👍 → "de"). 파란 "Al"은 한 가지 색에 가는 획이다
    static func isMisread(_ word: Word, over blob: Blob, in line: RecognizedLine) -> Bool {
        let overlap = min(word.box.maxX, blob.box.maxX) - max(word.box.minX, blob.box.minX)
        guard word.box.width > 0, overlap >= word.box.width * 0.5 else { return false }
        let letters = word.text.filter(\.isLetter)
        if letters.isEmpty {
            return true
        }
        if letters.allSatisfy(isEastAsian), !line.text.filter(\.isLetter).allSatisfy(isEastAsian) {
            return true
        }
        return letters.count <= 2 && (blob.spread >= junkSpread || blob.fill >= junkFill)
    }

    private static func isEastAsian(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x3040...0x30FF).contains(value) || (0x3400...0x9FFF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
    }

    // MARK: 표시 넣기

    /// 덩어리를 줄에 넣는다: 줄 안이면 그 자리, 두 줄 사이면 두 줄을 잇고, 줄 끝·앞 가까이면 붙인다. 이모지와 겹친 엉뚱한 글자는 뺀다
    static func place(_ blobs: [Blob], in row: [RecognizedLine]) -> [RecognizedLine] {
        let height = row.map(\.boundingBox.height).max() ?? 0
        let reach = height * reachRatio
        /// 줄(이었으면 여러 줄)과 그 단어. 바뀐 줄만 다시 만든다
        struct Segment {
            var lines: [RecognizedLine]
            var words: [Word]
            var changed = false
            /// 붙인 이모지까지 넣은 범위 (😂🔥처럼 이어진 이모지는 앞 이모지에서 거리를 잰다)
            var span: CGRect { (lines.map(\.boundingBox) + words.map(\.box)).reduce(CGRect.null) { $0.union($1) } }
        }
        var segments = row.map { line in
            Segment(
                lines: [line],
                words: words(of: line).filter { word in !blobs.contains { isMisread(word, over: $0, in: line) } })
        }
        for blob in blobs.sorted(by: { $0.box.minX < $1.box.minX }) {
            let emoji = Word(text: String(marker), box: blob.box, isEmoji: true)
            if let inside = segments.firstIndex(where: { $0.span.minX < blob.box.midX && blob.box.midX < $0.span.maxX })
            {
                segments[inside].words.append(emoji)
                segments[inside].changed = true
                continue
            }
            let left = segments.indices.filter { segments[$0].span.maxX <= blob.box.midX }.last
            let right = segments.indices.first { segments[$0].span.minX >= blob.box.midX }
            let leftClose = left.map { blob.box.minX - segments[$0].span.maxX <= reach } ?? false
            let rightClose = right.map { segments[$0].span.minX - blob.box.maxX <= reach } ?? false
            if let left, let right, leftClose, rightClose {
                segments[left].lines += segments[right].lines
                segments[left].words += [emoji] + segments[right].words
                segments[left].changed = true
                segments.remove(at: right)
            } else if let left, leftClose {
                segments[left].words.append(emoji)
                segments[left].changed = true
            } else if let right, rightClose {
                segments[right].words.insert(emoji, at: 0)
                segments[right].changed = true
            }
        }
        return segments.map { segment in
            guard segment.changed else { return segment.lines[0] }
            let words = segment.words.sorted { $0.box.minX < $1.box.minX }
            return RecognizedLine(
                text: words.map(\.text).joined(separator: " "),
                confidence: segment.lines.map(\.confidence).min() ?? 0,
                boundingBox: words.map(\.box).reduce(segment.lines.map(\.boundingBox).reduce(.null) { $0.union($1) }) {
                    $0.union($1)
                },
                wordBoxes: words.map(\.box),
                emojis: words.filter(\.isEmoji).map(\.box))
        }
    }

    // MARK: 픽셀

    /// 이미지 전체를 한 번 읽어 둔 색 있는 픽셀 지도. 줄마다 오려 읽으면 3200×1520 화면에서 수백 ms가 걸렸다
    struct Pixels {
        let width: Int
        let height: Int
        /// 픽셀마다 색 있으면 1 + 색상 구간(0~5), 없으면 0
        let hue: [UInt8]

        init?(_ image: CGImage) {
            let (width, height) = (image.width, image.height)
            guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            var hue = [UInt8](repeating: 0, count: width * height)
            bytes.withUnsafeBufferPointer { source in
                hue.withUnsafeMutableBufferPointer { target in
                    for index in 0..<(width * height) {
                        let red = Int(source[index * 4])
                        let green = Int(source[index * 4 + 1])
                        let blue = Int(source[index * 4 + 2])
                        let high = max(red, green, blue)
                        let low = min(red, green, blue)
                        if high - low >= EmojiFinder.minimumChroma {
                            target[index] = 1 + Self.hueSector(red, green, blue, high: high, delta: high - low)
                        }
                    }
                }
            }
            self.width = width
            self.height = height
            self.hue = hue
        }

        /// 색상을 60도 구간 6개로 나눈 번호
        static func hueSector(_ red: Int, _ green: Int, _ blue: Int, high: Int, delta: Int) -> UInt8 {
            let (r, g, b, d) = (Double(red), Double(green), Double(blue), Double(delta))
            var hue = high == red ? (g - b) / d : high == green ? 2 + (b - r) / d : 4 + (r - g) / d
            if hue < 0 { hue += 6 }
            return UInt8(Int(hue) % 6)
        }

        /// 줄 묶음 높이에서 색 있는 열이 이어진 덩어리 중 이모지 크기이고 위·아래로 크게 넘치지 않는 것
        func blobs(around row: [RecognizedLine]) -> [Blob] {
            guard let rowTop = row.map(\.boundingBox.minY).min(), let rowBottom = row.map(\.boundingBox.maxY).max()
            else { return [] }
            let top = max(Int(rowTop.rounded(.down)), 0)
            let bottom = min(Int(rowBottom.rounded(.up)), height)
            let lineHeight = Double(bottom - top)
            guard lineHeight >= 4 else { return [] }
            // 줄 높이 띠의 열마다 색 있는 픽셀 수
            var counts = [Int](repeating: 0, count: width)
            hue.withUnsafeBufferPointer { hue in
                for y in top..<bottom {
                    let rowStart = y * width
                    for x in 0..<width where hue[rowStart + x] != 0 {
                        counts[x] += 1
                    }
                }
            }
            let dense = lineHeight * EmojiFinder.columnDensity
            let maxGap = Int(lineHeight * EmojiFinder.gapRatio)
            var runs: [ClosedRange<Int>] = []
            var start: Int?
            var lastDense = 0
            for x in 0..<width {
                if Double(counts[x]) >= dense {
                    if start == nil { start = x }
                    lastDense = x
                } else if let first = start, x - lastDense > maxGap {
                    runs.append(first...lastDense)
                    start = nil
                }
            }
            if let first = start {
                runs.append(first...lastDense)
            }
            let minimum = lineHeight * EmojiFinder.minimumSizeRatio
            let overflow = lineHeight * EmojiFinder.overflowRatio
            let searchTop = max(top - Int(lineHeight / 2), 0)
            let searchBottom = min(bottom + Int(lineHeight / 2), height)
            return runs.filter { Double($0.count) >= minimum }.compactMap { run in
                var minY = Int.max
                var maxY = Int.min
                var sectors = [Int](repeating: 0, count: 6)
                for y in searchTop..<searchBottom {
                    for x in run where hue[y * width + x] != 0 {
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                        if y >= top, y < bottom {
                            sectors[Int(hue[y * width + x]) - 1] += 1
                        }
                    }
                }
                guard Double(top - minY) <= overflow, Double(maxY - bottom) <= overflow,
                    Double(maxY - minY + 1) >= minimum
                else { return nil }
                let colored = max(sectors.reduce(0, +), 1)
                return Blob(
                    box: CGRect(x: run.lowerBound, y: minY, width: run.count, height: maxY - minY + 1),
                    spread: 1 - Double(sectors.max() ?? 0) / Double(colored),
                    fill: Double(sectors.reduce(0, +)) / (Double(run.count) * lineHeight))
            }
        }
    }
}
