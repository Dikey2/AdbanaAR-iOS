import CoreLocation
import MapKit
import SwiftUI

/// Afiliación del restaurante a la AR: el encargado, estando en su local, fija el centro
/// (su ubicación actual o un toque en el mapa) y el radio. Solo dentro de esa zona
/// los clientes pueden abrir la realidad aumentada; fuera de ella se ofrece el visor 3D.
struct AfiliarRestauranteView: View {
    @Environment(AppEnvironment.self) private var env

    private struct Opcion: Identifiable, Hashable {
        let slug: String
        let nombre: String
        let configuracion: ConfiguracionDTO?
        var id: String { slug }
    }

    @State private var seleccion: String = ""
    @State private var centro: CLLocationCoordinate2D?
    @State private var radio: Double = 60
    @State private var camara: MapCameraPosition = .automatic
    @State private var ubicando = false
    @State private var mensaje: String?
    @State private var error: String?

    private var opciones: [Opcion] {
        var lista: [Opcion] = []
        if let c = env.carta, !DemoCatalog.esDemo(c.restaurante.slug) {
            lista.append(Opcion(slug: c.restaurante.slug, nombre: c.restaurante.nombre, configuracion: c.restaurante.configuracion))
        }
        lista += env.restaurantes(incluirOcultos: true).map { Opcion(slug: $0.slug, nombre: $0.nombre, configuracion: $0.carta.restaurante.configuracion) }
        return lista
    }

    private var opcion: Opcion? { opciones.first { $0.slug == seleccion } }
    private var esRemota: Bool { env.geocercaEsRemota(opcion?.configuracion) }

    var body: some View {
        Form {
            Section {
                Picker("Restaurante", selection: $seleccion) {
                    ForEach(opciones) { Text($0.nombre).tag($0.slug) }
                }
                .accessibilityIdentifier("afiliarRestaurante")
            } footer: {
                Text("Elige tu restaurante y fija la zona del local. Hazlo estando dentro del restaurante.")
            }

            if env.geocerca(slug: seleccion, configuracion: opcion?.configuracion) != nil {
                let _ = env.versionGeocercas
                Section {
                    Toggle(isOn: Binding(
                        get: { env.estadoAR(slug: seleccion, configuracion: opcion?.configuracion) != .desactivada },
                        set: { activa in
                            guard let opcion else { return }
                            env.cambiarAR(activa: activa, slug: opcion.slug, restauranteNombre: opcion.nombre,
                                          configuracion: opcion.configuracion)
                            withAnimation {
                                mensaje = activa ? "Realidad aumentada activada en \(opcion.nombre)."
                                                 : "Realidad aumentada desactivada en \(opcion.nombre). Los clientes solo verán el 3D."
                            }
                        })) {
                        Label("Realidad aumentada activa", systemImage: "arkit")
                    }
                    .accessibilityIdentifier("toggleAR")
                } footer: {
                    Text("Apágala cuando no quieras que los clientes usen la AR (por ejemplo, en hora punta). La ubicación del local se conserva.")
                }
            }

            Section("Ubicación del local") {
                mapa
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                Button { Task { await usarUbicacionActual() } } label: {
                    if ubicando { HStack { ProgressView(); Text("Obteniendo ubicación…") } }
                    else { Label("Usar mi ubicación actual", systemImage: "location.fill") }
                }
                .disabled(ubicando || esRemota)
                .accessibilityIdentifier("usarMiUbicacion")
                if let centro {
                    LabeledContent("Centro", value: String(format: "%.5f, %.5f", centro.latitude, centro.longitude))
                        .font(.footnote)
                } else {
                    Text("También puedes tocar el mapa para marcar la entrada del local.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Radio permitido: \(GeocercaAR.formatear(metros: radio))")
                    Slider(value: $radio, in: GeocercaAR.radioMinimo...300, step: 5)
                        .accessibilityIdentifier("radioAR")
                }
                .disabled(esRemota)
            }

            Section {
                Button {
                    guard let centro, let opcion else { return }
                    env.guardarGeocerca(GeocercaAR(latitud: centro.latitude, longitud: centro.longitude, radioMetros: radio),
                                        slug: opcion.slug, restauranteNombre: opcion.nombre)
                    withAnimation { mensaje = "Listo: la AR de \(opcion.nombre) solo funcionará dentro de \(GeocercaAR.formatear(metros: radio)) de este punto." }
                } label: {
                    Label("Activar AR en este local", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(centro == nil || opcion == nil || esRemota)
                .accessibilityIdentifier("guardarZonaAR")

                if env.ubicacionLocal(slug: seleccion) != nil, !esRemota {
                    Button("Quitar ubicación AR", role: .destructive) {
                        env.borrarGeocerca(slug: seleccion)
                        centro = nil
                        withAnimation { mensaje = "Ubicación eliminada: la AR queda desactivada para este restaurante." }
                    }
                }
                if let mensaje { Label(mensaje, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.green) }
                if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red) }
            } footer: {
                Text(esRemota
                     ? "La ubicación de este restaurante la publica el servidor Adbana y no se puede cambiar desde la app."
                     : "La zona se guarda en este dispositivo. Para que aplique en todos los teléfonos, el servidor Adbana debe publicar `ubicacion_ar` (ver la propuesta en docs). El GPS puede tener un error de 5 a 30 m en interiores.")
            }
        }
        .navigationTitle("Afiliar restaurante")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if seleccion.isEmpty { seleccion = env.carta.map(\.restaurante.slug).flatMap { s in opciones.first { $0.slug == s }?.slug } ?? opciones.first?.slug ?? "" } }
        .onChange(of: seleccion, initial: true) { _, _ in cargarZona() }
    }

    private var mapa: some View {
        MapReader { proxy in
            Map(position: $camara) {
                UserAnnotation()
                if let centro {
                    MapCircle(center: centro, radius: radio)
                        .foregroundStyle(Color.accentColor.opacity(0.22))
                        .stroke(Color.accentColor, lineWidth: 2)
                    Marker(opcion?.nombre ?? "Restaurante", systemImage: "fork.knife", coordinate: centro)
                        .tint(Color.accentColor)
                }
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .onTapGesture { punto in
                guard !esRemota, let c = proxy.convert(punto, from: .local) else { return }
                centro = c
                mensaje = nil
            }
        }
    }

    private func cargarZona() {
        mensaje = nil; error = nil
        if let zona = env.geocerca(slug: seleccion, configuracion: opcion?.configuracion) {
            centro = zona.centro
            radio = zona.radioMetros
            camara = .region(MKCoordinateRegion(center: zona.centro, latitudinalMeters: zona.radioMetros * 5, longitudinalMeters: zona.radioMetros * 5))
        } else {
            centro = nil
            radio = 60
            camara = .userLocation(fallback: .automatic)
        }
    }

    private func usarUbicacionActual() async {
        ubicando = true; error = nil; mensaje = nil
        defer { ubicando = false }
        do {
            let l = try await env.ubicacion.ubicacionActual()
            guard l.horizontalAccuracy <= GeocercaAR.precisionMaxima else {
                error = "Precisión baja (±\(Int(l.horizontalAccuracy)) m). Activa la ubicación exacta o acércate a una ventana."
                return
            }
            centro = l.coordinate
            withAnimation {
                camara = .region(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: radio * 5, longitudinalMeters: radio * 5))
            }
            mensaje = "Ubicación tomada (precisión ±\(Int(l.horizontalAccuracy)) m)."
        } catch {
            self.error = error.localizedDescription
        }
    }
}
