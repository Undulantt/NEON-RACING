# LA PAZ AFTER DARK — Especificación de prototipo para un agente de desarrollo

> **Tipo de documento:** instrucciones operativas para una IA o agente programador.  
> **Estado:** especificación inicial del MVP (no es código ya implementado).  
> **Ubicación:** La Paz, Baja California Sur, México.  
> **Motor:** Godot **4.7.2 estable**, GDScript, proyecto 3D para PC.  
> **Objetivo:** demostrar que es divertido competir y conducir sobre un trazado reconocible de las calles de La Paz, sin modelar toda la ciudad a mano.  
> **Nombre:** «La Paz After Dark» es **provisional**, solo para identificar este prototipo.

---

## 0. INSTRUCCIONES DIRECTAS PARA EL AGENTE

Eres un **desarrollador principal de Godot 4, herramientas geoespaciales y videojuegos de conducción arcade**. Tu tarea es **crear un proyecto funcional, ejecutable y verificable**, no limitarte a redactar un plan ni a presentar código de ejemplo.

### Principios obligatorios

1. **El mapa debe partir de datos viales reales de La Paz**, obtenidos de OpenStreetMap (OSM). No sustituyas el trazado por una cuadrícula inventada y no uses datos de Nueva York.
2. **Primero una zona pequeña y jugable.** Prioriza el Malecón / Paseo Álvaro Obregón y algunas calles conectadas del centro. No intentes recrear toda La Paz en la primera entrega.
3. La experiencia debe ser **arcade**, con cámara de persecución, una conducción accesible y sensación de velocidad; no es un simulador automovilístico.
4. El resultado debe incluir **exploración libre y al menos una carrera completa contra rivales controlados por la CPU**.
5. **Genera el mapa previamente (offline)** desde datos OSM descargados y guardados. El juego no debe necesitar Internet para abrirse.
6. Prefiere **GDScript y herramientas estándar de Godot**; usa **Python 3** solo para la conversión previa de datos si simplifica el trabajo. No incorpores dependencias pesadas innecesarias.
7. Usa geometría procedural de bajo detalle y materiales simples. **La fidelidad del recorrido es más importante que las fachadas**.
8. No copies archivos JavaScript de Three.js dentro de Godot esperando que funcionen. Del proyecto *Slop New York* reutiliza **conceptos y algoritmos**, y adapta únicamente código cuya licencia lo permita.
9. Cualquier ruta de carrera es **ficción interactiva dentro del videojuego**; no debe presentarse como recomendación para competir en calles reales.
10. Avanza por etapas ejecutables y registra qué funciona, qué falta, qué probaste realmente y cómo reproducir los resultados. **No afirmes que pasó una prueba si no la ejecutaste.**

**Autonomía:** toma decisiones técnicas razonables cuando falten detalles menores. Documenta las suposiciones. No detengas la implementación por preguntas estéticas o elecciones que no bloqueen el MVP.

---

## 1. VISIÓN Y ALCANCE

### Fantasía de juego

Un juego sencillo de **carreras clandestinas ficticias nocturnas** en el que el jugador conduce por una versión estilizada y reconocible de La Paz, B.C.S. La identidad del escenario proviene del **trazado real de las vialidades**, el paseo costero, los edificios bajos y el ambiente urbano de Baja California Sur.

### Bucle principal

1. Aparecer en una calle transitable, con un automóvil listo para conducir.
2. Explorar libremente un sector pequeño y reconocible de la ciudad.
3. Acercarse a un marcador para iniciar una carrera.
4. Ver cuenta regresiva **3, 2, 1, ¡YA!** y competir contra **2 vehículos rivales**.
5. Cruzar puntos de control en el orden correcto hasta la meta.
6. Mostrar puesto, tiempo y opción de **repetir** o volver a explorar.

### Debe existir en el MVP (P0)

- [ ] Proyecto Godot 4.7.2 que abre sin errores de importación o scripts.
- [ ] Vialidades y cruces generados desde datos OSM de un sector auténtico de La Paz.
- [ ] Calles con superficie transitable, anchura razonable y colisiones.
- [ ] Escenario básico: edificios genéricos bajos, banquetas o bordes, palmeras/postes simples, suelo y referencia visual del litoral cuando proceda.
- [ ] Un coche del jugador, control arcade con teclado y cámara de persecución.
- [ ] Modo libre y **una carrera de principio a fin** (circuito o sprint).
- [ ] **Dos rivales CPU** que siguen una ruta y pueden terminarla.
- [ ] HUD: velocidad km/h, estado de carrera, posición, cronómetro, progreso/checkpoint.
- [ ] Reiniciar vehículo si se atasca o vuelca, reiniciar carrera y volver al menú.
- [ ] Datos y escena jugables **sin conexión a Internet**.
- [ ] Documentación reproducible de instalación, generación del mapa y controles.

