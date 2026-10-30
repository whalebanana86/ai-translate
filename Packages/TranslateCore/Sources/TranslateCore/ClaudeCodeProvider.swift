import Foundation

/// Claude Code CLI(`claude -p`)로 번역하는 엔진.
///
/// 캡처한 텍스트는 신뢰할 수 없는 입력이므로 도구를 모두 끄고, 사용자 설정(훅·플러그인)·MCP·세션 기록을 쓰지 않고,
/// 요청마다 빈 임시 폴더에서 실행한다 (AGENTS.md 4장).
public struct ClaudeCodeProvider: TranslationProvider {
    public static let defaultModel = "haiku"
    public static let defaultTimeout: Duration = .seconds(60)

    public var executable: URL
    public var model: String
    public var timeout: Duration

    /// 요청마다 약 3초 고정 비용이 있지만, 8~28문단을 한 번에 보내면 7~21초 뒤에야 보인다 (TASK-019).
    /// 새 화면은 위쪽 3문단을 먼저 보내 첫 번역을 빨리 보여준다
    public var firstBatchSize: Int? { 3 }

    public init(executable: URL, model: String = defaultModel, timeout: Duration = defaultTimeout) {
        self.executable = executable
        self.model = model
        self.timeout = timeout
    }

    /// CLI를 찾아 엔진을 만든다. 찾지 못하면 `TranslationEngineError.executableNotFound`.
    public static func locate(
        configuredPath: String? = nil,
        model: String = defaultModel,
        timeout: Duration = defaultTimeout
    ) async throws -> ClaudeCodeProvider {
        guard
            let executable = await CLILocator.locate(
                "claude", configuredPath: configuredPath, knownLocations: CLILocator.claudeKnownLocations)
        else { throw TranslationEngineError.executableNotFound(name: "claude") }
        return ClaudeCodeProvider(executable: executable, model: model, timeout: timeout)
    }

    var arguments: [String] {
        [
            "-p",
            "--model", model,
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "project",
            "--no-session-persistence",
            "--system-prompt", TranslationPrompt.system,
            "--json-schema", TranslationPayload.outputSchema,
            "--output-format", "json",
        ]
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let input = try TranslationPayload.encode(request)
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AITranslate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let output: ProcessOutput
        do {
            output = try await ProcessExecutor.run(
                executable, arguments: arguments, input: input, workingDirectory: workingDirectory, timeout: timeout)
        } catch {
            throw TranslationEngineError.executableNotFound(name: "claude")
        }
        try Task.checkCancellation()
        if output.timedOut {
            throw TranslationEngineError.timedOut
        }
        return try Self.parse(output, for: request)
    }

    /// `--output-format json` 응답을 해석한다.
    static func parse(_ output: ProcessOutput, for request: TranslationRequest) throws -> TranslationResult {
        let stderr = String(decoding: output.stderr, as: UTF8.self)
        guard let response = try? JSONDecoder().decode(Response.self, from: output.stdout) else {
            if output.exitStatus != 0 {
                throw TranslationEngineError.classify(stderr)
            }
            throw TranslationEngineError.invalidOutput
        }
        if response.isError || output.exitStatus != 0 {
            let message = [response.result, response.subtype, stderr].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            throw TranslationEngineError.classify(message)
        }
        if let structured = response.structuredOutput {
            return try TranslationPayload.validate(structured, for: request)
        }
        guard let result = response.result else { throw TranslationEngineError.invalidOutput }
        do {
            return try TranslationPayload.decodeResult(Data(result.utf8), for: request)
        } catch let error as TranslationPayloadError {
            throw error
        } catch {
            throw TranslationEngineError.invalidOutput
        }
    }

    private struct Response: Decodable {
        var isError: Bool
        var subtype: String?
        var result: String?
        var structuredOutput: TranslationResult?

        enum CodingKeys: String, CodingKey {
            case isError = "is_error"
            case subtype
            case result
            case structuredOutput = "structured_output"
        }
    }
}
