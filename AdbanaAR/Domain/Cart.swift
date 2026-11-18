import Foundation
import Observation

struct CartLine: Identifiable, Hashable, Codable {
    let producto: ProductoDTO
    var cantidad: Int
    /// Cambios de ingredientes elegidos en 3D/AR ("sin cebolla"). No altera el precio:
    /// el backend no expone modificadores, por eso viaja como texto en `notas`.
    var personalizacion: String?
    var id: Int { producto.id }
    var subtotalEstimado: Decimal { producto.precio.value * Decimal(cantidad) }
}

/// Carrito de un único restaurante. El total es ESTIMADO: el backend recalcula precios con su BD.
@MainActor
@Observable
final class CartStore {
    /// Límites del contrato público (CartaController::crearPedido).
    nonisolated static let maxLines = 50
    nonisolated static let maxUnitsPerProduct = 100

    private(set) var slug: String?
    private(set) var restauranteNombre: String?
    private(set) var lines: [CartLine] = []
    /// Incrementa en cada alta para animar el icono del carrito.
    private(set) var bump = 0

    var onChange: (() -> Void)?

    var totalUnits: Int { lines.reduce(0) { $0 + $1.cantidad } }
    var estimatedTotal: Decimal { lines.reduce(Decimal(0)) { $0 + $1.subtotalEstimado } }
    var isEmpty: Bool { lines.isEmpty }

    enum AddResult: Equatable { case added, limitReached(String), unavailable, otherRestaurant }

    func bind(slug: String, restauranteNombre: String) {
        if self.slug != slug {
            lines.removeAll()
        }
        self.slug = slug
        self.restauranteNombre = restauranteNombre
        onChange?()
    }

    @discardableResult
    func add(_ producto: ProductoDTO, cantidad: Int = 1, slug: String, personalizacion: String? = nil) -> AddResult {
        guard slug == self.slug else { return .otherRestaurant }
        guard producto.disponible else { return .unavailable }
        guard cantidad > 0 else { return .limitReached("Cantidad inválida.") }
        if let i = lines.firstIndex(where: { $0.id == producto.id }) {
            let nueva = lines[i].cantidad + cantidad
            guard nueva <= Self.maxUnitsPerProduct else {
                return .limitReached("Máximo \(Self.maxUnitsPerProduct) unidades por producto.")
            }
            lines[i].cantidad = nueva
            // Una línea por producto: la última personalización elegida aplica a todas sus unidades.
            lines[i].personalizacion = personalizacion
        } else {
            guard lines.count < Self.maxLines else {
                return .limitReached("Máximo \(Self.maxLines) productos distintos por pedido.")
            }
            guard cantidad <= Self.maxUnitsPerProduct else {
                return .limitReached("Máximo \(Self.maxUnitsPerProduct) unidades por producto.")
            }
            lines.append(CartLine(producto: producto, cantidad: cantidad, personalizacion: personalizacion))
        }
        bump += 1
        onChange?()
        return .added
    }

    func setQuantity(_ cantidad: Int, for productoId: Int) {
        guard let i = lines.firstIndex(where: { $0.id == productoId }) else { return }
        if cantidad <= 0 {
            lines.remove(at: i)
        } else {
            lines[i].cantidad = min(cantidad, Self.maxUnitsPerProduct)
        }
        onChange?()
    }

    func remove(productoId: Int) { setQuantity(0, for: productoId) }

    func clear() {
        lines.removeAll()
        onChange?()
    }

    /// Restaura líneas guardadas (SwiftData) sin disparar onChange.
    func restore(slug: String, restauranteNombre: String, lines: [CartLine]) {
        self.slug = slug
        self.restauranteNombre = restauranteNombre
        self.lines = Array(lines.prefix(Self.maxLines))
    }

    /// Texto para la cocina con las personalizaciones del carrito; nil si no hay.
    var notasPersonalizacion: String? {
        let partes = lines.compactMap { l in l.personalizacion.map { "\(l.cantidad)× \(l.producto.nombre): \($0)" } }
        return partes.isEmpty ? nil : partes.joined(separator: ". ")
    }

    var requestItems: [PedidoRequest.Item] {
        lines.map { PedidoRequest.Item(productoId: $0.producto.id, cantidad: $0.cantidad) }
    }
}

enum Money {
    static func format(_ value: Decimal) -> String {
        value.formatted(.currency(code: "PEN").locale(Locale(identifier: "es_PE")))
    }
}
