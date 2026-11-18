import SwiftUI

struct AccountView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(FirebaseService.self) private var firebase
    @State private var email = ""
    @State private var password = ""
    @State private var urlServidor = ""
    @State private var mensajeURL: String?
    @State private var trabajando = false

    var body: some View {
        NavigationStack {
            Form {
                firebaseSection
                if firebase.estado == .conectado {
                    Section {
                        if firebase.pedidos.isEmpty {
                            Text("Aún no hay pedidos sincronizados.").foregroundStyle(.secondary)
                        }
                        ForEach(firebase.pedidos) { p in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("#\(p.pedidoId) · \(p.restaurante)").font(.subheadline)
                                    Text(OrderStatus(raw: p.estado).titulo).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(Decimal(string: p.total) ?? 0)).font(.caption)
                            }
                            .transition(.slide)
                        }
                    } header: { Text("Mis pedidos en tiempo real (Realtime Database)") } footer: {
                        Text("Copia personal para tus dispositivos. El estado oficial siempre proviene del restaurante.")
                    }
                }
                Section {
                    TextField("URL del servidor", text: $urlServidor)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button("Guardar servidor") {
                        mensajeURL = env.updateBaseURL(urlServidor) ?? "Servidor actualizado: \(env.api.baseURL.absoluteString)"
                    }
                    if let mensajeURL { Text(mensajeURL).font(.footnote) }
                } header: { Text("Servidor Adbana") } footer: {
                    Text("Vacío = valor de configuración (\(AppConfig.bundleBaseURL().absoluteString)). Los servidores remotos requieren HTTPS.")
                }
                Section("Acerca de") {
                    LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    LabeledContent("Entorno", value: AppConfig.environmentName)
                }
            }
            .navigationTitle("Cuenta")
            .onAppear { urlServidor = env.preferences.apiBaseURL ?? "" }
        }
    }

    @ViewBuilder
    private var firebaseSection: some View {
        Section {
            switch firebase.estado {
            case .noConfigurado:
                Label("Firebase no configurado: agrega GoogleService-Info.plist (ver README).", systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            case .sinSesion:
                Button {
                    Task { trabajando = true; await firebase.entrarAnonimo(); trabajando = false }
                } label: { Label("Continuar como invitado", systemImage: "person.fill.questionmark") }
                credenciales
                HStack {
                    Button("Ingresar") { Task { trabajando = true; await firebase.entrar(email: email, password: password); trabajando = false } }
                    Spacer()
                    Button("Crear cuenta") { Task { trabajando = true; await firebase.crearCuenta(email: email, password: password); trabajando = false } }
                }
                .disabled(email.isEmpty || password.count < 6)
            case .conectado:
                LabeledContent("Usuario", value: firebase.esAnonimo ? "Invitado" : (firebase.email ?? "-"))
                if firebase.esAnonimo {
                    credenciales
                    Button("Convertir en cuenta con correo") {
                        Task { trabajando = true; await firebase.crearCuenta(email: email, password: password); trabajando = false }
                    }
                    .disabled(email.isEmpty || password.count < 6)
                }
                Button("Cerrar sesión", role: .destructive) { firebase.salir() }
            }
            if trabajando { ProgressView() }
            if let e = firebase.ultimoError { Text(e).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Cuenta de cliente (Firebase Authentication)") } footer: {
            Text("Independiente de las cuentas del personal del restaurante (Laravel). Solo guarda tus datos personales en la app.")
        }
    }

    @ViewBuilder
    private var credenciales: some View {
        TextField("Correo", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        SecureField("Contraseña (mín. 6)", text: $password).textContentType(.password)
    }
}
