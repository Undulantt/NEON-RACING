# SF.3 — Evidencia urbana y propuesta de fachadas

Fecha: 2026-11-13. Estado: **investigación y propuesta; mejoras no implementadas**.

El usuario confirmó «Informe y propuesta primero». Esta entrega no modifica escenas, materiales, generación del mundo, conducción ni configuración de SF.3. No se descargaron conjuntos cartográficos nuevos. Se consultó documentación oficial y se procesaron los archivos que ya estaban en el proyecto.

## 1. Decisión recomendada

Podemos mejorar mucho la lectura de los edificios normales con variación de color, zócalos, ventanas oscuras, marcos y cornisas sencillas, conservando la estética low-poly y el neón como acento. Conviene hacerlo sobre las mallas existentes por sector, empezando por un sector piloto y las fachadas visibles desde la carretera. Esa apariencia será **diseño procedural**, no una reproducción arquitectónica verificada.

Los datos sostienen mejor la posición de los edificios y ciertos puntos urbanos que su apariencia: el proyecto prepara 62,465 edificios, todos con altura estimada; solo 7 conservan pisos de origen para estimar su altura. Tras las exclusiones arcade quedan 62,410: 61,410 con contornos de fuentes reales y 1,000 edificios ficticios identificados como tales. Hay 60,929 edificios efectivos sin uso clasificado.

La siguiente incorporación geográfica más prometedora es la infraestructura documentada del Malecón, cruces y puntos de referencia. No conviene llenar las calles de palmeras, postes o señales atribuyéndoles posiciones reales: el extracto local no documenta esos elementos con suficiente cobertura.

## 2. Alcance y método del recuento

Inventario reproducible: `python tools/audit_sf3_urban_evidence.py`, desde la raíz del proyecto. Requiere Python y Shapely ya utilizados por las herramientas del mapa. Su única salida es `docs/sf3_urban_evidence.json`; no hace peticiones de red ni construye recursos de Godot.

Se distinguen dos dominios reales del código:

- **V, envolvente visual:** bbox actual `[24.09, -110.3455, 24.185, -110.281]`, orden sur/oeste/norte/este, intersectada con `clip_polygon_lonlat`. Es la selección visual utilizada por el constructor urbano.
- **R, red activa:** unión de `active_blocks`, usando sus polígonos cuando existen, intersectada con el mismo recorte. Es la selección del trazado vial.

La tabla principal usa **V**. El JSON contiene ambos recuentos. Esto evita confundir edificios visibles alrededor del recorrido con el área activa de carreteras. El nombre histórico `inegi_blocks_in_bbox` del manifiesto no describe con precisión todos los filtros: sus 2,658 registros coinciden con R; en V se intersectan 2,998 manzanas.

OSM se cuenta una sola vez por tipo e identificador en el XML fusionado actual, no sumando los mosaicos solapados. Los nodos se filtran por posición; las vías por intersección de su línea de nodos; las relaciones por sus miembros disponibles. Para polígonos de GeoJSON se usa intersección geométrica. Las coordenadas de ejemplo de vías son puntos representativos **derivados sobre la geometría**, no accesos ni levantamientos de precisión. No se reconstruyen superficies de relaciones OSM en este inventario; habrá que resolver anillos y roles para generar esas superficies.

Las categorías pueden solaparse: un cruce puede tener nodo y vía, un establecimiento aparecer en varias fuentes y un parque tener punto y polígono. **Las cantidades son registros, no objetos físicos únicos ni porcentaje de cobertura de La Paz.** Cero significa ausencia bajo las reglas consultadas en este extracto; no significa ausencia en la ciudad. Las reglas completas están en el script.

### Evidencia: ubicación y apariencia son dimensiones distintas

1. **Ubicación documentada:** existe un ID y una geometría en una instantánea identificada. No equivale a verificación de campo ni garantiza vigencia actual.
2. **Existencia/categoría documentada, apariencia aproximada:** por ejemplo, restaurante ubicado por DENUE; fachada, puertas y altura no medidas. Un elemento puede tener ubicación de nivel 1 y apariencia de nivel 2 simultáneamente.
3. **Sin evidencia suficiente:** un poste colocado cada 38 m por diseño o una palma elegida por proximidad a la costa. Debe etiquetarse como decoración, nunca como reconstrucción verificada.

