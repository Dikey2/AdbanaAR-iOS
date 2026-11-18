import ARKit
import Combine
import Observation
import Photos
import RealityKit
import SwiftUI

/// Controla la sesión ARKit + RealityKit: detección de planos horizontales (no reconoce
/// semánticamente una "mesa"), retículo con vista previa, colocación anclada con `ARAnchor`,
/// movimiento/giro, ingredientes en vivo, estados de seguimiento y captura de foto.
@MainActor
@Observable
final class ARPlacementController {
    enum Fase: Equatable {
        case buscandoSuperficie
        /// Hay planos horizontales, pero el centro de la pantalla no apunta a uno.
        case superficieDetectada
        /// El retículo está sobre un plano: se puede pulsar "Colocar plato".
        case listoParaColocar
        case colocado
        case error(String)
    }

    private(set) var fase: Fase = .buscandoSuperficie
    /// Aviso de seguimiento limitado / sesión interrumpida (independiente de la fase).
    private(set) var avisoSeguimiento: String?
    private(set) var mensajeFoto: String?
    var escalaLibre = false { didSet { aplicarGestos() } }

    @ObservationIgnored weak var arView: ARView?
    @ObservationIgnored private var arAnchor: ARAnchor?
    @ObservationIgnored private var anchorEntity: AnchorEntity?
    @ObservationIgnored private var contenedor: ModelEntity?
    @ObservationIgnored private var plantilla: Entity?
    @ObservationIgnored private var reticulo: AnchorEntity?
    @ObservationIgnored private var vistaPrevia: Entity?
    @ObservationIgnored private var gestos: [EntityGestureRecognizer] = []
    @ObservationIgnored private var suscripcion: Cancellable?
    @ObservationIgnored private var hayPlanos = false
    @ObservationIgnored private var ultimoHit: simd_float4x4?
    @ObservationIgnored private var visibilidad: [String: Bool] = [:]
    @ObservationIgnored private var recetaId = ""

    static let nombreAnchor = "adbana-plato"

