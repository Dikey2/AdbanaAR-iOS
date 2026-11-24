import CoreLocation
import SwiftData
import XCTest
@testable import AdbanaAR

final class GeocercaARTests: XCTestCase {
    // Punto de referencia arbitrario para la prueba (no corresponde a un local real).
    private let zona = GeocercaAR(latitud: -12.0464, longitud: -77.0428, radioMetros: 50)

    private func lectura(desplazamientoNorte metros: Double, precision: Double) -> CLLocation {
        // 1° de latitud ≈ 111 320 m
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: zona.latitud + metros / 111_320, longitude: zona.longitud),
                   altitude: 0, horizontalAccuracy: precision, verticalAccuracy: 5, timestamp: .now)
    }

    func testDentroDelRadio() {
        guard case .dentro(let d) = zona.evaluar(lectura(desplazamientoNorte: 30, precision: 10)) else { return XCTFail() }
        XCTAssertEqual(d, 30, accuracy: 1)
    }

    func testFueraDelRadio() {
        guard case .fuera(let d) = zona.evaluar(lectura(desplazamientoNorte: 400, precision: 10)) else { return XCTFail() }
        XCTAssertEqual(d, 400, accuracy: 5) // la conversión grados→metros es aproximada
    }

    func testToleranciaPorPrecisionTieneTope() {
        // A 70 m con ±25 m: entra por tolerancia (50 + 25).
        if case .dentro = zona.evaluar(lectura(desplazamientoNorte: 70, precision: 25)) {} else { XCTFail("debió entrar") }
        // A 90 m con ±90 m: la tolerancia se limita a 30 m, queda fuera.
        if case .fuera = zona.evaluar(lectura(desplazamientoNorte: 90, precision: 90)) {} else { XCTFail("debió quedar fuera") }
    }

    func testPrecisionInsuficienteNoDecide() {
        XCTAssertEqual(zona.evaluar(lectura(desplazamientoNorte: 0, precision: 500)), .precisionInsuficiente(precision: 500))
        XCTAssertEqual(zona.evaluar(lectura(desplazamientoNorte: 0, precision: -1)), .precisionInsuficiente(precision: -1))
    }

    func testRadioSeAcotaYCoordenadaCeroEsInvalida() {
        XCTAssertEqual(GeocercaAR(latitud: 1, longitud: 1, radioMetros: 2).radioMetros, GeocercaAR.radioMinimo)
        XCTAssertEqual(GeocercaAR(latitud: 1, longitud: 1, radioMetros: 9_999).radioMetros, GeocercaAR.radioMaximo)
        XCTAssertFalse(GeocercaAR(latitud: 0, longitud: 0, radioMetros: 50).esValida)
    }

    func testConfiguracionDecodificaUbicacionARYToleraValorMalFormado() throws {
        let ok = #"{"descripcion":"x","ubicacion_ar":{"latitud":-12.1,"longitud":-77.0,"radio_metros":80}}"#
        let c = try JSONDecoder().decode(ConfiguracionDTO.self, from: Data(ok.utf8))
        XCTAssertEqual(c.ubicacionAR, GeocercaAR(latitud: -12.1, longitud: -77.0, radioMetros: 80))
        let malo = #"{"descripcion":"x","ubicacion_ar":"en el local"}"#
        let c2 = try JSONDecoder().decode(ConfiguracionDTO.self, from: Data(malo.utf8))
        XCTAssertNil(c2.ubicacionAR)
        XCTAssertEqual(c2.descripcion, "x")
    }

    @MainActor
    func testUbicacionRestauranteSePersisteEnSwiftData() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(UbicacionRestaurante(slug: "demo-test", restauranteNombre: "Prueba", geocerca: zona))
        try ctx.save()
        let slug = "demo-test"
        let leida = try ctx.fetch(FetchDescriptor<UbicacionRestaurante>(predicate: #Predicate { $0.slug == slug })).first
        XCTAssertEqual(leida?.geocerca, zona)
        XCTAssertEqual(leida?.arActiva, true, "Al afiliar, la AR queda activa por defecto")
        leida?.arActiva = false
        try ctx.save()
        let otra = try ctx.fetch(FetchDescriptor<UbicacionRestaurante>(predicate: #Predicate { $0.slug == slug })).first
        XCTAssertEqual(otra?.arActiva, false)
        XCTAssertEqual(otra?.geocerca, zona, "Desactivar la AR no borra la ubicación")
    }
}

@MainActor
final class SimuladorPedidosTests: XCTestCase {
    func testEstadoAvanzaConElTiempoYSePagaAlEntregar() {
        let sim = SimuladorPedidos(persistir: false)
        var reloj = Date(timeIntervalSince1970: 1_000_000)
        sim.ahora = { reloj }
        let producto = DemoCatalog.todosLosProductos.first { $0.id == 9102 }!
        let r = sim.crear(slug: "demo-barrio-burger", restaurante: "Barrio Burger", tipo: .delivery,
                          lineas: [CartLine(producto: producto, cantidad: 2, personalizacion: nil)])
        XCTAssertEqual(r.total.description, "48.00")
        XCTAssertEqual(sim.estado(pedidoId: r.pedidoId), .pendiente)
        reloj += 31
        XCTAssertEqual(sim.estado(pedidoId: r.pedidoId), .preparando)
        XCTAssertEqual(sim.seguimiento(pedidoId: r.pedidoId)?.pagado.description, "0.00")
        reloj += 200
        XCTAssertEqual(sim.estado(pedidoId: r.pedidoId), .entregado)
        XCTAssertEqual(sim.seguimiento(pedidoId: r.pedidoId)?.pagado.description, "48.00")
        XCTAssertEqual(sim.seguimiento(pedidoId: r.pedidoId)?.tipo, "delivery")
    }

    func testAvanzarSaltaUnEstadoCadaVez() {
        let sim = SimuladorPedidos(persistir: false)
        let producto = DemoCatalog.todosLosProductos.first { $0.id == 9101 }!
        let r = sim.crear(slug: "demo-forno-napoli", restaurante: "Forno Napoli", tipo: .recojo,
                          lineas: [CartLine(producto: producto, cantidad: 1, personalizacion: nil)])
        for esperado in [OrderStatus.confirmado, .preparando, .listo, .entregado, .entregado] {
            sim.avanzar(pedidoId: r.pedidoId)
            XCTAssertEqual(sim.estado(pedidoId: r.pedidoId), esperado)
        }
        XCTAssertEqual(OrderStatus.listo.titulo(para: .recojo), "Listo para recoger")
        XCTAssertEqual(OrderStatus.listo.titulo(para: .delivery), "En camino")
        XCTAssertEqual(OrderStatus.entregado.titulo(para: .recojo), "Recogido")
    }
}

@MainActor
final class AdminPINTests: XCTestCase {
    func testPINSeValidaYSeGuardaComoHash() {
        XCTAssertTrue(AppEnvironment.pinValido("2468"))
        XCTAssertFalse(AppEnvironment.pinValido("12"))
        XCTAssertFalse(AppEnvironment.pinValido("12ab"))
        let h = AppEnvironment.hashPIN("2468")
        XCTAssertEqual(h.count, 64)
        XCTAssertFalse(h.contains("2468"))
        XCTAssertNotEqual(h, AppEnvironment.hashPIN("2469"))
    }
}
