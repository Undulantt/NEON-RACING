> Actualización: Overture Places, DENUE y fachadas ampliadas ya están integrados. Estado actual y pruebas en [PHASE_B6_SOURCES.md](PHASE_B6_SOURCES.md). Los resultados siguientes conservan la entrega anterior como línea base.

# Fase B.6 — registro de implementación incremental

## Alcance y auditoría previa

Se leyó `docs/RECONSTRUCCIÓN_URBANO.md`, que contiene la especificación B.6. El archivo solicitado `docs/FASE_B6_RECONSTRUCCION_URBANA.md` no existe. Se inspeccionaron el generador offline, fuentes, proyección, geometría, colisiones, streaming y pruebas antes de editar.

Se reutilizan `build_urban_city.py`, `BuildingBuilder.gd` y `UrbanChunkManager.gd`. Se conservan 7.779 huellas (7.612 reales y 167 ficticias), 75 sectores y el controlador del coche. Origen 24.159,-110.3195; X este, Z sur; 1 unidad = 1 metro. Radios 650/850/180 m y sectores de 256 m sin cambios. No se modificaron las vías ni la configuración de conducción.

Al iniciar no existía repositorio `.git`. Se guardaron los archivos originales afectados y la evidencia de base en `docs/b6_baseline/`. Al terminar se inicializó Git para guardar un checkpoint local de la entrega validada; no se presenta como historial anterior ni se configuró un remoto. El README anterior permanece como documentación histórica.

## Plan ejecutado y progreso

1. **P0 auditoría/base:** Godot B5 PASS, F8, streaming y equivalencia ciudad activa/inactiva de 0 m y 0 m/s. Render estático inicial 1280×720: 120,20 FPS, p95 8,87 ms, 358 nodos y máximo 7 ms por sector.
2. **P0 datos:** 300 POI reales del XML OSM local, con hash y procedencia; 124 asociados por contención única, 176 pendientes de revisión, 15 candidatos a duplicado. Se conserva el registro completo; no se fusionan nombres parecidos automáticamente. Una construcción puede tener varios establecimientos.
3. **P0 apariencia:** ocho categorías soportadas; 118 edificios clasificados, 7.661 desconocidos. Colores, accesos/escaparates y bandas de fachada agrupados en mallas existentes. La geometría cosmética no entra en las colisiones. Se conservan atributos disponibles de Overture (class, subtype, names, level, num_floors); no se inventan alturas medidas.
4. **P0 overrides:** archivo independiente, razones/fuentes obligatorias, validación de tipos y detección de huérfanos. Soporta alturas, categoría, paleta, desactivación, prioridad, asociación POI y modelos locales con orientación/escala visual.
5. **P1 geografía:** 22 superficies visuales (21 cartográficas y suelo residual), incluida costa, agua y espacios abiertos. Agua derivada del sentido OSM y recorte de bbox: 2.805.558,04 m²; cero solapamiento de área con edificios. No se dibujan como terrenos los buffers ficticios de protección. La plataforma conserva su colisión. Su visual se sustituye por superficies disjuntas de tierra/agua/espacios y se excluye el asfalto para evitar interferencias de profundidad; no se introduce relieve.
6. **P1 lugares:** seis registros con ubicación respaldada por OSM: Museo de Arte BCS, Museo de Antropología e Historia, Catedral, Mercado Bravo, Mercado Francisco I. Madero y Centro Cultural. F9 muestra sus nombres. Las asociaciones ausentes no se fuerzan.
7. **P1 Catedral:** escena simplificada de dos torres con remates piramidales, basada en la monografía oficial MX-SC-DGSMPC-EM-03-001004. Se conserva la huella y ambas bases de torre están dentro de ella. Alturas de nave/torres/remates 10/18/21 m **ilustrativas y estimadas**, no levantadas. La colisión conserva la huella, con altura de nave. No se copiaron imágenes ni modelos externos.
8. **Validación:** pruebas geográficas, de overrides, patios, asociaciones ambiguas, orientación costera, colisión, render y determinismo. Resultados finales al pie.

## Arquitectura y formatos

