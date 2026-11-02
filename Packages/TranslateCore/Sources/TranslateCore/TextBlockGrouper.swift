import CoreGraphics

/// 번역 단위가 되는 문단. 줄 단위로 번역하면 줄바꿈 위치에서 문장이 쪼개지므로 줄을 이어 붙인다.
public struct TextBlock: Equatable, Sendable {
    public var lines: [RecognizedLine]
    public var text: String
    /// 줄 영역의 합집합. 이미지 픽셀 좌표, 왼쪽 위 원점
    public var boundingBox: CGRect

    /// 번역할 글자가 있는지. 숫자·기호·버튼(`$19`, `120`, `...`, 아이콘을 글자로 읽은 좋아요 수 `C 42만`)은 번역하지 않고
    /// 원문 그대로 보여준다
    public var isTranslatable: Bool {
        text.hasWord
    }
}

/// OCR 줄을 위치로 판단해 문단으로 묶는다.
public enum TextBlockGrouper {
    /// 바로 위 줄과의 세로 간격이 줄 높이의 이 배수 이하면 같은 문단으로 본다
    static let maxLineGapRatio: CGFloat = 0.8
    /// 두 줄의 높이 비율이 이 값을 넘으면(제목과 본문 등) 다른 문단으로 본다
    static let maxHeightRatio: CGFloat = 1.5
    /// 글자가 이보다 많은 단어가 없는 줄은 다른 줄과 묶지 않고, 그런 문단은 번역하지 않는다 (`String.hasWord`)
    static let minimumLetters = 2
    /// 신뢰도가 이보다 낮고 글자가 `noiseMaxLetters`개 미만이면 아이콘을 잘못 읽은 잡음으로 보고 버린다.
    /// 실제 웹페이지에서 아이콘 잡음은 0.3~0.5, 본문은 1.0이었다
    static let noiseConfidence: Float = 0.6
    static let noiseMaxLetters = 4

    public static func group(_ lines: [RecognizedLine]) -> [TextBlock] {
        let sorted = lines.filter { !isNoise($0) }.sorted {
            ($0.boundingBox.minY, $0.boundingBox.minX) < ($1.boundingBox.minY, $1.boundingBox.minX)
        }
        var blocks: [[RecognizedLine]] = []
        for line in sorted {
            // 다단 구성에서는 단마다 줄이 번갈아 나오므로 직전 문단만이 아니라 모든 문단의 마지막 줄과 비교한다
            let index = blocks.lastIndex { block in
                (block.last.map { continues($0, with: line) } ?? false) && !sitsInRow(line, among: sorted, under: block)
            }
            if let index {
                blocks[index].append(line)
            } else {
                blocks.append([line])
            }
        }
        return blocks.map { lines in
            TextBlock(
                lines: lines,
                text: join(lines),
                boundingBox: lines.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
            )
        }
    }

    static func isNoise(_ line: RecognizedLine) -> Bool {
        line.confidence < noiseConfidence && line.text.letterCount < noiseMaxLetters
    }

    /// `line`이 `previous` 바로 다음 줄로 이어지는지 판단한다. 글자가 거의 없는 줄(버튼·숫자), 작성자·시각 줄, 펼치기 링크는
    /// 어떤 줄과도 잇지 않는다.
    static func continues(_ previous: RecognizedLine, with line: RecognizedLine) -> Bool {
        guard previous.text.hasWord, line.text.hasWord, !isByline(previous), !isByline(line),
            !isExpandLink(previous), !isExpandLink(line)
        else {
            return false
        }
        let above = previous.boundingBox
        let below = line.boundingBox
        let height = min(above.height, below.height)
        guard height > 0 else { return false }
        let gap = below.minY - above.maxY
        let overlapsHorizontally = below.minX < above.maxX && below.maxX > above.minX
        return gap >= -height * 0.5
            && gap <= height * maxLineGapRatio
            && max(above.height, below.height) / height <= maxHeightRatio
            && overlapsHorizontally
    }

    /// 작성자·시각 줄 앞에 올 수 있는 단어 수 (예: "@아이디", "u/name ·", "user commented")
    static let maxBylineWords = 3

    /// 댓글 머리줄처럼 작성자 옆에 상대 시각이 붙은 줄("@아이디 6년 전(수정됨)", "@user 2 days ago").
    /// 본문과 크기·간격이 비슷해 한 문단으로 이어졌고, 그러면 번역이 원문 문단 너비 안에서 다시 줄바꿈돼 날짜가 다음 줄로
    /// 밀렸다(TASK-043). 상대 시각 앞 단어가 적은 줄만 본다: 본문의 긴 줄이 "... 2 years ago"로 끝나는 경우는 잇는다.
    static func isByline(_ line: RecognizedLine) -> Bool {
        let relativeTime =
            #/(?:\d+\s*(?:초|분|시간|일|주|개월|달|년)\s*전|\d+\s+(?:second|minute|hour|day|week|month|year)s?\s+ago|\d+\s*(?:秒|分|分钟|時間|小时|日|天|週間|周|か月|ヶ月|カ月|个月|年)\s*前)\s*(?:[(（]\s*(?:수정됨|edited|編集済み|已编辑|已編輯)\s*[)）])?\s*$/#
            .ignoresCase()
        guard let match = line.text.firstMatch(of: relativeTime) else { return false }
        return line.text[..<match.range.lowerBound].split(whereSeparator: \.isWhitespace).count <= maxBylineWords
    }

