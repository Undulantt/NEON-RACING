# Fase B.6 — enriquecimiento urbano

Implementación y registro: [docs/PHASE_B6.md](docs/PHASE_B6.md). Conserva conducción, vías y 7.779 huellas; incorpora 5.836 registros POI (OSM, Overture Places y DENUE), con 385 edificios clasificados, categorías, fachadas, overrides, costa, espacios abiertos y seis registros de lugares. La Catedral incorpora una silueta simplificada con dimensiones estimadas. **F9** muestra nombres de lugares; **F8** conserva el control de ciudad.

Regeneración: `tools/build_urban_city.py` con `.venv-urban`. Validación adicional: `tools/validate_urban_enrichment.py` y `tests/godot_phase_b6.gd`. Integración de fuentes y verificación: [continuación B.6](docs/PHASE_B6_SOURCES.md).

El texto siguiente conserva la documentación histórica B.5.

---

# La Paz After Dark — Fase B.5: ciudad híbrida

Prototipo Godot 3D sobre calles reales de La Paz, B.C.S. La conducción libre de fase B se conserva y el escenario ahora contiene **7,779 volúmenes**: 7,387 de Overture, 225 de huellas OSM y **167 ficticios** colocados conservadoramente dentro de manzanas INEGI. Las alturas están marcadas como estimadas.

La ciudad se carga por **75 sectores de 256 m**. **F8** activa/desactiva edificios y sus colisiones, conservando calles, suelo y límites. Para reactivarla vuelve completamente al asfalto. El HUD indica el estado y los sectores instanciados. Los controles del coche siguen iguales.

Documentación actual y pruebas: [docs/PHASE_B5.md](docs/PHASE_B5.md). Registro histórico de la conducción base: [docs/PHASE_B.md](docs/PHASE_B.md). No se inició la nueva fase C de turbo/derrape ni se implementaron carreras.

## Regenerar y probar la ciudad B.5

El juego funciona con datos locales ya incluidos. Para regenerar la ciudad se utiliza un entorno separado; Python 3.13.7, Shapely 2.1.2, overturemaps 1.0.2 y PyProj 3.8.0 fueron verificados:

```powershell
python -m venv .venv-urban
.\.venv-urban\Scripts\python.exe -m pip install -r tools/requirements-urban.txt
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py overture
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py inegi
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py protected
.\.venv-urban\Scripts\python.exe tools/build_urban_city.py
.\.venv-urban\Scripts\python.exe tools/validate_urban_city.py
.\.venv-urban\Scripts\python.exe -B -m unittest discover -s tests -v
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b5.gd
& $g --path .
```

Las tres fuentes tienen caché, hashes y procedencia. Overture está fijado a release **2026-10-21.0**; INEGI declara **Marco Geoestadístico de diciembre de 2025**. El coche, sus parámetros y las carreteras conservan sus hashes originales. El generador no rellena espacios sin las fuentes de protección y la evidencia de ocupación requeridas.

Para comparar la fase B anterior: `& $g --path . -- --legacy-city`. Para reproducir la comparación de render con viewport fijo: `& $g --path . --script tests/benchmark_phase_b5.gd`.

Archivos nuevos principales: `config/urban_config.json`, `tools/fetch_urban_sources.py`, `tools/build_urban_city.py`, `tools/validate_urban_city.py`, `data/processed/urban/city_manifest.json`, `data/processed/urban/chunks/`, `scripts/world/UrbanChunkManager.gd` y `tests/godot_phase_b5.gd`.

## Abrir y jugar

Abre `project.godot` con Godot **4.7.2.stable.official.ed1daf0bf** y pulsa **F5**. El coche aparece en Paseo Álvaro Obregón. El juego carga los JSON locales: **no necesita Internet ni Python** para jugar.

Desde PowerShell, situado en la raíz de este proyecto:

```powershell
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
& $g --path .
```

Adapta únicamente la ruta del ejecutable si mueves el proyecto.

| Acción | Tecla |
|---|---|
| Acelerar | W / flecha arriba |
| Frenar y después reversa | S / flecha abajo |
| Girar | A, D / flechas izquierda, derecha |
| Freno de mano | Espacio |
| Recuperar en última posición segura | R |
| Pausa y continuar | Esc |
| Inspección aérea / volver al coche | C |
| Activar/desactivar ciudad | F8 |
| Información sobre interacción | E |

La pausa ofrece continuar, recuperar y volver al menú. El menú permite continuar, conducir desde el punto inicial o salir. La cámara aérea detiene el coche. El freno de mano aumenta el deslizamiento lateral. El coche no gira estando detenido. La superficie fuera del asfalto reduce la velocidad máxima a 43.2 km/h.

## Herramientas base de fases A/B

Verificado con Python **3.13.7** y **Shapely 2.1.2**. Son necesarios solo para regeneración. No hay otras dependencias obligatorias de conversión.

```powershell
python -m pip install -r tools/requirements.txt
python tools/fetch_osm.py --config config/map_config.json
python tools/build_map.py --config config/map_config.json
python tools/fetch_buildings.py
python tools/build_environment.py
python tools/validate_map.py --input data/processed/la_paz_map.json
python -B -m unittest discover -s tests -v
& $g --headless --path . --editor --quit
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_a.gd
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b.gd
```

