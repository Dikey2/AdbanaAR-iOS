import SwiftUI

struct CartView: View {
    var onBrowse: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(CartStore.self) private var cart

    var body: some View {
        NavigationStack {
            Group {
                if cart.isEmpty {
                    ContentUnavailableView {
                        Label("Carrito vacío", systemImage: "cart")
                    } description: {
                        Text("Agrega platos desde la carta.")
                    } actions: {
                        Button("Ver carta", action: onBrowse).buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section(cart.restauranteNombre ?? "") {
                            ForEach(cart.lines) { line in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(line.producto.nombre).font(.headline)
                                        if let p = line.personalizacion {
                                            Text(p).font(.caption).foregroundStyle(.orange)
                                        }
                                        Text(Money.format(line.producto.precio.value)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Stepper("\(line.cantidad)", value: Binding(
                                        get: { line.cantidad },
                                        set: { cart.setQuantity($0, for: line.id) }
                                    ), in: 0...CartStore.maxUnitsPerProduct)
                                    .fixedSize()
                                    .accessibilityLabel("Cantidad de \(line.producto.nombre)")
                                }
                            }
                            .onDelete { idx in idx.map { cart.lines[$0].id }.forEach { cart.remove(productoId: $0) } }
                        }
                        Section {
                            HStack {
                                Text("Total estimado").font(.headline)
                                Spacer()
                                Text(Money.format(cart.estimatedTotal))
                                    .font(.title3.bold())
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: cart.estimatedTotal)
                                    .accessibilityIdentifier("totalEstimado")
                            }
                        } footer: {
                            Text("El restaurante calcula el precio definitivo con sus datos al registrar el pedido; el total confirmado aparecerá después de enviarlo.")
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        NavigationLink {
                            CheckoutView()
                        } label: {
                            Label("Continuar", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding()
                        .background(.bar)
                        .accessibilityIdentifier("continuarCheckout")
                    }
                }
            }
            .navigationTitle("Carrito")
            .toolbar {
                if !cart.isEmpty {
                    Button("Vaciar", role: .destructive) { withAnimation { cart.clear() } }
                }
            }
        }
    }
}
