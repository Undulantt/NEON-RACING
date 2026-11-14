# SF.3 — Mejora acotada de fachadas y recuperación de edificios

Fecha: 2026-11-13. Implementación solicitada después del informe `SF3_INVESTIGACION_URBANA.md`.

## Alcance elegido

Se priorizaron dos mejoras de impacto directo: recuperar contornos reales que faltaban y mejorar el acabado de las fachadas existentes. Se reutilizan datos locales y el sistema de sectores, sin reconstruir las carreteras, modificar la física del automóvil ni descargar nueva cartografía.

No se incorporaron NPC, tráfico, edificios inventados, monumentos nuevos ni un nuevo sistema de luces. Las lámparas y plantas decorativas anteriores conservan su carácter procedural; esta entrega no las convierte en elementos de ubicación verificada.

## Causa del fallo de generación

### UABCS y Tec de La Paz

Los polígonos OSM de los campus estaban incluidos en la máscara de protección para evitar colocar relleno ficticio en escuelas/universidades. El constructor aplicaba esa misma máscara a los edificios reales: **un contorno de techo dentro de la universidad se rechazaba por estar dentro de la universidad**.

Se confirmó en los archivos locales:

- Campus UABCS: OSM `way:137201460`; no había volúmenes urbanos dentro del recinto. La descarga Overture contiene 193 registros completamente interiores antes de los restantes filtros.
- Tec de La Paz: OSM `way:137201452`; tampoco había volúmenes dentro del recinto. La descarga Overture contiene 64 registros completamente interiores antes de los restantes filtros.

Un campus no es un edificio. No se extruyeron los recintos completos de aproximadamente 707,140 y 279,372 m². Se recuperaron únicamente contornos de construcciones OSM/Overture, manteniendo despejadas las áreas protegidas interiores, incluidas canchas, parques y estacionamientos.

### Soriana Forjadores

El contorno OSM `way:1495212806`, identificado como supermercado Soriana, ocupa aproximadamente 20,782 m². El importador antiguo de fase B (`build_environment.py`) admite hasta 15,000 m², por lo que lo descartó antes de que la ciudad híbrida pudiera recuperarlo desde esa lista OSM.

Además, la regla posterior que rechazaba cualquier intersección con zonas protegidas no distinguía una invasión sustancial de un contacto/solape mínimo en bordes de estacionamiento y pasos. La inspección encontró contactos de área nula y solapes inferiores a un metro cuadrado en esos bordes. Overture tampoco compensaba necesariamente las omisiones del importador anterior.

La recuperación lee el contorno original del XML, aplica el límite vigente de edificios reales de 25,000 m² y recorta los obstáculos en vez de descartar todo el edificio por un roce. Debe conservar al menos 85% del contorno para aceptarse. No se amplía ese límite para inventar una caja sobre toda la plaza.

Otro registro llamado Super Soriana (`way:1306713113`) está afectado por el límite geográfico del sector actual. Esta entrega no amplía ese límite ni promete importar todas las sucursales que tengan el mismo nombre.

## Resultado de la recuperación

| Lugar | Volúmenes añadidos | Evidencia de ubicación | Apariencia |
|---|---:|---|---|
| UABCS | 172 | Huellas OSM/Overture dentro del recinto OSM | Extrusión low-poly; altura aproximada cuando no hay dato |
| Tec de La Paz | 62 | Huellas OSM/Overture dentro del recinto OSM | Extrusión low-poly; altura aproximada cuando no hay dato |
| Soriana Forjadores | 1 | Contorno OSM original `1495212806` | Volumen comercial genérico, altura estimada de 7 m |
| **Total** | **235** | **22 sectores con adiciones** | **Sin afirmar reconstrucción arquitectónica exacta** |

Se examinaron 314 candidatos y se rechazaron 79 por límites geográficos, tamaño, áreas libres, carreteras o duplicados. En los campus, el fallback de altura es 6.2 m; pisos o altura de origen tienen prioridad cuando son válidos. Se conserva `height_estimated`, `source_id`, `sources`, `site`, `retained_fraction` y `architecture_verified=false`. No se añaden logos ni se reconstruyen fachadas comerciales a partir del nombre.

Los recuentos describen volúmenes aceptados del archivo local; no prueban que todos los edificios físicos del campus estén presentes, ni que las detecciones ML correspondan perfectamente a cada construcción actual.

## Integración mínima y reversible

`tools/build_sf3_recovery.py` genera un **complemento geográfico acotado** en `data/processed/urban/sf3_recovery/`. No regenera los más de 62 mil edificios existentes, el relieve ni el mapa. Los archivos crudos y los paquetes base permanecen intactos.

