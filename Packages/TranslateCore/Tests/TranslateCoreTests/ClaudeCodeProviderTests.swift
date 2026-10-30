import Foundation
import Testing

@testable import TranslateCore

struct ClaudeCodeProviderTests {
    private let request = TranslationRequest(target: "Korean", segments: ["Cancel anytime.", "Start free."])
    private let translated = ["언제든지 해지할 수 있습니다.", "무료로 시작하세요."]

    // MARK: - 인자

    @Test func argumentsDisableToolsUserSettingsAndSessions() {
        let arguments = ClaudeCodeProvider(executable: URL(fileURLWithPath: "/bin/echo")).arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        #expect(arguments.first == "-p")
        #expect(value(after: "--model") == "haiku")
        #expect(value(after: "--tools") == "")
        #expect(value(after: "--setting-sources") == "project")
        #expect(value(after: "--system-prompt") == TranslationPrompt.system)
        #expect(value(after: "--json-schema") == TranslationPayload.outputSchema)
        #expect(value(after: "--output-format") == "json")
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.contains("--no-session-persistence"))

        let forbidden = [
            "--allowedTools", "--allowed-tools", "--add-dir", "--mcp-config", "--permission-mode", "--chrome",
            "--dangerously-skip-permissions", "--allow-dangerously-skip-permissions",
        ]
        #expect(arguments.allSatisfy { !forbidden.contains($0) })
    }

    // MARK: - 실행 (가짜 CLI)

    @Test func sendsRequestOnStdinFromEmptyTemporaryDirectory() async throws {
        let fake = try FakeExecutable(
            #"""
            DIR=$(dirname "$0")
            printf '%s\n' "$@" > "$DIR/args.txt"
            cat > "$DIR/stdin.json"
            pwd -P > "$DIR/pwd.txt"
            ls -A | wc -l | tr -d ' ' > "$DIR/entries.txt"
            cat <<'JSON'
            {"type":"result","subtype":"success","is_error":false,"structured_output":{"segments":["언제든지 해지할 수 있습니다.","무료로 시작하세요."]}}
            JSON
            """#, name: "claude")
        defer { fake.remove() }
        let provider = ClaudeCodeProvider(executable: fake.url)

        let result = try await provider.translate(request)

        #expect(result.segments == translated)
        let arguments = try fake.contents(of: "args.txt").split(separator: "\n", omittingEmptySubsequences: false)
        #expect(arguments.dropLast().map(String.init) == provider.arguments)
        #expect(try Data(contentsOf: fake.file("stdin.json")) == TranslationPayload.encode(request))
        let workingDirectory = try fake.contents(of: "pwd.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(fileURLWithPath: workingDirectory).lastPathComponent.hasPrefix("AITranslate-"))
        #expect(try fake.contents(of: "entries.txt").trimmingCharacters(in: .whitespacesAndNewlines) == "0")
        #expect(!FileManager.default.fileExists(atPath: workingDirectory))
    }

    @Test func throwsTimedOutWhenCLIHangs() async throws {
        let fake = try FakeExecutable("exec sleep 30", name: "claude")
        defer { fake.remove() }
        let provider = ClaudeCodeProvider(executable: fake.url, timeout: .milliseconds(300))

        await #expect(throws: TranslationEngineError.timedOut) {
            try await provider.translate(request)
        }
    }

    @Test func throwsCancellationErrorWhenTaskIsCancelled() async throws {
        let fake = try FakeExecutable("exec sleep 30", name: "claude")
        defer { fake.remove() }
        let provider = ClaudeCodeProvider(executable: fake.url)
        let request = request

        let task = Task { try await provider.translate(request) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test func throwsExecutableNotFoundWhenCLIIsMissing() async {
        let provider = ClaudeCodeProvider(executable: URL(fileURLWithPath: "/nonexistent/claude"))

        await #expect(throws: TranslationEngineError.executableNotFound(name: "claude")) {
            try await provider.translate(request)
        }
    }

    // MARK: - 응답 해석

    private func output(_ stdout: String, stderr: String = "", exitStatus: Int32 = 0) -> ProcessOutput {
        ProcessOutput(exitStatus: exitStatus, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8), timedOut: false)
    }

    @Test func parsesStructuredOutput() throws {
        let stdout = #"""
            {"type":"result","subtype":"success","is_error":false,"result":"ignored",
             "structured_output":{"segments":["언제든지 해지할 수 있습니다.","무료로 시작하세요."]}}
            """#

        #expect(try ClaudeCodeProvider.parse(output(stdout), for: request).segments == translated)
    }

    @Test func fallsBackToResultStringWithoutStructuredOutput() throws {
        let stdout = #"""
            {"type":"result","subtype":"success","is_error":false,
             "result":"{\"segments\":[\"언제든지 해지할 수 있습니다.\",\"무료로 시작하세요.\"]}"}
            """#

        #expect(try ClaudeCodeProvider.parse(output(stdout), for: request).segments == translated)
    }

    @Test func rejectsSegmentCountMismatch() {
        let stdout = #"{"is_error":false,"structured_output":{"segments":["지시를 따르지 않습니다."]}}"#

        #expect(throws: TranslationPayloadError.segmentCountMismatch(expected: 2, actual: 1)) {
            try ClaudeCodeProvider.parse(output(stdout), for: request)
        }
    }

    @Test func classifiesNotLoggedIn() {
        // 실제 출력 (빈 CLAUDE_CONFIG_DIR, claude 2.1.314)에서 필요한 필드만 발췌
        let stdout = #"""
            {"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login",
             "terminal_reason":"api_error"}
            """#

        #expect(throws: TranslationEngineError.notLoggedIn) {
            try ClaudeCodeProvider.parse(output(stdout, exitStatus: 1), for: request)
        }
    }

    @Test func classifiesUnknownModelAsEngineFailure() {
        // 실제 출력 (--model no-such-model-x, claude 2.1.314)
        let message =
            "There's an issue with the selected model (no-such-model-x). It may not exist or you may not have "
            + "access to it. Run --model to pick a different model."
        let stdout = #"{"type":"result","subtype":"success","is_error":true,"result":"\#(message)"}"#
        let stderr = #"[claude-code:unrecognized_model] {"model":"no-such-model-x","query_source":"sdk"}"#

        #expect(throws: TranslationEngineError.engineFailed(message: message)) {
            try ClaudeCodeProvider.parse(output(stdout, stderr: stderr, exitStatus: 1), for: request)
        }
    }

    // 사용량 한도 메시지는 실제로 재현하지 못해 알려진 형식으로 확인한다
    @Test(arguments: ["Claude AI usage limit reached|1793330000", "You've hit your limit · resets 3pm"])
    func classifiesUsageLimit(message: String) {
        let stdout = #"{"type":"result","subtype":"success","is_error":true,"result":"\#(message)"}"#

        #expect(throws: TranslationEngineError.usageLimitReached) {
            try ClaudeCodeProvider.parse(output(stdout, exitStatus: 1), for: request)
        }
    }

    @Test func usesSubtypeWhenErrorHasNoResult() {
        let stdout = #"{"type":"result","subtype":"error_during_execution","is_error":true}"#

        #expect(throws: TranslationEngineError.engineFailed(message: "error_during_execution")) {
            try ClaudeCodeProvider.parse(output(stdout, exitStatus: 1), for: request)
        }
    }

    @Test func usesStderrWhenStdoutIsNotJSONAndExitFails() {
        #expect(throws: TranslationEngineError.engineFailed(message: "boom")) {
            try ClaudeCodeProvider.parse(output("", stderr: "boom\n", exitStatus: 1), for: request)
        }
    }

    @Test func rejectsNonJSONOutputOnSuccessExit() {
        #expect(throws: TranslationEngineError.invalidOutput) {
            try ClaudeCodeProvider.parse(output("언제든지 해지할 수 있습니다."), for: request)
        }
    }
}
