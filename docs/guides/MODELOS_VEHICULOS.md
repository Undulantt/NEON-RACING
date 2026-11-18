# Modelos de los tres vehículos

VECTOR y APEX utilizan los archivos aportados en `assets/autos/Vector.glb` y
`assets/autos/Apex.glb`. COMET conserva `Not1965FordMustangHoonicorn.glb`.
Selecciona cualquiera de los perfiles al entrar al modo libre o carrera;
los rivales usan también el modelo correspondiente a su perfil.

Los GLB originales se conservan sin modificaciones. Godot extrae sus atlas
JPEG de 128 × 128; los JPEG y archivos `.import` deben acompañar a los modelos.
VECTOR contiene 5,106 triángulos y APEX 3,630, frente a 5,236 del COMET.

## Adaptación visual compartida

`CarVisual.gd` elige el recurso por perfil. `ImportedCarVisual.gd` normaliza
las tres exportaciones, sin duplicar lógica de conducción. `CometVisual.gd`
conserva su interfaz anterior como adaptador de compatibilidad.

- Rotación de 180° en Y, escala uniforme 0.65 y desplazamiento
  `(0, -0.585, 0.13)` antes de la escala existente del automóvil. Comparten
  posiciones de ejes y radio de neumático; se conserva la normalización COMET.
- Las cuatro ruedas importadas se conectan a los pivotes existentes mediante
  portadores de giro. Se buscan por prefijo, tolerando los sufijos de Blender.
- Se ocultan las mallas procedurales anteriores, conservando los emisores de
  turbo existentes. `RetroCar.gd` respeta la marca del modelo importado.
- Las superficies `LightBack` reciben un material independiente por automóvil
  para responder al freno. APEX llama `Body.004` a las luces traseras: por eso
  se identifican por material, sin alterar la pintura ni los cristales.
- Las piezas pintadas se identifican para el overlay BURST usando la marca
  `sf4_body`; conservan sus materiales originales y texturas.
- La selección del menú indica que los tres perfiles usan modelos del equipo.

No se modifican `ArcadeCar.gd`, habilidades, estadísticas ni competición.
No se generan cuerpos físicos desde las mallas. Se conserva la caja arcade;
por tanto, la silueta visible no constituye una colisión exacta de la carrocería.
Los colores dependen de los materiales originales y de la iluminación nocturna.
El overlay BURST existente continúa aplicándose a la pieza completa, incluidos
cristales cuando comparten esa pieza con la carrocería.

## Validación

En Godot 4.7.2, Compatibility: importación sin errores y **75/75** comprobaciones
en `tests/godot_vehicle_models.gd`. Se comprueban los tres perfiles en modo libre,
ruedas visibles y animadas, dirección delantera, luces de freno independientes,
binding BURST, apoyo vial, colisión/configuración, modelos de los seis
participantes en carrera y hashes de los archivos de física/estadísticas.
Se revisan capturas frontales y traseras a 1280 × 720.
La regresión específica del COMET pasa **29/29** comprobaciones; los tres
registros de importación e integración no contienen errores ni advertencias de Godot.

```powershell
godot --headless --path . --editor --import --quit
godot --path . --script res://tests/godot_vehicle_models.gd -- --passport-test --capture-models
godot --headless --path . --script res://tests/godot_comet_model.gd -- --passport-test
```

Las pruebas usan ajustes aislados. Informe y capturas locales:
`.local/artifacts/vehicle_models_validation.json` y
`.local/artifacts/evidence/vehicle_model_*.png`.
Estas comprobaciones verifican la integración; no equivalen a medir el rendimiento
en todos los equipos ni a una evaluación manual prolongada de conducción.
