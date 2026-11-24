import SwiftUI

/// Atribución exigida por la licencia CC BY 4.0 de los escaneos de Sketchfab (vía Objaverse).
/// Los modelos se convirtieron a USDZ y se reescalaron; el pollo se recortó y se colocó sobre un plato de Poly Haven.
struct Credito: Identifiable {
    let plato: String
    let titulo: String
    let autor: String
    let url: String
    let licencia: String
    var id: String { url }

    static let modelos: [Credito] = [
        Credito(plato: "Pollo a la brasa entero (pollo recortado, sobre tabla Poly Haven)", titulo: "Roast Chicken Christmas Eve 2016", autor: "samhodge", url: "https://sketchfab.com/3d-models/b0a7a924c06f4146b9ef15f0dbc29b82", licencia: "CC BY 4.0"),
        Credito(plato: "Papas fritas caseras (también como guarnición)", titulo: "Home made frites", autor: "alban", url: "https://sketchfab.com/3d-models/27e5a025b66c492e9235ba7bbd9fc808", licencia: "CC BY 4.0"),
        Credito(plato: "Bife a la parrilla", titulo: "Florence Steak - Fiorentina bistecca", autor: "Shahriar Shahrabi", url: "https://sketchfab.com/3d-models/969285ae788c41cd914387cecf088708", licencia: "CC BY 4.0"),
        Credito(plato: "Hamburguesa con papas (hamburguesa extraída del escaneo)", titulo: "Burger", autor: "Keith Ito", url: "https://sketchfab.com/3d-models/0d339a3a91304192b4fc8d61ebd48bb1", licencia: "CC BY 4.0"),
        Credito(plato: "Hamburguesa de la casa", titulo: "Home made burger by T & Q", autor: "alban", url: "https://sketchfab.com/3d-models/1c6f76f53e8a4f8ba29de91630e4cadc", licencia: "CC BY 4.0"),
        Credito(plato: "Pizza de jamón", titulo: "Pizza! #3DST6", autor: "Victor", url: "https://sketchfab.com/3d-models/5b72a76136d547bf9789db41ac2323e2", licencia: "CC BY 4.0"),
        Credito(plato: "Pizza de la casa", titulo: "Pizza \"BigBoss\" Pancho", autor: "ponomarovmax", url: "https://sketchfab.com/3d-models/29832125251a44939fae1a21a3288f88", licencia: "CC BY 4.0"),
        Credito(plato: "Salmón a la plancha", titulo: "Salmon with whisky sauce", autor: "Emm (Scenario)", url: "https://sketchfab.com/3d-models/e8bfd53da4974957b0a6f662e6941ea0", licencia: "CC BY 4.0"),
        Credito(plato: "Gyozas a la plancha", titulo: "Japanese Gyoza (ObjectCapture)", autor: "Emm (Scenario)", url: "https://sketchfab.com/3d-models/d09c2142da5c41e498d4e8ce1e5a5502", licencia: "CC BY 4.0"),
        Credito(plato: "Momos al vapor", titulo: "Momo (food)", autor: "seirogan", url: "https://sketchfab.com/3d-models/c7fca235524a4a62b652da0571ebc824", licencia: "CC BY 4.0"),
        Credito(plato: "Tarta de limón merengada", titulo: "#3DST6 Tarte au citron meringuée", autor: "Maurice Svay", url: "https://sketchfab.com/3d-models/e20c3851d52c4261891b692a1dfc18c6", licencia: "CC BY 4.0"),
        Credito(plato: "Tarta de frambuesa", titulo: "Raspberry cake", autor: "Emm (Scenario)", url: "https://sketchfab.com/3d-models/cfcd4baf21944296bb93fc3c02d51dfe", licencia: "CC BY 4.0"),
        Credito(plato: "Pie con helado", titulo: "Strawberry pie - The Smith Restaurant", autor: "Guillermo", url: "https://sketchfab.com/3d-models/09af8624f011406c974b7cd4678650db", licencia: "CC BY 4.0"),
    ]
}

struct CreditosView: View {
    var body: some View {
        List {
            Section {
                ForEach(Credito.modelos) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.plato).font(.subheadline.bold())
                        Text("“\(c.titulo)” por \(c.autor) · \(c.licencia)").font(.caption)
                        if let url = URL(string: c.url) { Link(c.url, destination: url).font(.caption2) }
                    }
                }
            } header: { Text("Escaneos 3D (Sketchfab, CC BY 4.0)") } footer: {
                Text("Modificados: convertidos a USDZ, reescalados a tamaño real; el pollo y la hamburguesa se separaron de su base para combinarlos con guarniciones. Licencia: creativecommons.org/licenses/by/4.0")
            }
            Section {
                Text("Tortas, croissants, frutas, plato y tabla de madera: Poly Haven (polyhaven.com), licencia CC0.")
                Text("Pizza de pruebas: Innerscene, CC0. Platos de la carta de pruebas generados por código en la app.")
            } header: { Text("Otros modelos") }
            .font(.caption)
        }
        .navigationTitle("Créditos 3D")
    }
}
