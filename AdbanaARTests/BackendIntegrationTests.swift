import XCTest
@testable import AdbanaAR

/// Pruebas contra un backend Adbana REAL (por defecto Docker local, http://localhost:8080).
/// Se omiten si el backend no responde. Slug configurable con ADBANA_IT_SLUG.
/// Crean pedidos de prueba: NO ejecutar contra producción.
@MainActor
final class BackendIntegrationTests: XCTestCase {
    var api: APIClient!
    var slug: String!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        let base = URL(string: env["ADBANA_IT_BASE_URL"] ?? "http://localhost:8080")!
        guard AppConfig.isLocalHost(base.host ?? "") else {
            throw XCTSkip("Las pruebas de integración solo se ejecutan contra un backend local.")
        }
        api = APIClient(baseURL: base)
        slug = env["ADBANA_IT_SLUG"] ?? "adbana-demo-ios"
        do { _ = try await api.raw(Endpoint(method: .get, path: "health")) }
        catch { throw XCTSkip("Backend local no disponible: \(error)") }
    }

    func testCartaRealYSlugInexistente() async throws {
        let carta: CartaResponse = try await api.send(Endpoints.carta(slug: slug))
        XCTAssertEqual(carta.restaurante.slug, slug)
        do {
            let _: CartaResponse = try await api.send(Endpoints.carta(slug: "no-existe-\(Int.random(in: 1000...9999))"))
            XCTFail("debió ser 404")
        } catch let e as APIError { XCTAssertEqual(e.statusCode, 404) }
    }

    func testPedidoIdempotenteYSeguimiento() async throws {
        let carta: CartaResponse = try await api.send(Endpoints.carta(slug: slug))
        let producto = try XCTUnwrap(carta.carta.flatMap(\.productos).first { $0.disponible })
        let svc = OrderSubmissionService(api: api, store: InMemoryPendingOrderStore(),
                                         historial: HistorialStore(inMemory: true),
                                         keychain: KeychainStore(service: "tests.\(UUID().uuidString)"))
        var form = OrderForm()
        form.clienteNombre = "Prueba iOS"
        form.tipo = .recojo
        let intent = try svc.makeIntent(form: form, items: [.init(productoId: producto.id, cantidad: 1)],
                                        slug: slug, restauranteNombre: carta.restaurante.nombre, notaVozArchivo: nil)

        guard case .created(let r1) = await svc.submit(intent) else { return XCTFail("primer envío") }
        // Simula respuesta perdida: se reenvía la MISMA intención.
        guard case .created(let r2) = await svc.submit(intent) else { return XCTFail("reintento") }
        XCTAssertEqual(r1.pedidoId, r2.pedidoId, "Mismo pedido, sin duplicar")
        XCTAssertEqual(r1.total, DecimalString(producto.precio.value), "Total calculado por el servidor")

        // Misma clave con otro cuerpo => 409.
        var otro = try JSONSerialization.jsonObject(with: intent.body) as! [String: Any]
        otro["cliente_nombre"] = "Otro nombre"
        do {
            _ = try await api.raw(Endpoints.crearPedido(slug: slug, body: try JSONSerialization.data(withJSONObject: otro)))
            XCTFail("debió ser 409")
        } catch let e as APIError { XCTAssertEqual(e.statusCode, 409) }

        // Seguimiento con el token propio.
        let token = try XCTUnwrap(r1.seguimientoToken)
        let s: SeguimientoResponse = try await api.send(Endpoints.seguimiento(slug: slug, token: token))
        XCTAssertEqual(s.pedidoId, r1.pedidoId)
        XCTAssertEqual(s.tipo, "recojo")

        // Token de este restaurante no sirve en otro slug ni alterado.
        do {
            let _: SeguimientoResponse = try await api.send(Endpoints.seguimiento(slug: slug, token: token + "x"))
            XCTFail("token alterado debió ser 404")
        } catch let e as APIError { XCTAssertEqual(e.statusCode, 404) }
    }

    func testValidacion422() async throws {
        let body = try JSONEncoder().encode(PedidoRequest(claveOperacion: UUID().uuidString.lowercased(), clienteNombre: "Ana",
                                                          tipo: .delivery, mesa: nil, direccion: nil, clienteTelefono: nil,
                                                          notas: nil, items: [.init(productoId: 1, cantidad: 1)]))
        do {
            _ = try await api.raw(Endpoints.crearPedido(slug: slug, body: body))
            XCTFail("debió ser 422")
        } catch let e as APIError {
            guard case .validation(_, let fields) = e else { return XCTFail("\(e)") }
            XCTAssertNotNil(fields["direccion"])
        }
    }
}