    /// 잘린 글을 펼치거나 접는 링크 (공백을 빼고 소문자로 비교한다)
    static let expandLinks: Set<String> = [
        "자세히알아보기", "자세히보기", "더보기", "간략히", "간략히보기", "readmore", "showmore", "showless", "seemore", "seeless",
        "もっと見る", "続きを読む", "一部を表示", "簡易表示", "展开", "收起", "阅读更多", "显示更多", "显示较少", "閱讀更多", "顯示更多",
        "顯示較少",
    ]

    /// 펼치기·접기 링크만 있는 줄(유튜브 댓글의 "자세히 알아보기"). 잘린 본문 바로 아래에 같은 크기로 붙어 본문 문단에
    /// 이어졌다(TASK-044). 문장 안의 같은 말은 해당하지 않도록 줄 전체가 링크 표기일 때만 본다
    static func isExpandLink(_ line: RecognizedLine) -> Bool {
        let text = line.text.lowercased().filter { !$0.isWhitespace }
        let trimmed = text.reversed().drop { $0 == "." || $0 == "…" }.reversed()
        return expandLinks.contains(String(trimmed))
    }

    /// 같은 높이에 다른 글줄이 나란히 있고 그 글줄이 문단의 가로 범위 안에 있으면, `line`은 문단의 다음 줄이 아니라
    /// 링크·버튼이 나란히 놓인 줄이다 (예: 안내 문장 아래 "Show details  Get help"). 문단의 다음 줄 옆에는 다른 단의
    /// 글줄만 올 수 있고, 다른 단은 문단 가로 범위 밖에 있다.
    static func sitsInRow(_ line: RecognizedLine, among lines: [RecognizedLine], under block: [RecognizedLine]) -> Bool
    {
        let box = line.boundingBox
        let blockMinX = block.map(\.boundingBox.minX).min() ?? box.minX
        let blockMaxX = block.map(\.boundingBox.maxX).max() ?? box.maxX
        return lines.contains { other in
            let neighbor = other.boundingBox
            let overlap = min(neighbor.maxY, box.maxY) - max(neighbor.minY, box.minY)
            return other != line && other.text.letterCount >= minimumLetters
                && (neighbor.minX >= box.maxX || neighbor.maxX <= box.minX)
                && overlap >= min(neighbor.height, box.height) * 0.5
                && neighbor.minX < blockMaxX && neighbor.maxX > blockMinX
        }
    }

    /// 문단의 줄을 잇는다. 강제 줄바꿈은 `\n`으로, 자동 줄바꿈은 단어 사이를 띄우지 않는 문자(한자·가나 등) 경계에서는
    /// 공백 없이, 그 밖에는 공백 하나로 잇는다.
    static func join(_ lines: [RecognizedLine]) -> String {
        guard var text = lines.first?.text else { return "" }
        let right = lines.map(\.boundingBox.maxX).max() ?? 0
        for (previous, line) in zip(lines, lines.dropFirst()) {
            text += separator(between: previous, and: line, blockRight: right) + line.text
        }
        return text
    }

    static func separator(between previous: RecognizedLine, and next: RecognizedLine, blockRight: CGFloat) -> String {
        if endsEarly(previous, before: next, blockRight: blockRight) {
            return "\n"
        }
        guard let last = previous.text.unicodeScalars.last, let first = next.text.unicodeScalars.first else {
            return ""
        }
        return isWrittenWithoutSpaces(last) || isWrittenWithoutSpaces(first) ? "" : " "
    }

    /// 다음 줄의 첫 단어(CJK는 첫 글자)가 앞줄 뒤 남은 공간에 들어갔다면 자동 줄바꿈이 아니라 강제 줄바꿈이다.
    /// 글자 폭은 앞줄의 평균으로 어림한다.
    static func endsEarly(_ previous: RecognizedLine, before next: RecognizedLine, blockRight: CGFloat) -> Bool {
        let characterWidth = previous.boundingBox.width / CGFloat(max(previous.text.count, 1))
        let firstWordLength =
            next.text.unicodeScalars.first.map(isWrittenWithoutSpaces) == true
            ? 1 : next.text.prefix { !$0.isWhitespace }.count
        // 단어 앞 공백 한 칸 포함
        let needed = characterWidth * CGFloat(firstWordLength + 1)
        return previous.boundingBox.maxX + needed <= blockRight
    }

    /// CJK 문장부호, 히라가나, 가타카나, 한자, 전각·반각 형태. 한글은 띄어쓰기를 하므로 포함하지 않는다.
    static func isWrittenWithoutSpaces(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, 0x3040...0x309F, 0x30A0...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xFF00...0xFFEF:
            true
        default:
            false
        }
    }
}

extension StringProtocol {
    var letterCount: Int {
        reduce(0) { $1.isLetter ? $0 + 1 : $0 }
    }

    /// 글자가 `TextBlockGrouper.minimumLetters`개 이상인 단어(공백으로 나눈 조각)가 있는지. 아이콘을 글자로 잘못 읽은 좋아요 줄
    /// ("C 42만": 글자 "C"·"만"이 서로 다른 단어)은 없다(TASK-044). 띄어 쓰지 않는 한자·가나 줄은 한 단어다
    var hasWord: Bool {
        split(whereSeparator: \.isWhitespace).contains { $0.letterCount >= TextBlockGrouper.minimumLetters }
    }
}
