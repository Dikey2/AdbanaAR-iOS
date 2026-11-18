import SwiftUI

/// Lista de ingredientes y variantes. Usado en el detalle, el visor 3D y la vista AR:
/// la misma instancia de `DishCustomization` mantiene sincronizados los tres.
struct IngredientesPanel: View {
    let personalizacion: DishCustomization
    var compacto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(personalizacion.receta.ingredientes) { ing in
                        chip(ing)
                    }
                }
            }
            ForEach(personalizacion.receta.variantes) { grupo in
                Picker(grupo.nombre, selection: Binding(
                    get: { personalizacion.variantes[grupo.id] ?? grupo.predeterminada },
                    set: { nuevo in withAnimation(.snappy) { personalizacion.seleccionar(variante: grupo.id, opcion: nuevo) } }
                )) {
                    ForEach(grupo.opciones) { Text($0.nombre).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("variante-\(grupo.id)")
            }
            if !compacto {
                HStack {
                    Text(personalizacion.resumen.map { "Tu plato: \($0)" } ?? "Receta original")
                        .font(.footnote)
                        .foregroundStyle(personalizacion.esPredeterminada ? Color.secondary : Color.orange)
                        .contentTransition(.opacity)
                    Spacer()
                    if !personalizacion.esPredeterminada {
                        Button("Restaurar") { withAnimation(.snappy) { personalizacion.restaurar() } }
                            .font(.footnote)
                            .accessibilityIdentifier("restaurarIngredientes")
                    }
                }
                Text("Los cambios se envían como nota a cocina. El precio lo confirma el restaurante.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: personalizacion.version)
    }

    private func chip(_ ing: DishRecipe.Ingrediente) -> some View {
        let incluido = personalizacion.incluido(ing.id)
        return Button {
            withAnimation(.snappy) { personalizacion.alternar(ing.id) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Label(ing.nombre, systemImage: ing.obligatorio ? "lock.fill" : (incluido ? "checkmark.circle.fill" : "circle"))
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(incluido ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                .strikethrough(!incluido)
                .foregroundStyle(incluido ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(ing.obligatorio)
        .accessibilityIdentifier("ingrediente-\(ing.id)")
        .accessibilityLabel("\(ing.nombre), \(ing.obligatorio ? "obligatorio" : (incluido ? "incluido" : "quitado"))")
    }
}