- `tools/urban_enrichment.py`: normalización y asociación sobre la proyección existente. Contención única: confianza heurística 0,95. Proximidad hasta 8 m: solo revisión; margen de ambigüedad 3 m. No son probabilidades calibradas. Los polígonos POI usan un punto interior representativo, no una entrada inventada.
- `data/processed/urban/urban_enrichment.json`: POI, candidatos, fuentes, confianza, duplicados posibles, huérfanos y estadísticas.
- `tools/urban_geography.py`: triangula costa/espacios y produce `urban_geography.json` y `landmarks.json`. `tools/build_urban_geography.py` permite regenerar únicamente las superficies a partir de chunks y fuentes verificados; su resultado coincide con la generación completa.
- `scripts/world/UrbanGeography.gd`: una malla de superficies sin cuerpos físicos adicionales y etiquetas F9 con alcance 450 m. El manifiesto protege las nuevas capas con hashes.
- `config/urban_enrichment.json`: categorías, umbrales y altura estimada por piso.
- `tools/build_landmark_model.py`: reproduce la escena original simplificada a partir de la huella ya procesada. No aplica otra transformación geográfica.
- `scenes/landmarks/Cathedral.tscn`: modelo visual sustituible conservando identificación y colisión geográfica. Los modelos se cargan y descargan con su sector.
- `tests/benchmark_route_b6.gd`: mismo recorrido y controlador para B.5 equivalente y B.6. La referencia usa las mismas huellas desactivando adornos/costa y restaurando altura automática; no es un ejecutable histórico independiente.

## Correcciones manuales

Editar `config/urban_overrides.json` y regenerar. No editar fuentes crudas ni chunks a mano.

Cada entrada de `buildings` requiere `reason` y `source`. Campos admitidos: `height_m` (2,8–48 m), `category`, `palette_index` (0–5), `disabled`, `priority`, `model_path` (`res://...glb` o `.tscn` existente), `model_rotation_degrees`, `model_scale` (mayor de cero y hasta 10). El override inicial de Catedral identifica su referencia y la incertidumbre de dimensiones.

Cada entrada de `pois` requiere razón/fuente y `building_id` (o null). Los IDs/destinos ausentes se reportan como huérfanos. Los cambios se aplican después de la clasificación automática y sobreviven a la regeneración.

Un modelo debe ser visual y no contener CollisionObject3D. Su origen se sitúa en el promedio de vértices de la huella a nivel del suelo. Se conserva la colisión geográfica; una escena inválida mantiene el fallback procedural. No se certifican modelos externos arbitrarios: deben caber en la huella. Las transformaciones son del modelo, no desplazan el edificio geográfico. La corrección de posición de huellas aún no está soportada, pues necesita revalidar vías, exclusiones, vecinos y asociaciones.

## Reproducir

Desde la raíz en PowerShell:

```powershell
$p = '.\.venv-urban\Scripts\python.exe'
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
& $p tools/build_landmark_model.py
& $p tools/build_urban_city.py
& $p tools/build_urban_city.py --check-determinism
& $p tools/validate_urban_enrichment.py
& $p -B -m unittest discover -s tests -v
& $g --headless --path . --script tests/godot_phase_b6.gd
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b5.gd
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b.gd
& $g --path . --fixed-fps 60 --script tests/benchmark_route_b6.gd
& $g --path . --script tests/capture_phase_b6.gd
```

No se requiere Python ni red para jugar. F8 mantiene el control de ciudad; F9 muestra nombres de lugares; el resto de controles no cambia.

## Fuentes, límites y pendientes

