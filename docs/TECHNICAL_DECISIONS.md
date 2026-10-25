# Decisiones técnicas — Fase A

## Cartografía y grafo

Se usa una única respuesta original Overpass, sin editar. El archivo `.meta.json` conserva consulta, URL, bbox, SHA-256 y fechas de extracción y base OSM. El hash verificado es `a80c891a315fe1f0d1dc3f3dd74a040d41a8a68a94947925336a8754b0ee8142`. La primera instancia (`overpass-api.de`) devolvió un certificado vencido; la segunda funcionó con verificación TLS habilitada.

Proyección equirectangular local con radio 6,371,000 m: X=este, Z=sur, Y=arriba. Origen fijo en configuración. Se incluyen las clases viales configuradas y enlaces; no caminos peatonales/ciclovías. Acceso efectivo por prioridad `motorcar > motor_vehicle > vehicle > access`. Se excluyen private/no, uso forestal/agrícola, áreas viales, puentes, túneles, capas distintas de cero, interiores y restricciones condicionales que el importador no representa. En este snapshot solo se excluyó un way: **1410868892**, acceso privado. No se hicieron overrides cartográficos.

Cada par consecutivo de nodos OSM forma un tramo, conservando el way y los nodos originales. Esta partición más fina que solo cruces mantiene exactamente todas las curvas, simplifica trazabilidad y evita compresión topológica prematura. El grafo conecta **identificadores de nodo**, nunca proximidad o intersección geométrica. El validador rechaza cruces interiores de líneas sin nodo compartido; en el snapshot seleccionado encontró cero. No se fusionan nodos por proximidad.

Se recorta cada segmento a la bbox. Los nodos nuevos de borde tienen identificador `clip:way:segment:side`, `boundary_generated=true` y `osm_node_id=null`: no se presentan como nodos OSM. La calzada puede extenderse medio ancho fuera del borde. Se omiten longitudes menores a 1 cm después del recorte, sin unir sus extremos con conexiones ficticias.

`oneway=-1` invierte geometría y extremos; los sentidos `yes/1/true` generan una arista; los bidireccionales dos. Las glorietas son unidireccionales implícitamente salvo `oneway=no`. Se conservan tags íntegros en cada tramo. No se descargaron relaciones de restricción de giro: el recorrido es una prueba de conectividad con sentidos, **no navegación legal completa ni una carrera implementada**.

Dijkstra explora nodos del corredor Obregón y elige una ruta dirigida de 1.2–2.5 km que maximiza longitud sobre ese corredor. Resultado: **2,325.347220 m**, completamente en ways denominados Paseo Álvaro Obregón, 22 cruces de grado geométrico ≥3 en su secuencia. No hay checkpoints ni archivo de carrera vacío. `verification_route` contiene aristas reales, nodos y polilínea; su propósito queda identificado como sonda de fase A.

## Anchuras y superficies

Prioridad: `width` métrico válido; en su ausencia `lanes × 3.2 m` estimado; después heurística de clase en configuración. Tanto el origen de ancho como su carácter estimado se exportan. `maxspeed` admite números y mph; si falta o es no interpretable se usa una estimación configurable. Un valor numérico inválido de ancho o un sentido reversible no soportado excluye el way y registra el motivo. No son levantamientos de campo.

Shapely 2.1.2 es la única dependencia obligatoria del procesamiento. Se eligió por GEOS: buffers con extremos redondeados (4 subdivisiones por cuadrante), límite miter 2, unión geométrica real, recorte por sectores y triangulación Delaunay con restricciones que respeta huecos de manzanas. Los segmentos individuales usan extremos redondeados: la unión resuelve los giros sin picos. No se dibujan rectángulos de cruce superpuestos.

Se triangula la **unión de toda la calzada** por sectores de 256 m. El validador compara área y diferencia simétrica con esa unión, detecta solapamientos y comprueba todos los ejes viales. Se exportan triángulos locales de sector, reduciendo magnitudes de float32 en la física. Todos están en Y=0; no se presenta altimetría real. El área plana asume que este pequeño corredor no requiere pasos elevados; la política de exclusión impide aplanarlos inadvertidamente.

Godot construye un ArrayMesh y un StaticBody3D/ConcavePolygonShape3D por sector con los mismos triángulos y colisión en ambas caras. Material de asfalto compartido, normales UP. Son 74 cuerpos/mallas, no un objeto por tramo. No hay streaming porque el conjunto es pequeño. El plano neutro queda en Y=-2 y **no tiene colisión**: no puede ocultar huecos en las pruebas. No representa terreno ni bahía. Cámara de mapa con near=5 m para evitar pérdida de precisión de profundidad a kilómetros de distancia; recorrido con near=0.1 m.

## Esquema `la_paz_map.json`, versión 1

- `metadata`: fuente/licencia, bbox, origen GPS, unidades, ejes, hipótesis de altura, política de borde/topología y objeto `provenance`.
- `nodes[]`: `id`, `x`, `z`, `osm_node_id`, `boundary_generated`.
- `roads[]`: `id=way_id:pair_index`, `osm_way_id`, `osm_node_ids`, `from`, `to`, `points_xz`, `length_m`, `osm_tags`, `width_m`, `width_estimated`, `width_source`, `lanes`, `maxspeed_kph`, `maxspeed_estimated`, `oneway`, `reversed`, `street_name`, `highway`. En oneway=-1, from/to ya representan el sentido permitido; `reversed` conserva la decisión respecto al way original.
- `edges[]`: `id`, `road_id`, `from`, `to`, `length_m`, `reverse` (respecto a la geometría exportada).
- `verification_route`: propósito explícito, `edge_ids`, `road_node_sequence`, `points_xz`, `total_length_m`, `obregon_length_m`.
- `chunks[]`: `id`, `origin_xz`, `triangles_xz`; cada triángulo contiene tres pares de metros locales. Añadir origin_xz reconstruye la posición global.
- `statistics`: cantidades y área; `exclusions[]`: way, motivo y tags. `buildings=[]` porque queda fuera de fase.

Misma entrada/configuración y versión de Shapely producen el mismo objeto JSON, comprobado en integración. No se usa azar. Godot rechaza esquema incompatible, datos vacíos o unidades distintas. Las validaciones profundas se ejecutan offline.

## Referencias examinadas

Se revisaron `tools/geo-streets.mjs` y `js/road-network.js` de [Slop New York](https://github.com/mrdoob/slop-newyork): separación de conversión geográfica/grafo y atributos. Sus reglas de Manhattan no se portaron. No se copió código JS ni se incorporó MIT de ese proyecto al código propio.

Referencias API: [Overpass QL](https://wiki.openstreetmap.org/wiki/Overpass_API/Overpass_QL), [Geometry2D](https://docs.godotengine.org/en/stable/classes/class_geometry2d.html), [ConcavePolygonShape3D](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html). La unión y triangulación offline se prefirieron a una unión costosa durante cada inicio de Godot.
