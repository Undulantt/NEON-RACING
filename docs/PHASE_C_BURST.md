# Fase C — BURST, turbo, Drift Boost y perfiles

Actualización de presentación: [cuenta regresiva, llamas, velocidad, FOV y selección del perfil en Godot](BURST_PRESENTATION.md).

Implementación del 3 de noviembre de 2026, basada en [la especificación autorizada](BURST_DESIGN_SPEC.md). Los valores se mantienen como balance inicial; las mediciones siguientes proceden del controlador real, no de las puntuaciones de interfaz.

## Arquitectura y uso

Se conserva `CharacterBody3D`, la caja al 80%, los contactos con el relieve, recuperación, streaming y la ciudad nocturna. `ArcadeCar.gd` sigue resolviendo movimiento y colisiones. `DrivingAbilities.gd` calcula los estados de BURST, el límite vigente, la reserva de turbo y la recompensa de derrape. Las propiedades anteriores del coche delegan en esa capa para conservar cámara, partículas, estelas y audio de fase E.

`VehicleProfiles.gd` combina los parámetros comunes de `config/driving_config.json` con los bloques `physics` y `abilities` de `config/vehicles/vector.json`, `comet.json` y `apex.json`. Un solo controlador sirve para los tres. Las ocho puntuaciones se derivan de parámetros explícitos con escalas de comparación; no alimentan la física. `Profiles.load_profile(id)` entrega configuración, rol y estadísticas para el futuro selector.

VECTOR es el perfil por defecto. Para probar los demás desde la carpeta del proyecto:

```powershell
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . -- --vehicle=COMET
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . -- --vehicle=APEX
```

También se puede configurar `vehicle_profile` en la instancia de `PlayerCar` antes de añadirla al árbol. `apply_vehicle_profile("APEX")` permite cambiar en reposo; devuelve `false` si el coche está en movimiento o el identificador no existe. El selector visual, los tres modelos finales y la persistencia de la selección corresponden a la próxima beta.

Controles de teclado conservados. Mando: RT acelerar, LT frenar/reversa, stick izquierdo girar, A derrape, X turbo, Y recuperar y Start pausa. Se usan valores analógicos sin remapeo alrededor del umbral de BURST, con filtrado de ruido de 0,05 en acelerador y 0,10 en freno. Se vacía el buffer de entradas antes de cada paso para que un evento recibido cancele en ese paso también cuando el render agrupa varios pasos físicos. Las pruebas de mando inyectan eventos reales de la API de entrada; falta valorar el tacto con hardware físico.

El coche expone `burst_started`, `burst_ended(reason)`, `drift_boost_triggered(strength)`, `turbo_changed(active, charge)`, `vehicle_profile_changed(id)` y `physics_updated`. Este último permite instrumentar después de resolver movimiento y recompensas, sin desfase de un paso en los ensayos.

## BURST

- Estados: NORMAL → PREPARATION → BURST → RECOVERY.
- Preparación con acelerador ≥0,85, suelo y avance longitudinal ≥95% del límite base. Tiempo por perfil: 3 / 3,5 / 2,5 s.
- Bonificación creciente por segundos reales activos, limitada a 35 / 45 / 30%. Amplía el margen del motor; no suma ni asigna velocidad.
- Soltar acelerador por debajo de 0,85, frenar por encima de 0,10, freno de mano, reversa/parada, inspección, recuperación o perder avance por debajo del 90% cancela el progreso y el bonus en el mismo paso. Después de `move_and_slide`, se vuelve a comprobar la pérdida de avance para que una colisión no conserve BURST un paso más.
- Al cancelar se restaura inmediatamente el límite. El exceso se pierde mediante resistencia adicional de 7,5 m/s²; con acelerador suelto se añade la resistencia normal de 0,6 m/s². Frenar sigue aportando su fuerza de servicio. No se aplica un clamp a la velocidad existente ni se teletransporta el coche.
- RECOVERY impide rearmar usando velocidad residual. Vuelve a NORMAL al regresar al límite, con tolerancia numérica de 0,01 m/s.
- La velocidad elegible es la proyección longitudinal sobre el plano de apoyo reconstruido con la normal del suelo. La velocidad lateral y la caída no cuentan como avance. En el aire solo se conserva el componente horizontal para comprobar mantenimiento.
- Un vuelo corto conserva BURST pero congela su crecimiento; tras más de 0,5 s sin apoyo se cancela. La preparación exige suelo.
- Se conserva la penalización moderada del terreno de C.6: el límite y los umbrales de velocidad usan el 90% de la base del perfil fuera de asfalto, de modo que allí también se pueden preparar BURST y usar ambas recompensas. La cifra BASE del HUD sigue mostrando la referencia del perfil, y LÍMITE muestra el techo contextual real. Una salida ordinaria al terreno reduce el exceso a 3 m/s²; una recuperación de BURST usa 7,5 m/s² también en terreno.

## Motor y habilidades

