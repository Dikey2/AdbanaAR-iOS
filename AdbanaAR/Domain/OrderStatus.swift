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

    var isFinal: Bool { self == .entregado || self == .cancelado }
    var paso: Int { OrderStatus.flujo.firstIndex(of: self) ?? 0 }
}
