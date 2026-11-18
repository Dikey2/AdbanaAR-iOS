import Foundation

/// Origen del recurso 3D de un producto, según lo que realmente expone el backend.
enum ModelSource: Equatable {
    /// USDZ local listo para RealityKit.
    case usdz(URL, origen: String)
    /// El backend solo ofrece GLB: RealityKit no lo carga de forma nativa en iOS.
    case glbOnly(URL)
    /// Modelo propio generado en la app con ingredientes separables (escala real).
    case receta(DishRecipe)
    /// El producto no tiene modelo 3D.
    case none

    var hasNativeModel: Bool {
        switch self {
        case .usdz, .receta: return true
        case .glbOnly, .none: return false
        }
    }

    /// Solo los modelos con componentes identificados admiten personalización visual.
    var receta: DishRecipe? { if case .receta(let r) = self { return r } else { return nil } }

    var descripcion: String {
        switch self {
        case .usdz(_, let origen): return "Modelo USDZ (\(origen))"
        case .receta: return "Modelo 3D propio a escala real con ingredientes independientes (geometría simplificada, no fotorrealista)."
        case .glbOnly: return "El servidor ofrece este plato en GLB (formato web). Se muestra una representación genérica hasta publicar su versión USDZ."
        case .none: return "Este plato no tiene modelo 3D; se muestra una representación genérica."
        }
    }
}

/// Descarga y cachea USDZ. Prioridad: `modelo_usdz` (ampliación del backend) → recurso del bundle
/// (solo modo demostración) → GLB informado sin conversión.
actor ModelRepository {
    static let maxBytes: Int64 = 40 * 1024 * 1024
    private let session: URLSession
    private let cacheDir: URL

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("ModelosUSDZ", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    enum ModelError: LocalizedError {
        case tooLarge, invalidType, download(String)
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "El modelo supera el tamaño permitido (40 MB)."
            case .invalidType: return "El archivo recibido no es un USDZ válido."
            case .download(let m): return "No se pudo descargar el modelo: \(m)"
            }
        }
    }

    func resolve(producto: ProductoDTO, slug: String, api: APIClient) async throws -> ModelSource {
        if let raw = producto.modeloUSDZ {
            if let receta = DishRecipe.from(referencia: raw) {
                return .receta(receta)
            }
            if raw.hasPrefix("bundle:") {
                let name = String(raw.dropFirst("bundle:".count))
                if let url = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "usdz") {
                    return .usdz(url, origen: "incluido en la app, CC0")
                }
            } else if let remote = api.absoluteURL(raw) {
                return .usdz(try await download(remote, slug: slug, productoId: producto.id), origen: "servidor Adbana")
            }
        }
        if let glb = api.absoluteURL(producto.modelo3D) {
            return .glbOnly(glb)
        }
        return .none
    }

    private func download(_ url: URL, slug: String, productoId: Int) async throws -> URL {
        let dest = cacheDir.appendingPathComponent("\(slug)-\(productoId).usdz")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 3600 {
            return dest
        }
        let (tmp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ModelError.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
        guard size > 0, size <= Self.maxBytes else { throw ModelError.tooLarge }
        // USDZ es un ZIP sin compresión: debe comenzar con la firma "PK\u{3}\u{4}".
        let handle = try FileHandle(forReadingFrom: tmp)
        let magic = try handle.read(upToCount: 4) ?? Data()
        try handle.close()
        guard magic == Data([0x50, 0x4B, 0x03, 0x04]) else { throw ModelError.invalidType }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
