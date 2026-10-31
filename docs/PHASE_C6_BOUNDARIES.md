# Ampliaciones C2, A4 y A5 y límites montañosos

Revisión posterior vigente: [corrección del mar A1/A2/B1/A3 y retranqueo Centro–Sur](COAST_FIX.md). La conservación exacta del mar descrita en esta entrega inicial fue sustituida por esa petición del usuario.

Referencia: recorte del usuario del 31 de octubre de 2026. El contorno es una interpretación aproximada, no una delimitación topográfica. Se amplían el entrante oriental del centro y la franja oeste del corredor sur. Se conservan toda la zona anterior, el recorte sur, el origen métrico y el spawn. Área añadida: **2,1718 km²**, sin área retirada. Comparación: `map_extension_area.json`.

## Geografía y fuentes

`config/expansion_config.json` incorpora `block_polygons_lonlat`: polígonos por bloque dentro de sus envolventes de descarga. `expansion_regions.py` aplica la misma selección a calles, edificios, terreno, límites y manifiesto de streaming. Las cajas rectangulares siguen sirviendo para adquirir fuentes y consultar índices. No se introduce otra proyección.

Se reutiliza el extracto completo OSM C.5 y se agregan pequeñas teselas C2/A4/A5. Los XML originales, metadatos, fechas y SHA-256 permanecen en `data/raw`. La combinación conserva identificadores, versiones y topología dirigida. `source_base_selection` y `source_patch_bboxes` permiten reproducir esa selección sin descargar toda la ciudad.

El CEM4 local cubre las ampliaciones. Se mantiene la versión Overture `2026-10-21.0`. Su descarga suplementaria falló por un certificado TLS caducado; no se desactivó la verificación. La franja oeste fuera de su cobertura anterior usa huellas OSM verificadas y el relleno ficticio INEGI ya existente, etiquetado como tal. `overture_buildings_c6_boundary_selection.meta.json` distingue `bbox` real del origen y `selection_bbox` del mundo: no atribuye cobertura nueva a Overture. INEGI/DENUE reutilizan sus fuentes completas de localidad/estado.

## Mar conservado

`data/reference/sea_before_c6.geojson` conserva la geometría marítima anterior en coordenadas locales XZ. `preserved_sea_file` evita que la caja de selección mayor cambie la polygonización del litoral. `urban_geography.surfaces` aplica ese mar antes de comprobar solapes y particionar superficies. La diferencia entre ambos mares es **0 m²**. La altura del agua y el comportamiento físico marítimo anterior se conservan.

## Montañas ficticias

`fictional_boundary_mountains` está separado de la elevación real. `relief_limits.bake_mountains` genera una franja exterior irregular por sectores de 256 m. Las calles, techos, cimentaciones y muestras del DEM no se elevan para formar esa barrera.

El frente asciende aproximadamente 45 m en los primeros 6 m exteriores: supera los 42° máximos de suelo del coche. Cresta y anchura varían de forma determinista con las coordenadas; altura nominal 120 m y anchura máxima 220 m. Las caras se recortan contra el área transitable y contra un margen marítimo de 40 m. Son geometría ficticia de diseño del juego, no datos atribuidos a INEGI.

Cada sector contiene una sola geometría física: montaña terrestre o límite marítimo previo. `visible_triangles_count` distingue montaña visible y pared marítima con solo colisión. No se superponen paredes terrestres antiguas con el nuevo frente. `RoadBuilder` y el caché nativo utilizan los mismos vértices para físicas y visuales. `World` muestra el gestor de límites cuando el manifiesto declara montañas; se reutiliza el streaming. El piloto conserva sus límites aislados de prueba.

## Precisión del contacto vial

La regresión completa detectó un fotograma sin clasificar asfalto en la ruta hospitalaria, aunque el coche mantuvo suelo físico, sin choque ni recuperación. La instrumentación localizó un rayo exactamente sobre la arista X=144 m de dos caras contiguas. No era un hueco del terreno. La prueba específica reprodujo **41 fallos de rayo central en 123 muestras** de esa arista.

`ArcadeCar.road_hit` conserva el rayo central y, solo si falla, consulta una cruz de **1 mm**. Las 123 muestras aprueban con esa comprobación. No cambia el motor, frenado, gravedad, suspensión ni geometría vial, ni permite puentear huecos transitables. El controlador anterior queda archivado en `c6_baseline/ArcadeCar.gd`; `relief_migrations.json` vincula la modificación con pruebas actuales de pendientes y conducción plana.

## Reproducción

Con el entorno Python preparado y las fuentes incluidas:

```powershell
.\.venv-urban\Scripts\python.exe -B tools/prepare_extension_sources.py
.\.venv-urban\Scripts\python.exe -B tools/fetch_expansion_osm.py --offline
.\.venv-urban\Scripts\python.exe -B tools/expand_map.py
.\.venv-urban\Scripts\python.exe -B tools/build_relief.py --mode pilot
.\.venv-urban\Scripts\python.exe -B tools/build_relief.py --mode world
```

Después, ejecutar Godot con `--headless --path . --script tools/bake_relief_resources.gd -- --mode=pilot` y repetir con `--mode=world`. Agregar `--log-file <ruta absoluta del proyecto>` en entornos con perfil global restringido.

Para ajustar solo montañas sin volver a procesar calles, edificios ni terreno, ejecutar `tools/rebuild_boundary_mountains.py` y regenerar el caché nativo del mundo. Exige fuentes y alturas preparadas verificadas. `tools/rebuild_extension_geography.py` permite recalcular únicamente la geografía y sus referencias tras fijar el mar; una reconstrucción completa ya incorpora esa selección directamente.

## Pruebas y límites

- `map_extension_python_final.log`: 50 pruebas de datos y regresiones aprobadas.
- `map_extension_boundary_tests.log`: conservación del área, mar exacto, exclusión de agua/interior y determinismo.
- `phase_b7r_world_geometry.json`: alturas, geometrías, cachés nativos y costa.
- `map_extension_physics.json`: tres recorridos nuevos e impactos aéreos a 88 m/s contra tres montañas, sin recuperación que oculte escapes.
- `map_extension_world_final.log`: regresión de las cuatro rutas existentes tras corregir el contacto.
- `map_extension_seam_validation.json`: reproducción dirigida de la arista vial.
- `map_extension_summary.json`: resultados finales, costes geométricos y limitaciones.

Se conservan los registros del fallo inicial en `map_extension_world_regression.log` y `map_extension_world_trace.log`. No se ha reducido la exigencia del test.

Siguen vigentes las limitaciones geodésicas, pasos a distinto nivel y cimentaciones grandes de B.7-R. Las cimentaciones con dispersión superior a 6 m pasan de 20 a 25 y necesitan revisión manual. Se registra el coste geométrico; los tiempos headless concurrentes no son una comparación de FPS renderizados. Las barreras no protegen frente a teletransportes o modificaciones arbitrarias del controlador.

Capturas: `evidence/la_paz_boundary_extension.png` y `evidence/la_paz_boundary_extension_grid.png`. No se ha solicitado un nuevo commit ni push para esta ampliación.

Resultado final: 23,69 km de rutas anteriores y 12,24 km de rutas nuevas completados sin pérdidas de asfalto, apoyo, choques ni recuperaciones durante los recorridos. Las tres pruebas de impacto aéreo a 88 m/s se detienen ante la montaña sin recuperación. La geometría total pasa de 1.776.750 a 1.905.237 triángulos (+7,23%); el caché nativo pasa de 52,18 a 55,94 MB. La captura de detalle está en `evidence/la_paz_boundary_mountains_detail.png`.
