# Banquetas y mobiliario urbano

## Resultado

El mundo nocturno compartido por modo libre y carreras construye primero las
banquetas del sector y después coloca los recursos de `assets/3D/`:

| Recurso | Uso | Altura visual normalizada |
|---|---|---|
| BigPalm.glb | Vegetación urbana, con presencia prioritaria en el Malecón | 13 m |
| Palm.glb | Vegetación urbana, con presencia prioritaria en el Malecón | 9.5 m |
| Chair.glb | Bancas únicamente en el corredor Paseo Álvaro Obregón del Malecón | 1.15 m |
| LightPole.glb | Sustituye la farola procedural del mundo nocturno de ciudad | 9 m |

Se mantienen árboles procedurales como variedad. Los GLB no se modifican; sus
atlas JPEG de 128 × 128 extraídos por Godot y sus `.import` se versionan junto
a los modelos. Las alturas son ajustes artísticos, no dimensiones levantadas.
El piloto nocturno histórico aislado conserva su ruta anterior; las escenas
de juego actuales utilizan `NightCity.gd` y el sistema compartido.

## Datos y límites geográficos

No se descarga ni reconstruye el mapa. `tools/build_streetscape.py` utiliza
la red OSM ya procesada y el ancho arcade vigente de cada segmento. Conserva
los hashes de 1,072 entradas, incluyendo edificios efectivos de OSM/Overture,
overrides arcade y los edificios recuperados de los campus. Resta sus
contornos, el asfalto y las superficies protegidas de parques, playas, agua,
estacionamientos y otros espacios abiertos. Las manzanas INEGI son referencia
estadística del proyecto; no se reinterpretan como límites de banqueta.

El XML OSM contiene evidencia parcial de `sidewalk*` y `footway=sidewalk`.
Se conserva su inventario en `osm_sidewalk_evidence`; se respetan los atributos
laterales de las vías motorizadas y `sidewalk=no`. **La geometría visible se
deriva del borde vial ensanchado, no copia un levantamiento de banquetas.**
Los ejes peatonales se conservan como evidencia, sin trasladarlos sobre el
asfalto arcade ni generar otra banqueta superpuesta por cada eje.

Ancho estimado: 2.6 m por lado, 4.2 m en el corredor del Malecón; separación
horizontal mínima de 0.22 m respecto al asfalto y 0.25 m de edificios. Las
intersecciones y accesos que sí figuran como vías quedan libres al restar
todo el asfalto, incluidos servicios. No se conocen todos los accesos privados.
Los obstáculos o falta de espacio pueden estrechar, cortar o eliminar un tramo.

**No se generan camellones nuevos:** el extracto no aporta vías con etiquetas
explícitas de isleta/camellón bajo las reglas del generador. Dos calzadas
paralelas no se toman como prueba de un camellón construido. Las banquetas
estimadas siguen bordes libres; no alteran la calzada ni añaden obstáculos
centrales físicos.

Postes, bancas y palmeras son **decoración estimada**, no posiciones individuales
verificadas. Cada registro conserva vía OSM de referencia, posición métrica,
orientación, pertenencia al corredor y `placement=decorative_estimate_on_derived_sidewalk`.
Las bancas prefieren el lado más próximo al mar preparado; no son un inventario
municipal. La colocación exige espacio en la banqueta, separación entre objetos
y distancia a edificios. En ejecución también se exige terreno cargado con
normal suficientemente vertical; se descartan posiciones sin apoyo seguro.

## Construcción y rendimiento

- `SidewalkBuilder.gd` lee solo el sector solicitado. Pavimento violeta mate,
  borde bajo de 16 cm y una línea cian estrecha de acento; dos mallas por sector.
  Las alturas se muestrean en el relieve existente. Los parches demasiado
  inclinados se omiten. La banqueta es visual: **no tiene colisión elevada**;
  se conserva el comportamiento físico al salir de la calzada.
- Los polígonos se simplifican dentro de su máscara válida, se triangulan offline
  y se almacenan comprimidos en `data/processed/streetscape/chunks/*.json.gz`
  (aproximadamente 24.3 MB decimales en total). No se carga toda la geometría en
  memoria al conducir. El manifiesto y cada sector se verifican mediante SHA-256.
