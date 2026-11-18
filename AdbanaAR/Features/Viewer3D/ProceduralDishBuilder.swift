import RealityKit
import UIKit

/// Construye platos 3D propios con primitivas RealityKit a escala real (metros).
/// Cada ingrediente es una entidad independiente cuyo `name` es el id estable de `DishRecipe`,
/// para poder ocultarlo sin afectar al resto. Geometría simplificada: NO es fotorrealista.
@MainActor
enum ProceduralDishBuilder {
    static func build(_ receta: DishRecipe) -> Entity {
        let root = Entity()
        root.name = "plato-\(receta.id)"
        root.addChild(plato(diametro: receta.diametroPlato))
        switch receta.id {
        case "pizza": construirPizza(en: root)
        case "hamburguesa": construirHamburguesa(en: root)
        case "pollo": construirPollo(en: root)
        default: break
        }
        root.components.set(GroundingShadowComponent(castsShadow: true))
        aplicarSombras(root)
        return root
    }

    /// Muestra u oculta cada componente según la personalización y reapila capas si aplica.
    static func aplicar(_ visibilidad: [String: Bool], recetaId: String, a root: Entity) {
        for (id, visible) in visibilidad {
            root.findEntity(named: id)?.isEnabled = visible
        }
        if recetaId == "hamburguesa" { reapilarHamburguesa(root) }
    }

    // MARK: - Materiales PBR

    static func material(_ color: UIColor, rugosidad: Float, brillo: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: rugosidad)
        m.metallic = .init(floatLiteral: 0)
        if brillo > 0 { m.clearcoat = .init(floatLiteral: brillo) }
        return m
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static func cilindro(radio: Float, alto: Float, _ m: PhysicallyBasedMaterial) -> ModelEntity {
        ModelEntity(mesh: .generateCylinder(height: alto, radius: radio), materials: [m])
    }

    /// Distribución determinista (ángulo áureo) para colocar piezas sin aleatoriedad.
    private static func puntos(_ n: Int, radioMax: Float, offset: Int = 0) -> [SIMD2<Float>] {
        (0..<n).map { i in
            let k = Float(i + offset) + 0.5
            let r = radioMax * (k / Float(n + offset)).squareRoot()
            let a = k * 2.39996
            return [r * cos(a), r * sin(a)]
        }
    }

    // MARK: - Recipiente

    private static func plato(diametro: Float) -> Entity {
        let e = Entity()
        e.name = "recipiente"
        let ceramica = material(.white, rugosidad: 0.15, brillo: 0.8)
        let fondo = cilindro(radio: diametro / 2, alto: 0.008, ceramica)
        fondo.position.y = 0.004
        let borde = cilindro(radio: diametro / 2 * 0.98, alto: 0.004, material(rgb(240, 240, 236), rugosidad: 0.2, brillo: 0.6))
        borde.position.y = 0.010
        e.addChild(fondo)
        e.addChild(borde)
        return e
    }

    private static let alturaPlato: Float = 0.012

    // MARK: - Pizza (≈ 26 cm sobre plato de 30 cm)

