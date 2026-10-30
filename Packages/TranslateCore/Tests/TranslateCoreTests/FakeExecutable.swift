import Foundation

/// 테스트용 가짜 실행 파일. 임시 폴더에 셸 스크립트를 만든다. 스크립트 안에서는 `$(dirname "$0")`로 그 폴더를 쓴다.
struct FakeExecutable {
    let directory: URL
    let url: URL

    init(_ script: String, name: String = "fake") throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeExecutable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        try ("#!/bin/sh\n" + script + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func contents(of name: String) throws -> String {
        try String(contentsOf: file(name), encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