### No forma parte del MVP (P2 / fuera de alcance)

- Toda la extensión urbana de La Paz, interiores y edificios reales uno a uno.
- Multijugador, personalización avanzada, economía, policía, persecuciones, peatones, tránsito masivo, daños realistas, tuning, música comercial y guardado en la nube.
- Fotogrametría, mapa satelital, iluminación fotorrealista, un simulador de física de neumáticos o navegación dinámica de toda la ciudad.
- Generación procedimental de alturas exactas, puentes complejos, pasos elevados y terrenos accidentados.

**Prioridad invariable:** mapa vial creíble → coche divertido → carrera completa → ambientación → optimización.

---

## 2. REFERENCIAS QUE DEBES EXAMINAR

### Proyecto inspirador: Slop New York

- Repositorio: https://github.com/mrdoob/slop-newyork
- Licencia de código: MIT (ver `LICENSE` del repositorio).
- `tools/geo-streets.mjs`: ejemplo de conversión y agrupación de geometría vial con atributos.
- `js/road-network.js`: ejemplo de grafo de circulación, carriles y conexiones.
- `js/city-grid.js`: referencia conceptual para calzadas, cruces y banquetas.
- `js/buildings.js`: referencia conceptual para lotes, volúmenes arquitectónicos, aleatoriedad reproducible y partición espacial.

**Advertencia crucial:** esos algoritmos contienen reglas específicas de Manhattan (avenidas ortogonales, anchos, barrios, geometría isleña, nombres de calles, etc.). **No los portes literalmente**. Un sistema de La Paz debe leer **polilíneas viales OSM**, incluidas curvas, calles irregulares e intersecciones, y generar geometría a partir de ellas.

### Fuentes y documentación

- OpenStreetMap: https://www.openstreetmap.org/
- OpenStreetMap, licencias y atribución: https://www.openstreetmap.org/copyright
- Overpass QL: https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL
- Overpass Turbo (explorar consultas): https://overpass-turbo.eu/
- Godot, documentación estable: https://docs.godotengine.org/en/stable/
- Godot, `CharacterBody3D`: https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html
- Godot, importación de escenas glTF: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html
- Godot, `MultiMeshInstance3D`: https://docs.godotengine.org/en/stable/tutorials/3d/using_multi_mesh_instance.html
- Información turística oficial del Malecón: https://turismo.lapaz.gob.mx/atractivos/malecon-de-la-paz

---

## 3. ÁREA GEOGRÁFICA DEL PROTOTIPO

### Zona de arranque

**Malecón / Paseo Álvaro Obregón y calles conectadas del centro de La Paz.** Es una elección inicial por su identidad visual y por la posibilidad de recorrer una parte costera reconocible.

Usa esta **caja geográfica orientativa**, únicamente como punto de partida para inspeccionar datos:

```text
Sur:   24.1480
Oeste: -110.3340
Norte: 24.1700
Este:  -110.3050
```

**No presupongas que la caja es la selección final perfecta.** Antes de procesarla, inspecciona en OSM/Overpass la conectividad, la extensión de la costa y las calles incluidas. Ajusta y registra los límites en `config/map_config.json`; conserva un área razonable (aprox. 2–3 km por lado). La selección definitiva debe contener un recorrido continuo y suficiente para al menos una carrera de **1.2 a 2.5 km**. Si no existe un circuito adecuado por sentidos viales, crea **una carrera tipo sprint** (inicio y meta distintos), sin inventar conexiones entre calles.

**Criterios de selección:**

- Reconocer el trazo de Paseo Álvaro Obregón y algunas conexiones reales.
- No diseñar rutas fuera del área descargada o sobre zonas marítimas.
- Utilizar cruces transitables; registrar calles de un solo sentido.
- Mantener las proporciones en **metros**.
- Si OSM tiene datos inconsistentes, registrar las correcciones locales en un archivo separado (`config/map_overrides.json`) con motivo y referencia; **no editar los datos crudos a mano**.

---

## 4. ARQUITECTURA DEL SISTEMA