La aceleración de baja velocidad se calcula desde el objetivo 0–100 de cada perfil. Después de 100 km/h disminuye suavemente hasta un 65/70/65% del valor inicial; conserva potencia suficiente para aprovechar el crecimiento BURST. Las fuerzas de habilidades se suman a ese motor, multiplicadas por acelerador y por el modo de prueba T si está activo. Solo se limita el incremento nuevo de motor al margen disponible: la velocidad previa por pendientes o inercia se conserva y pierde gradualmente con resistencia.

Con estos nuevos objetivos, VECTOR no arrancaba inicialmente en la cuesta sintética del 25% usando la gravedad existente de 22 m/s². Se añadió compensación de par del 55% de la carga gravitatoria cuesta arriba, aplicada proporcionalmente al acelerador. No modifica gravedad, el avance sin motor ni las fuerzas en vuelo. El ensayo verifica retroceso con poca potencia, frenado en cuesta, subida a fondo y conservación de impulso en saltos. La velocidad máxima en pendiente se convierte al plano del suelo para no ganar límite artificial por el componente vertical.

Turbo añade +2,5 / +2,8 / +2,1 m/s² y dura nominalmente 5 / 6 / 4 s. Comparte techo con el motor; antes de BURST no eleva la velocidad base. Recarga completa en 18 s, tras 1,5 s de espera. Mantener pulsado después de agotarlo no crea pulsos automáticos: hay que soltarlo para habilitarlo de nuevo.

Drift Boost exige avance ≥55 km/h, deslizamiento de 12–35°, giro real, al menos 0,6 s válidos y carga suficiente. La recompensa se obtiene una vez al soltar el derrape y alinear por debajo de 10° durante 0,1 s. Choques y trompos fuera de control pierden la carga. El cooldown entre premios es de 0,65 s. La rotación del agarre durante el derrape conserva la magnitud de movimiento previa a esa corrección; se eliminó la pérdida artificial causada por interpolar vectores. El freno de mano conserva su frenado explícito y mantiene el vehículo detenido en una cuesta.

El premio aplica +2,8 m/s² durante 0,9 s para VECTOR, +1,9 durante 0,7 s para COMET y +4,0 durante 1,25 s para APEX, con potencia proporcional a la calidad acumulada. Turbo y Drift Boost pueden coincidir y comparten el mismo límite. El premio no inicia ni conserva BURST por sí mismo. Una salida válida devuelve hasta 6% de reserva, sin regenerar si ese paso consumió turbo, incluido el paso en que se agota.

## Perfiles y mediciones

| Perfil | Base km/h | Máximo BURST teórico km/h | 0–100 objetivo s | 0–100 medido s |
|---|---:|---:|---:|---:|
| VECTOR | 185 | 249,75 | 5,3 | 5,32 |
| COMET | 205 | 297,25 | 6,1 | 6,12 |
| APEX | 175 | 227,50 | 4,9 | 4,90 |

Las ocho puntuaciones derivadas coinciden con las referencias 1–10 de la propuesta. Por ejemplo, velocidad usa umbrales de velocidad base; aceleración, el objetivo físico 0–100; frenado, la desaceleración; turbo y Drift Boost, su aporte de aceleración integrado en la duración nominal. BURST combina techo teórico, crecimiento y tiempo de preparación. Los parámetros numéricos de detalle siguen disponibles junto a las puntuaciones.

Plataforma sintética plana, salida desde reposo sin turbo manual en las rectas:

| Ensayo | VECTOR s | COMET s | APEX s |
|---|---:|---:|---:|
| 500 m | 14,73 | 15,23 | 14,42 |
| 1 km | 22,68 | 23,02 | 22,43 |
| 2 km | 37,10 | **35,30** | 38,27 |
| 1,75 km con cuatro giros de 90° | 68,32 | 70,78 | **67,57** |

APEX aprovecha su salida y preparación temprana en rectas cortas. COMET necesita una recta más larga para compensar su aceleración inicial y aprovechar el techo final. VECTOR queda cerca de los mejores en ambos ensayos. No se ha igualado artificialmente a los perfiles.

Se recorrieron tres rutas geográficas completas por perfil, unos 17,02 km por coche y 51,06 km acumulados. Mismo piloto de seguimiento de ruta con acelerador, frenado y turbo; sin corregir posición ni optimizar técnicas de derrape.

| Ruta real | Distancia | VECTOR s | COMET s | APEX s |
|---|---:|---:|---:|---:|
| Federal 1 / Cajoncito | 9,35 km | 288,08 | 323,98 | 271,82 |
| Barrios del norte | 3,97 km | 209,35 | 240,00 | 195,35 |
| Malecón / costa norte | 3,70 km | 150,82 | 172,17 | 141,23 |

Los nueve recorridos terminaron con cero salidas de asfalto, contactos con paredes y recuperaciones. Hubo vuelos pequeños sobre el relieve, sin valores no finitos ni correcciones por recuperación. El piloto compara los mismos criterios de conducción usando el frenado y manejo propios de cada perfil.

