# SF.4 — Derrape ilustrado y transformación BURST

Fecha: 2026-11-13. Primera versión experimental para evaluación del jugador. No se inicia SF.5.

## Dirección artística aplicada

La indicación posterior del usuario sustituye el humo gris del adjunto inicial: se utiliza **lavanda y rosa, sombras violetas y siluetas irregulares**, siguiendo como inspiración la última imagen facilitada. Las marcas permanecen oscuras. BURST utiliza patrones geométricos magenta/cian/violeta y estelas energéticas, conservando visible la carrocería original.

El humo y sus máscaras se generan con código propio. No se copiaron texturas, shaders, modelos ni imágenes de otros videojuegos. Tampoco se añadió una mecánica física de burnout estacionario; la quema visual responde al deslizamiento que ya produce el controlador durante la conducción.

## Desarrollo por subetapas

1. **SF.4.1:** humo en un pool acotado, silueta de tres tonos y sensores de ruedas. Se ejecutaron las primeras 37 comprobaciones y una captura/medición en una avenida real antes de avanzar.
2. **SF.4.2:** marcas persistentes con contactos de asfalto y validación de bordes. Se comprobaron continuidad, caducidad, superficies equivocadas y una carretera inclinada: 42 comprobaciones acumuladas.
3. **SF.4.3:** shader de carrocería, progreso real normalizado, estelas, previsualización y retirada al cancelar. 66 comprobaciones acumuladas, además de capturas de varios porcentajes.
4. **SF.4.4:** controles independientes, límites, restauración A/B, integración con efectos anteriores y transiciones. Las comprobaciones finales están en los informes de esta entrega.

Las primeras imágenes de humo gris son evidencia histórica de SF.4.1, no el acabado final. `sf4_drift.png` y `sf4_stage_4.png` muestran la paleta posterior solicitada.

## Arquitectura y archivos

`scripts/feedback/VehicleVFXController.gd` es un componente de presentación asociado al automóvil a través del gestor Speed Feel existente. Lee velocidad, deslizamiento, pérdida de adherencia, contactos, TURBO y BURST. No aplica fuerzas ni modifica habilidades, límites de velocidad, aceleración, frenado o FOV.

El componente se crea desde `SpeedFeedbackController.gd` y sirve para VECTOR, COMET y APEX. Usa los anclajes de ruedas existentes, no posiciones de neumáticos inventadas para cada modo de juego.

| Componente | Función |
|---|---|
| `config/sf4_vehicle_vfx.json` | Valores iniciales experimentales y límites |
| `shaders/sf4_smoke.gdshader` | Sprites orientados a cámara, expansión y disipación |
| `assets/textures/sf4_smoke.png` | Máscara original ilustrada de tres tonos |
| `tools/build_sf4_smoke.py` | Generador reproducible de la textura, con Pillow |
| `shaders/sf4_tire_marks.gdshader` | Trazos oscuros, desgaste y retirada gradual |
| `shaders/sf4_burst_body.gdshader` | Bordes, circuitos y malla energética progresiva |
| `CarVisual.gd` / `RetroCar.gd` | Etiqueta de material de pintura para el overlay, sin cambios geométricos |
| `RetroLook.gd` | Conecta los efectos visuales anteriores con SF.4 |
| `TurboTrail.gd` | Evita duplicar estelas cuando las energéticas de BURST ya están presentes |
| `SpeedEffects.gd` | Ajusta la intensidad visual de pantalla al progreso SF.4, manteniendo la ruta original para A/B |
| `SpeedFeelPanel.gd` | Pestaña SF.4, controles, comparación, previsualización y guardado de pruebas |

Para incorporar otro modelo, proporcionar los anclajes traseros en la interfaz visual del automóvil y etiquetar su material de pintura con `sf4_body=true`. Las ruedas, cristales y luces no se transforman indiscriminadamente.

## Humo ilustrado

Un MultiMesh reutiliza hasta 128 quads preasignados; el límite inicial activo es 96. Las partículas guardan posición, velocidad, edad y vida en coordenadas del mundo. El automóvil se aleja de ellas mientras se expanden, suben suavemente y desaparecen. No se crean nodos por partícula.

La máscara original tiene sombras violetas, masa lavanda y luces rosa claro. Su sombreado es plano; solo la opacidad se interpola al aparecer/desaparecer. El tamaño y la rotación varían entre partículas para evitar una sucesión de discos idénticos.

La emisión exige conducción habilitada, contacto global con el suelo, suficiente velocidad, ángulo de deslizamiento y señal de derrape. La densidad aumenta con velocidad, deslizamiento, pérdida de adherencia y duración sostenida. Los dos anclajes traseros se comprueban mediante rayos que solo aceptan **capa 1 de carreteras**. No se utiliza la plataforma de seguridad ni los edificios como asfalto.

El umbral VFX inicial es 0.20 rad de deslizamiento y señal de derrape >0.3. El controlador físico conserva además su propio umbral real de derrape, aproximadamente 55 km/h. Por eso no basta con mover ligeramente el volante o mantener el vehículo parado para emitir humo.