Para una futura integración propongo conservar por elemento `source_id`, archivo y hash, fecha de extracción/edición, licencia, método de posición, evidencia de categoría, evidencia de apariencia y dimensiones estimadas. Separar los registros decorativos de los geográficos desde el preprocesado.

## 3. Qué contiene el proyecto

| Conjunto local | Contenido y selección | Límites importantes |
|---|---|---|
| `osm_map_c6_boundary_expansion.osm` | XML canónico de mosaicos OSM; edificios, vías, puntos y etiquetas retenidos | No es un inventario municipal exhaustivo; los extractos son instantáneas con fechas distintas |
| `overture_buildings_20261026T064408Z.geojson` | Edición 2026-10-21.0, 84,824 registros de archivo; 74,704 intersectan V y 65,558 R | Bbox de descarga comienza en longitud -110.342, no -110.3455; falta la franja occidental añadida después |
| `inegi_blocks_20261024T220934Z.geojson` | 5,796 manzanas de la localidad 030030001; 2,998 intersectan V, 2,658 R | Manzana estadística, no lote ni contorno de construcción; fecha de descarga no es fecha del levantamiento |
| `denue_03_csv.zip` y POI procesados | Fuente estatal, edición 05_2026 según metadatos; 9,232 registros seleccionados en el enriquecimiento actual | Coordenadas de establecimientos; no prueban la fachada, su acceso o la actividad de hoy |
| `overture_places_20261021.geojson` | 3,055 registros; todos dentro de ambos dominios | Solo bbox original del centro: `[24.148,-110.334,24.17,-110.305]`; no cubre toda la expansión |
| `urban_enrichment.json` | 12,890 registros POI: DENUE 9,232, OSM 603, Overture 3,055 | Son registros de fuentes; 670 pares candidatos a duplicado, no 670 establecimientos únicos duplicados |
| `urban_geography.json` | 147 superficies preparadas, incluyendo mar | Son superficies derivadas; no un censo independiente de parques o playas |
| `landmarks.json` | 8 lugares seleccionados para el proyecto | Es una selección editorial, no el total de atractivos; ninguno declara arquitectura verificada |
| `city_manifest.json` y 541 sectores | 5,194 volúmenes OSM, 56,271 Overture, 1,000 ficticios antes de adaptación arcade | Recortes, filtros de tamaño y despeje impiden equiparar estos volúmenes con la cantidad de edificios de la ciudad |

Todos los hashes completos de los archivos leídos están en el JSON de auditoría. Referencias principales:

- Mapa: `58d9e247ab2fde691adb4685dabf12c01ed736f1816c2aba52873b22f54c93c3`.
- XML OSM: `46c8f238ffc3a21a392ace20186f40bbfa94ad8a50c2bf39ea38034da07cf5ad`.
- Overture edificios: `bef1283309ec393bbea5e665fd59c0480d572846ca2f8abd3e08e2147fc4da6e`.
- INEGI manzanas: `3f421a39b699dd37abd938aac5726adfdc67eb14284394542d6b31e14d43d4f9`.

### Arquitectura existente y componentes reutilizables

`BuildingBuilder.gd` extruye contornos, respeta huecos, triangula techos y agrupa geometría y colisiones por sector. Ya dispone de colores por vértice, categorías y detalles sencillos; no hacen falta nodos por ventana.

`UrbanChunkManager.gd` carga sectores de 256 m, con radios configurados de 650 m de carga, 850 m de descarga y 240 m de colisiones. Limita el procesamiento a un sector por frame; esto no garantiza por sí solo que cada sector tarde menos que un frame. Reutilizar este ciclo también para retirar detalles al descargar el sector.

En modo nocturno se desactivan `category_facades` y `detail_windows` del constructor. `NightStyle.gd` añade después sus propias ventanas, cornisas, locales y franjas luminosas. Trabaja sobre hasta tres bordes por edificio, con límites por sector de 10 locales y 8 franjas; agrupa el resultado en dos mallas adicionales. El bucle contempla reanudaciones con un presupuesto de 1,500 microsegundos; la lectura de JSON y la subida de mallas necesitan medirse aparte. Activar ambas rutas de fachadas produciría duplicación y coste innecesario.

`CityFurniture.gd` genera lámparas y vegetación deterministas a partir de carreteras, con separación de referencia de 38 m y topes de 24 lámparas y 14 plantas por sector. Usa MultiMesh y cuatro referencias próximas para el efecto de iluminación sobre el asfalto. **No usa un inventario real de cada poste o palma.** Los detalles y marcas cosméticas de SF.3 tampoco son levantamientos de pintura vial.

