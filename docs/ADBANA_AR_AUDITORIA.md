# ADBANA AR: auditoría técnica

- **Fecha de la auditoría:** 2026-11-18
- **Alcance:** workspace `/Users/alexis/development` (proyectos `AdbanaAR-iOS`, `Adbana_saas` y `flutter`) y herramientas instaladas en la Mac de desarrollo.
- **Leyenda de estados:** IMPLEMENTADO · PARCIAL · NO IMPLEMENTADO · NO VERIFICADO · BLOQUEADO.

> Este documento separa lo que se **ejecutó** de lo que solo está **escrito**. Un resultado de simulador no prueba el funcionamiento de AR en un dispositivo físico.

---

## 1. Estado inicial

| Elemento | Hallazgo |
|---|---|
| Proyecto iOS | `AdbanaAR-iOS/AdbanaAR.xcodeproj`. Swift 5 y SwiftUI con UIKit. Despliegue iOS 18.0. Usa carpetas sincronizadas de Xcode. |
| Control de versiones iOS | **No es un repositorio Git**. No hay historial ni rama. Recomendación: `git init` antes de entregar, con el `.gitignore` existente. |
| Backend | `Adbana_saas`: Git en la rama `main`, sincronizado con `origin/main`. HEAD `cdc0c09`. Laravel en `src/` y PostgreSQL 16 en `docker-compose.yml`. |
| Android | `Adbana_saas/flutter` (paquete `adbana_carta`): Flutter con `model_viewer_plus` y `http`. |
| Unity | **No instalado**: no hay Unity Hub ni Editor en `/Applications`. |
| Blender | **No instalado** (`blender` no está en el PATH ni en `/Applications`). |
| Rúbrica | `~/Downloads/Trabajo Final 2027.pdf`, idéntica byte a byte a `Trabajo Final 2026-02.pdf`. **Leída** (4 páginas). |
| `Trabajo Final 2027(1).pdf` | No encontrado. |
| `Documentacion_Adbana_SaaS_80_revisada.pdf` | No encontrado. Existe `Documentacion_Adbana_SaaS_25.docx/.html`, que no se leyó en esta sesión. |
| Imágenes `IMG_0054.jpeg`, `IMG_0055.jpeg`, `IMG_0057.jpeg`, `IMG_0058.png` | **No encontradas** en el workspace ni en `~/Downloads`. Colocarlas en `AdbanaAR-iOS/docs/referencias/`. La interfaz actual **no** se basa en ellas. |

### Herramientas verificadas

| Herramienta | Versión o estado |
|---|---|
| Xcode | 26.6 (17F113) |
| Swift | 6.3.3 (el proyecto compila en modo Swift 5) |
| SDK del simulador | iOS 26.5 (iPhone 17) |
| Firebase iOS SDK (SPM) | 13.2.0, resuelto y enlazado |
| Flutter | 3.47.0 stable |
| Android SDK | platforms 33–37, NDK, cmake |
| Java | **No disponible** ("Unable to locate a Java Runtime"). El JDK incluido en Android Studio no se probó. |
| Unity / Blender | No instalados |
| PHP / Composer locales | No instalados (el backend corre con Docker) |

---

## 2. Arquitectura encontrada y decisión

**Encontrado:** la app iOS ya hace AR **nativa** con ARKit y RealityKit (opción B del docente), no con Unity.

**Decisión:** mantener ARKit y RealityKit en iOS. Motivos:

1. Unity no está instalado. La opción C (Unity con AR Foundation y Unity as a Library) queda **BLOQUEADA** en este equipo.
2. La rúbrica exige una app nativa en Xcode con UIKit y SwiftUI. Esa base ya existe y compila.
3. RealityKit cubre lo necesario sin otro motor: planos, raycast, `ARAnchor`, iluminación con `environmentTexturing`, materiales PBR, sombras de contacto y entidades separables para los ingredientes.

**Android:** el cliente Flutter usa `model_viewer_plus` (opción A, `<model-viewer>`, que delega la AR en Scene Viewer o ARCore). No se compiló en esta sesión porque falta un JDK. Estado: **NO VERIFICADO**.

**Unity:** queda como trabajo futuro documentado. No se presenta como integrado.