`UrbanChunkManager.gd` incorpora los sectores del complemento a su propio índice espacial. Cuando ya existe el sector, combina sus registros al leerlo; cuando no existe, usa el archivo complementario como sector nuevo. Se conserva un único gestor urbano, sus distancias de carga/descarga y la activación de colisiones próximas. Cada archivo se comprueba con SHA-256.

El complemento está vinculado a los hashes del mapa, asfalto arcade y manifiesto urbano base. Si esos datos cambian, se avisa y no se mezcla un complemento desactualizado. Volver a ejecutar la herramienta después de cambiar la cartografía. Los baselines B.6 y el piloto de relieve limitado mantienen sus datos de referencia; la recuperación se habilita para la ciudad plana y el relieve completo del juego.

La lectura de sectores se centralizó en `read_chunk()`. La usan tanto el constructor de edificios como `NightStyle` y el índice de exclusión de `CityFurniture`; así los postes y plantas existentes también evitan los edificios recuperados. No hay un lector paralelo que omita las nuevas construcciones.

Las bases de los edificios recuperados muestrean el mismo terreno que el automóvil. Se precalculan posiciones sobre el perímetro y una cuadrícula de 8 m; al cargar el sector se obtiene la cota real del modo activo. Base nivelada al máximo muestreado y cimentación hasta el mínimo menos 0.2 m. En modo plano, la misma ruta da altura de terreno cero. La carretera no se desplaza para acomodar un edificio.

También se corrigió la política de `build_urban_city.py` para futuras generaciones: las parcelas institucionales dejan de excluir huellas reales, mientras que el relleno ficticio continúa utilizando la máscara completa. `urban_protection.py` contiene esa distinción compartida con la validación. Las superficies explícitas de parques, canchas, agua y estacionamientos siguen protegidas.

El paquete base conserva sus estadísticas históricas. El complemento informa su inventario por separado y `city_manager.status()` expone `sf3_recovered_buildings`; no se debe interpretar el total base como el inventario combinado actualizado.

## Cambios visuales de bajo coste

- Modulación nocturna más clara para que se distingan los colores por edificio ya existentes, manteniendo el tono violeta del juego.
- Zócalos sencillos sobre los bordes que ya recibían detalle; una puerta genérica en el borde principal de edificios no comerciales.
- Parte de las ventanas existentes pasa a color oscuro en vez de estar siempre encendida. Esto aporta contraste sin crear más ventanas.
- Se mantienen las cornisas, locales y franjas de neón anteriores, sus límites y el presupuesto de trabajo repartido entre frames.

Toda la decoración utiliza los lotes de geometría sólida/luminosa ya previstos en `NightStyle`. No se añaden nodos por ventana, materiales por edificio, luces, transparencias o sombras nuevas. Algunos sectores antes no tenían geometría sólida decorativa; ahora su lote deja de estar vacío y por ello sí pueden aumentar las mallas y draw calls visibles. No se afirma coste cero.

Los nuevos detalles son cosméticos y no entran en la malla de colisión. Los edificios recuperados sí utilizan la carcasa geográfica normal y las reglas existentes de proximidad a la carretera. La decoración no convierte las categorías desconocidas en comercios ni inventa marcas o establecimientos.

## Configuración y comparación

`config/sf3_city_life.json` tiene dos interruptores independientes:

- `facades_enabled`: acabado visual nuevo.
- `recovery_enabled`: recuperación geográfica.

Con la configuración entregada, ambos están activos al iniciar una nueva partida. Para comparar las fachadas anteriores, iniciar Godot con `-- --sf3-facades-original`; los 235 edificios recuperados permanecen en ambos modos, evitando confundir más edificios con un cambio de acabado. Reiniciar la escena al cambiar esta configuración. `--sf3-no-recovery` es una opción de diagnóstico para volver temporalmente al inventario base.

No se sobrecargó el panel SF.3 existente con opciones de generación que exigirían recargar sectores mientras se conduce. Los ajustes de asfalto, referencias y luces del panel conservan su función.

## Pruebas reproducibles

Desde la raíz del proyecto:

```powershell
.\.venv-urban\Scripts\python.exe tools/build_sf3_recovery.py
.\.venv-urban\Scripts\python.exe tools/validate_sf3_recovery.py
```

Con el ejecutable Godot 4.7.2 del proyecto:

