import CoreData
import Foundation

/// Registro de lectura para la capa UIKit (evita exponer NSManagedObject fuera del contexto).
struct HistorialRegistro: Equatable, Hashable {
    let pedidoId: Int
    let slug: String
    let restauranteNombre: String
    let total: String
    let pagado: String
    let estado: String
    let tipo: String
    let creadoEn: Date
    let actualizadoEn: Date
    let notaVozArchivo: String?

    var status: OrderStatus { OrderStatus(raw: estado) }
}

/// Historial local de pedidos del cliente en este dispositivo (CoreData).
/// Solo guarda lo que el backend devolvió al cliente; el token de seguimiento va en Keychain.
final class HistorialStore {
    private static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: HistorialStore.self)
        guard let url = bundle.url(forResource: "Historial", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("No se encontró Historial.momd en el bundle")
        }
        return model
    }()

    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Historial", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { assertionFailure("CoreData: \(error.localizedDescription)") }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private func find(slug: String, pedidoId: Int) -> HistorialPedido? {
        let req = HistorialPedido.fetchRequest()
        req.predicate = NSPredicate(format: "slug == %@ AND pedidoId == %lld", slug, Int64(pedidoId))
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    @discardableResult
    func upsert(pedidoId: Int, slug: String, restauranteNombre: String, total: String, pagado: String = "0.00",
                estado: String, tipo: String, notaVozArchivo: String? = nil) -> HistorialRegistro? {
        let obj = find(slug: slug, pedidoId: pedidoId) ?? {
            let o = HistorialPedido(context: context)
            o.creadoEn = .now
            o.pedidoId = Int64(pedidoId)
            o.slug = slug
            return o
        }()
        obj.restauranteNombre = restauranteNombre
        obj.total = total
        obj.pagado = pagado
        obj.estado = estado
        obj.tipo = tipo
        if let notaVozArchivo { obj.notaVozArchivo = notaVozArchivo }
        obj.actualizadoEn = .now
        save()
        return map(obj)
    }

    func updateEstado(slug: String, pedidoId: Int, estado: String, pagado: String, total: String) {
        guard let obj = find(slug: slug, pedidoId: pedidoId) else { return }
        guard obj.estado != estado || obj.pagado != pagado || obj.total != total else { return }
        obj.estado = estado
        obj.pagado = pagado
        obj.total = total
        obj.actualizadoEn = .now
        save()
    }

    enum Filtro: Int { case todos = 0, activos = 1, finalizados = 2 }

    func fetch(filtro: Filtro = .todos) -> [HistorialRegistro] {
        let req = HistorialPedido.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "creadoEn", ascending: false)]
        switch filtro {
        case .todos: break
        case .activos: req.predicate = NSPredicate(format: "NOT (estado IN %@)", ["entregado", "cancelado"])
        case .finalizados: req.predicate = NSPredicate(format: "estado IN %@", ["entregado", "cancelado"])
        }
        return ((try? context.fetch(req)) ?? []).map(map)
    }

    func registro(slug: String, pedidoId: Int) -> HistorialRegistro? {
        find(slug: slug, pedidoId: pedidoId).map(map)
    }

    func delete(slug: String, pedidoId: Int) {
        guard let obj = find(slug: slug, pedidoId: pedidoId) else { return }
        context.delete(obj)
        save()
    }

    private func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch { context.rollback() }
    }

    private func map(_ o: HistorialPedido) -> HistorialRegistro {
        HistorialRegistro(pedidoId: Int(o.pedidoId), slug: o.slug ?? "", restauranteNombre: o.restauranteNombre ?? "",
                          total: o.total ?? "0.00", pagado: o.pagado ?? "0.00", estado: o.estado ?? "pendiente",
                          tipo: o.tipo ?? "", creadoEn: o.creadoEn ?? .now, actualizadoEn: o.actualizadoEn ?? .now,
                          notaVozArchivo: o.notaVozArchivo)
    }
}