Se conserva el sistema anterior para la comparación Original. En SF.4 se detiene su emisión para no dibujar los dos humos a la vez.

## Marcas de neumáticos

Las marcas unen contactos sucesivos de cada rueda trasera. Un segundo MultiMesh almacena segmentos de cinta orientados por la dirección y la normal de la carretera. Su ancho se escala con el vehículo. Las posiciones permanecen en el mundo después de recuperar agarre.

Antes de aceptar un segmento se verifican sus cuatro bordes y el punto intermedio con rayos de asfalto. Se rechazan huecos, apoyos incorrectos, cambios bruscos de normal y diferencias de superficie excesivas. Los contactos dejan de enlazarse al terminar el derrape, volar o perder apoyo, evitando líneas que atraviesen calles o saltos.

El shader añade variación en bordes y franjas de goma; el color es oscuro, sin emisión. Se usa una pequeña separación superficial para reducir z-fighting. El fundido se produce al final de su vida útil.

Límite inicial: 512 segmentos, vida de 16 s y radio de conservación de 350 m. El buffer máximo preasignado es 1,024. Al alcanzar el límite se retiran los segmentos más antiguos. También se eliminan al quedar lejos del jugador; no se depende de que todo el mapa permanezca cargado.

Una cinta corta aproxima localmente el plano del asfalto. Se prefiere interrumpirla en un cambio brusco de pendiente antes que proyectarla sobre terreno equivocado. No son decals del renderizador: la geometría funciona en Compatibility.

## Transformación BURST y diferenciación de TURBO

La intensidad real se obtiene de `burst_bonus / burst_max_bonus`, limitada a 0–1 y solo válida cuando BURST está activo. Cada vehículo utiliza su propio límite. No se calcula a partir de una velocidad inventada ni se modifica el estado físico.

- **Bajo:** iluminación sutil de bordes.
- **Intermedio:** circuitos, barridos y pequeños puntos luminosos.
- **Alto:** diagonales y malla energética, con estelas de mayor presencia.
- **Máximo:** máxima cobertura configurada, con pintura y cabina aún reconocibles.

El overlay es aditivo y se limita a materiales de pintura etiquetados. No sustituye el material base ni altera proporciones. Al quedar sin intensidad se retira el pase y se restauran los overlays anteriores.

La activación acompaña al progreso real con una respuesta suave. Tras cancelar BURST, el bonus físico se reinicia por su lógica anterior y el efecto visual baja a cero en un máximo inicial de 0.25 s. No se conserva una transformación permanente después de cancelar.

Las estelas energéticas son dos cintas mundiales, con historia máxima de 40 muestras y vida de 0.18–0.55 s según progreso. Su intensidad crece a partir del tramo medio de BURST. TURBO conserva el escape y la respuesta inmediata anteriores; SF.4 añade un pulso breve cian de aproximadamente 0.18 s. Cuando ambos coinciden, se evita dibujar dos juegos redundantes de estelas largas.

Al habilitar la transformación nueva, se retiran las antiguas llamas de suelo de BURST y la intensidad de pantalla acompaña al progreso en vez de saltar siempre al máximo. El modo Original restaura esos sistemas. No se añadió distorsión de pantalla ni otro cambio de FOV.

## Controles y valores iniciales

Abrir **Ctrl+Alt+P → pestaña SF.4**. La comparación de esta fase usa **A · Original / B · SF.4** de esa pestaña; los botones superiores de cámara siguen comparando SF.1.

| Ajuste | Inicial | Rango del panel |
|---|---:|---:|
| Densidad de humo por rueda | 26/s a intensidad plena | 4–55 |
| Vida base de humo | 0.9 s | 0.3–1.8 s |
| Tamaño base | 1.65 m | 0.6–2.4 m |
| Partículas máximas | 96 | 16–128 |
| Segmentos máximos | 512 | 64–1,024 |
| Vida de marcas | 16 s | 3–30 s |
| Intensidad de carrocería | 0.85 | 0–1 |
| Respuesta de entrada BURST | 14/s | 3–25/s |
| Retirada BURST | 0.25 s | 0.15–0.35 s |

El archivo JSON incluye ancho de marcas de 0.22 m antes de la escala del coche, espaciado de 0.45 m y radio de conservación de 350 m. El tamaño y vida de cada puff tienen una variación moderada respecto al valor base.

Hay interruptores independientes para humo, marcas y transformación. Ajustar el humo no reinicia la transformación; apagar marcas no elimina el estado visual del cuerpo. **Restablecer** devuelve la configuración inicial y limpia los efectos retenidos.

**Previsualizar BURST (solo visual)** y su porcentaje permiten observar el shader sin acelerar, cambiar marchas, cargar TURBO o alterar el bonus. El panel distingue BURST real de BURST visual y señala PREVISUALIZACIÓN. Desactivarla devuelve la apariencia al valor real. No se guarda esa simulación de porcentaje en la configuración de prueba.

**Guardar prueba / Cargar prueba** usan `user://sf4_vehicle_vfx.cfg`, independiente de la cámara y audio. `--sf4-original` inicia con la presentación anterior. F4 conserva su control global de intensidad; los efectos nuevos respetan su estado desactivado.

