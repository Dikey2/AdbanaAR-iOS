import RealityKit
import UIKit
import XCTest
@testable import AdbanaAR

@MainActor
final class DishCustomizationTests: XCTestCase {
    func testReferenciaRecetaSeResuelve() {
        XCTAssertEqual(DishRecipe.from(referencia: "receta:pizza")?.id, "pizza")
        XCTAssertNil(DishRecipe.from(referencia: "receta:inexistente"))
        XCTAssertNil(DishRecipe.from(referencia: "bundle:pizza.usdz"))
    }

    func testIdsDeIngredientesSonUnicos() {
        for receta in DishRecipe.catalogo {
            let ids = receta.ingredientes.map(\.id) + receta.variantes.flatMap { $0.opciones.map(\.id) }
            XCTAssertEqual(ids.count, Set(ids).count, "ids duplicados en \(receta.id)")
        }
    }

    func testQuitarOpcionalYRestaurar() {
        let p = DishCustomization(receta: .pizza)
        XCTAssertNil(p.resumen)
        p.alternar("champinones")
        XCTAssertFalse(p.incluido("champinones"))
        XCTAssertEqual(p.visibilidad["champinones"], false)
        XCTAssertEqual(p.visibilidad["queso"], true)
        XCTAssertEqual(p.resumen, "sin champiñones")
        p.restaurar()
        XCTAssertTrue(p.esPredeterminada)
        XCTAssertNil(p.resumen)
    }

    func testObligatorioNoSePuedeQuitar() {
        let p = DishCustomization(receta: .hamburguesa)
        p.alternar("carne")
        XCTAssertTrue(p.incluido("carne"))
        XCTAssertEqual(p.version, 0)
    }

    func testVarianteExcluyente() {
        let p = DishCustomization(receta: .pollo)
        XCTAssertEqual(p.visibilidad["papas"], true)
        XCTAssertEqual(p.visibilidad["arroz"], false)
        p.seleccionar(variante: "guarnicion", opcion: "arroz")
        XCTAssertEqual(p.visibilidad["papas"], false)
        XCTAssertEqual(p.visibilidad["arroz"], true)
        XCTAssertEqual(p.resumen, "guarnición: arroz")
        p.seleccionar(variante: "guarnicion", opcion: "no-existe")
        XCTAssertEqual(p.variantes["guarnicion"], "arroz")
    }

    func testModeloProceduralTieneComponentesYEscalaReal() {
        for receta in DishRecipe.catalogo {
            let root = ProceduralDishBuilder.build(receta)
            for id in receta.ingredientes.map(\.id) + receta.variantes.flatMap({ $0.opciones.map(\.id) }) {
                XCTAssertNotNil(root.findEntity(named: id), "\(receta.id) sin entidad \(id)")
            }
            let b = root.visualBounds(relativeTo: nil)
            // Unidad = metros: el ancho total debe coincidir con el diámetro del plato (±1 cm).
            XCTAssertEqual(max(b.extents.x, b.extents.z), receta.diametroPlato, accuracy: 0.01, receta.id)
            XCTAssertGreaterThanOrEqual(b.min.y, -0.0001, "\(receta.id) atraviesa la mesa")
        }
    }

    func testOcultarIngredienteNoAfectaOtros() {
        let root = ProceduralDishBuilder.build(.pizza)
        let p = DishCustomization(receta: .pizza)
        p.alternar("champinones")
        ProceduralDishBuilder.aplicar(p.visibilidad, recetaId: "pizza", a: root)
        XCTAssertEqual(root.findEntity(named: "champinones")?.isEnabled, false)
        XCTAssertEqual(root.findEntity(named: "aceitunas")?.isEnabled, true)
        XCTAssertEqual(root.findEntity(named: "queso")?.isEnabled, true)
    }

    func testHamburguesaSeReapilaAlQuitarCapa() {
        let root = ProceduralDishBuilder.build(.hamburguesa)
        let antes = root.findEntity(named: "pan_superior")!.position.y
        let p = DishCustomization(receta: .hamburguesa)
        p.alternar("tomate")
        ProceduralDishBuilder.aplicar(p.visibilidad, recetaId: "hamburguesa", a: root)
        let despues = root.findEntity(named: "pan_superior")!.position.y
        XCTAssertEqual(antes - despues, 0.006, accuracy: 0.0001)
    }