```
iOS nativo (Xcode)
 ├─ SwiftUI (MVVM): carta, detalle, personalización, visor 3D, AR, carrito, checkout, cuenta
 ├─ UIKit (storyboard): historial (UITableView, Segue, IBOutlet/IBAction, nota de voz)
 ├─ CoreData: historial · SwiftData: preferencias, borrador de pedido, carrito
 ├─ ARKit + RealityKit: visor 3D (cámara virtual) y AR de colocación sobre plano
 ├─ Firebase: Auth, Realtime DB (copia personal de pedidos), Storage (notas de voz)
 └─ REST → Laravel Adbana (/api/carta/{slug}, /pedidos, /seguimiento)
```

---

## 3. Contrato real del backend (verificado en `routes/api.php`)

| Ruta | Estado |
|---|---|
| `GET /api/carta/{slug}` | IMPLEMENTADO en el backend y consumido por la app |
| `POST /api/carta/{slug}/pedidos` | IMPLEMENTADO y consumido, con `clave_operacion` para idempotencia |
| `GET /api/carta/{slug}/seguimiento` | IMPLEMENTADO y consumido |
| `GET /api/carta/{slug}/productos/{id}/modelo` | IMPLEMENTADO (sirve GLB) |
| Modificadores o ingredientes por producto | **NO IMPLEMENTADO** en el backend |
| Cotización de precio con modificadores | **NO IMPLEMENTADO** en el backend |
| Campo `modelo_usdz` o referencia de receta AR | **NO IMPLEMENTADO** en el backend. La app ya lo lee como campo opcional. |

**Consecuencia:** la personalización de ingredientes **no cambia el precio**. Se envía como texto en `notas`, un campo real y validado del pedido. El precio sigue siendo el que calcula el servidor.

**Propuesta mínima (no aplicada):**

1. Añadir a `productos` una columna `modelo_ar` (texto, por ejemplo `receta:pizza` o una URL USDZ).
2. Añadir tablas de modificadores (`producto_modificadores`) y que `crearPedido` valide `items[].modificadores[]`.
3. Añadir `POST /api/carta/{slug}/cotizar`.

No se ejecutaron migraciones.

---

## 4. Componentes: estado

| Componente | Estado | Evidencia |
|---|---|---|
| Carta REST, detalle, carrito, checkout idempotente, seguimiento | IMPLEMENTADO | Tests `APIClientTests`, `OrderTests` y `DTODecodingTests` (pasan) |
| Modo demostración sin servidor | IMPLEMENTADO | UI test `testDemoAgregarAlCarritoYVerTotal` |
| Historial UIKit (UITableView, Segue, IBOutlet/IBAction) y CoreData | IMPLEMENTADO | UI test `testHistorialUIKitCarga` |
| Nota de voz (AVFoundation y permisos) | IMPLEMENTADO en código | **NO VERIFICADO** en dispositivo: el micrófono no funciona en las pruebas automáticas |
| SwiftData (preferencias, borrador, carrito) | IMPLEMENTADO | `SwiftDataTests` |
| Firebase Auth, Realtime DB y Storage | PARCIAL | El código y el SDK compilan. Faltan `GoogleService-Info.plist` (por seguridad no se versiona) y un proyecto Firebase activo. Reglas en `Firebase/`. **NO VERIFICADO** contra Firebase real. |
| Visor 3D (orbitar y zoom) | IMPLEMENTADO | Capturas `evidencias/sim-visor-3d-*.png` |
| **Platos 3D propios con ingredientes separables** (nuevo) | IMPLEMENTADO | `ProceduralDishBuilder.swift` y `DishCustomizationTests` |
| **Personalización en vivo (detalle, 3D y AR)** (nuevo) | IMPLEMENTADO | UI tests `testPersonalizarHamburguesaEn3DYCarrito` y `testVisor3DPolloCambiaGuarnicion` |
| AR: planos, retículo, vista previa, "Colocar plato", `ARAnchor`, estados de tracking, interrupción, foto | IMPLEMENTADO en código y compila para el dispositivo | **PENDIENTE DE VALIDACIÓN FÍSICA** |
| Unity con AR Foundation y Unity as a Library | BLOQUEADO | Unity no está instalado |
| Android con ARCore (Flutter y model-viewer) | NO VERIFICADO | Falta un JDK para compilar |
| Modelos de Blender | BLOQUEADO | Blender no está instalado. Los platos se generan con código (ver §6). |

---

## 5. Cambios de esta sesión

