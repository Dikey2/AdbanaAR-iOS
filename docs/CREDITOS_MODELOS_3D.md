# Créditos de modelos 3D

## Escaneos de Sketchfab (licencia CC BY 4.0)

Los escaneos se obtuvieron mediante el dataset abierto Objaverse (Allen AI), que indica la licencia de cada modelo; esa licencia se verificó en sus metadatos el 2026-11-21.

Los cambios hechos a estos modelos fueron:
- conversión de GLB a USDZ con `tools/escaneos/glb2usdz.py`;
- reescalado a tamaño real;
- texturas reducidas a 1024 px;
- el pollo y la hamburguesa se separaron de su base y se combinaron con papas, limón y lima sobre la tabla de Poly Haven, para que cada pieza se pueda quitar en 3D y AR.

La app muestra estos créditos en **Mi perfil → Créditos de modelos 3D**.

| Plato en la app | Modelo original | Autor |
|---|---|---|
| Pollo a la brasa entero (sobre plato Poly Haven) | [Roast Chicken Christmas Eve 2016](https://sketchfab.com/3d-models/b0a7a924c06f4146b9ef15f0dbc29b82) | samhodge |
| Papas fritas caseras | [Home made frites](https://sketchfab.com/3d-models/27e5a025b66c492e9235ba7bbd9fc808) | alban |
| Bife a la parrilla | [Florence Steak - Fiorentina bistecca](https://sketchfab.com/3d-models/969285ae788c41cd914387cecf088708) | Shahriar Shahrabi |
| Hamburguesa con papas | [Burger](https://sketchfab.com/3d-models/0d339a3a91304192b4fc8d61ebd48bb1) | Keith Ito |
| Hamburguesa de la casa | [Home made burger by T & Q](https://sketchfab.com/3d-models/1c6f76f53e8a4f8ba29de91630e4cadc) | alban |
| Pizza de jamón | [Pizza! #3DST6](https://sketchfab.com/3d-models/5b72a76136d547bf9789db41ac2323e2) | Victor |
| Pizza de la casa | [Pizza "BigBoss" Pancho](https://sketchfab.com/3d-models/29832125251a44939fae1a21a3288f88) | ponomarovmax |
| Salmón a la plancha | [Salmon with whisky sauce](https://sketchfab.com/3d-models/e8bfd53da4974957b0a6f662e6941ea0) | Emm (Scenario) |
| Gyozas a la plancha | [Japanese Gyoza (ObjectCapture)](https://sketchfab.com/3d-models/d09c2142da5c41e498d4e8ce1e5a5502) | Emm (Scenario) |
| Momos al vapor | [Momo (food)](https://sketchfab.com/3d-models/c7fca235524a4a62b652da0571ebc824) | seirogan |
| Tarta de limón merengada | [#3DST6 Tarte au citron meringuée](https://sketchfab.com/3d-models/e20c3851d52c4261891b692a1dfc18c6) | Maurice Svay |
| Tarta de frambuesa | [Raspberry cake](https://sketchfab.com/3d-models/cfcd4baf21944296bb93fc3c02d51dfe) | Emm (Scenario) |
| Pie con helado | [Strawberry pie - The Smith Restaurant](https://sketchfab.com/3d-models/09af8624f011406c974b7cd4678650db) | Guillermo |

## Poly Haven (licencia CC0)

Todos los modelos de terceros tienen licencia **CC0 1.0** (dominio público) y provienen de [Poly Haven](https://polyhaven.com/models). Los autores son los que figuran en la API de Poly Haven, consultada el 2026-11-21.

| Modelo (id de Poly Haven) | Uso en la app | Autor según Poly Haven |
|---|---|---|
| `croissant` | Croissants de mantequilla | Dario Barresi (escaneo), Greg Zaal (procesado) |
| `carrot_cake` | Torta de zanahoria | Greg Zaal (fotografía), James Ray Cock (procesado) |
| `strawberry_chocolate_cake` | Torta de chocolate con fresas | Kuutti Siitonen |
| `carved_wooden_plate` | Plato de madera de las tortas y croissants | Jan Martens |
| `wooden_bowl_01` | Bowl de frutas | Oliver Harries |
| `wooden_cutting_board` | Tabla de frutas | Kuutti Siitonen |
| `food_apple_01`, `food_avocado_01`, `food_kiwi_01`, `food_lime_01`, `food_lychee_01`, `food_pomegranate_01` | Frutas del bowl y de la tabla | Oliver Harries |
| `lemon` | Bowl y tabla de frutas | Kuutti Siitonen |
| `pizza.usdz` (carta de pruebas) | Pizza de demostración | Innerscene (CC0), ya incluido antes |

La pizza, la hamburguesa y el pollo personalizables de la "Carta de pruebas técnicas" los genera la app por código (`ProceduralDishBuilder.swift`), con texturas procedurales propias.

Los restaurantes de demostración (Dulce Nube, Brasa Dorada, Barrio Burger, Forno Napoli y Fruta Viva) son ficticios, al igual que sus precios. La app los rotula como "Demo" y no envía pedidos con ellos.
