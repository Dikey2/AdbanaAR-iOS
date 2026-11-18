import Foundation
import Observation
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseAuth
import FirebaseDatabase
import FirebaseStorage
#endif

/// Pedido sincronizado en Realtime Database bajo `usuarios/{uid}/pedidos`.
struct PedidoSincronizado: Identifiable, Equatable {
    let id: String
    let slug: String
    let pedidoId: Int
    let restaurante: String
    let estado: String
    let total: String
}

/// Integración Firebase del CLIENTE (comensal). No reemplaza ni toca la autenticación Laravel/Sanctum
/// del personal: Laravel sigue siendo la única autoridad sobre pedidos, precios y estados.
/// - Authentication: identidad del comensal (anónima o correo) para sus datos personales en la app.
/// - Realtime Database: copia personal de SUS pedidos para verlos en vivo en sus dispositivos.
/// - Storage: respaldo opcional de SUS notas de voz (≤1 MB, audio/mp4), solo él puede leerlas.
/// Reglas en Firebase/database.rules.json y Firebase/storage.rules.
@MainActor
@Observable
final class FirebaseService {
    enum Estado: Equatable { case noConfigurado, sinSesion, conectado }

    private(set) var estado: Estado = .noConfigurado
    private(set) var uid: String?
    private(set) var email: String?
    private(set) var esAnonimo = true
    private(set) var pedidos: [PedidoSincronizado] = []
    var ultimoError: String?

    static let maxNotaVozBytes = 1_048_576

    #if canImport(FirebaseCore)
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var pedidosHandle: DatabaseHandle?
    private var pedidosRef: DatabaseReference?
    #endif

    /// Configura Firebase solo si existe GoogleService-Info.plist (no se versiona en Git).
    static func configureIfPossible() -> Bool {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return true
        #else
        return false
        #endif
    }

    init(configured: Bool) {
        guard configured else { return }
        #if canImport(FirebaseCore)
        estado = .sinSesion
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user: user) }
        }
        #endif
    }

    #if canImport(FirebaseCore)
    private func apply(user: User?) {
        uid = user?.uid
        email = user?.email
        esAnonimo = user?.isAnonymous ?? true
        estado = user == nil ? .sinSesion : .conectado
        observarPedidos()
    }
    #endif

    func entrarAnonimo() async {
        #if canImport(FirebaseCore)
        guard estado != .noConfigurado else { return }
        do { _ = try await Auth.auth().signInAnonymously(); ultimoError = nil }
        catch { ultimoError = Self.mensaje(error) }
        #endif
    }

    func entrar(email: String, password: String) async {
        #if canImport(FirebaseCore)
        guard estado != .noConfigurado else { return }
        do { _ = try await Auth.auth().signIn(withEmail: email, password: password); ultimoError = nil }
        catch { ultimoError = Self.mensaje(error) }
        #endif
    }

    /// Crea cuenta con correo. Si la sesión actual es anónima, la vincula para conservar sus datos.
    func crearCuenta(email: String, password: String) async {
        #if canImport(FirebaseCore)
        guard estado != .noConfigurado else { return }
        do {
            if let user = Auth.auth().currentUser, user.isAnonymous {
                let cred = EmailAuthProvider.credential(withEmail: email, password: password)
                let result = try await user.link(with: cred)
                apply(user: result.user)
            } else {
                _ = try await Auth.auth().createUser(withEmail: email, password: password)
            }
            ultimoError = nil
        } catch { ultimoError = Self.mensaje(error) }
        #endif
    }

    func salir() {
        #if canImport(FirebaseCore)
        do { try Auth.auth().signOut() } catch { ultimoError = Self.mensaje(error) }
        #endif
    }

    /// Copia el estado devuelto por Laravel. Nunca es fuente de verdad para el restaurante.
    func reflejarPedido(slug: String, pedidoId: Int, restaurante: String, estado: String, total: String) async {
        #if canImport(FirebaseCore)
        guard let uid, self.estado == .conectado else { return }
        let ref = Database.database().reference().child("usuarios").child(uid).child("pedidos").child("\(slug)__\(pedidoId)")
        let valor: [String: Any] = [
            "slug": slug, "pedidoId": pedidoId, "restaurante": String(restaurante.prefix(120)),
            "estado": estado, "total": total, "actualizadoEn": ServerValue.timestamp(),
        ]
        do { try await ref.setValue(valor) } catch { ultimoError = Self.mensaje(error) }
        #endif
    }

    /// Sube una nota de voz del propio usuario. Devuelve la ruta en Storage.
    func subirNotaVoz(archivo: URL, clave: String) async throws -> String {
        #if canImport(FirebaseCore)
        guard let uid, estado == .conectado else { throw FirebaseFeatureError.sinSesion }
        let size = (try? FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int) ?? 0
        guard size > 0, size <= Self.maxNotaVozBytes else { throw FirebaseFeatureError.archivoInvalido }
        guard UUID(uuidString: clave) != nil else { throw FirebaseFeatureError.archivoInvalido }
        let path = "notas-voz/\(uid)/\(clave.lowercased()).m4a"
        let meta = StorageMetadata()
        meta.contentType = "audio/mp4"
        _ = try await Storage.storage().reference().child(path).putFileAsync(from: archivo, metadata: meta)
        return path
        #else
        throw FirebaseFeatureError.noConfigurado
        #endif
    }

    #if canImport(FirebaseCore)
    private func observarPedidos() {
        if let pedidosHandle, let pedidosRef { pedidosRef.removeObserver(withHandle: pedidosHandle) }
        pedidosHandle = nil
        pedidos = []
        guard let uid else { return }
        let ref = Database.database().reference().child("usuarios").child(uid).child("pedidos")
        pedidosRef = ref
        pedidosHandle = ref.queryLimited(toLast: 50).observe(.value) { [weak self] snapshot in
            var lista: [PedidoSincronizado] = []
            for case let child as DataSnapshot in snapshot.children {
                guard let v = child.value as? [String: Any] else { continue }
                lista.append(PedidoSincronizado(id: child.key, slug: v["slug"] as? String ?? "",
                                                pedidoId: v["pedidoId"] as? Int ?? 0,
                                                restaurante: v["restaurante"] as? String ?? "",
                                                estado: v["estado"] as? String ?? "",
                                                total: v["total"] as? String ?? ""))
            }
            Task { @MainActor in self?.pedidos = lista.reversed() }
        } withCancel: { [weak self] error in
            Task { @MainActor in self?.ultimoError = FirebaseService.mensaje(error) }
        }
    }
    #endif

    nonisolated static func mensaje(_ error: Error) -> String {
        let ns = error as NSError
        return "Firebase (\(ns.code)): \(ns.localizedDescription)"
    }
}

enum FirebaseFeatureError: LocalizedError {
    case noConfigurado, sinSesion, archivoInvalido
    var errorDescription: String? {
        switch self {
        case .noConfigurado: return "Firebase no está configurado (falta GoogleService-Info.plist)."
        case .sinSesion: return "Inicia sesión en Firebase para respaldar la nota."
        case .archivoInvalido: return "La nota de voz debe ser un audio M4A de hasta 1 MB."
        }
    }
}
