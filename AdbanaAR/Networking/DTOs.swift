import Foundation

// Contratos confirmados contra CartaController, SeguimientoPedidoController y
// CatalogoRestaurantesController del repositorio Adbana_saas (ver docs/INTEGRACION_API.md).

/// Decimal serializado por Laravel como texto ("42.50"). Acepta también números.
struct DecimalString: Codable, Hashable, Sendable, CustomStringConvertible {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) {
            value = d
        } else if let i = try? c.decode(Int.self) {
            value = Decimal(i)
        } else if let dbl = try? c.decode(Double.self), let d = Decimal(string: String(dbl), locale: Locale(identifier: "en_US_POSIX")) {
            value = d
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Importe no decimal")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    var description: String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .plain)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f.string(from: rounded as NSDecimalNumber) ?? "0.00"
    }
}

struct CartaResponse: Codable, Sendable {
    let restaurante: RestauranteDTO
    let carta: [CategoriaDTO]
    let mesas: [MesaDTO]?
    let mesa: MesaQRDTO?
}

struct RestauranteDTO: Codable, Hashable, Sendable {
    let nombre: String
    let slug: String
    let telefono: String?
    let configuracion: ConfiguracionDTO?

    private enum CodingKeys: String, CodingKey { case nombre, slug, telefono, configuracion }

    init(nombre: String, slug: String, telefono: String?, configuracion: ConfiguracionDTO?) {
        self.nombre = nombre; self.slug = slug; self.telefono = telefono; self.configuracion = configuracion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = try c.decode(String.self, forKey: .nombre)
        slug = try c.decode(String.self, forKey: .slug)
        telefono = try c.decodeIfPresent(String.self, forKey: .telefono)
        // PHP serializa un arreglo vacío como [] en lugar de {}: se trata como "sin configuración".
        configuracion = (try? c.decodeIfPresent(ConfiguracionDTO.self, forKey: .configuracion)) ?? nil
    }

    /// Modalidades ofrecidas; el backend usa ["mesa","recojo","delivery"] por defecto.
    var modalidades: [Modalidad] {
        let raw = configuracion?.modalidades ?? Modalidad.allCases.map(\.rawValue)
        return raw.compactMap(Modalidad.init(rawValue:))
    }
}

struct ConfiguracionDTO: Codable, Hashable, Sendable {
    let modalidades: [String]?
    let descripcion: String?
    let direccion: String?
    let horario: String?
    /// Ampliación propuesta (docs/PROPUESTA_BACKEND_UBICACION_AR.md): zona donde se permite la AR.
    let ubicacionAR: GeocercaAR?

    private enum CodingKeys: String, CodingKey {
        case modalidades, descripcion, direccion, horario
        case ubicacionAR = "ubicacion_ar"
    }

    init(modalidades: [String]?, descripcion: String?, direccion: String?, horario: String?, ubicacionAR: GeocercaAR? = nil) {
        self.modalidades = modalidades; self.descripcion = descripcion; self.direccion = direccion
        self.horario = horario; self.ubicacionAR = ubicacionAR
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modalidades = try c.decodeIfPresent([String].self, forKey: .modalidades)
        descripcion = try c.decodeIfPresent(String.self, forKey: .descripcion)
        direccion = try c.decodeIfPresent(String.self, forKey: .direccion)
        horario = try c.decodeIfPresent(String.self, forKey: .horario)
        // Un valor mal formado no debe impedir abrir la carta: se ignora.
        ubicacionAR = (try? c.decodeIfPresent(GeocercaAR.self, forKey: .ubicacionAR)) ?? nil
    }
}

struct CategoriaDTO: Codable, Hashable, Sendable {
    let id: Int?
    let nombre: String
    let productos: [ProductoDTO]

    var identity: String { id.map { "cat-\($0)" } ?? "cat-otros" }
}

struct ProductoDTO: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let nombre: String
    let descripcion: String?
    let precio: DecimalString
    let imagen: String?
    /// URL GLB (proxy `/api/carta/{slug}/productos/{id}/modelo` o https absoluta).
    let modelo3D: String?
    /// Ampliación opcional propuesta (docs/backend-patch): URL USDZ compatible con RealityKit.
    let modeloUSDZ: String?
    let disponible: Bool

    private enum CodingKeys: String, CodingKey {
        case id, nombre, descripcion, precio, imagen, disponible
        case modelo3D = "modelo_3d"
        case modeloUSDZ = "modelo_usdz"
    }
}

struct MesaDTO: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let nombre: String
    let ocupada: Bool
}

struct MesaQRDTO: Codable, Hashable, Sendable {
    let nombre: String
    let codigo: String
}

enum Modalidad: String, CaseIterable, Codable, Identifiable, Sendable {
    case mesa, recojo, delivery
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .mesa: return "En mesa"
        case .recojo: return "Recojo"
        case .delivery: return "Delivery"
        }
    }
    var icono: String {
        switch self {
        case .mesa: return "fork.knife"
        case .recojo: return "bag"
        case .delivery: return "bicycle"
        }
    }
}

/// Cuerpo de POST /api/carta/{slug}/pedidos. Las claves opcionales se omiten si son nil.
struct PedidoRequest: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let productoId: Int
        let cantidad: Int
        private enum CodingKeys: String, CodingKey { case productoId = "producto_id", cantidad }
    }

    let claveOperacion: String
    let clienteNombre: String
    let tipo: Modalidad
    let mesa: String?
    let direccion: String?
    let clienteTelefono: String?
    let notas: String?
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case claveOperacion = "clave_operacion"
        case clienteNombre = "cliente_nombre"
        case tipo, mesa, direccion, notas, items
        case clienteTelefono = "cliente_telefono"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claveOperacion, forKey: .claveOperacion)
        try c.encode(clienteNombre, forKey: .clienteNombre)
        try c.encode(tipo, forKey: .tipo)
        try c.encodeIfPresent(mesa, forKey: .mesa)
        try c.encodeIfPresent(direccion, forKey: .direccion)
        try c.encodeIfPresent(clienteTelefono, forKey: .clienteTelefono)
        try c.encodeIfPresent(notas, forKey: .notas)
        try c.encode(items, forKey: .items)
    }
}

struct PedidoCreadoResponse: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let producto: String
        let cantidad: Int
        let precioUnitario: DecimalString
        let subtotal: DecimalString
        private enum CodingKeys: String, CodingKey {
            case producto, cantidad, subtotal
            case precioUnitario = "precio_unitario"
        }
    }

    let seguimientoToken: String?
    let pedidoId: Int
    let estado: String
    let total: DecimalString
    let items: [Item]

    private enum CodingKeys: String, CodingKey {
        case seguimientoToken = "seguimiento_token"
        case pedidoId = "pedido_id"
        case estado, total, items
    }
}

struct SeguimientoResponse: Codable, Equatable, Sendable {
    let pedidoId: Int
    let estado: String
    let total: DecimalString
    let pagado: DecimalString
    let tipo: String

    private enum CodingKeys: String, CodingKey {
        case pedidoId = "pedido_id"
        case estado, total, pagado, tipo
    }
}

struct RestauranteResumenDTO: Codable, Hashable, Identifiable, Sendable {
    let nombre: String
    let slug: String
    let telefono: String?
    var id: String { slug }
}

struct PaginaRestaurantes: Codable, Sendable {
    let data: [RestauranteResumenDTO]
    let currentPage: Int?
    let lastPage: Int?
    private enum CodingKeys: String, CodingKey {
        case data
        case currentPage = "current_page"
        case lastPage = "last_page"
    }
}
