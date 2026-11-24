import Foundation
import SwiftData

/// Cambios del administrador sobre un restaurante incluido en la app (SwiftData).
/// Un campo nil conserva el valor original del catálogo.
@Model
final class AjusteRestaurante {
    @Attribute(.unique) var slug: String
    var nombre: String?
    var lema: String?
    var descripcion: String?
    var horario: String?
    var modalidades: [String]?
    var visible: Bool = true
    var actualizadoEn: Date

    init(slug: String) {
        self.slug = slug
        actualizadoEn = .now
    }
}

/// Cambios del administrador sobre un plato (precio, disponibilidad, textos, visibilidad).
@Model
final class AjusteProducto {
    @Attribute(.unique) var productoId: Int
    var nombre: String?
    var descripcion: String?
    var precio: String?
    var disponible: Bool?
    var oculto: Bool = false
    var actualizadoEn: Date

    init(productoId: Int) {
        self.productoId = productoId
        actualizadoEn = .now
    }
}

/// Banner del carrusel del inicio, editable por el administrador.
@Model
final class AjusteBanner {
    @Attribute(.unique) var orden: Int
    var antetitulo: String
    var titulo: String
    var detalle: String
    var foto: String
    var visible: Bool = true

    init(orden: Int, antetitulo: String, titulo: String, detalle: String, foto: String) {
        self.orden = orden
        self.antetitulo = antetitulo
        self.titulo = titulo
        self.detalle = detalle
        self.foto = foto
    }
}

/// Banner listo para mostrar (desacoplado de SwiftData).
struct Banner: Identifiable, Equatable {
    let id: Int
    let antetitulo: String
    let titulo: String
    let detalle: String
    let foto: String
    let visible: Bool

    static let originales: [Banner] = [
        Banner(id: 0, antetitulo: "Nuevo", titulo: "Mira tu plato antes de pedirlo", detalle: "Ponlo sobre tu mesa con realidad aumentada.", foto: "foto-torta_chocolate_fresas", visible: true),
        Banner(id: 1, antetitulo: "A tu gusto", titulo: "Platos reales en 3D", detalle: "Escaneados de comida real, a tamaño real.", foto: "foto-combo_burger", visible: true),
        Banner(id: 2, antetitulo: "Tamaño real", titulo: "Lo que ves es lo que llega", detalle: "Platos en 3D a escala real.", foto: "foto-bowl_frutas", visible: true),
    ]

    /// Fotos disponibles para elegir en el editor de banners.
    static let fotos = ["foto-torta_chocolate_fresas", "foto-torta_zanahoria", "foto-croissants", "foto-bowl_frutas",
                        "foto-tabla_frutas", "foto-combo_pollo", "foto-combo_burger", "foto-burger_casera", "foto-pizza_3dst6",
                        "foto-combo_bife", "foto-salmon", "foto-gyoza", "foto-momo", "foto-tarta_limon"]
}
