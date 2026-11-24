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
        XCTAssertTrue(app.buttons["enviarPedido"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Carta → agregar (barra fija) → "Ver carrito" → checkout delivery → seguimiento hasta "Entregado".
    func testPedidoDeliveryHastaEntrega() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirRestaurante(app, "demo-dulce-nube")
        tocarProducto(app, 9201)
        let agregar = app.buttons["agregarCarrito"].firstMatch
        XCTAssertTrue(agregar.waitForExistence(timeout: 10))
        agregar.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let verCarrito = app.buttons["verCarritoDesdeCarta"].firstMatch
        XCTAssertTrue(verCarrito.waitForExistence(timeout: 5), "La carta debe mostrar la barra del carrito")
        adjuntar(app, "carta-con-carrito")
        verCarrito.tap()
        app.buttons["continuarCheckout"].firstMatch.tap()

        let nombre = app.textFields["nombreCliente"].firstMatch
        XCTAssertTrue(nombre.waitForExistence(timeout: 5))
        nombre.tap(); nombre.typeText("Cliente Demo")
        app.buttons["Delivery"].firstMatch.tap()
        let direccion = app.textFields["Dirección"].firstMatch
        XCTAssertTrue(direccion.waitForExistence(timeout: 3))
        direccion.tap(); direccion.typeText("Calle de prueba 123")
        let telefono = app.textFields["Teléfono"].firstMatch
        telefono.tap(); telefono.typeText("999999999")
        app.buttons["enviarPedido"].firstMatch.tap()

        let estado = app.staticTexts["estadoPedido"].firstMatch
        XCTAssertTrue(estado.waitForExistence(timeout: 10))
        XCTAssertEqual(estado.label, "Recibido")
        adjuntar(app, "seguimiento-delivery-recibido")
        avanzarHasta(app, "En camino")
        adjuntar(app, "seguimiento-delivery-en-camino")
        avanzarHasta(app, "Entregado")
        adjuntar(app, "seguimiento-delivery-entregado")

        // El pedido queda en el historial UIKit con su estado final.
        app.tabBars.buttons["Pedidos"].tap()
        XCTAssertTrue(app.tables["historialTable"].cells.firstMatch.waitForExistence(timeout: 5))
    }

    /// Recojo en el local: el número de pedido se muestra para el mostrador y termina en "Recogido".
    func testPedidoRecojoHastaRecogido() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirRestaurante(app, "demo-barrio-burger")
        tocarProducto(app, 9411)
        let agregar = app.buttons["agregarCarrito"].firstMatch
        XCTAssertTrue(agregar.waitForExistence(timeout: 10))
        agregar.tap()
        app.tabBars.buttons["Carrito"].tap()
        app.buttons["continuarCheckout"].firstMatch.tap()
        let nombre = app.textFields["nombreCliente"].firstMatch
        XCTAssertTrue(nombre.waitForExistence(timeout: 5))
        nombre.tap(); nombre.typeText("Cliente Demo")
        app.buttons["Recojo"].firstMatch.tap()
        app.buttons["enviarPedido"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["estadoPedido"].firstMatch.waitForExistence(timeout: 10))
        avanzarHasta(app, "Listo para recoger")
        XCTAssertTrue(app.staticTexts["Muestra este número"].exists)
        adjuntar(app, "seguimiento-recojo-listo")
        avanzarHasta(app, "Recogido")
    }

    private func avanzarHasta(_ app: XCUIApplication, _ titulo: String) {
        let estado = app.staticTexts["estadoPedido"].firstMatch
        var intentos = 0
        while estado.label != titulo, intentos < 6 {
            let boton = app.buttons["avanzarEstado"].firstMatch
            var scroll = 0
            while (!boton.exists || !boton.isHittable), scroll < 4 { app.swipeUp(velocity: .slow); scroll += 1 }
            boton.tap()
            sleep(1)
            intentos += 1
        }
        XCTAssertEqual(estado.label, titulo)
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
        tocarEnInicio(app, app.buttons["modoDemo"].firstMatch)
    }

    /// Abre un restaurante de demostración desde la lista del inicio.
    private func abrirRestaurante(_ app: XCUIApplication, _ slug: String) {
        tocarEnInicio(app, app.buttons["restaurante-\(slug)"].firstMatch)
    }

    /// El inicio es largo: desplaza hasta que el elemento quede sobre la barra de pestañas.
    private func tocarEnInicio(_ app: XCUIApplication, _ el: XCUIElement) {
        XCTAssertTrue(app.buttons["accesoRestaurantes"].firstMatch.waitForExistence(timeout: 10))
        var intentos = 0
        while (!el.exists || !el.isHittable || el.frame.maxY > app.frame.maxY - 120), intentos < 12 {
            app.swipeUp(velocity: .slow); intentos += 1
        }
        el.tap()
    }

    func testInicioMuestraRestaurantesYFiltraPorRubro() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["accesoRestaurantes"].firstMatch.waitForExistence(timeout: 10))
        adjuntar(app, "inicio")
        app.buttons["accesoPostres"].firstMatch.tap()
        XCTAssertTrue(app.buttons["restaurante-demo-dulce-nube"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["restaurante-demo-barrio-burger"].firstMatch.exists)
        abrirRestaurante(app, "demo-dulce-nube")
        XCTAssertTrue(app.buttons["producto-9202"].firstMatch.waitForExistence(timeout: 5))
        adjuntar(app, "carta-dulce-nube")
        tocarProducto(app, 9202)
        let ver3D = app.buttons["ver3D"].firstMatch
        XCTAssertTrue(ver3D.waitForExistence(timeout: 10))
        adjuntar(app, "detalle-torta")
        ver3D.tap()
        XCTAssertTrue(app.buttons["cerrar3D"].firstMatch.waitForExistence(timeout: 15))
        sleep(3)
        adjuntar(app, "visor-3d-torta-escaneo")
    }

    func testVisor3DPizzaPersonalizable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirDemo(app)
        tocarProducto(app, 9101)
        let ver3D = app.buttons["ver3D"].firstMatch
        XCTAssertTrue(ver3D.waitForExistence(timeout: 10))
        ver3D.tap()
        XCTAssertTrue(app.buttons["cerrar3D"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        adjuntar(app, "visor-3d-pizza")
        app.buttons["ingrediente-champinones"].firstMatch.tap()
        sleep(1)
        adjuntar(app, "visor-3d-pizza-sin-champinones")
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

    /// Sin zona configurada, la AR del restaurante queda desactivada y se avisa en el detalle.
    func testARBloqueadaSinUbicacionYPantallaDeAfiliacion() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        abrirRestaurante(app, "demo-dulce-nube")
        tocarProducto(app, 9203)
        XCTAssertTrue(app.staticTexts["zonaARSinConfigurar"].firstMatch.waitForExistence(timeout: 10)
                      || app.otherElements["zonaARSinConfigurar"].firstMatch.exists
                      || app.descendants(matching: .any)["zonaARSinConfigurar"].firstMatch.exists)
        adjuntar(app, "detalle-ar-sin-zona")
        // En iOS 26 la barra de pestañas se minimiza al desplazar el detalle: se vuelve atrás antes de cambiar de pestaña.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let perfil = app.tabBars.buttons["Mi perfil"].firstMatch
        XCTAssertTrue(perfil.waitForExistence(timeout: 5))
        perfil.tap()
        entrarAdmin(app)
        let afiliar = app.buttons["abrirAfiliacion"].firstMatch
        desplazarHasta(app, afiliar)
        XCTAssertTrue(afiliar.exists)
        afiliar.tap()
        XCTAssertTrue(app.buttons["usarMiUbicacion"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["guardarZonaAR"].firstMatch.isEnabled, "Sin centro no se puede activar")
        adjuntar(app, "afiliar-restaurante")
    }

    /// Mi perfil → Modo administrador: crea el PIN la primera vez y entra al panel.
    private func entrarAdmin(_ app: XCUIApplication) {
        let abrir = app.buttons["abrirAdmin"].firstMatch
        XCTAssertTrue(abrir.waitForExistence(timeout: 5))
        abrir.tap()
        let pin = app.secureTextFields["pinAdmin"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap(); pin.typeText("2468")
        let confirmar = app.secureTextFields["pinAdminConfirmar"].firstMatch
        if confirmar.exists { confirmar.tap(); confirmar.typeText("2468") }
        app.buttons["entrarAdmin"].firstMatch.tap()
        XCTAssertTrue(app.buttons["admin-restaurante-demo-dulce-nube"].firstMatch.waitForExistence(timeout: 5),
                      "No se abrió el panel de administración")
    }

    /// Desplaza una lista hasta que el elemento sea tocable.
    private func desplazarHasta(_ app: XCUIApplication, _ el: XCUIElement) {
        var intentos = 0
        while (!el.exists || !el.isHittable), intentos < 10 { app.swipeUp(velocity: .slow); intentos += 1 }
    }

    /// El administrador cambia el precio de un plato y lo ve reflejado en la carta del cliente.
    func testAdminCambiaPrecioYSeVeEnLaCarta() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.tabBars.buttons["Mi perfil"].tap()
        entrarAdmin(app)
        adjuntar(app, "admin-panel")
        let restaurante = app.buttons["admin-restaurante-demo-barrio-burger"].firstMatch
        desplazarHasta(app, restaurante)
        restaurante.tap()
        let plato = app.buttons["admin-producto-9411"].firstMatch
        var intentos = 0
        while !plato.isHittable, intentos < 5 { app.swipeUp(velocity: .slow); intentos += 1 }
        plato.tap()
        let precio = app.textFields["adminPrecio"].firstMatch
        XCTAssertTrue(precio.waitForExistence(timeout: 5))
        precio.tap()
        precio.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else if app.menuItems["Seleccionar todo"].waitForExistence(timeout: 1) { app.menuItems["Seleccionar todo"].tap() }
        precio.typeText(XCUIKeyboardKey.delete.rawValue)
        precio.typeText("30.50")
        adjuntar(app, "admin-editar-plato")
        app.buttons["adminGuardarPlato"].firstMatch.tap()

        app.tabBars.buttons["Inicio"].tap()
        abrirRestaurante(app, "demo-barrio-burger")
        let fila = app.buttons["producto-9411"].firstMatch
        XCTAssertTrue(fila.waitForExistence(timeout: 5))
        XCTAssertTrue(fila.label.contains("30.50"), "La carta debe mostrar el nuevo precio: \(fila.label)")
    }
}