    private static func construirPizza(en root: Entity) {
        var y = alturaPlato
        func capa(_ id: String, radio: Float, alto: Float, _ m: PhysicallyBasedMaterial) -> Entity {
            let e = Entity(); e.name = id
            let mesh = cilindro(radio: radio, alto: alto, m)
            mesh.position.y = y + alto / 2
            e.addChild(mesh)
            root.addChild(e)
            y += alto
            return e
        }
        _ = capa("base", radio: 0.13, alto: 0.010, material(rgb(214, 165, 98), rugosidad: 0.85))
        _ = capa("salsa", radio: 0.118, alto: 0.002, material(rgb(178, 34, 20), rugosidad: 0.4, brillo: 0.3))
        _ = capa("queso", radio: 0.112, alto: 0.003, material(rgb(250, 214, 120), rugosidad: 0.55, brillo: 0.2))
        let topY = y

        let tomate = Entity(); tomate.name = "tomate"
        for p in puntos(7, radioMax: 0.085) {
            let t = cilindro(radio: 0.016, alto: 0.003, material(rgb(214, 40, 30), rugosidad: 0.35, brillo: 0.4))
            t.position = [p.x, topY + 0.0015, p.y]
            tomate.addChild(t)
        }
        root.addChild(tomate)

        let champi = Entity(); champi.name = "champinones"
        for p in puntos(9, radioMax: 0.095, offset: 3) {
            let c = ModelEntity(mesh: .generateSphere(radius: 0.011), materials: [material(rgb(222, 205, 178), rugosidad: 0.7)])
            c.scale = [1, 0.35, 1]
            c.position = [p.x * 0.92, topY + 0.003, p.y * 1.05]
            champi.addChild(c)
        }
        root.addChild(champi)

        let aceitunas = Entity(); aceitunas.name = "aceitunas"
        for p in puntos(12, radioMax: 0.1, offset: 7) {
            let a = cilindro(radio: 0.0055, alto: 0.004, material(rgb(35, 30, 30), rugosidad: 0.25, brillo: 0.6))
            a.position = [-p.y, topY + 0.002, p.x]
            aceitunas.addChild(a)
        }
        root.addChild(aceitunas)
    }

    // MARK: - Hamburguesa (≈ 11 cm de diámetro sobre plato de 26 cm)

    /// Orden de abajo hacia arriba y altura de cada capa (m).
    private static let capasHamburguesa: [(id: String, alto: Float)] = [
        ("pan_inferior", 0.018), ("lechuga", 0.005), ("carne", 0.016), ("queso", 0.003),
        ("tomate", 0.006), ("cebolla", 0.004), ("pan_superior", 0.03),
    ]

