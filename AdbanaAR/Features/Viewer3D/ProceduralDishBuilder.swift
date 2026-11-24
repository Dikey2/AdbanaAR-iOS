import RealityKit
import UIKit

/// Construye platos 3D propios a escala real (metros) con formas orgánicas, texturas
/// procedurales y mapas de relieve. Cada ingrediente es una entidad independiente cuyo `name`
/// es el id estable de `DishRecipe`, para ocultarlo sin afectar al resto.
/// Es una aproximación artística generada por código: no es un escaneo fotográfico.
@MainActor
enum ProceduralDishBuilder {
    static func build(_ receta: DishRecipe) -> Entity {
        let root = Entity()
        root.name = "plato-\(receta.id)"
        let pozo: Float = receta.id == "pizza" ? 0.9 : (receta.id == "pollo" ? 0.8 : 0.66)
        root.addChild(plato(diametro: receta.diametroPlato, pozo: pozo))
        switch receta.id {
        case "pizza": construirPizza(en: root)
        case "hamburguesa": construirHamburguesa(en: root)
        case "pollo": construirPollo(en: root)
        default: break
        }
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

    /// Altura de la superficie interior del plato (donde se apoya la comida).
    static let alturaPlato: Float = 0.006

    // MARK: - Utilidades

    private static func entidad(_ malla: Malla, _ material: PhysicallyBasedMaterial) -> ModelEntity {
        guard let mesh = try? malla.recurso() else { return ModelEntity() }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    /// Instancia que reutiliza una malla ya generada (piezas repetidas).
    private static func instancia(_ mesh: MeshResource?, _ material: PhysicallyBasedMaterial) -> ModelEntity {
        guard let mesh else { return ModelEntity() }
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private static func grupo(_ id: String, en root: Entity) -> Entity {
        let e = Entity(); e.name = id; root.addChild(e); return e
    }

    /// Distribución determinista (ángulo áureo).
    private static func puntos(_ n: Int, radioMax: Float, offset: Int = 0) -> [SIMD2<Float>] {
        (0..<n).map { i in
            let k = Float(i + offset) + 0.5
            let r = radioMax * (k / Float(n + offset)).squareRoot()
            let a = k * 2.39996
            return [r * cos(a), r * sin(a)]
        }
    }

    private static func azar(_ i: Int, _ s: Int32) -> Float { Ruido.hash(Int32(i), 7, s) }

    // MARK: - Recipiente de cerámica

    private static func plato(diametro: Float, pozo: Float) -> Entity {
        let e = Entity(); e.name = "recipiente"
        let R = diametro / 2, w = pozo
        let perfil: [SIMD2<Float>] = [
            [0, alturaPlato], [R * w * 0.5, alturaPlato], [R * w, alturaPlato],
            [R * (w + (1 - w) * 0.25), alturaPlato + 0.002], [R * (w + (1 - w) * 0.6), alturaPlato + 0.0065],
            [R * 0.985, alturaPlato + 0.0095], [R, alturaPlato + 0.0088], [R * 0.995, alturaPlato + 0.0072],
            [R * (w + (1 - w) * 0.6), alturaPlato + 0.0035], [R * w, alturaPlato - 0.0028],
            [R * w * 0.62, 0.0025], [R * w * 0.6, 0], [R * w * 0.52, 0], [R * w * 0.5, 0.0025], [0, 0.0025],
        ]
        let malla = Malla.torno(perfil: perfil, segmentos: 96, escalaUV: R)
        let esmalte = TexturaProcedural.color("ceramica") { u, v in
            let n = Ruido.fbm(u * 6, v * 6, octavas: 3, seed: 3)
            return mezclar([0.97, 0.965, 0.95], [0.93, 0.925, 0.91], n)
        }
        e.addChild(entidad(malla, MaterialComida.pbr(esmalte, rugosidad: 0.12, brillo: 1, brilloRugosidad: 0.05)))
        return e
    }

    // MARK: - Pizza (≈ 26 cm sobre plato de 30 cm)

    private static func construirPizza(en root: Entity) {
        let y0 = alturaPlato
        let R: Float = 0.13

        // Masa con cornicione inflado e irregular.
        let masaTex = TexturaProcedural.color("masa", tam: 512) { u, v in
            let r = length(SIMD2(u - 0.5, v - 0.5)) * 2
            let n = Ruido.fbm(u * 18, v * 18, seed: 11)
            var c = mezclar([0.95, 0.86, 0.66], [0.84, 0.6, 0.3], suave(0.7, 0.95, r) * (0.6 + 0.6 * n))
            let quemado = suave(0.68, 0.8, Ruido.fbm(u * 26, v * 26, seed: 12)) * suave(0.8, 0.95, r)
            c = mezclar(c, [0.3, 0.17, 0.08], quemado)
            let harina = suave(0.9, 0.97, Ruido.valor(u * 160, v * 160, seed: 13))
            return mezclar(c, [0.98, 0.96, 0.9], harina * 0.5)
        }
        let masaN = TexturaProcedural.normal("masa-n", tam: 512, fuerza: 3) { u, v in Ruido.fbm(u * 30, v * 30, seed: 14) }
        let perfilMasa: [SIMD2<Float>] = [
            [0, 0.006], [0.06, 0.006], [0.1, 0.0065], [0.108, 0.008], [0.115, 0.013], [0.122, 0.0165],
            [0.128, 0.0165], [0.1315, 0.013], [0.132, 0.008], [0.129, 0.003], [0.122, 0.0005], [0.06, 0], [0, 0],
        ]
        let masa = Malla.torno(perfil: perfilMasa, segmentos: 96,
                               radial: { 1 + 0.03 * (Ruido.circular($0, frecuencia: 3, seed: 21) - 0.5) },
                               desplazar: { p, th in
                                   let r = length(SIMD2(p.x, p.z))
                                   guard r > 0.105, p.y > 0.004 else { return p }
                                   let bulto = Ruido.circular(th, frecuencia: 6, seed: 22) - 0.5
                                   return p + [0, bulto * 0.006, 0]
                               }, escalaUV: R)
        let base = grupo("base", en: root)
        let masaE = entidad(masa, MaterialComida.pbr(masaTex, normal: masaN, rugosidad: 0.8))
        masaE.position.y = y0
        base.addChild(masaE)

        // Salsa.
        let salsaTex = TexturaProcedural.color("salsa") { u, v in
            let n = Ruido.fbm(u * 20, v * 20, seed: 31)
            var c = mezclar([0.55, 0.07, 0.03], [0.75, 0.16, 0.06], n)
            let hierba = suave(0.93, 0.97, Ruido.valor(u * 90, v * 90, seed: 32))
            c = mezclar(c, [0.15, 0.25, 0.08], hierba)
            return c
        }
        let salsa = Malla.torno(perfil: [[0, 0.0015], [0.06, 0.0015], [0.104, 0.0012], [0.108, 0.0004], [0.104, 0], [0, 0]],
                                segmentos: 72, radial: { 1 + 0.06 * (Ruido.circular($0, frecuencia: 5, seed: 33) - 0.5) },
                                escalaUV: R)
        let salsaE = entidad(salsa, MaterialComida.pbr(salsaTex, rugosidad: 0.35, brillo: 0.6))
        salsaE.position.y = y0 + 0.0063
        grupo("salsa", en: root).addChild(salsaE)

        // Queso derretido: borde irregular, burbujas y manchas doradas.
        let quesoTex = TexturaProcedural.color("queso-pizza", tam: 512) { u, v in
            let n = Ruido.fbm(u * 10, v * 10, seed: 41)
            var c = mezclar([0.99, 0.93, 0.7], [0.98, 0.82, 0.45], n)
            let dorado = suave(0.6, 0.72, Ruido.fbm(u * 16, v * 16, seed: 42))
            c = mezclar(c, [0.82, 0.52, 0.2], dorado * 0.85)
            let tostado = suave(0.74, 0.8, Ruido.fbm(u * 22, v * 22, seed: 43))
            c = mezclar(c, [0.5, 0.28, 0.1], tostado * 0.8)
            let oregano = suave(0.95, 0.985, Ruido.valor(u * 140, v * 140, seed: 44))
            return mezclar(c, [0.22, 0.28, 0.1], oregano)
        }
        let quesoN = TexturaProcedural.normal("queso-pizza-n", tam: 512, fuerza: 4) { u, v in Ruido.fbm(u * 14, v * 14, seed: 45) }
        let quesoPerfil: [SIMD2<Float>] = (0...14).map { [Float($0) / 14 * 0.098, 0.0028] } + [[0.101, 0.0016], [0.098, 0], [0, 0]]
        let queso = Malla.torno(perfil: quesoPerfil, segmentos: 96,
                                radial: { 1 + 0.12 * (Ruido.circular($0, frecuencia: 7, seed: 46) - 0.5) },
                                desplazar: { p, _ in
                                    guard p.y > 0.002 else { return p }
                                    return p + [0, (Ruido.fbm(p.x * 90, p.z * 90, seed: 47) - 0.5) * 0.0025, 0]
                                }, escalaUV: R)
        let quesoE = entidad(queso, MaterialComida.pbr(quesoTex, normal: quesoN, rugosidad: 0.45, brillo: 0.45, brilloRugosidad: 0.3))
        quesoE.position.y = y0 + 0.0072
        grupo("queso", en: root).addChild(quesoE)
        let topY = y0 + 0.0105

        // Rodajas de tomate con lóculos y semillas.
        let tomateTex = TexturaProcedural.color("tomate-rodaja") { u, v in
            let d = SIMD2(u - 0.5, v - 0.5)
            let r = length(d) * 2, a = atan2(d.y, d.x)
            var c: SIMD3<Float> = [0.86, 0.14, 0.08]
            if r > 0.88 { c = [0.62, 0.05, 0.03] }
            let sector = abs(sin(a * 2.5))
            let loculo = suave(0.25, 0.35, r) * (1 - suave(0.72, 0.8, r)) * suave(0.35, 0.7, sector)
            c = mezclar(c, [0.96, 0.45, 0.3], loculo)
            let semilla = loculo * suave(0.82, 0.9, Ruido.valor(u * 40, v * 40, seed: 51))
            c = mezclar(c, [0.95, 0.85, 0.55], semilla)
            if r < 0.22 { c = mezclar(c, [0.95, 0.55, 0.4], 0.6) }
            return c
        }
        let rodaja = try? Malla.torno(perfil: Malla.perfilDisco(r: 0.017, h: 0.0028, bisel: 0.0012), segmentos: 40, escalaUV: 0.017).recurso()
        let rodajaMat = MaterialComida.pbr(tomateTex, rugosidad: 0.25, brillo: 0.8)
        let tomate = grupo("tomate", en: root)
        for (i, p) in puntos(7, radioMax: 0.082).enumerated() {
            let t = instancia(rodaja, rodajaMat)
            t.position = [p.x, topY - 0.0012, p.y]
            t.orientation = simd_quatf(angle: azar(i, 52) * 6.28, axis: [0, 1, 0]) * simd_quatf(angle: 0.06, axis: [1, 0, 0])
            tomate.addChild(t)
        }

        // Láminas de champiñón (silueta sombrero + tallo).
        var silueta: [SIMD2<Float>] = (0...16).map { k in
            let a = Float(k) / 16 * .pi
            return [0.012 * cos(a), 0.003 - 0.011 * sin(a)]
        }
        silueta += [[-0.0038, 0.003], [-0.0034, 0.011], [0.0034, 0.011], [0.0038, 0.003]]
        let champiTex = TexturaProcedural.color("champinon") { u, v in
            let n = Ruido.fbm(u * 30, v * 30, seed: 61)
            var c = mezclar([0.9, 0.83, 0.72], [0.78, 0.66, 0.5], n)
            let laminas = suave(0.8, 0.95, abs(sin(u * 140)))
            c = mezclar(c, [0.6, 0.48, 0.36], laminas * 0.35)
            return c
        }
        let champiMalla = try? Malla.extruir(contorno: silueta, alto: 0.0022, escalaUV: 0.012).recurso()
        let champiMat = MaterialComida.pbr(champiTex, rugosidad: 0.55, brillo: 0.3)
        let champi = grupo("champinones", en: root)
        for (i, p) in puntos(9, radioMax: 0.09, offset: 3).enumerated() {
            let c = instancia(champiMalla, champiMat)
            c.position = [p.x * 0.95, topY - 0.0005 + Float(i % 2) * 0.0008, p.y * 1.02]
            c.orientation = simd_quatf(angle: azar(i, 62) * 6.28, axis: [0, 1, 0]) * simd_quatf(angle: (azar(i, 63) - 0.5) * 0.12, axis: [1, 0, 0])
            champi.addChild(c)
        }

        // Aceitunas negras en aro.
        let aro: [SIMD2<Float>] = (0...12).map { k in
            let a = Float(k) / 12 * 2 * .pi
            return [0.0043 + 0.0017 * cos(a), 0.0017 + 0.0013 * sin(a)]
        }
        let aceitunaMalla = try? Malla.torno(perfil: aro, segmentos: 24, escalaUV: 0.006).recurso()
        let aceitunaMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.07, green: 0.06, blue: 0.06, alpha: 1), rugosidad: 0.2, brillo: 1, brilloRugosidad: 0.1)
        let aceitunas = grupo("aceitunas", en: root)
        for (i, p) in puntos(12, radioMax: 0.1, offset: 7).enumerated() {
            let a = instancia(aceitunaMalla, aceitunaMat)
            a.position = [-p.y, topY - 0.0008, p.x]
            a.orientation = simd_quatf(angle: (azar(i, 71) - 0.5) * 0.3, axis: [1, 0, 0])
            aceitunas.addChild(a)
        }
    }

    // MARK: - Hamburguesa (≈ 12 cm sobre plato de 26 cm)

    /// Orden de abajo hacia arriba y altura de cada capa (m).
    private static let capasHamburguesa: [(id: String, alto: Float)] = [
        ("pan_inferior", 0.018), ("lechuga", 0.005), ("carne", 0.016), ("queso", 0.003),
        ("tomate", 0.006), ("cebolla", 0.004), ("pan_superior", 0.03),
    ]

    private static func construirHamburguesa(en root: Entity) {
        // Pan inferior: miga en la cara cortada, corteza dorada en los lados.
        let migaTex = TexturaProcedural.color("miga") { u, v in
            let r = length(SIMD2(u - 0.5, v - 0.5)) * 2
            let n = Ruido.fbm(u * 25, v * 25, seed: 81)
            var c = mezclar([0.96, 0.88, 0.7], [0.88, 0.76, 0.55], n)
            let poro = suave(0.78, 0.86, Ruido.valor(u * 70, v * 70, seed: 82))
            c = mezclar(c, [0.75, 0.62, 0.42], poro * 0.6)
            return mezclar(c, [0.72, 0.44, 0.18], suave(0.82, 0.95, r))
        }
        let migaN = TexturaProcedural.normal("miga-n", fuerza: 5) { u, v in Ruido.valor(u * 70, v * 70, seed: 82) }
        let panInf = Malla.torno(perfil: Malla.perfilDisco(r: 0.056, h: 0.018, bisel: 0.008), segmentos: 64, escalaUV: 0.056)
        let panInfE = entidad(panInf, MaterialComida.pbr(migaTex, normal: migaN, rugosidad: 0.85))

        // Lechuga ondulada y con nervaduras.
        let lechugaTex = TexturaProcedural.color("lechuga") { u, v in
            let d = SIMD2(u - 0.5, v - 0.5)
            let r = length(d) * 2, a = atan2(d.y, d.x)
            var c = mezclar([0.42, 0.68, 0.2], [0.6, 0.8, 0.3], Ruido.fbm(u * 12, v * 12, seed: 91))
            let nervio = suave(0.94, 0.99, abs(sin(a * 7 + Ruido.fbm(u * 6, v * 6, seed: 92) * 3)))
            c = mezclar(c, [0.82, 0.92, 0.6], nervio * 0.7)
            return mezclar(c, [0.3, 0.52, 0.14], suave(0.85, 1, r))
        }
        let lechuga = Malla.torno(perfil: (0...10).map { [Float($0) / 10 * 0.066, 0.0025] }, segmentos: 96,
                                  radial: { 1 + 0.08 * (Ruido.circular($0, frecuencia: 6, seed: 93) - 0.5) },
                                  desplazar: { p, th in
                                      let r = length(SIMD2(p.x, p.z)) / 0.066
                                      let onda = sin(th * 11 + Ruido.circular(th, frecuencia: 4, seed: 94) * 4) * 0.0022 * r * r
                                      return p + [0, onda - 0.0012 * r * r * r, 0]
                                  }, escalaUV: 0.066)
        let lechugaE = entidad(lechuga, MaterialComida.pbr(lechugaTex, rugosidad: 0.4, brillo: 0.5))

        // Carne a la parrilla, irregular y con relieve.
        let carneTex = TexturaProcedural.color("carne", tam: 512) { u, v in
            let n = Ruido.fbm(u * 20, v * 20, seed: 101)
            var c = mezclar([0.36, 0.2, 0.11], [0.24, 0.13, 0.07], n)
            let costra = suave(0.6, 0.75, Ruido.fbm(u * 40, v * 40, seed: 102))
            c = mezclar(c, [0.1, 0.06, 0.04], costra * 0.8)
            let jugo = suave(0.85, 0.92, Ruido.valor(u * 50, v * 50, seed: 103))
            return mezclar(c, [0.5, 0.28, 0.15], jugo * 0.5)
        }
        let carneN = TexturaProcedural.normal("carne-n", tam: 512, fuerza: 8) { u, v in Ruido.fbm(u * 35, v * 35, seed: 104) }
        let carne = Malla.torno(perfil: Malla.perfilDisco(r: 0.06, h: 0.016, bisel: 0.006), segmentos: 80,
                                radial: { 1 + 0.07 * (Ruido.circular($0, frecuencia: 5, seed: 105) - 0.5) },
                                desplazar: { p, _ in p + [0, (Ruido.fbm(p.x * 120, p.z * 120, seed: 106) - 0.5) * 0.0018, 0] },
                                escalaUV: 0.06)
        let carneE = entidad(carne, MaterialComida.pbr(carneTex, normal: carneN, rugosidad: 0.7, brillo: 0.25, brilloRugosidad: 0.4))

        // Queso cheddar derretido cayendo por las esquinas.
        let cheddarTex = TexturaProcedural.color("cheddar") { u, v in
            mezclar([1.0, 0.72, 0.15], [0.98, 0.62, 0.08], Ruido.fbm(u * 8, v * 8, seed: 111))
        }
        let cheddar = Malla.lamina(lado: 0.1, divisiones: 30) { x, z in
            let c = cos(Float.pi / 4), s = sin(Float.pi / 4)
            let xr = x * c - z * s, zr = x * s + z * c
            let d = max(abs(xr), abs(zr)) * 0.5 + length(SIMD2(xr, zr)) * 0.5
            return 0.0018 - max(0, d - 0.052) * 0.45
        }
        let cheddarE = entidad(cheddar, MaterialComida.pbr(cheddarTex, rugosidad: 0.35, brillo: 0.7, brilloRugosidad: 0.25))

        // Tomate y cebolla morada.
        let tomateTex = TexturaProcedural.color("tomate-rodaja-grande") { u, v in
            let d = SIMD2(u - 0.5, v - 0.5)
            let r = length(d) * 2, a = atan2(d.y, d.x)
            var c: SIMD3<Float> = [0.86, 0.14, 0.08]
            if r > 0.9 { c = [0.62, 0.05, 0.03] }
            let loculo = suave(0.25, 0.35, r) * (1 - suave(0.74, 0.82, r)) * suave(0.35, 0.7, abs(sin(a * 2.5)))
            c = mezclar(c, [0.96, 0.45, 0.3], loculo)
            return mezclar(c, [0.95, 0.85, 0.55], loculo * suave(0.82, 0.9, Ruido.valor(u * 50, v * 50, seed: 121)))
        }
        let tomateE = entidad(Malla.torno(perfil: Malla.perfilDisco(r: 0.048, h: 0.006, bisel: 0.002), segmentos: 64, escalaUV: 0.048),
                              MaterialComida.pbr(tomateTex, rugosidad: 0.25, brillo: 0.9, brilloRugosidad: 0.1))
        let cebollaE = Entity()
        let cebollaMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.82, green: 0.62, blue: 0.8, alpha: 1), rugosidad: 0.25, brillo: 0.8, brilloRugosidad: 0.15)
        for (i, radio) in [Float(0.042), 0.032, 0.022].enumerated() {
            let aro: [SIMD2<Float>] = (0...10).map { k in
                let a = Float(k) / 10 * 2 * .pi
                return [radio + 0.0018 * cos(a), 0.0018 + 0.0016 * sin(a)]
            }
            let anillo = entidad(Malla.torno(perfil: aro, segmentos: 48, escalaUV: radio), cebollaMat)
            anillo.position = [Float(i) * 0.004 - 0.004, 0, Float(i) * 0.003]
            cebollaE.addChild(anillo)
        }

