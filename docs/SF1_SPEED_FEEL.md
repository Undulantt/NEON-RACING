# SF.1 — Cámara experimental de velocidad

> Documento de la entrega base. SF.1.1/SF.2.1 amplían el panel y el FOV TURBO: para reproducir los valores de esta página usar TURBO **0%**. Ver [guía vigente](SF21_AUDIO_Y_TURBO.md).

Estado: implementado para evaluación del jugador. SF.2–SF.5 permanecen pendientes. Esta entrega experimenta con cámara; la mejora subjetiva de velocidad y comodidad se decidirá al conducir.

## Uso inmediato

F5 conserva el flujo normal: menú → Jugar → modo → vehículo. La configuración inicial utiliza **B experimental** en modo libre y carreras.

| Acción durante la conducción | Control |
|---|---|
| Alternar A original / B experimental | **Ctrl + Alt + B** |
| Abrir/cerrar laboratorio de cámara | **Ctrl + Alt + P** |
| Cambiar vista cercana/lejana | **V**, como antes |
| Restituir exactamente la presentación anterior | Botón **A · Original** |
| Recuperar los valores iniciales del experimento | **Restablecer B** |
| Guardar/reutilizar parámetros de prueba | **Guardar prueba / Cargar** |

El panel permite conducir mientras se ajusta con el ratón. Sus controles no capturan foco de teclado. Se oculta al pausar, usar la vista aérea, cambiar de escena o cargar una actividad. Esc mantiene la pausa y el mapa existentes. No se usa F8, reservado por el editor para detener el juego.

El panel muestra velocidad física en km/h, límite normal efectivo, aceleración filtrada, TURBO, estado y progresión **real** de BURST, FOV actual/objetivo, distancia de SpringArm, altura resultante, FPS, duración del último frame de render y tiempo CPU de la actualización de cámara. Con T ×2 muestra esa condición: desactivarla para la prueba de referencia. Los FPS del panel son una lectura en vivo, no una garantía.

La configuración guardada reside únicamente en `user://sf1_camera_experimental.cfg`. Se carga al crear la cámara; no cambia perfiles ni ajustes de conducción. Los argumentos `--sf1-original` y `--sf1-experimental`, después de `--`, prevalecen sobre el modo guardado. **A** restaura la cámara antigua; **Restablecer B** restaura el experimento, son acciones diferentes.

## Arquitectura y decisiones

- `scripts/feedback/SpeedFeedbackController.gd`: observa el vehículo, calcula aceleración y mezclas audiovisuales; expone `telemetry`, `fov_target` y la señal `telemetry_updated(snapshot)`. No aplica fuerzas, controles, límites de velocidad ni estados de habilidades. Reinicia su historial al recuperar el vehículo o cambiar de perfil, evitando aceleraciones visuales falsas después de un teletransporte.
- `scripts/driving/FollowCamera.gd`: conserva el algoritmo anterior en `_original_physics_process`; elige A/B y consume los objetivos del controlador. Reutiliza una sola cámara y el SpringArm existentes. La posición horizontal sigue el coche sin retraso que pueda arrastrarla a un edificio; se suavizan altura, distancia y orientación.
- `scripts/ui/SpeedFeelPanel.gd`: presentación y edición de parámetros; no toca entradas del automóvil. El laboratorio no necesita otro Autoload ni modifica GameFlow.
- `config/sf1_camera_experimental.json`: valores experimentales separados de los perfiles definitivos.

La cámara nocturna previa usaba 5.3 m de brazo con inclinación de 10° y un pivote 1.25 m sobre el centro del coche. Su FOV podía llegar aproximadamente a 98° durante BURST. B busca otra combinación: cámara más baja, horizonte legible y amplitud más contenida. Por eso **B no significa simplemente más FOV que A**. Se conservan los VFX, sonidos y tratamientos retro existentes para que el cambio de cámara se pueda evaluar aisladamente.

Se fija `Camera3D.KEEP_HEIGHT`: los grados del panel son **verticales**. En 16:9, 75° verticales corresponden aproximadamente a 107.5° horizontales; la proporción de pantalla importa. La prueba comprueba la matriz de proyección del motor, además de la propiedad FOV. Referencia: [Camera3D, Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html).