    private static func construirHamburguesa(en root: Entity) {
        let mats: [String: (ModelEntity)] = [
            "pan_inferior": cilindro(radio: 0.055, alto: 0.018, material(rgb(205, 140, 70), rugosidad: 0.7)),
            "lechuga": cilindro(radio: 0.062, alto: 0.005, material(rgb(110, 170, 60), rugosidad: 0.5, brillo: 0.2)),
            "carne": cilindro(radio: 0.058, alto: 0.016, material(rgb(90, 50, 30), rugosidad: 0.8)),
            "queso": ModelEntity(mesh: .generateBox(size: [0.105, 0.003, 0.105], cornerRadius: 0.001),
                                 materials: [material(rgb(250, 190, 40), rugosidad: 0.4, brillo: 0.3)]),
            "tomate": cilindro(radio: 0.05, alto: 0.006, material(rgb(214, 40, 30), rugosidad: 0.35, brillo: 0.4)),
            "cebolla": cilindro(radio: 0.047, alto: 0.004, material(rgb(235, 215, 235), rugosidad: 0.3, brillo: 0.4)),
        ]
        for (id, alto) in capasHamburguesa {
            let e = Entity(); e.name = id
            let mesh: ModelEntity
            if id == "pan_superior" {
                mesh = ModelEntity(mesh: .generateSphere(radius: 0.057), materials: [material(rgb(196, 120, 50), rugosidad: 0.6, brillo: 0.25)])
                mesh.scale = [1, alto * 2 / 0.114, 1]
                mesh.position.y = 0
                // Media esfera visible: el centro queda en la base de la capa.
            } else {
                mesh = mats[id]!
                mesh.position.y = alto / 2
                if id == "queso" { mesh.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0]) }
            }
            e.addChild(mesh)
            root.addChild(e)
        }
        reapilarHamburguesa(root)
    }

    /// Las capas visibles se apoyan una sobre otra: quitar el tomate no deja un hueco flotante.
    private static func reapilarHamburguesa(_ root: Entity) {
        var y = alturaPlato
        for (id, alto) in capasHamburguesa {
            guard let e = root.findEntity(named: id) else { continue }
            e.position.y = y
            if e.isEnabled { y += alto }
        }
    }

    // MARK: - Pollo con guarnición (plato de 28 cm)

    private static func construirPollo(en root: Entity) {
        let y = alturaPlato
        let pollo = Entity(); pollo.name = "pollo"
        let pechuga = ModelEntity(mesh: .generateBox(size: [0.13, 0.022, 0.075], cornerRadius: 0.01),
                                  materials: [material(rgb(196, 140, 70), rugosidad: 0.6, brillo: 0.2)])
        pechuga.position = [-0.035, y + 0.011, -0.02]
        pechuga.orientation = simd_quatf(angle: 0.25, axis: [0, 1, 0])
        for i in 0..<4 {
            let marca = ModelEntity(mesh: .generateBox(size: [0.006, 0.001, 0.07]), materials: [material(rgb(80, 45, 20), rugosidad: 0.9)])
            marca.position = [Float(i) * 0.028 - 0.042, 0.0115, 0]
            pechuga.addChild(marca)
        }
        pollo.addChild(pechuga)
        root.addChild(pollo)

        let papas = Entity(); papas.name = "papas"
        for (i, p) in puntos(14, radioMax: 0.035).enumerated() {
            let b = ModelEntity(mesh: .generateBox(size: [0.008, 0.008, 0.06], cornerRadius: 0.002),
                                materials: [material(rgb(240, 190, 80), rugosidad: 0.6)])
            b.position = [0.06 + p.x, y + 0.004 + Float(i % 3) * 0.007, 0.055 + p.y]
            b.orientation = simd_quatf(angle: Float(i) * 0.7, axis: [0, 1, 0])
            papas.addChild(b)
        }
        root.addChild(papas)

        let arroz = Entity(); arroz.name = "arroz"
        let domo = ModelEntity(mesh: .generateSphere(radius: 0.045), materials: [material(rgb(248, 246, 238), rugosidad: 0.9)])
        domo.scale = [1, 0.6, 1]
        domo.position = [0.06, y + 0.02, 0.055] // base del domo hundida en el plato, nunca bajo la mesa
        arroz.addChild(domo)
        root.addChild(arroz)

        let ensalada = Entity(); ensalada.name = "ensalada"
        for (i, p) in puntos(16, radioMax: 0.045).enumerated() {
            let color = i % 4 == 0 ? rgb(214, 40, 30) : rgb(90 + CGFloat(i * 5), 160, 60)
            let h = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [material(color, rugosidad: 0.45, brillo: 0.3)])
            h.scale = [1.2, 0.4, 0.9]
            h.position = [0.06 + p.x, y + 0.005 + Float(i % 2) * 0.004, 0.055 + p.y]
            ensalada.addChild(h)
        }
        root.addChild(ensalada)

        let criolla = Entity(); criolla.name = "salsa_criolla"
        for (i, p) in puntos(10, radioMax: 0.022).enumerated() {
            let c = ModelEntity(mesh: .generateBox(size: [0.03, 0.003, 0.004], cornerRadius: 0.001),
                                materials: [material(i % 3 == 0 ? rgb(214, 40, 30) : rgb(170, 70, 140), rugosidad: 0.3, brillo: 0.5)])
            c.position = [-0.04 + p.x, y + 0.024 + Float(i % 2) * 0.003, -0.02 + p.y]
            c.orientation = simd_quatf(angle: Float(i) * 1.1, axis: [0, 1, 0])
            criolla.addChild(c)
        }
        root.addChild(criolla)

        let limon = Entity(); limon.name = "limon"
        let gajo = ModelEntity(mesh: .generateSphere(radius: 0.018), materials: [material(rgb(170, 210, 60), rugosidad: 0.35, brillo: 0.5)])
        gajo.scale = [1.4, 0.6, 0.8]
        gajo.position = [-0.075, y + 0.008, 0.075]
        limon.addChild(gajo)
        root.addChild(limon)
    }

    private static func aplicarSombras(_ e: Entity) {
        if e is ModelEntity { e.components.set(GroundingShadowComponent(castsShadow: true)) }
        e.children.forEach(aplicarSombras)
    }
}
