# Fase B.5 — ciudad híbrida del sector de La Paz

Implementada el **24 de octubre de 2026**. Incluye B.5.1 (datos reales), B.5.2 (relleno ficticio conservador) y B.5.3 (sectores Godot). Permanece en el mismo sector: no se amplió el mapa, no se inició la fase C de turbo/derrape y no se modificó el controlador del coche.

## Resultado

| Fuente de los volúmenes aceptados | Cantidad |
|---|---:|
| Overture Maps | 7,387 |
| Huellas OSM anteriores, con prioridad sobre duplicados | 225 |
| Construcciones **ficticias**, dentro de manzanas INEGI elegibles | 167 |
| Total | **7,779** |

Hay **7,612 volúmenes derivados de huellas reales de las fuentes**, no comprobados edificio por edificio en campo. Overture incluye geometrías inferidas por ML; que una huella aparezca en la fuente no garantiza precisión de levantamiento ni identificación del inmueble. Los volúmenes genéricos preservan ubicación y contorno dentro de las modificaciones documentadas; las fachadas no son reproducciones arquitectónicas.

Se descargaron 8,033 entidades Overture; se procesaron 321 manzanas INEGI que intersectan el sector. 183 cumplieron criterios de elegibilidad, pero solo 89 recibieron relleno, con un total de 167 edificios ficticios. El resto conserva sus espacios libres.

**Todas las 7,779 alturas están marcadas como estimadas.** No apareció `height` utilizable en este recorte. Dos volúmenes aceptados utilizan `num_floors × 3.1 m` y los otros 7,610 volúmenes reales utilizan una altura determinista de 1–3 pisos. Los 167 ficticios también usan 1–3 pisos. Overture descargó tres entidades con pisos, pero una no se incorporó tras los filtros. No se presentan estas alturas como mediciones.

## B.5.1 — adquisición, procedencia y coordenadas

BBox vial/urbana `(sur,oeste,norte,este)` = **(24.148,-110.334,24.170,-110.305)**. Origen métrico **(24.159,-110.3195)**, radio terrestre 6,371,000 m; +X este, -Z norte, +Y arriba; **1 unidad Godot = 1 m**. La prueba compara la proyección nueva con `gps_to_local` de fase A.

| Fuente | Archivo original | Versión/fecha declarada |
|---|---|---|
| Overture Maps | `data/raw/overture_buildings_20261024T220936Z.geojson` | Release **2026-10-21.0**, extracción 24/10/2026 15:09:39 UTC−07 |
| INEGI | `data/raw/inegi_blocks_20261024T220934Z.geojson` | Fuente vectorial: **Marco Geoestadístico, diciembre de 2025**; datos de población/vivienda: Censo 2020; extracción 15:09:40 UTC−07 |
| OSM para espacios libres | `data/raw/osm_map_20261024T221536Z.osm` | Extracto XML de la API oficial, extracción 15:15:39 UTC−07; no se afirma una fecha base homogénea |
| Vías existentes | `data/processed/la_paz_map.json` y su snapshot original | Base OSM de julio de 2026, sin cambios en esta fase |

Todos los archivos tienen SHA-256, URL/consulta/CLI y fecha UTC en metadatos separados. Se fija la versión Overture en `config/urban_config.json`; la caché exige esa release. La caché de INEGI exige también el endpoint correspondiente a la localidad. No se vuelven a descargar datos salvo ausencia de caché válida o `--refresh`.

Overture se adquirió con el cliente oficial `overturemaps` por bbox, sin descargar el planeta. Dataset de origen declarado en las entidades: Microsoft ML Buildings, Google Open Buildings y OpenStreetMap; se conservan `sources` por edificio, con confianza/fecha cuando la fuente los aporta.

