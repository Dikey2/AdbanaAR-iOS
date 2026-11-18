import XCTest
@testable import AdbanaAR

@MainActor
final class OrderTests: XCTestCase {
    private func producto(_ id: Int, _ precio: String, disponible: Bool = true) -> ProductoDTO {
        ProductoDTO(id: id, nombre: "P\(id)", descripcion: nil, precio: DecimalString(Decimal(string: precio)!),
                    imagen: nil, modelo3D: nil, modeloUSDZ: nil, disponible: disponible)
    }

    // MARK: Carrito

    func testTotalEstimadoConDecimal() {
        let cart = CartStore()
        cart.bind(slug: "r", restauranteNombre: "R")
        cart.add(producto(1, "42.50"), cantidad: 2, slug: "r")
        cart.add(producto(2, "0.10"), cantidad: 3, slug: "r")
        XCTAssertEqual(cart.estimatedTotal, Decimal(string: "85.30"))
        XCTAssertEqual(cart.totalUnits, 5)
    }

    func testLimitesDelCarrito() {
        let cart = CartStore()
        cart.bind(slug: "r", restauranteNombre: "R")
        XCTAssertEqual(cart.add(producto(1, "1"), cantidad: 100, slug: "r"), .added)
        if case .limitReached = cart.add(producto(1, "1"), cantidad: 1, slug: "r") {} else { XCTFail() }
        XCTAssertEqual(cart.add(producto(2, "1", disponible: false), slug: "r"), .unavailable)
        XCTAssertEqual(cart.add(producto(3, "1"), slug: "otro"), .otherRestaurant)
        for i in 10..<59 { cart.add(producto(i, "1"), slug: "r") }
        XCTAssertEqual(cart.lines.count, 50)
        if case .limitReached = cart.add(producto(99, "1"), slug: "r") {} else { XCTFail() }
    }

    func testCambiarRestauranteVaciaCarrito() {
        let cart = CartStore()
        cart.bind(slug: "a", restauranteNombre: "A")
        cart.add(producto(1, "1"), slug: "a")
        cart.bind(slug: "b", restauranteNombre: "B")
        XCTAssertTrue(cart.isEmpty)
    }

    // MARK: Validación

    func testValidacionPorModalidad() {
        var f = OrderForm()
        let items = [PedidoRequest.Item(productoId: 1, cantidad: 1)]
        f.tipo = .mesa
        var e = f.validate(modalidades: Modalidad.allCases, items: items)
        XCTAssertNotNil(e[.clienteNombre]); XCTAssertNotNil(e[.mesa])
        f.clienteNombre = "Ana"; f.tipo = .delivery
        e = f.validate(modalidades: Modalidad.allCases, items: items)
        XCTAssertNotNil(e[.direccion]); XCTAssertNotNil(e[.telefono]); XCTAssertNil(e[.mesa])
        f.tipo = .recojo
        XCTAssertTrue(f.validate(modalidades: Modalidad.allCases, items: items).isEmpty)
        XCTAssertNotNil(f.validate(modalidades: [.mesa], items: items)[.tipo])
        XCTAssertNotNil(f.validate(modalidades: Modalidad.allCases, items: [])[.items])
        f.notas = String(repeating: "a", count: 501)
        XCTAssertNotNil(f.validate(modalidades: Modalidad.allCases, items: items)[.notas])
    }

    func testRequestSoloIncluyeCamposDeLaModalidad() {
        var f = OrderForm()
        f.clienteNombre = "  Ana  "; f.tipo = .recojo; f.mesa = "Mesa 01"; f.direccion = "x"
        let r = f.makeRequest(clave: UUID(), items: [.init(productoId: 1, cantidad: 1)])
        XCTAssertEqual(r.clienteNombre, "Ana")
        XCTAssertNil(r.mesa); XCTAssertNil(r.direccion); XCTAssertNil(r.clienteTelefono)
        XCTAssertEqual(r.claveOperacion, r.claveOperacion.lowercased())
    }

