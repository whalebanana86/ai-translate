import CoreGraphics

/// 화면 위에 뜬 메뉴·툴팁에 일부가 가려져 잘린 문단을 찾는다 (TASK-073).
///
/// 드롭다운 메뉴가 문단 일부를 덮으면 OCR은 보이는 조각만 읽는다("Search API for agents From $4 /1k requests" →
/// "Search AF From $4 /", "Talk to sales" → "Talk to si"). 조각을 새 문단으로 번역하면 엉뚱한 번역이 나오고("API 검색,
/// $4k 부터 시작", "s와 이야기해 보세요") 번역 글이 문단 너비만큼 그려져 메뉴 위로 넘쳤다. 조각은 번역하지 않고 원문 그대로
/// 두면, 메뉴가 닫힌 뒤 원래 문단이 번역 기억으로 바로 보인다.
///
/// 바로 전에 읽은 문단과 같은 자리에서 줄이 가로로 잘려 글이 짧아진 문단만 조각으로 본다. 글이 바뀐 문단, 줄바꿈만 바뀐 문단,
/// 말줄임("…")으로 줄인 줄은 조각이 아니다
public enum OccludedParagraphs {
    /// 잘린 줄 끝에서 비교하지 않는 글자 수. 반쯤 가려진 글자를 OCR이 다르게 읽는다("API" → "AF", "sales" → "si")
    static let garbledCharacters = 2
    /// 줄 끝이 같은 자리로 보는 차이와 잘렸다고 보는 폭 감소(줄 높이 배수)
    static let alignmentTolerance: CGFloat = 0.5
    /// 같은 줄로 보는 세로 겹침(두 줄 중 낮은 줄 높이 대비)
    static let minimumVerticalOverlap: CGFloat = 0.5

    /// `blocks` 중 `reference`의 어떤 문단이 가려져 잘린 조각인 것. 조각 문단 위치 → 원래 문단
    public static func find(in blocks: [TextBlock], reference: [TextBlock]) -> [Int: TextBlock] {
        var fragments: [Int: TextBlock] = [:]
        for (index, block) in blocks.enumerated() {
            let source = reference.first { source in
                guard source.boundingBox.intersects(block.boundingBox), block.text.count < source.text.count else {
                    return false
                }
                let matches = block.lines.map { line in source.lines.lazy.compactMap { match(line, in: $0) }.first }
                return matches.allSatisfy { $0 != nil } && matches.contains(.cut)
            }
            fragments[index] = source
        }
        // 가려진 문단이 여러 문단으로 나뉘어 읽혔으면(가려진 줄 위아래) 온전한 줄만 남은 문단도 그 문단의 일부다
        let occluded = sources(of: fragments)
        for (index, block) in blocks.enumerated() where fragments[index] == nil {
            fragments[index] = occluded.first { source in
                source.boundingBox.intersects(block.boundingBox)
                    && block.lines.allSatisfy { line in source.lines.contains { match(line, in: $0) == .whole } }
            }
        }
        return fragments
    }

    /// 조각을 뺀 문단과, 가려진 원래 문단. 원래 문단은 다음 인식의 참고 문단에 더해, 메뉴가 열린 채 다시 인식해도(메뉴 안 호버)
    /// 조각을 알아본다
    public static func removingFragments(
        from blocks: [TextBlock], reference: [TextBlock]
    ) -> (blocks: [TextBlock], occluded: [TextBlock]) {
        let fragments = find(in: blocks, reference: reference)
        return (blocks.indices.filter { fragments[$0] == nil }.map { blocks[$0] }, sources(of: fragments))
    }

    /// 조각들의 원래 문단(겹치지 않게), 조각 위치 순. 사전 순서로 모으면 읽을 때마다 순서가 바뀌었다 (TASK-079)
    static func sources(of fragments: [Int: TextBlock]) -> [TextBlock] {
        var sources: [TextBlock] = []
        for (_, source) in fragments.sorted(by: { $0.key < $1.key }) where !sources.contains(source) {
            sources.append(source)
        }
        return sources
    }

    enum LineMatch {
        /// 같은 줄
        case whole
        /// 같은 줄의 왼쪽이나 오른쪽이 가려졌다
        case cut
    }

    /// 새로 읽은 줄이 전에 읽은 줄과 같은 줄인지, 그 줄이 가려져 잘린 것인지
    static func match(_ line: RecognizedLine, in source: RecognizedLine) -> LineMatch? {
        let box = line.boundingBox
        let sourceBox = source.boundingBox
        let overlap = min(box.maxY, sourceBox.maxY) - max(box.minY, sourceBox.minY)
        guard overlap >= min(box.height, sourceBox.height) * minimumVerticalOverlap else { return nil }
        let tolerance = max(box.height, sourceBox.height) * alignmentTolerance
        let text = Array(line.text)
        let sourceText = Array(source.text)
        guard !text.isEmpty else { return nil }
        let sameStart = abs(box.minX - sourceBox.minX) <= tolerance
        let sameEnd = abs(box.maxX - sourceBox.maxX) <= tolerance
        if box.width >= sourceBox.width - tolerance {
            return sameStart && sameEnd && text == sourceText ? .whole : nil
        }
        guard text.count < sourceText.count, !line.text.hasSuffix("…"), !line.text.hasSuffix("...") else {
            return nil
        }
        let kept = text.count - garbledCharacters
        // 오른쪽이 가려지면 왼쪽 끝이 같고 앞부분 글이 같다. 왼쪽이 가려지면 반대
        if sameStart, commonPrefixLength(text, sourceText) >= kept {
            return .cut
        }
        if sameEnd, commonPrefixLength(text.reversed(), sourceText.reversed()) >= kept {
            return .cut
        }
        return nil
    }

    private static func commonPrefixLength(_ first: [Character], _ second: [Character]) -> Int {
        zip(first, second).prefix { $0 == $1 }.count
    }
}
