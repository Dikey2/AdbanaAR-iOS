import XCTest
@testable import AdbanaAR

/// Las fixtures son respuestas reales del backend local (token redactado).
final class DTODecodingTests: XCTestCase {
    func testCartaRealSeDecodifica() throws {
        let carta = try JSONDecoder().decode(CartaResponse.self, from: Fixture.data("carta"))
        XCTAssertEqual(carta.restaurante.slug, "adbana-demo-ios")
        XCTAssertEqual(carta.restaurante.modalidades, [.mesa, .recojo, .delivery])
        XCTAssertFalse(carta.carta.isEmpty)
        let productos = carta.carta.flatMap(\.productos)
        let pizza = try XCTUnwrap(productos.first { $0.nombre.contains("Pizza") })
        XCTAssertEqual(pizza.precio.value, Decimal(string: "42.50"))
        XCTAssertEqual(pizza.modelo3D, "/api/carta/adbana-demo-ios/productos/1/modelo")
        XCTAssertNil(pizza.modeloUSDZ)
        XCTAssertTrue(productos.contains { !$0.disponible }, "Chicha Morada tiene stock 0")
        XCTAssertEqual(carta.mesas?.count, 6)
    }

    func testConfiguracionVaciaComoArregloPHP() throws {
        let json = #"{"nombre":"X","slug":"x","telefono":null,"configuracion":[]}"#
        let r = try JSONDecoder().decode(RestauranteDTO.self, from: Data(json.utf8))
        XCTAssertNil(r.configuracion)
        XCTAssertEqual(r.modalidades, Modalidad.allCases, "Sin configuración, el backend admite las tres")
    }

    func testPedidoCreadoReal() throws {
        let r = try JSONDecoder().decode(PedidoCreadoResponse.self, from: Fixture.data("pedido_201"))
        XCTAssertEqual(r.pedidoId, 1)
        XCTAssertEqual(r.estado, "pendiente")
        XCTAssertEqual(r.total.description, "85.00")
        XCTAssertEqual(r.items.first?.precioUnitario.description, "42.50")
        XCTAssertNotNil(r.seguimientoToken)
    }

    func testSeguimientoReal() throws {
        let s = try JSONDecoder().decode(SeguimientoResponse.self, from: Fixture.data("seguimiento"))
        XCTAssertEqual(s.estado, "pendiente")
        XCTAssertEqual(s.pagado.description, "0.00")
        XCTAssertEqual(s.tipo, "mesa")
    }

    func testDecimalAceptaNumero() throws {
        let d = try JSONDecoder().decode([DecimalString].self, from: Data("[12, 9.5, \"3.10\"]".utf8))
        XCTAssertEqual(d.map(\.description), ["12.00", "9.50", "3.10"])
    }

    func testPedidoRequestOmiteOpcionalesNulos() throws {
        let req = PedidoRequest(claveOperacion: "k", clienteNombre: "Ana", tipo: .recojo, mesa: nil,
                                direccion: nil, clienteTelefono: nil, notas: nil,
                                items: [.init(productoId: 1, cantidad: 2)])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as! [String: Any]
        XCTAssertEqual(Set(obj.keys), ["clave_operacion", "cliente_nombre", "tipo", "items"])
        let item = (obj["items"] as! [[String: Any]])[0]
        XCTAssertEqual(item["producto_id"] as? Int, 1)
    }
}
