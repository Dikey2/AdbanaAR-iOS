import SwiftUI
import UIKit

/// Historial de pedidos del dispositivo (UIKit + Storyboard + CoreData).
/// Demuestra: UIViewController, IBOutlet, IBAction, UITableView y Segue ("mostrarDetalle").
final class HistorialViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var filtroControl: UISegmentedControl!
    @IBOutlet weak var emptyLabel: UILabel!
    @IBOutlet weak var refreshButton: UIBarButtonItem!

    private var registros: [HistorialRegistro] = []
    private var store: HistorialStore { AppEnvironment.shared.historial }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.accessibilityIdentifier = "historialTable"
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        tableView.refreshControl = rc
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        recargar()
    }

    func recargar() {
        registros = store.fetch(filtro: HistorialStore.Filtro(rawValue: filtroControl.selectedSegmentIndex) ?? .todos)
        emptyLabel.isHidden = !registros.isEmpty
        tableView.reloadData()
    }

    @IBAction func filtroCambiado(_ sender: UISegmentedControl) {
        UIView.transition(with: tableView, duration: 0.25, options: .transitionCrossDissolve) { self.recargar() }
    }

    /// Consulta en el backend el estado de los pedidos activos (con su token de seguimiento).
    @IBAction func refrescar(_ sender: UIBarButtonItem) {
        Task { await actualizarActivos() }
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        Task {
            await actualizarActivos()
            sender.endRefreshing()
        }
    }

    private func actualizarActivos() async {
        refreshButton.isEnabled = false
        defer { refreshButton.isEnabled = true }
        let activos = store.fetch(filtro: .activos)
        var fallos = 0
        for r in activos {
            do { _ = try await AppEnvironment.shared.refreshStatus(slug: r.slug, pedidoId: r.pedidoId) }
            catch { fallos += 1 }
        }
        recargar()
        if fallos > 0 {
            let alert = UIAlertController(title: "Actualización parcial",
                                          message: "\(fallos) pedido(s) no se pudieron consultar (sin conexión o seguimiento expirado).",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { registros.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistorialCell", for: indexPath)
        let r = registros[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = "#\(r.pedidoId) · \(r.restauranteNombre)"
        content.secondaryText = "\(r.status.titulo) · S/ \(r.total) · \(r.creadoEn.formatted(date: .abbreviated, time: .shortened))"
        content.image = UIImage(systemName: r.status.icono)
        content.imageProperties.tintColor = r.status == .cancelado ? .systemRed : .tintColor
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "historial-\(r.pedidoId)"
        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let r = registros[indexPath.row]
        store.delete(slug: r.slug, pedidoId: r.pedidoId)
        AppEnvironment.shared.keychain.delete(account: KeychainStore.account(slug: r.slug, pedidoId: r.pedidoId))
        registros.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        emptyLabel.isHidden = !registros.isEmpty
    }

    // MARK: Segue

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "mostrarDetalle",
              let destino = segue.destination as? DetalleHistorialViewController,
              let cell = sender as? UITableViewCell,
              let indexPath = tableView.indexPath(for: cell) else { return }
        destino.registro = registros[indexPath.row]
    }
}

/// Inserta el Storyboard UIKit dentro de la navegación SwiftUI (pestaña "Pedidos").
struct HistorialContainerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIStoryboard(name: "Historial", bundle: .main).instantiateInitialViewController() ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
