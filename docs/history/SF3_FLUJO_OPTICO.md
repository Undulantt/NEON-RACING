# SF.3 — Flujo óptico ambiental

> Corrección vigente: se reforzó el contraste, se añadió una base visible estando detenido y una vista previa estática. Ver [corrección y cómo comprobarla](SF3_VISIBILITY_FIX.md).

Primera versión funcional para evaluación del jugador. Se implementan asfalto/marcas, referencias próximas y respuesta gradual por estado. La sensación de velocidad y la comodidad requieren tu prueba personal; las comprobaciones técnicas no sustituyen esa evaluación. SF.4 queda preparado únicamente como interfaz.

## Probar y comparar

Iniciar con F5 y entrar a modo libre o carrera con cualquiera de los tres perfiles. Se conserva el flujo habitual.

| Control | Acción |
|---|---|
| **Ctrl + Alt + L** | Ciclar **Original → Parcial → Completo**. Inicialmente está en Completo. |
| **Ctrl + Alt + P → Entorno** | Activar SF.3, aislar capas, ajustar parámetros y guardar pruebas. |
| **Restablecer entorno** | Recuperar la configuración inicial SF.3. |
| **Guardar / Cargar**, dentro de Entorno | Guardar/reutilizar `user://sf3_environment.cfg`. |

Los botones inferiores que dicen **cámara** siguen afectando solo a la cámara. Los controles de Audio siguen siendo independientes. Ctrl+Alt+B compara cámaras y Ctrl+Alt+O compara audio; ninguno de ellos selecciona el modo SF.3.

- **Original:** retira las mejoras ambientales, devuelve los overrides originales de marcas/farolas y deja los nuevos parámetros del asfalto en cero. Conserva cámara, audio y VFX anteriores.
- **Parcial:** asfalto y marcas existentes, con bordes/farolas en su presentación anterior.
- **Completo:** activa las cuatro subcapas. También pueden seleccionarse combinaciones manuales mediante sus interruptores.

Esperar aproximadamente **1.5 segundos** tras alternar el modo para comparar el resultado estabilizado. Los atajos se limitan a conducción activa y se comprobó su funcionamiento manteniendo W pulsada. El panel no captura foco de teclado y se oculta en pausa, carga y vista aérea. Esc conserva la pausa/mapa existentes.

La base visual está activa aun detenido; la respuesta por velocidad empieza a crecer cerca de **65 km/h**: comparar a velocidad alta, TURBO y BURST, además de aproximarse a curvas y frenar. Mantener el mismo perfil, cámara, FOV, audio y nivel F4 en las pasadas. Los streaks de pantalla ya existentes pueden ponerse sutiles o desactivarse con F4 para aislar el entorno; SF.3 no añade otro efecto de pantalla.

Argumentos de inicio, después de `--`: `--sf3-original`, `--sf3-partial`, `--sf3-full`. Prevalecen sobre el modo guardado. Los ajustes de SF.1 y audio se conservan.

## Cambios visuales

### SF.3.1 — Suelo y marcas

El shader nocturno conserva su aspecto anterior con SF.3 en cero. Al crecer la intensidad añade variación de brillo/contraste de escala métrica al asfalto. El detalle está **fijo en coordenadas del mundo** y tiene atenuación por resolución de píxel para reducir aliasing a distancia. No se desplaza UV ni se acelera artificialmente una textura: el flujo lo produce el avance real del coche sobre referencias más visibles.

Las marcas y bordes reutilizan las mallas ya preparadas y proyectadas sobre el relieve. Las marcas claras ganan legibilidad sin modificar tamaño, ubicación o recorrido. En los bordes cian, una malla espacial de brillo de 5 m aporta referencias de paso. Es variación cosmética sobre el borde existente, no nuevos carriles, señalización oficial ni postes levantados de datos cartográficos.

### SF.3.2 — Referencias cercanas

Se reutilizan los **LampBatch** existentes y las cuatro manchas de luz que ya calculaba CityFurniture. Solo las caras coloreadas como luminaria reciben el refuerzo: los postes mantienen su color. Las manchas existentes pueden extenderse suavemente en la dirección del movimiento, como reflejos estilizados sobre asfalto. Cuando el coche está detenido, la dirección de referencia sigue su orientación; no hay animación autónoma.

No se añaden luces dinámicas, postes, palmeras, barreras, colisiones ni nuevos sectores. Donde no hay farolas preparadas y próximas, esta capa aporta poco o nada. Los reflejos no son SSR ni una simulación de reflexión física de los edificios. No hay parpadeo, strobe o pulsos temporales nuevos.

La respuesta queda limitada por defecto a **85 m** alrededor del jugador, con fundido espacial y por diferencia de altura para no iluminar indiscriminadamente otras cotas. Más allá, los materiales mantienen su apariencia anterior.

### SF.3.3 — Estados

La velocidad usa magnitud horizontal real / límite normal del perfil; puede superar 1 durante BURST. La intensidad normal se suaviza desde el umbral hasta la máxima normal. TURBO responde con una envolvente rápida, y BURST usa la **bonificación física real / bonificación máxima del perfil**, no un reloj visual independiente.

