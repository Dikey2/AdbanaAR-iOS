import SwiftUI

/// Puerta del modo administrador: crea el PIN la primera vez y luego lo pide.
/// El PIN se guarda como hash SHA-256 en el llavero del iPhone.
struct AdminAccesoView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pin = ""
    @State private var confirmacion = ""
    @State private var error: String?
    @State private var intentosFallidos = 0
    @State private var bloqueadoHasta: Date?

    var body: some View {
        Group {
            if env.adminActivo {
                AdminPanelView()
            } else {
                acceso
            }
        }
    }

    private var creando: Bool { !env.tienePINAdmin }

    private var acceso: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                    Text(creando ? "Crea el PIN de administrador" : "Modo administrador").font(.title2.bold())
                    Text(creando ? "Con este PIN se gestionan restaurantes, platos, precios, AR, banners y pedidos desde este iPhone."
                                 : "Ingresa tu PIN para administrar la aplicación.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                SecureField(creando ? "Nuevo PIN (4 a 8 dígitos)" : "PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .accessibilityIdentifier("pinAdmin")
                if creando {
                    SecureField("Repite el PIN", text: $confirmacion)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("pinAdminConfirmar")
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Button(creando ? "Crear PIN y entrar" : "Entrar") { entrar() }
                    .frame(maxWidth: .infinity)
                    .disabled(pin.isEmpty || (creando && confirmacion.isEmpty))
                    .accessibilityIdentifier("entrarAdmin")
            }
        }
        .navigationTitle("Administrador")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func entrar() {
        if let hasta = bloqueadoHasta, hasta > .now {
            error = "Demasiados intentos. Espera \(Int(hasta.timeIntervalSinceNow.rounded(.up))) s."
            return
        }
        if creando {
            guard AppEnvironment.pinValido(pin) else { error = "El PIN debe tener de 4 a 8 dígitos."; return }
            guard pin == confirmacion else { error = "Los PIN no coinciden."; return }
            guard env.crearPINAdmin(pin) else { error = "No se pudo guardar el PIN en el llavero."; return }
        } else if !env.verificarPINAdmin(pin) {
            intentosFallidos += 1
            pin = ""
            if intentosFallidos >= 5 {
                bloqueadoHasta = .now.addingTimeInterval(30)
                intentosFallidos = 0
                error = "PIN incorrecto. Acceso bloqueado 30 s."
            } else {
                error = "PIN incorrecto (\(intentosFallidos)/5)."
            }
            return
        }
        pin = ""; confirmacion = ""; error = nil
        withAnimation { env.adminActivo = true }
    }
}
