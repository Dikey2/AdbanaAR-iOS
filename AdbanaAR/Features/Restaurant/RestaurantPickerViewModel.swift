import Foundation
import Observation

@MainActor
@Observable
final class RestaurantPickerViewModel {
    enum LoadState: Equatable { case idle, loading, failed(String) }

    var slugInput = ""
    var busqueda = ""
    private(set) var state: LoadState = .idle
    private(set) var resultados: [RestauranteResumenDTO] = []
    private(set) var buscando = false
    var abrirCarta = false

    private let env: AppEnvironment
    init(env: AppEnvironment) {
        self.env = env
        slugInput = env.preferences.ultimoSlug ?? ""
    }

    /// Valida que el restaurante exista y esté activo descargando su carta (404 si no).
    func abrir(slug rawSlug: String, mesaCodigo: String? = nil) async {
        let slug = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Endpoints.isValidSlug(slug) else {
            state = .failed("El código del restaurante solo admite minúsculas, números y guiones.")
            return
        }
        state = .loading
        do {
            let carta: CartaResponse = try await env.api.send(Endpoints.carta(slug: slug, mesaCodigo: mesaCodigo))
            env.activate(carta: carta, mesaCodigo: mesaCodigo)
            state = .idle
            abrirCarta = true
        } catch let e as APIError {
            if case .notFound = e {
                state = .failed(mesaCodigo == nil ? "No existe un restaurante activo con el código «\(slug)»." :
                                    "El restaurante o la mesa del QR no están activos.")
            } else {
                state = .failed(e.userMessage)
            }
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("No se pudo abrir la carta.")
        }
    }

    func abrirQR(_ contenido: String) async {
        guard let r = QRLinkParser.parse(contenido) else {
            state = .failed("El QR no corresponde a una carta Adbana.")
            return
        }
        slugInput = r.slug
        await abrir(slug: r.slug, mesaCodigo: r.mesaCodigo)
    }

    func abrirDemo() {
        env.activate(carta: DemoCatalog.carta, mesaCodigo: nil)
        abrirCarta = true
    }

    func buscar() async {
        buscando = true
        defer { buscando = false }
        do {
            let pagina: PaginaRestaurantes = try await env.api.send(Endpoints.restaurantes(q: busqueda))
            resultados = pagina.data
            if resultados.isEmpty { state = .failed("No hay restaurantes publicados que coincidan.") } else { state = .idle }
        } catch let e as APIError {
            state = .failed(e.userMessage)
        } catch {
            state = .failed("No se pudo buscar restaurantes.")
        }
    }
}
