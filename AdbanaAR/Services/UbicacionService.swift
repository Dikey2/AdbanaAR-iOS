import CoreLocation
import Foundation
import Observation

/// Ubicación del cliente (solo "mientras se usa la app") para validar la geocerca AR
/// y para que el restaurante fije su posición al afiliarse. No se guarda ni se envía.
@MainActor
@Observable
final class UbicacionService: NSObject, CLLocationManagerDelegate {
    enum UbicacionError: LocalizedError {
        case sinPermiso, noDisponible(String)
        var errorDescription: String? {
            switch self {
            case .sinPermiso: return "Activa el permiso de ubicación en Ajustes para usar la realidad aumentada en el restaurante."
            case .noDisponible(let m): return "No se pudo obtener tu ubicación: \(m)"
            }
        }
    }

    private let manager = CLLocationManager()
    private var esperaPermiso: [CheckedContinuation<Void, Never>] = []
    private var esperaUbicacion: [CheckedContinuation<CLLocation, Error>] = []
    private(set) var ultima: CLLocation?
    private(set) var siguiendo = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var autorizado: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    /// Una lectura actual (pide permiso la primera vez). Descarta lecturas en caché de más de 15 s.
    func ubicacionActual() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { esperaPermiso.append($0); manager.requestWhenInUseAuthorization() }
        }
        guard autorizado else { throw UbicacionError.sinPermiso }
        if let ultima, -ultima.timestamp.timeIntervalSinceNow < 15, ultima.horizontalAccuracy <= 65 { return ultima }
        return try await withCheckedThrowingContinuation { c in
            esperaUbicacion.append(c)
            manager.requestLocation()
        }
    }

    /// Lecturas continuas mientras la sesión AR está abierta.
    func seguir(_ activo: Bool) {
        guard autorizado else { return }
        siguiendo = activo
        activo ? manager.startUpdatingLocation() : manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            let pendientes = esperaPermiso; esperaPermiso = []
            pendientes.forEach { $0.resume() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            ultima = l
            let pendientes = esperaUbicacion; esperaUbicacion = []
            pendientes.forEach { $0.resume(returning: l) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // kCLErrorLocationUnknown es transitorio durante el seguimiento continuo.
            if (error as? CLError)?.code == .locationUnknown, siguiendo { return }
            let pendientes = esperaUbicacion; esperaUbicacion = []
            pendientes.forEach { $0.resume(throwing: UbicacionError.noDisponible(error.localizedDescription)) }
        }
    }
}
