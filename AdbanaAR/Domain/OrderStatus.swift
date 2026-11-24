import Foundation

/// Estados operativos de `pedidos.estado` (PedidoController::cambiarEstado).
enum OrderStatus: String, CaseIterable, Codable {
    case pendiente, confirmado, preparando, listo, entregado, cancelado

    init(raw: String) { self = OrderStatus(rawValue: raw.lowercased()) ?? .pendiente }

    static let flujo: [OrderStatus] = [.pendiente, .confirmado, .preparando, .listo, .entregado]

    var titulo: String {
        switch self {
        case .pendiente: return "Recibido"
        case .confirmado: return "Confirmado"
        case .preparando: return "En preparación"
        case .listo: return "Listo"
        case .entregado: return "Entregado"
        case .cancelado: return "Cancelado"
        }
    }

    var icono: String {
        switch self {
        case .pendiente: return "tray.and.arrow.down"
        case .confirmado: return "checkmark.seal"
        case .preparando: return "flame"
        case .listo: return "bell"
        case .entregado: return "hand.thumbsup"
        case .cancelado: return "xmark.octagon"
        }
    }

    /// Título del paso según la modalidad (delivery, recojo o mesa).
    func titulo(para tipo: Modalidad?) -> String {
        switch (self, tipo) {
        case (.listo, .delivery?): return "En camino"
        case (.entregado, .delivery?): return "Entregado"
        case (.listo, .recojo?): return "Listo para recoger"
        case (.entregado, .recojo?): return "Recogido"
        case (.listo, .mesa?): return "Listo para servir"
        case (.entregado, .mesa?): return "Servido"
        default: return titulo
        }
    }

    func detalle(para tipo: Modalidad?) -> String {
        switch (self, tipo) {
        case (.pendiente, _): return "El restaurante recibió tu pedido."
        case (.confirmado, _): return "El restaurante aceptó tu pedido."
        case (.preparando, _): return "La cocina está preparando tus platos."
        case (.listo, .delivery?): return "Tu pedido salió del local hacia tu dirección."
        case (.listo, .recojo?): return "Acércate al mostrador y muestra tu número de pedido."
        case (.listo, _): return "Tu pedido está listo y va a tu mesa."
        case (.entregado, .delivery?): return "Tu pedido llegó a tu dirección. ¡Buen provecho!"
        case (.entregado, .recojo?): return "Recogiste tu pedido. ¡Buen provecho!"
        case (.entregado, _): return "Tu pedido fue servido. ¡Buen provecho!"
        case (.cancelado, _): return "El restaurante canceló el pedido."
        }
    }

    func icono(para tipo: Modalidad?) -> String {
        switch (self, tipo) {
        case (.listo, .delivery?): return "bicycle"
        case (.entregado, .delivery?): return "house.fill"
        case (.listo, .recojo?): return "bag.fill"
        case (.entregado, .recojo?): return "checkmark.seal.fill"
        default: return icono
        }
    }

    var isFinal: Bool { self == .entregado || self == .cancelado }
    var paso: Int { OrderStatus.flujo.firstIndex(of: self) ?? 0 }
}
