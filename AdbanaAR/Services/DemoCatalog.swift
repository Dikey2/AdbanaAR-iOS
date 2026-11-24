import Foundation
import SwiftUI

/// Carta de demostración SIN conexión, claramente rotulada en la interfaz.
/// Sirve para mostrar el visor 3D/AR si el backend no está disponible durante la exposición.
/// No envía pedidos: el checkout se deshabilita en este modo.
enum DemoCatalog {
    static let slug = "demo-local"

    /// Todos los restaurantes de demostración usan el prefijo "demo-": nunca envían pedidos.
    static func esDemo(_ slug: String?) -> Bool { slug?.hasPrefix("demo-") ?? false }

    static func restaurante(slug: String) -> DemoRestaurante? { restaurantes.first { $0.slug == slug } }

    /// Productos de todos los restaurantes de demostración y de la carta de pruebas.
    static var todosLosProductos: [ProductoDTO] {
        (restaurantes.map(\.carta) + [carta]).flatMap { $0.carta.flatMap(\.productos) }
    }

    static let carta = CartaResponse(
        restaurante: RestauranteDTO(
            nombre: "Carta de pruebas técnicas",
            slug: slug,
            telefono: nil,
            configuracion: ConfiguracionDTO(modalidades: ["mesa", "recojo"], descripcion: "Datos de ejemplo incluidos en la app. No corresponden a un restaurante real.", direccion: nil, horario: nil)
        ),
        carta: [
            CategoriaDTO(id: 2, nombre: "Ingredientes en 3D (modelos generados por código)", productos: [
                ProductoDTO(id: 9101, nombre: "Pizza personalizable", descripcion: "Quita queso, tomate, champiñones o aceitunas y mira el cambio en 3D.",
                            precio: DecimalString(Decimal(string: "38.00")!), imagen: "foto:foto-pizza", modelo3D: nil,
                            modeloUSDZ: "receta:pizza", disponible: true),
                ProductoDTO(id: 9102, nombre: "Hamburguesa clásica", descripcion: "Capas independientes: retira tomate, cebolla, lechuga o queso.",
                            precio: DecimalString(Decimal(string: "24.00")!), imagen: "foto:foto-hamburguesa", modelo3D: nil,
                            modeloUSDZ: "receta:hamburguesa", disponible: true),
                ProductoDTO(id: 9103, nombre: "Pollo a la plancha", descripcion: "Elige guarnición (papas, arroz o ensalada) y quita salsa criolla o limón.",
                            precio: DecimalString(Decimal(string: "29.00")!), imagen: "foto:foto-pollo", modelo3D: nil,
                            modeloUSDZ: "receta:pollo", disponible: true),
            ]),
            CategoriaDTO(id: 1, nombre: "Platos de ejemplo", productos: [
                ProductoDTO(id: 9001, nombre: "Pizza de demostración", descripcion: "Modelo 3D CC0 (Innerscene) incluido en la app para probar RealityKit y ARKit.",
                            precio: DecimalString(Decimal(string: "40.00")!), imagen: "foto:foto-pizza_cc0", modelo3D: nil,
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

// MARK: - Restaurantes de demostración

/// Rubro gastronómico para filtrar en el inicio.
enum Rubro: String, CaseIterable, Identifiable, Sendable {
    case pollerias, hamburguesas, pizzas, pescados, asiatica, postres, frutas
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .pollerias: return "Pollerías"
        case .hamburguesas: return "Hamburguesas"
        case .pizzas: return "Pizzas"
        case .pescados: return "Pescados"
        case .asiatica: return "Asiática"
        case .postres: return "Postres"
        case .frutas: return "Frutas y jugos"
        }
    }
    /// Foto (render del propio modelo 3D) usada en la tarjeta del rubro.
    var foto: String {
        switch self {
        case .pollerias: return "foto-combo_pollo"
        case .hamburguesas: return "foto-combo_burger"
        case .pizzas: return "foto-pizza_3dst6"
        case .pescados: return "foto-salmon"
        case .asiatica: return "foto-gyoza"
        case .postres: return "foto-torta_chocolate_fresas"
        case .frutas: return "foto-bowl_frutas"
        }
    }
}

/// Restaurante ficticio para la demostración. Nombres, precios y cartas son de ejemplo
/// (la interfaz lo indica); los platos usan modelos 3D a escala real incluidos en la app.
struct DemoRestaurante: Identifiable, Sendable {
    let slug: String
    let nombre: String
    let rubro: Rubro
    let lema: String
    let simbolo: String
    let colorHex: UInt32
    let portada: String
    let carta: CartaResponse

    var id: String { slug }
    var color: Color { Color(hex: colorHex) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension DemoCatalog {
    private static func p(_ id: Int, _ nombre: String, _ descripcion: String, _ precio: String, foto: String, modelo: String) -> ProductoDTO {
        ProductoDTO(id: id, nombre: nombre, descripcion: descripcion, precio: DecimalString(Decimal(string: precio)!),
                    imagen: "foto:\(foto)", modelo3D: nil, modeloUSDZ: modelo, disponible: true)
    }

    private static func carta(_ slug: String, _ nombre: String, _ descripcion: String, horario: String,
                              _ categorias: [CategoriaDTO]) -> CartaResponse {
        CartaResponse(
            restaurante: RestauranteDTO(nombre: nombre, slug: slug, telefono: nil,
                                        configuracion: ConfiguracionDTO(modalidades: ["mesa", "recojo", "delivery"],
                                                                        descripcion: descripcion, direccion: nil, horario: horario)),
            carta: categorias, mesas: nil, mesa: nil)
    }

    static let restaurantes: [DemoRestaurante] = [
        DemoRestaurante(
            slug: "demo-dulce-nube", nombre: "Dulce Nube", rubro: .postres,
            lema: "Tortas y pastelería artesanal", simbolo: "birthday.cake.fill", colorHex: 0x8E4A6B,
            portada: "foto-torta_chocolate_fresas",
            carta: carta("demo-dulce-nube", "Dulce Nube", "Pastelería artesanal. Mira cada postre en 3D a escala real y ponlo sobre tu mesa.", horario: "9:00 – 21:00", [
                CategoriaDTO(id: 21, nombre: "Tortas enteras", productos: [
                    p(9202, "Torta de chocolate con fresas", "Bizcocho de chocolate cubierto de fresas frescas y chocolate rallado. 24 cm, 10 porciones.", "78.00", foto: "foto-torta_chocolate_fresas", modelo: "escaneo:torta_chocolate_fresas"),
                    p(9201, "Torta de zanahoria", "Queque húmedo de zanahoria con frosting de queso crema y nueces. 22 cm.", "65.00", foto: "foto-torta_zanahoria", modelo: "escaneo:torta_zanahoria"),
                ]),
                CategoriaDTO(id: 23, nombre: "Tartas individuales", productos: [
                    p(9204, "Tarta de limón merengada", "Masa sablée, crema de limón y merengue tostado. Individual.", "12.00", foto: "foto-tarta_limon", modelo: "escaneo:tarta_limon"),
                    p(9205, "Tarta de frambuesa", "Base de masa con frambuesas frescas. Individual.", "14.00", foto: "foto-tarta_frambuesa", modelo: "escaneo:tarta_frambuesa"),
                    p(9206, "Pie con helado", "Pie de frutas horneado con una bola de helado.", "16.00", foto: "foto-pie_fresa", modelo: "escaneo:pie_fresa"),
                ]),
                CategoriaDTO(id: 22, nombre: "Panadería", productos: [
                    p(9203, "Croissants de mantequilla (2 u.)", "Hojaldre dorado y crujiente, servido en plato de madera.", "14.00", foto: "foto-croissants", modelo: "escaneo:croissants"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-brasa-dorada", nombre: "Brasa Dorada", rubro: .pollerias,
            lema: "Pollo a la brasa y parrillas", simbolo: "flame.fill", colorHex: 0xC2571A,
            portada: "foto-combo_pollo",
            carta: carta("demo-brasa-dorada", "Brasa Dorada", "Pollo dorado a la brasa, papas fritas caseras y cortes a la parrilla.", horario: "12:00 – 23:00", [
                CategoriaDTO(id: 31, nombre: "A la brasa", productos: [
                    p(9401, "Pollo a la brasa entero", "Pollo entero dorado con papas fritas, limón y lima, en tabla. Para 3 o 4 personas.", "62.00", foto: "foto-combo_pollo", modelo: "escaneo:combo_pollo"),
                    p(9403, "Bife a la parrilla con papas", "Corte de res en tajadas, término medio, al estilo fiorentina, con papas fritas.", "68.00", foto: "foto-combo_bife", modelo: "escaneo:combo_bife"),
                ]),
                CategoriaDTO(id: 32, nombre: "Acompañamientos", productos: [
                    p(9402, "Papas fritas caseras", "Papas cortadas a mano y fritas al momento.", "12.00", foto: "foto-papas_fritas", modelo: "escaneo:papas_fritas"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-barrio-burger", nombre: "Barrio Burger", rubro: .hamburguesas,
            lema: "Hamburguesas a la plancha", simbolo: "takeoutbag.and.cup.and.straw.fill", colorHex: 0x2F3A4A,
            portada: "foto-combo_burger",
            carta: carta("demo-barrio-burger", "Barrio Burger", "Hamburguesas jugosas a la plancha con pan artesanal.", horario: "12:00 – 00:00", [
                CategoriaDTO(id: 41, nombre: "Hamburguesas", productos: [
                    p(9411, "Hamburguesa con papas", "Carne a la plancha, lechuga y pan dorado, con papas fritas. Servida en tabla.", "26.00", foto: "foto-combo_burger", modelo: "escaneo:combo_burger"),
                    p(9412, "Hamburguesa de la casa", "Carne, queso, tomate y lechuga en pan con semillas.", "22.00", foto: "foto-burger_casera", modelo: "escaneo:burger_casera"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-forno-napoli", nombre: "Forno Napoli", rubro: .pizzas,
            lema: "Pizzas al horno de piedra", simbolo: "fork.knife", colorHex: 0x2E7D4F,
            portada: "foto-pizza_3dst6",
            carta: carta("demo-forno-napoli", "Forno Napoli", "Pizzas de masa delgada horneadas en horno de piedra.", horario: "13:00 – 23:30", [
                CategoriaDTO(id: 51, nombre: "Pizzas", productos: [
                    p(9421, "Pizza de jamón", "Salsa de tomate, mozzarella y jamón. 30 cm.", "42.00", foto: "foto-pizza_3dst6", modelo: "escaneo:pizza_3dst6"),
                    p(9422, "Pizza de la casa", "Mozzarella, carnes y aceitunas negras. 32 cm.", "45.00", foto: "foto-pizza_bigboss", modelo: "escaneo:pizza_bigboss"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-mar-azul", nombre: "Mar Azul", rubro: .pescados,
            lema: "Pescados a la plancha", simbolo: "fish.fill", colorHex: 0x1F5E8C,
            portada: "foto-salmon",
            carta: carta("demo-mar-azul", "Mar Azul", "Pescados frescos a la plancha.", horario: "11:00 – 17:00", [
                CategoriaDTO(id: 71, nombre: "Del mar", productos: [
                    p(9431, "Salmón a la plancha", "Filete de salmón con puré y salsa de la casa.", "48.00", foto: "foto-salmon", modelo: "escaneo:salmon"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-sakura", nombre: "Sakura", rubro: .asiatica,
            lema: "Cocina asiática", simbolo: "leaf.circle.fill", colorHex: 0xA23B4F,
            portada: "foto-gyoza",
            carta: carta("demo-sakura", "Sakura", "Gyozas y dumplings hechos a mano.", horario: "12:30 – 22:30", [
                CategoriaDTO(id: 81, nombre: "Dumplings", productos: [
                    p(9441, "Gyozas a la plancha (7 u.)", "Empanaditas japonesas doradas, con salsa de soya.", "24.00", foto: "foto-gyoza", modelo: "escaneo:gyoza"),
                    p(9442, "Momos al vapor", "Dumplings al vapor rellenos, con ensalada de col.", "26.00", foto: "foto-momo", modelo: "escaneo:momo"),
                ]),
            ])),
        DemoRestaurante(
            slug: "demo-fruta-viva", nombre: "Fruta Viva", rubro: .frutas,
            lema: "Frutas frescas para compartir", simbolo: "leaf.fill", colorHex: 0x5E8C2A,
            portada: "foto-bowl_frutas",
            carta: carta("demo-fruta-viva", "Fruta Viva", "Fruta fresca para compartir, en 3D fotorrealista.", horario: "8:00 – 20:00", [
                CategoriaDTO(id: 61, nombre: "Para compartir", productos: [
                    p(9301, "Bowl de frutas de estación", "Granada, manzana, kiwi, limón, lima y lichis en bowl de madera.", "22.00", foto: "foto-bowl_frutas", modelo: "escaneo:bowl_frutas"),
                    p(9302, "Tabla de frutas", "Palta, granada, manzana, kiwi, limón, lima y lichis sobre tabla de madera.", "28.00", foto: "foto-tabla_frutas", modelo: "escaneo:tabla_frutas"),
                ]),
            ])),
    ]
}