`arcade_layout.json` mantiene los ejes reales, pero ensancha el asfalto para jugar y adapta construcciones: registra 10,230 edificios ajustados y 55 eliminados. El gestor borra `facade_edge_index` y `model_path` cuando aplica un override porque se refieren al contorno original. Hay que calcular futuras fachadas sobre el contorno efectivo y revisar por separado la integración de hitos; un modelo declarado en datos no garantiza que aparezca con ese override.

## 4. Tabla comparativa: registros locales encontrados

N = nodos, W = vías, Rl = relaciones OSM. Cantidades en V salvo indicación expresa. «Alta» significa buena candidata para piloto, no autorización para implementarla.

| Elemento | Fuente | Registros reales disponibles | Fidelidad posible | Dificultad | Prioridad |
|---|---|---|---|---|---|
| Banquetas | OSM | 22 W `footway=sidewalk`; 38 W con atributos `sidewalk*` | Eje registrado o lado documentado; ancho y borde generalmente aproximados | Media | Alta en Malecón |
| Pasos peatonales | OSM | 52 N + 9 W | Punto/línea documentados; ancho, pintura y orientación requieren resolver la vía | Media | Alta |
| Semáforos | OSM | 28 N | Intersección/control documentado; no necesariamente ubicación de cada poste o cabeza | Media | Alta, con revisión |
| Señales de tránsito | OSM | 21 N (`traffic_sign` o `highway=stop/give_way/traffic_sign`) | Tipo/posición de control; soporte y lateral no siempre conocidos | Media | Media |
| Camellones/isletas explícitos | OSM | 0 bajo reglas `median`, `area:highway=traffic_island`, `traffic_calming=island` | Insuficiente; dos calzadas paralelas no prueban un camellón construido | Alta | Baja |
| Estacionamientos | OSM | 6 N + 70 W; además 38 W con atributos `parking:*` | Áreas o existencia; plazas individuales y accesos no completos | Baja/media | Media |
| Luminarias individuales | OSM | 0 | Sin posición individual documentada | Media | Baja como reconstrucción |
| Disponibilidad de iluminación | OSM | 2 N + 90 W + 1 Rl con `lit` | Indica atributo, incluyendo posibles valores negativos; no cantidad ni posición de postes | Baja | Media para contexto |
| Barreras/protecciones | OSM | 36 N + 2 W | Incluye puertas y otros tipos; no son 38 guardarraíles | Media | Media |
| Bancas | OSM | 0 | Sin evidencia local en consulta | Baja | Baja como reconstrucción |
| Árboles individuales | OSM | 6 N | Punto documentado; especie, copa y altura no completas | Baja | Alta para piloto pequeño |
| Palmeras explícitas / alineaciones | OSM | 0 / 0 | No afirmar especies ni posiciones nuevas | Baja | Baja como reconstrucción |
| Parques/jardines | OSM | 2 N + 60 W | Punto o límite según registro; vegetación interior aproximada | Media | Alta |
| Otras áreas verdes | OSM | 7 W | Uso/superficie registrados; no árboles individuales | Media | Media |
| Plazas | OSM | 1 W `place=square` | Geometría registrada; detalles interiores no descritos | Media | Media |
| Espacios peatonales | OSM | 161 W, incluye senderos y escaleras | Ejes reales; no todos son banquetas | Media | Alta en corredores visibles |
| Malecón por nombre | OSM | 5 W con nombre que contiene `malec` | Tramos documentados; comparten registros con otras filas | Media | Alta |
| Playa/costa | OSM | 1 N de playa, 3 W de costa | El punto de playa no delimita una playa; costa y mar preparados son referencias para exclusión | Media | Alta para proteger espacios |
| Contornos de edificios | OSM + Overture | 61,465 volúmenes de fuente real preparados; 61,410 efectivos | Ubicación y silueta horizontal aproximadas, con adaptación arcade declarada | Baja para reutilizar | Alta |
| Altura medida | OSM / Overture local | 0 edificios con `height` en las consultas | No es posible reconstruir alturas medidas con estos archivos | Alta para nueva evidencia | Baja |
| Pisos de origen | OSM / Overture local | 9 W OSM con `building:levels`; 9 registros Overture con `num_floors`; no sumarlos | Pisos documentados; convertirlos a metros sigue siendo estimación. 7 conservados en ciudad preparada | Baja/media | Media |
| Apariencia arquitectónica etiquetada | OSM | 2 W bajo reglas consultadas: una cubierta y un color de edificio | Atributos puntuales, insuficientes para fachadas completas | Media | Baja como reconstrucción |
| Comercio/restauración/hospedaje | OSM; DENUE; Overture Places | OSM: tiendas 107 N + 44 W; comida 194 N + 20 W; hospedaje 32 N + 6 W + 1 Rl. Otras fuentes: 9,232 + 3,055 POI de todas las categorías | Ubicación/categoría de establecimiento; no toda su fachada ni su contorno | Media | Alta con asociación segura |
| Edificios/servicios públicos y culturales | OSM + POI | 27 N + 83 W + 2 Rl OSM bajo reglas del script | Incluye áreas y establecimientos; no todos son edificios individuales | Media | Alta para selección |
| Monumentos/memoriales | OSM | 1 W | Existencia/tipo; volumen y dimensiones aproximados | Media/alta | Media |
| Esculturas/arte público | OSM | 13 N `tourism=artwork` | Posición, algunos nombres/tipos; sin malla de la escultura | Alta para semejanza visual | Media |
| Atractivos/miradores/información | OSM | 10 N + 1 W | Puntos o geometrías; no 11 atracciones independientes garantizadas | Media | Media |
| Hitos seleccionados del proyecto | OSM y selección local | 8 registros | Ubicación documentada, arquitectura no verificada; modelo estimado de Catedral declarado | Media/alta | Alta para pocos hitos |
| Referencia de manzanas | INEGI | 2,998 en V; 2,658 en R | Límites estadísticos; no permite atribuir edificios ficticios al INEGI | Media | Media |
| Entorno urbano por frente/manzana | INEGI, producto adicional | No descargado ni contado para esta entrega | Disponibilidad de banqueta, alumbrado o árboles; no posiciones de cada objeto | Media | Media |
| Contornos Microsoft independientes | Microsoft Global ML | No descargados ni contados como capa independiente | Potencial contraste de huecos; no fachadas | Media/alta | Baja hasta demostrar ganancia |