Con la configuración inicial, a máxima normal:

| Estado | Intensidad combinada estabilizada |
|---|---:|
| Normal | 0.45 |
| TURBO | 0.75 |
| Entrada BURST, progreso físico 0 | 0.483 |
| BURST al 50% | 0.7415 |
| BURST al 100% | 1.0 |

Se toma el mayor aporte entre TURBO y BURST sobre la contribución normal, en lugar de sumarlos ambos. El resultado común está limitado a 0–1. BURST arranca con un 6% de su envolvente y crece con smoothstep del progreso real. Al cancelar la habilidad, `burst_ratio` vuelve inmediatamente a cero, mientras la intensidad de presentación puede decaer suavemente.

Los porcentajes visuales no aumentan la velocidad ni representan metros recorridos. Los efectos TURBO/BURST de etapas anteriores siguen existiendo; esta tabla describe únicamente la nueva envolvente ambiental compartida.

## Parámetros configurables

Archivo base: `config/sf3_environment_experimental.json`. Todos los siguientes parámetros tienen control en la pestaña Entorno:

| Parámetro | Inicial |
|---|---:|
| SF.3 / asfalto / marcas / bordes / farolas | Activados |
| Intensidad general | 1.0 |
| Visibilidad mínima detenido | 0.20 |
| Fuerza asfalto | 0.65 |
| Fuerza marcas | 0.70 |
| Fuerza bordes | 0.60 |
| Fuerza farolas/reflejos | 0.65 |
| Inicio de respuesta normal | 65 km/h |
| Ratio para respuesta normal máxima | 1.0 |
| Respuesta normal | 6/s |
| Respuesta TURBO | 12/s |
| Respuesta BURST | 4/s |
| Salida / transición general | 6/s |
| Aporte TURBO / BURST | 0.30 / 0.55 |
| Radio local | 85 m |
| Malla de referencias de borde | 5 m |
| Alargamiento de reflejos | 2.5 |

El inicio efectivo se limita a quedar por debajo del final si se elige una combinación incompatible de umbral/ratio. El espaciado es de una malla XZ: no garantiza exactamente esa distancia recorrida entre cambios de brillo en una curva. Radio y alargamiento tienen límites de seguridad en el panel.

## Arquitectura y reversibilidad

`SpeedVisualFeedback.gd`, hijo del observador SF.1, tiene dos partes: `advance(snapshot, delta)` produce el estado visual común; `bind_world`/`_process` aplican ese estado a los materiales del entorno. No existe otro Autoload ni se modifica el controlador del automóvil.

El adaptador se enlaza desde NightStyle reutilizando el material del asfalto y CityFurniture. No cambia RetroLook, CityFurniture, RoadNeon, RoadBuilder, los generadores offline ni las mallas cacheadas. Se evita invalidar el hash del generador de bordes y no hay que reconstruir la ciudad.

Las marcas usan **overrides por superficie de la instancia** y las farolas un override por MultiMeshInstance. Nunca se escribe sobre las superficies del ArrayMesh compartido. Se conservan los materiales originales, se restauran al desactivar y se usan referencias débiles para tolerar descarga de sectores. El límite es **96 instancias vinculadas**, con búsqueda local cada **0.5 s**. No se recorre la geometría de toda la ciudad cada frame: se consultan los sectores viales próximos y los propietarios ya registrados por CityFurniture.

Se conserva una copia del shader anterior en `sf3_original_road.gdshader.txt` y hashes de 27 archivos protegidos en `sf3_baseline.json`. Los únicos cambios de integración de producción son el consumidor nuevo, la exposición de estado en SpeedFeedbackController, el enlace de NightStyle, el panel y los shaders ambientales.

El adaptador está dirigido al escenario nocturno actual usado por modo libre y carrera. Las escenas diurnas de diagnóstico sin NightStyle conservan la telemetría/hook, pero no reciben automáticamente una conversión de materiales.

## Interfaz preparada para SF.4

Los consumidores pueden leer `world.follow_camera.speed_feedback.visual_state` o conectarse a **`visual_state_updated(state)`**. Se publica incluso sin ciudad enlazada o con SF.3 en Original. Esto permite que un futuro efecto del automóvil tenga su propio interruptor y no dependa de los materiales viales.

| Campo | Significado |
|---|---|
| `speed_ratio` | Velocidad horizontal / máxima normal; puede superar 1. |
| `speed_intensity` | Respuesta normal filtrada, 0–1. |
| `turbo_active`, `turbo_intensity` | Estado real habilitado y envolvente suavizada. |
| `burst_active` | BURST real habilitado. |
| `burst_ratio` | Progreso físico real 0–1, reinicio inmediato al cancelar. |
| `burst_intensity` | Envolvente visual filtrada con entrada/salida suave. |
| `combined_intensity` | Intensidad común limitada 0–1. |

La instantánea original de telemetría también expone `speed_ratio`, `forward_speed_ratio`, `burst_active` y `burst_ratio`. El primero usa magnitud real, el segundo velocidad longitudinal: en derrape pueden diferir.