        // Pan superior en domo, brillante y con ajonjolí.
        let H: Float = 0.03, R: Float = 0.057
        let domo: [SIMD2<Float>] = (0...16).map { k in
            let t = Float(k) / 16
            let r = R * t
            return [r, 0.004 + (H - 0.004) * pow(max(0, 1 - pow(t, 2.4)), 0.55)]
        } + [[R, 0.002], [R * 0.97, 0], [0, 0]]
        let panTex = TexturaProcedural.color("pan", tam: 512) { u, v in
            let r = length(SIMD2(u - 0.5, v - 0.5)) * 2
            let n = Ruido.fbm(u * 10, v * 10, seed: 131)
            var c = mezclar([0.62, 0.33, 0.1], [0.78, 0.48, 0.18], n * 0.8 + r * 0.4)
            c = mezclar(c, [0.92, 0.75, 0.45], suave(0.82, 1.0, r))
            return c
        }
        let panN = TexturaProcedural.normal("pan-n", fuerza: 2) { u, v in Ruido.fbm(u * 16, v * 16, seed: 132) }
        let panSupE = entidad(Malla.torno(perfil: domo, segmentos: 80, escalaUV: R),
                              MaterialComida.pbr(panTex, normal: panN, rugosidad: 0.45, brillo: 0.7, brilloRugosidad: 0.25))
        let semillaMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.97, green: 0.92, blue: 0.8, alpha: 1), rugosidad: 0.5, brillo: 0.3)
        let semilla = MeshResource.generateSphere(radius: 0.0014)
        for (i, p) in puntos(34, radioMax: 0.044).enumerated() {
            let t = length(p) / R
            let y = 0.004 + (H - 0.004) * pow(max(0, 1 - pow(t, 2.4)), 0.55)
            let s = ModelEntity(mesh: semilla, materials: [semillaMat])
            s.scale = [1.9, 0.7, 1]
            s.position = [p.x, y - 0.0002, p.y]
            s.orientation = simd_quatf(angle: azar(i, 133) * 6.28, axis: [0, 1, 0])
            panSupE.addChild(s)
        }

        let piezas: [String: Entity] = ["pan_inferior": panInfE, "lechuga": lechugaE, "carne": carneE,
                                        "queso": cheddarE, "tomate": tomateE, "cebolla": cebollaE, "pan_superior": panSupE]
        for (id, _) in capasHamburguesa {
            let e = grupo(id, en: root)
            e.addChild(piezas[id]!)
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

    // MARK: - Pollo a la plancha con guarnición (plato de 28 cm)

    private static func construirPollo(en root: Entity) {
        let y = alturaPlato

        // Pechuga ovalada con marcas de parrilla.
        let polloTex = TexturaProcedural.color("pollo", tam: 512) { u, v in
            let n = Ruido.fbm(u * 14, v * 14, seed: 141)
            var c = mezclar([0.9, 0.68, 0.38], [0.78, 0.5, 0.22], n)
            let franja = suave(0.08, 0.02, abs((u + v * 0.6) * 9 - ((u + v * 0.6) * 9).rounded()))
            c = mezclar(c, [0.22, 0.11, 0.05], franja * (0.7 + 0.3 * Ruido.fbm(u * 30, v * 30, seed: 142)))
            return c
        }
        let polloN = TexturaProcedural.normal("pollo-n", tam: 512, fuerza: 6) { u, v in
            let franja = suave(0.08, 0.02, abs((u + v * 0.6) * 9 - ((u + v * 0.6) * 9).rounded()))
            return Ruido.fbm(u * 25, v * 25, seed: 143) * 0.5 - franja * 0.5
        }
        let Rp: Float = 0.05, Hp: Float = 0.022
        let perfilPollo: [SIMD2<Float>] = (0...14).map { k in
            let t = Float(k) / 14
            return [Rp * t, 0.002 + (Hp - 0.002) * pow(max(0, 1 - pow(t, 3.5)), 0.5)]
        } + [[Rp, 0.001], [Rp * 0.96, 0], [0, 0]]
        let pechuga = Malla.torno(perfil: perfilPollo, segmentos: 80,
                                  radial: { 1 + 0.1 * (Ruido.circular($0, frecuencia: 3, seed: 144) - 0.5) },
                                  desplazar: { p, _ in [p.x * 1.45, p.y, p.z * 0.85] }, escalaUV: Rp * 1.45)
        let polloE = entidad(pechuga, MaterialComida.pbr(polloTex, normal: polloN, rugosidad: 0.55, brillo: 0.35, brilloRugosidad: 0.35))
        polloE.position = [-0.035, y, -0.025]
        polloE.orientation = simd_quatf(angle: 0.25, axis: [0, 1, 0])
        grupo("pollo", en: root).addChild(polloE)

        // Papas fritas.
        let papaTex = TexturaProcedural.color("papa") { u, v in
            var c = mezclar([0.98, 0.82, 0.42], [0.92, 0.68, 0.28], Ruido.fbm(u * 20, v * 20, seed: 151))
            c = mezclar(c, [0.7, 0.45, 0.18], suave(0.75, 0.85, Ruido.fbm(u * 30, v * 30, seed: 152)) * 0.6)
            return c
        }
        let papaMat = MaterialComida.pbr(papaTex, rugosidad: 0.55, brillo: 0.3)
        let papas = grupo("papas", en: root)
        for (i, p) in puntos(16, radioMax: 0.032).enumerated() {
            let largo = 0.045 + azar(i, 153) * 0.025
            let b = ModelEntity(mesh: .generateBox(size: [0.0085, 0.0085, largo], cornerRadius: 0.0015), materials: [papaMat])
            b.position = [0.06 + p.x, y + 0.0045 + Float(i % 3) * 0.0075, 0.055 + p.y]
            b.orientation = simd_quatf(angle: azar(i, 154) * 6.28, axis: [0, 1, 0]) * simd_quatf(angle: (azar(i, 155) - 0.5) * 0.35, axis: [1, 0, 0])
            papas.addChild(b)
        }

        // Arroz en domo con granos.
        let arrozTex = TexturaProcedural.color("arroz") { u, v in
            let g = Ruido.valor(u * 90, v * 45, seed: 161)
            return mezclar([0.98, 0.97, 0.93], [0.86, 0.85, 0.8], suave(0.55, 0.9, g) * 0.6)
        }
        let arrozN = TexturaProcedural.normal("arroz-n", fuerza: 8) { u, v in Ruido.valor(u * 90, v * 45, seed: 161) }
        let domo: [SIMD2<Float>] = (0...12).map { k in
            let t = Float(k) / 12
            return [0.044 * t, 0.026 * pow(max(0, 1 - t * t), 0.6)]
        } + [[0, 0]]
        let arrozMalla = Malla.torno(perfil: domo, segmentos: 64,
                                     desplazar: { p, _ in p + [0, (Ruido.fbm(p.x * 300, p.z * 300, seed: 162) - 0.5) * 0.0025 * (p.y > 0.001 ? 1 : 0), 0] },
                                     escalaUV: 0.044)
        let arrozE = entidad(arrozMalla, MaterialComida.pbr(arrozTex, normal: arrozN, rugosidad: 0.75))
        arrozE.position = [0.06, y, 0.055]
        let perejil = MaterialComida.pbr(nil, tinte: UIColor(red: 0.2, green: 0.45, blue: 0.12, alpha: 1), rugosidad: 0.5)
        for (i, p) in puntos(10, radioMax: 0.02).enumerated() {
            let h = ModelEntity(mesh: .generateBox(size: [0.003, 0.0006, 0.002]), materials: [perejil])
            h.position = [p.x, 0.026 * pow(max(0, 1 - pow(length(p) / 0.044, 2)), 0.6) + 0.0006, p.y]
            h.orientation = simd_quatf(angle: azar(i, 163) * 6.28, axis: [0, 1, 0])
            arrozE.addChild(h)
        }
        grupo("arroz", en: root).addChild(arrozE)

        // Ensalada: hojas onduladas, tomate cherry y pepino.
        let ensalada = grupo("ensalada", en: root)
        let lechugaTex = TexturaProcedural.color("lechuga") { u, v in
            mezclar([0.42, 0.68, 0.2], [0.6, 0.8, 0.3], Ruido.fbm(u * 12, v * 12, seed: 91))
        }
        let hojaMalla = try? Malla.torno(perfil: (0...6).map { [Float($0) / 6 * 0.02, 0] }, segmentos: 40,
                                    radial: { 1 + 0.25 * (Ruido.circular($0, frecuencia: 4, seed: 171) - 0.5) },
                                    desplazar: { p, th in p + [0, sin(th * 6) * 0.002 * length(SIMD2(p.x, p.z)) / 0.02, 0] },
                                    escalaUV: 0.02).recurso()
        let hojaMat = MaterialComida.pbr(lechugaTex, rugosidad: 0.4, brillo: 0.6)
        for (i, p) in puntos(9, radioMax: 0.036).enumerated() {
            let h = instancia(hojaMalla, hojaMat)
            h.position = [0.06 + p.x, y + 0.004 + Float(i % 3) * 0.004, 0.055 + p.y]
            h.orientation = simd_quatf(angle: azar(i, 172) * 6.28, axis: [0, 1, 0]) * simd_quatf(angle: (azar(i, 173) - 0.5) * 0.8, axis: [1, 0, 0])
            ensalada.addChild(h)
        }
        let cherryMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.85, green: 0.1, blue: 0.06, alpha: 1), rugosidad: 0.2, brillo: 1, brilloRugosidad: 0.08)
        for (i, p) in puntos(4, radioMax: 0.03, offset: 2).enumerated() {
            let c = ModelEntity(mesh: .generateSphere(radius: 0.0095), materials: [cherryMat])
            c.scale = [1, 0.9, 1]
            c.position = [0.06 + p.x, y + 0.012 + Float(i % 2) * 0.002, 0.055 + p.y]
            ensalada.addChild(c)
        }
        let pepinoTex = TexturaProcedural.color("pepino") { u, v in
            let r = length(SIMD2(u - 0.5, v - 0.5)) * 2
            var c = mezclar([0.85, 0.93, 0.7], [0.7, 0.85, 0.5], suave(0.3, 0.8, r))
            if r > 0.88 { c = [0.18, 0.38, 0.12] }
            return mezclar(c, [0.95, 0.97, 0.85], suave(0.85, 0.92, Ruido.valor(u * 30, v * 30, seed: 174)) * (1 - suave(0.3, 0.5, r)))
        }
        let pepino = try? Malla.torno(perfil: Malla.perfilDisco(r: 0.012, h: 0.003, bisel: 0.001), segmentos: 32, escalaUV: 0.012).recurso()
        let pepinoMat = MaterialComida.pbr(pepinoTex, rugosidad: 0.3, brillo: 0.8)
        for (i, p) in puntos(3, radioMax: 0.028, offset: 5).enumerated() {
            let s = instancia(pepino, pepinoMat)
            s.position = [0.06 + p.x, y + 0.011, 0.055 + p.y]
            s.orientation = simd_quatf(angle: (azar(i, 175) - 0.5) * 0.7, axis: [1, 0, 0])
            ensalada.addChild(s)
        }

        // Salsa criolla: tiras de cebolla morada con culantro, sobre la pechuga.
        let criolla = grupo("salsa_criolla", en: root)
        let moradaMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.72, green: 0.32, blue: 0.58, alpha: 1), rugosidad: 0.2, brillo: 1, brilloRugosidad: 0.1)
        let blancaMat = MaterialComida.pbr(nil, tinte: UIColor(red: 0.95, green: 0.88, blue: 0.94, alpha: 1), rugosidad: 0.2, brillo: 1, brilloRugosidad: 0.1)
        let culantro = MaterialComida.pbr(nil, tinte: UIColor(red: 0.18, green: 0.48, blue: 0.12, alpha: 1), rugosidad: 0.45)
        for (i, p) in puntos(14, radioMax: 0.024).enumerated() {
            let tira = ModelEntity(mesh: .generateBox(size: [0.03, 0.0022, 0.0032], cornerRadius: 0.0009), materials: [i % 3 == 0 ? blancaMat : moradaMat])
            tira.position = [-0.04 + p.x, y + Hp + 0.0008 + Float(i % 3) * 0.0016, -0.022 + p.y]
            tira.orientation = simd_quatf(angle: azar(i, 181) * 6.28, axis: [0, 1, 0])
            criolla.addChild(tira)
        }
        for (i, p) in puntos(8, radioMax: 0.022, offset: 3).enumerated() {
            let h = ModelEntity(mesh: .generateBox(size: [0.004, 0.0006, 0.003]), materials: [culantro])
            h.position = [-0.04 + p.x, y + Hp + 0.004, -0.022 + p.y]
            h.orientation = simd_quatf(angle: azar(i, 182) * 6.28, axis: [0, 1, 0])
            criolla.addChild(h)
        }

        // Limón: gajo con cáscara porosa.
        let limonTex = TexturaProcedural.color("limon") { u, v in
            var c = mezclar([0.72, 0.84, 0.22], [0.6, 0.76, 0.15], Ruido.fbm(u * 20, v * 20, seed: 191))
            c = mezclar(c, [0.5, 0.65, 0.1], suave(0.8, 0.9, Ruido.valor(u * 120, v * 120, seed: 192)) * 0.5)
            return c
        }
        let limonN = TexturaProcedural.normal("limon-n", fuerza: 6) { u, v in Ruido.valor(u * 120, v * 120, seed: 192) }
        let gajo = ModelEntity(mesh: .generateSphere(radius: 0.018),
                               materials: [MaterialComida.pbr(limonTex, normal: limonN, rugosidad: 0.35, brillo: 0.6)])
        gajo.scale = [1.45, 0.62, 0.8]
        gajo.position = [-0.078, y + 0.0105, 0.072]
        gajo.orientation = simd_quatf(angle: 0.5, axis: [0, 1, 0])
        grupo("limon", en: root).addChild(gajo)
    }

    private static func aplicarSombras(_ e: Entity) {
        if e is ModelEntity { e.components.set(GroundingShadowComponent(castsShadow: true)) }
        e.children.forEach(aplicarSombras)
    }
}
