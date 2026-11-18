import SwiftUI

@MainActor
@Observable
final class TrackingViewModel {
    let slug: String
    let pedidoId: Int
    private(set) var estado: OrderStatus
    private(set) var total: String
    private(set) var pagado = "0.00"
    private(set) var error: String?
    private(set) var actualizando = false
    private(set) var ultimaConsulta: Date?
    private let env: AppEnvironment

    /// 15 s respeta el límite del backend (12 consultas/min por token).
    static let intervalo: Duration = .seconds(15)

    init(env: AppEnvironment, slug: String, pedidoId: Int, estadoInicial: String, total: String) {
        self.env = env
        self.slug = slug
        self.pedidoId = pedidoId
        self.estado = OrderStatus(raw: estadoInicial)
        self.total = total
    }

    func actualizar() async {
        actualizando = true
        defer { actualizando = false }
        do {
            let s = try await env.refreshStatus(slug: slug, pedidoId: pedidoId)
            withAnimation(.spring) { estado = OrderStatus(raw: s.estado) }
            total = s.total.description
            pagado = s.pagado.description
            error = nil
            ultimaConsulta = .now
        } catch let e as APIError {
            if case .notFound = e {
                error = "El seguimiento expiró (48 h) o no pertenece a este dispositivo."
            } else {
                error = e.userMessage
            }
        } catch {}
    }

    func sondear() async {
        while !Task.isCancelled && !estado.isFinal {
            await actualizar()
            if case .some = error, error?.contains("expiró") == true { return }
            try? await Task.sleep(for: Self.intervalo)
        }
    }
}

struct TrackingView: View {
    let slug: String
    let pedidoId: Int
    var inicial: PedidoCreadoResponse?
    var estadoInicial: String = "pendiente"
    var totalInicial: String = "0.00"

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
                                       total: inicial?.total.description ?? totalInicial)
            }
            await vm?.sondear()
        }
    }

    @ViewBuilder
    private func contenido(_ vm: TrackingViewModel) -> some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: vm.estado.icono)
                        .font(.system(size: 56))
                        .foregroundStyle(vm.estado == .cancelado ? Color.red : Color.accentColor)
                        .symbolEffect(.bounce, value: vm.estado)
                        .contentTransition(.symbolEffect(.replace))
                    Text("Pedido #\(pedidoId)").font(.title2.bold()).accessibilityIdentifier("pedidoNumero")
                    Text(vm.estado.titulo).font(.headline)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            if vm.estado != .cancelado {
                Section("Progreso") {
                    ForEach(OrderStatus.flujo, id: \.self) { s in
                        HStack {
                            Image(systemName: s.paso <= vm.estado.paso ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(s.paso <= vm.estado.paso ? Color.accentColor : .secondary)
                            Text(s.titulo)
                            Spacer()
                        }
                        .animation(.easeInOut, value: vm.estado)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if let inicial {
                Section("Detalle confirmado por el restaurante") {
                    ForEach(Array(inicial.items.enumerated()), id: \.offset) { _, i in
                        HStack { Text("\(i.cantidad) × \(i.producto)"); Spacer(); Text(Money.format(i.subtotal.value)) }
                    }
                }
            }

            Section {
                LabeledContent("Total", value: Money.format(Decimal(string: vm.total) ?? 0))
                LabeledContent("Pagado", value: Money.format(Decimal(string: vm.pagado) ?? 0))
                if let t = vm.ultimaConsulta {
                    LabeledContent("Última consulta", value: t.formatted(date: .omitted, time: .standard))
                }
                if let e = vm.error { Text(e).foregroundStyle(.orange).font(.footnote) }
                Button {
                    Task { await vm.actualizar() }
                } label: {
                    if vm.actualizando { ProgressView() } else { Label("Actualizar ahora", systemImage: "arrow.clockwise") }
                }
            } footer: {
                Text("El estado se consulta con un token privado de este pedido, guardado en el llavero del iPhone. Se actualiza cada 15 s.")
            }
        }
        .navigationTitle("Seguimiento")
    }
}
