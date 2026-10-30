import Foundation

/// CLI 실행 파일을 찾는다. GUI 앱은 셸 PATH를 상속하지 않으므로 직접 찾아야 한다.
public enum CLILocator {
    public static let claudeKnownLocations = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    /// npm으로 설치하는 경우가 많아 Node 버전 관리자 위치도 본다
    public static let codexKnownLocations = [
        "~/.volta/bin/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "~/.local/bin/codex",
        "~/.npm-global/bin/codex",
    ]

    /// 사용자의 로그인 셸. 알 수 없으면 zsh.
    public static var loginShell: URL {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return URL(fileURLWithPath: "/bin/zsh")
        }
        return URL(fileURLWithPath: String(cString: shell))
    }

    /// 사용자 설정 경로 → 알려진 설치 위치 → 로그인 셸의 `command -v` 순서로 찾는다.
    ///
    /// 사용자 설정 경로가 있으면 그것만 확인한다. 잘못 설정된 경로를 다른 실행 파일로 몰래 대신하지 않기 위해서다.
    public static func locate(
        _ name: String,
        configuredPath: String? = nil,
        knownLocations: [String],
        shell: URL? = loginShell
    ) async -> URL? {
        if let configuredPath, !configuredPath.isEmpty {
            return executableURL(atPath: configuredPath)
        }
        for path in knownLocations {
            if let url = executableURL(atPath: path) {
                return url
            }
        }
        guard let shell, isSafeCommandName(name) else { return nil }
        return await lookUpInLoginShell(name, shell: shell)
    }

    static func executableURL(atPath path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    /// 셸 명령에 그대로 들어가므로 영숫자와 `._-`만 허용한다.
    static func isSafeCommandName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    private static func lookUpInLoginShell(_ name: String, shell: URL) async -> URL? {
        // PATH를 대화형 셸 설정(.zshrc 등)에서 추가하는 경우가 많아 로그인 + 대화형으로 실행한다.
        // 셸 설정이 출력하는 다른 문구는 건너뛰고 실행 가능한 절대 경로만 받는다
        guard
            let output = try? await ProcessExecutor.run(
                shell, arguments: ["-l", "-i", "-c", "command -v \(name)"], timeout: .seconds(5)),
            !output.timedOut
        else { return nil }
        let lines = String(decoding: output.stdout, as: UTF8.self).split(whereSeparator: \.isNewline)
        return lines.reversed().lazy
            .compactMap { executableURL(atPath: $0.trimmingCharacters(in: .whitespaces)) }
            .first
    }
}