Los 1,000 edificios de relleno quedan fuera de los «registros reales» de la tabla. Su ubicación está restringida por manzanas, pero el contorno sigue siendo ficticio.

### Datos de uso y altura: límites concretos

El enriquecimiento tiene **1,131 asociaciones por contención única**, 11,759 registros sin edificio asignado y 1,369 registros no elegibles para clasificación. La proximidad de hasta 8 m se deja para revisión; no permite trasladar un negocio a la fachada más próxima automáticamente. Los 670 pares de posibles duplicados tampoco se fusionan por nombre de manera automática.

Los edificios efectivos se clasifican así: desconocidos 60,929; residenciales 798; comerciales 361; restaurantes 157; institucionales 86; hoteles 33; culturales 27; industriales 19. Son categorías de generación del proyecto, algunas derivadas de etiquetas y otras de asociaciones de POI. No equivalen a un catastro de uso de suelo.

Antes de arcade, las alturas se obtienen mediante: 61,457 estimaciones deterministas de 1–3 pisos, 1,000 estimaciones para relleno ficticio, 7 conversiones de pisos a 3.1 m/piso y 1 override manual. Todas siguen marcadas como estimadas. Un registro de pisos OSM llega a 20: antes de adoptar valores extremos hay que contrastarlos, sin convertirlos silenciosamente en una medición validada.

