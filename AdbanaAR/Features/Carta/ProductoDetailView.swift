import ARKit
import AVFoundation
import SwiftUI

struct ProductoDetailView: View {
    let producto: ProductoDTO
    let slug: String

    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart
    @State private var cantidad = 1
    @State private var fuente: ModelSource?
    @State private var personalizacion: DishCustomization?
    @State private var errorModelo: String?
    @State private var cargandoModelo = false
    @State private var mostrar3D = false
    @State private var mostrarAR = false
    @State private var avisoAR: String?
    @State private var agregado = false
    @State private var mensaje: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProductoThumb(url: env.api.absoluteURL(producto.imagen), size: 120)
                    .frame(maxWidth: .infinity)
                Text(producto.nombre).font(.title.bold())
                if let d = producto.descripcion { Text(d).foregroundStyle(.secondary) }
                HStack {
                    Text(Money.format(producto.precio.value)).font(.title2.bold())
                    Spacer()
                    Label(producto.disponible ? "Disponible" : "Agotado",
                          systemImage: producto.disponible ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(producto.disponible ? .green : .red)
                }

                modeloSection

                if let personalizacion {
                    GroupBox {
                        IngredientesPanel(personalizacion: personalizacion)
                    } label: {
                        Label("Personaliza tus ingredientes", systemImage: "slider.horizontal.3")
                    }
                }

                if producto.disponible {
                    Stepper("Cantidad: \(cantidad)", value: $cantidad, in: 1...CartStore.maxUnitsPerProduct)
                        .accessibilityIdentifier("cantidadStepper")
                    Button(action: agregar) {
                        Label(agregado ? "Agregado" : "Agregar al carrito",
                              systemImage: agregado ? "checkmark" : "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(env.isDemo && false)
                    .accessibilityIdentifier("agregarCarrito")
                }
                if let mensaje {
                    Text(mensaje).font(.footnote).foregroundStyle(.orange)
                        .transition(.opacity)
                }
                Text("Precio referencial. El total definitivo lo calcula el restaurante al registrar el pedido.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(producto.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargarModelo() }
        .fullScreenCover(isPresented: $mostrar3D) {
            ModelViewer3DView(titulo: producto.nombre, fuente: fuente ?? .none, personalizacion: personalizacion) {
                mostrar3D = false
                Task { try? await Task.sleep(for: .milliseconds(450)); await abrirAR() }
            }
        }
        .fullScreenCover(isPresented: $mostrarAR) {
            ARPlacementView(titulo: producto.nombre, fuente: fuente ?? .none, personalizacion: personalizacion)
        }
        .alert("Realidad aumentada", isPresented: Binding(get: { avisoAR != nil }, set: { if !$0 { avisoAR = nil } })) {
            Button("Ver en 3D") { mostrar3D = true }
            Button("Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cerrar", role: .cancel) {}
        } message: {
            Text(avisoAR ?? "")
        }
    }

    @ViewBuilder
    private var modeloSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if cargandoModelo {
                    HStack { ProgressView(); Text("Preparando modelo 3D…") }
                } else if let fuente {
                    Text(fuente.descripcion).font(.footnote)
                }
                if let errorModelo {
                    Text(errorModelo).font(.footnote).foregroundStyle(.red)
                }
                HStack {
                    Button { mostrar3D = true } label: { Label("Ver en 3D", systemImage: "cube") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("ver3D")
                    Button { Task { await abrirAR() } } label: { Label("Ver en tu mesa", systemImage: "arkit") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("verAR")
                }
                .disabled(cargandoModelo)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Experiencia 3D / AR", systemImage: "cube.transparent")
        }
    }

    private func agregar() {
        switch cart.add(producto, cantidad: cantidad, slug: slug, personalizacion: personalizacion?.resumen) {
        case .added:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { agregado = true; mensaje = nil }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation { agregado = false }
            }
        case .limitReached(let m): withAnimation { mensaje = m }
        case .unavailable: withAnimation { mensaje = "Producto agotado." }
        case .otherRestaurant: withAnimation { mensaje = "El carrito pertenece a otro restaurante." }
        }
    }

    private func cargarModelo() async {
        guard fuente == nil else { return }
        cargandoModelo = true
        defer { cargandoModelo = false }
        do {
            fuente = try await env.models.resolve(producto: producto, slug: slug, api: env.api)
            if let receta = fuente?.receta { personalizacion = DishCustomization(receta: receta) }
        } catch {
            errorModelo = error.localizedDescription
            fuente = producto.modelo3D.flatMap { env.api.absoluteURL($0) }.map { .glbOnly($0) } ?? ModelSource.none
        }
    }

    private func abrirAR() async {
        guard ARWorldTrackingConfiguration.isSupported else {
            avisoAR = "Este dispositivo no admite ARKit con seguimiento de superficies (por ejemplo, el simulador). Puedes ver el plato en el visor 3D."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            mostrarAR = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { mostrarAR = true }
            else { avisoAR = "Sin permiso de cámara no es posible usar la realidad aumentada." }
        default:
            avisoAR = "El permiso de cámara está desactivado. Actívalo en Ajustes para colocar el plato en tu mesa."
        }
    }
}
