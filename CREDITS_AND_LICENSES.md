# Créditos y licencias

## Datos cartográficos

**© OpenStreetMap contributors.** [Copyright y atribución](https://www.openstreetmap.org/copyright). Snapshot original y base derivada `la_paz_map.json`: [Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/). Se conserva procedencia y registro de modificaciones (proyección, filtrado, recorte, anchos estimados, grafo y superficies) en metadatos y documentación técnica. La atribución también aparece dentro de la escena ejecutable. Los datos derivados se suministran bajo ODbL 1.0; no se atribuyen a OSM las anchuras estimadas ni la altimetría plana.

Extracción vía Overpass Kumi, 2026-10-24T05:35:45Z. Base OSM declarada: 2026-07-15T15:22:01Z. El JSON crudo conserva su aviso original de copyright. No se incluyen mapas raster comerciales.

## Motor y conversión

- [Godot Engine](https://godotengine.org/license/): licencia MIT. Este proyecto usa una instalación del motor existente; no redistribuye sus binarios.
- [Shapely 2.1.2](https://github.com/shapely/shapely/blob/2.1.2/LICENSE.txt): BSD 3-Clause. El paquete de conversión no se incluye en el proyecto y se instala separadamente. GEOS es dependencia del wheel de Shapely y está sujeto a sus propios avisos LGPL; conservar los avisos del paquete si se redistribuye.
- Python 3: instalación separada, no redistribuida aquí.
- Pillow: se utilizó únicamente para una imagen de comparación de datos crudos. No se incluye el paquete ni se requiere para el juego.

## Referencias conceptuales

Se examinaron [Slop New York](https://github.com/mrdoob/slop-newyork), `tools/geo-streets.mjs` y `js/road-network.js`. No se copió ni adaptó literalmente su código. La implementación Python/GDScript de esta fase es propia del proyecto.

No se añadieron modelos, texturas, audio ni logotipos de terceros. Se conservó el icono que ya existía en el proyecto.

## Adición de fase B

Edificios © OpenStreetMap contributors, ODbL 1.0. Snapshot independiente adquirido vía `https://overpass.private.coffee/api/interpreter` el 2026-10-24T06:29:13Z (23/10/2026 23:29 UTC−07), base declarada 2026-06-01T08:52:28Z. El original y sus metadatos están en `data/raw`; `la_paz_environment.json` es una base derivada bajo ODbL 1.0. Se conservaron huellas reales, se omitieron interferencias con carreteras y se generaron alturas estimadas/estilizadas con marcas explícitas.

La carrocería procedural, los materiales planos, ventanas genéricas, plataforma y límites de fase B son implementaciones originales del proyecto. No se descargaron modelos de automóviles, marcas, música ni texturas. Las fachadas no pretenden reproducir los edificios reales más allá de su huella OSM.

## Adición de fase B.5 — Overture, INEGI y espacios libres OSM

**© OpenStreetMap contributors, Overture Maps Foundation.** Tema Buildings de Overture release 2026-10-21.0, descargado el 24/10/2026. [Atribución y licencias Overture](https://docs.overturemaps.org/attribution/), [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/). En el recorte se declaran fuentes **Microsoft ML Buildings / Global ML Building Footprints** (Microsoft, ODbL), **Google Open Buildings** (CC BY 4.0) y **OpenStreetMap contributors** (ODbL). Se conservan los objetos `sources` originales con sus campos de procedencia por entidad. No se atribuye a esos proveedores la altura estimada ni los edificios ficticios.

**INEGI. Marco Geoestadístico, diciembre de 2025; Censo de Población y Vivienda 2020**, según los metadatos del GeoJSON obtenido del servicio oficial el 24/10/2026. [Servicio y documentación](https://www.inegi.org.mx/servicios/catalogounico.html), [términos de libre uso de la información INEGI](https://www.inegi.org.mx/inegi/terminos.html). Las manzanas se transformaron de Mexico ITRF2008 a la proyección local y se utilizaron únicamente como restricciones de colocación; **INEGI no proporciona ni certifica las 167 huellas ficticias generadas**.

Extracto adicional OSM para espacios abiertos: API oficial, XML original conservado con hash y JSON derivado normalizado; © OpenStreetMap contributors, ODbL. La base urbana derivada de OSM/Overture y sus modificaciones se ofrece bajo ODbL 1.0; los términos y atribución de la fuente INEGI se mantienen expresamente. Todo origen, exclusión, recorte menor y estimación se documenta en `docs/PHASE_B5.md` y la auditoría de colocación.

Cliente Overture, PyProj, Shapely/PyArrow y dependencias se instalan en `.venv-urban` exclusivamente para herramientas offline, con sus licencias en los paquetes. Ese entorno se excluye de Git y del contenido Godot mediante `.gdignore`; no se requiere ni se incorpora como dependencia del juego. No se añadieron texturas, audio ni modelos descargados.

## B.6 — procedencia adicional
Los 300 POI se extraen del XML OSM ya conservado (hash verificado), bajo ODbL-1.0. Los seis landmarks usan nombres y ubicaciones de ese snapshot; no se afirma comprobación de campo, fotografía ni silueta arquitectónica exacta. Las fachadas por categoría son reglas visuales propias, no levantamientos del establecimiento.
La costa se deriva de las líneas OSM dirigidas y se recorta al sector original. Convención de orientación consultada: https://osmdata.openstreetmap.de/processing/coastline.html . Las superficies públicas provienen exclusivamente de contornos cerrados/relaciones del snapshot; los buffers de exclusión no constituyen límites cartográficos.
No se importó Microsoft por separado: el snapshot Overture ya declara esa procedencia y agregarlo sin evidencia adicional duplicaría huellas. La primera entrega incorporó únicamente OSM; la continuación añade Places y DENUE con la procedencia indicada abajo. No se usaron Google Maps/Earth ni modelos externos.

### Referencia arquitectónica de la Catedral
Se consultó la monografía oficial **MX-SC-DGSMPC-EM-03-001004**, Secretaría de Cultura, de Salvador Hinojosa Oliva (1984): https://sitiosymonumentos.cultura.gob.mx/iii-estudios-monograficos/nuestra-senora-de-la-paz-catedral/ . Se usó como referencia factual de la pareja de torres y remates piramidales. No se copiaron imágenes, planos ni modelos. La escena y geometría son originales. Las alturas de 10/18/21 m son estimaciones ilustrativas explícitas; no constituyen mediciones del inmueble. Las bases de ambas torres están comprobadas dentro de la huella OSM aceptada.

## Continuación B.6 — Places y DENUE

**Overture Maps Foundation, Places release 2026-10-21.0**. Se conserva el recorte original, hash y atribución `sources` por entidad. [Atribución oficial](https://docs.overturemaps.org/attribution/). Las licencias declaradas en este snapshot son CDLA-Permissive-2.0, Apache-2.0 y CC0-1.0; no se debe atribuir a todo Places la licencia ODbL de Buildings. Copias locales: `data/licenses/CDLA-Permissive-2.0.html`, `Apache-2.0.txt` y `Foursquare-Places-NOTICE.html`. Los registros procedentes de Foursquare mantienen su aviso y atribución; [aviso original](https://opensource.foursquare.com/places-notice-txt/). [CC0](https://creativecommons.org/publicdomain/zero/1.0/). Se preservan las atribuciones originales de proveedores, incluidas Meta y Foursquare. Las categorías, asociaciones a huellas y detalles visuales son modificaciones propias, no certificaciones de los proveedores. Las obligaciones y atribuciones de OSM/ODbL en la base combinada siguen vigentes, además de los términos de estas fuentes.

**INEGI. Directorio Estadístico Nacional de Unidades Económicas (DENUE), edición mayo de 2026**, metadatos modificados el 20/05/2026. [ZIP oficial de Baja California Sur](https://www.inegi.org.mx/contenidos/masiva/denue/denue_03_csv.zip), [términos de libre uso](https://www.inegi.org.mx/inegi/terminos.html). Archivo original y metadatos conservados localmente. La información se recorta al mapa y la actividad SCIAN se traduce a categorías visuales aproximadas. INEGI no certifica las fachadas, entradas, alturas ni asociaciones propuestas. `fecha_alta` es fecha de alta del registro, no de publicación ni garantía de operación actual.

La Catedral amplía la referencia histórica ya citada con arcos, óculo, divisiones de torre, cubierta a dos aguas y cruces. Geometría original procedural, sin copiar fotografías ni planos. Nave de 10 m, cumbrera de 12,4 m, torres de 18 m, remates hasta 21 m y cruces hasta 22,7 m: todas son dimensiones estimadas. La orientación de fachadas genéricas hacia la vía más próxima es una inferencia visual, no una entrada levantada en campo.
