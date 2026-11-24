import Foundation

/// Pedidos de los restaurantes de DEMOSTRACIÓN (ficticios). No se envían a ningún servidor:
/// se registran en el dispositivo y su estado avanza con el tiempo para mostrar el seguimiento
/// completo (recibido → entregado). La interfaz los rotula como "pedido simulado".
@MainActor
final class SimuladorPedidos {
    struct Item: Codable, Equatable {
        let producto: String
        let cantidad: Int
        let precioUnitario: String
        let subtotal: String
    }

    struct Pedido: Codable, Equatable {
        let id: Int
        let slug: String
        let restaurante: String
        let tipo: String
        let creadoEn: Date
        let total: String
        let items: [Item]
        /// Segundos adelantados con "Avanzar estado" (para la exposición).
        var adelanto: TimeInterval
        /// Fijado por el administrador: detiene el avance automático en ese estado.
        var estadoFijo: String?
    }

    /// Segundos desde la creación en que se alcanza cada estado.
    static let cronograma: [(OrderStatus, TimeInterval)] = [
        (.pendiente, 0), (.confirmado, 12), (.preparando, 30), (.listo, 75), (.entregado, 130),
    ]

    private let defaults: UserDefaults?
    private let clave = "simulador.pedidos.v1"
    private(set) var pedidos: [Int: Pedido] = [:]
    var ahora: () -> Date = { .now }

    /// `persistir: false` en pruebas: los pedidos viven solo en memoria.
    init(persistir: Bool) {
        defaults = persistir ? .standard : nil
        if let data = defaults?.data(forKey: clave),
           let guardados = try? JSONDecoder().decode([Int: Pedido].self, from: data) {
            pedidos = guardados
        }
    }

    func crear(slug: String, restaurante: String, tipo: Modalidad, lineas: [CartLine]) -> PedidoCreadoResponse {
        let id = (pedidos.keys.max() ?? 70_000) + 1
        let items = lineas.map {
            Item(producto: $0.producto.nombre, cantidad: $0.cantidad,
                 precioUnitario: $0.producto.precio.description, subtotal: DecimalString($0.subtotalEstimado).description)
        }
        let total = DecimalString(lineas.reduce(Decimal(0)) { $0 + $1.subtotalEstimado }).description
        let p = Pedido(id: id, slug: slug, restaurante: restaurante, tipo: tipo.rawValue, creadoEn: ahora(),
                       total: total, items: items, adelanto: 0)
        pedidos[id] = p
        guardar()
        return PedidoCreadoResponse(
            seguimientoToken: nil, pedidoId: id, estado: OrderStatus.pendiente.rawValue,
            total: DecimalString(Decimal(string: total) ?? 0),
            items: items.map {
                PedidoCreadoResponse.Item(producto: $0.producto, cantidad: $0.cantidad,
                                          precioUnitario: DecimalString(Decimal(string: $0.precioUnitario) ?? 0),
                                          subtotal: DecimalString(Decimal(string: $0.subtotal) ?? 0))
            })
    }

    func estado(pedidoId: Int) -> OrderStatus? {
        guard let p = pedidos[pedidoId] else { return nil }
        if let fijo = p.estadoFijo { return OrderStatus(raw: fijo) }
        let t = ahora().timeIntervalSince(p.creadoEn) + p.adelanto
        return Self.cronograma.last { $0.1 <= t }?.0 ?? .pendiente
    }

    func seguimiento(pedidoId: Int) -> SeguimientoResponse? {
        guard let p = pedidos[pedidoId], let e = estado(pedidoId: pedidoId) else { return nil }
        let total = DecimalString(Decimal(string: p.total) ?? 0)
        // Se considera pagado al entregar (pago contra entrega / en caja).
        return SeguimientoResponse(pedidoId: p.id, estado: e.rawValue, total: total,
                                   pagado: e == .entregado ? total : DecimalString(0), tipo: p.tipo)
    }

    /// Salta al siguiente estado (solo demostración).
    func avanzar(pedidoId: Int) {
        guard var p = pedidos[pedidoId], p.estadoFijo == nil, let actual = estado(pedidoId: pedidoId),
              let i = Self.cronograma.firstIndex(where: { $0.0 == actual }), i + 1 < Self.cronograma.count else { return }
        let transcurrido = ahora().timeIntervalSince(p.creadoEn) + p.adelanto
        p.adelanto += Self.cronograma[i + 1].1 - transcurrido
        pedidos[pedidoId] = p
        guardar()
    }

    /// Administrador: fija el estado (incluido cancelado). `nil` reanuda el avance automático desde ese punto.
    func fijar(pedidoId: Int, estado: OrderStatus?) {
        guard var p = pedidos[pedidoId] else { return }
        if let estado, estado != .cancelado, let umbral = Self.cronograma.first(where: { $0.0 == estado })?.1 {
            // Se reubica el reloj en el umbral del estado elegido y se deja fijo.
            p.adelanto = umbral - ahora().timeIntervalSince(p.creadoEn)
        }
        p.estadoFijo = estado?.rawValue
        pedidos[pedidoId] = p
        guardar()
    }

    func eliminar(pedidoId: Int) {
        pedidos[pedidoId] = nil
        guardar()
    }

    func eliminarTodos() {
        pedidos = [:]
        guardar()
    }

    private func guardar() {
        guard let defaults, let data = try? JSONEncoder().encode(pedidos) else { return }
        defaults.set(data, forKey: clave)
    }
}