El análisis de caminos alineados, con hasta 12° de cambio acumulado de rumbo, encontró aproximadamente 1.271 m en Federal 1, 1.463 m en Forjadores y 1.694 m en C2; una alineación no garantiza ausencia de pendientes, cruces o necesidad de frenar. En Federal 1 se alcanzaron bonus de 35% con VECTOR, 28,9% con COMET y 30% con APEX. Barrios del norte no permitió activar BURST con este piloto; en el Malecón su uso fue breve. El mapa conserva su geometría. C2 sirvió para verificar visualmente un sprint con BURST real.

Este primer balance favorece APEX en los tres trayectos urbanos ensayados. COMET demuestra su especialidad en la recta plana de 2 km. Antes de cerrar balance de carrera se necesita prueba humana y un piloto que use derrapes; estos resultados no prueban igualdad competitiva en cualquier ruta ni una IA de carrera final.

## HUD y verificación

Se conservaron minimapa, calle, velocímetro, turbo, derrape y pausa. Se añadieron estado BURST, preparación, porcentaje activo, perfil, base y límite real. El velocímetro de aguja adapta su escala al máximo teórico del perfil y al modo T. Drift Boost usa su nombre propio y tiempo restante. Los controles de mando aparecen en pausa.

`docs/evidence/burst_hud_normal.png` y `burst_hud_active.png` se capturaron en `Main.tscn`, ciudad nocturna de producción. La captura activa procede de una salida desde reposo y conducción física por el tramo alineado de C2, sin simular los valores del HUD: velocidad 203,70 km/h y límite 203,75 km/h con BURST +10,13%, sin choques ni recuperaciones.

Pasaron:

- `godot_burst.gd`: estados y temporizadores, límites, cancelación por input y por choque físico, recuperación suave, bloqueo por exceso residual, lateral/caída, tolerancia de vuelos, recarga sin consumo simultáneo, teclado W/D/Espacio, eventos de mando, ruido analógico, derrape en ambas superficies, recompensa única, cooldown, pausa y señales.
- El mismo ensayo con deltas de render de 30, 60 y 120 FPS, conservando física a 60 Hz: resultados idénticos en 0–100 y velocidad BURST tras 30 s. Es una prueba de independencia del render, no una medición de rendimiento en FPS.
- `godot_drift_rewards.gd`: comparación física de la misma salida con y sin premio. Diferencia medida tras medio segundo: +1,07 m/s con 77,8% de calidad.
- `godot_phase_c.gd`, `godot_phase_c6.gd` y `godot_debug_speed.gd`: integración, cámaras, pausa, terreno, turbo y modo T con los perfiles actuales. Las expectativas históricas de turbo elevando el límite fueron sustituidas por el nuevo diseño.
- `godot_slope_physics.gd`: apoyo, gravedad, carga de motor, retroceso, frenado, despegue y aterrizaje.
- `godot_real_crest.gd`: salto de la calle Miguel Hidalgo, 19 pasos en el aire, aterrizaje sin choque o recuperación, neumáticos con al menos 4 mm de separación. La comprobación ahora lee el radio real de la rueda al 80%, en lugar de usar el radio anterior a C.6.
- `phase_e_motion.gd`: estelas, desenfoque periférico, pausa, recuperación y modos F4 compatibles.
- `benchmark_burst_balance.gd` y `capture_burst_hud.gd`: recorridos, balance e integración visual real.

Los informes agregados y hashes de código, habilidades y perfiles están en `burst_summary.json` y `burst_validation*.json`. `relief_migrations.json` conserva el archivo histórico exacto esperado por los datos urbanos y fija la nueva migración a estas pruebas; la validación urbana también comprueba los hashes de las nuevas fuentes de habilidades. Los archivos anteriores a esta implementación quedan en `burst_baseline/`.

El primer benchmark concurrente emitió una advertencia no fatal del pool de tareas de Jolt, sin fallos de recorrido. La captura OpenGL registró el aviso existente de inicialización de caché de shaders y renderizó correctamente. El importador del editor completó el registro de clases sin errores de script, pero emitió «Safe save failed» al arrancar; queda registrado en `burst_editor_import.log`. Los hashes finales de las fuentes y las pruebas de ejecución se verificaron correctamente. Las pruebas no sustituyen la evaluación del manejo con teclado y mando físico.

```powershell
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location) '.godot/test_userdata'
& $g --headless --path . --fixed-fps 60 --script tests/godot_burst.gd
& $g --headless --path . --fixed-fps 30 --script tests/godot_burst.gd -- --report-suffix=_render30
& $g --headless --path . --fixed-fps 120 --script tests/godot_burst.gd -- --report-suffix=_render120
& $g --headless --path . --fixed-fps 60 --script tests/benchmark_burst_balance.gd
& $g --path . --fixed-fps 60 --script tests/capture_burst_hud.gd
```

Referencias de integración: [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html), [Input](https://docs.godotengine.org/en/stable/classes/class_input.html). El modelo físico concreto y los resultados anteriores corresponden al código y a los ensayos del proyecto.
