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
    @State private var verificandoUbicacion = false
    @State private var zonaActiva: GeocercaAR?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FotoPlato(imagen: producto.imagen, api: env.api)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .bottomTrailing) {
                        if fuente?.hasNativeModel == true {
                            Button { mostrar3D = true } label: {
                                Label("Girar en 3D", systemImage: "rotate.3d").font(.footnote.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .clipShape(Capsule())
                            .padding(10)
                        }
                    }
                    .accessibilityHidden(true)
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

                if let mensaje {
                    Text(mensaje).font(.footnote).foregroundStyle(.orange)
                        .transition(.opacity)
                }
                Text("Precio referencial. El total definitivo lo calcula el restaurante al registrar el pedido.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { barraAgregar }
        .navigationTitle(producto.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .task { await cargarModelo() }
        .fullScreenCover(isPresented: $mostrar3D) {
            ModelViewer3DView(titulo: producto.nombre, fuente: fuente ?? .none, personalizacion: personalizacion,
                              onAbrirAR: {
                                  mostrar3D = false
                                  Task { try? await Task.sleep(for: .milliseconds(450)); await abrirAR() }
                              },
                              onAgregar: producto.disponible ? { agregar() } : nil,
                              precio: producto.precio.value)
        }
        .fullScreenCover(isPresented: $mostrarAR) {
            ARPlacementView(titulo: producto.nombre, fuente: fuente ?? .none, personalizacion: personalizacion, geocerca: zonaActiva,
                            onAgregar: producto.disponible ? { agregar() } : nil)
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
                    Button { Task { await abrirAR() } } label: {
                        if verificandoUbicacion {
                            HStack { ProgressView(); Text("Ubicando…") }
                        } else {
                            Label("Ver en tu mesa", systemImage: "arkit")
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("verAR")
                }
                .disabled(cargandoModelo || verificandoUbicacion)
                zonaAviso
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Experiencia 3D / AR", systemImage: "cube.transparent")
        }
    }

    /// Estado de la zona AR del restaurante, visible antes de intentar abrir la cámara.
    @ViewBuilder
    private var zonaAviso: some View {
        let _ = env.versionGeocercas
        switch env.estadoAR(slug: slug, configuracion: env.carta?.restaurante.configuracion) {
        case .activa(let zona):
            Label("AR disponible solo dentro del restaurante (radio de \(GeocercaAR.formatear(metros: zona.radioMetros))).",
                  systemImage: "mappin.and.ellipse")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("zonaAR")
        case .desactivada:
            Label("El restaurante desactivó la realidad aumentada. Puedes verlo en 3D.", systemImage: "xmark.circle")
                .font(.caption).foregroundStyle(.orange)
                .accessibilityIdentifier("zonaARDesactivada")
        case .sinConfigurar:
            Label("Este restaurante aún no activó la AR en su local. Puedes verlo en 3D.", systemImage: "location.slash")
                .font(.caption).foregroundStyle(.orange)
                .accessibilityIdentifier("zonaARSinConfigurar")
        }
    }

    /// La AR solo se habilita si el cliente está dentro de la zona configurada por el restaurante afiliado.
    private func verificarUbicacion() async -> Bool {
        let nombre = env.carta?.restaurante.nombre ?? "El restaurante"
        let zona: GeocercaAR
        switch env.estadoAR(slug: slug, configuracion: env.carta?.restaurante.configuracion) {
        case .activa(let z): zona = z
        case .desactivada:
            avisoAR = "\(nombre) desactivó la realidad aumentada por el momento. Puedes ver el plato en 3D."
            return false
        case .sinConfigurar:
            avisoAR = "La realidad aumentada solo funciona dentro del restaurante afiliado. \(nombre) aún no configuró la ubicación de su local. Puedes ver el plato en 3D."
            return false
        }
        verificandoUbicacion = true
        defer { verificandoUbicacion = false }
        do {
            let actual = try await env.ubicacion.ubicacionActual()
            switch zona.evaluar(actual) {
            case .dentro:
                zonaActiva = zona
                return true
            case .fuera(let d):
                avisoAR = "Estás a \(GeocercaAR.formatear(metros: d)) de \(nombre). La realidad aumentada solo funciona dentro del local (radio de \(GeocercaAR.formatear(metros: zona.radioMetros))). Mientras tanto puedes ver el plato en 3D."
            case .precisionInsuficiente(let p):
                avisoAR = "Tu ubicación no es lo bastante precisa (±\(GeocercaAR.formatear(metros: max(p, 0)))). Activa \"Ubicación exacta\" para Adbana AR en Ajustes e inténtalo de nuevo."
            }
        } catch {
            avisoAR = error.localizedDescription
        }
        return false
    }

    /// Barra fija sobre la barra de pestañas: cantidad + agregar, siempre visible.
    @ViewBuilder
    private var barraAgregar: some View {
        if producto.disponible {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    Button { cantidad = max(1, cantidad - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                        .disabled(cantidad <= 1)
                    Text("\(cantidad)").font(.headline.monospacedDigit()).frame(minWidth: 24)
                        .contentTransition(.numericText())
                    Button { cantidad = min(CartStore.maxUnitsPerProduct, cantidad + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                }
                .background(Color(.secondarySystemBackground), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cantidad")
                .accessibilityValue("\(cantidad)")
                .accessibilityAdjustableAction { d in
                    if d == .increment { cantidad = min(CartStore.maxUnitsPerProduct, cantidad + 1) } else { cantidad = max(1, cantidad - 1) }
                }
                .accessibilityIdentifier("cantidadStepper")

                Button(action: agregar) {
                    HStack {
                        Image(systemName: agregado ? "checkmark" : "cart.badge.plus")
                            .contentTransition(.symbolEffect(.replace))
                        Text(agregado ? "Agregado" : "Agregar")
                        Spacer()
                        Text(Money.format(producto.precio.value * Decimal(cantidad)))
                            .contentTransition(.numericText())
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("agregarCarrito")
            }
            .animation(.snappy, value: cantidad)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
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
        guard await verificarUbicacion() else { return }
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
