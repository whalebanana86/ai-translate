import Foundation
import Testing

@testable import TranslateCore

struct ProcessExecutorTests {
    @Test func capturesOutputAndExitStatus() async throws {
        let fake = try FakeExecutable("cat; echo oops >&2; exit 3")
        defer { fake.remove() }

        let output = try await ProcessExecutor.run(
            fake.url, arguments: [], input: Data("hello".utf8), timeout: .seconds(10))

        #expect(output.exitStatus == 3)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "hello")
        #expect(String(decoding: output.stderr, as: UTF8.self) == "oops\n")
        #expect(!output.timedOut)
    }

    @Test func passesArgumentsAndWorkingDirectory() async throws {
        let fake = try FakeExecutable(#"pwd -P; for arg in "$@"; do echo "[$arg]"; done"#)
        defer { fake.remove() }

        let output = try await ProcessExecutor.run(
            fake.url, arguments: ["--tools", "", "a b"], workingDirectory: fake.directory, timeout: .seconds(10))

        let lines = String(decoding: output.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(lines.first?.hasSuffix(fake.directory.lastPathComponent) == true)
        #expect(Array(lines.dropFirst()) == ["[--tools]", "[]", "[a b]"])
    }

    @Test func handlesInputAndOutputLargerThanPipeBuffer() async throws {
        let fake = try FakeExecutable("cat")
        defer { fake.remove() }
        let input = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)

        let output = try await ProcessExecutor.run(fake.url, arguments: [], input: input, timeout: .seconds(20))

        #expect(output.stdout == input)
    }

    @Test func survivesChildThatExitsWithoutReadingInput() async throws {
        let fake = try FakeExecutable("exit 0")
        defer { fake.remove() }
        let input = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)

        let output = try await ProcessExecutor.run(fake.url, arguments: [], input: input, timeout: .seconds(10))

        #expect(output.exitStatus == 0)
    }

    @Test func terminatesOnTimeout() async throws {
        let fake = try FakeExecutable("exec sleep 30")
        defer { fake.remove() }
        let clock = ContinuousClock()
        let start = clock.now

        let output = try await ProcessExecutor.run(fake.url, arguments: [], timeout: .milliseconds(300))

        #expect(output.timedOut)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func terminatesOnCancellation() async throws {
        let fake = try FakeExecutable("exec sleep 30")
        defer { fake.remove() }
        let clock = ContinuousClock()
        let start = clock.now
        let url = fake.url

        let task = Task { try await ProcessExecutor.run(url, arguments: [], timeout: .seconds(60)) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let output = try await task.value

        #expect(!output.timedOut)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func returnsWhenGrandchildKeepsPipeOpen() async throws {
        // 종료 신호가 닿지 않는 손자 프로세스가 stdout 파이프를 쥐고 있어 EOF가 오지 않는 경우.
        // Process.terminate()는 하위 프로세스에도 신호를 보내므로, setpgrp로 다른 프로세스 그룹에 띄워 재현한다.
        // 부하가 크면 setpgrp 전에 함께 종료돼 상황이 재현되지 않으므로, 그룹을 벗어난 뒤 남기는 ready 파일을
        // 확인하고 나서 취소한다. 수집 대기에 상한이 없다면 sleep이 끝나는 8초 뒤에야 반환된다
        let fake = try FakeExecutable(
            #"""
            perl -e 'setpgrp(0, 0); open(my $f, ">", $ARGV[0]); close($f); exec "sleep", "8"' "$(dirname "$0")/ready" &
            wait
            """#)
        defer { fake.remove() }
        let clock = ContinuousClock()
        let url = fake.url
        let task = Task { try await ProcessExecutor.run(url, arguments: [], timeout: .seconds(60)) }

        let readyDeadline = clock.now + .seconds(10)
        while !FileManager.default.fileExists(atPath: fake.file("ready").path) {
            try #require(clock.now < readyDeadline, "손자 프로세스가 10초 안에 시작되지 않음")
            try await Task.sleep(for: .milliseconds(20))
        }
        let cancelledAt = clock.now
        task.cancel()
        _ = try await task.value

        #expect(clock.now - cancelledAt < .seconds(5))
    }

    @Test func throwsWhenExecutableIsMissing() async {
        await #expect(throws: (any Error).self) {
            try await ProcessExecutor.run(
                URL(fileURLWithPath: "/nonexistent/claude"), arguments: [], timeout: .seconds(1))
        }
    }
}
