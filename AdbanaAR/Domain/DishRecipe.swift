import Foundation
import Observation

/// Receta visual de un plato 3D propio: identificadores estables de cada componente
/// y qué puede personalizar el cliente. No contiene precios: el precio pertenece al backend.
struct DishRecipe: Equatable, Hashable, Sendable, Identifiable {
    struct Ingrediente: Equatable, Hashable, Sendable, Identifiable {
        /// Identificador estable; coincide con el nombre de la entidad RealityKit.
        let id: String
        let nombre: String
        /// Obligatorio = forma parte del plato y no se puede quitar.
        let obligatorio: Bool
    }

    /// Grupo de opciones mutuamente excluyentes (p. ej. guarnición). Cada opción es una entidad.
    struct GrupoVariante: Equatable, Hashable, Sendable, Identifiable {
        let id: String
        let nombre: String
        let opciones: [Ingrediente]
        let predeterminada: String
    }

    let id: String
    let nombre: String
    /// Diámetro del recipiente en metros (unidad de RealityKit).
    let diametroPlato: Float
    let ingredientes: [Ingrediente]
    let variantes: [GrupoVariante]

    var opcionales: [Ingrediente] { ingredientes.filter { !$0.obligatorio } }

    /// Referencia usada por el catálogo: `receta:<id>`.
    static let prefijoReferencia = "receta:"

    static func from(referencia: String) -> DishRecipe? {
        guard referencia.hasPrefix(prefijoReferencia) else { return nil }
        let id = String(referencia.dropFirst(prefijoReferencia.count))
        return catalogo.first { $0.id == id }
    }

    static let catalogo: [DishRecipe] = [pizza, hamburguesa, pollo]

    static let pizza = DishRecipe(
        id: "pizza", nombre: "Pizza", diametroPlato: 0.30,
        ingredientes: [
            .init(id: "base", nombre: "Masa", obligatorio: true),
            .init(id: "salsa", nombre: "Salsa de tomate", obligatorio: true),
            .init(id: "queso", nombre: "Queso", obligatorio: false),
            .init(id: "tomate", nombre: "Tomate", obligatorio: false),
            .init(id: "champinones", nombre: "Champiñones", obligatorio: false),
            .init(id: "aceitunas", nombre: "Aceitunas", obligatorio: false),
        ],
        variantes: []
    )

    static let hamburguesa = DishRecipe(
        id: "hamburguesa", nombre: "Hamburguesa", diametroPlato: 0.26,
        ingredientes: [
            .init(id: "pan_inferior", nombre: "Pan inferior", obligatorio: true),
            .init(id: "carne", nombre: "Carne", obligatorio: true),
            .init(id: "queso", nombre: "Queso", obligatorio: false),
            .init(id: "tomate", nombre: "Tomate", obligatorio: false),
            .init(id: "cebolla", nombre: "Cebolla", obligatorio: false),
            .init(id: "lechuga", nombre: "Lechuga", obligatorio: false),
            .init(id: "pan_superior", nombre: "Pan superior", obligatorio: true),
        ],
        variantes: []
    )

    static let pollo = DishRecipe(
        id: "pollo", nombre: "Pollo a la plancha", diametroPlato: 0.28,
        ingredientes: [
            .init(id: "pollo", nombre: "Pechuga de pollo", obligatorio: true),
            .init(id: "salsa_criolla", nombre: "Salsa criolla", obligatorio: false),
            .init(id: "limon", nombre: "Limón", obligatorio: false),
        ],
        variantes: [
            .init(id: "guarnicion", nombre: "Guarnición", opciones: [
                .init(id: "papas", nombre: "Papas fritas", obligatorio: false),
                .init(id: "arroz", nombre: "Arroz", obligatorio: false),
                .init(id: "ensalada", nombre: "Ensalada", obligatorio: false),
            ], predeterminada: "papas"),
        ]
    )
}

/// Estado de personalización compartido por detalle, visor 3D y AR.
/// Solo describe preferencias visuales/de cocina; NO modifica precios.
@MainActor
@Observable
final class DishCustomization {
    let receta: DishRecipe
    private(set) var quitados: Set<String> = []
    private(set) var variantes: [String: String]
    /// Aumenta en cada cambio para que AR/3D reapliquen el estado.
    private(set) var version = 0

    init(receta: DishRecipe) {
        self.receta = receta
        variantes = Dictionary(uniqueKeysWithValues: receta.variantes.map { ($0.id, $0.predeterminada) })
    }

    func incluido(_ ingredienteId: String) -> Bool { !quitados.contains(ingredienteId) }

    func alternar(_ ingredienteId: String) {
        guard let ing = receta.ingredientes.first(where: { $0.id == ingredienteId }), !ing.obligatorio else { return }
        if quitados.contains(ingredienteId) { quitados.remove(ingredienteId) } else { quitados.insert(ingredienteId) }
        version += 1
    }

    func seleccionar(variante grupoId: String, opcion: String) {
        guard let grupo = receta.variantes.first(where: { $0.id == grupoId }),
              grupo.opciones.contains(where: { $0.id == opcion }) else { return }
        variantes[grupoId] = opcion
        version += 1
    }

    func restaurar() {
        quitados = []
        variantes = Dictionary(uniqueKeysWithValues: receta.variantes.map { ($0.id, $0.predeterminada) })
        version += 1
    }

    /// Visibilidad de cada entidad identificada (ingredientes y opciones de variante).
    var visibilidad: [String: Bool] {
        var v: [String: Bool] = [:]
        for ing in receta.ingredientes { v[ing.id] = incluido(ing.id) }
        for grupo in receta.variantes {
            for op in grupo.opciones { v[op.id] = variantes[grupo.id] == op.id }
        }
        return v
    }

    var esPredeterminada: Bool {
        quitados.isEmpty && receta.variantes.allSatisfy { variantes[$0.id] == $0.predeterminada }
    }

    /// Texto legible para la cocina; nil si no hay cambios respecto de la receta.
    var resumen: String? {
        var partes: [String] = receta.ingredientes
            .filter { quitados.contains($0.id) }
            .map { "sin \($0.nombre.lowercased())" }
        for grupo in receta.variantes where variantes[grupo.id] != grupo.predeterminada {
            if let op = grupo.opciones.first(where: { $0.id == variantes[grupo.id] }) {
                partes.append("\(grupo.nombre.lowercased()): \(op.nombre.lowercased())")
            }
        }
        return partes.isEmpty ? nil : partes.joined(separator: ", ")
    }
}
