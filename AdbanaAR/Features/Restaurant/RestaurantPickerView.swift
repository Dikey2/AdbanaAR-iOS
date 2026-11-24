import SwiftUI
import VisionKit

struct RestaurantPickerView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: RestaurantPickerViewModel?
    @State private var mostrarQR = false

    var body: some View {
        Group {
            if let vm { content(vm) } else { ProgressView() }
        }
        .navigationTitle("Conectar restaurante")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm == nil { vm = RestaurantPickerViewModel(env: env) } }
    }

    @ViewBuilder
    private func content(_ vm: RestaurantPickerViewModel) -> some View {
        @Bindable var vm = vm
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Carta en realidad aumentada")
                        .font(.title2.bold())
                    Text("Escanea el QR de tu mesa o escribe el código del restaurante para ver sus platos en 3D sobre tu mesa.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Código del restaurante") {
                TextField("ej. mi-restaurante", text: $vm.slugInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.go)
                    .onSubmit { Task { await vm.abrir(slug: vm.slugInput) } }
                    .accessibilityIdentifier("slugField")
                Button {
                    Task { await vm.abrir(slug: vm.slugInput) }
                } label: {
                    Label("Abrir carta", systemImage: "arrow.right.circle.fill")
                }
                .disabled(vm.slugInput.isEmpty || vm.state == .loading)
                .accessibilityIdentifier("abrirCarta")

                Button { mostrarQR = true } label: {
                    Label("Escanear QR de la mesa", systemImage: "qrcode.viewfinder")
                }
                .disabled(!QRScannerView.isAvailable)
                if !QRScannerView.isAvailable {
                    Text("El escáner QR requiere un iPhone con cámara (no disponible en el simulador).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if vm.state == .loading {
                Section { HStack { ProgressView(); Text("Validando restaurante…") } }
            }
            if case .failed(let msg) = vm.state {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("errorRestaurante")
                }
            }

            Section("Buscar restaurantes publicados") {
                HStack {
                    TextField("Nombre", text: $vm.busqueda)
                        .onSubmit { Task { await vm.buscar() } }
                    if vm.buscando { ProgressView() } else {
                        Button("Buscar") { Task { await vm.buscar() } }
                    }
                }
                ForEach(vm.resultados) { r in
                    Button {
                        vm.slugInput = r.slug
                        Task { await vm.abrir(slug: r.slug) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(r.nombre).foregroundStyle(.primary)
                            Text(r.slug).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {} footer: {
                Text("Servidor: \(env.api.baseURL.absoluteString) · entorno \(AppConfig.environmentName)")
            }
        }
        .navigationDestination(isPresented: $vm.abrirCarta) {
            CartaView()
        }
        .sheet(isPresented: $mostrarQR) {
            QRScannerView { codigo in
                mostrarQR = false
                Task { await vm.abrirQR(codigo) }
            }
            .ignoresSafeArea()
        }
    }
}

/// Escáner QR con VisionKit (DataScannerViewController).
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    done = true
                    onCode(value)
                    return
                }
            }
        }
    }
}
