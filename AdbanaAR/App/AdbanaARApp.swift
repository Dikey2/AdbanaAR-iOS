import SwiftUI
import SwiftData

@main
struct AdbanaARApp: App {
    @State private var env = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(env)
                .environment(env.cart)
                .environment(env.firebase)
                .tint(Color.accentColor)
        }
        .modelContainer(env.modelContainer)
    }
}

struct RootTabView: View {
    @Environment(CartStore.self) private var cart
    @State private var tab: Tab = .carta

    enum Tab: Hashable { case carta, carrito, historial, cuenta }

    var body: some View {
        TabView(selection: $tab) {
            RestaurantPickerView()
                .tabItem { Label("Carta", systemImage: "menucard") }
                .tag(Tab.carta)

            CartView(onBrowse: { tab = .carta })
                .tabItem { Label("Carrito", systemImage: "cart") }
                .badge(cart.totalUnits)
                .tag(Tab.carrito)

            HistorialContainerView()
                .ignoresSafeArea()
                .tabItem { Label("Pedidos", systemImage: "list.bullet.rectangle") }
                .tag(Tab.historial)

            AccountView()
                .tabItem { Label("Cuenta", systemImage: "person.crop.circle") }
                .tag(Tab.cuenta)
        }
    }
}