```text
                  PROCESAMIENTO PREVIO (Python)
  OpenStreetMap/Overpass -> cache OSM JSON -> validador
                                        |
                              proyección local metros
                                        |
                         grafo vial + segmentos + lotes
                                        |
                         data/processed/la_paz_map.json
                                        |
                           EJECUCIÓN LOCAL (Godot)
                          lectura de datos procesados
                                        |
                        generación de sectores 3D
                      /        |          |         \
                  calles    colisiones  edificios  decorado
                                        |
                  automóvil jugador + rivales + checkpoints
                                        |
                             UI y flujo de carrera
```

**Regla arquitectónica:** las herramientas *offline* nunca deben depender de cargar escenas de Godot, y Godot nunca debe ejecutar consultas a Overpass para construir una partida normal.

### Estructura propuesta del repositorio

```text
la-paz-after-dark/
├── project.godot
├── README.md
├── CREDITS_AND_LICENSES.md
├── config/
│   ├── map_config.json
│   ├── map_overrides.json
│   └── driving_config.json
├── tools/
│   ├── fetch_osm.py
│   ├── build_map.py
│   ├── validate_map.py
│   └── requirements.txt
├── data/
│   ├── raw/                  # snapshot OSM descargado, con fecha y origen
│   └── processed/
│       └── la_paz_map.json
├── scenes/
│   ├── Main.tscn
│   ├── world/World.tscn
│   ├── cars/PlayerCar.tscn
│   ├── cars/RivalCar.tscn
│   └── ui/HUD.tscn
├── scripts/
│   ├── world/MapLoader.gd
│   ├── world/ChunkManager.gd
│   ├── world/RoadBuilder.gd
│   ├── world/BuildingBuilder.gd
│   ├── driving/ArcadeCar.gd
│   ├── driving/RivalDriver.gd
│   ├── race/RaceManager.gd
│   ├── race/Checkpoint.gd
│   └── ui/HUD.gd
├── tracks/
│   └── malecon_sprint.json
├── tests/
│   ├── test_projection.py
│   ├── test_road_graph.py
│   └── test_map_export.py
└── assets/
    └── materials/           # materiales básicos, propios o compatibles
```

Se permite ajustar nombres, pero mantén la separación entre **geodatos**, **generación visual**, **conducción** y **lógica de carreras**.

---

## 5. IMPORTACIÓN Y NORMALIZACIÓN DE OPENSTREETMAP

### 5.1 Descarga reproducible

Crea `tools/fetch_osm.py` para consultar una instancia pública de Overpass con reintentos moderados y tiempo de espera; respeta sus límites de uso. Guarda la respuesta sin modificar en `data/raw/la_paz_roads_YYYYMMDD.json`, con fecha, URL de origen, bbox y hash en un archivo de metadatos. **No descargues nada de nuevo si existe una caché válida**, salvo que el usuario indique `--refresh`.

Ejemplo de consulta Overpass QL **solo para carreteras** (el agente puede mejorarla):

```overpass
[out:json][timeout:90];
(
  way["highway"~"^(primary|secondary|tertiary|residential|unclassified|living_street|service)$"](24.1480,-110.3340,24.1700,-110.3050);
);
(._;>;);
out body;
```

En una petición separada y opcional, buscar `way["building"]` dentro del área. No mezclar indiscriminadamente edificios y carreteras en la primera consulta si se vuelve demasiado pesada.

**Precauciones:**

- El orden de bbox de Overpass es `(sur, oeste, norte, este)`.
- Una `way` puede extenderse fuera de la bbox: recorta solo en una fase geométrica consistente y conserva nodos en el borde cuando hagan falta.
- No confundas `highway` en OSM con autopistas: incluye muchos tipos de vialidad.
- Excluye del grafo de vehículos: `footway`, `pedestrian`, `path`, `cycleway`, `steps`, `construction` y accesos `private`/`no` cuando corresponda.
- Trata `oneway=yes`, `oneway=-1`, `junction=roundabout`, `lanes`, `width` y `maxspeed` cuando existan.
- **No inventes precisión:** si `width`, `lanes` o `maxspeed` faltan, aplica valores heurísticos configurables y márcalos como estimados.
- No crees una intersección por el simple cruce visual de dos líneas si no comparten nodo OSM (ej. niveles distintos).

### 5.2 Proyección geográfica a Godot

Usa una proyección local **equirectangular alrededor de un origen fijo** de la zona (suficiente para un mapa urbano pequeño), con todas las coordenadas en metros:

```python
from math import cos, radians

R = 6_371_000.0

def gps_to_local(lat, lon, lat0, lon0):
    x_east = R * radians(lon - lon0) * cos(radians(lat0))
    z_south = -R * radians(lat - lat0)
    return x_east, z_south
```

