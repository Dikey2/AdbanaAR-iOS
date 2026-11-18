import Foundation

/// Interpreta el contenido de un QR de Adbana. Formatos reales del backend:
/// `https://host/c/{slug}?mesa={uuid}`, `https://host/m/{slug}?mesa={uuid}` o un slug directo.
/// Solo se extrae el slug y el código de mesa; el restaurante se valida luego con GET /api/carta/{slug}.
enum QRLinkParser {
    struct Result: Equatable {
        let slug: String
        let mesaCodigo: String?
    }

    static func parse(_ raw: String) -> Result? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if Endpoints.isValidSlug(text.lowercased()), !text.contains("/") {
            return Result(slug: text.lowercased(), mesaCodigo: nil)
        }
        guard let comps = URLComponents(string: text) else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)
        guard let i = parts.firstIndex(where: { $0 == "c" || $0 == "m" || $0 == "carta" }), i + 1 < parts.count else {
            return nil
        }
        let slug = parts[i + 1].lowercased()
        guard Endpoints.isValidSlug(slug) else { return nil }
        let mesa = comps.queryItems?.first(where: { $0.name == "mesa" })?.value
        let mesaValida = mesa.flatMap { UUID(uuidString: $0) != nil ? $0.lowercased() : nil }
        return Result(slug: slug, mesaCodigo: mesaValida)
    }
}
