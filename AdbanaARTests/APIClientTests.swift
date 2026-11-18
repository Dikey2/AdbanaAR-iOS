import XCTest
@testable import AdbanaAR

final class APIClientTests: XCTestCase {
    var api: APIClient!

    override func setUp() {
        MockURLProtocol.reset()
        api = APIClient(baseURL: URL(string: "http://localhost:8080")!, session: MockURLProtocol.session())
    }

    func testConstruyeRutaYCabeceras() throws {
        let req = try api.request(for: Endpoints.carta(slug: "mi-resto", mesaCodigo: "D9428888-122B-4A77-9C09-CBC6D2CB3A01"))
        XCTAssertEqual(req.url?.absoluteString, "http://localhost:8080/api/carta/mi-resto?mesa=d9428888-122b-4a77-9c09-cbc6d2cb3a01")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "La carta pública no envía credenciales")
    }

    func testMesaNoUUIDSeIgnora() throws {
        let req = try api.request(for: Endpoints.carta(slug: "x", mesaCodigo: "4"))
        XCTAssertNil(req.url?.query)
    }

    func testTokenConMasSeCodifica() throws {
        let req = try api.request(for: Endpoints.seguimiento(slug: "x", token: "ab+c/d=="))
        XCTAssertTrue(req.url!.absoluteString.contains("token=ab%2Bc/d%3D%3D") || req.url!.absoluteString.contains("token=ab%2Bc/d=="))
        XCTAssertFalse(req.url!.absoluteString.contains("+"))
    }

    func testMapeoDeErrores() async {
        let casos: [(Int, String, [String: String])] = [
            (401, #"{"message":"Unauthenticated."}"#, [:]),
            (403, #"{"message":"No"}"#, [:]),
            (404, #"{"message":""}"#, [:]),
            (409, String(data: Fixture.data("pedido_409"), encoding: .utf8)!, [:]),
            (422, String(data: Fixture.data("pedido_422"), encoding: .utf8)!, [:]),
            (429, #"{"message":"Too Many Attempts."}"#, ["Retry-After": "42"]),
            (500, #"{"message":"Server Error"}"#, [:]),
        ]
        for (status, body, headers) in casos {
            MockURLProtocol.handler = { _ in .init(status: status, body: Data(body.utf8), headers: headers) }
            do {
                let _: CartaResponse = try await api.send(Endpoints.carta(slug: "x"))
                XCTFail("debió fallar \(status)")
            } catch let e as APIError {
                XCTAssertEqual(e.statusCode, status)
                switch (status, e) {
                case (401, .unauthorized), (403, .forbidden), (404, .notFound), (409, .conflict), (500, .server): break
                case (422, .validation(_, let fields)):
                    XCTAssertNotNil(fields["direccion"]); XCTAssertNotNil(fields["cliente_telefono"])
                case (429, .rateLimited(let retry, _)):
                    XCTAssertEqual(retry, 42)
                default: XCTFail("mapeo incorrecto para \(status): \(e)")
                }
            } catch { XCTFail("\(error)") }
        }
    }

    func testReintentablesSoloTransporte429Y5xx() {
        XCTAssertTrue(APIError.transport("x").isRetryableForSameIntent)
        XCTAssertTrue(APIError.rateLimited(retryAfter: nil, "").isRetryableForSameIntent)
        XCTAssertTrue(APIError.server(status: 503, "").isRetryableForSameIntent)
        XCTAssertFalse(APIError.validation("", fields: [:]).isRetryableForSameIntent)
        XCTAssertFalse(APIError.conflict("").isRetryableForSameIntent)
        XCTAssertFalse(APIError.notFound("").isRetryableForSameIntent)
    }

    func testAbsoluteURLRechazaHttpRemoto() {
        XCTAssertEqual(api.absoluteURL("/fotos-platos/a.jpg")?.absoluteString, "http://localhost:8080/fotos-platos/a.jpg")
        XCTAssertNotNil(api.absoluteURL("https://cdn.example.com/a.usdz"))
        XCTAssertNil(api.absoluteURL("http://evil.example.com/a.usdz"))
        XCTAssertNil(api.absoluteURL("//evil.example.com/a"))
        XCTAssertNil(api.absoluteURL(nil))
    }
}

final class AppConfigTests: XCTestCase {
    func testValidaHTTPS() {
        XCTAssertEqual(try AppConfig.validate("https://adbana.example.com/api/").get().absoluteString, "https://adbana.example.com")
        XCTAssertEqual(try AppConfig.validate("http://192.168.1.50:8080").get().port, 8080)
        XCTAssertNoThrow(try AppConfig.validate("http://localhost:8080").get())
        XCTAssertEqual(AppConfig.validate("http://adbana.example.com"), .failure(.insecureRemoteURL))
        XCTAssertEqual(AppConfig.validate("ftp://x"), .failure(.invalidURL))
        XCTAssertEqual(AppConfig.validate("no es url"), .failure(.invalidURL))
    }

    func testHostsLocales() {
        XCTAssertTrue(AppConfig.isLocalHost("10.0.0.5"))
        XCTAssertTrue(AppConfig.isLocalHost("172.20.1.1"))
        XCTAssertFalse(AppConfig.isLocalHost("172.32.1.1"))
        XCTAssertTrue(AppConfig.isLocalHost("mac-de-alexis.local"))
        XCTAssertFalse(AppConfig.isLocalHost("8.8.8.8"))
    }
}
