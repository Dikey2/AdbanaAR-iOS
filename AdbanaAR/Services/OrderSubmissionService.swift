import Foundation
import SwiftData

/// Intención de pedido: una clave UUID por intención de compra y el cuerpo exacto serializado una sola vez.
struct OrderIntent: Equatable {
    let clave: String
    let slug: String
    let restauranteNombre: String
    let body: Data
    let notaVozArchivo: String?
}

/// Persistencia de intenciones pendientes (SwiftData en la app, memoria en pruebas).
@MainActor
protocol PendingOrderStore: AnyObject {
    func save(_ intent: OrderIntent)
    func pending(slug: String) -> OrderIntent?
    func recordFailure(clave: String, message: String)
    func remove(clave: String)
}

@MainActor
final class SwiftDataPendingOrderStore: PendingOrderStore {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func save(_ intent: OrderIntent) {
        let clave = intent.clave
        let existing = try? context.fetch(FetchDescriptor<BorradorPedido>(predicate: #Predicate { $0.clave == clave })).first
        guard existing == nil else { return } // nunca se sobrescribe el cuerpo de una clave existente
        context.insert(BorradorPedido(clave: intent.clave, slug: intent.slug, restauranteNombre: intent.restauranteNombre,
                                      cuerpo: intent.body, notaVozArchivo: intent.notaVozArchivo))
        try? context.save()
    }

    func pending(slug: String) -> OrderIntent? {
        var d = FetchDescriptor<BorradorPedido>(predicate: #Predicate { $0.slug == slug }, sortBy: [SortDescriptor(\.creadoEn, order: .reverse)])
        d.fetchLimit = 1
        guard let b = try? context.fetch(d).first else { return nil }
        return OrderIntent(clave: b.clave, slug: b.slug, restauranteNombre: b.restauranteNombre, body: b.cuerpo, notaVozArchivo: b.notaVozArchivo)
    }

    func recordFailure(clave: String, message: String) {
        guard let b = try? context.fetch(FetchDescriptor<BorradorPedido>(predicate: #Predicate { $0.clave == clave })).first else { return }
        b.intentos += 1
        b.ultimoError = message
        try? context.save()
    }

    func remove(clave: String) {
        try? context.delete(model: BorradorPedido.self, where: #Predicate { $0.clave == clave })
        try? context.save()
    }
}

@MainActor
final class InMemoryPendingOrderStore: PendingOrderStore {
    private(set) var items: [String: OrderIntent] = [:]
    private(set) var failures: [String: Int] = [:]
    func save(_ intent: OrderIntent) { if items[intent.clave] == nil { items[intent.clave] = intent } }
    func pending(slug: String) -> OrderIntent? { items.values.first { $0.slug == slug } }
    func recordFailure(clave: String, message: String) { failures[clave, default: 0] += 1 }
    func remove(clave: String) { items[clave] = nil }
}

/// Envía pedidos públicos respetando la idempotencia del backend (PedidoPublicoIdempotente):
/// misma clave + mismo cuerpo => mismo pedido; misma clave + otro cuerpo => 409.
@MainActor
final class OrderSubmissionService {
    enum Outcome: Equatable {
        case created(PedidoCreadoResponse)
        /// Puede reintentarse con la MISMA intención (respuesta perdida, 429, 5xx).
        case retryable(APIError, OrderIntent)
        /// Requiere corregir datos; una corrección es una NUEVA intención con otra clave.
        case rejected(APIError)
    }

    private let api: APIClient
    private let store: PendingOrderStore
    private let historial: HistorialStore
    private let keychain: KeychainStore
    var onCreated: ((PedidoCreadoResponse, OrderIntent) -> Void)?

    init(api: APIClient, store: PendingOrderStore, historial: HistorialStore, keychain: KeychainStore) {
        self.api = api
        self.store = store
        self.historial = historial
        self.keychain = keychain
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// Crea una intención nueva (nueva clave UUID) y la guarda ANTES del primer envío.
    func makeIntent(form: OrderForm, items: [PedidoRequest.Item], slug: String, restauranteNombre: String,
                    notaVozArchivo: String?, clave: UUID = UUID()) throws -> OrderIntent {
        let request = form.makeRequest(clave: clave, items: items)
        let body = try Self.encoder.encode(request)
        let intent = OrderIntent(clave: request.claveOperacion, slug: slug, restauranteNombre: restauranteNombre,
                                 body: body, notaVozArchivo: notaVozArchivo)
        store.save(intent)
        return intent
    }

    func pendingIntent(slug: String) -> OrderIntent? { store.pending(slug: slug) }

    func discard(_ intent: OrderIntent) { store.remove(clave: intent.clave) }

    /// Envía exactamente `intent.body`. Se puede invocar varias veces con la misma intención.
    func submit(_ intent: OrderIntent) async -> Outcome {
        do {
            let response: PedidoCreadoResponse = try await api.send(Endpoints.crearPedido(slug: intent.slug, body: intent.body))
            store.remove(clave: intent.clave)
            if let token = response.seguimientoToken {
                keychain.set(token, account: KeychainStore.account(slug: intent.slug, pedidoId: response.pedidoId))
            }
            let tipo = (try? JSONDecoder().decode(PedidoRequest.self, from: intent.body).tipo.rawValue) ?? ""
            historial.upsert(pedidoId: response.pedidoId, slug: intent.slug, restauranteNombre: intent.restauranteNombre,
                             total: response.total.description, estado: response.estado, tipo: tipo,
                             notaVozArchivo: intent.notaVozArchivo)
            onCreated?(response, intent)
            return .created(response)
        } catch let error as APIError {
            if error.isRetryableForSameIntent {
                store.recordFailure(clave: intent.clave, message: error.userMessage)
                return .retryable(error, intent)
            }
            store.remove(clave: intent.clave)
            return .rejected(error)
        } catch is CancellationError {
            return .retryable(.transport("cancelado"), intent)
        } catch {
            store.recordFailure(clave: intent.clave, message: "error")
            return .retryable(.transport("desconocido"), intent)
        }
    }
}
