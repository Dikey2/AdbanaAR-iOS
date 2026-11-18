import SwiftUI

struct CheckoutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart
    @State private var vm: CheckoutViewModel?
    @State private var mostrarNotaVoz = false

    var body: some View {
        Group {
            if let vm { form(vm) } else { ProgressView() }
        }
        .navigationTitle("Confirmar pedido")
        .task { if vm == nil { vm = CheckoutViewModel(env: env) } }
    }

    @ViewBuilder
    private func form(_ vm: CheckoutViewModel) -> some View {
        @Bindable var vm = vm
        if case .creado(let r) = vm.fase, let slug = env.carta?.restaurante.slug {
            TrackingView(slug: slug, pedidoId: r.pedidoId, inicial: r)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        } else {
            Form {
                if vm.isDemo {
                    Section { Label("Modo demostración: el envío está deshabilitado.", systemImage: "info.circle").foregroundStyle(.orange) }
                }
                Section("Tus datos") {
                    TextField("Nombre", text: $vm.form.clienteNombre)
                        .textContentType(.name)
                        .accessibilityIdentifier("nombreCliente")
                    error(vm, .clienteNombre)
                }
                Section("Modalidad") {
                    Picker("Modalidad", selection: $vm.form.tipo) {
                        ForEach(vm.modalidades) { m in Label(m.titulo, systemImage: m.icono).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(vm.mesaFijadaPorQR)
                    error(vm, .tipo)
                    switch vm.form.tipo {
                    case .mesa:
                        if vm.mesaFijadaPorQR {
                            Label("Mesa del QR: \(vm.form.mesa)", systemImage: "qrcode")
                        } else if !vm.mesas.isEmpty {
                            Picker("Mesa", selection: $vm.form.mesa) {
                                Text("Elige tu mesa").tag("")
                                ForEach(vm.mesas) { m in
                                    Text(m.ocupada ? "\(m.nombre) (con cuenta abierta)" : m.nombre).tag(m.nombre)
                                }
                            }
                        } else {
                            TextField("Mesa", text: $vm.form.mesa)
                        }
                        error(vm, .mesa)
                    case .delivery:
                        TextField("Dirección", text: $vm.form.direccion).textContentType(.fullStreetAddress)
                        error(vm, .direccion)
                        TextField("Teléfono", text: $vm.form.telefono).keyboardType(.phonePad).textContentType(.telephoneNumber)
                        error(vm, .telefono)
                    case .recojo:
                        Text("Recoge tu pedido en el mostrador.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Notas para cocina (opcional)", text: $vm.form.notas, axis: .vertical)
                        .lineLimit(2...5)
                    Button { mostrarNotaVoz = true } label: {
                        Label(vm.notaVozArchivo == nil ? "Dictar nota de voz" : "Nota de voz grabada", systemImage: "mic.fill")
                    }
                    error(vm, .notas)
                } header: { Text("Notas") } footer: {
                    Text("\(vm.form.notas.count)/500 · El restaurante recibe solo el texto de la nota.")
                }
                Section {
                    ForEach(cart.lines) { l in
                        HStack { Text("\(l.cantidad) × \(l.producto.nombre)"); Spacer(); Text(Money.format(l.subtotalEstimado)) }
                            .font(.subheadline)
                    }
                    HStack { Text("Total estimado").bold(); Spacer(); Text(Money.format(cart.estimatedTotal)).bold() }
                    error(vm, .items)
                } header: { Text("Resumen") } footer: {
                    Text("El total final lo calcula el servidor del restaurante.")
                }

                estado(vm)
            }
            .safeAreaInset(edge: .bottom) { boton(vm) }
            .sheet(isPresented: $mostrarNotaVoz) {
                VoiceNoteView { archivo, texto in
                    vm.notaVozArchivo = archivo
                    if let texto, !texto.isEmpty {
                        let combinado = vm.form.notas.isEmpty ? texto : vm.form.notas + " " + texto
                        vm.form.notas = String(combinado.prefix(500))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func error(_ vm: CheckoutViewModel, _ f: OrderForm.Field) -> some View {
        if let m = vm.errores[f] {
            Text(m).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func estado(_ vm: CheckoutViewModel) -> some View {
        switch vm.fase {
        case .reintentable(let m):
            Section {
                Label(m, systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                if let i = vm.intent {
                    Text("Clave de operación: \(i.clave.prefix(8))… (se reutiliza en cada reintento)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Button("Descartar y editar", role: .destructive) { vm.descartarPendiente() }
            }
        case .rechazado(let m):
            Section { Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityIdentifier("errorPedido") }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func boton(_ vm: CheckoutViewModel) -> some View {
        Group {
            switch vm.fase {
            case .enviando:
                ProgressView("Enviando pedido…").frame(maxWidth: .infinity)
            case .reintentable:
                Button { Task { await vm.reintentar() } } label: {
                    Label("Reintentar el mismo pedido", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            default:
                Button { Task { await vm.enviar() } } label: {
                    Label("Enviar pedido", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(cart.isEmpty || vm.isDemo)
                .accessibilityIdentifier("enviarPedido")
            }
        }
        .padding()
        .background(.bar)
    }
}