Convenciones: `+X = este`, `-Z = norte`, `Y = arriba`. Por tanto, la posición Godot de un punto vial será `(x_east, 0, z_south)`. No conviertas grados en unidades de juego directamente. Guarda el origen `(lat0, lon0)` en el resultado para obtener coordenadas coherentes entre edificios, rutas y calles. Para regiones mayores, sustituye este método por una proyección métrica adecuada, pero **no es necesario en el MVP**.

### 5.3 Grafo vial

- Conserva identificadores OSM de los nodos y los segmentos originales.
- Divide tramos en nodos de cruce/topología y construye un grafo **dirigido** con distancias en metros.
- En calles bidireccionales crea aristas en ambos sentidos; en calles `oneway`, solo el sentido permitido.
- No conectes pasos a diferente nivel si OSM no señala una conexión.
- Almacena una polilínea asociada a cada tramo del grafo para conducir por la curva real, no en línea recta entre extremos.
- Usa **Dijkstra o A\*** para calcular rutas y verificar que un inicio tiene conexión real con la meta.
- Conserva nombres de calles para depuración; no dependas de los nombres para generar geometría.

### 5.4 Datos intermedios

`data/processed/la_paz_map.json` debe tener esquema **documentado y versionado**. Ejemplo ilustrativo, no datos reales:

```json
{
  "schema_version": 1,
  "metadata": {
    "source": "OpenStreetMap contributors",
    "license": "ODbL",
    "origin_lat": 24.158,
    "origin_lon": -110.320,
    "units": "meters",
    "axes": "+X=east,-Z=north,+Y=up",
    "bbox": [24.148, -110.334, 24.170, -110.305]
  },
  "nodes": [
    {"id": "sample_node_1", "x": 0.0, "z": 0.0},
    {"id": "sample_node_2", "x": 40.0, "z": -12.0}
  ],
  "roads": [
    {
      "id": "sample_segment_1",
      "from": "sample_node_1",
      "to": "sample_node_2",
      "points_xz": [[0.0, 0.0], [40.0, -12.0]],
      "oneway": false,
      "width_m": 8.0,
      "width_estimated": true,
      "street_name": "EJEMPLO, NO ES UNA CALLE REAL"
    }
  ],
  "buildings": []
}
```

**Importante:** el JSON mostrado sirve exclusivamente como **esquema de ejemplo**. El archivo final debe contener datos auténticos procesados a partir de OSM; jamás entregues los ejemplos como si fueran el mapa de La Paz.

### 5.5 Validaciones automáticas de datos

Implementa `tools/validate_map.py` y pruebas para asegurar:

- Existe al menos una red vial no vacía y de extensión razonable.
- Todos los puntos contienen números finitos y escalas correctas.
- Ningún tramo tiene longitud cero o nodos faltantes.
- Las aristas del grafo respetan las direcciones declaradas.
- Las rutas de carrera recorren aristas válidas y no se teletransportan.
- La geometría vial no crea saltos bruscos en cruces transitables.
- El mapa no muestra etiquetas o datos ficticios ocultos como datos reales.

Si la API falla, proporciona un error útil y permite continuar con un **snapshot OSM legítimo ya cacheado**. Puede existir una pista sintética de **test técnico**, pero debe estar inequívocamente separada y etiquetada como tal, nunca reemplazar silenciosamente a La Paz.

---

## 6. GENERACIÓN DE LA CIUDAD EN GODOT

### 6.1 Carreteras (prioridad absoluta)

Para cada segmento OSM, construye una **tira de geometría** siguiendo su polilínea, con anchura calculada desde `width`, `lanes` o una heurística. Puede implementarse con `ArrayMesh`/`SurfaceTool`:

1. Calcular dirección tangente en cada punto, ignorando segmentos degenerados.
2. Calcular una normal horizontal para obtener borde izquierdo y derecho.
3. En giros, usar uniones con límite de *miter* o redondeos simples para evitar picos.
4. Triangular la superficie a una altura consistente; asignar material de asfalto.
5. Resolver cruces: que no queden huecos ni bordes elevados capaces de detener al automóvil.
6. Generar colisión **estática** para la superficie manejable, sin duplicar mallas de colisión por detalle cosmético.
7. Añadir marcas viales mínimas opcionales solo cuando no degraden rendimiento.

**Las intersecciones no pueden ser simples rectángulos superpuestos de forma que el vehículo se caiga o rebote.** Prioriza continuidad física sobre acabados visuales.

Valores iniciales **heurísticos**, configurables cuando OSM no da ancho:

| Tipo OSM | Ancho aproximado de calzada |
|---|---:|
| `residential` | 7 m |
| `unclassified` / `living_street` | 6 m |
| `tertiary` | 9 m |
| `secondary` | 11 m |
| `primary` | 12 m |
| `service` | 4.5 m |

