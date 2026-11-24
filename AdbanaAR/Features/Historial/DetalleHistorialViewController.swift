import AVFoundation
import SwiftUI
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
        let seguir = UIBarButtonItem(title: "Seguimiento", image: UIImage(systemName: "map"), primaryAction: UIAction { [weak self] _ in
            self?.abrirSeguimiento()
        })
        seguir.accessibilityIdentifier = "abrirSeguimiento"
        navigationItem.rightBarButtonItem = seguir
        pintar()
    }

    private func pintar() {
        guard let r = registro else { return }
        restauranteLabel.text = r.restauranteNombre
        pedidoLabel.text = "Pedido #\(r.pedidoId) · \(Modalidad(rawValue: r.tipo)?.titulo ?? r.tipo)"
        estadoLabel.text = "Estado: \(r.status.titulo(para: Modalidad(rawValue: r.tipo)))"
        totalLabel.text = "Total: S/ \(r.total) · Pagado: S/ \(r.pagado)"
        fechaLabel.text = "Creado \(r.creadoEn.formatted(date: .long, time: .shortened)) · actualizado \(r.actualizadoEn.formatted(date: .omitted, time: .shortened))"
        let tieneNota = r.notaVozArchivo.map { FileManager.default.fileExists(atPath: VoiceNoteRecorder.directorio.appendingPathComponent($0).path) } ?? false
        notaVozButton.isHidden = !tieneNota
        actualizarButton.isEnabled = !r.status.isFinal
        actualizarButton.accessibilityHint = "Consulta el estado actual en el restaurante"
    }

    /// Seguimiento visual (SwiftUI) del mismo pedido: línea de tiempo según delivery, recojo o mesa.
    private func abrirSeguimiento() {
        guard let r = registro else { return }
        let env = AppEnvironment.shared
        let vista = TrackingView(slug: r.slug, pedidoId: r.pedidoId, estadoInicial: r.estado, totalInicial: r.total,
                                 tipo: r.tipo, restauranteNombre: r.restauranteNombre)
            .environment(env)
            .environment(env.cart)
            .tint(Color.accentColor)
        navigationController?.pushViewController(UIHostingController(rootView: vista), animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let r = registro, let nuevo = AppEnvironment.shared.historial.registro(slug: r.slug, pedidoId: r.pedidoId) {
            registro = nuevo
            pintar()
        }
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
