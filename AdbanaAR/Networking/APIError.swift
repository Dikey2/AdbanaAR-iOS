import Foundation

/// Errores tipados de la API Adbana. Cada código HTTP relevante se maneja por separado.
enum APIError: Error, Equatable {
    case invalidRequest(String)
    case transport(String)
    case unauthorized(String)          // 401
    case forbidden(String)             // 403
    case notFound(String)              // 404
    case conflict(String)              // 409
    case validation(String, fields: [String: [String]]) // 422
    case rateLimited(retryAfter: Int?, String)          // 429
    case server(status: Int, String)   // 5xx
    case unexpectedStatus(Int, String)
    case decoding(String)

    /// Mensaje apto para mostrar al cliente (nunca incluye tokens ni cuerpos completos).
    var userMessage: String {
        switch self {
        case .invalidRequest(let m): return m
        case .transport: return "No se pudo conectar con el restaurante. Revisa tu conexión e inténtalo de nuevo."
        case .unauthorized: return "La sesión no es válida (401)."
        case .forbidden(let m): return m.isEmpty ? "No tienes permiso para esta acción (403)." : m
        case .notFound(let m): return m.isEmpty ? "No se encontró el recurso solicitado (404)." : m
        case .conflict(let m): return m.isEmpty ? "La operación entra en conflicto con un pedido anterior (409)." : m
        case .validation(let m, let fields):
            let detail = fields.sorted { $0.key < $1.key }.flatMap { $0.value }.joined(separator: "\n")
            return detail.isEmpty ? m : detail
        case .rateLimited(let retry, _):
            if let retry { return "Demasiadas solicitudes. Espera \(retry) s y vuelve a intentarlo (429)." }
            return "Demasiadas solicitudes. Espera un momento y vuelve a intentarlo (429)."
        case .server(let status, _): return "El servidor tuvo un problema (\(status)). Puedes reintentar."
        case .unexpectedStatus(let status, _): return "Respuesta inesperada del servidor (\(status))."
        case .decoding: return "La respuesta del servidor no tiene el formato esperado."
        }
    }

    /// Un pedido con este error puede reenviarse con la MISMA clave y el MISMO cuerpo.
    var isRetryableForSameIntent: Bool {
        switch self {
        case .transport, .rateLimited, .server, .decoding: return true
        default: return false
        }
    }

    var statusCode: Int? {
        switch self {
        case .unauthorized: return 401
        case .forbidden: return 403
        case .notFound: return 404
        case .conflict: return 409
        case .validation: return 422
        case .rateLimited: return 429
        case .server(let s, _), .unexpectedStatus(let s, _): return s
        default: return nil
        }
    }

    static func from(status: Int, data: Data, headers: [AnyHashable: Any]) -> APIError {
        let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)
        let message = body?.message ?? ""
        switch status {
        case 401: return .unauthorized(message)
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 409: return .conflict(message)
        case 422: return .validation(message, fields: body?.errors ?? [:])
        case 429:
            let raw = headers.first { ($0.key as? String)?.lowercased() == "retry-after" }?.value
            let retry = (raw as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? (raw as? Int)
            return .rateLimited(retryAfter: retry, message)
        case 500...599: return .server(status: status, message)
        default: return .unexpectedStatus(status, message)
        }
    }
}

struct APIErrorBody: Decodable {
    let message: String?
    let errors: [String: [String]]?

    private enum CodingKeys: String, CodingKey { case message, errors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        if let dict = try? c.decodeIfPresent([String: [String]].self, forKey: .errors) {
            errors = dict
        } else if let flat = try? c.decodeIfPresent([String: String].self, forKey: .errors) {
            errors = flat.mapValues { [$0] }
        } else {
            errors = nil
        }
    }
}