- `UrbanAssetLibrary.gd` aplica las transformaciones locales de Blender y agrupa
  las superficies por material una vez por mundo. Tronco y hojas conservan su
  posición relativa y el atlas original. `CityFurniture.gd` utiliza MultiMesh
  por modelo/material/sector, con hasta dos lotes por recurso.
- Topes por sector: 24 postes, 18 plantas, 10 bancas. Separación mínima de 6 m
  entre objetos; fase determinista sobre segmentos reales cada 28 m como referencia.
  Vegetación y bancas se dibujan hasta 280 m, postes hasta 360 m. Sin sombras
  adicionales ni OmniLight por farola: se reutilizan los cuatro pools sobre asfalto.
- SF.3 modifica únicamente `LampEmitterBatch`; el cuerpo del poste conserva el
  atlas y su material. La emisión fija tiene un acento rosa acorde al juego.
- El trabajo geométrico se reparte en reanudaciones con referencia de 1.5 ms;
  descompresión, lectura y subida de mallas siguen siendo operaciones puntuales.
  Se comparte el propietario urbano: descarga, visibilidad de ciudad y colisiones
  cercanas siguen el gestor existente. Los objetos sólidos usan formas simples
  fuera del asfalto; no se modifican las físicas ni estadísticas de los coches.

El dataset preparado contiene 522 sectores, 769,980 triángulos de pavimento,
10,993 postes, 2,772 BigPalm, 2,721 Palm, 2,725 árboles y 71 bancas. En el
corredor del Malecón hay candidatos para 55 BigPalm, 49 Palm, 109 postes y las
71 bancas. Son candidatos globales, **no objetos simultáneamente cargados**;
los filtros de terreno pueden reducir las instancias visibles.

## Pruebas y reproducción

```powershell
.venv-urban/Scripts/python.exe tools/build_streetscape.py
godot --headless --path . --editor --import --quit
godot --path . --script res://tests/godot_streetscape.gd -- --passport-test --capture-streetscape
```

Godot 4.7.2 Compatibility: **123 comprobaciones aprobadas**, sin errores de
importación/ejecución. Se comprueban las cuatro normalizaciones y presupuestos
de materiales, presencia de ambas palmeras y bancas en el Malecón, exclusividad
de bancas, apoyo del coche, SF.3 sin reemplazar el material del poste, ocultación
de ciudad, descarga y nueva generación al trasladarse a Forjadores, conducción,
entrada a carrera con rivales y retorno al menú. Los hashes de conducción,
habilidades, perfiles y cartografía permanecen iguales.

El generador verifica cero área de solapamiento con asfalto, edificios y
superficies protegidas, además de los hashes de entrada sin modificaciones.
No se prueba mediante capturas cada cuadra de la ciudad.

Comparación estática A/B/B/A a 1280 × 720, VSync desactivado, RTX 4060 Ti,
nueve sectores decorados, 150 frames por muestra: medias sin nueva geometría
2.356/2.486 ms, con geometría 2.419/2.461 ms; diferencia media aproximada
**+0.019 ms**, 163 frente a 183 draw calls. No se observó una regresión relevante
en esa vista. No es una garantía de 60 FPS en otros equipos ni una medición de
recorrido completo; todavía conviene evaluar personalmente la ciudad al conducir.

Informes y capturas locales: `.local/artifacts/streetscape_validation.json`,
`streetscape_build.log`, `streetscape_import.log` y `evidence/streetscape_*.png`.
Las preferencias y el pasaporte se aíslan durante la prueba.

Para cambiar distribución/ancho se edita el generador y se regenera el dataset;
para escalar modelos se ajusta `UrbanAssetLibrary.HEIGHTS`. El alto del borde
visible está en `SidewalkBuilder.HEIGHT` y debe mantenerse consistente con los
16 cm de apoyo de mobiliario y los metadatos del generador. Al exportar un PCK,
incluir también `data/processed/streetscape/*.json` y `**/*.json.gz` en los
filtros de datos no importados, junto a los datasets offline existentes.
