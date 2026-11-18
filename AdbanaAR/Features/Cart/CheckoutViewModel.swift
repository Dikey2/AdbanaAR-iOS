import Foundation
import Observation

@MainActor
@Observable
final class CheckoutViewModel {
    enum Fase: Equatable {
        case editando
        case enviando
        /// Respuesta perdida / 429 / 5xx: se reintenta con la misma clave y cuerpo.
        case reintentable(String)
        case rechazado(String)
        case creado(PedidoCreadoResponse)
    }

    var form = OrderForm()
    var errores: [OrderForm.Field: String] = [:]
    var notaVozArchivo: String?
    private(set) var fase: Fase = .editando
    private(set) var intent: OrderIntent?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
        let p = env.preferences
        form.clienteNombre = p.nombreCliente
        form.telefono = p.telefono
        let modalidades = env.carta?.restaurante.modalidades ?? Modalidad.allCases
        form.tipo = Modalidad(rawValue: p.modalidadPreferida).flatMap { modalidades.contains($0) ? $0 : nil } ?? modalidades.first ?? .recojo
        if let mesa = env.carta?.mesa { form.tipo = .mesa; form.mesa = mesa.nombre }
        // Personalización 3D/AR: se precarga como nota editable (el cliente la ve antes de enviar).
        if let p = env.cart.notasPersonalizacion { form.notas = String(p.prefix(500)) }
        // Si quedó una intención sin respuesta, se recupera para reenviarla idéntica.
        if let slug = env.carta?.restaurante.slug, let pendiente = env.orders.pendingIntent(slug: slug) {
            intent = pendiente
            fase = .reintentable("Hay un pedido enviado sin confirmación. Reintenta para consultar el resultado sin duplicarlo.")
        }
    }

    var modalidades: [Modalidad] { env.carta?.restaurante.modalidades ?? [] }
    var mesas: [MesaDTO] { env.carta?.mesas ?? [] }
    var mesaFijadaPorQR: Bool { env.carta?.mesa != nil }
    var isDemo: Bool { env.isDemo }

    func enviar() async {
        guard !isDemo else {
            fase = .rechazado("El modo demostración no envía pedidos. Abre un restaurante real.")
            return
        }
        guard let carta = env.carta, carta.restaurante.slug == env.cart.slug else {
            fase = .rechazado("Abre la carta del restaurante antes de enviar.")
            return
        }
        errores = form.validate(modalidades: carta.restaurante.modalidades, items: env.cart.requestItems)
        guard errores.isEmpty else { return }

        let p = env.preferences
        p.nombreCliente = form.clienteNombre
        p.telefono = form.telefono
        p.modalidadPreferida = form.tipo.rawValue
        try? env.modelContainer.mainContext.save()

        do {
            // Nueva intención = nueva clave. Solo se crea una vez por intención de compra.
            let nueva = try env.orders.makeIntent(form: form, items: env.cart.requestItems,
                                                  slug: carta.restaurante.slug, restauranteNombre: carta.restaurante.nombre,
                                                  notaVozArchivo: notaVozArchivo)
            intent = nueva
            await enviar(nueva)
        } catch {
            fase = .rechazado("No se pudo preparar el pedido.")
        }
    }

    /// Reintento: MISMA clave y MISMO cuerpo (no se regenera nada).
    func reintentar() async {
        guard let intent else { return }
        await enviar(intent)
    }

    /// El cliente decide abandonar la intención pendiente (p. ej. para cambiar el pedido).
    func descartarPendiente() {
        if let intent { env.orders.discard(intent) }
        intent = nil
        fase = .editando
    }

    private func enviar(_ intent: OrderIntent) async {
        fase = .enviando
        switch await env.orders.submit(intent) {
        case .created(let r):
            env.cart.clear()
            self.intent = nil
            fase = .creado(r)
            if let archivo = notaVozArchivo ?? intent.notaVozArchivo {
                let url = VoiceNoteRecorder.directorio.appendingPathComponent(archivo)
                _ = try? await env.firebase.subirNotaVoz(archivo: url, clave: intent.clave)
            }
        case .retryable(let e, _):
            fase = .reintentable(e.userMessage)
        case .rejected(let e):
            self.intent = nil
            if case .validation(_, let fields) = e { mapear(fields) }
            fase = .rechazado(e.userMessage)
        }
    }

    private func mapear(_ fields: [String: [String]]) {
        let mapa: [String: OrderForm.Field] = ["cliente_nombre": .clienteNombre, "tipo": .tipo, "mesa": .mesa,
                                               "direccion": .direccion, "cliente_telefono": .telefono, "notas": .notas]
        for (k, v) in fields {
            let campo = mapa[k] ?? (k.hasPrefix("items") ? .items : nil)
            if let campo, let m = v.first { errores[campo] = m }
        }
    }
}
