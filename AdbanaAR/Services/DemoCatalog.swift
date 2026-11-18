import Foundation

/// Carta de demostración SIN conexión, claramente rotulada en la interfaz.
/// Sirve para mostrar el visor 3D/AR si el backend no está disponible durante la exposición.
/// No envía pedidos: el checkout se deshabilita en este modo.
enum DemoCatalog {
    static let slug = "demo-local"

    static let carta = CartaResponse(
        restaurante: RestauranteDTO(
            nombre: "Demostración local (sin servidor)",
            slug: slug,
            telefono: nil,
            configuracion: ConfiguracionDTO(modalidades: ["mesa", "recojo"], descripcion: "Datos de ejemplo incluidos en la app. No corresponden a un restaurante real.", direccion: nil, horario: nil)
        ),
        carta: [
            CategoriaDTO(id: 2, nombre: "Personalizables en 3D", productos: [
                ProductoDTO(id: 9101, nombre: "Pizza personalizable", descripcion: "Modelo propio a escala (≈26 cm). Quita queso, tomate, champiñones o aceitunas y mira el cambio en 3D.",
                            precio: DecimalString(Decimal(string: "38.00")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: "receta:pizza", disponible: true),
                ProductoDTO(id: 9102, nombre: "Hamburguesa clásica", descripcion: "Capas independientes: retira tomate, cebolla, lechuga o queso.",
                            precio: DecimalString(Decimal(string: "24.00")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: "receta:hamburguesa", disponible: true),
                ProductoDTO(id: 9103, nombre: "Pollo a la plancha", descripcion: "Elige guarnición (papas, arroz o ensalada) y quita salsa criolla o limón.",
                            precio: DecimalString(Decimal(string: "29.00")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: "receta:pollo", disponible: true),
            ]),
            CategoriaDTO(id: 1, nombre: "Platos de ejemplo", productos: [
                ProductoDTO(id: 9001, nombre: "Pizza de demostración", descripcion: "Modelo 3D CC0 (Innerscene) incluido en la app para probar RealityKit y ARKit.",
                            precio: DecimalString(Decimal(string: "40.00")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: "bundle:pizza.usdz", disponible: true),
                ProductoDTO(id: 9002, nombre: "Plato sin modelo 3D", descripcion: "Muestra la representación genérica cuando un producto no tiene modelo.",
                            precio: DecimalString(Decimal(string: "25.50")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: nil, disponible: true),
                ProductoDTO(id: 9003, nombre: "Producto agotado", descripcion: "Ejemplo de producto no disponible.",
                            precio: DecimalString(Decimal(string: "12.00")!), imagen: nil, modelo3D: nil,
                            modeloUSDZ: nil, disponible: false),
            ]),
        ],
        mesas: [MesaDTO(id: 1, nombre: "Mesa 01", ocupada: false), MesaDTO(id: 2, nombre: "Mesa 02", ocupada: true)],
        mesa: nil
    )
}
