import XCTest

/// Flujo de UI en modo demostración (sin backend, datos en memoria).
final class AdbanaARUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDemoAgregarAlCarritoYVerTotal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        abrirDemo(app)
        tocarProducto(app, 9001)

        let agregar = app.buttons["agregarCarrito"].firstMatch
        if !agregar.waitForExistence(timeout: 5) { print("JERARQUIA:\n" + app.debugDescription) }
        XCTAssertTrue(agregar.exists)
        agregar.tap()

        app.tabBars.buttons["Carrito"].tap()
        let total = app.staticTexts["totalEstimado"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("40"), "Total estimado: \(total.label)")

        app.buttons["continuarCheckout"].firstMatch.tap()
        XCTAssertFalse(app.buttons["enviarPedido"].firstMatch.isEnabled, "El modo demo no envía pedidos")
    }

    func testVisor3DEnSimulador() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirDemo(app)
        tocarProducto(app, 9001)
        let ver3D = app.buttons["ver3D"].firstMatch
        XCTAssertTrue(ver3D.waitForExistence(timeout: 5))
        ver3D.tap()
        XCTAssertTrue(app.buttons["cerrar3D"].firstMatch.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "visor-3d-demo"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["cerrar3D"].firstMatch.tap()
    }

    /// Quita ingredientes en el detalle y en el visor 3D; el carrito conserva la personalización.
    func testPersonalizarHamburguesaEn3DYCarrito() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirDemo(app)
        let burger = app.buttons["producto-9102"].firstMatch
        XCTAssertTrue(burger.waitForExistence(timeout: 5))
        burger.tap()

        let tomate = app.buttons["ingrediente-tomate"].firstMatch
        XCTAssertTrue(tomate.waitForExistence(timeout: 10), "El panel de ingredientes no apareció")
        tomate.tap()
        XCTAssertTrue(app.staticTexts["Tu plato: sin tomate"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["ingrediente-carne"].firstMatch.isEnabled, "La carne es obligatoria")

        app.buttons["ver3D"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cerrar3D"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        adjuntar(app, "visor-3d-hamburguesa-sin-tomate")
        app.buttons["ingrediente-cebolla"].firstMatch.tap()
        sleep(1)
        adjuntar(app, "visor-3d-hamburguesa-sin-tomate-ni-cebolla")
        app.buttons["cerrar3D"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Tu plato: sin tomate, sin cebolla"].waitForExistence(timeout: 3))
        app.buttons["agregarCarrito"].firstMatch.tap()
        app.tabBars.buttons["Carrito"].tap()
        XCTAssertTrue(app.staticTexts["sin tomate, sin cebolla"].waitForExistence(timeout: 5))
        adjuntar(app, "carrito-con-personalizacion")
    }

    func testVisor3DPolloCambiaGuarnicion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirDemo(app)
        app.buttons["producto-9103"].firstMatch.tap()
        let ver3D = app.buttons["ver3D"].firstMatch
        XCTAssertTrue(ver3D.waitForExistence(timeout: 10))
        ver3D.tap()
        XCTAssertTrue(app.buttons["cerrar3D"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        adjuntar(app, "visor-3d-pollo-papas")
        let ensalada = app.segmentedControls.buttons["Ensalada"].firstMatch
        ensalada.tap()
        sleep(1)
        XCTAssertTrue(ensalada.isSelected, "La guarnición no cambió")
        adjuntar(app, "visor-3d-pollo-ensalada")
    }

    /// En pantallas compactas el botón queda bajo la barra de pestañas: se desplaza antes de tocar.
    private func abrirDemo(_ app: XCUIApplication) {
        let demo = app.buttons["modoDemo"].firstMatch
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        app.swipeUp()
        demo.tap()
    }

    /// UITableView (CoreData) → Segue "mostrarDetalle" → UIViewController con IBOutlets.
    func testHistorialSegueAlDetalle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-historial"]
        app.launch()
        app.tabBars.buttons["Pedidos"].tap()
        let fila = app.cells["historial-4242"].firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 5), "La fila sembrada en CoreData no aparece")
        adjuntar(app, "uikit-historial-tabla")
        fila.tap()
        XCTAssertTrue(app.staticTexts["Pedido #4242 · En mesa"].waitForExistence(timeout: 5), "El Segue no mostró el detalle")
        XCTAssertTrue(app.staticTexts["Restaurante de prueba UI"].exists)
        XCTAssertTrue(app.staticTexts["Total: S/ 38.00 · Pagado: S/ 0.00"].exists)
        adjuntar(app, "uikit-historial-detalle-segue")
    }

    /// Desplaza la carta hasta que la fila no quede bajo la barra de pestañas.
    private func tocarProducto(_ app: XCUIApplication, _ id: Int) {
        let fila = app.buttons["producto-\(id)"].firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 5))
        var intentos = 0
        while fila.frame.maxY > app.frame.maxY - 140, intentos < 4 { app.swipeUp(velocity: .slow); intentos += 1 }
        fila.tap()
    }

    private func adjuntar(_ app: XCUIApplication, _ nombre: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = nombre
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testHistorialUIKitCarga() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Pedidos"].tap()
        XCTAssertTrue(app.tables["historialTable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Activos"].exists)
        app.segmentedControls.buttons["Activos"].tap()
    }
}