    // MARK: Idempotencia

    private func makeService() -> (OrderSubmissionService, InMemoryPendingOrderStore, HistorialStore) {
        MockURLProtocol.reset()
        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!, session: MockURLProtocol.session())
        let store = InMemoryPendingOrderStore()
        let historial = HistorialStore(inMemory: true)
        let svc = OrderSubmissionService(api: api, store: store, historial: historial,
                                         keychain: KeychainStore(service: "tests.\(UUID().uuidString)"))
        return (svc, store, historial)
    }

    private func intent(_ svc: OrderSubmissionService) throws -> OrderIntent {
        var f = OrderForm(); f.clienteNombre = "Ana"; f.tipo = .mesa; f.mesa = "Mesa 01"
        return try svc.makeIntent(form: f, items: [.init(productoId: 1, cantidad: 2)], slug: "adbana-demo-ios",
                                  restauranteNombre: "Demo", notaVozArchivo: nil)
    }

    func testReintentoEnviaMismaClaveYMismoCuerpo() async throws {
        let (svc, store, historial) = makeService()
        let i = try intent(svc)
        XCTAssertNotNil(store.items[i.clave], "La intención se guarda ANTES del primer envío")

        MockURLProtocol.failWithError = URLError(.networkConnectionLost)
        let r1 = await svc.submit(i)
        guard case .retryable(_, let pendiente) = r1 else { return XCTFail("\(r1)") }
        XCTAssertEqual(pendiente, i)
        XCTAssertNotNil(store.items[i.clave], "Se conserva para reintentar")

        MockURLProtocol.failWithError = nil
        MockURLProtocol.handler = { _ in .init(status: 201, body: Fixture.data("pedido_201")) }
        let r2 = await svc.submit(pendiente)
        guard case .created(let creado) = r2 else { return XCTFail("\(r2)") }
        XCTAssertEqual(creado.pedidoId, 1)

        XCTAssertEqual(MockURLProtocol.bodies.count, 2)
        XCTAssertEqual(MockURLProtocol.bodies[0], MockURLProtocol.bodies[1], "Cuerpo idéntico byte a byte")
        let enviado = try JSONDecoder().decode(PedidoRequest.self, from: MockURLProtocol.bodies[1])
        XCTAssertEqual(enviado.claveOperacion, i.clave)
        XCTAssertNil(store.items[i.clave], "Se elimina al confirmar")
        XCTAssertEqual(historial.fetch().first?.pedidoId, 1)
        XCTAssertEqual(historial.fetch().first?.total, "85.00")
    }

    func testNuevaIntencionGeneraNuevaClave() throws {
        let (svc, _, _) = makeService()
        XCTAssertNotEqual(try intent(svc).clave, try intent(svc).clave)
    }

    func testRechazosNoSeReintentan() async throws {
        for (status, fixture) in [(409, "pedido_409"), (422, "pedido_422")] {
            let (svc, store, historial) = makeService()
            let i = try intent(svc)
            MockURLProtocol.handler = { _ in .init(status: status, body: Fixture.data(fixture)) }
            let r = await svc.submit(i)
            guard case .rejected(let e) = r else { return XCTFail("\(status): \(r)") }
            XCTAssertEqual(e.statusCode, status)
            XCTAssertNil(store.items[i.clave])
            XCTAssertTrue(historial.fetch().isEmpty)
        }
    }

    func test429Y500SonReintentables() async throws {
        for status in [429, 500, 503] {
            let (svc, store, _) = makeService()
            let i = try intent(svc)
            MockURLProtocol.handler = { _ in .init(status: status, body: Data("{}".utf8)) }
            guard case .retryable = await svc.submit(i) else { return XCTFail("\(status)") }
            XCTAssertEqual(store.failures[i.clave], 1)
        }
    }
}
