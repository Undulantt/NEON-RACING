# B.7-R — Auditoría y propuesta de relieve

Fecha: 2026-10-26. Estado histórico: estrategia validada por el usuario; implementación y pruebas en [PHASE_B7R.md](PHASE_B7R.md). El texto siguiente conserva la auditoría previa.
Base Git inspeccionada: `be1de562a69be4518646b9769df2d1c567c7e1e3`. Árbol inicialmente limpio.

## 1. Estado real del proyecto

La fuente de verdad es el código y los manifiestos actuales. La documentación de C.5 describe versiones anteriores y no debe usarse como inventario vigente.

| Componente | Estado comprobado | Consecuencia |
|---|---|---|
| Conversión | `tools/map_core.py:gps_to_local`, radio 6371000 m, origen 24.159/-110.3195; X este, Z sur | Reutilizar exactamente; no sustituir por UTM en runtime |
| Selección | Centro, norte y sur; envolvente [24.09,-110.342,24.185,-110.281], unión de bloques y recorte sur | Recortar DEM con la misma región, añadiendo halo de procesamiento |
| Grafo | 13.092 tramos, 10.597 nodos; tags originales en archivos locales | Resolver cotas antes de que World borre tags del objeto runtime |
| Asfalto activo | World sustituye los chunks originales por `arcade_layout.json`; 537 sectores, 55.864 triángulos en arranque | Integrar el asfalto ensanchado; cambiar solo `map_core` no basta |
| Carreteras | `RoadBuilder.gd`: ArrayMesh y ConcavePolygonShape3D con los mismos triángulos; Y=0, normales UP | Exportar XYZ y normales calculadas; conservar capas |
| Streaming vial | 256 m; carga 1100 m, descarga 1400 m, precarga 300 m; hasta dos cargas por paso | Reutilizar partición y prioridad; observar ráfagas de precarga |
| Streaming urbano | 519 sectores, 59.635 edificios; carga 650 m, descarga 850 m, colisiones 240 m; una carga ordinaria por frame | Aplicar cotas a huellas finales después del recorte arcade |
| Recuperación | RoadChunkManager retiene soporte en spawn y posición segura | Extender la misma garantía al terreno |
| Plataforma | `build_clipped_limits`: colisión poligonal Y=0, visual Y=-0.1; barreras de borde de 3 m | Sustituir por área solo al validar reemplazo; adaptar barreras a cotas |
| Geografía | Una malla global, alturas constantes; mar visual Y=-0.04; plataforma física bajo agua | Separar mar del terreno y adaptar superficies abiertas |
| Edificios | Muros desde -0.1, techos a height_m; modelos especiales y ventanas con Y fija | Trasladar conjunto por edificio, incluyendo colisión y detalles |
| Automóvil | CharacterBody3D, caja 1.8×1.2×4.1; snap 0.35 m, límite 42°; sin suspensión física de ruedas | No migrar a VehicleBody ni recalibrar conducción sin mediciones |
| Dependencias planas | road_hit raycast mundial [1.8,-0.5]; spawn y recuperación Y=.67; recuperación si Y<-4 | Hacer consultas relativas a cota/posición antes del piloto |

Capas físicas actuales: asfalto 1, suelo 2, edificios 4, límites 8, coche 16. F8 se preservará mediante el flujo actual de activación urbana; F9 conserva etiquetas. Cámara SpringArm sigue al coche en altura, pero debe probarse en crestas y con fachadas elevadas. Partículas, marcas, feedback y utilidades de pruebas también deben auditar sus alturas al integrar.

Hashes SHA-256 de entradas auditadas:

- Mapa: `1f193ceac94a730853cd1c73cf6f55f83d30d82b245b42e4877037c724f6f4fb`.
- Asfalto arcade: `b9f65101e436c89a6ed24481a52d9ac7cc63570fa5cb0f3dc0351f3af3ecdc92`.
- Ciudad: `3c734734b6aff04b90c06b29b29d7d7195660e880def121f5d209a0e9e65b55f`.

## 2. Fuente recomendada y verificación pendiente

**Recomendación: CEM 4.0 como primera opción de terreno; Copernicus GLO-30 como alternativa operativa si no se consigue un recorte oficial utilizable.** No existe todavía un raster descargado y validado en esta fase; la recomendación no equivale a comprobar muestras locales.

### INEGI CEM 4.0

