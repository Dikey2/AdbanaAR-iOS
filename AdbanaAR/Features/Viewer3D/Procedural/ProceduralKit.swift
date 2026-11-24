import CoreGraphics
import ImageIO
import Foundation
import RealityKit
import UIKit

// Utilidades para construir comida 3D procedural: ruido, mallas (torno, extrusión, lámina)
// y texturas generadas en tiempo de ejecución. Todo en metros (unidad de RealityKit).

// MARK: - Ruido de valor (determinista, sin aleatoriedad entre ejecuciones)

enum Ruido {
    static func hash(_ x: Int32, _ y: Int32, _ seed: Int32) -> Float {
        var h = UInt32(bitPattern: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    static func valor(_ x: Float, _ y: Float, seed: Int32 = 0) -> Float {
        let xi = x.rounded(.down), yi = y.rounded(.down)
        let fx = x - xi, fy = y - yi
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let ix = Int32(xi), iy = Int32(yi)
        let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed)
        let c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
        return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy
    }

    /// Ruido fractal en [0, 1].
    static func fbm(_ x: Float, _ y: Float, octavas: Int = 4, seed: Int32 = 0) -> Float {
        var s: Float = 0, amp: Float = 0.5, f: Float = 1, norm: Float = 0
        for o in 0..<octavas {
            s += amp * valor(x * f, y * f, seed: seed &+ Int32(o) &* 17)
            norm += amp; amp *= 0.5; f *= 2
        }
        return s / norm
    }

    /// Ruido sobre una circunferencia (sin costura en θ = 0 / 2π).
    static func circular(_ theta: Float, frecuencia: Float, seed: Int32 = 0) -> Float {
        fbm(cos(theta) * frecuencia + 10, sin(theta) * frecuencia + 10, octavas: 3, seed: seed)
    }
}

@inline(__always) func mezclar(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * min(max(t, 0), 1)
}

@inline(__always) func suave(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Mallas

struct Malla {
    var posiciones: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    /// Radio usado para el mapeo UV planar (vista superior) centrado en el origen.
    var escalaUV: Float = 0.1

    /// Genera el recurso con normales suaves y caras dobles (robusto ante el orden de vértices).
    func recurso() throws -> MeshResource {
        var normales = [SIMD3<Float>](repeating: .zero, count: posiciones.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let n = cross(posiciones[b] - posiciones[a], posiciones[c] - posiciones[a])
            normales[a] += n; normales[b] += n; normales[c] += n
        }
        normales = normales.map { length($0) > 1e-12 ? normalize($0) : [0, 1, 0] }
        let uvs = posiciones.map { SIMD2<Float>($0.x / escalaUV * 0.5 + 0.5, $0.z / escalaUV * 0.5 + 0.5) }
        let tangentes = normales.map { n -> SIMD3<Float> in
            var t = SIMD3<Float>(1, 0, 0) - n * n.x
            if length(t) < 1e-4 { t = SIMD3<Float>(0, 0, 1) - n * n.z }
            return normalize(t)
        }
        // Copia trasera con normales invertidas y orden inverso.
        let n0 = UInt32(posiciones.count)
        var idx = indices
        for t in stride(from: 0, to: indices.count, by: 3) {
            idx += [indices[t] + n0, indices[t + 2] + n0, indices[t + 1] + n0]
        }
        var d = MeshDescriptor(name: "comida")
        d.positions = MeshBuffers.Positions(posiciones + posiciones)
        d.normals = MeshBuffers.Normals(normales + normales.map { -$0 })
        d.tangents = MeshBuffers.Tangents(tangentes + tangentes)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs + uvs)
        d.primitives = .triangles(idx)
        return try MeshResource.generate(from: [d])
    }

    /// Superficie de revolución. `perfil` = (radio, altura) desde el eje hacia afuera.
    /// `radial(θ)` deforma el contorno; `desplazar` modifica cada vértice ya colocado.
    static func torno(perfil: [SIMD2<Float>], segmentos: Int = 64,
                      radial: ((Float) -> Float)? = nil,
                      desplazar: ((SIMD3<Float>, Float) -> SIMD3<Float>)? = nil,
                      escalaUV: Float) -> Malla {
        var m = Malla(escalaUV: escalaUV)
        let n = perfil.count
        for j in 0...segmentos {
            let th = Float(j) / Float(segmentos) * 2 * .pi
            let k = radial?(th) ?? 1
            for p in perfil {
                var v = SIMD3<Float>(p.x * k * cos(th), p.y, p.x * k * sin(th))
                if let desplazar { v = desplazar(v, th) }
                m.posiciones.append(v)
            }
        }
        for j in 0..<segmentos {
            for i in 0..<(n - 1) {
                let a = UInt32(j * n + i), b = UInt32((j + 1) * n + i)
                m.indices += [a, b, b + 1, a, b + 1, a + 1]
            }
        }
        return m
    }

    /// Prisma a partir de un contorno en estrella (visto desde arriba), de altura `alto`.
    static func extruir(contorno: [SIMD2<Float>], alto: Float, escalaUV: Float) -> Malla {
        var m = Malla(escalaUV: escalaUV)
        let c = contorno.reduce(SIMD2<Float>.zero, +) / Float(contorno.count)
        let n = UInt32(contorno.count)
        m.posiciones.append([c.x, alto, c.y])
        m.posiciones.append([c.x, 0, c.y])
        for p in contorno { m.posiciones.append([p.x, alto, p.y]) }
        for p in contorno { m.posiciones.append([p.x, 0, p.y]) }
        for i in 0..<n {
            let j = (i + 1) % n
            m.indices += [0, 2 + i, 2 + j]
            m.indices += [1, 2 + n + j, 2 + n + i]
            m.indices += [2 + i, 2 + n + i, 2 + n + j, 2 + i, 2 + n + j, 2 + j]
        }
        return m
    }

    /// Lámina cuadrada de lado `lado` con altura y(x, z).
    static func lamina(lado: Float, divisiones: Int = 24, altura: (Float, Float) -> Float) -> Malla {
        var m = Malla(escalaUV: lado / 2)
        for j in 0...divisiones {
            for i in 0...divisiones {
                let x = (Float(i) / Float(divisiones) - 0.5) * lado
                let z = (Float(j) / Float(divisiones) - 0.5) * lado
                m.posiciones.append([x, altura(x, z), z])
            }
        }
        let w = UInt32(divisiones + 1)
        for j in 0..<UInt32(divisiones) {
            for i in 0..<UInt32(divisiones) {
                let a = j * w + i
                m.indices += [a, a + w, a + w + 1, a, a + w + 1, a + 1]
            }
        }
        return m
    }

    /// Perfil de disco macizo de radio `r` y alto `h` con borde redondeado.
    static func perfilDisco(r: Float, h: Float, bisel: Float, anillos: Int = 8) -> [SIMD2<Float>] {
        var p: [SIMD2<Float>] = (0...anillos).map { SIMD2(r - bisel, h) * SIMD2(Float($0) / Float(anillos), 1) }
        for k in 1...6 {
            let a = Float(k) / 6 * .pi
            p.append([r - bisel + bisel * sin(a), h / 2 + (h / 2) * cos(a)])
        }
        p.append([r - bisel, 0])
        p.append([0, 0])
        return p
    }
}

// MARK: - Texturas procedurales

@MainActor
enum TexturaProcedural {
    private static var cache: [String: TextureResource] = [:]

