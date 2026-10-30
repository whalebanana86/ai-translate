import Foundation

/// Codex CLI(`codex exec`)로 번역하는 엔진.
///
/// Codex는 도구를 완전히 끌 수 없으므로 읽기 전용 샌드박스에서, 사용자 설정을 읽지 않고, 세션을 남기지 않고,
/// 요청마다 빈 임시 폴더에서 실행한다 (AGENTS.md 4장). 출력은 스키마로 강제하고 마지막 메시지를 파일로 받는다.
public struct CodexProvider: TranslationProvider {
    /// Codex는 요청마다 7~9초 걸린다 (2026-10-30 측정)
    public static let defaultTimeout: Duration = .seconds(90)

    public var executable: URL
    public var timeout: Duration

    public init(executable: URL, timeout: Duration = defaultTimeout) {
        self.executable = executable
        self.timeout = timeout
    }

    /// CLI를 찾아 엔진을 만든다. 찾지 못하면 `TranslationEngineError.executableNotFound`.
    public static func locate(configuredPath: String? = nil, timeout: Duration = defaultTimeout) async throws
        -> CodexProvider
    {
        guard
            let executable = await CLILocator.locate(
                "codex", configuredPath: configuredPath, knownLocations: CLILocator.codexKnownLocations)
        else { throw TranslationEngineError.executableNotFound(name: "codex") }
        return CodexProvider(executable: executable, timeout: timeout)
    }

    func arguments(workingDirectory: URL, schema: URL, output: URL) -> [String] {
        [
            "exec",
            "--skip-git-repo-check",
            "--ephemeral",
            "--ignore-user-config",
            "--sandbox", "read-only",
            "--cd", workingDirectory.path,
            "--config", "model_reasoning_effort=\"low\"",
            "--output-schema", schema.path,
            "--output-last-message", output.path,
            "-",
        ]
    }

    /// 표준 입력으로 보내는 프롬프트: 번역 지시 + JSON 세그먼트 (Codex에는 시스템 프롬프트 옵션이 없다)
    static func prompt(for request: TranslationRequest) throws -> Data {
        Data((TranslationPrompt.system + "\n\n").utf8) + (try TranslationPayload.encode(request))
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("AITranslate-\(UUID().uuidString)", isDirectory: true)
        // 작업 폴더는 비워 두고, 스키마·출력 파일은 옆 폴더에 둔다
        let workingDirectory = base.appendingPathComponent("work", isDirectory: true)
        let files = base.appendingPathComponent("io", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let schema = files.appendingPathComponent("schema.json")
        let output = files.appendingPathComponent("output.json")
        try Data(TranslationPayload.outputSchema.utf8).write(to: schema)

        let result: ProcessOutput
        do {
            result = try await ProcessExecutor.run(
                executable, arguments: arguments(workingDirectory: workingDirectory, schema: schema, output: output),
                input: try Self.prompt(for: request), workingDirectory: workingDirectory, timeout: timeout)
        } catch {
            throw TranslationEngineError.executableNotFound(name: "codex")
        }
        try Task.checkCancellation()
        if result.timedOut {
            throw TranslationEngineError.timedOut
        }
        if result.exitStatus != 0 {
            // 오류 출력 앞부분에는 입력(페이지 글)이 되풀이되므로 끝부분만 본다
            throw TranslationEngineError.classify(String(String(decoding: result.stderr, as: UTF8.self).suffix(600)))
        }
        guard let data = try? Data(contentsOf: output) else { throw TranslationEngineError.invalidOutput }
        do {
            return try TranslationPayload.decodeResult(data, for: request)
        } catch let error as TranslationPayloadError {
            throw error
        } catch {
            throw TranslationEngineError.invalidOutput
        }
    }
}
