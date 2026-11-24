# Platos fotorrealistas (modelos CC0 de Poly Haven)

Estos scripts generan los archivos `AdbanaAR/Resources/Models/Escaneos/*.usdz` y las fotos `AdbanaAR/Resources/Fotos/*.png`.

## Requisitos

- macOS con Xcode: `usdcat`, `usdzip`, `usdchecker` y `usdrecord` vienen en `/usr/bin`.
- Conexión a internet para descargar de la API de Poly Haven.

## Pasos

1. `python3 build.py <asset> 1k`: descarga el modelo USD de Poly Haven y lo convierte a USDZ para RealityKit.
   - Cambia las texturas EXR por las versiones JPG.
   - Quita los shaders MaterialX.
   - Corrige el color base cuando apunta a una máscara.
   - Lo pasa de Z-up a Y-up.
   - Valida el resultado con `usdchecker --arkit`.
2. `python3 compose.py [escena…]`: arma cada plato (plato, bowl o tabla más los alimentos) en metros, a escala real. Valida cada escena y la renderiza con `usdrecord` para revisarla.
3. `swiftc -O recortar.swift -o recortar`, y luego `./recortar entrada.png salida.png 700 [croma]`: recorta el render a un cuadrado con fondo transparente.
   - Las fotos de pizza, hamburguesa y pollo (modelos generados por código) se capturan en el simulador con `-captura-foto <receta>`, sobre fondo magenta.
   - El argumento `croma` quita ese fondo magenta.

Los restaurantes donde aparecen estos platos son **ficticios** y la app los rotula como demostración. Los modelos no son platos escaneados por el equipo: son recursos CC0 de terceros, listados en `docs/CREDITOS_MODELOS_3D.md`.