Estas medidas **no son mediciones reales de La Paz** y deben ceder ante atributos OSM verificados. La altura base puede ser `Y=0` mientras el circuito permanezca en un sector relativamente plano. Si se encuentra un puente, túnel o desnivel no representable, **exclúyelo del recorrido del MVP** o resuélvelo explícitamente: no aplanes conexiones que deberían estar separadas.

### 6.2 Ciudad de bajo detalle

La decoración **no debe impedir circular**. Orden recomendado:

1. Suelo simple color arena/tierra; asfalto oscuro y banquetas claras.
2. Edificios bajos como prismas de 1–3 niveles, alturas variadas pero moderadas.
3. Muros o fachadas simples con colores claros; evita rascacielos de estilo Manhattan.
4. Palmeras, alumbrado vial y postes sencillos en zonas adecuadas.
5. Mar o bahía visible cerca del Malecón, **solo donde corresponda geográficamente**; no coloques agua en la cuadrícula urbana.
6. Señales, texturas detalladas y edificios emblemáticos: posteriores al núcleo jugable.

**Edificios:** si hay huellas `building=*` de OSM, aprovéchalas para colocar volúmenes simples. Si faltan, genera lotes *aproximados* en áreas libres de las vías mediante semillas reproducibles. **No generes edificios sobre carreteras, intersecciones o la bahía.** Si no puedes delimitar lotes con suficiente confianza, prefiere manzanas vacías o decorado manual sencillo a ocupar calles.

**Costa:** utiliza datos de costa/agua OSM válidos o una silueta visual trazada manualmente sobre una referencia contrastada. Si faltan datos, crea una vista costera estilizada sin atribuirle precisión métrica. No es obligatorio generar la línea de costa completa.

### 6.3 Escena y rendimiento

- Divide el área en **sectores de ~256 m** configurables.
- Cada sector agrupa mallas estáticas de calles, detalles y edificios.
- Usa `MultiMeshInstance3D` para repeticiones de palmeras/postes cuando resulte útil.
- Evita una escena con miles de nodos individuales de decoración si pueden combinarse.
- Carga todo el sector del MVP si funciona fluidamente; añade *streaming* por distancia solo si las mediciones indican necesidad. No sobreingenierices.
- Mantén colisiones precisas solo en carreteras, bordes importantes y obstáculos grandes.
- Para depurar agrega una vista opcional de grafo, rutas, puntos de control y límites de sectores.

**Meta de calidad (no garantía):** buscar 60 FPS a 1080p en una PC de desarrollo de gama media, con ajustes gráficos básicos; registrar FPS medidos y equipo real cuando se pruebe. Si no se dispone de GPU interactiva para medirlo, dejarlo expresamente pendiente.

---

## 7. VEHÍCULO DEL JUGADOR: CONDUCCIÓN ARCADE

### Decisión técnica inicial

Usa `CharacterBody3D` con movimiento programado en `_physics_process(delta)`, salvo que una prueba breve demuestre que una alternativa es claramente mejor. La documentación de Godot advierte limitaciones conocidas de `VehicleBody3D` para física de vehículos avanzada; para este MVP **no necesitamos simular suspensión y neumáticos con realismo**.

Usa una colisión sencilla tipo caja/cápsula adecuada al cuerpo del coche, gravedad, detección de suelo y `move_and_slide()`. No multipliques `velocity` por `delta` al asignarla a `CharacterBody3D`: el método ya utiliza el paso de física.

### Controles requeridos

| Acción | Entrada por defecto |
|---|---|
| Acelerar | `W` / Flecha arriba |
| Frenar / reversa | `S` / Flecha abajo |
| Girar | `A`,`D` / Flechas |
| Freno de mano | Barra espaciadora |
| Reiniciar vehículo | `R` |
| Iniciar carrera / interactuar | `E` |
| Pausa | `Esc` |
| Cámara alternativa (opcional) | `C` |

Todas las acciones deben quedar declaradas en `InputMap` para poder remapearlas después.

### Parámetros iniciales ajustables

```ini
max_forward_speed_mps = 32.0   # aprox. 115 km/h
max_reverse_speed_mps = 7.0
acceleration_mps2 = 11.0
braking_mps2 = 22.0
coast_deceleration_mps2 = 4.0
steering_sensitivity = 1.0
steering_reduction_at_high_speed = 0.55
handbrake_grip_multiplier = 0.45
```