Estos comandos regeneran la base histórica: después ejecuta `tools/build_urban_city.py` con el entorno urbano antes de abrir B.5. Las descargas reutilizan caché verificada salvo `--refresh`. El JSON del entorno está ligado al SHA-256 del mapa: si regeneras carreteras, regenera también el entorno. No edites el snapshot crudo. Los errores de descarga no se sustituyen por datos ficticios.

Para repetir el recorrido de prueba con render y capturas (unos 2–3 minutos si hay sincronización vertical):

```powershell
& $g --path . --fixed-fps 60 --script tests/godot_phase_b.gd -- --visual-test
& $g --path . -- --capture=res://docs/evidence/phase_b_spawn.png
& $g --path . -- --aerial --capture=res://docs/evidence/phase_b_aerial.png
& $g --path . --script tests/benchmark_phase_b.gd
```

El benchmark guarda dimensiones **reales** de textura. El gestor de ventanas puede cambiar el tamaño solicitado; no asumir 1080p sin leer el informe.

La fase A original permanece disponible, con su plataforma sin colisión y cámara de inspección:

```powershell
& $g --path . res://scenes/PhaseA.tscn
```

## Archivos principales

```text
project.godot                           escena principal e InputMap persistente
config/driving_config.json             parámetros ajustables del coche
scenes/Main.tscn                        conducción libre de fase B
scenes/PhaseA.tscn                      inspección aislada de carreteras
scenes/cars/PlayerCar.tscn              automóvil del jugador
scripts/driving/ArcadeCar.gd            física, controles y recuperación
scripts/driving/CarVisual.gd            modelo procedural original
scripts/driving/FollowCamera.gd         cámara con SpringArm y colisión
scripts/ui/DrivingHUD.gd                velocidad, pausa y menú
scripts/world/World.gd                  integración de la fase B
scripts/world/BuildingBuilder.gd        fachadas, colisiones, suelo y límites
scripts/world/PhaseAWorld.gd            escena de carretera previa aislada
scripts/world/RoadBuilder.gd            mallas y colisiones viales compartidas
tools/fetch_osm.py, build_map.py         adquisición y conversión vial
tools/fetch_buildings.py                adquisición separada de edificios
tools/build_environment.py              filtrado, extrusión y ruta técnica
data/raw/                              snapshots originales y metadatos
data/processed/la_paz_map.json          mapa vial en metros
data/processed/la_paz_environment.json  huellas, alturas, spawn y límites
tests/test_map.py                       12 pruebas originales
tests/test_environment.py               4 pruebas de entorno auténtico
tests/godot_phase_a.gd                  regresión de calzada sin suelo auxiliar
tests/godot_phase_b.gd                  integración del coche real
tests/benchmark_phase_b.gd              muestra breve del render
docs/PHASE_B.md                         decisiones, pruebas y limitaciones
docs/phase_b_validation.json            último informe headless
docs/phase_b_validation_render.json     informe de recorrido renderizado
docs/phase_b_benchmark.json             muestra de rendimiento
docs/evidence/                         capturas reales de Godot
CREDITS_AND_LICENSES.md                 atribuciones y licencias
```

## Procedencia y límites

© OpenStreetMap contributors · [ODbL](https://www.openstreetmap.org/copyright). Bbox final `(sur,oeste,norte,este)` = **(24.148,-110.334,24.170,-110.305)**, origen **24.159,-110.3195**, 1 unidad = 1 metro. Snapshot vial descargado el 23/10/2026 a las 22:35 UTC−07, base OSM 15/07/2026. Snapshot de edificios descargado el 23/10/2026 a las 23:29 UTC−07, base OSM 01/06/2026. Son dos snapshots de fechas base diferentes; no representan un levantamiento actualizado a octubre.

Carreteras planas y anchos estimados cuando falta información OSM. Edificios con huellas reales pero alturas estimadas/estilizadas y fachadas genéricas. La plataforma de seguridad y las barreras son elementos del prototipo, **no terreno ni costa cartográficos**. No hay mar, edificios emblemáticos fieles, tráfico, carrera ni IA rival.

Pruebas automáticas y recorrido renderizado aprobados. La prueba manual de escritorio quedó pendiente porque la herramienta de control capturó otra ventana; no se enviaron teclas a un destino incierto. El InputMap sí se probó con eventos físicos dentro del motor. Consulta [docs/PHASE_B.md](docs/PHASE_B.md) para resultados y alcance exactos.

## Pruebas actuales B.5

Datos geométricos y fuentes validados, **22 pruebas Python**, recorrido de coche de ~1.2 km/14 cruces sin pérdida de suelo, streaming/F8 y equivalencia de manejo con ciudad activa/desactivada aprobados. Muestra estática a render fijo 1280×720: 120 FPS aproximados tanto con ciudad anterior como nueva en RTX 4060 Ti; no es garantía de rendimiento general.

Capturas actuales: [Aquiles Serdán](docs/evidence/phase_b5_drive_1.png), [Melchor Ocampo](docs/evidence/phase_b5_drive_2.png). Los registros anteriores se conservan como historial; la documentación vigente de ciudad es PHASE_B5.md.
