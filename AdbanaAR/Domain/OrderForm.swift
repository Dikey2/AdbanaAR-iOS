import Foundation

/// Datos del cliente para un pedido público. Replica las reglas de validación del backend
/// para dar retroalimentación inmediata; el backend sigue siendo la autoridad (422).
struct OrderForm: Equatable {
    var clienteNombre = ""
    var tipo: Modalidad = .mesa
    var mesa = ""
    var direccion = ""
    var telefono = ""
    var notas = ""

    enum Field: String, CaseIterable { case clienteNombre, tipo, mesa, direccion, telefono, notas, items }

    func validate(modalidades: [Modalidad], items: [PedidoRequest.Item]) -> [Field: String] {
        var e: [Field: String] = [:]
        let nombre = clienteNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if nombre.isEmpty { e[.clienteNombre] = "Ingresa tu nombre." }
        else if nombre.count > 120 { e[.clienteNombre] = "Máximo 120 caracteres." }

        if !modalidades.contains(tipo) { e[.tipo] = "El restaurante no ofrece esta modalidad." }

        switch tipo {
        case .mesa:
            let m = mesa.trimmingCharacters(in: .whitespacesAndNewlines)
            if m.isEmpty { e[.mesa] = "Indica tu mesa." }
            else if m.count > 20 { e[.mesa] = "Máximo 20 caracteres." }
        case .delivery:
            let d = direccion.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = telefono.trimmingCharacters(in: .whitespacesAndNewlines)
            if d.isEmpty { e[.direccion] = "La dirección es obligatoria para delivery." }
            else if d.count > 255 { e[.direccion] = "Máximo 255 caracteres." }
            if t.isEmpty { e[.telefono] = "El teléfono es obligatorio para delivery." }
            else if t.count > 30 { e[.telefono] = "Máximo 30 caracteres." }
        case .recojo:
            break
        }
        if notas.count > 500 { e[.notas] = "Máximo 500 caracteres." }

        if items.isEmpty { e[.items] = "El carrito está vacío." }
        else if items.count > CartStore.maxLines { e[.items] = "Máximo \(CartStore.maxLines) productos." }
        else {
            let porProducto = Dictionary(grouping: items, by: \.productoId).mapValues { $0.reduce(0) { $0 + $1.cantidad } }
            if items.contains(where: { $0.cantidad < 1 || $0.cantidad > 100 }) || porProducto.values.contains(where: { $0 > 100 }) {
                e[.items] = "Cada producto admite de 1 a 100 unidades."
            }
        }
        return e
    }

    /// Construye el cuerpo con una clave de operación ya generada para ESTA intención.
    func makeRequest(clave: UUID, items: [PedidoRequest.Item]) -> PedidoRequest {
        func clean(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return PedidoRequest(
            claveOperacion: clave.uuidString.lowercased(),
            clienteNombre: clienteNombre.trimmingCharacters(in: .whitespacesAndNewlines),
            tipo: tipo,
            mesa: tipo == .mesa ? clean(mesa) : nil,
            direccion: tipo == .delivery ? clean(direccion) : nil,
            clienteTelefono: tipo == .delivery ? clean(telefono) : nil,
            notas: clean(notas),
            items: items
        )
    }
}