Los números son **puntos de partida de diseño**, no valores físicos precisos. Ajustar mediante pruebas para que el coche se conduzca con teclado y pueda tomar curvas urbanas sin volcar constantemente.

### Comportamiento mínimo

- Acelera y desacelera de forma gradual.
- Direcciona según la velocidad; no gira sobre su centro a velocidad cero como un personaje caminando.
- El freno de mano incrementa el derrape de forma controlada.
- Chocar contra muros sólidos reduce velocidad y evita atravesarlos.
- Si sale de la carretera, no atraviesa edificios o el vacío; penalizar velocidad sobre suelo no asfaltado es opcional.
- **Recuperación:** la tecla `R` coloca el coche en el último punto seguro sobre calzada, orientado según el sentido del recorrido, nunca en medio de un edificio ni bajo el mapa.
- Indicador de km/h: `abs(velocidad_en_m_s) * 3.6` redondeado; no confundir unidades.
- Cámara `SpringArm3D` / `Camera3D` detrás del vehículo, interpolación suave y protección contra atravesar paredes.

El vehículo puede ser **un bloque/modelo low-poly propio**; evita descargar marcas, logos o automóviles comerciales para un prototipo técnico.

---

## 8. RUTAS Y CARRERAS

### Carrera inicial

Crear **una carrera urbana de 1.2–2.5 km**, preferentemente cercana al Malecón, con:

- Inicio y meta definidos sobre nodos o tramos reales de OSM.
- Entre **6 y 12 checkpoints** (ajustables a la distancia real).
- Al menos **2 vehículos rivales**.
- Cuenta regresiva, cronómetro, clasificación y finalización.
- Reinicio inmediato y vuelta al modo libre.

**Regla antiinvento:** no declares un «circuito del Malecón» basándote solo en nombres de calles. Calcula primero una ruta **continua y transitables** en el grafo importado. Si no hay circuito, usa un **sprint**. Los puntos de control se sitúan **sobre la geometría vial**, no en coordenadas GPS estimadas a ojo.

### Esquema de ruta sugerido

`tracks/malecon_sprint.json` debe registrar:

```json
{
  "id": "malecon_sprint",
  "display_name": "Recorrido del Malecón",
  "mode": "sprint",
  "map_schema_version": 1,
  "road_node_sequence": [],
  "checkpoint_distances_m": [],
  "total_length_m": 0,
  "start_grid_offsets_m": [0.0, -4.0, 4.0]
}
```

Las listas del ejemplo están vacías **intencionalmente**. El agente debe **generar y guardar identificadores reales** del grafo antes de considerarlo entregado. Documentar si se usa una polilínea de ruta alternativa y cómo se relaciona con el grafo. Si las posiciones de salida no permiten tres vehículos en paralelo, optar por una **parrilla escalonada** sobre el carril válido, no colocar rivales fuera de carretera.

### Checkpoints y reglas

- Un checkpoint es un `Area3D` que solo se activa después del anterior.
- Verifica dirección de paso cuando corresponda; pasar por detrás no debe completar la carrera.
- No se puede saltar checkpoints.
- `RaceManager` mantiene estado explícito: `FREE_ROAM`, `COUNTDOWN`, `RACING`, `RESULTS`, `PAUSED`.
- Tiempo y orden de llegada consistentes, no estimados con base en la distancia al último checkpoint.
- Si el jugador se atasca, la recuperación debe preservar progreso válido y aplicar una penalización simple (por ejemplo, unos segundos) si se desea balancear.
- Un rival que termina registra resultado; clasificación durante la carrera según avance **a lo largo de la ruta**, no según distancia recta a la meta.

### IA rival: sencilla, verificable

- Ruta precomputada a partir de la misma polilínea que recorren los checkpoints.
- Seguir trayectoria con un algoritmo de seguimiento tipo **pure pursuit** o dirección al punto objetivo con anticipación.
- Reducir velocidad antes de curvas cerradas según curvatura estimada.
- Evitar giros instantáneos y cambios abruptos de orientación.
- Recuperarse si queda bloqueado, con lógica de *unstuck* (temporalizador, recolocación en segmento seguro); que quede registrado en debug.
- Permitido que rivales tengan parámetros simplificados, pero no deben teletransportarse arbitrariamente frente al jugador.
- No implementar tráfico general ni pathfinding reactivo de toda la ciudad durante el MVP.

---

## 9. UI Y PRESENTACIÓN

### HUD imprescindible

