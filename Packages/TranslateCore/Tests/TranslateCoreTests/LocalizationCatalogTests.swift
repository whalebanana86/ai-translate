import Foundation
import Testing

@testable import TranslateCore

/// 화면 글 카탈로그(TASK-058): 모든 글에 영어 번역이 있고, 형식 자리(%@ 등)가 원문과 같고, TranslateCore 화면 글이 모두 카탈로그에 있다.
/// 새 화면 글은 빌드 뒤 `scripts/sync-strings.sh`로 카탈로그에 더하고 영어를 채운다
struct LocalizationCatalogTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    var state: String
                    var value: String
                }
                var stringUnit: StringUnit?
            }
            var shouldTranslate: Bool?
            var extractionState: String?
            var localizations: [String: Localization]?
        }
        var sourceLanguage: String
        var strings: [String: Entry]
    }

    private static let packageRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let coreCatalog = packageRoot.appending(
        path: "Sources/TranslateCore/Resources/Localizable.xcstrings")
    /// 앱 타깃(App/)의 카탈로그. 앱 타깃에는 테스트가 없어 여기서 함께 본다
    private static let appCatalog = packageRoot.appending(path: "../../App/Localizable.xcstrings")

    private func load(_ url: URL) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// 형식 자리 종류를 차례로 (위치 지정 `%1$@`도 같은 종류로 본다)
    private func placeholders(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(@|lld|ld|d|f|%)/).map { String($0.output.1) }
    }

    @Test(arguments: [coreCatalog, appCatalog])
    func everyStringHasEnglish(_ url: URL) throws {
        let catalog = try load(url)
        #expect(catalog.sourceLanguage == "ko")
        #expect(!catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            #expect(entry.extractionState != "stale", "코드에서 쓰지 않는 글: \(key)")
            if entry.shouldTranslate == false { continue }
            let english = entry.localizations?["en"]?.stringUnit
            #expect(english?.state == "translated", "영어 번역 없음: \(key)")
            guard let value = english?.value else { continue }
            #expect(!value.isEmpty && value != key, "영어 번역이 원문 그대로: \(key)")
            #expect(placeholders(value).sorted() == placeholders(key).sorted(), "형식 자리가 다름: \(key)")
        }
    }

    /// TranslateCore가 화면에 내놓는 글. 테스트(swift test)에서는 카탈로그를 컴파일하지 않아 한국어 원문이 나온다
    private var coreUserFacingStrings: [String] {
        let engineErrors: [TranslationEngineError] = [
            .executableNotFound(name: "claude"), .timedOut, .notLoggedIn, .usageLimitReached,
            .engineFailed(message: "boom"), .invalidOutput,
        ]
        let errors: [any LocalizedError] =
            engineErrors + [
                LocalEngineError.modelNotInstalled, LocalEngineError.unsupportedMac,
                ModelDownloadError.badStatus(file: "model.safetensors", status: 404),
                ModelDownloadError.sizeMismatch(file: "model.safetensors"),
                TranslationPayloadError.segmentCountMismatch(expected: 2, actual: 1),
            ]
        return errors.compactMap(\.errorDescription)
            + TranslationEngine.allCases.flatMap { [$0.summary] + [$0.transmissionDestination].compactMap { $0 } }
            + [TranslationEngine.local.displayName]
            + ClaudeCodeProvider.models.map(\.summary)
    }

    @Test func coreUserFacingStringsAreInCatalog() throws {
        let keys = try load(Self.coreCatalog).strings.keys.map { key in
            // 형식 자리는 어떤 글이든 맞게 본다
            let pattern = NSRegularExpression.escapedPattern(for: key)
                .replacingOccurrences(of: "%@", with: ".+").replacingOccurrences(of: "%lld", with: "-?\\d+")
            return try Regex("^" + pattern + "$")
        }
        for text in coreUserFacingStrings {
            #expect(keys.contains { text.wholeMatch(of: $0) != nil }, "카탈로그에 없는 글: \(text)")
        }
    }
}
