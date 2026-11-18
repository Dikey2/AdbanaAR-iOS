import RealityKit
import SwiftUI

/// Visor 3D sin cámara (RealityKit, iOS 18+). Funciona también en el simulador y es el
/// modo alternativo cuando el dispositivo no admite AR o no hay permiso de cámara.
struct ModelViewer3DView: View {
    let titulo: String
    let fuente: ModelSource
    var personalizacion: DishCustomization? = nil
    /// Si se indica, muestra "Ver en mi mesa" para pasar del visor a AR.
    var onAbrirAR: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var cargado = false

    var body: some View {
        // Leer la visibilidad en `body` registra la dependencia: cada cambio reejecuta `update`.
        let visibilidad = personalizacion?.visibilidad ?? [:]
        let recetaId = fuente.receta?.id ?? ""
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color.accentColor.opacity(0.15)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                RealityView { content in
                    content.camera = .virtual
                    let ancla = Entity()
                    ancla.name = "ancla-visor"
                    do {
                        ancla.addChild(try await DishEntityFactory.load(fuente))
                    } catch {
                        self.error = "No se pudo cargar el modelo: \(error.localizedDescription)"
                        ancla.addChild(DishEntityFactory.placeholder())
                    }
                    // Solo en el visor: se amplía y se inclina para verlo de frente a la cámara virtual.
                    // La escala física real (metros) se conserva intacta en la vista AR.
                    let b = ancla.visualBounds(relativeTo: nil)
                    let ancho = max(b.extents.x, b.extents.z, 0.01)
                    ancla.scale = SIMD3<Float>(repeating: 0.9 / ancho)
                    ancla.orientation = simd_quatf(angle: .pi / 5, axis: [1, 0, 0])
                    ancla.position = [0, -0.05, 0]
                    content.add(ancla)
                    cargado = true
                } update: { content in
                    guard !visibilidad.isEmpty, let ancla = content.entities.first(where: { $0.name == "ancla-visor" }) else { return }
                    ProceduralDishBuilder.aplicar(visibilidad, recetaId: recetaId, a: ancla)
                }
                .realityViewCameraControls(.orbit)
                .accessibilityLabel("Modelo 3D de \(titulo). Arrastra para girar.")

                if !cargado { ProgressView("Cargando modelo…") }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let personalizacion {
                        IngredientesPanel(personalizacion: personalizacion, compacto: true)
                    } else {
                        Text(fuente.descripcion).font(.footnote).multilineTextAlignment(.center)
                    }
                    Text("Arrastra para girar · pellizca para acercar").font(.caption).foregroundStyle(.secondary)
                    if let onAbrirAR {
                        Button(action: onAbrirAR) {
                            Label("Ver en mi mesa", systemImage: "arkit").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("verARDesde3D")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }.accessibilityIdentifier("cerrar3D")
                }
            }
        }
    }
}