- Velocímetro legible en **km/h**.
- Posición: **1.º / 3**, **2.º / 3** o **3.º / 3**.
- Cronómetro `MM:SS.mmm`.
- Checkpoint actual/total y marcador visual claro del siguiente objetivo.
- Indicaciones `E para correr`, `R para recuperar`, `Esc para pausa` cuando apliquen.
- Pantalla final con clasificación y botón **Reintentar** / **Modo libre**.

### Dirección visual

Atmósfera estilizada de **La Paz de noche o al atardecer**: cielo cálido/oscuro, luces viales y una franja costera distinguible. El objetivo no es fotorrealismo. Debe poder distinguirse el asfalto de los límites de conducción, de día o de noche.

Para preservar tiempo de desarrollo, el agente puede usar primitivas, materiales planos y una interfaz minimalista. Agrega música/efectos solo si son propios o con licencia verificada; nunca utilices archivos encontrados en Internet sin comprobar sus permisos.

---

## 10. PLAN DE EJECUCIÓN POR FASES

### Fase A — La Paz en el motor (primer entregable jugable parcial)

**Construir:** repositorio Godot + herramientas de adquisición OSM + transformación a metros + malla vial + colisiones + cámara de prueba.

**Prueba de salida:** abrir Godot y recorrer visualmente un sector que corresponda a calles reales de La Paz; el automóvil o una cámara de depuración permanece sobre la superficie al cruzar intersecciones. El archivo JSON y el origen OSM se pueden inspeccionar.

### Fase B — Conducción libre

**Construir:** vehículo arcade, controles, cámara de seguimiento, velocidad, recuperación, edificios low-poly básicos y límites del mundo.

**Prueba de salida:** conducir por varias calles conectadas sin caerse del mapa ni atravesar fachadas, detenerse y recuperar el coche.

### Fase C — Una carrera completa

**Construir:** ruta validada por el grafo, checkpoints, estados de carrera, cuenta regresiva, 2 rivales, HUD, meta, resultados y reinicio.

**Prueba de salida:** iniciar, completar y repetir una carrera sin edición manual de escenas entre intentos; los rivales también pueden llegar a meta.

### Fase D — Pulido mínimo y entrega

**Construir:** ambientación del Malecón, ajustes de manejo, optimización medida, instrucciones de instalación, créditos y registro de limitaciones.

**Prueba de salida:** un tercero puede abrir el proyecto descargado, jugar sin conexión y reproducir la extracción/regeneración de datos si lo desea.

**No continúes automáticamente con nuevas funciones P2 antes de satisfacer las pruebas de salida P0.**

---

## 11. PRUEBAS Y CRITERIOS DE ACEPTACIÓN

### Automatizadas (obligatorias si pueden ejecutarse en el entorno)

1. **Proyección:** el mismo punto GPS siempre se transforma a `(0,0)` respecto de sí mismo; distancias cortas coherentes con metros; norte produce `z` negativa.
2. **Importación:** datos OSM reales producen una red no vacía, sin NaN, ids duplicados ni segmentos degenerados.
3. **Grafo:** direcciones únicas respetadas; rutas no conectan puntos sin arista vial; prueba una búsqueda de ruta real.
4. **Ruta:** todos los checkpoints están sobre el corredor generado, son ordenados y la meta es alcanzable.
5. **Carga:** JSON procesado válido para la versión de esquema que espera Godot.

Comandos orientativos que deben quedar documentados y ajustados a la implementación final:

```bash
python tools/fetch_osm.py --config config/map_config.json
python tools/build_map.py --config config/map_config.json
python tools/validate_map.py --input data/processed/la_paz_map.json
python -m unittest discover -s tests -v

godot --headless --path . --editor --quit
godot --path .
```

`godot --headless --editor --quit` sirve para comprobar carga/importación y detectar ciertos errores, **no sustituye** la prueba visual de que la conducción y las carreras funcionan.

### Manuales (requieren ejecución del juego)

- [ ] El vehículo arranca sobre asfalto reconocible y con colisión.
- [ ] Se puede conducir en al menos cinco intersecciones conectadas sin huecos físicos importantes.
- [ ] Acelerar, frenar, girar y recuperar funciona repetidamente.
- [ ] Una carrera puede iniciarse, terminarse y reiniciarse.
- [ ] Los dos rivales siguen los checkpoints y terminan o gestionan atasco de manera visible.
- [ ] El HUD coincide con progreso, posición y tiempo reales.
- [ ] El juego puede iniciar con Internet desconectado.
- [ ] El trazado coincide **visualmente** con la zona OSM seleccionada; si no coincide, NO se declara aprobado.
- [ ] Se incluyen atribución de OSM y licencia de terceros.

### Rendimiento y límites