    /// Si está definida, las texturas se regeneran y se exportan como PNG a esa carpeta
    /// (se usa una vez al desarrollar para empaquetarlas en `Resources/Texturas`).
    private static let carpetaExportacion = ProcessInfo.processInfo.environment["ADBANA_EXPORTAR_TEXTURAS"]

    /// Textura pregenerada incluida en la app: carga instantánea en el dispositivo.
    private static func empaquetada(_ nombre: String, _ semantica: TextureResource.Semantic) -> TextureResource? {
        guard carpetaExportacion == nil,
              let url = Bundle.main.url(forResource: nombre, withExtension: "png") else { return nil }
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(fuente, 0, nil) else { return nil }
        return try? TextureResource(image: img, withName: nombre, options: .init(semantic: semantica))
    }

    private static func exportar(_ img: CGImage, _ nombre: String) {
        guard let carpeta = carpetaExportacion else { return }
        let url = URL(fileURLWithPath: carpeta).appendingPathComponent("\(nombre).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    static func color(_ nombre: String, tam: Int = 256, _ f: (Float, Float) -> SIMD3<Float>) -> TextureResource? {
        if let t = cache[nombre] { return t }
        if let t = empaquetada(nombre, .color) { cache[nombre] = t; return t }
        guard let img = imagen(tam: tam, f) else { return nil }
        exportar(img, nombre)
        let t = try? TextureResource(image: img, withName: nombre, options: .init(semantic: .color))
        cache[nombre] = t
        return t
    }

    /// Mapa de normales a partir de una función de altura en [0, 1].
    static func normal(_ nombre: String, tam: Int = 256, fuerza: Float, _ h: (Float, Float) -> Float) -> TextureResource? {
        if let t = cache[nombre] { return t }
        if let t = empaquetada(nombre, .normal) { cache[nombre] = t; return t }
        var alturas = [Float](repeating: 0, count: tam * tam)
        for y in 0..<tam { for x in 0..<tam {
            alturas[y * tam + x] = h((Float(x) + 0.5) / Float(tam), (Float(y) + 0.5) / Float(tam))
        } }
        let img = imagen(tam: tam, lineal: true) { u, v in
            let x = min(Int(u * Float(tam)), tam - 1), y = min(Int(v * Float(tam)), tam - 1)
            let dx = alturas[y * tam + min(x + 1, tam - 1)] - alturas[y * tam + max(x - 1, 0)]
            let dy = alturas[min(y + 1, tam - 1) * tam + x] - alturas[max(y - 1, 0) * tam + x]
            let n = normalize(SIMD3<Float>(-dx * fuerza, -dy * fuerza, 1))
            return n * 0.5 + 0.5
        }
        guard let img else { return nil }
        exportar(img, nombre)
        let t = try? TextureResource(image: img, withName: nombre, options: .init(semantic: .normal))
        cache[nombre] = t
        return t
    }

    static func imagen(tam: Int, lineal: Bool = false, _ f: (Float, Float) -> SIMD3<Float>) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: tam * tam * 4)
        for y in 0..<tam {
            for x in 0..<tam {
                let c = f((Float(x) + 0.5) / Float(tam), (Float(y) + 0.5) / Float(tam))
                let i = (y * tam + x) * 4
                bytes[i] = UInt8(min(max(c.x, 0), 1) * 255)
                bytes[i + 1] = UInt8(min(max(c.y, 0), 1) * 255)
                bytes[i + 2] = UInt8(min(max(c.z, 0), 1) * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let espacio = lineal ? CGColorSpace(name: CGColorSpace.linearSRGB) : CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(width: tam, height: tam, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: tam * 4,
                       space: espacio, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Entorno de estudio (equirectangular) para reflejos en el visor 3D sin cámara.
    static func estudio() -> CGImage? {
        imagen(tam: 256) { u, v in
            let cielo = mezclar([1.0, 0.98, 0.95], [0.75, 0.78, 0.85], v * 2)
            let suelo = mezclar([0.55, 0.48, 0.42], [0.3, 0.26, 0.23], (v - 0.5) * 2)
            var c = v < 0.5 ? cielo : suelo
            // Dos "softboxes" que generan brillos especulares.
            let s1 = suave(0.08, 0.0, length(SIMD2(u - 0.25, (v - 0.22) * 1.6)))
            let s2 = suave(0.06, 0.0, length(SIMD2(u - 0.7, (v - 0.3) * 1.6)))
            c += SIMD3<Float>(repeating: 1) * (s1 + 0.6 * s2)
            return c
        }
    }
}

// MARK: - Materiales

@MainActor
enum MaterialComida {
    static func pbr(_ color: TextureResource?, tinte: UIColor = .white, normal: TextureResource? = nil,
                    rugosidad: Float, brillo: Float = 0, brilloRugosidad: Float = 0.2) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let color { m.baseColor = .init(tint: tinte, texture: .init(color)) } else { m.baseColor = .init(tint: tinte) }
        if let normal { m.normal = .init(texture: .init(normal)) }
        m.roughness = .init(floatLiteral: rugosidad)
        m.metallic = .init(floatLiteral: 0)
        if brillo > 0 {
            m.clearcoat = .init(floatLiteral: brillo)
            m.clearcoatRoughness = .init(floatLiteral: brilloRugosidad)
        }
        return m
    }
}
