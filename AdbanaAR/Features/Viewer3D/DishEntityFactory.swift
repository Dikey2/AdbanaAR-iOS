import Foundation
import RealityKit
import UIKit

/// Construye entidades RealityKit normalizadas para un plato.
enum DishEntityFactory {
    /// Diámetro aproximado de un plato servido. Los productos no traen medidas reales en la API,
    /// por lo que la escala es una aproximación documentada (no una medición).
    static let diametroReferencia: Float = 0.28

    @MainActor
    static func load(_ fuente: ModelSource) async throws -> Entity {
        switch fuente {
        case .usdz(let url, _):
            let entity = try await Entity(contentsOf: url)
            return normalize(entity, diametro: diametroReferencia)
        case .receta(let receta):
            // Construido en metros: no se normaliza para conservar la escala física.
            return ProceduralDishBuilder.build(receta)
        case .glbOnly, .none:
            return placeholder()
        }
    }

    /// Escala el modelo para que su mayor dimensión horizontal mida `diametro` metros
    /// y lo apoya sobre y = 0 (la superficie de la mesa).
    @MainActor
    static func normalize(_ entity: Entity, diametro: Float) -> Entity {
        let root = Entity()
        root.name = "plato"
        root.addChild(entity)
        let b = entity.visualBounds(relativeTo: root)
        let extent = max(b.extents.x, b.extents.z, 0.0001)
        let s = diametro / extent
        entity.scale *= SIMD3<Float>(repeating: s)
        let b2 = entity.visualBounds(relativeTo: root)
        entity.position -= SIMD3<Float>(b2.center.x, b2.min.y, b2.center.z)
        return root
    }

    /// Representación genérica (plato + domo) cuando no hay USDZ disponible.
    @MainActor
    static func placeholder() -> Entity {
        let root = Entity()
        root.name = "plato-generico"
        let plato = ModelEntity(mesh: .generateCylinder(height: 0.012, radius: 0.13),
                                materials: [SimpleMaterial(color: .white, roughness: 0.3, isMetallic: false)])
        plato.position.y = 0.006
        let comida = ModelEntity(mesh: .generateSphere(radius: 0.07),
                                 materials: [SimpleMaterial(color: UIColor(red: 0.85, green: 0.45, blue: 0.2, alpha: 1), roughness: 0.6, isMetallic: false)])
        comida.scale = SIMD3<Float>(1, 0.45, 1)
        comida.position.y = 0.02
        root.addChild(plato)
        root.addChild(comida)
        return root
    }
}