INEGI se adquirió mediante el [servicio documentado de manzanas](https://www.inegi.org.mx/servicios/catalogounico.html), endpoint `https://gaia.inegi.org.mx/wscatgeo/v2/geo/mza/03/003/0001`. El servicio devuelve 5,796 manzanas de toda la localidad; solo se normalizan las 321 pertinentes al sector. Las geometrías declaran **EPSG:6365, Mexico ITRF2008**, coordenadas geográficas. Se usa `pyproj.Transformer(..., always_xy=True)` hacia EPSG:4326 y luego la proyección métrica del juego. La transformación publicada declara **1 m de exactitud**, sin prometer mayor precisión; su nombre y exactitud quedan en la auditoría.

La consulta de protección a Overpass Private.coffee agotó el tiempo; Kumi devolvió 502; la alternativa Mail.ru falló la verificación TLS. No se desactivó TLS. El extracto pequeño de la API OSM funcionó: **1,797,590 bytes** de XML original conservados. Se extrajeron 111 elementos etiquetados a un JSON normalizado separado; 109 generaron geometrías válidas de protección. No faltaron miembros de relaciones en ese extracto. El original XML sigue intacto y su hash se comprueba además del JSON normalizado.

Referencias: [cliente Overture](https://docs.overturemaps.org/getting-data/overturemaps-py/), [esquema de edificios](https://docs.overturemaps.org/schema/v1.18.0/reference/buildings/building/), [licencias Overture](https://docs.overturemaps.org/attribution/).

## B.5.2 — reglas del generador

### Edificios de fuentes reales

1. Se priorizan las huellas OSM ya verificadas para evitar duplicarlas con Overture.
2. Se exige polígono válido, dentro de la bbox y área de 12–25,000 m². Se excluyen los subterráneos.
3. Se conserva la calzada de fase A exactamente como fue triangulada. Se aplica **1.25 m de separación adicional** para las nuevas fachadas.
4. No se colocan volúmenes dentro de los espacios protegidos disponibles en OSM: parques, jardines, áreas deportivas, playas, agua/humedales, zonas verdes, cementerios, terrenos agrícolas, estacionamientos, escuelas y otros recintos, plazas y corredores peatonales/ciclistas. Una etiqueta puntual sin contorno solo aporta un radio conservador de 25 m; no se inventa el límite del recinto.
5. Simplificación de contorno de **0.12 m**, conservando topología. Se puede recortar un conflicto menor con carretera o un volumen previo; si quedaría menos del **85% del área**, se omite. Nunca se ensancha o desplaza la carretera para acomodar un edificio.
6. Se guardan área original, fracción retenida y bandera `geometry_adjusted`. **1,152 volúmenes reales** tienen alguna simplificación/ajuste de área superior a 0.01 m²; los originales siguen disponibles. No se afirma que cada malla sea una copia geométrica sin modificaciones.
7. Se preservan huecos de patios, se triangula el techo con restricciones y se extruyen paredes exteriores e interiores. Hay dos volúmenes con huecos en el resultado.

Auditoría de 657 exclusiones: 226 duplicados/solapamientos, 187 fuera de bbox, 106 sobre espacios protegidos, 74 por tamaño y 64 por conflicto que eliminaría más del 15% de la huella.

### Relleno ficticio

Una manzana INEGI es una unidad geoestadística, **no un lote edificable ni un permiso de construcción**. Solo se permite relleno si:

- Es de tipo **Típica**, está completa dentro de bbox y tiene tamaño razonable.
- Tiene evidencia combinada de ocupación: al menos 8% de cobertura por huellas reales aceptadas y viviendas habitadas en la información censal disponible.
- No intersecta protección OSM ni guardas costeras adicionales: 100 m de costa cartografiada y 50 m alrededor de Álvaro Obregón, utilizadas exclusivamente para restringir relleno ficticio.
- El nuevo volumen queda completamente en el interior seguro de la manzana, con retiro de 5 m y separaciones respecto de vías, otros edificios y espacios libres.
- Está a no más de 38 m de una calzada; máximo 12 ficticios por manzana y 1,000 en total, aunque el resultado actual solo necesitó 167.

Se alinean rectángulos low-poly con la orientación de la manzana, usando semilla fija. Cada uno tiene `source_kind="fictional"`, `fictional=true`, ID `fiction:inegi:...`, manzana de referencia y altura estimada. **INEGI aporta la restricción espacial, no esa huella inventada.** No se completa un espacio solo por estar vacío.

Se guardan los polígonos normalizados, áreas seguras, exclusiones y motivos en `placement_audit.json`. Los filtros conservadores no sustituyen revisión de campo y pueden omitir lugares donde sí existen edificios. Se prefirió omitir antes que ocupar áreas sin justificación.

## B.5.3 — integración y sectores

Los edificios están en **75 JSON de sector de 256 m**, aproximadamente 11.9 MB sumados, con manifiesto de conteos, bbox y hashes. El juego abre el manifiesto pequeño y solo lee/instancia los sectores próximos al coche. No usa Python ni red al jugar.

`UrbanChunkManager.gd` carga geometría hasta 650 m y la descarga después de 850 m para evitar cambios repetidos en los bordes. Se prepara el entorno inmediato al aparecer y después se crea como máximo un sector por frame. Cada sector combina los volúmenes en mallas con colores de vértice; no hay ventanas ni texturas complejas en la nueva ciudad. Los huecos de patios siguen vacíos.

Se preparan colisiones solo para edificios a **38 m o menos de la calzada** (7,369 volúmenes potenciales). De esos, solo se activan los cuerpos de sectores que estén a 180 m o menos del coche. Se conservan las capas físicas y el suelo/límites de fase B. Los interiores profundos y alejados de vías no son un escenario de colisión detallado en este prototipo.

**F8 activa/desactiva la ciudad**, tanto sus mallas como las colisiones de edificios; no quita asfalto, suelo ni límites. Para reactivarla hay que estar completamente sobre una posición segura de asfalto: así no aparece una pared dentro del coche tras conducir con la ciudad desactivada. El HUD muestra el estado y sectores activos. R sigue recuperando el vehículo.

`--legacy-city` abre explícitamente los 239 edificios de fase B para comparación; `--no-city` inicia con la nueva ciudad desactivada. No hay sustitución silenciosa de Overture: si falta o está desactualizado el manifiesto, se indica qué herramienta debe ejecutarse. Cada sector se comprueba por hash al cargarlo.

## Archivos y esquema

```text
config/urban_config.json                 fuentes y reglas configurables
tools/requirements-urban.txt            dependencias offline separadas
tools/fetch_urban_sources.py            tres adquisiciones con caché verificable
tools/build_urban_city.py               conversión y relleno determinista
tools/validate_urban_city.py            validación integral de datos y geometría
data/raw/overture_buildings_*.geojson   recorte original del cliente oficial
data/raw/inegi_blocks_*.geojson         GeoJSON original INEGI
data/raw/osm_map_*.osm                  XML OSM original
data/raw/osm_protected_*.json           derivado normalizado del XML
data/processed/urban/city_manifest.json manifiesto, fuentes, configuración, hashes
data/processed/urban/chunks/*.json      edificios y techos por sector
data/processed/urban/placement_audit.json reglas y máscaras geográficas auditables
scripts/world/UrbanChunkManager.gd      streaming y depuración F8
scripts/world/BuildingBuilder.gd        extrusión, patios, color y colisión opcional
scripts/world/World.gd                  integración con el proyecto existente
tests/test_urban.py                     pruebas de datos y CRS
tests/godot_phase_b5.gd                 equivalencia de manejo y streaming
tests/benchmark_phase_b5.gd             comparación del render
```

Esquema urbano **v1**:

- Manifiesto: versión, metros/origen/bbox, SHA-256 vial, fuentes con hashes, configuración, lista de sectores, estadísticas y hashes de los archivos de conducción/vías que deben conservarse.
- Sector: `schema_version`, `id`, `chunk_cell`, `detail_windows=false`, `buildings[]`.
- Edificio: `id`, `source_kind`, `fictional`, `source_id` cuando existe, anillo exterior `footprint_xz`, patios `holes_xz`, triángulos de techo, altura y su procedencia, paleta, `collision_enabled` por proximidad vial; las huellas reales añaden `sources`, área y datos de ajuste; los ficticios añaden `inegi_block_id` y nota explícita.
- Auditoría: máscaras protegidas, guarda costera, manzanas normalizadas y áreas seguras, motivos de exclusión y transformación CRS.

## Pruebas y evidencia real

Entorno: **Godot 4.7.2.stable.official.ed1daf0bf**, Python **3.13.7**, Shapely **2.1.2**, overturemaps **1.0.2**, PyProj **3.8.0**. Adquisición/conversión en `.venv-urban`; el juego no depende de esas bibliotecas. NVIDIA RTX 4060 Ti, OpenGL Compatibility, driver NVIDIA 610.88.

- **22 pruebas Python** en el entorno urbano: las 16 de fases anteriores y 6 urbanas. Comprueban fuentes/hashes, proyección, CRS, techo/patios, separación, ausencia de duplicados, condiciones del relleno y caché ligada a release/endpoint.
- `validate_urban_city.py`: pasó para 7,779 volúmenes, 34,038 triángulos de techo, cero área de intrusión detectada en calzada/protección, alturas explícitas y archivos base intactos. Las tolerancias numéricas se expresan en el código; no equivalen a exactitud de campo.
- Regeneración `--check-determinism`: mismo manifiesto, hashes de los 75 sectores y auditoría. Se ejecutó una segunda conversión completa desde los snapshots locales.
- Importación Godot sin errores de scripts/escenas.
- Se reutilizó la batería del **coche real de fase B** con la ciudad B.5: avance 31.9983 m/s, reversa -7 m/s, frenado 87 frames, derrape, teclas, recuperación, fachadas, cámara, límites y pausa aprobados.
- Ruta técnica de **1,200.919 m**, criterio de llegada a menos de 3 m del extremo: progreso final headless **1,197.937 m**, renderizado **1,197.920 m**, **14 cruces**, cero frames fuera de asfalto/sin apoyo, cero contactos de pared y cero recuperaciones durante la ruta.
- Prueba ciudad activada/desactivada sobre el mismo tramo: **0.0 m de diferencia de posición y 0.0 m/s de velocidad**. Los hashes de `ArcadeCar.gd`, `driving_config.json`, `la_paz_map.json` y el entorno original no cambiaron.
- F8 probado con eventos físicos dentro del motor. Se comprobó visibilidad y desactivación de máscaras de edificio, reactivación segura, carga/descarga al cambiar de zona y colisiones próximas/lejanías.
- En spawn: **17/75 sectores y 1,514 edificios** instanciados, no toda la ciudad. En la ruta se alcanzó un máximo de **36 sectores**, con 106 cargas y 89 descargas contando los casos de recolocación de pruebas. Sin sectores fallidos. Construcción máxima por sector: **11 ms headless**, **8 ms en la prueba renderizada**, según esas ejecuciones.

Informes: [datos](phase_b5_data_validation.json), [conducción](phase_b5_driving_validation.json), [conducción renderizada](phase_b5_driving_validation_render.json), [streaming y F8](phase_b5_runtime_validation.json), [render](phase_b5_benchmark.json). El informe previo del coche se conservó en `baseline_phase_b_validation.json`.

Capturas del viewport real revisadas: [ciudad anterior](evidence/phase_b5_legacy.png), [ciudad nueva en spawn](evidence/phase_b5_urban.png), [ciudad desactivada](evidence/phase_b5_urban_hidden.png), [16 de Septiembre](evidence/phase_b5_drive_0.png), [Aquiles Serdán](evidence/phase_b5_drive_1.png), [Melchor Ocampo](evidence/phase_b5_drive_2.png). Las imágenes de comparación preceden al pequeño indicador permanente de sectores y a la última atribución completa; las de recorrido ya muestran la interfaz final.

### Rendimiento comparado

Misma cámara de spawn, **viewport de render fijo 1280×720**, 2 s de calentamiento + 5 s de muestra por modo, misma ejecución/equipo. La fijación del viewport evita el problema anterior de DPI/tamaño de ventana.

| Modo | FPS promedio | p95 frame | Draw calls | Primitivas visibles | Nodos |
|---|---:|---:|---:|---:|---:|
| Fase B anterior | 120.47 | 8.68 ms | 163 | ~14,946 | 411 |
| B.5 activada | 120.00 | 8.83 ms | 170 | 30,644 | 357 |
| B.5 desactivada | 119.99 | 8.68 ms | 153 | 9,700 | 305 |

Relación FPS B.5/anterior: **0.9961**. La muestra no muestra perjuicio grave en esta escena. Está cerca del límite de presentación de la pantalla, por lo que no demuestra cuánto margen libre tiene la GPU. No es prueba de 1080p, rendimiento mínimo de hardware ni benchmark prolongado de conducción. El recorrido completo sí se ejecutó con render, pero sin prometer FPS sostenidos en toda la zona.

## Reproducir

Desde la raíz, con PowerShell:

```powershell
python -m venv .venv-urban
.\.venv-urban\Scripts\python.exe -m pip install -r tools/requirements-urban.txt
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py overture
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py inegi
.\.venv-urban\Scripts\python.exe tools/fetch_urban_sources.py protected
.\.venv-urban\Scripts\python.exe tools/build_urban_city.py
.\.venv-urban\Scripts\python.exe tools/validate_urban_city.py
.\.venv-urban\Scripts\python.exe tools/build_urban_city.py --check-determinism
.\.venv-urban\Scripts\python.exe -B -m unittest discover -s tests -v
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
& $g --headless --path . --editor --quit
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b.gd
& $g --headless --path . --fixed-fps 60 --script tests/godot_phase_b5.gd
& $g --path . --script tests/benchmark_phase_b5.gd
& $g --path . --fixed-fps 60 --script tests/godot_phase_b.gd -- --visual-test
& $g --path .
```

Para comparar manualmente el entorno anterior: `& $g --path . -- --legacy-city`. Para iniciar sin ciudad: `& $g --path . -- --no-city`. Los datos originales de vías y el entorno fase B ya están incluidos; no necesitas refrescarlos para generar B.5. Si los cambias intencionalmente, regenera primero el entorno base y luego la ciudad urbana.

## Límites y trabajo posterior

- No se añadieron texturas complejas, neón, turbo, nueva física de derrape, rivales ni carrera. La premisa arcade y la nueva fase C permanecen pendientes.
- Precisión y cobertura dependen de Overture/OSM/INEGI y de fechas diferentes; no se verificó cada edificio con fotografía o en campo. Las alturas son estimadas, las fachadas genéricas y el relleno ficticio está identificado.
- La máscara de espacios libres conserva los identificados en las fuentes y añade filtros conservadores; no es un inventario completo de usos del suelo. Zonas inciertas se omiten cuando fallan los criterios, pero una manzana urbanizada tampoco garantiza la situación real de cada lote.
- El suelo sigue siendo una plataforma plana de seguridad, no tierra/costa cartográfica. Los edificios interiores alejados de vías tienen colisión simplificada o desactivada según la política documentada.
- Se revisaron capturas reales y se ejecutaron entradas en Godot. No se afirma una sesión humana prolongada de recorrido ni una desconexión física de la red de Windows; el runtime no contiene adquisición de red.
- Próximo paso: prueba humana del sector denso y ajuste de radios si el equipo lo requiere. Después puede continuarse, con autorización, a turbo y derrape de la nueva fase C.
