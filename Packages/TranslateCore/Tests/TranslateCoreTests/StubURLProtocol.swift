import Foundation
import Synchronization

/// 테스트용 가짜 서버. URL마다 상태 코드와 본문을 등록해 두면 그대로 돌려준다.
/// 테스트가 동시에 돌므로 테스트마다 다른 저장소 이름(URL)을 쓴다.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let routes = Mutex<[URL: (status: Int, body: Data)]>([:])

    static func register(_ url: URL, status: Int = 200, body: Data) {
        routes.withLock { $0[url] = (status, body) }
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let route = Self.routes.withLock { $0[url] } ?? (status: 404, body: Data("not found".utf8))
        let response = HTTPURLResponse(
            url: url, statusCode: route.status, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Length": String(route.body.count)
            ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: route.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
