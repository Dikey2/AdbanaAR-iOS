import SwiftUI

struct CartaView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart
    @State private var filtro = ""
    @State private var refrescando = false
    @State private var aviso: String?

    var body: some View {
        if let carta = env.carta {
            List {
                header(carta)
                ForEach(categorias(carta), id: \.identity) { cat in
                    Section(cat.nombre) {
                        ForEach(cat.productos) { p in
                            // Destino directo: NavigationLink(value:) no navegaba en iOS 26 dentro de una
                            // vista empujada con navigationDestination(isPresented:) (verificado con UI test).
                            NavigationLink {
                                ProductoDetailView(producto: p, slug: carta.restaurante.slug)
                            } label: {
                                ProductoRow(producto: p, baseURL: env.api)
                            }
                            .accessibilityIdentifier("producto-\(p.id)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $filtro, prompt: "Buscar plato")
            .navigationTitle(carta.restaurante.nombre)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await refrescar(carta) }
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

    @ViewBuilder
    private func header(_ carta: CartaResponse) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if env.isDemo {
                    Label("Datos de demostración locales: no se envían pedidos.", systemImage: "info.circle")
                        .font(.footnote.bold())
                        .foregroundStyle(.orange)
                }
                if let d = carta.restaurante.configuracion?.descripcion { Text(d).font(.subheadline) }
                if let h = carta.restaurante.configuracion?.horario { Label(h, systemImage: "clock").font(.caption) }
                if let m = carta.mesa {
                    Label("Mesa del QR: \(m.nombre)", systemImage: "qrcode")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                HStack {
                    ForEach(carta.restaurante.modalidades) { m in
                        Label(m.titulo, systemImage: m.icono)
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
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

struct ProductoRow: View {
    let producto: ProductoDTO
    let baseURL: APIClient

    var body: some View {
        HStack(spacing: 12) {
            ProductoThumb(url: baseURL.absoluteURL(producto.imagen))
            VStack(alignment: .leading, spacing: 4) {
                Text(producto.nombre).font(.headline)
                if let d = producto.descripcion {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(Money.format(producto.precio.value)).font(.subheadline.bold())
                    if producto.modeloUSDZ != nil || producto.modelo3D != nil {
                        Image(systemName: "cube.fill").font(.caption).foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Tiene modelo 3D")
                    }
                    if !producto.disponible {
                        Text("Agotado").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.red, in: Capsule())
                    }
                }
            }
        }
        .opacity(producto.disponible ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }
}

struct ProductoThumb: View {
    let url: URL?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.accentColor.opacity(0.12)
            Image(systemName: "fork.knife").foregroundStyle(Color.accentColor)
        }
    }
}
