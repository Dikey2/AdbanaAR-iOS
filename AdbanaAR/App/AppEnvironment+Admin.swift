import CryptoKit
import Foundation
import SwiftData

/// Catálogo editable y sesión del modo administrador.
extension AppEnvironment {
    // MARK: Catálogo con los cambios del administrador

    /// Restaurantes incluidos en la app con los ajustes aplicados.
    /// `incluirOcultos` solo lo usa el panel de administración.
    func restaurantes(incluirOcultos: Bool = false) -> [DemoRestaurante] {
        _ = versionCatalogo
        let ajustesR = Dictionary(uniqueKeysWithValues: ((try? contexto.fetch(FetchDescriptor<AjusteRestaurante>())) ?? []).map { ($0.slug, $0) })
        let ajustesP = Dictionary(uniqueKeysWithValues: ((try? contexto.fetch(FetchDescriptor<AjusteProducto>())) ?? []).map { ($0.productoId, $0) })
        return DemoCatalog.restaurantes.compactMap { r in
            let a = ajustesR[r.slug]
            if a?.visible == false && !incluirOcultos { return nil }
            return aplicar(a, ajustesP, a: r, incluirOcultos: incluirOcultos)
        }
    }

    func restaurante(slug: String, incluirOcultos: Bool = false) -> DemoRestaurante? {
        restaurantes(incluirOcultos: incluirOcultos).first { $0.slug == slug }
    }

    func restauranteVisible(_ slug: String) -> Bool { ajusteRestaurante(slug)?.visible ?? true }

    private func aplicar(_ a: AjusteRestaurante?, _ ajustesP: [Int: AjusteProducto], a r: DemoRestaurante,
                         incluirOcultos: Bool) -> DemoRestaurante {
        let base = r.carta.restaurante
        let conf = base.configuracion
        let nombre = a?.nombre ?? r.nombre
        let restauranteDTO = RestauranteDTO(
            nombre: nombre, slug: base.slug, telefono: base.telefono,
            configuracion: ConfiguracionDTO(modalidades: a?.modalidades ?? conf?.modalidades,
                                            descripcion: a?.descripcion ?? conf?.descripcion,
                                            direccion: conf?.direccion, horario: a?.horario ?? conf?.horario,
                                            ubicacionAR: conf?.ubicacionAR))
        let categorias = r.carta.carta.compactMap { c -> CategoriaDTO? in
            let productos = c.productos.compactMap { p -> ProductoDTO? in
                let ap = ajustesP[p.id]
                if ap?.oculto == true && !incluirOcultos { return nil }
                return ProductoDTO(id: p.id, nombre: ap?.nombre ?? p.nombre, descripcion: ap?.descripcion ?? p.descripcion,
                                   precio: ap?.precio.flatMap { Decimal(string: $0) }.map(DecimalString.init) ?? p.precio,
                                   imagen: p.imagen, modelo3D: p.modelo3D, modeloUSDZ: p.modeloUSDZ,
                                   disponible: ap?.disponible ?? p.disponible)
            }
            return productos.isEmpty ? nil : CategoriaDTO(id: c.id, nombre: c.nombre, productos: productos)
        }
        return DemoRestaurante(slug: r.slug, nombre: nombre, rubro: r.rubro, lema: a?.lema ?? r.lema, simbolo: r.simbolo,
                               colorHex: r.colorHex, portada: r.portada,
                               carta: CartaResponse(restaurante: restauranteDTO, carta: categorias, mesas: r.carta.mesas, mesa: nil))
    }

    var contexto: ModelContext { modelContainer.mainContext }

    func ajusteRestaurante(_ slug: String) -> AjusteRestaurante? {
        try? contexto.fetch(FetchDescriptor<AjusteRestaurante>(predicate: #Predicate { $0.slug == slug })).first
    }

    func ajusteProducto(_ id: Int) -> AjusteProducto? {
        try? contexto.fetch(FetchDescriptor<AjusteProducto>(predicate: #Predicate { $0.productoId == id })).first
    }

    /// Crea el ajuste si no existe, aplica el cambio y guarda.
    func editarRestaurante(_ slug: String, _ cambio: (AjusteRestaurante) -> Void) {
        let a = ajusteRestaurante(slug) ?? { let n = AjusteRestaurante(slug: slug); contexto.insert(n); return n }()
        cambio(a)
        a.actualizadoEn = .now
        guardarCatalogo()
    }

    func editarProducto(_ id: Int, _ cambio: (AjusteProducto) -> Void) {
        let a = ajusteProducto(id) ?? { let n = AjusteProducto(productoId: id); contexto.insert(n); return n }()
        cambio(a)
        a.actualizadoEn = .now
        guardarCatalogo()
    }

    func restablecerCatalogo() {
        try? contexto.delete(model: AjusteRestaurante.self)
        try? contexto.delete(model: AjusteProducto.self)
        try? contexto.delete(model: AjusteBanner.self)
        guardarCatalogo()
    }

    func guardarCatalogo() {
        try? contexto.save()
        versionCatalogo += 1
        // Si el cliente tiene abierta una carta de la app, se refresca con los cambios.
        if let slug = carta?.restaurante.slug, let r = restaurante(slug: slug, incluirOcultos: true) {
            carta = r.carta
        }
    }

    // MARK: Banners

    var banners: [Banner] {
        _ = versionCatalogo
        let guardados = (try? contexto.fetch(FetchDescriptor<AjusteBanner>(sortBy: [SortDescriptor(\.orden)]))) ?? []
        guard !guardados.isEmpty else { return Banner.originales }
        return guardados.map { Banner(id: $0.orden, antetitulo: $0.antetitulo, titulo: $0.titulo, detalle: $0.detalle, foto: $0.foto, visible: $0.visible) }
    }

    func guardarBanners(_ lista: [Banner]) {
        try? contexto.delete(model: AjusteBanner.self)
        for (i, b) in lista.enumerated() {
            let m = AjusteBanner(orden: i, antetitulo: b.antetitulo, titulo: b.titulo, detalle: b.detalle, foto: b.foto)
            m.visible = b.visible
            contexto.insert(m)
        }
        guardarCatalogo()
    }

    // MARK: PIN del administrador (hash SHA-256 en el llavero, nunca el PIN en claro)

    private static let cuentaPIN = "admin-pin-sha256"
    private var llaveroAdmin: KeychainStore { KeychainStore(service: "pe.edu.tecsup.adbana.ar.admin") }

    /// En pruebas de UI el PIN vive en memoria para no dejar rastros en el llavero del simulador.
    nonisolated(unsafe) private static var pinPruebas: String?

    private func leerPIN() -> String? { isUITesting ? Self.pinPruebas : llaveroAdmin.get(account: Self.cuentaPIN) }

    var tienePINAdmin: Bool { leerPIN() != nil }

    static func hashPIN(_ pin: String) -> String {
        SHA256.hash(data: Data(("adbana-ar|" + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func pinValido(_ pin: String) -> Bool { (4...8).contains(pin.count) && pin.allSatisfy(\.isNumber) }

    @discardableResult
    func crearPINAdmin(_ pin: String) -> Bool {
        guard Self.pinValido(pin) else { return false }
        if isUITesting { Self.pinPruebas = Self.hashPIN(pin); return true }
        return llaveroAdmin.set(Self.hashPIN(pin), account: Self.cuentaPIN)
    }

    func verificarPINAdmin(_ pin: String) -> Bool {
        leerPIN() == Self.hashPIN(pin)
    }

    func borrarPINAdmin() {
        if isUITesting { Self.pinPruebas = nil } else { llaveroAdmin.delete(account: Self.cuentaPIN) }
    }
}
