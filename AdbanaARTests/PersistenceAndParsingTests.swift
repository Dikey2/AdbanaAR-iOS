import SwiftData
import XCTest
@testable import AdbanaAR

final class QRLinkParserTests: XCTestCase {
    func testFormatosReales() {
        XCTAssertEqual(QRLinkParser.parse("https://x.nip.io/c/mi-resto?mesa=D9428888-122B-4A77-9C09-CBC6D2CB3A01"),
                       .init(slug: "mi-resto", mesaCodigo: "d9428888-122b-4a77-9c09-cbc6d2cb3a01"))
        XCTAssertEqual(QRLinkParser.parse("http://localhost:8080/m/adbana-demo-ios"), .init(slug: "adbana-demo-ios", mesaCodigo: nil))
        XCTAssertEqual(QRLinkParser.parse("adbana-demo-ios"), .init(slug: "adbana-demo-ios", mesaCodigo: nil))
        XCTAssertEqual(QRLinkParser.parse("https://x/c/resto?mesa=4")?.mesaCodigo, nil, "Mesa no UUID se descarta")
    }

    func testRechazaContenidoAjeno() {
        XCTAssertNil(QRLinkParser.parse("https://evil.example.com/login"))
        XCTAssertNil(QRLinkParser.parse("https://x/c/../../etc"))
        XCTAssertNil(QRLinkParser.parse("WIFI:S:red;T:WPA;P:clave;;"))
    }
}

final class HistorialStoreTests: XCTestCase {
    func testUpsertActualizaYFiltra() {
        let s = HistorialStore(inMemory: true)
        s.upsert(pedidoId: 1, slug: "r", restauranteNombre: "R", total: "10.00", estado: "pendiente", tipo: "mesa")
        s.upsert(pedidoId: 2, slug: "r", restauranteNombre: "R", total: "20.00", estado: "pendiente", tipo: "recojo")
        s.upsert(pedidoId: 1, slug: "r", restauranteNombre: "R", total: "10.00", estado: "pendiente", tipo: "mesa")
        XCTAssertEqual(s.fetch().count, 2, "Clave única slug+pedidoId")
        s.updateEstado(slug: "r", pedidoId: 2, estado: "entregado", pagado: "20.00", total: "20.00")
        XCTAssertEqual(s.fetch(filtro: .activos).map(\.pedidoId), [1])
        XCTAssertEqual(s.fetch(filtro: .finalizados).first?.pagado, "20.00")
        s.delete(slug: "r", pedidoId: 1)
        XCTAssertEqual(s.fetch().count, 1)
    }
}

@MainActor
final class SwiftDataTests: XCTestCase {
    func testBorradorPedidoConservaCuerpoExacto() throws {
        let container = LocalStore.makeContainer(inMemory: true)
        let store = SwiftDataPendingOrderStore(context: container.mainContext)
        let body = Data(#"{"clave_operacion":"k1","items":[]}"#.utf8)
        let intent = OrderIntent(clave: "k1", slug: "r", restauranteNombre: "R", body: body, notaVozArchivo: nil)
        store.save(intent)
        // Guardar de nuevo con otro cuerpo NO debe sobrescribir la clave existente.
        store.save(OrderIntent(clave: "k1", slug: "r", restauranteNombre: "R", body: Data("otro".utf8), notaVozArchivo: nil))
        XCTAssertEqual(store.pending(slug: "r")?.body, body)
        store.recordFailure(clave: "k1", message: "timeout")
        let b = try container.mainContext.fetch(FetchDescriptor<BorradorPedido>()).first
        XCTAssertEqual(b?.intentos, 1)
        store.remove(clave: "k1")
        XCTAssertNil(store.pending(slug: "r"))
    }

    func testPreferenciasPorDefecto() {
        let p = PreferenciasUsuario()
        XCTAssertNil(p.apiBaseURL)
        XCTAssertEqual(p.modalidadPreferida, "mesa")
    }
}

final class KeychainStoreTests: XCTestCase {
    func testGuardaLeeYBorra() {
        let k = KeychainStore(service: "tests.\(UUID().uuidString)")
        let acc = KeychainStore.account(slug: "r", pedidoId: 7)
        XCTAssertEqual(acc, "r#7")
        k.set("token-1", account: acc)
        k.set("token-2", account: acc)
        XCTAssertEqual(k.get(account: acc), "token-2")
        k.delete(account: acc)
        XCTAssertNil(k.get(account: acc))
    }
}

@MainActor
final class DishEntityTests: XCTestCase {
    func testPizzaIncluidaSeNormalizaADiametroReferencia() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "pizza", withExtension: "usdz"))
        let e = try await DishEntityFactory.load(.usdz(url, origen: "test"))
        let b = e.visualBounds(relativeTo: nil)
        XCTAssertEqual(max(b.extents.x, b.extents.z), DishEntityFactory.diametroReferencia, accuracy: 0.01)
        XCTAssertEqual(b.min.y, 0, accuracy: 0.005, "Apoyado sobre la mesa")
    }

    func testPlaceholderSinModelo() async throws {
        let e = try await DishEntityFactory.load(.none)
        XCTAssertEqual(e.name, "plato-generico")
    }
}