**Propuesta concreta para SF.4, no implementada:** crear un `BurstVehicleVisualController` que reciba esta señal y duplique únicamente los materiales del vehículo activo. Empezar con una capa de emisión controlada por `burst_intensity`; después evaluar bordes/overlay según `burst_ratio`, conservando una mezcla cero que restaure exactamente el coche normal. Partículas, destellos o trails serían consumidores separados con presupuestos y controles propios. No conectar estos efectos al adaptador vial ni añadir fuerzas o cambios al perfil.

En esta entrega no se modificó RetroCar ni se creó un shader, skin, overlay o transformación BURST del automóvil.

## Pruebas reproducibles

Desde la raíz del proyecto:

```powershell
$godot = (Resolve-Path '..\..\Godot_v4.7.2-stable_win64_console.exe').Path
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf3.gd
& $godot --headless --path . --fixed-fps 60 --script tests/sf1_city.gd -- --sf3-compare
& $godot --path . --script tests/sf3_city.gd -- --benchmark
& $godot --path . --script tests/sf1_city.gd -- --manual-route
```

La prueba manual conserva el tramo OSM existente de `extension_C2`, puntos 25–42, **1693.97 m**. El botón Reiniciar tramo OSM vuelve a la misma salida con VECTOR. Comparar Original/Parcial/Completo a velocidad equivalente y al frenar ante cruces; probar derrapes a velocidad moderada. El auxiliar sigue reutilizando el conductor de pruebas existente para la reproducción automática; no se añade una carrera ni un piloto automático al producto.

Resultados:

- **77 comprobaciones SF.3 aprobadas:** intensidades por estado/perfil, BURST progresivo y salida, equivalencia temporal a 30/60/120 Hz, independencia de cámara/audio, presets, ajustes, persistencia, foco, hook SF.4 sin ciudad, overrides Mesh/MultiMesh, restauración, descarga por referencias débiles y 27 hashes protegidos.
- **67 de SF.1, 110 de SF.1.1/SF.2.1, 207 de D.1 y 48 de navegación de carreras**, aprobadas. El atajo SF.3 se probó mediante eventos nativos junto a cámara/audio, manteniendo el acelerador.
- **Conducción física real sobre el recorrido existente:** Original y Completo con la misma cámara/audio completaron el tramo en **32.6167 s**, pico **249.803 km/h** con el BURST ya existente, **19.3667 s** en BURST y sin contactos de pared, recuperaciones ni frames fuera de asfalto. La diferencia de progreso final sobre el recorrido fue inferior a 0.2 mm. Los tres perfiles siguen dando diferencia física máxima cero en la reproducción controlada de SF.1.
- **Shaders compilados y capturas renderizadas en la GPU**. La comparación de coste usa 1280×720, Compatibility, VSync desactivado, misma pose y FOV75, telemetría sintética de máxima normal/BURST completo. Se desactivan los streaks antiguos por igual. Tras precalentar se congela la generación cosmética, y se toman seis muestras Original/Parcial/Completo/Completo/Parcial/Original: 3 s de estabilización y 600 frames renderizados por muestra, medidos con reloj real, sin `--fixed-fps`.

En la medición actualizada tras la corrección de visibilidad, la RTX 4060 Ti registró medias **2.242 ms Original**, **2.463 ms Parcial** y **2.050 ms Completo**, con **259 llamadas de dibujo** en todos los casos. La diferencia negativa de Completo respecto a Original refleja la variación entre muestras y no demuestra una mejora de rendimiento. La búsqueda de referencias alcanzó **188 µs** y la actualización ambiental de Completo promedió aproximadamente **16–17 µs**. Había dos manchas de luz existentes activas; Parcial enlazó dos instancias y Completo diez, sin añadir geometría.

La medición de materiales en pose fija no acredita 60 FPS recorriendo toda la ciudad ni en otras computadoras. Una diferencia negativa frente a Original puede ser variabilidad del sistema, no una mejora de rendimiento. La claridad de curvas y comodidad siguen pendientes de la evaluación del jugador.

Informes: `sf3_validation.json`, `sf3_city_drive.json`, `sf3_benchmark.json`, `sf3_regressions.json`. Evidencia: `evidence/sf3_original.png`, `sf3_partial.png`, `sf3_full.png`, `sf3_panel.png`. Las imágenes del benchmark usan telemetría sintética para comparar materiales, no una captura de conducción física.

## Límites de esta primera versión

- El cambio es local y depende de referencias existentes. No se añaden farolas a los sectores que carecen de ellas ni se garantiza un cambio igual en todas las calles.
- No se recorrieron todas las calles ni todas las combinaciones extremas de ajustes. Reducir fuerzas por capa o volver a Original permite evaluar comodidad sin perder la configuración del coche.
- Los nuevos detalles están fijos al mundo. No hay animación UV acelerada, vibración, deformación de la vía, postprocesado añadido ni motion blur nuevo.
- Los VFX previos permanecen intactos; su respuesta no debe confundirse con la progresión del nuevo estado ambiental.

La entrega se detiene en SF.3 para probar cuánto aporta el entorno antes de implementar la transformación del vehículo de SF.4.
