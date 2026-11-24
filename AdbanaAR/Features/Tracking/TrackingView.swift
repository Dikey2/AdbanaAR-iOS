import MapKit
import SwiftUI

@MainActor
@Observable
final class TrackingViewModel {
    let slug: String
    let pedidoId: Int
    private(set) var estado: OrderStatus
    private(set) var tipo: Modalidad?
    private(set) var total: String
    private(set) var pagado = "0.00"
    private(set) var error: String?
    private(set) var actualizando = false
    private(set) var ultimaConsulta: Date?
    private let env: AppEnvironment

    /// Pedido de un restaurante de demostración: se simula en el dispositivo.
    var simulado: Bool { DemoCatalog.esDemo(slug) }

    /// 15 s respeta el límite del backend (12 consultas/min por token). El simulado no consulta la red.
    var intervalo: Duration { simulado ? .seconds(2) : .seconds(15) }

    init(env: AppEnvironment, slug: String, pedidoId: Int, estadoInicial: String, total: String, tipo: String?) {
        self.env = env
        self.slug = slug
        self.pedidoId = pedidoId
        self.estado = OrderStatus(raw: estadoInicial)
        self.total = total
        self.tipo = tipo.flatMap(Modalidad.init(rawValue:))
    }

    func actualizar() async {
        actualizando = true
        defer { actualizando = false }
        do {
            let s = try await env.refreshStatus(slug: slug, pedidoId: pedidoId)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                estado = OrderStatus(raw: s.estado)
                tipo = Modalidad(rawValue: s.tipo) ?? tipo
            }
            total = s.total.description
            pagado = s.pagado.description
            error = nil
            ultimaConsulta = .now
        } catch let e as APIError {
            if case .notFound = e {
                error = simulado ? "Este pedido ya no está disponible en el dispositivo."
                                 : "El seguimiento expiró (48 h) o no pertenece a este dispositivo."
            } else {
                error = e.userMessage
            }
        } catch {}
    }

    func sondear() async {
        while !Task.isCancelled && !estado.isFinal {
            await actualizar()
            if error != nil, error?.contains("expiró") == true || error?.contains("ya no está disponible") == true { return }
            try? await Task.sleep(for: intervalo)
        }
    }

    /// Solo demostración: pasa al siguiente estado sin esperar.
    func avanzar() async {
        env.simulador.avanzar(pedidoId: pedidoId)
        await actualizar()
    }
}

struct TrackingView: View {
    let slug: String
    let pedidoId: Int
    var inicial: PedidoCreadoResponse?
    var estadoInicial: String = "pendiente"
    var totalInicial: String = "0.00"
    var tipo: String? = nil
    var restauranteNombre: String? = nil

    @Environment(AppEnvironment.self) private var env
    @State private var vm: TrackingViewModel?

    var body: some View {
        Group {
            if let vm { contenido(vm) } else { ProgressView() }
        }
        .task {
            if vm == nil {
                vm = TrackingViewModel(env: env, slug: slug, pedidoId: pedidoId,
                                       estadoInicial: inicial?.estado ?? estadoInicial,
                                       total: inicial?.total.description ?? totalInicial,
                                       tipo: tipo ?? env.historial.registro(slug: slug, pedidoId: pedidoId)?.tipo)
            }
            await vm?.sondear()
        }
    }

    private var nombre: String {
        restauranteNombre ?? env.historial.registro(slug: slug, pedidoId: pedidoId)?.restauranteNombre ?? "el restaurante"
    }

