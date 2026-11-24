import CoreLocation
import Foundation

/// Zona donde un restaurante afiliado permite la realidad aumentada: un círculo
/// (centro + radio en metros) alrededor del local. Fuera de él solo se ofrece el visor 3D.
struct GeocercaAR: Codable, Equatable, Hashable, Sendable {
    let latitud: Double
    let longitud: Double
    let radioMetros: Double

    static let radioMinimo: Double = 20
    static let radioMaximo: Double = 500
    /// Lecturas con un error mayor no permiten decidir si el cliente está dentro del local.
    static let precisionMaxima: Double = 100

    private enum CodingKeys: String, CodingKey {
        case latitud, longitud
        case radioMetros = "radio_metros"
    }

    init(latitud: Double, longitud: Double, radioMetros: Double) {
        self.latitud = latitud
        self.longitud = longitud
        self.radioMetros = min(max(radioMetros, Self.radioMinimo), Self.radioMaximo)
    }

    var esValida: Bool { CLLocationCoordinate2DIsValid(centro) && !(latitud == 0 && longitud == 0) }
    var centro: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitud, longitude: longitud) }

    enum Resultado: Equatable {
        case dentro(distancia: Double)
        case fuera(distancia: Double)
        case precisionInsuficiente(precision: Double)
    }

    /// Considera la imprecisión del GPS con una tolerancia de hasta 30 m: en interiores
    /// el error suele crecer y un cliente sentado en la mesa no debe quedar fuera.
    func evaluar(_ ubicacion: CLLocation) -> Resultado {
        let precision = ubicacion.horizontalAccuracy
        guard precision >= 0, precision <= Self.precisionMaxima else {
            return .precisionInsuficiente(precision: precision)
        }
        let distancia = ubicacion.distance(from: CLLocation(latitude: latitud, longitude: longitud))
        return distancia <= radioMetros + min(precision, 30) ? .dentro(distancia: distancia) : .fuera(distancia: distancia)
    }

    static func formatear(metros: Double) -> String {
        metros < 1000 ? "\(Int(metros.rounded())) m" : String(format: "%.1f km", metros / 1000)
    }
}
