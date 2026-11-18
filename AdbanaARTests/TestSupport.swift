import Foundation
@testable import AdbanaAR

/// Intercepta peticiones HTTP para probar APIClient sin red.
final class MockURLProtocol: URLProtocol {
    struct Stub { let status: Int; let body: Data; var headers: [String: String] = [:] }
    nonisolated(unsafe) static var handler: ((URLRequest) -> Stub)?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var failWithError: URLError?

    static func reset() { handler = nil; requests = []; bodies = []; failWithError = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(request))
        if let err = Self.failWithError {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let stub = Self.handler?(request) ?? Stub(status: 200, body: Data("{}".utf8))
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(_ r: URLRequest) -> Data {
        if let b = r.httpBody { return b }
        guard let s = r.httpBodyStream else { return Data() }
        s.open(); defer { s.close() }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: c)
    }
}

enum Fixture {
    static func data(_ name: String) -> Data {
        let bundle = Bundle(for: MockURLProtocol.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            fatalError("Falta fixture \(name).json")
        }
        return try! Data(contentsOf: url)
    }
}
