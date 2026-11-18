import AVFoundation
import UIKit

/// Detalle de un pedido del historial (destino del Segue "mostrarDetalle").
final class DetalleHistorialViewController: UIViewController {
    @IBOutlet weak var restauranteLabel: UILabel!
    @IBOutlet weak var pedidoLabel: UILabel!
    @IBOutlet weak var estadoLabel: UILabel!
    @IBOutlet weak var totalLabel: UILabel!
    @IBOutlet weak var fechaLabel: UILabel!
    @IBOutlet weak var actualizarButton: UIButton!
    @IBOutlet weak var notaVozButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var mensajeLabel: UILabel!

    var registro: HistorialRegistro?
    private var player: AVAudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        pintar()
    }

    private func pintar() {
        guard let r = registro else { return }
        restauranteLabel.text = r.restauranteNombre
        pedidoLabel.text = "Pedido #\(r.pedidoId) · \(Modalidad(rawValue: r.tipo)?.titulo ?? r.tipo)"
        estadoLabel.text = "Estado: \(r.status.titulo)"
        totalLabel.text = "Total: S/ \(r.total) · Pagado: S/ \(r.pagado)"
        fechaLabel.text = "Creado \(r.creadoEn.formatted(date: .long, time: .shortened)) · actualizado \(r.actualizadoEn.formatted(date: .omitted, time: .shortened))"
        let tieneNota = r.notaVozArchivo.map { FileManager.default.fileExists(atPath: VoiceNoteRecorder.directorio.appendingPathComponent($0).path) } ?? false
        notaVozButton.isHidden = !tieneNota
        actualizarButton.isEnabled = !r.status.isFinal
        actualizarButton.accessibilityHint = "Consulta el estado actual en el restaurante"
    }

    @IBAction func actualizarEstado(_ sender: UIButton) {
        guard let r = registro else { return }
        activityIndicator.startAnimating()
        sender.isEnabled = false
        mensajeLabel.text = ""
        Task {
            defer {
                activityIndicator.stopAnimating()
                sender.isEnabled = !(registro?.status.isFinal ?? true)
            }
            do {
                _ = try await AppEnvironment.shared.refreshStatus(slug: r.slug, pedidoId: r.pedidoId)
                registro = AppEnvironment.shared.historial.registro(slug: r.slug, pedidoId: r.pedidoId)
                UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) { self.pintar() }
            } catch let e as APIError {
                mensajeLabel.text = e.statusCode == 404 ? "El seguimiento expiró (48 h)." : e.userMessage
            } catch {
                mensajeLabel.text = "No se pudo actualizar."
            }
        }
    }

    @IBAction func reproducirNota(_ sender: UIButton) {
        guard let archivo = registro?.notaVozArchivo else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player = try AVAudioPlayer(contentsOf: VoiceNoteRecorder.directorio.appendingPathComponent(archivo))
            player?.play()
        } catch {
            mensajeLabel.text = "No se pudo reproducir la nota."
        }
    }
}