    func configurar(_ view: ARView, fuente: ModelSource) {
        arView = view
        recetaId = fuente.receta?.id ?? ""
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isLightEstimationEnabled = true
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coaching.frame = view.bounds
        view.addSubview(coaching)

        crearReticulo(en: view)
        suscripcion = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.actualizarReticulo() }
        }

        Task {
            do { plantilla = try await DishEntityFactory.load(fuente) }
            catch {
                plantilla = DishEntityFactory.placeholder()
                fase = .error("No se pudo cargar el modelo; se usa una representación genérica.")
            }
            crearVistaPrevia()
        }
    }

    // MARK: Retículo y vista previa

    private func crearReticulo(en view: ARView) {
        let anchor = AnchorEntity(world: .zero)
        var anillo = UnlitMaterial(color: .white)
        anillo.blending = .transparent(opacity: 0.9)
        var disco = UnlitMaterial(color: .white)
        disco.blending = .transparent(opacity: 0.18)
        let borde = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: 0.15), materials: [anillo])
        let interior = ModelEntity(mesh: .generateCylinder(height: 0.0012, radius: 0.142), materials: [disco])
        anchor.addChild(borde)
        anchor.addChild(interior)
        anchor.isEnabled = false
        view.scene.addAnchor(anchor)
        reticulo = anchor
    }

    private func crearVistaPrevia() {
        guard let plantilla, let reticulo else { return }
        let previa = plantilla.clone(recursive: true)
        previa.components.set(OpacityComponent(opacity: 0.45))
        if !visibilidad.isEmpty { ProceduralDishBuilder.aplicar(visibilidad, recetaId: recetaId, a: previa) }
        reticulo.addChild(previa)
        vistaPrevia = previa
    }

    private func actualizarReticulo() {
        guard let arView, let reticulo else { return }
        guard fase != .colocado else { reticulo.isEnabled = false; return }
        let centro = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let hit = arView.raycast(from: centro, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            ?? arView.raycast(from: centro, allowing: .estimatedPlane, alignment: .horizontal).first
        if let hit {
            ultimoHit = hit.worldTransform
            reticulo.setTransformMatrix(hit.worldTransform, relativeTo: nil)
            reticulo.isEnabled = true
            if case .error = fase { return }
            if fase != .listoParaColocar { fase = .listoParaColocar }
        } else {
            ultimoHit = nil
            reticulo.isEnabled = false
            if case .error = fase { return }
            let nueva: Fase = hayPlanos ? .superficieDetectada : .buscandoSuperficie
            if fase != nueva { fase = nueva }
        }
    }

    func planosDetectados() { hayPlanos = true }

    // MARK: Colocación anclada

    /// Coloca el plato donde apunta el retículo.
    func colocarEnReticulo() {
        guard let ultimoHit else { return }
        anclar(en: ultimoHit)
    }

    /// Toque en pantalla: coloca o reubica el plato sobre un plano horizontal.
    func colocar(en punto: CGPoint) {
        guard let arView else { return }
        guard let hit = arView.raycast(from: punto, allowing: .estimatedPlane, alignment: .horizontal).first else { return }
        anclar(en: hit.worldTransform)
    }

    private func anclar(en transform: simd_float4x4) {
        guard let arView, let plantilla else { return }
        // Un ARAnchor registra el punto en el mapa del mundo de ARKit: el plato permanece fijo
        // al caminar alrededor y ARKit lo corrige al relocalizar.
        if let viejo = arAnchor { arView.session.remove(anchor: viejo) }
        let nuevo = ARAnchor(name: Self.nombreAnchor, transform: transform)
        arView.session.add(anchor: nuevo)
        arAnchor = nuevo

        if let anchorEntity, let contenedor {
            anchorEntity.removeChild(contenedor)
            arView.scene.removeAnchor(anchorEntity)
        }
        let entidadAncla = AnchorEntity(anchor: nuevo)
        let caja = contenedor ?? {
            let caja = ModelEntity()
            let modelo = plantilla.clone(recursive: true)
            modelo.name = "modelo"
            caja.addChild(modelo)
            if !visibilidad.isEmpty { ProceduralDishBuilder.aplicar(visibilidad, recetaId: recetaId, a: modelo) }
            let b = modelo.visualBounds(relativeTo: caja)
            caja.collision = CollisionComponent(shapes: [ShapeResource.generateBox(size: b.extents).offsetBy(translation: b.center)])
            return caja
        }()
        caja.position = .zero
        entidadAncla.addChild(caja)
        arView.scene.addAnchor(entidadAncla)
        anchorEntity = entidadAncla
        contenedor = caja
        aplicarGestos()
        fase = .colocado
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func girar(grados: Float) {
        guard let contenedor else { return }
        let q = simd_quatf(angle: grados * .pi / 180, axis: [0, 1, 0])
        contenedor.move(to: Transform(scale: contenedor.scale, rotation: q * contenedor.orientation, translation: contenedor.position),
                        relativeTo: contenedor.parent, duration: 0.25)
    }

    /// Retira el plato y vuelve a mostrar el retículo (recupera la escala realista).
    func retirar() {
        gestos.forEach { arView?.removeGestureRecognizer($0) }
        gestos = []
        if let arAnchor { arView?.session.remove(anchor: arAnchor) }
        if let anchorEntity { arView?.scene.removeAnchor(anchorEntity) }
        arAnchor = nil
        anchorEntity = nil
        contenedor = nil
        escalaLibre = false
        fase = hayPlanos ? .superficieDetectada : .buscandoSuperficie
    }

    // MARK: Ingredientes

    func aplicar(visibilidad nueva: [String: Bool]) {
        visibilidad = nueva
        guard !nueva.isEmpty else { return }
        if let modelo = contenedor?.findEntity(named: "modelo") {
            ProceduralDishBuilder.aplicar(nueva, recetaId: recetaId, a: modelo)
        }
        if let vistaPrevia { ProceduralDishBuilder.aplicar(nueva, recetaId: recetaId, a: vistaPrevia) }
    }

    // MARK: Seguimiento

    func seguimiento(_ estado: ARCamera.TrackingState) {
        switch estado {
        case .normal: avisoSeguimiento = nil
        case .notAvailable: avisoSeguimiento = "Seguimiento no disponible."
        case .limited(let razon):
            switch razon {
            case .initializing: avisoSeguimiento = "Iniciando seguimiento…"
            case .excessiveMotion: avisoSeguimiento = "Seguimiento limitado: mueve el iPhone más despacio."
            case .insufficientFeatures: avisoSeguimiento = "Seguimiento limitado: apunta a una superficie con más textura o mejor luz."
            case .relocalizing: avisoSeguimiento = "Reubicando el plato… vuelve a apuntar a la zona anterior."
            @unknown default: avisoSeguimiento = "Seguimiento limitado."
            }
        }
    }

    func interrumpida(_ si: Bool) {
        avisoSeguimiento = si ? "Sesión AR interrumpida." : "Sesión reanudada: reubicando…"
    }

    // MARK: Foto

    /// Captura cámara + plato virtual y la guarda en Fotos solo tras la acción del usuario.
    func tomarFoto() {
        guard let arView else { return }
        arView.snapshot(saveToHDR: false) { [weak self] imagen in
            guard let imagen else {
                Task { @MainActor in self?.mensajeFoto = "No se pudo capturar la imagen." }
                return
            }
            Task { @MainActor in await self?.guardar(imagen) }
        }
    }

    private func guardar(_ imagen: UIImage) async {
        let estado = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard estado == .authorized || estado == .limited else {
            mensajeFoto = "Sin permiso para guardar en Fotos. Puedes activarlo en Ajustes."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: imagen)
            }
            mensajeFoto = "Foto guardada en tu galería."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            mensajeFoto = "No se pudo guardar la foto: \(error.localizedDescription)"
        }
    }

    func limpiarMensajeFoto() { mensajeFoto = nil }

    func falloSesion(_ mensaje: String) {
        fase = .error(mensaje + " Cierra y vuelve a abrir la vista AR, o usa el visor 3D.")
    }

    func pausar() {
        suscripcion?.cancel()
        suscripcion = nil
        arView?.session.pause()
    }

    private func aplicarGestos() {
        guard let arView, let contenedor else { return }
        gestos.forEach { arView.removeGestureRecognizer($0) }
        var tipos: ARView.EntityGestures = [.translation, .rotation]
        if escalaLibre { tipos.insert(.scale) } else { contenedor.scale = .one }
        gestos = arView.installGestures(tipos, for: contenedor)
    }
}