```text
--headless --path . --script res://tests/godot_sf3.gd
--headless --path . --script res://tests/godot_sf3_city_life.gd
--headless --path . --script res://tests/godot_sf3_city_life.gd -- --flat-world
--path . --script res://tests/godot_sf3_city_life.gd -- --render-life --sf3-facades-original
--path . --script res://tests/godot_sf3_city_life.gd -- --render-life
```

La prueba de integración inicia desde menú, selecciona VECTOR, entra a modo libre, prepara puntos sobre calles existentes próximos a los tres lugares, carga/decora sectores, comprueba IDs y bases contra el terreno, fuerza desplazamientos/descargas y regresa al menú. El test renderizado usa cámaras fijas elevadas y no es una carrera ni un benchmark de conducción.

El validador independiente contrasta geometría con XML/GeoJSON de origen, triangulación, hashes, cobertura retenida, duplicados y máscaras de asfalto/áreas libres. El resultado está en `docs/sf3_recovery_data_validation.json`. Las pruebas existentes de SF.3 comprueban 85 condiciones, incluidos los tres perfiles y el comportamiento independiente de presentación.

## Limitaciones conocidas

- Los 235 volúmenes no son modelos arquitectónicos exactos. No se investigaron texturas reales ni fachadas individuales.
- La cobertura geográfica sigue siendo la del sector actual; no se amplió La Paz ni se completaron todos los edificios que falten en otras zonas.
- Las cimentaciones niveladas sobre el relieve pueden quedar altas en parcelas grandes: en las vistas de prueba se midieron diferencias máximo/mínimo de aproximadamente 8.22 m en Soriana, 5.58 m en el Tec y 5.47 m en UABCS. Son diferencias del terreno compartido, no alturas de edificio medidas. Sigue pendiente un acabado específico de cimentaciones/terrazas; no se alteró el terreno para ocultarlo.
- La vista de prueba es estática y no prueba 60 FPS sostenidos durante toda la conducción ni en otro hardware. Las colisiones de recuperación están geométricamente libres de asfalto; el comportamiento de manejo conserva el controlador y parámetros anteriores.
- El modo histórico B.6 y el piloto de relieve limitado no reciben el complemento. El juego normal con relieve completo y el modo plano sí lo cargan.

Las capturas de evidencia están en `docs/evidence/sf3_soriana_*`, `sf3_tec_*` y `sf3_uabcs_*`. «Original» en esos nombres compara el acabado anterior **con la misma recuperación geográfica activa**.

## Resultados de la comparación renderizada

GPU: NVIDIA GeForce RTX 4060 Ti. Resolución 1280×720, Compatibility y VSync desactivado. Dos segundos de calentamiento y 240 frames por vista/modo, con la misma recuperación activa.

| Lugar | Mediana anterior → nueva (ms) | p95 anterior → nuevo (ms) | Draw calls anteriores → nuevos |
|---|---|---|---|
| Soriana Forjadores | 2.658 → 2.671 | 3.243 → 3.504 | 322 → 334 |
| Tec de La Paz | 2.328 → 2.391 | 2.806 → 2.776 | 397 → 416 |
| UABCS | 1.939 → 1.958 | 2.201 → 2.345 | 342 → 363 |

El coste incremental observado del p95 fue como máximo 0.261 ms y todas las vistas quedaron por debajo de 16.67 ms. Se acepta este piloto con un presupuesto absoluto de aumento de 1 ms, coherente con la comparación previa de SF.3. El objetivo preliminar del informe de ≤5% de aumento relativo del p95 **no se cumple en todas las vistas**: Soriana sube aproximadamente 8% y UABCS 6.5%, con tiempos absolutos bajos. No se oculta esa diferencia ni se presenta como garantía de 60 FPS durante conducción. Véase `sf3_city_life_comparison.json`.

La suite antigua `test_urban.py` pasa 5 de 6 pruebas. La restante falla antes de comprobar geometría por una discrepancia histórica del hash de `ArcadeCar.gd`; el fallo se reprodujo ejecutando el validador de HEAD anterior a estos cambios. El controlador actual conserva el hash capturado al comenzar esta recuperación y no se reescribieron manifiestos o migraciones para ocultar ese fallo. Evidencia: `sf3_city_life_legacy_baseline.json` y `sf3_city_life_urban_tests.log`.

Resultados finales de integración: 13,473 comprobaciones en relieve completo, 13,483 en modo plano y 48 en la regresión existente de navegación/carreras, todas aprobadas y con logs sin errores de scripts. Los conteos incluyen verificaciones repetidas por edificio y muestra de terreno, no miles de casos independientes. La regresión de carreras confirma también recuperación con demora de tres segundos y retorno al mundo libre.
