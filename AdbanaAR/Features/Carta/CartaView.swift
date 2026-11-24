import SwiftUI

struct CartaView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart
    @State private var filtro = ""
    @State private var aviso: String?

    var body: some View {
        if let carta = env.carta {
            let demo = env.restaurante(slug: carta.restaurante.slug, incluirOcultos: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    let _ = env.versionGeocercas
                    CartaCabecera(carta: carta, demo: demo, esDemo: env.isDemo,
                                  estadoAR: env.estadoAR(slug: carta.restaurante.slug, configuracion: carta.restaurante.configuracion))
                    ForEach(categorias(carta), id: \.identity) { cat in
                        Text(cat.nombre)
                            .font(.title3.bold())
                            .padding(.horizontal)
                            .padding(.top, 22)
                            .padding(.bottom, 6)
                        ForEach(cat.productos) { p in
                            // Destino directo: NavigationLink(value:) no navegaba en iOS 26 dentro de una
                            // vista empujada con navigationDestination(isPresented:) (verificado con UI test).
                            NavigationLink {
                                ProductoDetailView(producto: p, slug: carta.restaurante.slug)
                            } label: {
                                ProductoRow(producto: p, baseURL: env.api)
                                    .padding(.horizontal)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("producto-\(p.id)")
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemBackground))
            .searchable(text: $filtro, prompt: "Buscar en \(carta.restaurante.nombre)")
            .navigationTitle(carta.restaurante.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await refrescar(carta) }
            .safeAreaInset(edge: .bottom) {
                if cart.slug == carta.restaurante.slug, !cart.isEmpty {
                    Button { env.tab = .carrito } label: {
                        HStack {
                            Text("\(cart.totalUnits)")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(.white.opacity(0.25), in: Capsule())
                            Text("Ver carrito").font(.headline)
                            Spacer()
                            Text(Money.format(cart.estimatedTotal)).font(.headline).contentTransition(.numericText())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 54)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("verCarritoDesdeCarta")
                }
            }
            .animation(.snappy, value: cart.totalUnits)
            .overlay(alignment: .bottom) {
                if let aviso {
                    Text(aviso)
                        .font(.footnote)
                        .padding(10)
                        .background(.thinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }
            }
        } else {
            ContentUnavailableView("Sin carta", systemImage: "menucard", description: Text("Elige un restaurante primero."))
        }
    }

    private func categorias(_ carta: CartaResponse) -> [CategoriaDTO] {
        guard !filtro.isEmpty else { return carta.carta }
        return carta.carta.compactMap { c in
            let ps = c.productos.filter { $0.nombre.localizedCaseInsensitiveContains(filtro) }
            return ps.isEmpty ? nil : CategoriaDTO(id: c.id, nombre: c.nombre, productos: ps)
        }
    }

    private func refrescar(_ carta: CartaResponse) async {
        guard !env.isDemo else { return }
        do {
            let nueva: CartaResponse = try await env.api.send(Endpoints.carta(slug: carta.restaurante.slug, mesaCodigo: env.mesaCodigo))
            env.activate(carta: nueva, mesaCodigo: env.mesaCodigo)
        } catch let e as APIError {
            withAnimation { aviso = e.userMessage }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { aviso = nil }
        } catch {}
    }
}

/// Portada del restaurante: foto del plato estrella, logo, nombre, horario y modalidades.
struct CartaCabecera: View {
    let carta: CartaResponse
    let demo: DemoRestaurante?
    let esDemo: Bool
    var estadoAR: AppEnvironment.EstadoAR = .sinConfigurar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [(demo?.color ?? .accentColor).opacity(0.9), (demo?.color ?? .accentColor).opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let foto = demo.flatMap({ UIImage(named: $0.portada) }) {
                    Image(uiImage: foto).resizable().scaledToFit()
                        .frame(height: 170)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                        .padding(.bottom, 26)
                }
            }
            .frame(height: 200)
            .clipped()

            HStack(alignment: .bottom, spacing: 12) {
                LogoRestaurante(simbolo: demo?.simbolo ?? "fork.knife", color: demo?.color ?? .accentColor, tam: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(carta.restaurante.nombre).font(.title2.bold())
                    if let lema = demo?.lema { Text(lema).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.bottom, 4)
            }
            .padding(.horizontal)
            .offset(y: -30)
            .padding(.bottom, -22)

            VStack(alignment: .leading, spacing: 8) {
                if let d = carta.restaurante.configuracion?.descripcion { Text(d).font(.subheadline) }
                Group {
                    switch estadoAR {
                    case .activa(let zona):
                        Label("AR activa dentro del local · \(GeocercaAR.formatear(metros: zona.radioMetros))", systemImage: "arkit")
                            .foregroundStyle(Color.green)
                    case .desactivada:
                        Label("AR desactivada por el restaurante · 3D disponible", systemImage: "xmark.circle")
                            .foregroundStyle(Color.orange)
                    case .sinConfigurar:
                        Label("AR aún no activada en el local · 3D disponible", systemImage: "location.slash")
                            .foregroundStyle(Color.secondary)
                    }
                }
                .font(.caption.bold())
                HStack(spacing: 8) {
                    if let h = carta.restaurante.configuracion?.horario {
                        Label(h, systemImage: "clock").font(.caption.bold())
                    }
                    ForEach(carta.restaurante.modalidades) { m in
                        Label(m.titulo, systemImage: m.icono)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                if let m = carta.mesa {
                    Label("Mesa del QR: \(m.nombre)", systemImage: "qrcode")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Logo genérico (símbolo sobre color de marca). No se usan logos de marcas reales.
struct LogoRestaurante: View {
    let simbolo: String
    let color: Color
    var tam: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: simbolo)
                .font(.system(size: tam * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: tam, height: tam)
        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

struct ProductoRow: View {
    let producto: ProductoDTO
    let baseURL: APIClient

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(producto.nombre).font(.headline).foregroundStyle(.primary)
                if let d = producto.descripcion {
                    Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(Money.format(producto.precio.value)).font(.subheadline.bold()).foregroundStyle(.primary)
                    if producto.modeloUSDZ != nil || producto.modelo3D != nil {
                        Label("3D · AR", systemImage: "cube.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .accessibilityLabel("Tiene modelo 3D")
                    }
                    if !producto.disponible {
                        Text("Agotado").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
            ProductoThumb(imagen: producto.imagen, api: baseURL, size: 96, esquina: 16)
        }
        .opacity(producto.disponible ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

struct ProductoThumb: View {
    /// URL remota o referencia local "foto:<nombre>" (foto incluida en la app).
    let imagen: String?
    let api: APIClient
    var size: CGFloat = 56
    var esquina: CGFloat = 12

    var body: some View {
        FotoPlato(imagen: imagen, api: api)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: esquina))
            .accessibilityHidden(true)
    }
}

/// Foto de un plato: local (render del propio modelo 3D, fondo transparente) o remota del backend.
struct FotoPlato: View {
    let imagen: String?
    let api: APIClient
    var contenido: ContentMode = .fit

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let local = Self.local(imagen) {
                Image(uiImage: local).resizable().aspectRatio(contentMode: contenido).padding(4)
            } else if imagen?.hasPrefix("foto:") != true, let url = api.absoluteURL(imagen) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() } else { placeholder }
                }
            } else { placeholder }
        }
    }

    static func local(_ imagen: String?) -> UIImage? {
        guard let imagen, imagen.hasPrefix("foto:") else { return nil }
        return UIImage(named: String(imagen.dropFirst(5)))
    }

    private var placeholder: some View {
        Image(systemName: "fork.knife").font(.title3).foregroundStyle(Color.accentColor.opacity(0.6))
    }
}
