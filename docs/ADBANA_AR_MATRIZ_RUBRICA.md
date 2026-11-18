# ADBANA AR: matriz de cumplimiento de la rúbrica

- **Fuente:** `Trabajo Final 2027.pdf` (Tecsup, Programación en Móviles Avanzado 2026-02).
- **Fecha:** 2026-11-18.
- **Estados permitidos:** CUMPLE · PARCIAL · NO CUMPLE · NO VERIFICADO · BLOQUEADO.

Un estado CUMPLE exige código funcional **y** una prueba ejecutada. Que exista un archivo con el nombre de la tecnología no basta.

## UIKit

| Requisito | Tecnología | Funcionalidad implementada | Archivo o módulo | Evidencia | Prueba | Estado | Pendiente |
|---|---|---|---|---|---|---|---|
| UIViewController | UIKit | Lista y detalle del historial de pedidos | `Features/Historial/HistorialViewController.swift`, `DetalleHistorialViewController.swift` | Pestaña "Pedidos" | UI `testHistorialUIKitCarga` (OK) | CUMPLE | Captura en un iPhone real |
| IBOutlet | UIKit, storyboard | Tabla, filtro, etiquetas y botones del detalle | `Historial.storyboard` y los controladores | Código | Mismo UI test | CUMPLE | — |
| IBAction | UIKit | `filtroCambiado`, `refrescar`, `actualizarEstado`, `reproducirNota` | Controladores del historial | Código | UI test (filtro "Activos") | CUMPLE | Probar `reproducirNota` en el dispositivo |
| TableView | UITableView | Historial con filtro por estado | `HistorialViewController.swift` | — | `historialTable` existe (OK) | CUMPLE | — |
| Segue | Storyboard | `mostrarDetalle` con `prepare(for:)` | `HistorialViewController.swift:100` | — | Sin test de navegación al detalle | PARCIAL | Añadir un UI test que toque una fila con datos |
| CoreData | NSPersistentContainer | Historial local de pedidos | `Persistence/HistorialStore.swift`, `Historial.xcdatamodeld` | — | `PersistenceAndParsingTests` (OK) | CUMPLE | — |
| Memoria local | FileManager y Keychain | Notas de voz en disco, caché USDZ (≤40 MB), Keychain | `VoiceNoteRecorder.swift`, `ModelRepository.swift`, `KeychainStore.swift` | — | Tests de persistencia (OK) | CUMPLE | — |
| Micrófono | AVFoundation (AVAudioRecorder) | Nota de voz de 30 s como máximo, con permiso, reproducción y transcripción opcional | `Features/VoiceNotes/*` | — | Sin prueba automática (no hay micrófono en CI) | NO VERIFICADO | Grabar, reproducir y eliminar en un iPhone, con captura |

## SwiftUI

| Requisito | Tecnología | Funcionalidad implementada | Archivo o módulo | Evidencia | Prueba | Estado | Pendiente |
|---|---|---|---|---|---|---|---|
| Reactividad | SwiftUI y @Observable | Los chips de ingredientes actualizan el 3D y el resumen al instante | `IngredientesPanel.swift`, `DishRecipe.swift` | `evidencias/sim-visor-3d-hamburguesa-*.png` | UI `testPersonalizarHamburguesaEn3DYCarrito` (OK) | CUMPLE | — |
| Estados | @State, @Observable, @Bindable, @Environment | Carga, error y vacío en la carta y el modelo; fases del checkout | `CartaView`, `ProductoDetailView`, `CheckoutViewModel` | — | `OrderTests` (OK) | CUMPLE | — |
| MVVM | ViewModels @Observable | `RestaurantPickerViewModel`, `CheckoutViewModel`, `ARPlacementController` | `Features/*` | — | Tests de pedidos (OK) | CUMPLE | — |
| SwiftData | @Model | Preferencias, borrador idempotente del pedido, carrito guardado | `Persistence/SwiftDataModels.swift` | — | `SwiftDataTests` (OK) | CUMPLE | — |
| REST | URLSession y async/await | Carta, pedido con `clave_operacion`, seguimiento | `Networking/APIClient.swift`, `DTOs.swift` | — | `APIClientTests` (OK). `BackendIntegrationTests` omitidos sin backend. | PARCIAL | Ejecutar la integración con Docker levantado |
| Animaciones | withAnimation, symbolEffect | Botón "Agregado", chips, avisos AR | Vistas | Capturas | UI tests (OK) | CUMPLE | — |
| Transiciones | `.transition`, `fullScreenCover`, `NavigationStack` | Carta → detalle → 3D → AR; checkout → seguimiento | Vistas | — | UI tests (OK) | CUMPLE | — |

## Firebase

