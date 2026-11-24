import Foundation
import Observation
import SwiftData

enum AppTab: Hashable { case inicio, carrito, historial, cuenta }

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
    let ubicacion = UbicacionService()
    let simulador: SimuladorPedidos
    /// Pestaña visible: permite que la carta abra el carrito.
    var tab: AppTab = .inicio
    /// Sesión del modo administrador (se cierra al salir o al cerrar la app).
    var adminActivo = false
    /// Cambia con cada edición del administrador para refrescar las vistas.
    var versionCatalogo = 0
    private(set) var api: APIClient
    private(set) var orders: OrderSubmissionService
    private(set) var configError: String?

    /// Restaurante activo (carta descargada o demo local).
    var carta: CartaResponse?
    var mesaCodigo: String?
    var isDemo: Bool { DemoCatalog.esDemo(carta?.restaurante.slug) }

    private init() {
        let args = ProcessInfo.processInfo.arguments
        isUITesting = args.contains("-ui-testing")
        modelContainer = LocalStore.makeContainer(inMemory: isUITesting)
        historial = HistorialStore(inMemory: isUITesting)
        simulador = SimuladorPedidos(persistir: !isUITesting)
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

    // MARK: Geocerca AR

    /// Zona AR del restaurante: la publicada por el backend o, si no existe, la configurada al afiliarlo en este dispositivo.
    func geocerca(slug: String, configuracion: ConfiguracionDTO? = nil) -> GeocercaAR? {
        if let remota = configuracion?.ubicacionAR, remota.esValida { return remota }
        return ubicacionLocal(slug: slug)?.geocerca
    }

    enum EstadoAR: Equatable {
        case activa(GeocercaAR)
        case desactivada
        case sinConfigurar
    }

    /// Estado de la AR del restaurante: activa (con su zona), desactivada por el restaurante o sin ubicación.
    func estadoAR(slug: String, configuracion: ConfiguracionDTO? = nil) -> EstadoAR {
        guard let zona = geocerca(slug: slug, configuracion: configuracion) else { return .sinConfigurar }
        return ubicacionLocal(slug: slug)?.arActiva == false ? .desactivada : .activa(zona)
    }

    /// Activa o desactiva la AR de un restaurante que ya tiene ubicación (propia o publicada por el servidor).
    func cambiarAR(activa: Bool, slug: String, restauranteNombre: String, configuracion: ConfiguracionDTO? = nil) {
        let ctx = modelContainer.mainContext
        if let actual = ubicacionLocal(slug: slug) {
            actual.arActiva = activa
            actual.actualizadoEn = .now
        } else if let remota = geocerca(slug: slug, configuracion: configuracion) {
            let nueva = UbicacionRestaurante(slug: slug, restauranteNombre: restauranteNombre, geocerca: remota)
            nueva.arActiva = activa
            ctx.insert(nueva)
        } else { return }
        try? ctx.save()
        versionGeocercas += 1
    }

    /// Indica si la zona proviene del servidor (no editable desde la app).
    func geocercaEsRemota(_ configuracion: ConfiguracionDTO?) -> Bool { configuracion?.ubicacionAR?.esValida == true }

    func ubicacionLocal(slug: String) -> UbicacionRestaurante? {
        let d = FetchDescriptor<UbicacionRestaurante>(predicate: #Predicate { $0.slug == slug })
        return try? modelContainer.mainContext.fetch(d).first
    }

    func guardarGeocerca(_ g: GeocercaAR, slug: String, restauranteNombre: String) {
        let ctx = modelContainer.mainContext
        if let actual = ubicacionLocal(slug: slug) {
            actual.latitud = g.latitud; actual.longitud = g.longitud; actual.radioMetros = g.radioMetros
            actual.restauranteNombre = restauranteNombre; actual.actualizadoEn = .now
        } else {
            ctx.insert(UbicacionRestaurante(slug: slug, restauranteNombre: restauranteNombre, geocerca: g))
        }
        try? ctx.save()
        versionGeocercas += 1
    }

    func borrarGeocerca(slug: String) {
        guard let actual = ubicacionLocal(slug: slug) else { return }
        modelContainer.mainContext.delete(actual)
        try? modelContainer.mainContext.save()
        versionGeocercas += 1
    }

    /// Cambia al guardar o borrar una zona, para refrescar las vistas que la muestran.
    private(set) var versionGeocercas = 0

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
        if !DemoCatalog.esDemo(carta.restaurante.slug) {
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
        if DemoCatalog.esDemo(slug) {
            guard let s = simulador.seguimiento(pedidoId: pedidoId) else {
                throw APIError.notFound("Este pedido ya no está disponible en el dispositivo.")
            }
            historial.updateEstado(slug: slug, pedidoId: pedidoId, estado: s.estado, pagado: s.pagado.description, total: s.total.description)
            return s
        }
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