- POI/costa: XML OSM existente, hash verificado, ODbL. Overture Buildings e INEGI conservan sus fuentes/licencias anteriores. Ver `CREDITS_AND_LICENSES.md`.
- Convención costera: [OSM Coastline processing](https://osmdata.openstreetmap.de/processing/coastline.html).
- Catedral: [monografía Secretaría de Cultura](https://sitiosymonumentos.cultura.gob.mx/iii-estudios-monograficos/nuestra-senora-de-la-paz-catedral/). La referencia arquitectónica histórica no certifica dimensiones actuales ni cada detalle.
- Overture Places y DENUE **no integrados**: se utilizó la fuente OSM local disponible. No se afirma haber intentado/obtenido esas descargas ni se presume su esquema. Quedan como fuentes complementarias pendientes.
- Microsoft ya figura entre las fuentes del snapshot Overture; no se duplicaron huellas descargándolo por separado.
- Cinco lugares mantienen representación por categoría/registro geográfico, sin reconstrucción arquitectónica específica. Dos no tienen asociación de edificio segura; se conserva el POI. No se fabrica una construcción para completar el inventario.
- La mayor parte de la ciudad permanece sin clasificación: falta evidencia, no geometría. No hay verificaciones de campo ni una fachada fotográfica por negocio.
- No se inició P2: sin altimetría, modelos detallados ni identidad neón definitiva.
- Entorno de ejecución restringido: el editor importa sin errores GDScript, pero hubo fallos al guardar preferencias/caché global. Un perfil APPDATA local resolvió la ruta de escritura para pruebas runtime; persistió un aviso de guardado seguro en editor y un aviso de inicialización de shader en una ejecución renderizada. Se revisan imágenes y resultados, sin ocultar esas advertencias.
- B.6 queda como **entrega incremental P0 y P1 básico**, no como cierre de todas las integraciones de fuentes y fidelidad arquitectónica descritas en la especificación.

## Reanudación y revisión visual

Tras la interrupción de la conversación se continuó desde la validación visual. La vista aérea inicial reveló z-fighting entre agua y plataforma. Se corrigió particionando el suelo visible, sin cambiar su colisión, y usando un near adecuado a la cámara aérea de prueba. Se verifican cobertura de suelo y ausencia de solapamientos entre superficies/asfalto, con tolerancia de área de 0,01 m².

Capturas reales revisadas: [costa](evidence/phase_b6_coast.png), [Catedral](evidence/phase_b6_cathedral.png). Son imágenes de Godot, no montajes. La vista general muestra únicamente los sectores cargados alrededor del punto de captura; no implica que se cargue toda la ciudad al mismo tiempo.

La prueba inicial de datos se ejecutó demasiado pronto y falló porque la regeneración aún no había producido el archivo de POI. Se repitió después de completarla: 28 pruebas Python aprobadas. La primera fixture de costa tenía invertida su expectativa de este/oeste; se corrigió conforme al convenio documentado y pasó. No se ocultaron esos fallos intermedios.

## Resultados finales verificados

- 28 pruebas Python: PASS. Validación geográfica B.6: PASS (22 superficies, cobertura completa, sin solapamientos superiores a 0,01 m²).
- Regeneración completa `--check-determinism`: PASS después de la corrección del suelo; manifiesto, chunks y auditoría idénticos.
- Godot B.6: PASS, fachada fuera de colisión, sustitución visual y Catedral. Godot B.5: PASS, F8, radios, carga/descarga y diferencia de movimiento 0 m / 0 m/s.
- Recorrido final renderizado: PASS en ambas configuraciones, 1.197,93 m de avance sobre ruta de 1.200,92 m, 14 cruces, cero frames sin apoyo, cero salidas del asfalto, cero contactos de pared y cero recuperaciones.

| Métrica | B.5 equivalente | B.6 final |
|---|---:|---:|
| FPS promedio | 119.986 | 119.970 |
| Tiempo medio (ms) | 8.334 | 8.335 |
| p95 (ms) | 8.630 | 8.631 |
| Máximo fotograma (ms) | 25.706 | 25.025 |
| Memoria estática máxima (MB decimales) | 98.748 | 100.147 |
| Nodos máximos | 435.000 | 448.000 |
| Carga máxima sector (ms) | 9.000 | 18.000 |

Cambio de tiempo medio: **0.0137 %**, dentro del objetivo de 15 %. Se registraron 7.314 fotogramas renderizados por pasada, viewport 1280×720, RTX 4060 Ti, Compatibility/OpenGL. La presentación limita la prueba a aproximadamente 120 FPS: no demuestra margen de GPU ni rendimiento en hardware inferior. Memoria es el contador estático de Godot, no RAM total del proceso ni VRAM; ambas pasadas comparten proceso y cachés. El pico de sector de 18 ms merece seguimiento aunque el tiempo medio no se degrade apreciablemente.

La ejecución final con perfil local limpio no emitió el aviso de shader observado con el perfil anterior. Las advertencias históricas de editor/perfil permanecen documentadas. No se realizó una sesión humana prolongada de teclado/ratón.

Informes: [datos](phase_b6_data_validation.json), [runtime](phase_b6_runtime.json), [recorrido y rendimiento](phase_b6_route_benchmark.json). Comparación al final del mismo recorrido: [referencia](evidence/phase_b6_route_b5_equivalent.png), [B.6](evidence/phase_b6_route_b6.png).

El checkpoint Git preserva bytes de datos, configuración y controlador incluidos en hashes mediante `.gitattributes`; una restauración no debe cambiar sus finales de línea. Los archivos originales respaldados también se conservan sin normalización.
