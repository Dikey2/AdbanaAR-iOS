import SwiftUI

/// Edición de un restaurante incluido en la app y acceso a sus platos.
struct AdminRestauranteView: View {
    let slug: String
    @Environment(AppEnvironment.self) private var env

    @State private var nombre = ""
    @State private var lema = ""
    @State private var descripcion = ""
    @State private var horario = ""
    @State private var modalidades: Set<Modalidad> = []
    @State private var visible = true
    @State private var guardado = false
    @State private var cargado = false

    var body: some View {
        let r = env.restaurante(slug: slug, incluirOcultos: true)
        Form {
            if let r {
                Section {
                    HStack(spacing: 12) {
                        LogoRestaurante(simbolo: r.simbolo, color: r.color, tam: 56)
                        if let img = UIImage(named: r.portada) {
                            Image(uiImage: img).resizable().scaledToFit().frame(height: 70)
                        }
                    }
                    Toggle("Visible para los clientes", isOn: $visible).accessibilityIdentifier("adminVisible")
                }
                Section("Datos del restaurante") {
                    TextField("Nombre", text: $nombre).accessibilityIdentifier("adminNombreRestaurante")
                    TextField("Lema", text: $lema)
                    TextField("Descripción", text: $descripcion, axis: .vertical).lineLimit(2...4)
                    TextField("Horario (ej. 9:00 – 21:00)", text: $horario)
                }
                Section("Modalidades de pedido") {
                    ForEach(Modalidad.allCases) { m in
                        Toggle(isOn: Binding(get: { modalidades.contains(m) },
                                             set: { activo in if activo { modalidades.insert(m) } else { modalidades.remove(m) } })) {
                            Label(m.titulo, systemImage: m.icono)
                        }
                    }
                }
                Section {
                    Button {
                        guardar()
                    } label: {
                        Label(guardado ? "Guardado" : "Guardar cambios", systemImage: guardado ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty || modalidades.isEmpty)
                    .accessibilityIdentifier("adminGuardarRestaurante")
                } footer: {
                    if modalidades.isEmpty { Text("Activa al menos una modalidad.").foregroundStyle(.red) }
                }
                Section("Platos") {
                    ForEach(r.carta.carta.flatMap(\.productos)) { p in
                        NavigationLink {
                            AdminProductoView(productoId: p.id, slug: slug)
                        } label: {
                            HStack(spacing: 12) {
                                ProductoThumb(imagen: p.imagen, api: env.api, size: 48, esquina: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.nombre).font(.subheadline.bold())
                                    Text(Money.format(p.precio.value)).font(.caption)
                                }
                                Spacer()
                                if env.ajusteProducto(p.id)?.oculto == true {
                                    Image(systemName: "eye.slash").foregroundStyle(.secondary)
                                }
                                if !p.disponible {
                                    Text("Agotado").font(.caption2.bold()).foregroundStyle(.red)
                                }
                            }
                        }
                        .accessibilityIdentifier("admin-producto-\(p.id)")
                    }
                }
            }
        }
        .navigationTitle(r?.nombre ?? "Restaurante")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !cargado, let r else { return }
            cargado = true
            nombre = r.nombre
            lema = r.lema
            descripcion = r.carta.restaurante.configuracion?.descripcion ?? ""
            horario = r.carta.restaurante.configuracion?.horario ?? ""
            modalidades = Set(r.carta.restaurante.modalidades)
            visible = env.restauranteVisible(slug)
        }
    }

    private func guardar() {
        env.editarRestaurante(slug) { a in
            a.nombre = nombre.trimmingCharacters(in: .whitespaces)
            a.lema = lema
            a.descripcion = descripcion
            a.horario = horario
            a.modalidades = Modalidad.allCases.filter { modalidades.contains($0) }.map(\.rawValue)
            a.visible = visible
        }
        withAnimation { guardado = true }
        Task { try? await Task.sleep(for: .seconds(1.5)); withAnimation { guardado = false } }
    }
}

/// Edición de un plato: nombre, descripción, precio, disponibilidad y visibilidad.
struct AdminProductoView: View {
    let productoId: Int
    let slug: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var descripcion = ""
    @State private var precio = ""
    @State private var disponible = true
    @State private var oculto = false
    @State private var error: String?
    @State private var cargado = false

    private var producto: ProductoDTO? {
        env.restaurante(slug: slug, incluirOcultos: true)?.carta.carta.flatMap(\.productos).first { $0.id == productoId }
    }

