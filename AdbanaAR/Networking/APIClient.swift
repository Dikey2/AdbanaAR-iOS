import Foundation
import os

/// Petición HTTP relativa a `{baseURL}/api/`.
struct Endpoint: Sendable {
    enum Method: String, Sendable { case get = "GET", post = "POST" }
    let method: Method
    let path: String
    var query: [URLQueryItem] = []
    var body: Data? = nil
    /// Ruta sin parámetros para logs (las queries pueden contener tokens).
    var logLabel: String { "\(method.rawValue) /api/\(path)" }
}

/// Rutas públicas de la API Adbana usadas por la app. Ninguna requiere credenciales de personal.
enum Endpoints {
    static let slugPattern = /^[a-z0-9][a-z0-9-]{0,99}$/

    static func isValidSlug(_ slug: String) -> Bool { slug.wholeMatch(of: slugPattern) != nil }

    static func carta(slug: String, mesaCodigo: String? = nil) -> Endpoint {
        var e = Endpoint(method: .get, path: "carta/\(slug)")
        if let mesaCodigo, UUID(uuidString: mesaCodigo) != nil {
            e.query = [URLQueryItem(name: "mesa", value: mesaCodigo.lowercased())]
        }
        return e
    }

    static func crearPedido(slug: String, body: Data) -> Endpoint {
        Endpoint(method: .post, path: "carta/\(slug)/pedidos", body: body)
    }

    static func seguimiento(slug: String, token: String) -> Endpoint {
        Endpoint(method: .get, path: "carta/\(slug)/seguimiento", query: [URLQueryItem(name: "token", value: token)])
    }

    static func restaurantes(q: String?) -> Endpoint {
        var e = Endpoint(method: .get, path: "restaurantes")
        if let q, !q.isEmpty { e.query = [URLQueryItem(name: "q", value: String(q.prefix(100)))] }
        return e
    }
}

/// Cliente REST tipado. URL base configurable; nunca registra tokens ni cuerpos.
final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "pe.edu.tecsup.adbana.ar", category: "api")

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    func request(for endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest("URL base inválida.")
        }
        let encodedPath = endpoint.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String($0) }
            .joined(separator: "/")
        components.percentEncodedPath = components.percentEncodedPath + "/" + encodedPath
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        // `+` en tokens: se codifica explícitamente para que el servidor no lo lea como espacio.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw APIError.invalidRequest("URL inválida.") }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("es", forHTTPHeaderField: "Accept-Language")
        if let body = endpoint.body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await raw(endpoint)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("\(endpoint.logLabel, privacy: .public) decoding error")
            throw APIError.decoding(String(describing: type))
        }
    }

    func raw(_ endpoint: Endpoint) async throws -> (Data, HTTPURLResponse) {
        let req = try request(for: endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            logger.error("\(endpoint.logLabel, privacy: .public) transport error")
            throw APIError.transport((error as? URLError)?.code.rawValue.description ?? "desconocido")
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("sin respuesta HTTP") }
        logger.info("\(endpoint.logLabel, privacy: .public) -> \(http.statusCode)")
        guard (200...299).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, data: data, headers: http.allHeaderFields)
        }
        return (data, http)
    }

    /// Resuelve rutas relativas del backend (`/api/...`, `/fotos-platos/...`) contra la URL base.
    /// Rechaza http remoto para respetar HTTPS fuera de la red local.
    func absoluteURL(_ pathOrURL: String?) -> URL? {
        guard let s = pathOrURL, !s.isEmpty else { return nil }
        if s.hasPrefix("/") && !s.hasPrefix("//") {
            return URL(string: s, relativeTo: baseURL)?.absoluteURL
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", let host = url.host, AppConfig.isLocalHost(host) { return url }
        return nil
    }
}
