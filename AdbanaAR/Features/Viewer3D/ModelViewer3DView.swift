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
    /// Si se indica, muestra "Agregar al carrito" dentro del visor.
    var onAgregar: (() -> Void)? = nil
    var precio: Decimal? = nil
    /// Fondo de croma y sin controles: solo para generar las fotos de la carta.
    var modoFoto = false

    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var cargado = false
    @State private var agregado = false

    var body: some View {
        // Leer la visibilidad en `body` registra la dependencia: cada cambio reejecuta `update`.
        let visibilidad = personalizacion?.visibilidad ?? [:]
        let recetaId = fuente.receta?.id ?? ""
        NavigationStack {
            ZStack {
                if modoFoto {
                    Color(red: 1, green: 0, blue: 1).ignoresSafeArea()
                } else {
                    LinearGradient(colors: [Color(.systemBackground), Color.accentColor.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
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
                    // Iluminación de estudio: reflejos en salsa/queso/cerámica y luz principal con sombra.
                    if let img = TexturaProcedural.estudio(),
                       let entorno = try? await EnvironmentResource(equirectangular: img) {
                        ancla.components.set(ImageBasedLightComponent(source: .single(entorno), intensityExponent: 0.6))
                        ancla.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ancla))
                    }
                    let luz = DirectionalLight()
                    luz.light.intensity = 2500
                    luz.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 2)
                    luz.look(at: .zero, from: [0.4, 1.2, 0.6], relativeTo: nil)
                    content.add(luz)
                    content.add(ancla)
                    cargado = true
                } update: { content in
                    guard !visibilidad.isEmpty, let ancla = content.entities.first(where: { $0.name == "ancla-visor" }) else { return }
                    ProceduralDishBuilder.aplicar(visibilidad, recetaId: recetaId, a: ancla)
                }
                .realityViewCameraControls(.orbit)
                .accessibilityLabel("Modelo 3D de \(titulo). Arrastra para girar.")

                if !cargado && !modoFoto { ProgressView("Cargando modelo…") }
            }
            .safeAreaInset(edge: .bottom) {
                if !modoFoto { controles }
            }
            .toolbar(modoFoto ? .hidden : .automatic, for: .navigationBar)
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }.accessibilityIdentifier("cerrar3D")
                }
            }
        }
    }

    private var controles: some View {
                VStack(spacing: 8) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let personalizacion {
                        IngredientesPanel(personalizacion: personalizacion, compacto: true)
                    } else {
                        Text(fuente.descripcion).font(.footnote).multilineTextAlignment(.center)
                    }
                    Text("Arrastra para girar · pellizca para acercar").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if let onAgregar {
                            Button {
                                onAgregar()
                                withAnimation(.spring) { agregado = true }
                                Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { agregado = false } }
                            } label: {
                                Label(agregado ? "Agregado" : "Agregar \(precio.map { Money.format($0) } ?? "")",
                                      systemImage: agregado ? "checkmark" : "cart.badge.plus")
                                    .frame(maxWidth: .infinity)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("agregarDesde3D")
                        }
                        if let onAbrirAR {
                            Button(action: onAbrirAR) {
                                Label("Ver en mi mesa", systemImage: "arkit").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("verARDesde3D")
                        }
                    }
                    .controlSize(.large)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
    }
}
