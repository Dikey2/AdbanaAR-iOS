import SwiftUI
import SwiftData

@main
struct AdbanaARApp: App {
    @State private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            if let receta = CapturaFotoView.recetaSolicitada {
                CapturaFotoView(receta: receta)
            } else {
                principal
            }
        }
        .modelContainer(env.modelContainer)
    }

    private var principal: some View {
        Group {
            RootTabView()
                .environment(env)
                .environment(env.cart)
                .environment(env.firebase)
                .tint(Color.accentColor)
        }
    }
}

/// Solo para generar las fotos de la carta (`-captura-foto <receta>` en el simulador):
/// muestra el plato sobre un fondo de croma magenta que luego se recorta a transparente.
struct CapturaFotoView: View {
    let receta: DishRecipe

    static var recetaSolicitada: DishRecipe? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-captura-foto"), i + 1 < args.count else { return nil }
        return DishRecipe.from(referencia: "receta:" + args[i + 1])
    }

    var body: some View {
        ModelViewer3DView(titulo: "", fuente: .receta(receta), personalizacion: DishCustomization(receta: receta), modoFoto: true)
    }
}

struct RootTabView: View {
    @Environment(CartStore.self) private var cart
    @Environment(AppEnvironment.self) private var env
    private typealias Tab = AppTab

    var body: some View {
        @Bindable var env = env
        TabView(selection: $env.tab) {
            InicioView(onVerCarrito: { env.tab = .carrito })
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(Tab.inicio)

            CartView(onBrowse: { env.tab = .inicio })
                .tabItem { Label("Carrito", systemImage: "cart") }
                .badge(cart.totalUnits)
                .tag(Tab.carrito)

            HistorialContainerView()
                .ignoresSafeArea()
                .tabItem { Label("Pedidos", systemImage: "list.bullet.rectangle") }
                .tag(Tab.historial)

            AccountView()
                .tabItem { Label("Mi perfil", systemImage: "person") }
                .tag(Tab.cuenta)
        }
    }
}
