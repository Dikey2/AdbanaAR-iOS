import SwiftUI

/// Panel del administrador: catálogo, banners, realidad aumentada, pedidos y ajustes.
/// Los cambios aplican a los restaurantes incluidos en la app y se guardan en este iPhone (SwiftData).
struct AdminPanelView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var urlServidor = ""
    @State private var mensaje: String?
    @State private var confirmarRestablecer = false
    @State private var confirmarBorrarPedidos = false
    @State private var cambiarPIN = false

    var body: some View {
        let restaurantes = env.restaurantes(incluirOcultos: true)
        let pedidos = env.historial.fetch()
        Form {
            Section {
                HStack(spacing: 12) {
                    resumen("\(restaurantes.count)", "Restaurantes", "storefront")
                    resumen("\(restaurantes.flatMap { $0.carta.carta.flatMap(\.productos) }.count)", "Platos", "fork.knife")
                    resumen("\(pedidos.filter { !$0.status.isFinal }.count)", "Pedidos activos", "bag")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(restaurantes) { r in
                    NavigationLink {
                        AdminRestauranteView(slug: r.slug)
                    } label: {
                        HStack(spacing: 12) {
                            LogoRestaurante(simbolo: r.simbolo, color: r.color, tam: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.nombre).font(.headline)
                                Text("\(r.carta.carta.flatMap(\.productos).count) platos · \(estadoAR(r))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !env.restauranteVisible(r.slug) {
                                Text("Oculto").font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.gray, in: Capsule())
                            }
                        }
                    }
                    .accessibilityIdentifier("admin-restaurante-\(r.slug)")
                }
            } header: { Text("Restaurantes y carta") } footer: {
                Text("Edita nombre, descripción, horario, modalidades, platos, precios y disponibilidad.")
            }

            Section("Aplicación") {
                NavigationLink { AdminBannersView() } label: { Label("Banners del inicio", systemImage: "rectangle.stack") }
                    .accessibilityIdentifier("adminBanners")
                NavigationLink { AfiliarRestauranteView() } label: { Label("Ubicación y AR de los locales", systemImage: "mappin.and.ellipse") }
                    .accessibilityIdentifier("abrirAfiliacion")
                NavigationLink { AdminPedidosView() } label: {
                    Label("Pedidos", systemImage: "list.bullet.rectangle")
                        .badge(pedidos.filter { !$0.status.isFinal }.count)
                }
                .accessibilityIdentifier("adminPedidos")
            }

            Section {
                TextField("URL del servidor", text: $urlServidor)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Guardar servidor") {
                    mensaje = env.updateBaseURL(urlServidor) ?? "Servidor actualizado: \(env.api.baseURL.absoluteString)"
                }
                Button("Cambiar PIN de administrador") { cambiarPIN = true }
                Button("Restablecer catálogo original", role: .destructive) { confirmarRestablecer = true }
                Button("Borrar pedidos de los restaurantes de la app", role: .destructive) { confirmarBorrarPedidos = true }
                if let mensaje { Text(mensaje).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Ajustes") } footer: {
                Text("Los restaurantes reales conectados por QR o código se administran en el panel web de Adbana; aquí solo se cambia el servidor.")
            }

            Section {
                Button {
                    withAnimation { env.adminActivo = false }
                } label: {
                    Label("Salir del modo administrador", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("salirAdmin")
            }
        }
        .navigationTitle("Administrador")
        .onAppear { urlServidor = env.preferences.apiBaseURL ?? "" }
        .confirmationDialog("¿Restablecer el catálogo?", isPresented: $confirmarRestablecer, titleVisibility: .visible) {
            Button("Restablecer", role: .destructive) {
                env.restablecerCatalogo()
                mensaje = "Catálogo y banners restablecidos."
            }
        } message: {
            Text("Se descartan los cambios de nombres, precios, disponibilidad, visibilidad y banners.")
        }
        .confirmationDialog("¿Borrar los pedidos?", isPresented: $confirmarBorrarPedidos, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                for p in env.historial.fetch() where DemoCatalog.esDemo(p.slug) {
                    env.historial.delete(slug: p.slug, pedidoId: p.pedidoId)
                }
                env.simulador.eliminarTodos()
                env.versionCatalogo += 1
                mensaje = "Pedidos eliminados."
            }
        } message: {
            Text("Solo se borran los pedidos de los restaurantes incluidos en la app. Los pedidos reales no se tocan.")
        }
        .sheet(isPresented: $cambiarPIN) { CambiarPINView() }
    }

    private func estadoAR(_ r: DemoRestaurante) -> String {
        switch env.estadoAR(slug: r.slug, configuracion: r.carta.restaurante.configuracion) {
        case .activa: return "AR activa"
        case .desactivada: return "AR desactivada"
        case .sinConfigurar: return "AR sin ubicación"
        }
    }

    private func resumen(_ valor: String, _ titulo: String, _ icono: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icono).foregroundStyle(Color.accentColor)
            Text(valor).font(.title2.bold())
            Text(titulo).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CambiarPINView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var actual = ""
    @State private var nuevo = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                SecureField("PIN actual", text: $actual).keyboardType(.numberPad)
                SecureField("Nuevo PIN (4 a 8 dígitos)", text: $nuevo).keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Cambiar PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard env.verificarPINAdmin(actual) else { error = "El PIN actual no es correcto."; return }
                        guard AppEnvironment.pinValido(nuevo) else { error = "El nuevo PIN debe tener de 4 a 8 dígitos."; return }
                        env.crearPINAdmin(nuevo)
                        dismiss()
                    }
                }
            }
        }
    }
}
