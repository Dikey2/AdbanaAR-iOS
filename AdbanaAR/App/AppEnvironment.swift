import Foundation
import Observation
import SwiftData

/// Contenedor de dependencias compartido por SwiftUI y UIKit (Storyboard).
@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let isUITesting: Bool
    let modelContainer: ModelContainer
    let historial: HistorialStore
    let keychain = KeychainStore()
    let cart = CartStore()
    let firebase: FirebaseService
    let models = ModelRepository()
    private(set) var api: APIClient
    private(set) var orders: OrderSubmissionService
    private(set) var configError: String?

    /// Restaurante activo (carta descargada o demo local).
    var carta: CartaResponse?
    var mesaCodigo: String?
    var isDemo: Bool { carta?.restaurante.slug == DemoCatalog.slug }

    private init() {
        let args = ProcessInfo.processInfo.arguments
        isUITesting = args.contains("-ui-testing")
        modelContainer = LocalStore.makeContainer(inMemory: isUITesting)
        historial = HistorialStore(inMemory: isUITesting)
        if isUITesting && args.contains("-ui-testing-historial") {
            // Solo pruebas de UI: un pedido ficticio en el CoreData en memoria para ejercitar el Segue.
            _ = historial.upsert(pedidoId: 4242, slug: DemoCatalog.slug, restauranteNombre: "Restaurante de prueba UI",
                                 total: "38.00", estado: "pendiente", tipo: "mesa")
        }
        firebase = FirebaseService(configured: !isUITesting && FirebaseService.configureIfPossible())

        let prefs = Self.loadPreferences(modelContainer.mainContext)
        var base = AppConfig.bundleBaseURL()
        if let override = prefs.apiBaseURL, case let .success(url) = AppConfig.validate(override) { base = url }
        let client = APIClient(baseURL: base)
        api = client
        orders = OrderSubmissionService(api: client, store: SwiftDataPendingOrderStore(context: modelContainer.mainContext),
                                        historial: historial, keychain: keychain)
        wireOrders()
        restoreCart()
        cart.onChange = { [weak self] in self?.persistCart() }
    }

    var preferences: PreferenciasUsuario { Self.loadPreferences(modelContainer.mainContext) }

    private static func loadPreferences(_ context: ModelContext) -> PreferenciasUsuario {
        if let p = try? context.fetch(FetchDescriptor<PreferenciasUsuario>()).first { return p }
        let p = PreferenciasUsuario()
        context.insert(p)
        try? context.save()
        return p
    }

    /// Cambia la URL base (validada). Vacío = valor del xcconfig.
    func updateBaseURL(_ raw: String) -> String? {
        let prefs = preferences
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if trimmed.isEmpty {
            prefs.apiBaseURL = nil
            url = AppConfig.bundleBaseURL()
        } else {
            switch AppConfig.validate(trimmed) {
            case .failure(let e): return e.localizedDescription
            case .success(let u): prefs.apiBaseURL = u.absoluteString; url = u
            }
        }
        prefs.actualizadoEn = .now
        try? modelContainer.mainContext.save()
        api = APIClient(baseURL: url)
        orders = OrderSubmissionService(api: api, store: SwiftDataPendingOrderStore(context: modelContainer.mainContext),
                                        historial: historial, keychain: keychain)
        wireOrders()
        return nil
    }

    private func wireOrders() {
        orders.onCreated = { [weak self] response, intent in
            guard let self else { return }
            Task {
                await self.firebase.reflejarPedido(slug: intent.slug, pedidoId: response.pedidoId,
                                                   restaurante: intent.restauranteNombre,
                                                   estado: response.estado, total: response.total.description)
            }
        }
    }

    func activate(carta: CartaResponse, mesaCodigo: String?) {
        self.carta = carta
        self.mesaCodigo = mesaCodigo
        cart.bind(slug: carta.restaurante.slug, restauranteNombre: carta.restaurante.nombre)
        if carta.restaurante.slug != DemoCatalog.slug {
            preferences.ultimoSlug = carta.restaurante.slug
            try? modelContainer.mainContext.save()
        }
    }

    // MARK: Carrito (borrador SwiftData)

    private func persistCart() {
        guard let slug = cart.slug, let nombre = cart.restauranteNombre else { return }
        let context = modelContainer.mainContext
        let data = (try? JSONEncoder().encode(cart.lines)) ?? Data()
        if let saved = try? context.fetch(FetchDescriptor<CarritoGuardado>(predicate: #Predicate { $0.slug == slug })).first {
            saved.lineasJSON = data
            saved.restauranteNombre = nombre
            saved.actualizadoEn = .now
        } else {
            context.insert(CarritoGuardado(slug: slug, restauranteNombre: nombre, lineasJSON: data))
        }
        try? context.save()
    }

    private func restoreCart() {
        var d = FetchDescriptor<CarritoGuardado>(sortBy: [SortDescriptor(\.actualizadoEn, order: .reverse)])
        d.fetchLimit = 1
        guard let saved = try? modelContainer.mainContext.fetch(d).first,
              let lines = try? JSONDecoder().decode([CartLine].self, from: saved.lineasJSON), !lines.isEmpty else { return }
        cart.restore(slug: saved.slug, restauranteNombre: saved.restauranteNombre, lines: lines)
    }

    // MARK: Seguimiento

    func trackingToken(slug: String, pedidoId: Int) -> String? {
        keychain.get(account: KeychainStore.account(slug: slug, pedidoId: pedidoId))
    }

    /// Consulta el estado con el token del propio pedido y actualiza CoreData + Firebase.
    func refreshStatus(slug: String, pedidoId: Int) async throws -> SeguimientoResponse {
        guard let token = trackingToken(slug: slug, pedidoId: pedidoId) else {
            throw APIError.notFound("No hay token de seguimiento para este pedido en este dispositivo.")
        }
        let s: SeguimientoResponse = try await api.send(Endpoints.seguimiento(slug: slug, token: token))
        historial.updateEstado(slug: slug, pedidoId: pedidoId, estado: s.estado, pagado: s.pagado.description, total: s.total.description)
        let nombre = historial.registro(slug: slug, pedidoId: pedidoId)?.restauranteNombre ?? slug
        await firebase.reflejarPedido(slug: slug, pedidoId: pedidoId, restaurante: nombre, estado: s.estado, total: s.total.description)
        return s
    }
}