| Requisito | Tecnología | Funcionalidad implementada | Archivo o módulo | Evidencia | Prueba | Estado | Pendiente |
|---|---|---|---|---|---|---|---|
| Authentication | FirebaseAuth 13.2.0 | Sesión anónima o con correo del comensal (no sustituye a Sanctum) | `Firebase/FirebaseService.swift`, `Account/AccountView.swift` | Compila | Ninguna contra Firebase real | NO VERIFICADO | Añadir `GoogleService-Info.plist` y probar el ingreso |
| Storage | FirebaseStorage | Respaldo opcional de notas de voz en `notas-voz/{uid}/` | `FirebaseService.subirNotaVoz` y `Firebase/storage.rules` | Reglas escritas | Ninguna | NO VERIFICADO | Desplegar las reglas, subir un archivo y probar que otro uid no puede leerlo |
| Realtime Database | FirebaseDatabase | Copia personal en vivo de los pedidos (`usuarios/{uid}/pedidos`) | `FirebaseService.reflejarPedido` y `Firebase/database.rules.json` | Reglas escritas | Ninguna | NO VERIFICADO | Desplegar y probar con dos dispositivos |

## Producto

| Requisito | Tecnología | Funcionalidad implementada | Archivo o módulo | Evidencia | Prueba | Estado | Pendiente |
|---|---|---|---|---|---|---|---|
| Aplicación empresarial | — | Carta digital AR integrada con Adbana SaaS (restaurantes) | Toda la app | — | — | CUMPLE | Describir el problema en el informe |
| Menú | REST y demo | Carta por categorías, búsqueda, disponibilidad | `CartaView.swift` | `evidencias/sim-01-inicio.png` | UI tests (OK) | CUMPLE | — |
| 3D | RealityKit | Visor con órbita y zoom; 3 platos propios y 1 USDZ CC0 | `ModelViewer3DView.swift`, `ProceduralDishBuilder.swift` | `evidencias/sim-visor-3d-*.png` | UI y unit tests (OK) | CUMPLE | Modelos más realistas (Blender o escaneo) |
| AR | ARKit y RealityKit | Planos horizontales, retículo, "Colocar plato", ARAnchor, tracking e interrupción, foto | `Features/AR/ARPlacementView.swift` | Compila para el dispositivo | Sin prueba física | NO VERIFICADO | Protocolo físico (abajo) |
| Ingredientes | Entidades separadas | Quitar o poner ingredientes, variante de guarnición, restaurar, reapilado | `DishRecipe.swift`, `ProceduralDishBuilder.swift` | Capturas | 10 unit y 2 UI tests (OK) | CUMPLE (3D) / NO VERIFICADO (en AR) | Probar en AR físico |
| Pedido | REST de Adbana | Envío idempotente; la personalización va en `notas`; el precio lo fija el servidor | `CheckoutViewModel.swift`, `Cart.swift` | — | `OrderTests` con mock (OK) | PARCIAL | Pedido de prueba real con backend local y captura |
| Multiplataforma (investigación) | Flutter y model-viewer | Cliente Android existente | `Adbana_saas/flutter` | — | No compilado (falta JDK) | NO VERIFICADO | Instalar un JDK y ejecutar `flutter build apk` |
| Unity con AR Foundation | Unity | — | — | — | — | BLOQUEADO | Unity no está instalado |

## Entrega

| Requisito | Estado | Pendiente |
|---|---|---|
| Informe (A4, interlineado 1.5, márgenes 3.5/2.5/3.0/2.5, Arial o Times 11/12/10) | NO CUMPLE | Redactar. Faltan integrantes y su participación reales. |
| Presentación (diapositivas) | NO CUMPLE | Resumen del informe |
| Gantt por integrante | NO CUMPLE | Requiere datos reales del grupo (mínimo 6 integrantes) |
| Evidencias | PARCIAL | Hay capturas de simulador. Faltan fotos y video de AR físico y de Firebase. |
| Guion de 20 minutos como máximo | NO CUMPLE | Propuesta: 3 min de problema, 3 de arquitectura, 10 de demostración y 4 de conclusiones |
| Carpeta en Drive (semana 16) | NO CUMPLE | Subir el código sin `build/`, `Local.xcconfig` ni `GoogleService-Info.plist` |

## Protocolo de validación física de AR (completar en iPhone)

Registrar dispositivo, versión de iOS y resultado con foto o video:

1. Se abre la cámara tras aceptar el permiso.
2. Aparecen "Buscando superficie" y luego "Superficie detectada" sobre la mesa.
3. Aparece el retículo con la vista previa translúcida.
4. "Colocar plato" pone el plato; medir con una regla que la pizza ocupa unos 30 cm (plato completo).
5. Caminar alrededor: el plato no sigue a la cámara.
6. Moverlo con un dedo y girarlo con dos.
7. Quitar "Champiñones" en AR: desaparecen y lo demás se mantiene.
8. Bloquear y desbloquear el iPhone: aparece "Sesión interrumpida" y luego "Reubicando…".
9. Tomar una foto: pide permiso de Fotos y la guarda.
10. Retirar el plato y volver a colocarlo.
