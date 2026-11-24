# Propuesta para el backend: ubicación AR del restaurante afiliado

**Estado:** solo es una propuesta. No se modificó `Adbana_saas` ni se ejecutaron migraciones.

## Objetivo

La realidad aumentada de la carta debe funcionar **solo dentro del restaurante afiliado**. Fuera del local, el cliente puede ver el plato en el visor 3D, pero no puede abrir la AR.

## Qué hace hoy la app iOS

- El encargado fija la zona en **Inicio → "¿Tienes un restaurante?"** o en **Mi perfil → Afiliar restaurante**. Para fijar el centro usa su ubicación actual o toca el mapa, y define un radio de 20 a 300 m.
- La zona se guarda **en el dispositivo** (SwiftData, `UbicacionRestaurante`). Por eso solo aplica en el iPhone donde se configuró. Sirve para la demostración, pero no reemplaza la configuración en el servidor.
- Antes de abrir la cámara, la app pide la ubicación ("mientras se usa"). Con esa lectura:
  - permite la AR si el cliente está dentro de `radio + min(precisión, 30 m)`;
  - la rechaza si la precisión es peor que ±100 m.
- Durante la sesión AR sigue leyendo la ubicación. Si dos lecturas seguidas quedan fuera de la zona, retira el plato y cierra la AR.
- Si la carta del servidor trae `configuracion.ubicacion_ar`, esa zona **tiene prioridad** y no se puede editar desde la app.

## Cambio propuesto en Laravel (requiere aprobación del equipo)

1. Guardar la zona en la `configuracion` (JSON) del restaurante, que ya existe. Así **no hace falta una migración nueva**:

   ```json
   "ubicacion_ar": { "latitud": -12.0, "longitud": -77.0, "radio_metros": 60 }
   ```

2. Agregar al panel del administrador un formulario con mapa que valide estos rangos:
   - `latitud`: de -90 a 90;
   - `longitud`: de -180 a 180;
   - `radio_metros`: de 20 a 500.
3. Exponer el campo en `GET /api/carta/{slug}` dentro de `restaurante.configuracion`. La app ya lo decodifica, e ignora el campo si viene mal formado.

## Limitaciones honestas

- El GPS puede tener un error de 5 a 30 m en interiores, y en un centro comercial puede ser mayor.
- La ubicación se puede falsificar con herramientas de desarrollador. La geocerca es un control de experiencia, **no un control de seguridad**.
- Si se necesita una garantía fuerte de que el cliente está en el local, hay que combinarla con el QR de la mesa: la app ya lee `mesa` desde el QR.
