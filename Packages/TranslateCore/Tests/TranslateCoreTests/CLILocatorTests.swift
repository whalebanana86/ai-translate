import Foundation
import Testing

@testable import TranslateCore

struct CLILocatorTests {
    @Test func usesConfiguredPathOnly() async throws {
        let configured = try FakeExecutable("exit 0", name: "claude")
        defer { configured.remove() }
        let known = try FakeExecutable("exit 0", name: "claude")
        defer { known.remove() }

        let found = await CLILocator.locate(
            "claude", configuredPath: configured.url.path, knownLocations: [known.url.path], shell: nil)
        let wrongConfig = await CLILocator.locate(
            "claude", configuredPath: "/nonexistent/claude", knownLocations: [known.url.path], shell: nil)

        #expect(found?.path == configured.url.path)
        #expect(wrongConfig == nil)
    }

    @Test func returnsFirstExecutableKnownLocation() async throws {
        let fake = try FakeExecutable("exit 0", name: "claude")
        defer { fake.remove() }
        let notExecutable = fake.file("plain")
        try "x".write(to: notExecutable, atomically: true, encoding: .utf8)

        let found = await CLILocator.locate(
            "claude", knownLocations: ["/nonexistent/claude", notExecutable.path, fake.url.path], shell: nil)

        #expect(found?.path == fake.url.path)
    }

    @Test func fallsBackToLoginShell() async throws {
        let target = try FakeExecutable("exit 0", name: "claude")
        defer { target.remove() }
        let shell = try FakeExecutable(
            #"""
            printf '%s\n' "$@" > "$(dirname "$0")/shell-args.txt"
            echo "Welcome banner"
            echo "\#(target.url.path)"
            """#, name: "shell")
        defer { shell.remove() }

        let found = await CLILocator.locate("claude", knownLocations: [], shell: shell.url)

        #expect(found?.path == target.url.path)
        #expect(try shell.contents(of: "shell-args.txt") == "-l\n-i\n-c\ncommand -v claude\n")
    }

    @Test func ignoresShellOutputThatIsNotAnExecutablePath() async throws {
        let shell = try FakeExecutable("echo 'claude: aliased to npx claude'; echo /nonexistent/claude", name: "shell")
        defer { shell.remove() }

        #expect(await CLILocator.locate("claude", knownLocations: [], shell: shell.url) == nil)
    }

    @Test func refusesUnsafeNameWithoutRunningShell() async throws {
        let shell = try FakeExecutable(#"touch "$(dirname "$0")/ran""#, name: "shell")
        defer { shell.remove() }

        let found = await CLILocator.locate("claude$(id)", knownLocations: [], shell: shell.url)

        #expect(found == nil)
        #expect(!FileManager.default.fileExists(atPath: shell.file("ran").path))
    }
}