| Archivo | Cambio |
|---|---|
| `AdbanaAR/Domain/DishRecipe.swift` (nuevo) | Recetas `pizza`, `hamburguesa` y `pollo`, con ids estables, ingredientes obligatorios y opcionales, y variantes (guarnición). `DishCustomization` es @Observable y genera el resumen para la cocina. |
| `AdbanaAR/Features/Viewer3D/ProceduralDishBuilder.swift` (nuevo) | Platos a escala real en metros con primitivas RealityKit, materiales PBR y sombra de contacto. Cada ingrediente es una entidad con `name` igual a su id. La hamburguesa se reapila al quitar capas. |
| `AdbanaAR/Features/Carta/IngredientesPanel.swift` (nuevo) | Chips de ingredientes y selector de variantes. Se reutiliza en el detalle, el visor 3D y AR. |
| `Features/AR/ARPlacementView.swift` | Retículo con vista previa translúcida, botón "Colocar plato", `ARAnchor` real, fases separadas (buscando, detectada, listo, colocado), aviso de tracking limitado o sesión interrumpida, relocalización, retirar plato, ingredientes en vivo y foto con permiso *add-only*. |
| `Features/Viewer3D/ModelViewer3DView.swift` | Panel de ingredientes, botón "Ver en mi mesa" y encuadre del plato. La ampliación se aplica solo en el visor; AR conserva la escala real. |
| `Features/Carta/ProductoDetailView.swift`, `Domain/Cart.swift`, `Features/Cart/*` | La personalización viaja al carrito y se precarga en las notas del pedido (el cliente puede editarla). |
| `Features/Carta/CartaView.swift` | **Bug corregido:** `NavigationLink(value:)` no navegaba en iOS 26 dentro de una vista empujada con `navigationDestination(isPresented:)`. Se detectó con UI tests. |
| `Services/ModelRepository.swift`, `DishEntityFactory.swift`, `DemoCatalog.swift` | Nueva fuente `.receta` y tres platos personalizables en la demo. |
| `AdbanaAR.xcodeproj` | Se añadió `NSPhotoLibraryAddUsageDescription`. |
| `Firebase/database.rules.json`, `Firebase/storage.rules` (nuevos) | Acceso solo para el dueño (`auth.uid`), validación de campos, y en Storage audio/mp4 de 1 MB como máximo. |
| `AdbanaARTests/DishCustomizationTests.swift` (nuevo) y `AdbanaARUITests` | 10 tests unitarios y 2 UI tests nuevos. Además, helpers para tocar filas tapadas por la barra de pestañas. |

---

## 6. Modelos 3D

- `pizza.usdz`: CC0 (Innerscene). Ya estaba incluido y validado con `usdchecker`. Es una sola malla y **no** permite personalizar ingredientes.
- **Platos propios generados por código** (estrategia "modelado asistido o automatizado" sin Blender): son geometría simplificada y **no fotorrealista**. Tienen escala física verificada por test: el ancho coincide con el diámetro del plato (±1 cm) y no hay geometría bajo la mesa. Con Blender disponible se pueden reemplazar por USDZ que conserven los mismos nombres de nodo.

---

## 7. Pruebas ejecutadas (simulador iPhone 17, iOS 26.5)

| Ejecución | Resultado |
|---|---|
| Baseline de tests unitarios (antes de los cambios) | 34 tests: 31 OK, 3 omitidos (integración con un backend no levantado), 0 fallos |
| Tests unitarios tras los cambios | 44 tests: 41 OK, 3 omitidos, 0 fallos. Un test nuevo detectó que el arroz atravesaba la mesa 1 cm; se corrigió. |
| UI tests | 5/5 OK. Antes 4 fallaban por el botón tapado y el bug de navegación; ambos se corrigieron. |
| Compilación para dispositivo (`generic/platform=iOS`, sin firma) | BUILD SUCCEEDED |
| AR en dispositivo físico | **PENDIENTE DE VALIDACIÓN FÍSICA** |

---

## 8. Riesgos y bloqueos

1. **AR sin validar en iPhone.** Es el mayor riesgo para la demostración (8 puntos). Probar en el dispositivo cuanto antes (protocolo en la matriz).
2. **Firebase sin configurar.** Crear el proyecto, descargar `GoogleService-Info.plist` a `AdbanaAR/` (ignorado por Git) y desplegar las reglas con `firebase deploy --only database,storage`.
3. **Backend sin modificadores.** Los precios no varían con los ingredientes. Es correcto por diseño, pero conviene explicarlo en la exposición.
4. **Sin Git en iOS.** Riesgo de perder trabajo.
5. **Unity y Blender ausentes.** La alternativa multiplataforma real es el Flutter actual, que falta verificar.
6. Los datos del informe (integrantes, porcentajes, Gantt) **no están disponibles**. No se inventaron.
