import SwiftUI

/// Pantalla de inicio estilo app de delivery: cabecera de marca con buscador y carrusel,
/// accesos por rubro, logos y lista de restaurantes con carta 3D.
/// Los restaurantes listados aquí son de demostración (ficticios) y la interfaz lo indica;
/// los restaurantes reales se abren con su código o el QR de la mesa.
struct InicioView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart
    var onVerCarrito: () -> Void = {}

    @State private var busqueda = ""
    @State private var rubro: Rubro?
    @State private var abrirCarta = false
    @State private var conectar = false
    @State private var afiliar = false

    private var restaurantes: [DemoRestaurante] {
        env.restaurantes().filter { rubro == nil || $0.rubro == rubro }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        cabecera
                        if busqueda.isEmpty {
                            accesosPrincipales(proxy)
                            rubros
                            logos
                            listaRestaurantes.id("lista")
                            conexion
                        } else {
                            resultados
                        }
                    }
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.immediately)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $abrirCarta) { CartaView() }
            .navigationDestination(isPresented: $conectar) { RestaurantPickerView() }
            .navigationDestination(isPresented: $afiliar) { AdminAccesoView() }
        }
    }

    private func abrir(_ r: DemoRestaurante) {
        env.activate(carta: r.carta, mesaCodigo: nil)
        abrirCarta = true
    }

    // MARK: Cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Button { conectar = true } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Carta en realidad aumentada").font(.caption.weight(.medium)).opacity(0.85)
                            Text("Adbana AR").font(.title2.weight(.heavy))
                        }
                        Image(systemName: "chevron.down").font(.subheadline.bold())
                    }
                }
                .accessibilityLabel("Conectar con un restaurante")
                Spacer()
                Button { conectar = true } label: { Image(systemName: "qrcode.viewfinder") }
                    .accessibilityLabel("Escanear QR de la mesa")
                Button(action: onVerCarrito) {
                    Image(systemName: "cart")
                        .overlay(alignment: .topTrailing) {
                            if cart.totalUnits > 0 {
                                Text("\(cart.totalUnits)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .padding(4)
                                    .background(.white, in: Circle())
                                    .offset(x: 10, y: -8)
                            }
                        }
                }
                .accessibilityLabel("Carrito")
            }
            .font(.title2)
            .foregroundStyle(.white)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Restaurantes y platos", text: $busqueda)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityIdentifier("buscarInicio")
                if !busqueda.isEmpty {
                    Button { busqueda = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Color(.systemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            if busqueda.isEmpty, env.banners.contains(where: \.visible) { CarruselPromos(promos: env.banners.filter(\.visible)) }
        }
        .padding(.horizontal)
        .padding(.top, 64)
        .padding(.bottom, 22)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 64)
                .fill(Color.accentColor.gradient)
        }
    }

    // MARK: Accesos

    private func accesosPrincipales(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 14) {
            TarjetaAcceso(titulo: "Restaurantes", foto: "foto-combo_pollo", alto: 170) {
                rubro = nil
                withAnimation { proxy.scrollTo("lista", anchor: .top) }
            }
            .accessibilityIdentifier("accesoRestaurantes")
            TarjetaAcceso(titulo: "Postres", foto: "foto-torta_zanahoria", alto: 170) {
                withAnimation { rubro = .postres; proxy.scrollTo("lista", anchor: .top) }
            }
            .accessibilityIdentifier("accesoPostres")
        }
        .padding(.horizontal)
    }

    private var rubros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Rubro.allCases) { r in
                    TarjetaAcceso(titulo: r.titulo, foto: r.foto, alto: 128, ancho: 116, seleccionada: rubro == r) {
                        withAnimation(.snappy) { rubro = (rubro == r ? nil : r) }
                    }
                    .accessibilityIdentifier("rubro-\(r.rawValue)")
                }
            }
            .padding(.horizontal)
        }
    }

    private var logos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(env.restaurantes()) { r in
                    Button { abrir(r) } label: {
                        VStack(spacing: 6) {
                            LogoRestaurante(simbolo: r.simbolo, color: r.color, tam: 70)
                            Text(r.nombre).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        }
                        .frame(width: 82)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(r.nombre)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }

    private var listaRestaurantes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(rubro?.titulo ?? "Restaurantes con carta 3D").font(.title2.bold())
                Spacer()
                if rubro != nil {
                    Button("Ver todos") { withAnimation(.snappy) { rubro = nil } }.font(.subheadline.bold())
                }
            }
            Text("Mira cada plato en 3D a escala real antes de pedir")
                .font(.footnote).foregroundStyle(.secondary)
                .padding(.top, -8)
            ForEach(restaurantes) { r in
                Button { abrir(r) } label: { TarjetaRestaurante(restaurante: r) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("restaurante-\(r.slug)")
            }
        }
        .padding(.horizontal)
    }

    private var conexion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Estás en un restaurante?").font(.title3.bold())
            Button { conectar = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Escanea el QR de tu mesa").font(.headline)
                        Text("O escribe el código del restaurante para ver su carta real y pedir.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("conectarRestaurante")

            Button { afiliar = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color(hex: 0x2F3A4A), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿Tienes un restaurante?").font(.headline)
                        Text("Afílialo y activa la realidad aumentada solo dentro de tu local.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("afiliarDesdeInicio")

            Button {
                env.activate(carta: DemoCatalog.carta, mesaCodigo: nil)
                abrirCarta = true
            } label: {
                Label("Carta de pruebas técnicas", systemImage: "wrench.and.screwdriver")
                    .font(.footnote)
            }
            .padding(.top, 4)
            .accessibilityIdentifier("modoDemo")
        }
        .padding(.horizontal)
    }

    // MARK: Búsqueda

    private var resultados: some View {
        let platos = env.restaurantes().flatMap { r in
            r.carta.carta.flatMap(\.productos)
                .filter { $0.nombre.localizedCaseInsensitiveContains(busqueda) }
                .map { (r, $0) }
        }
        let locales = env.restaurantes().filter {
            $0.nombre.localizedCaseInsensitiveContains(busqueda) || $0.rubro.titulo.localizedCaseInsensitiveContains(busqueda)
        }
        return VStack(alignment: .leading, spacing: 14) {
            if locales.isEmpty && platos.isEmpty {
                ContentUnavailableView.search(text: busqueda)
            }
            if !locales.isEmpty {
                Text("Locales").font(.title3.bold())
                ForEach(locales) { r in
                    Button { abrir(r) } label: { TarjetaRestaurante(restaurante: r) }.buttonStyle(.plain)
                }
            }
            if !platos.isEmpty {
                Text("Platos").font(.title3.bold())
                ForEach(platos, id: \.1.id) { r, p in
                    Button { abrir(r) } label: {
                        HStack(spacing: 12) {
                            ProductoThumb(imagen: p.imagen, api: env.api, size: 64, esquina: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nombre).font(.headline)
                                Text(r.nombre).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(p.precio.value)).font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Componentes

/// Carrusel de la cabecera. Solo describe funciones reales de la app (no hay promociones ni descuentos).
struct CarruselPromos: View {
    let promos: [Banner]
    @State private var actual = 0
    private let reloj = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $actual) {
            ForEach(Array(promos.enumerated()), id: \.offset) { i, p in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.antetitulo).font(.subheadline.bold())
                        Text(p.titulo).font(.title.weight(.heavy)).lineLimit(3).minimumScaleFactor(0.8)
                        Text(p.detalle).font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let img = UIImage(named: p.foto) {
                        Image(uiImage: img).resizable().scaledToFit()
                            .frame(width: 150)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                    }
                }
                .padding(.bottom, 28)
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 210)
        .onReceive(reloj) { _ in guard !promos.isEmpty else { return }; withAnimation { actual = (actual + 1) % promos.count } }
    }
}

struct TarjetaAcceso: View {
    let titulo: String
    let foto: String
    var alto: CGFloat = 150
    var ancho: CGFloat? = nil
    var seleccionada = false
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 8) {
                if let img = UIImage(named: foto) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: .infinity)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 5)
                } else {
                    Image(systemName: "fork.knife").font(.largeTitle).frame(maxHeight: .infinity)
                }
                Text(titulo)
                    .font(ancho == nil ? .title3.bold() : .subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: ancho ?? .infinity)
            .frame(width: ancho, height: alto)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.accentColor, lineWidth: seleccionada ? 2.5 : 0))
        }
        .buttonStyle(.plain)
    }
}

struct TarjetaRestaurante: View {
    let restaurante: DemoRestaurante

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [restaurante.color.opacity(0.85), restaurante.color.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let img = UIImage(named: restaurante.portada) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .padding(.vertical, 12)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                }
            }
            .frame(height: 150)
            .overlay(alignment: .topLeading) {
                Label("Carta 3D", systemImage: "cube.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }

            HStack(spacing: 12) {
                LogoRestaurante(simbolo: restaurante.simbolo, color: restaurante.color, tam: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(restaurante.nombre).font(.headline)
                    Text("\(restaurante.rubro.titulo) · \(restaurante.lema)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let h = restaurante.carta.restaurante.configuracion?.horario {
                    Label(h, systemImage: "clock").font(.caption).foregroundStyle(.secondary).labelStyle(.titleOnly)
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(.separator).opacity(0.4)))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }
}