struct ARPlacementView: View {
    let titulo: String
    let fuente: ModelSource
    var personalizacion: DishCustomization? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var controller = ARPlacementController()
    @State private var mostrarIngredientes = false

    var body: some View {
        ZStack {
            ARViewContainer(controller: controller, fuente: fuente)
                .ignoresSafeArea()
                .accessibilityLabel("Vista de cámara en realidad aumentada")

            VStack {
                HStack {
                    Text(titulo).font(.headline)
                    Spacer()
                    Button { controller.tomarFoto() } label: {
                        Image(systemName: "camera.circle.fill").font(.title)
                    }
                    .disabled(controller.fase != .colocado)
                    .accessibilityLabel("Tomar foto del plato")
                    Button { controller.pausar(); dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    .accessibilityLabel("Cerrar realidad aumentada")
                }
                .padding()
                .background(.ultraThinMaterial)

                if let aviso = controller.avisoSeguimiento {
                    Label(aviso, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.bold())
                        .padding(8)
                        .background(.yellow.opacity(0.85), in: Capsule())
                        .foregroundStyle(.black)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let foto = controller.mensajeFoto {
                    Text(foto).font(.footnote).padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .task { try? await Task.sleep(for: .seconds(2.5)); controller.limpiarMensajeFoto() }
                }

                Spacer()

                VStack(spacing: 10) {
                    Text(mensaje)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                    if !fuente.hasNativeModel {
                        Text(fuente.descripcion).font(.caption).multilineTextAlignment(.center)
                    }
                    if controller.fase == .listoParaColocar {
                        Button { controller.colocarEnReticulo() } label: {
                            Label("Colocar plato", systemImage: "hand.tap.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("colocarPlato")
                    }
                    if controller.fase == .colocado {
                        HStack(spacing: 12) {
                            Button { controller.girar(grados: -45) } label: { Label("Girar a la izquierda", systemImage: "rotate.left") }
                            Button { controller.girar(grados: 45) } label: { Label("Girar a la derecha", systemImage: "rotate.right") }
                            Button(role: .destructive) { controller.retirar() } label: {
                                Label("Retirar plato", systemImage: "trash")
                            }
                            if personalizacion != nil {
                                Button { withAnimation(.snappy) { mostrarIngredientes.toggle() } } label: {
                                    Label("Ingredientes", systemImage: "slider.horizontal.3")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        Toggle("Permitir cambiar tamaño", isOn: $controller.escalaLibre)
                            .font(.footnote)
                    }
                    if let personalizacion, mostrarIngredientes || controller.fase != .colocado {
                        IngredientesPanel(personalizacion: personalizacion, compacto: true)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Text(controller.escalaLibre ? "Tamaño libre (no realista)" : escalaTexto)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
            .animation(.easeInOut, value: controller.fase)
            .animation(.easeInOut, value: controller.avisoSeguimiento)
        }
        .onAppear { controller.aplicar(visibilidad: personalizacion?.visibilidad ?? [:]) }
        .onChange(of: personalizacion?.version) { _, _ in
            controller.aplicar(visibilidad: personalizacion?.visibilidad ?? [:])
        }
        .onDisappear { controller.pausar() }
    }

    private var escalaTexto: String {
        let d = fuente.receta?.diametroPlato ?? DishEntityFactory.diametroReferencia
        return "Escala aproximada real: plato de \(Int((d * 100).rounded())) cm de diámetro"
    }

    private var mensaje: String {
        switch controller.fase {
        case .buscandoSuperficie: return "Buscando superficie: mueve el iPhone lentamente sobre la mesa."
        case .superficieDetectada: return "Superficie detectada. Apunta el centro de la pantalla hacia ella."
        case .listoParaColocar: return "Listo para colocar: pulsa \"Colocar plato\" o toca la mesa."
        case .colocado: return "Plato colocado. Camina alrededor · arrastra para mover · gira con dos dedos."
        case .error(let m): return m
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let controller: ARPlacementController
    let fuente: ModelSource

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session.delegate = context.coordinator
        controller.configurar(view, fuente: fuente)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject, ARSessionDelegate {
        let controller: ARPlacementController
        init(controller: ARPlacementController) { self.controller = controller }

        @MainActor @objc func tap(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            controller.colocar(en: g.location(in: view))
        }

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            let hayPlano = anchors.contains { ($0 as? ARPlaneAnchor)?.alignment == .horizontal }
            guard hayPlano else { return }
            Task { @MainActor in self.controller.planosDetectados() }
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let estado = camera.trackingState
            Task { @MainActor in self.controller.seguimiento(estado) }
        }

        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in self.controller.interrumpida(true) }
        }

        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in self.controller.interrumpida(false) }
        }

        /// Permite a ARKit relocalizar tras una interrupción y conservar el anclaje del plato.
        nonisolated func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { true }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let msg = "Error de AR: \(error.localizedDescription)"
            Task { @MainActor in self.controller.falloSesion(msg) }
        }
    }
}