El SpringArm mantiene máscara 15 y excluye el RID del jugador. En B, su esfera cubre las esquinas del plano cercano según FOV y relación de aspecto, con margen adicional. Se eleva el pivote si el brazo se comprime mucho, para conservar visibilidad por encima del techo. La altura se calcula desde la base física del coche, en vez de consultar el terreno bajo un puente. Referencia: [SpringArm y barrido de formas](https://docs.godotengine.org/en/4.7/tutorials/3d/spring_arm.html).

## Parámetros iniciales

| Parámetro | Valor |
|---|---:|
| FOV base | 70° |
| Incremento por velocidad normal | 5° |
| Incremento TURBO sobre velocidad normal | 3° |
| Incremento máximo BURST sobre velocidad normal | 7° |
| Límite objetivo de B | 82° |
| Respuesta FOV | 5/s |
| Respuesta de posición / orientación | 8/s / 9/s |
| Distancia horizontal cercana | 5.4 m |
| Altura deseada sobre la base del coche | 1.8 m |
| Inclinación hacia abajo | 4° |
| Vista lejana V | +1.3 m |
| Retroceso al acelerar / avance al frenar | hasta 0.22 / 0.18 m |
| Retroceso TURBO / BURST | hasta 0.18 / 0.35 m |
| Derrape: desplazamiento / giro máximo | 0.12 m / 2° |

FOV normal = base + incremento de velocidad × smoothstep(velocidad longitudinal / límite normal efectivo).

TURBO y BURST proponen **objetivos independientes** sobre el FOV normal; se utiliza el mayor y se limita, evitando sumar ambos incrementos. El estado BURST se lee de DrivingAbilities y su progresión es `burst_bonus / burst_max_bonus`, no un cronómetro visual inventado. Su entrada vale el 12% de la intensidad y luego crece con smoothstep hasta el 100%. A máxima velocidad normal: entrada ≈75.84°, mitad ≈78.92°, máximo 82°. Soltar acelerador reinicia inmediatamente la habilidad original; únicamente la intensidad visual vuelve suavemente.

La interpolación exponencial usa delta. Desactivar FOV o posición conserva el componente previo, para probarlos por separado; movimiento y derrape también tienen interruptores independientes. El límite afecta al objetivo B: al pasar desde A con FOV superior, o bajar el límite en vivo, el FOV actual converge suavemente desde el valor anterior. No se fuerza un salto para recortarlo.

La altura es un objetivo sujeto a seguridad: el pivote mínimo y la retracción pueden elevar la cámara, especialmente junto a paredes o con combinaciones extremas de los deslizadores. No hay vibración, roll de cámara, predicción de rutas ni postprocesado nuevo.

## Prueba reproducible sobre cartografía existente

Desde la raíz del proyecto, en PowerShell (ajustar la ruta del motor si se mueve):

```powershell
$godot = (Resolve-Path '..\..\Godot_v4.7.2-stable_win64_console.exe').Path
& $godot --path . --script tests/sf1_city.gd -- --manual-route
```

El auxiliar entra por el flujo normal con VECTOR y prepara el tramo existente `tracks/extension_C2.json`, puntos **25–42**, identificado previamente en `docs/burst_route_geometry.json`: **1693.97 m** y como máximo 12° de cambio acumulado de rumbo. Empieza cerca de X=604.55, Z=-693.90, sobre Calle Miguel Hidalgo y Costilla según el rótulo vial del mapa; los nombres y la geometría proceden de los datos existentes. Es un **recorrido de prueba**, no una nueva carrera ni una avenida ficticia. Conserva cruces y relieve. No modifica ningún archivo cartográfico.

El panel agrega **Reiniciar tramo OSM (SF.1)** para repetir salida y vehículo con velocidad inicial cero. La prueba emplea un archivo temporal de opciones del juego, sin sustituir preferencias del usuario. Se pueden comparar los tres perfiles en el flujo normal; el auxiliar fija VECTOR para repetir las condiciones de referencia.

1. Restablecer B, desactivar T ×2 y mantener el mismo nivel F4 de efectos existentes en ambas pasadas.
2. Elegir A y reiniciar el tramo. Acelerar desde reposo; observar distancia visual y aproximación a los cruces.
3. Antes de sostener la máxima, probar brevemente Shift y soltarlo para distinguir TURBO. Mantener después acelerador para observar preparación, entrada y crecimiento de BURST.
4. Soltar acelerador y frenar antes de agotar el tramo. Probar un derrape en una intersección con espacio, a velocidad moderada; no intentar completar todo el recorrido recto derrapando.
5. Elegir B y reiniciar. Repetir la misma secuencia, perfil, dirección y nivel F4.
6. Para observar A/B a velocidades equivalentes, alternar Ctrl+Alt+B en la misma pasada y leer el velocímetro, o comparar las dos pasadas en el mismo intervalo de velocidad. Dejar aproximadamente 3 segundos tras alternar para que la transición termine. Mantener volante/acelerador igual al cambiar la cámara.

La comparación automatizada en ese tramo utilizó el **conductor de pruebas ya existente**, no un piloto automático añadido al juego. En ambas pasadas alcanzó BURST completo; la persona que conduce debe frenar según los obstáculos visibles. Para comparar exactamente 180 km/h, las capturas y el benchmark congelan la pose y proporcionan telemetría sintética: se identifican expresamente así y no representan una medición de aceleración física.

## Validación

Godot 4.7.2 estable, física a 60 Hz para las pruebas deterministas:

```powershell
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf1.gd
& $godot --headless --path . --fixed-fps 60 --script tests/sf1_city.gd
& $godot --headless --path . --fixed-fps 60 --script tests/sf1_city.gd -- --manual-smoke
& $godot --path . --script tests/sf1_city.gd -- --benchmark
& $godot --headless --path . --fixed-fps 60 --script tests/godot_phase_d1.gd
& $godot --headless --path . --fixed-fps 60 --script tests/godot_race_navigation.gd
& $godot --headless --path . --fixed-fps 60 --script tests/godot_powertrain.gd
& $godot --headless --path . --fixed-fps 60 --script tests/godot_burst.gd
```

- **67 comprobaciones SF.1 aprobadas**: FOV por estado y perfil, progresión/salida BURST, equivalencia con el script original, respuesta 30/60/120 Hz, ajustes y persistencia, foco, pausa, pared cercana, techo del vehículo, terreno elevado y plano cercano ultrapanorámico. La reproducción física de 1800 pasos por modo/perfil dio **diferencia máxima cero** en trayectoria, velocidad y estado BURST.
- **13 archivos protegidos idénticos por SHA-256**: controlador, habilidades, entradas, perfiles, sonido existente, configuraciones, VFX existentes y cartografía. `docs/sf1_baseline/manifest.json` registra el commit de origen y `FollowCamera.gd.txt` conserva la cámara anterior para la comparación real de A.
- **Ciudad real**: ambas pasadas completaron el tramo en **32.6167 s**, máxima **249.803 km/h**, BURST **19.3667 s**, sin contactos de pared, recuperaciones ni frames fuera de asfalto. Esa velocidad ya corresponde al VECTOR con BURST existente; SF.1 no la aumenta. La pequeña diferencia de posición final (~0.2 mm) está dentro de la precisión de la simulación del mundo; la prueba controlada plana es exactamente idéntica.
- **Regresiones**: 207 comprobaciones D.1 y 48 de navegación aprobadas; suites de transmisión y TURBO/BURST/derrape aprobadas. No aparecieron errores de scripts en las ejecuciones finales.
- **Rendimiento**: ver `sf1_benchmark.json`. Mismo punto de ciudad, 1280×720, Compatibility, RTX 4060 Ti, VSync desactivado; secuencia A/B/B/A, calentamiento real de 3.5 s y 600 frames renderizados por muestra. Se informa tiempo de pared, sin `--fixed-fps`. Es una prueba de coste de presentación en pose estática con telemetría sintética; no mide el streaming durante un recorrido completo ni acredita 60 FPS en otras computadoras.

La medición de referencia dio medias A/B de **2.505 / 2.539 ms** (+0.034 ms, aproximadamente 1.35%); las dos muestras B tuvieron p95 de **4.328 / 2.560 ms**. Es una diferencia pequeña en este escenario estático y este hardware, sin extrapolarla a toda la ciudad.

También se verificó la entrega nativa de Ctrl+Alt+P/B manteniendo W: el panel abrió, A/B cambió y el acelerador permaneció activo. El reinicio del tramo volvió a una salida vial válida (`sf1_manual_validation.json`).

Informes: `sf1_validation.json`, `sf1_city_drive.json`, `sf1_benchmark.json`, `sf1_manual_validation.json` y el consolidado `sf1_regressions.json`. Evidencia renderizada: `evidence/sf1_A_180kmh.png`, `evidence/sf1_B_180kmh.png`, `evidence/sf1_panel.png`. Las líneas y el tratamiento visual que se ven en esas imágenes ya existían antes de SF.1.

Se cambió únicamente la resolución de la escena ReliefWorld del auxiliar `benchmark_burst_balance.gd` de preload a load: permite reutilizar su conductor después de inicializar el Autoload y evita una dependencia circular en la compilación de las pruebas. No cambia el piloto ni la conducción del producto.

## Límites y próxima evaluación

La sensación, la lectura de curvas y el posible malestar requieren tu prueba personal. No se recorrieron todas las calles ni todas las combinaciones extremas de ajustes; los barridos de cámara y las pruebas de esquina reducen el riesgo de clipping, sin prometer cobertura exhaustiva. En hardware distinto debe medirse también el streaming y los percentiles de frame durante conducción real. Los ajustes son experimentales, no estadísticas definitivas de los automóviles.

Para la próxima revisión, evaluar primero altura/distancia, lectura de obstáculos a 180 km/h, claridad de entrada/crecimiento de BURST y comodidad en derrape. Conservar o descartar cada componente con sus interruptores. El controlador expone telemetría para futuros consumidores de audio o VFX, pero **SF.2, SF.3, SF.4 y SF.5 no se implementaron**. El desarrollo se detiene en SF.1 a la espera de esa evaluación.