    func testCarritoGuardaPersonalizacionComoNota() {
        let cart = CartStore()
        cart.bind(slug: DemoCatalog.slug, restauranteNombre: "Demo")
        let pizza = DemoCatalog.todosLosProductos.first { $0.id == 9101 }!
        XCTAssertEqual(cart.add(pizza, cantidad: 2, slug: DemoCatalog.slug, personalizacion: "sin aceitunas"), .added)
        XCTAssertEqual(cart.notasPersonalizacion, "2× Pizza personalizable: sin aceitunas")
        // El precio no cambia por la personalización: sigue siendo el del producto.
        XCTAssertEqual(cart.estimatedTotal, pizza.precio.value * 2)
        // Las líneas antiguas sin el campo siguen decodificándose.
        let json = try! JSONEncoder().encode(cart.lines)
        let decoded = try! JSONDecoder().decode([CartLine].self, from: json)
        XCTAssertEqual(decoded.first?.personalizacion, "sin aceitunas")
    }

    func testDemoCatalogResuelveRecetas() async throws {
        let repo = ModelRepository()
        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        let pizza = DemoCatalog.todosLosProductos.first { $0.id == 9101 }!
        let fuente = try await repo.resolve(producto: pizza, slug: DemoCatalog.slug, api: api)
        XCTAssertEqual(fuente.receta?.id, "pizza")
        XCTAssertTrue(fuente.hasNativeModel)
    }

    /// Los platos fotorrealistas (CC0 Poly Haven) cargan desde el bundle a escala real, apoyados en la mesa.
    func testEscaneosCarganAEscalaReal() async throws {
        let repo = ModelRepository()
        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        let escaneos = DemoCatalog.todosLosProductos.filter { $0.modeloUSDZ?.hasPrefix("escaneo:") == true }
        XCTAssertEqual(escaneos.count, 18)
        for producto in escaneos {
            let fuente = try await repo.resolve(producto: producto, slug: "demo-test", api: api)
            guard case .escaneo = fuente else { return XCTFail("\(producto.nombre) no resolvió a escaneo") }
            let entidad = try await DishEntityFactory.load(fuente)
            let b = entidad.visualBounds(relativeTo: nil)
            let ancho = max(b.extents.x, b.extents.z)
            XCTAssertGreaterThan(ancho, 0.07, producto.nombre)
            XCTAssertLessThan(ancho, 0.55, producto.nombre)
            XCTAssertEqual(b.min.y, 0, accuracy: 0.002, producto.nombre)
        }
    }

    func testRestaurantesDemoTienenIdsUnicosYFotos() {
        let ids = DemoCatalog.todosLosProductos.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for r in DemoCatalog.restaurantes {
            XCTAssertTrue(DemoCatalog.esDemo(r.slug))
            XCTAssertNotNil(UIImage(named: r.portada), r.portada)
        }
    }

    /// Los platos escaneados compuestos exponen cada pieza como entidad y se pueden ocultar sin tocar las demás.
    func testEscaneosConPiezasSeparables() async throws {
        let repo = ModelRepository()
        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        for receta in DishRecipe.escaneos {
            let nombre = String(receta.id.dropFirst("escaneo-".count))
            let producto = DemoCatalog.todosLosProductos.first { $0.modeloUSDZ == "escaneo:" + nombre }
            XCTAssertNotNil(producto, "Ningún producto usa \(nombre)")
            guard let producto else { continue }
            let fuente = try await repo.resolve(producto: producto, slug: "demo-test", api: api)
            XCTAssertEqual(fuente.receta?.id, receta.id)
            let entidad = try await DishEntityFactory.load(fuente)
            for ing in receta.ingredientes {
                XCTAssertNotNil(entidad.findEntity(named: ing.id), "\(nombre): falta la pieza \(ing.id)")
            }
            let opcional = receta.opcionales.first!
            let p = DishCustomization(receta: receta)
            p.alternar(opcional.id)
            ProceduralDishBuilder.aplicar(p.visibilidad, recetaId: receta.id, a: entidad)
            XCTAssertEqual(entidad.findEntity(named: opcional.id)?.isEnabled, false)
            for otro in receta.ingredientes where otro.id != opcional.id {
                XCTAssertEqual(entidad.findEntity(named: otro.id)?.isEnabled, true, "\(nombre): \(otro.id) no debió ocultarse")
            }
        }
    }
}