Mide FPS, tiempo de carga, número de nodos, triángulos y draw calls **si tu entorno permite esas mediciones**. No inventes números. Deja un registro simple de la computadora utilizada y configura una opción de calidad reducida si fuera necesario.

---

## 12. LICENCIAS Y ATRIBUCIÓN

- **OpenStreetMap:** datos bajo **ODbL**; mostrar `© OpenStreetMap contributors` en créditos y reconocer la licencia y enlace. Las obligaciones sobre bases de datos derivadas pueden aplicar si distribuyes los datos modificados; conservar procedencia, modificaciones y fecha de extracción y revisar los términos antes de publicar.
- **Slop New York:** si adaptas literalmente código protegido del repositorio, conserva el aviso de copyright y la licencia **MIT** correspondiente. Que las ideas se inspiren en el proyecto **no significa** que sus archivos JS se puedan usar sin adaptación técnica.
- **Godot:** cumplir licencia y avisos del motor cuando corresponda.
- **Modelos y audio:** originales, dominio público verificable o licencias compatibles, registradas en `CREDITS_AND_LICENSES.md`.
- **No marques, logotipos ni nombres comerciales innecesarios** en los modelos generados.

No empaquetes mapas raster comerciales, capturas de Google Maps o materiales de terceros sin derechos suficientes.

---

## 13. REGLAS DE CALIDAD DEL AGENTE

1. Implementa primero una **sección vertical completa**, no veinte sistemas incompletos.
2. No dejes funciones `pass`, `TODO` o pseudocódigo en el camino crítico del MVP.
3. No atribuyas a OpenStreetMap calles, anchos, edificios o coordenadas inventados.
4. En caso de conflicto entre *Slop New York* y la realidad cartográfica de La Paz, **prevalecen los datos de La Paz**.
5. No fijes rutas ni checkpoints únicamente con texto: guárdalos en archivos de datos válidos y verificables.
6. Mantén el generador **determinista**: misma entrada + misma semilla → mismo resultado visual.
7. Si un problema impide terminar, entrega la última fase operativa, la causa precisa, logs relevantes y el siguiente cambio mínimo necesario.
8. Registra errores con contexto (archivo OSM, `way_id`, coordenada, ruta, sector) para localizarlos.
9. Evita sistemas que solo funcionen en la computadora del agente; usa rutas relativas y dependencias documentadas.
10. Al final muestra **comandos exactos**, archivos creados, pruebas ejecutadas con resultado real y limitaciones verificadas.

---

## 14. FORMATO OBLIGATORIO DE ENTREGA DEL AGENTE

La respuesta final del agente implementador deberá contener:

1. **Estado del prototipo:** qué se puede jugar ya y qué no.
2. **Árbol de archivos:** los archivos fuente más importantes con ruta.
3. **Ejecución paso a paso:** versión precisa de Godot y Python, dependencias si existen, comandos para abrir, generar datos y probar.
4. **Procedencia geográfica:** bbox elegida finalmente, fecha de extracción, origen de la información y adaptaciones documentadas.
5. **Pruebas realizadas:** comandos, salidas relevantes, errores y pruebas manuales efectuadas o pendientes.
6. **Capturas o video** solo si pudo obtenerlos realmente, sin afirmar pruebas visuales que no ocurrieron.
7. **Siguientes mejoras ordenadas por impacto**, limitadas a lo que ayude a pasar de prototipo a demo.

### Definición exacta de «terminado»

> El prototipo está terminado cuando un usuario abre un proyecto Godot en su computadora, puede conducir por un sector construido desde datos reales de La Paz, reconocer el paseo costero o las calles conectadas, iniciar una carrera, competir contra dos coches CPU, pasar por puntos de control, llegar a meta y reiniciar; todo ello sin depender de Internet durante la partida.

**Si falla cualquiera de esos puntos, etiqueta el entregable como parcial y corrige primero el núcleo jugable.**

---

## 15. PRIMERA TAREA QUE DEBES EJECUTAR

**Comienza por crear el proyecto Godot mínimo y la tubería de extracción OSM.** Descarga los datos de la zona propuesta, analiza su grafo, confirma una ruta de 1.2–2.5 km y genera una escena con las calles, superficie física y una cámara de prueba. Solo después incorpora el vehículo. Si el servicio OSM no está disponible, comprueba si existe una caché legítima y documenta el bloqueo; **no sustituyas silenciosamente La Paz por una ciudad ficticia**.

---

*Documento de especificación elaborado el 23 de octubre de 2026. Los límites geográficos, parámetros físicos y métricas objetivo aquí definidos son propuestas iniciales que requieren validación durante la implementación.*