    var body: some View {
        Form {
            if let p = producto {
                Section {
                    FotoPlato(imagen: p.imagen, api: env.api)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .listRowInsets(EdgeInsets())
                }
                Section("Plato") {
                    TextField("Nombre", text: $nombre).accessibilityIdentifier("adminNombrePlato")
                    TextField("Descripción", text: $descripcion, axis: .vertical).lineLimit(2...5)
                    HStack {
                        Text("Precio S/")
                        TextField("0.00", text: $precio)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("adminPrecio")
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Toggle("Disponible (si no, aparece como agotado)", isOn: $disponible)
                        .accessibilityIdentifier("adminDisponible")
                    Toggle("Ocultar de la carta", isOn: $oculto)
                        .accessibilityIdentifier("adminOculto")
                }
                Section {
                    Button("Guardar plato") { guardar() }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("adminGuardarPlato")
                    Button("Restablecer este plato", role: .destructive) {
                        if let a = env.ajusteProducto(productoId) { env.contexto.delete(a); env.guardarCatalogo() }
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("El precio aplica a los nuevos pedidos. Los platos ya en el carrito conservan el precio con que se agregaron.")
                }
            }
        }
        .navigationTitle(producto?.nombre ?? "Plato")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !cargado, let p = producto else { return }
            cargado = true
            nombre = p.nombre
            descripcion = p.descripcion ?? ""
            precio = p.precio.description
            disponible = p.disponible
            oculto = env.ajusteProducto(productoId)?.oculto ?? false
        }
    }

    private func guardar() {
        let texto = precio.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let valor = Decimal(string: texto, locale: Locale(identifier: "en_US_POSIX")), valor > 0, valor < 100_000 else {
            error = "Ingresa un precio válido (ej. 24.50)."
            return
        }
        guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty else { error = "El nombre no puede quedar vacío."; return }
        env.editarProducto(productoId) { a in
            a.nombre = nombre.trimmingCharacters(in: .whitespaces)
            a.descripcion = descripcion
            a.precio = DecimalString(valor).description
            a.disponible = disponible
            a.oculto = oculto
        }
        dismiss()
    }
}

/// Banners del carrusel del inicio: textos, foto, visibilidad, alta y baja.
struct AdminBannersView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var lista: [Banner] = []
    @State private var guardado = false