La [ficha oficial del producto 794551151600](https://www.inegi.org.mx/app/biblioteca/ficha.html?upc=794551151600) y su [API pública de ficha](https://www.inegi.org.mx/app/api/productos/interna_v2/ficha/datos?upc=794551151600&lang=false), consultadas en esta auditoría, confirman edición 2025, temporalidad 2024, terreno continuo de 15 m y alturas sobre nivel medio del mar. La fuente integra información radar y aportes LiDAR/fotogramétricos. Es una mejor candidata inicial para suelo urbano que un DSM con edificios.

La API ofrece un ZIP nacional de 8,9 GB: no se ha descargado, dado que excede el área necesaria. El [visor oficial](https://www.inegi.org.mx/app/geo2/elevacionesmex/) ofrece selección por área y resolución; falta comprobar que permita obtener específicamente versión 4.0 para nuestra selección. No se debe etiquetar una descarga del visor como 4.0 sin metadatos.

La ficha devuelve datum y proyección nulos y no publica en esa respuesta una exactitud vertical del 4.0. Por tanto quedan pendientes CRS del raster, geoide/datum vertical específico, unidades codificadas, NoData, geotransformación, cobertura efectiva y precisión. No extrapolar errores del CEM 3.0 ni usar 15 m como precisión vertical. No adoptar metadatos de copias comunitarias como verificación oficial.

Los [términos de libre uso INEGI](https://www.inegi.org.mx/inegi/terminos.html) permiten productos derivados y redistribución bajo sus condiciones de atribución y declaración de modificaciones. Guardar texto/URL de licencia y atribución con el snapshot elegido; no atribuir al INEGI los ajustes de transitabilidad.

### INEGI LiDAR

El visor distingue terreno/superficie, 5/1,5 m y origen LiDAR/fotogrametría. Eso no demuestra cobertura LiDAR del mapa. Falta intersectar el índice de teselas con los bloques vigentes y comprobar fichas y archivos específicos. No se elige LiDAR para el piloto sin esa evidencia. Mayor resolución aumenta almacenamiento y procesamiento y no garantiza mejor continuidad entre campañas.

### Copernicus GLO-30

La [documentación oficial](https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM) confirma cobertura mundial, grilla DGED de 1 segundo de arco, WGS84-G1150 horizontal, EGM2008 vertical y unidades métricas. Por la envolvente, la celda candidata es N24/W111; falta comprobar el archivo y su máscara en el área. Es DSM: puede incluir edificios y vegetación; no representa automáticamente suelo desnudo. La especificación publica error vertical absoluto <4 m al 90%; no es una medición de La Paz ni una garantía por muestra.

GLO-30 permite distribución con licencia y avisos propios; conservar el aviso exacto para datos modificados que publica el proveedor. No tratar su licencia como CC0. El acceso CDSE requiere registro y condiciones de usuario. No se han comprobado credenciales ni descargado teselas en esta auditoría.

**Cierre obligatorio de R.1:** adquirir solo selección+halo, verificar valores válidos en cada zona terrestre, guardar fuente/fecha/hash/CRS/datum/unidades/licencia, registrar min/max/NoData y comparar perfiles de vías. Si se cambia de fuente entre regiones, convertir primero referencia vertical y medir diferencias; no mezclar datums con un offset arbitrario.

## 3. Diseño recomendado

### Procesamiento fuera del juego y dos superficies explícitas

Añadir un pipeline derivado, sin sobrescribir fuentes ni archivos actuales, bajo `data/processed/relief/` y sus scripts de preparación. Un manifiesto enlazará hashes de DEM, mapa, asfalto arcade, ciudad, configuración y versiones de herramientas. Modo de depuración seleccionará plano o relieve al iniciar; evitar conmutación en caliente de colisiones durante la conducción.

Mantener separadas la altura geográfica original y la superficie jugable ajustada. Un servicio de elevación permitirá consultar ambas, con resultado válido/fuera de cobertura/NoData y procedencia medida/interpolada/estimada/ajustada. Interpolación de raster para preparar el modelo; para consultas físicas del mundo, interpolación sobre la triangulación exportada. Una bilineal independiente no coincide exactamente con los triángulos de colisión.

Invertir analíticamente `gps_to_local` para localizar muestras del DEM, transformando al CRS de entrada si procede. Esto conserva la proyección existente. Propuesta vertical: Y=altura ortométrica en metros, origen vertical 0, mar de referencia Y=0, sin exageración. Es referencia de juego coherente con el DEM, no un modelo de marea local. No confundir altura elipsoidal y ortométrica. Si se usa otra transformación, guardarla explícitamente.

NoData terrestre que afecte conducción debe invalidar el bake o usar una corrección declarada; nunca convertirse silenciosamente a cero. Mar conocido por máscara costera puede tener una política explícita distinta. Usar halo antes de filtrar/recortar evita artefactos en bordes.

### Vías e intersecciones

Conservar ejes, anchos arcade y grafo. Preparar perfiles longitudinales con muestras adicionales, suavizado controlado y cotas compartidas en nodos conectados. Ajustar transiciones de pendiente sin aplanar corredores completos. Un cruce geométrico sin nodo no crea conectividad.

Derivar una superficie vial continua de los perfiles y la unión arcade. Subdividir su interior y sus bordes para evitar triángulos largos que ignoren el relieve. La geometría debe incorporar restricciones de perfiles y zonas de intersección; asignar DEM por vértice de los triángulos actuales es insuficiente. Resolver cruces del mismo nivel conjuntamente con aproximaciones compatibles; en calzadas próximas sin conexión, imponer continuidad geométrica donde realmente comparten superficie sin inventar aristas de navegación.

Triangular antes de dividir o utilizar una subdivisión global canónica y recorte conforme: los dos lados de cada sector deben compartir la misma secuencia XYZ de borde. Igualar solo alturas en extremos no elimina T-junctions ni grietas. Normales compartidas obtenidas con halo; render y colisión usan exactamente la misma superficie.

Excluir del terreno la huella vial física de superficie o construir cortes/cunetas compatibles con sus bordes; no dejar una malla de terreno más alta atravesando el asfalto. Una simple separación vertical no resuelve diferencias causadas por suavizado. En puentes no abrir huecos indiscriminadamente en el suelo que pasa debajo.

**Riesgo concreto ya presente:** cuatro ways de puentes de Forjadores están admitidos temporalmente planos y el inferior 660516292 se difiere. Conservar esa política inicialmente. No liberar el paso inferior ni unir estratos en la unión 2D. Incorporar estructura elevada requiere tratamiento por nivel y verificación de gálibo; un DEM no proporciona altura de tablero. El primer piloto evitará esos cruces y se documentará la limitación hasta resolverla.

### Terreno, edificios, costa y streaming

Exportar mallas de terreno por sectores de 256 m, recortadas por los bloques y el límite sur. Empezar con separación de muestras aproximada 16 m, evaluable contra el DEM; refinar cerca de vías y recortes. Remuestrear a 16 m no añade precisión al dato. Conservar la misma triangulación para colisión. Evaluar recursos binarios precalculados tras medir el piloto; no convertir toda la ciudad primero ni introducir un compilador externo obligatorio.

Reutilizar el patrón de manifiesto, distancia XZ, histéresis y cola de cargas; no heredar sin mediciones todos los radios urbanos. Precargar soporte antes del movimiento y retener vecindarios de recuperación. Evitar que una vuelta/teletransporte espere carga asíncrona para obtener suelo. Sustituir plataforma y terreno por máscaras disjuntas en el piloto: no superponer suelo plano y nuevo terreno. Bordes de piloto requieren transición derivada, o una escena de validación aislada; no crear un escalón contra la ciudad plana.

Calcular cimentaciones sobre huellas **finales**, después de overrides y recortes arcade. Mantener techo horizontal, altura y escala; escoger cota de plataforma y generar zócalo hasta el suelo. Muestrear interior y bordes, incluyendo patios: sus huecos no deben rellenarse. Limitar diferencias admisibles y reportar casos extremos para corrección; nivelar un cerro entero bajo una construcción no es aceptable. Trasladar modelos especiales, detalles de fachada, techos, colisiones y etiquetas juntos.

Reutilizar `water_geometry_xz` y litoral actuales. Agua marina a referencia 0, terreno terrestre recortado y ajustado localmente en una franja documentada; conservar accesos y cotas de costa transitables. Lagos/estanques requieren su propia cota. El DEM no provee batimetría: fondo bajo mar, si se necesita, será estimado y marcado. La plataforma actual aporta colisión bajo agua: decidir y probar una política de conducción/recuperación costera antes de retirarla.

### Coche y efectos

Cambios necesarios primero: raycasts relativos a la posición/cota esperada, spawn y recuperación basados en superficie vial, seguridad respecto a terreno y límites elevados. Mantener soporte cargado durante recuperación. Probar la caja de colisión sobre crestas; no interpretar el coche actual como vehículo con suspensión física.

Conservar parámetros de conducción. Primero probar subida/bajada, frenado, curvas inclinadas, snap y cambios de normal. Solo añadir respuesta tangencial a gravedad o adaptar orientación visual si las mediciones muestran una carencia del controlador; CharacterBody no reproduce automáticamente toda la dinámica de un vehículo. Revisar ruedas, partículas y marcas contra superficie. Cambiar gravedad o grip para disimular un escalón geométrico queda descartado.

## 4. Alternativas y costes

| Alternativa | Ventaja | Coste/riesgo | Decisión |
|---|---|---|---|
| ArrayMesh sectorizado derivado offline | Reutiliza capas, recortes, huellas y pruebas; render y física idénticos | Más complejidad de bake conforme y tamaño de datos | Recomendada |
| HeightMapShape3D regular | Representación compacta y nativa | Difícil excluir huellas viales y respetar recorte irregular; huecos y orientación requieren ensayo | Probar solo si colisión de malla resulta costosa |
| Terrain3D | LOD y herramientas de terreno | Dependencia nativa y compatibilidad aún no ensayada con Godot 4.7.2/GL Compatibility; no resuelve por sí sola vías ni edificios | No introducir en esta fase |
| Construcción densa en runtime | Iteración inicial sencilla | Picos CPU/carga al conducir, difícil reproducibilidad de ajustes | Evitar para geometría pesada |
| LiDAR generalizado | Potencial de mejor suelo local | Cobertura sin comprobar, datos grandes y cambios de datum/campaña | Solo mejora posterior verificada |

La simplificación principal es reutilizar la superficie arcade ya unificada y los manifiestos, manteniendo toda la adaptación geográfica en el bake. No crear otro grafo de calles ni otro sistema de proyección.

## 5. Implementación progresiva propuesta

1. Validar esta estrategia; completar adquisición R.1 y fijar referencia vertical. Crear servicio y pruebas de ejes, interpolación, NoData y reproducibilidad.
2. Seleccionar con perfiles DEM un sector norte en Colina del Sol/Pedregal con desnivel medido y vía conectada. Es candidato, no piloto ya confirmado. Incluir halo y edificios próximos; escena aislada o transición segura al plano. Probar mallas, cimentaciones y coche de producción antes de tocar todo el mundo.
3. Dos sectores adyacentes: comparar secuencias de borde, normales y raycasts, recorrer unión en ambos sentidos y probar carga/descarga/recuperación.
4. Región urbana con cruces, espacios abiertos y costa: comprobar ajustes viales, patios, landmarks, F8/F9 y seguridad marítima.
5. Expandir centro/norte/sur desde manifiesto; abordar por separado Forjadores y mantener exclusiones hasta validar estructuras. Comparar rendimiento y regresiones sobre el mismo snapshot antes de habilitar relieve por defecto.

## 6. Validación y aceptación

Pruebas propuestas: alturas originales frente a muestras de raster; determinismo por hash; ausencia de NaN/NoData oculto; bordes compartidos sin T-junction; cobertura del asfalto y no solapamiento físico; continuidad de cota y normal en cruces; pendientes y variación de pendiente reportadas; huecos interiores conservados; fundaciones verificadas sobre malla final; mar y litoral; spawn/recuperación a distintas alturas; límites del recorte; subida/bajada y curvas en ambas direcciones, ruedas visuales, turbo, frenado y drift; streaming a velocidad máxima y teletransporte.

Los umbrales de pendiente, curvatura y error geométrico se fijarán con el piloto y quedarán en configuración. No se declarará continuidad solamente por una captura visual ni transitabilidad solamente por raycasts.

Baseline histórico disponible: `phase_c5_south_cut_benchmark.json`, media 0,783 ms, p95 0,97 ms, máximo 8,63 ms, memoria estática 188.246.677 bytes y arranque 1303 ms. Es benchmark estático de una versión previa, no medición actual ni comparación de relieve. Debe repetirse plano/relieve con mismo mapa, cámara, viewport, renderer y equipo; medir arranque, media/p95/p99/máximo, memoria estática y proceso por separado, triángulos, cuerpos, tiempos de carga por sector y pasos de física. Añadir recorrido y límites de carga; no inferir rendimiento de GPU de ejecución headless.

En esta auditoría se ejecutó arranque headless de 120 cuadros: `PHASE_C5_READY`, 537 sectores viales, 55.864 triángulos, 59.635 edificios, 519 sectores urbanos, build_ms=1306. Hubo aviso de que `user://logs/godot.log` no era escribible dentro del entorno restringido; no aparecieron errores de carga de datos o scripts. No es prueba de conducción ni benchmark renderizado.

La suite Python de regresión se registra en `phase_b7r_audit_validation.json` al finalizar su ejecución. No se ha ejecutado un piloto de relieve, ni comparativa nueva de rendimiento, ni pruebas de conducción en pendientes. Todos los criterios de aceptación del relieve permanecen pendientes hasta implementarlos y comprobarlos.

## 7. Alcance de esta entrega

Solo auditoría, investigación inicial, propuesta y baseline. No se han cambiado scripts de juego, fuentes originales, datos procesados ni parámetros físicos. La implementación queda a la validación previa solicitada expresamente en la sección 17 de `ELEVACIONES.md` y del encargo del usuario.