Overture local tiene, dentro de V, 929 registros con `subtype`, 879 con `class`, 138 con `names`, 9 con `num_floors` y 1 con `roof_shape`. No tiene valores de `height`, `facade_color` ni `facade_material`. La existencia de campos opcionales en el [esquema de edificios de Overture](https://docs.overturemaps.org/schema/reference/buildings/building/) no demuestra que estén poblados en La Paz ni en la edición descargada.

## 5. Ejemplos verificables del archivo local

Coordenadas en latitud, longitud. Se verifica presencia en la instantánea, no vigencia mediante visita de campo. Los enlaces apuntan al objeto OSM actual, que puede haber cambiado respecto al archivo local.

| Registro | Coordenadas | Lo que podemos afirmar / lo que falta |
|---|---|---|
| [Semáforo, nodo 313433815](https://www.openstreetmap.org/node/313433815) | 24.1513110, -110.3263697 | Punto de control registrado; falta soporte, altura y orientación de las cabezas |
| [Árbol, nodo 5877319628](https://www.openstreetmap.org/node/5877319628) | 24.1620340, -110.3137460 | Árbol registrado; no está identificado como palmera |
| [Piedras y Pájaros, nodo 9284265540](https://www.openstreetmap.org/node/9284265540) | 24.1634429, -110.3133879 | Arte público, tipo estatua; no dispone de geometría escultórica |
| [Parque Conchalito, nodo 6285201962](https://www.openstreetmap.org/node/6285201962) | 24.1346634, -110.3445919 | Existencia puntual; ese nodo no define el perímetro del parque |
| [Estacionamiento, nodo 920620957](https://www.openstreetmap.org/node/920620957) | 24.1499210, -110.3056610 | Existencia registrada; faltan límites y cajones |
| [Malecón, vía 462434216](https://www.openstreetmap.org/way/462434216) | 24.1642221, -110.3154026, punto derivado de línea | Banqueta nombrada, `surface=concrete`, `width=5`; dimensiones de esa etiqueta, no de todo el Malecón |
| [Memorial, vía 1365246290](https://www.openstreetmap.org/way/1365246290) | 24.1641019, -110.3165341, punto derivado | Monumento a Los Niños Héroes, obelisco de concreto según etiquetas; dimensiones desconocidas |
| Centro Cultural La Paz, `osm:node:958717770` | 24.1620477, -110.3154512 | Ubicación en `landmarks.json`; sin asociación a edificio ni fachada verificada |
| Catedral, `osm:way:155831066` | 24.1615961, -110.3128991, punto derivado del enriquecimiento | Lugar asociado a edificio; modelo local con dimensiones estimadas, no levantamiento arquitectónico |

Los nombres, direcciones y coordenadas de POI no constituyen permiso para reproducir fotografías, marcas comerciales o esculturas. Para los hitos, comenzar con representación esquemática y referencias con permisos identificados; no descargar automáticamente imágenes de terceros.

## 6. Qué aporta cada fuente y qué falta descargar

### OpenStreetMap

Ya ofrece en los archivos puntos, líneas, nombres y etiquetas útiles. Ampliar consultas acotadas podría recuperar información nueva o actualizada de mobiliario, cruces y superficies; **cantidad adicional desconocida**. Para los 28 puntos de control de semáforos habrá que resolver lateral, dirección y relación con la intersección; no colocar un poste dentro del asfalto solo porque el punto OSM cae sobre el eje. La [documentación de semáforos](https://wiki.openstreetmap.org/wiki/Tag:highway=traffic_signals) admite distintas convenciones de representación.

Las etiquetas [`sidewalk`](https://wiki.openstreetmap.org/wiki/Key:sidewalk) indican presencia y lado respecto a la dirección de una vía; no siempre trazan su geometría. [Simple 3D Buildings](https://wiki.openstreetmap.org/wiki/Simple_3D_Buildings) documenta pisos, alturas, cubiertas y materiales. Hay que leer el dato local, no suponerlo por estar permitido en el esquema.

Precisión: variable por edición, fuente de imagen y colaborador. No se ha medido error horizontal local ni existen tolerancias métricas certificadas en este inventario. Muchos decimales no garantizan centímetros de precisión.

### INEGI

Las manzanas existentes sirven para exclusiones y contexto espacial; DENUE aporta nombre, actividad SCIAN, coordenadas y referencias de domicilio. Ninguno proporciona la fachada exacta. El archivo de manzanas inspeccionado contiene claves geográficas y población/vivienda, **no columnas de ubicación individual de árboles o luminarias**.

Como adquisición futura, el producto [Características de las Localidades y del Entorno Urbano 2020](https://www.inegi.org.mx/rnm/index.php/catalog/941) documenta observaciones por frente de manzana; su [diccionario](https://www.inegi.org.mx/rnm/index.php/catalog/941/data-dictionary/F1) incluye disponibilidad de banqueta, árboles y alumbrado. Es evidencia de disponibilidad a esa escala y fecha, no coordenadas de cada poste. Habría que descargar el subconjunto de La Paz, enlazar claves y comprobar granularidad y correspondencia con la edición de manzanas. No se ha contado cobertura local de ese producto adicional. No se afirma que sea la edición más reciente existente.

Precisión: conservar CRS y metadatos de cada producto. Las manzanas no son planos de ingeniería ni predios catastrales. Para DENUE, la asociación geométrica se debe revisar cuando puntos y contornos discrepen; no asignar una precisión uniforme inventada.

### Overture Maps

Las huellas existentes ya son suficientes para la primera prueba visual. Overture distingue edificios y partes; la huella puede representar el techo visto desde arriba. [Su guía oficial](https://docs.overturemaps.org/guides/buildings/) explica la combinación de fuentes, incluyendo Microsoft y Google, con prioridad de OSM. En V, el archivo local contiene 30,054 registros cuyo origen principal es Microsoft ML Buildings, 38,834 Google Open Buildings y 5,816 OSM. No deben sumarse otra vez como construcciones independientes.

La descarga adicional razonable sería solo la franja occidental faltante y, si se necesita, Places para los sectores de expansión. Conteos nuevos y ganancia neta todavía no medidos. `confidence`, actividad y categoría requieren filtros; los 3,055 POI descargados no se deben activar todos como comercios confirmados. Tampoco hay evidencia de que descargar `building_part` vaya a resolver las fachadas normales: primero consultar presencia local y atributos.

### Microsoft Global ML Building Footprints

El [repositorio oficial](https://github.com/microsoft/GlobalMLBuildingFootprints) publica polígonos por particiones; algunas estructuras tienen alturas estimadas y los valores ausentes pueden codificarse como -1. No aporta escaparates, ventanas ni texturas. La calidad y antigüedad varían; no existe aquí una evaluación independiente de precisión en La Paz.

No se descargó una capa independiente ni se atribuye un número de registros locales a esa capa. Solo tendría prioridad si un piloto acotado demuestra huecos relevantes que no estén ya cubiertos por Overture/OSM. Comparar intersección de huellas y procedencia antes de añadir geometría. Contar registros globales no informa la cobertura útil de nuestro mapa.

### Otra fuente compatible: Wikidata

Puede aportar identificadores, coordenadas y relaciones de hitos culturales para contrastar nombres y enlazar evidencia. Sus [datos estructurados se publican como CC0](https://www.wikidata.org/wiki/Wikidata:Licensing). No se descargó ni contó un subconjunto local; es complemento documental, no sustituto de contornos ni modelos. Imágenes de Commons enlazadas desde Wikidata tienen licencias propias; CC0 de los datos no las cubre.

## 7. Licencias y uso offline

| Fuente | Condiciones relevantes para la integración propuesta |
|---|---|
| OSM | ODbL: atribución y obligaciones sobre bases derivadas al distribuirlas/usar públicamente sus resultados. Mantener origen y licencia de los datos; no asumir que esto licencia automáticamente código o arte propio. [Copyright oficial](https://www.openstreetmap.org/copyright) y [directrices para juegos y simulaciones](https://osmfoundation.org/wiki/Attribution_Guidelines#Computer_games_and_simulations). |
| Overture Buildings | Tema publicado bajo ODbL; conservar procedencias y atribuciones aplicables. [Guía de edificios](https://docs.overturemaps.org/guides/buildings/) y [atribución](https://docs.overturemaps.org/attribution/). |
| Overture Places | Licencia por fuente: el archivo local declara CDLA-Permissive-2.0, Apache-2.0 y CC0. La mezcla incluye Foursquare; no marcar todo Places como ODbL ni todo como CC0. Retener `sources`, textos y avisos correspondientes. [Detalle oficial por fuente](https://docs.overturemaps.org/attribution/#places). |
| INEGI, manzanas y DENUE | Libre uso, incluida explotación comercial; conservar metadatos, dar crédito de producto/fecha e identificar transformaciones sin atribuirlas al Instituto. [Términos oficiales](https://www.inegi.org.mx/inegi/terminos.html). |
| Microsoft independiente | README actual indica CDLA Permissive 2.0, cuya distribución de datos requiere acompañar el texto de licencia. Existe una discrepancia con la página de atribución de Overture, que referencia Microsoft bajo ODbL. Fijar edición y licencia del artefacto que se descargue; no relicenciar el extracto Overture existente por la licencia actual del proveedor. [README](https://github.com/microsoft/GlobalMLBuildingFootprints#license), [LICENSE](https://github.com/microsoft/GlobalMLBuildingFootprints/blob/main/LICENSE), [CDLA 2.0](https://cdla.dev/permissive-2-0/). |
| Wikidata | CC0 para datos estructurados; otras páginas y medios tienen condiciones independientes. [Política](https://www.wikidata.org/wiki/Wikidata:Licensing). |

La propuesta usa paquetes locales precalculados y no necesita un servicio de mapas durante la partida. Mantener junto al paquete la lista de fuentes, edición, recorte, hashes y avisos; actualizar créditos cuando se incorporen nuevas fuentes. Esta investigación no cambia los créditos existentes ni certifica todavía el cumplimiento completo de una distribución comercial.

## 8. Propuesta visual para edificios normales

### Primera prueba: variedad legible con coste acotado

1. **Color por edificio:** crema, arena, terracota, turquesa apagado y violeta; variación determinista por ID. El violeta nocturno actual tiende a uniformar fachadas. Revisar su modulación para conservar variedad sin sacar al edificio de la iluminación del juego. Son decisiones artísticas, no colores reales salvo etiqueta contrastada.
2. **Separar base, pared y coronamiento:** zócalo sencillo, franja superior y pretil de techo plano cuando sea un arquetipo artístico permitido. Mantener los casos documentados de cubierta y no proclamar que todas las casas reales tienen techo plano.
3. **Ventanas y puertas con contraste:** planos opacos oscuros, marcos de bajo relieve o dibujados en un atlas pequeño compartido. Reservar emisión moderada para pocas ventanas y locales; evitar que todos los edificios parezcan carteles de neón.
4. **Arquetipos limitados:** residencial clasificado, local comercial validado y volumen genérico desconocido. Los desconocidos no se convierten automáticamente en tienda ni reciben nombres inventados. Solo variación arquitectónica decorativa.
5. **Detalle hacia la carretera:** elegir bordes a partir del contorno arcade efectivo y proximidad/orientación a vía, con límites de columnas y filas. Ajustar una sola ruta de fachadas nocturnas, reutilizando los dos lotes existentes; no reactivar en paralelo el detalle de `BuildingBuilder`.
6. **Lectura durante conducción:** ritmo de puertas, ventanas y zócalos ayuda al flujo óptico lateral. El neón debe acentuar accesos y esquinas sin competir con ruta naranja, checkpoints azules y accesos rosas a carreras.

No propongo texturas fotográficas, reflejos de pantalla, parallax, cristales transparentes superpuestos, sombras por ventana ni una luz por edificio. Un atlas estilizado original de hasta 1024×1024 sería una opción posterior a evaluar, no una dependencia obligatoria del piloto.

### Integración y límites de rendimiento propuestos

- Reutilizar extrusión, colisiones, terreno y carga existentes. Fachadas nuevas solo visuales: no expandir sus colisiones ni tocar el automóvil. El relieve de marcos debe quedar dentro de la envolvente de seguridad revisada, sin invadir asfalto, banquetas o accesos.
- Precalcular selección de bordes y variante por edificio fuera de la partida. Cachear la descripción visual por sector/versiones de mapa y arcade. Evitar volver a analizar todos los POI en runtime.
- Compartir materiales y atlas; incorporar detalles al lote de sector correspondiente. Reutilizar MultiMesh para objetos repetidos y dividirlo por sector para que el culling siga siendo útil.
- LOD propuesto para el piloto: fachada completa hasta 90 m, simplificada hasta 220 m y volumen existente más lejos. Son umbrales iniciales **sin medir**; probar bandas de transición y conservar siluetas para evitar saltos. No ocultar bruscamente edificios completos para ganar FPS.
- Presupuesto inicial propuesto: sustituir los dos lotes de decoración existentes, sin añadir superficies/materiales nuevos por edificio; limitar el primer arquetipo a la cantidad actual de filas/columnas y un borde principal. Subir el detalle solo si la medición lo permite.
- Mantener el reparto de trabajo de 1.5 ms del bucle, midiendo también lectura, construcción, subida de malla y eliminación. No hay garantía de presupuesto total únicamente por usar `await`.
- Aplicar alturas de terreno y bases de los edificios efectivos; no asumir Y=0 ni inventar desniveles. Si el modo del mundo aplana elevación, respetarlo. Proteger playas, parques y superficies libres existentes antes de cualquier relleno futuro.

### Prueba A/B propuesta, todavía pendiente

Usar mismo vehículo, semilla, cámara, FOV, resolución, renderizador, densidad de ciudad y posición/orientación. A = actual; B = fachadas piloto. Probar primero una vista fija y después el mismo recorrido, con aceleración, TURBO y BURST equivalentes. Mantener iguales los efectos de SF.3 para que el cambio de fachada sea la única variable.

Calentar la carga y registrar al menos tres pasadas por modo, separando carga fría y estable. Medir CPU y GPU si están disponibles, mediana/p95/p99 del tiempo de frame, draw calls, triángulos, memoria y picos al entrar/salir de sectores. Registrar hardware y número de sectores/edificios visibles. Comparar también pausas, carreras, mapa y vuelta al menú por la liberación de sectores.

Criterio provisional de aceptación: p95 estable dentro del presupuesto de 16.67 ms si la referencia ya lo alcanza, incremento p95 ≤5% respecto a A y ausencia de picos nuevos perceptibles al cargar. Si A no alcanza 60 FPS, declarar ese punto de partida y exigir además que B no empeore significativamente la experiencia; el piloto no demuestra 60 FPS en otros equipos. Estos son objetivos de la prueba, **no resultados obtenidos**.

## 9. Orden recomendado de implementación futura

| Etapa propuesta | Trabajo | Condición para continuar |
|---|---|---|
| Alta: piloto de fachadas | Un sector representativo, colores/zócalos/marcos y un arquetipo genérico, reutilizando lotes nocturnos | Aprobación visual y comparación A/B con coste documentado |
| Alta: geografía visible verificable | Tramos de banqueta del Malecón, cruces documentados y pocos árboles registrados; proteger áreas libres | Revisar asfalto arcade, apoyo de terreno y procedencia por registro; no desplazar evidencia silenciosamente |
| Alta: locales e hitos seleccionados | Aplicar categoría solo con asociación segura; revisar los 8 hitos existentes y el caso de `model_path` con overrides | No afirmar arquitectura real sin referencia; no convertir proximidad en asignación automática |
| Media: infraestructura adicional | Señales/semáforos con lateral revisado, áreas de parking y parques con polígonos válidos | Validar tipo, orientación y geometría; instancias agrupadas por sector |
| Media: más evidencia | Recorte INEGI entorno urbano, Places en expansión y franja Overture occidental | Medir ganancia neta; conservar edición, licencia y asociación espacial |
| Baja: reconstrucciones específicas | Esculturas reconocibles, alturas faltantes, fachadas singulares y contraste Microsoft independiente | Evidencia de forma/dimensiones o interpretación explícita y coste justificado |
| Fase E / decisión artística | Distribución decorativa de palmeras/lámparas y acabado definitivo | Identificarlas como ficticias y hacerlas regulables por calidad; no mezclarlas con la capa verificada |

No se propone introducir carreras, NPC, Pasaporte ni audio en estas etapas. El piloto puede tener encendido/apagado independiente del resto de SF.3 para revertirlo con facilidad.

## 10. Validaciones realizadas y límites de esta entrega

- Auditoría offline ejecutada correctamente y recuentos contrastados con el manifiesto urbano, enriquecimiento y estadísticas de arcade.
- Verificados hashes de los 541 sectores urbanos y 502 archivos de overrides arcade.
- Comprobada unicidad de IDs de edificios preparados y diferencia exacta de 55 edificios desactivados. Se conserva el desglose de alturas, procedencias, dominios, ejemplos y métodos de asociación en el JSON.
- El script verifica antes/después que sus 1,054 archivos de entrada no cambian. No genera edificios ni modifica datos geográficos.
- No hubo descarga cartográfica nueva ni medición de completitud contra un inventario de campo. No hay precisión horizontal local certificada ni un censo actualizado de establecimientos.
- No se ejecutó Godot para simular una mejora aún no implementada. No existen mediciones de FPS de las fachadas propuestas; los límites de rendimiento son criterios para el piloto futuro. Las pruebas previas de SF.3 no demostrarían el coste de este diseño nuevo.

La decisión pendiente es seleccionar el piloto visual y su sector de prueba. La recomendación es empezar por fachadas genéricas agrupadas, validar su legibilidad y coste, y después incorporar mobiliario únicamente donde la evidencia permita sostener su ubicación.