    @ViewBuilder
    private func contenido(_ vm: TrackingViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                cabecera(vm)
                if vm.estado != .cancelado {
                    switch vm.tipo {
                    case .delivery?: RecorridoDelivery(estado: vm.estado)
                    case .recojo?: TarjetaRecojo(pedidoId: pedidoId, restaurante: nombre, estado: vm.estado,
                                                 zona: env.geocerca(slug: slug, configuracion: env.carta?.restaurante.slug == slug ? env.carta?.restaurante.configuracion : nil))
                    default: EmptyView()
                    }
                    lineaDeTiempo(vm)
                }
                detalle(vm)
                if vm.simulado { demo(vm) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Seguimiento")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cabecera(_ vm: TrackingViewModel) -> some View {
        VStack(spacing: 8) {
            Image(systemName: vm.estado.icono(para: vm.tipo))
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(vm.estado == .cancelado ? Color.red.gradient : Color.accentColor.gradient, in: Circle())
                .symbolEffect(.bounce, value: vm.estado)
                .contentTransition(.symbolEffect(.replace))
            Text(vm.estado.titulo(para: vm.tipo))
                .font(.title.bold())
                .contentTransition(.opacity)
                .accessibilityIdentifier("estadoPedido")
            Text(vm.estado.detalle(para: vm.tipo))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Text(verbatim: "Pedido #\(pedidoId)").font(.footnote.bold()).accessibilityIdentifier("pedidoNumero")
                if let t = vm.tipo {
                    Label(t.titulo, systemImage: t.icono).font(.footnote.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            Text(nombre).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func lineaDeTiempo(_ vm: TrackingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(OrderStatus.flujo.enumerated()), id: \.element) { i, s in
                let hecho = s.paso <= vm.estado.paso
                let actual = s == vm.estado
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Image(systemName: hecho ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(hecho ? Color.accentColor : Color.secondary.opacity(0.5))
                            .scaleEffect(actual ? 1.15 : 1)
                        if i < OrderStatus.flujo.count - 1 {
                            Rectangle()
                                .fill(s.paso < vm.estado.paso ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 3, height: 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.titulo(para: vm.tipo))
                            .font(actual ? .headline : .subheadline)
                            .foregroundStyle(hecho ? .primary : .secondary)
                        if actual {
                            Text(s.detalle(para: vm.tipo)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("paso-\(s.rawValue)")
            }
        }
        .animation(.easeInOut, value: vm.estado)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func detalle(_ vm: TrackingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inicial {
                Text(vm.simulado ? "Tu pedido" : "Detalle confirmado por el restaurante").font(.headline)
                ForEach(Array(inicial.items.enumerated()), id: \.offset) { _, i in
                    HStack { Text("\(i.cantidad) × \(i.producto)"); Spacer(); Text(Money.format(i.subtotal.value)) }
                        .font(.subheadline)
                }
                Divider()
            }
            LabeledContent("Total", value: Money.format(Decimal(string: vm.total) ?? 0)).font(.subheadline.bold())
            LabeledContent("Pagado", value: Money.format(Decimal(string: vm.pagado) ?? 0)).font(.subheadline)
            if let e = vm.error { Text(e).foregroundStyle(.orange).font(.footnote) }
            if !vm.simulado {
                if let t = vm.ultimaConsulta {
                    LabeledContent("Última consulta", value: t.formatted(date: .omitted, time: .standard)).font(.caption)
                }
                Button {
                    Task { await vm.actualizar() }
                } label: {
                    if vm.actualizando { ProgressView() } else { Label("Actualizar ahora", systemImage: "arrow.clockwise") }
                }
                Text("El estado se consulta con un token privado de este pedido, guardado en el llavero del iPhone, cada 15 s.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private func demo(_ vm: TrackingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vm.estado.isFinal {
                Button { Task { await vm.avanzar() } } label: {
                    Label("Avanzar al siguiente estado", systemImage: "forward.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("avanzarEstado")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

/// Recorrido ilustrativo del delivery: local → repartidor → tu casa.
/// No es la posición GPS del repartidor (el backend no la expone).
struct RecorridoDelivery: View {
    let estado: OrderStatus

    private var avance: CGFloat {
        switch estado {
        case .pendiente, .confirmado: return 0
        case .preparando: return 0.08
        case .listo: return 0.55
        case .entregado: return 1
        case .cancelado: return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let ancho = geo.size.width - 56
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 6).padding(.horizontal, 28)
                    Capsule().fill(Color.accentColor).frame(width: max(0, ancho * avance), height: 6).padding(.leading, 28)
                    Image(systemName: "storefront.fill").font(.title2).foregroundStyle(Color.accentColor)
                    Image(systemName: "house.fill").font(.title2)
                        .foregroundStyle(estado == .entregado ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "bicycle")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
                        .shadow(radius: 3, y: 2)
                        .offset(x: 8 + ancho * avance)
                        .opacity(estado == .listo ? 1 : 0.0)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 48)
            .animation(.easeInOut(duration: 1.2), value: estado)
            Text(estado == .listo ? "Tu repartidor va en camino." :
                 estado == .entregado ? "Pedido entregado en tu dirección." : "El repartidor saldrá cuando tu pedido esté listo.")
                .font(.subheadline.bold())
            Text("Recorrido ilustrativo: no muestra la ubicación GPS del repartidor.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

/// Recojo en el local: número para el mostrador y, si el restaurante fijó su ubicación, el mapa.
struct TarjetaRecojo: View {
    let pedidoId: Int
    let restaurante: String
    let estado: OrderStatus
    let zona: GeocercaAR?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recoge en").font(.caption).foregroundStyle(.secondary)
                    Text(restaurante).font(.headline)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Muestra este número").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "#\(pedidoId)").font(.title.bold().monospacedDigit()).foregroundStyle(Color.accentColor)
                }
            }
            if let zona {
                Map(initialPosition: .region(MKCoordinateRegion(center: zona.centro, latitudinalMeters: 600, longitudinalMeters: 600))) {
                    Marker(restaurante, systemImage: "fork.knife", coordinate: zona.centro).tint(Color.accentColor)
                    UserAnnotation()
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
            }
            Label(estado == .listo ? "¡Tu pedido te espera en el mostrador!" :
                  estado == .entregado ? "Pedido recogido." : "Te avisaremos aquí cuando esté listo para recoger.",
                  systemImage: estado == .listo ? "bell.badge.fill" : "clock")
                .font(.subheadline.bold())
                .foregroundStyle(estado == .listo ? Color.accentColor : .primary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