    var body: some View {
        Form {
            ForEach(lista.indices, id: \.self) { i in
                Section("Banner \(i + 1)") {
                    Toggle("Visible", isOn: binding(i, \.visible))
                    TextField("Antetítulo", text: binding(i, \.antetitulo))
                    TextField("Título", text: binding(i, \.titulo)).accessibilityIdentifier("adminBannerTitulo-\(i)")
                    TextField("Detalle", text: binding(i, \.detalle))
                    Picker("Foto", selection: binding(i, \.foto)) {
                        ForEach(Banner.fotos, id: \.self) { f in
                            Text(f.replacingOccurrences(of: "foto-", with: "").replacingOccurrences(of: "_", with: " ")).tag(f)
                        }
                    }
                    if let img = UIImage(named: lista[i].foto) {
                        Image(uiImage: img).resizable().scaledToFit().frame(height: 80).frame(maxWidth: .infinity)
                    }
                    Button("Eliminar banner", role: .destructive) { lista.remove(at: i) }
                }
            }
            Section {
                Button { lista.append(Banner(id: lista.count, antetitulo: "Nuevo", titulo: "Título", detalle: "Detalle", foto: Banner.fotos[0], visible: true)) } label: {
                    Label("Agregar banner", systemImage: "plus")
                }
                Button {
                    env.guardarBanners(lista)
                    withAnimation { guardado = true }
                } label: {
                    Label(guardado ? "Guardado" : "Guardar banners", systemImage: guardado ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("adminGuardarBanners")
            }
        }
        .navigationTitle("Banners del inicio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if lista.isEmpty { lista = env.banners } }
        .onChange(of: lista) { _, _ in guardado = false }
    }

    private func binding<T>(_ i: Int, _ campo: KeyPath<Banner, T>) -> Binding<T> {
        Binding(get: { lista[i][keyPath: campo] }, set: { nuevo in
            var b = lista[i]
            switch campo {
            case \Banner.visible: b = Banner(id: b.id, antetitulo: b.antetitulo, titulo: b.titulo, detalle: b.detalle, foto: b.foto, visible: nuevo as! Bool)
            case \Banner.antetitulo: b = Banner(id: b.id, antetitulo: nuevo as! String, titulo: b.titulo, detalle: b.detalle, foto: b.foto, visible: b.visible)
            case \Banner.titulo: b = Banner(id: b.id, antetitulo: b.antetitulo, titulo: nuevo as! String, detalle: b.detalle, foto: b.foto, visible: b.visible)
            case \Banner.detalle: b = Banner(id: b.id, antetitulo: b.antetitulo, titulo: b.titulo, detalle: nuevo as! String, foto: b.foto, visible: b.visible)
            case \Banner.foto: b = Banner(id: b.id, antetitulo: b.antetitulo, titulo: b.titulo, detalle: b.detalle, foto: nuevo as! String, visible: b.visible)
            default: break
            }
            lista[i] = b
        })
    }
}

/// Pedidos del dispositivo. Los de los restaurantes de la app se pueden mover de estado o cancelar;
/// los de restaurantes reales se gestionan en el panel web de Adbana.
struct AdminPedidosView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let _ = env.versionCatalogo
        let pedidos = env.historial.fetch()
        List {
            if pedidos.isEmpty {
                ContentUnavailableView("Sin pedidos", systemImage: "tray", description: Text("Los pedidos hechos desde la app aparecerán aquí."))
            }
            ForEach(pedidos, id: \.self) { p in
                let tipo = Modalidad(rawValue: p.tipo)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verbatim: "#\(p.pedidoId)").font(.headline.monospacedDigit())
                        Text(p.restauranteNombre).font(.subheadline)
                        Spacer()
                        Text(Money.format(Decimal(string: p.total) ?? 0)).font(.subheadline.bold())
                    }
                    HStack {
                        Label(tipo?.titulo ?? p.tipo, systemImage: tipo?.icono ?? "bag").font(.caption)
                        Text(p.creadoEn.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if DemoCatalog.esDemo(p.slug) {
                            Menu {
                                ForEach(OrderStatus.flujo + [.cancelado], id: \.self) { s in
                                    Button(s.titulo(para: tipo)) { cambiar(p, a: s) }
                                }
                                Divider()
                                Button("Reanudar avance automático") { cambiar(p, a: nil) }
                            } label: {
                                Label(p.status.titulo(para: tipo), systemImage: p.status.icono(para: tipo))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(color(p.status).opacity(0.15), in: Capsule())
                                    .foregroundStyle(color(p.status))
                            }
                            .accessibilityIdentifier("admin-estado-\(p.pedidoId)")
                        } else {
                            Text(p.status.titulo(para: tipo)).font(.caption.bold()).foregroundStyle(color(p.status))
                        }
                    }
                    if !DemoCatalog.esDemo(p.slug) {
                        Text("Restaurante real: el estado lo cambia el restaurante en el panel de Adbana.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if DemoCatalog.esDemo(p.slug) {
                        Button("Eliminar", role: .destructive) {
                            env.simulador.eliminar(pedidoId: p.pedidoId)
                            env.historial.delete(slug: p.slug, pedidoId: p.pedidoId)
                            env.versionCatalogo += 1
                        }
                    }
                }
            }
        }
        .navigationTitle("Pedidos")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refrescar(pedidos) }
        .task { await refrescar(pedidos) }
    }

    private func color(_ s: OrderStatus) -> Color {
        switch s {
        case .cancelado: return .red
        case .entregado: return .green
        default: return .accentColor
        }
    }

    private func cambiar(_ p: HistorialRegistro, a estado: OrderStatus?) {
        env.simulador.fijar(pedidoId: p.pedidoId, estado: estado)
        if let s = env.simulador.seguimiento(pedidoId: p.pedidoId) {
            env.historial.updateEstado(slug: p.slug, pedidoId: p.pedidoId, estado: s.estado, pagado: s.pagado.description, total: s.total.description)
        }
        env.versionCatalogo += 1
    }

    /// Actualiza el estado de los pedidos de la app (avance automático) antes de listar.
    private func refrescar(_ pedidos: [HistorialRegistro]) async {
        for p in pedidos where DemoCatalog.esDemo(p.slug) && !p.status.isFinal {
            _ = try? await env.refreshStatus(slug: p.slug, pedidoId: p.pedidoId)
        }
        env.versionCatalogo += 1
    }
}
