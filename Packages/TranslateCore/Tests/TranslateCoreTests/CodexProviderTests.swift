import Foundation
import Testing

@testable import TranslateCore

struct CodexProviderTests {
    private let request = TranslationRequest(target: "Korean", segments: ["Cancel anytime.", "Start free."])

    /// 인자에서 `--output-last-message`·`--cd` 값을 찾아 쓰는 가짜 codex. `$1` 이후는 그대로 기록한다
    private func fake(output: String?, exitStatus: Int = 0, stderr: String = "") throws -> FakeExecutable {
        let writeOutput = output.map { "printf '%s' '\($0)' > \"$OUT\"" } ?? ":"
        return try FakeExecutable(
            """
            DIR=$(dirname "$0")
            printf '%s\\n' "$@" > "$DIR/args.txt"
            OUT=""; WORK=""; PREV=""
            for ARG in "$@"; do
              [ "$PREV" = "--output-last-message" ] && OUT="$ARG"
              [ "$PREV" = "--cd" ] && WORK="$ARG"
              PREV="$ARG"
            done
            cat > "$DIR/stdin.txt"
            pwd -P > "$DIR/pwd.txt"
            ( cd "$WORK" && pwd -P > "$DIR/cd.txt" && ls -A | wc -l | tr -d ' ' > "$DIR/entries.txt" )
            \(writeOutput)
            printf '%s' '\(stderr)' >&2
            exit \(exitStatus)
            """, name: "codex")
    }

    @Test func argumentsUseReadOnlySandboxAndNoUserConfig() {
        let provider = CodexProvider(executable: URL(fileURLWithPath: "/bin/echo"))
        let arguments = provider.arguments(
            workingDirectory: URL(fileURLWithPath: "/tmp/work"), schema: URL(fileURLWithPath: "/tmp/io/schema.json"),
            output: URL(fileURLWithPath: "/tmp/io/output.json"))
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        #expect(arguments.first == "exec")
        #expect(arguments.last == "-")
        #expect(value(after: "--sandbox") == "read-only")
        #expect(value(after: "--cd") == "/tmp/work")
        #expect(value(after: "--output-schema") == "/tmp/io/schema.json")
        #expect(value(after: "--output-last-message") == "/tmp/io/output.json")
        for flag in ["--skip-git-repo-check", "--ephemeral", "--ignore-user-config"] {
            #expect(arguments.contains(flag))
        }
        let forbidden = [
            "workspace-write", "danger-full-access", "--full-auto", "--dangerously-bypass-approvals-and-sandbox",
            "--add-dir",
        ]
        #expect(arguments.allSatisfy { !forbidden.contains($0) })
    }

    @Test func sendsPromptOnStdinFromEmptyWorkingDirectoryAndReadsOutputFile() async throws {
        let fake = try fake(output: #"{"segments":["언제든지 해지할 수 있습니다.","무료로 시작하세요."]}"#)
        defer { fake.remove() }

        let result = try await CodexProvider(executable: fake.url).translate(request)

        #expect(result.segments == ["언제든지 해지할 수 있습니다.", "무료로 시작하세요."])
        #expect(try Data(contentsOf: fake.file("stdin.txt")) == CodexProvider.prompt(for: request))
        let workingDirectory = try fake.contents(of: "pwd.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try fake.contents(of: "cd.txt").trimmingCharacters(in: .whitespacesAndNewlines) == workingDirectory)
        #expect(try fake.contents(of: "entries.txt").trimmingCharacters(in: .whitespacesAndNewlines) == "0")
        #expect(
            URL(fileURLWithPath: workingDirectory).deletingLastPathComponent().lastPathComponent.hasPrefix(
                "AITranslate-"))
        #expect(!FileManager.default.fileExists(atPath: workingDirectory))
    }

    @Test(arguments: [
        ("Error: You have hit your usage limit. Upgrade or try again later.", TranslationEngineError.usageLimitReached),
        ("Error: Not logged in. Run `codex login` first.", TranslationEngineError.notLoggedIn),
    ])
    func classifiesErrorsFromEndOfStderr(message: String, expected: TranslationEngineError) async throws {
        // 오류 출력 앞부분은 입력 되풀이 (분류에 쓰지 않음)
        let echo = String(repeating: "page text ", count: 100)
        let fake = try fake(output: nil, exitStatus: 1, stderr: echo + message)
        defer { fake.remove() }

        await #expect(throws: expected) {
            try await CodexProvider(executable: fake.url).translate(request)
        }
    }

    @Test func throwsInvalidOutputWithoutOutputFile() async throws {
        let fake = try fake(output: nil)
        defer { fake.remove() }

        await #expect(throws: TranslationEngineError.invalidOutput) {
            try await CodexProvider(executable: fake.url).translate(request)
        }
    }

    @Test func rejectsSegmentCountMismatch() async throws {
        let fake = try fake(output: #"{"segments":["하나뿐"]}"#)
        defer { fake.remove() }

        await #expect(throws: TranslationPayloadError.segmentCountMismatch(expected: 2, actual: 1)) {
            try await CodexProvider(executable: fake.url).translate(request)
        }
    }

    @Test func throwsTimedOutWhenCLIHangs() async throws {
        let fake = try FakeExecutable("exec sleep 30", name: "codex")
        defer { fake.remove() }

        await #expect(throws: TranslationEngineError.timedOut) {
            try await CodexProvider(executable: fake.url, timeout: .milliseconds(300)).translate(request)
        }
    }
}
