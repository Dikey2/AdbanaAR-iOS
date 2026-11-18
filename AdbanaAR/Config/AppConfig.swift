import Foundation

/// Configuración de entorno. La URL base viene de Info.plist (definida en Configs/*.xcconfig)
/// y puede sobrescribirse desde Preferencias (SwiftData) para pruebas en iPhone físico.
enum AppConfig {
    enum ConfigError: Error, Equatable, LocalizedError {
        case invalidURL
        case insecureRemoteURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "La URL no es válida. Usa el formato https://dominio o http://IP-local:8080."
            case .insecureRemoteURL: return "Por seguridad, los servidores remotos deben usar HTTPS."
            }
        }
    }

    static let fallbackBaseURL = URL(string: "http://localhost:8080")!

    /// URL base declarada en el bundle (`AdbanaAPIBaseURL`).
    static func bundleBaseURL(_ bundle: Bundle = .main) -> URL {
        guard let raw = bundle.object(forInfoDictionaryKey: "AdbanaAPIBaseURL") as? String,
              case let .success(url) = validate(raw) else {
            return fallbackBaseURL
        }
        return url
    }

    static var environmentName: String {
        (Bundle.main.object(forInfoDictionaryKey: "AdbanaEnvironment") as? String) ?? "desarrollo"
    }

    /// Valida la URL base: HTTPS obligatorio salvo hosts de red local (simulador o Docker en la LAN).
    static func validate(_ raw: String) -> Result<URL, ConfigError> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/api") { text.removeLast(4) }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty,
              scheme == "https" || scheme == "http" else {
            return .failure(.invalidURL)
        }
        if scheme == "http" && !isLocalHost(host) {
            return .failure(.insecureRemoteURL)
        }
        return .success(url)
    }

    static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local") { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _): return true
        case (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}
