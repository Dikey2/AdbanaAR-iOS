import SwiftUI

struct VoiceNoteView: View {
    /// (nombre de archivo, transcripción opcional)
    var onDone: (String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rec = VoiceNoteRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Graba hasta 30 s con indicaciones (alergias, punto de cocción…). Puedes convertirla a texto y revisarla antes de enviarla.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 160, height: 160)
                        .scaleEffect(1 + CGFloat(rec.nivel) * 0.5)
                        .animation(.easeOut(duration: 0.1), value: rec.nivel)
                    Button {
                        Task { rec.estado == .grabando ? rec.detener() : await rec.iniciar() }
                    } label: {
                        Image(systemName: rec.estado == .grabando ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 96))
                            .symbolEffect(.pulse, isActive: rec.estado == .grabando)
                    }
                    .accessibilityLabel(rec.estado == .grabando ? "Detener grabación" : "Grabar nota de voz")
                    .accessibilityIdentifier("grabarNota")
                }

                Text(String(format: "%.0f / %.0f s", rec.segundos, VoiceNoteRecorder.duracionMaxima))
                    .font(.caption.monospacedDigit())

                if rec.estado == .grabado || rec.estado == .reproduciendo || rec.estado == .transcribiendo {
                    HStack {
                        Button { rec.estado == .reproduciendo ? rec.detenerReproduccion() : rec.reproducir() } label: {
                            Label(rec.estado == .reproduciendo ? "Detener" : "Escuchar", systemImage: rec.estado == .reproduciendo ? "stop.fill" : "play.fill")
                        }
                        Button { Task { await rec.transcribir() } } label: {
                            Label("Convertir a texto", systemImage: "text.bubble")
                        }
                        .disabled(rec.estado == .transcribiendo)
                        Button(role: .destructive) { rec.descartar() } label: { Label("Borrar", systemImage: "trash") }
                    }
                    .buttonStyle(.bordered)
                }
                if rec.estado == .transcribiendo { ProgressView("Transcribiendo…") }
                if let t = rec.transcripcion {
                    GroupBox("Texto") { Text(t).frame(maxWidth: .infinity, alignment: .leading) }
                }
                if let e = rec.error { Text(e).font(.footnote).foregroundStyle(.red) }
                if rec.estado == .sinPermiso {
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Nota de voz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { rec.descartar(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usar") { onDone(rec.archivo, rec.transcripcion); dismiss() }
                        .disabled(rec.archivo == nil || rec.estado == .grabando)
                }
            }
        }
    }
}
