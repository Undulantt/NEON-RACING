# Corrección del mar y retranqueo Centro–Sur

Petición del usuario: A1, A2 y B1 deben ser mar ficticio; ajustar la parte costera de A3 conservando su parte urbana. La montaña del encuentro Centro–Sur debe quedar más hacia afuera. Esta revisión sustituye la conservación estricta del mar descrita en la entrega C.6 anterior.

## Implementación

- `tools/prepare_coast_fix.py` interpreta las casillas con el encuadre **anterior** de 2560×3840, norte arriba. El encuadre se guarda en `docs/coast_fix_baseline/relief_manifest.json`: los nombres de casillas no dependen de un zoom futuro.
- `data/reference/sea_c6_coastal_fix.geojson` une el mar anterior con las zonas autorizadas. Las propiedades marcan su carácter ficticio y contienen la máscara exacta de cambio. La costa fuera de esa máscara se conserva.
- La parte urbana de A3 se mantiene: la preparación rechaza cualquier máscara que inunde edificios. La nueva geometría también se comprueba contra las carreteras. La porción de tierra aislada de A2 deja de generar terreno y montañas.
- El mar visual se extiende fuera de la envolvente de adquisición GIS para llenar A1/A2/B1; no es solo un cambio del color de fondo. La superficie de agua conserva nivel y material y no incorpora un suelo transitable. El piloto aislado conserva su propia envolvente de agua.
- `local_boundary_outsets` configura un retranqueo máximo de **60 m**, centrado en XZ `[2285.29, 889.56]`, con transición de **400 m**. `relief_regions.apply_boundary_outsets` agrega terreno hacia afuera de forma gradual y conserva el área anterior. La montaña se genera sobre el nuevo contorno; su colisión se mueve con ella y no queda una pared invisible en el lugar anterior.
- Ese espacio nuevo usa el mismo DEM y triangulación que el terreno. No se limita a desplazar una malla dejando un hueco delante de ella. No cambia el motor, la gravedad, el freno ni los controles.
- La montaña se triangula en bandas exteriores de distancia, recortadas por booleanas y divididas en celdas de 16 m. El frente de 6 m conserva su pendiente infranqueable. Este método reemplaza la extrusión independiente de vértices, que cruzaba caras en esquinas cóncavas. Una prueba de unión cóncava comprueba que la suma de áreas de las caras coincide con su unión, sin solapamientos.
- La preparación de alturas calcula una sola vez el polígono de soporte, en vez de repetir su buffer por muestra sin datos. Es una optimización offline y conserva las consultas geográficas.
- Los sectores se escriben mediante reemplazo atómico y reintentos ante bloqueos breves de Windows; los contenidos idénticos se conservan sin reescribir. Se verificó que un bloqueo temporal no trunca la copia anterior.

## Regeneración local

```powershell
.\.venv-urban\Scripts\python.exe -B tools/prepare_coast_fix.py
.\.venv-urban\Scripts\python.exe -B tools/rebuild_extension_geography.py
.\.venv-urban\Scripts\python.exe -B tools/build_expansion_routes.py
.\.venv-urban\Scripts\python.exe -B tools/build_relief.py --mode pilot
.\.venv-urban\Scripts\python.exe -B tools/build_relief.py --mode world
```

Regenerar después los cachés Godot con `tools/bake_relief_resources.gd`, primero `--mode=pilot` y después `--mode=world`. No se requieren fuentes ni descargas nuevas. Una reconstrucción urbana completa también consume la nueva referencia marítima desde `map_config.json`.

## Evidencia

- `coast_fix_python_final.log`: 54 regresiones de datos, cuadrantes y escritura segura.
- `coast_fix_boundary_tests.log`: cuatro pruebas dirigidas después del cambio de triangulación, incluida la unión cóncava sin caras solapadas.
- `coast_fix_physics.json`: ausencia de terreno en A2, retirada de la colisión anterior, nueva montaña y suelo continuo delante de ella.
- `coast_fix_world_regression.log`: cuatro rutas de la ciudad.
- `coast_fix_extension_regression.log`: rutas de las ampliaciones y pruebas de barreras a 88 m/s.
- `phase_b7r_world_geometry.json`: continuidad geométrica, alturas, costa y cachés verificados.
- `coast_fix_summary.json`: resultados finales y límites de verificación.

Capturas: `evidence/la_paz_coast_fix.png`, `evidence/la_paz_coast_fix_grid.png` y `evidence/la_paz_core_south_setback.png`.

La geometría marítima de esta revisión es una decisión explícita de diseño del juego. No representa una corrección geográfica atribuible a OSM o INEGI. Se conservan las limitaciones geodésicas y cimentaciones pendientes de B.7-R/C.6. Los registros C.6 anteriores son históricos; la evidencia vigente de estos dos ajustes es la de esta revisión.

El retranqueo se mide perpendicularmente al contorno original. La prueba obtiene 55,04 m de separación normal en el punto examinado; el recorrido diagonal desde la esquina hasta el nuevo borde mide 93,80 m y alcanza la colisión a 100,32 m. Se comprobó que el borde viejo está despejado y que hay suelo antes del frente nuevo. Cambiar el retranqueo requiere regenerar el terreno; cambiar solo el aspecto de la franja permite usar `rebuild_boundary_mountains.py` sin reprocesar la ciudad.
