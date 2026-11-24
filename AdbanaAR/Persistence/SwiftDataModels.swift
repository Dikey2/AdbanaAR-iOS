import Foundation
import SwiftData

/// Preferencias locales del cliente (SwiftData). No contiene secretos.
@Model
final class PreferenciasUsuario {
    var apiBaseURL: String?
    var ultimoSlug: String?
    var nombreCliente: String
    var telefono: String
    var modalidadPreferida: String
    var escalaRealAR: Bool
    var actualizadoEn: Date

    init() {
        apiBaseURL = nil
        ultimoSlug = nil
        nombreCliente = ""
        telefono = ""
        modalidadPreferida = Modalidad.mesa.rawValue
        escalaRealAR = true
        actualizadoEn = .now
    }
}

/// Intención de pedido pendiente: guarda la clave UUID y el cuerpo EXACTO enviado
/// para reintentos idempotentes tras perder la respuesta (SwiftData).
@Model
final class BorradorPedido {
    @Attribute(.unique) var clave: String
    var slug: String
    var restauranteNombre: String
    var cuerpo: Data
    var creadoEn: Date
    var intentos: Int
    var ultimoError: String?
    var notaVozArchivo: String?

    init(clave: String, slug: String, restauranteNombre: String, cuerpo: Data, notaVozArchivo: String?) {
        self.clave = clave
        self.slug = slug
        self.restauranteNombre = restauranteNombre
        self.cuerpo = cuerpo
        self.creadoEn = .now
        self.intentos = 0
        self.ultimoError = nil
        self.notaVozArchivo = notaVozArchivo
    }
}

/// Borrador del carrito para recuperarlo al reabrir la app (SwiftData).
@Model
final class CarritoGuardado {
    @Attribute(.unique) var slug: String
    var restauranteNombre: String
    var lineasJSON: Data
    var actualizadoEn: Date

    init(slug: String, restauranteNombre: String, lineasJSON: Data) {
        self.slug = slug
        self.restauranteNombre = restauranteNombre
        self.lineasJSON = lineasJSON
        self.actualizadoEn = .now
    }
}

/// Ubicación AR de un restaurante afiliado, configurada en este dispositivo (SwiftData).
/// Si el backend publica `configuracion.ubicacion_ar`, esa tiene prioridad sobre esta.
@Model
final class UbicacionRestaurante {
    @Attribute(.unique) var slug: String
    var restauranteNombre: String
    var latitud: Double
    var longitud: Double
    var radioMetros: Double
    /// El restaurante puede apagar la AR sin perder la ubicación configurada.
    var arActiva: Bool = true
    var actualizadoEn: Date

    init(slug: String, restauranteNombre: String, geocerca: GeocercaAR) {
        self.slug = slug
        self.restauranteNombre = restauranteNombre
        latitud = geocerca.latitud
        longitud = geocerca.longitud
        radioMetros = geocerca.radioMetros
        actualizadoEn = .now
    }

    var geocerca: GeocercaAR { GeocercaAR(latitud: latitud, longitud: longitud, radioMetros: radioMetros) }
}

enum LocalStore {
    static let schema: [any PersistentModel.Type] = [PreferenciasUsuario.self, BorradorPedido.self, CarritoGuardado.self,
                                                     UbicacionRestaurante.self, AjusteRestaurante.self, AjusteProducto.self,
                                                     AjusteBanner.self]

    static func makeContainer(inMemory: Bool) -> ModelContainer {
        // En el primer arranque Application Support no existe; crearlo evita errores de CoreData.
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: Schema(schema), configurations: config)
        } catch {
            // Si el almacén está dañado, se usa memoria para no bloquear la app.
            return try! ModelContainer(for: Schema(schema), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }
}