## Limpieza y rendimiento

Recuperar, teletransportar más de 12 m, cambiar perfil o reiniciar actividad limpia historias y partículas para no unir posiciones discontinuas. Los materiales anteriores se restauran al retirar el componente. Al salir del mundo se liberan sus mallas y recursos.

Se utilizan un lote para humo, otro para marcas y una malla pequeña para las estelas. El overlay añade pases únicamente a piezas de pintura. No hay luces por partícula, humo volumétrico, miles de nodos ni reconstrucción del mapa. Las marcas solo vuelven a subir transforms cuando su lista cambia; la edad avanza mediante uniforme del shader. El reloj se envuelve en 64 s para mantener precisión en datos de instancia del renderer Compatibility.

El diagnóstico muestra partículas, segmentos, deslizamiento, progreso real/visual, tiempo de CPU, FPS y tiempo aproximado por frame. El dato de FPS del panel no sustituye una captura de profiler.

## Validaciones y reproducción

Desde Godot 4.7.2, con `--path .`:

```text
--headless --script res://tests/godot_sf4.gd -- --stage=4
--headless --script res://tests/sf4_physical_driving.gd
--headless --script res://tests/godot_race_navigation.gd
--script res://tests/sf4_city.gd -- --benchmark --stage=4
```

La prueba de conducción usa **controles reales** con los tres perfiles sobre una superficie sintética de prueba, que nunca se exporta al mapa. Comprueba aceleración recta sin humo y derrape con humo/marcas; no inyecta ángulo de deslizamiento. La aceleración previa debe superar el umbral físico de derrape antes de accionar freno de mano.

La captura sobre la avenida OSM sí utiliza telemetría VFX suministrada y física detenida, exclusivamente para revisar arte y comparar el coste de los mismos lotes. Las capturas de porcentajes BURST son previsualizaciones. No se presentan como una carrera ni como FPS de conducción real.

Se conservan hashes de física, habilidades, transmisión, perfiles, cámara/FOV y mapa en `docs/sf4_baseline.json`. No se reescribieron los baselines históricos de fases anteriores para hacerlos coincidir con cambios visuales nuevos.

Evidencia: `sf4_stage_1_validation.json`, `sf4_stage_2_validation.json`, `sf4_stage_3_validation.json`, `sf4_stage_4_validation.json`, `sf4_physical_driving.json`, `sf4_stage_4_render.json`, logs `sf4_navigation.log` y capturas `docs/evidence/sf4_*`.

## Límites y evaluación pendiente del jugador

El humo es un conjunto de sprites ilustrados, no una simulación volumétrica; puede reconocerse la repetición de la máscara en primeros planos o desde cámaras aéreas. Las marcas pueden interrumpirse en bordes o irregularidades fuertes para conservar apoyo correcto. La comparación gráfica es una vista fija con carga estabilizada y no garantiza 60 FPS sostenidos en todo el mapa ni en otro hardware.

La dirección de color sigue la última referencia del usuario y requiere su evaluación personal. Antes de añadir más efectos conviene ajustar tamaño/opacidad percibida del humo, legibilidad del shader a medio BURST y longitud de estelas. Esta entrega se detiene en SF.4.

## Resultados finales

- 75 comprobaciones de efectos/contactos/panel/hashes: aprobadas.
- 15 comprobaciones con conducción física real en los tres perfiles: aprobadas.
- 48 comprobaciones existentes de navegación y carreras: aprobadas.
- 13 archivos protegidos conservan sus hashes; 12 logs Godot revisados sin errores de scripts.
- Textura final reproducida idéntica byte por byte.

En la conducción de prueba se midieron picos de VFX de 0.624 ms (VECTOR), 0.855 ms (COMET) y 0.814 ms (APEX), con hasta 172 marcas y 30 partículas durante esos derrapes. Estos valores no son un benchmark del peor caso con todos los límites saturados.

Comparación final en RTX 4060 Ti, 1280×720 Compatibility, VSync desactivado, ciudad estabilizada, A/B/B/A con dos segundos de estabilización y 600 muestras por modo:

| Lotes SF.4 | Mediana (ms) | p95 (ms) | Draw calls |
|---|---:|---:|---:|
| Ocultos | 2.265 | 3.780 | 258 |
| Visibles | 2.165 | 2.988 | 264 |
| Visibles | 2.424 | 3.251 | 264 |
| Ocultos | 2.079 | 3.001 | 258 |

Incremento medio entre medianas: 0.123 ms; diferencia media entre p95: -0.271 ms. Se añadió un total de seis draw calls en esa vista con humo, marcas, estelas y overlay de pintura. El margen de p95 incremental de 1 ms se cumple; la dispersión de las muestras impide atribuir una mejora de FPS a los efectos. La comparación oculta/muestra los lotes nuevos, mientras que los botones A/B del panel restauran además los sistemas anteriores. Son pruebas diferentes y se documentan por separado.

Resumen verificable: `docs/sf4_final_validation.json`.
