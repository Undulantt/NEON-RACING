# Modelo del COMET

El perfil COMET utiliza `assets/autos/Not1965FordMustangHoonicorn.glb`, aportado
por el usuario. Se conserva el archivo original: SHA-256
`668f51882979242cd2ce67b2b8e488b1d9106433a689842ff29819ddf5ef4ffe`.
La textura JPEG de 128 × 128 y sus `.import` se extraen al importar con Godot;
deben acompañar al GLB en Git. El modelo contiene 5,236 triángulos de origen.

`scripts/driving/CometVisual.gd` delega en el adaptador compartido
`ImportedCarVisual.gd` y adapta exclusivamente la presentación:

- Rota 180° sobre Y para orientar el frontal hacia -Z.
- Aplica escala uniforme 0.65 y desplazamiento `(0, -0.585, 0.13)` en el espacio
  visual, antes de la escala del vehículo existente. Así alinea los ejes delantero
  y trasero aproximadamente en Z -1.3 y +1.3. Las ruedas conservan sus posiciones
  laterales originales y un diámetro visual de 0.65 antes de la escala del coche.
- Reutiliza los pivotes de dirección y suspensión visual. Un portador común
  permite que las cuatro ruedas giren en el mismo sentido pese a sus rotaciones
  locales distintas en el GLB.
- Conserva los materiales y la textura originales. Asigna un material oscuro al
  soporte del alerón, cuya primitiva no trae material. La luz trasera recibe una
  copia independiente de su material para responder al freno sin afectar a otros
  coches. Continúan funcionando los emisores de turbo existentes.
- Marca las piezas de carrocería para el overlay BURST. El adaptador de VFX
  admite esa marca en el nodo, conservando el material multisuperficie del GLB.

`CarVisual.gd` recibe el perfil al construir la representación. `RetroCar.gd`
respeta los modelos importados de COMET, VECTOR y APEX (ver
[integración de los tres modelos](MODELOS_VEHICULOS.md)). `ArcadeCar.gd`
reconstruye únicamente los hijos visuales al aplicar
un perfil en reposo y conserva los nodos de luz añadidos por la iluminación del
mundo. No cambia las fórmulas de conducción, las estadísticas, la caja física,
las máscaras de colisión ni la cámara. El modelo se usa tanto por el jugador
como por los rivales COMET en carreras, a través del mismo código.

Para verlo: inicia el juego, selecciona **COMET** y entra al modo libre o a una
carrera. El aspecto original del archivo es oscuro; responde a la iluminación
neón de la ciudad. La silueta nueva es ligeramente más larga que la anterior,
pero se conserva la caja de colisión arcade existente. No se generan colisiones
desde la malla. La carrocería importada tiene varias superficies; el overlay
actual de BURST se aplica a la pieza completa, incluidos sus cristales.

## Verificación

Godot 4.7.2: importación sin errores. `tests/godot_comet_model.gd` verifica el
modelo en modo libre y carrera, los cuatro ejes/ruedas, aceleración, giro de
ruedas, dirección delantera, freno, binding BURST, cambios VECTOR/APEX/COMET,
conservación de luces, caja/configuración y modelos de los rivales: **29/29**.
La regresión del pasaporte `godot_phase_d4.gd` pasó **54/54**, incluyendo acceso
vial con los tres perfiles. Se revisaron capturas frontales y traseras en
1280 × 720, Compatibility. Los resultados locales quedan en
`.local/artifacts/comet_model_validation.json`, `comet_model.log`,
`comet_d4_regression.log` y `evidence/comet_*.png`.

```powershell
godot --headless --path . --editor --import --quit
godot --path . --script res://tests/godot_comet_model.gd -- --passport-test --capture
godot --headless --path . --script res://tests/godot_phase_d4.gd -- --passport-test
```

Las pruebas usan ajustes y progreso aislados. `--capture --diagnose` produce
además capturas ocultando piezas individuales para depuración. No se añaden
materiales descargados ni se atribuyen nombres/licencias no proporcionados.
El archivo se registra como recurso aportado por el usuario; no especifica
el nombre del autor ni las condiciones de distribución en sus metadatos.
