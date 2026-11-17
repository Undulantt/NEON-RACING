# Checkpoints esféricos y auditoría de habilidades

**Actualización:** los agresivos del [nivel Experto](RIVAL_EXPERT_MODE.md) ya obtienen Drift Boost en una prueba de curva amplia. Las mediciones siguientes corresponden al controlador anterior.

16 de noviembre de 2026. Alineación: Luque/COMET/agresiva, Guille/APEX/conservador, Dani/COMET/agresiva, Xavi/VECTOR/equilibrado e Iris/APEX/agresiva.

## Cambio de detección

El checkpoint acepta el contacto con una esfera 3D en vez de exigir atravesar el plano del aro. El radio es `half_width_m × 1.3`, conservando la anchura útil anterior. Su centro está 0.75 m sobre la carretera local. Se muestrea el relieve de cada checkpoint al preparar la carrera y se conservan las alturas reales anterior/actual del coche. El aro sigue como referencia visual.

La intersección se calcula sobre todo el segmento de movimiento entre pasos físicos. Así se registra un paso rápido aunque ambas posiciones estén fuera, y se interpola el instante del primer contacto. Se admite desplazamiento lateral durante un derrape. El chequeo vertical usa la distancia 3D a la esfera; ya no se recorta el volumen a una banda de altura de 3.5 m.

Se mantienen el orden obligatorio, rechazo de marcha en sentido contrario, rechazo de teletransportes, bloqueo durante recuperación y cuenta regresiva y todas las puertas antes de conceder otra vuelta. Un vehículo inmóvil no consume controles. Esferas próximas pueden registrarse en un mismo paso si el segmento las alcanza en orden; un paso no puede consumir dos vueltas. La misma detección se aplica al jugador y a los NPC, incluida la llegada. Los tiempos nuevos se miden al contactar la esfera, por lo que no equivalen exactamente a los tiempos anteriores del plano.

La esfera es un disparador lógico barrido, no una pared física. No aplica fuerzas ni mueve el coche.

## Pruebas de checkpoints

- `godot_checkpoint_spheres.gd`: 13 comprobaciones aprobadas. Entrada lateral sin cruzar el plano, barrido rápido, tiempo de contacto, altura y distancia 3D, sentido contrario, inmovilidad, teletransporte, recuperación, controles solapados y orden obligatorio.
- `godot_checkpoint_drift.gd`: control positivo con APEX y acelerador/dirección/freno de mano programados, usando física real y sin inyectar velocidad, carga o recompensas. Derrape válido 1.20 s, deslizamiento máximo 29.70°, una recompensa y Drift Boost con aceleración habilitada durante 1.25 s. El checkpoint se valida durante el derrape y antes del antiguo plano. Cero contactos de pared y recuperaciones. Este control positivo no es una prueba del controlador rival.
- Reglas de carrera: 12 comprobaciones; trayectoria continua y densidad de controles: 12; editor/vueltas: 87; navegación y recuperación: 48. Todas aprobadas.

Informes: `checkpoint_spheres_validation.json`, `checkpoint_physical_drift_validation.json` y logs `sphere_godot_*.log`.

## Rivales en Centro LP, dos vueltas

`godot_phase_d3.gd -- --rivals=5 --audit-abilities` observa sólo el tiempo de competición de cada coche. Excluye cuenta regresiva y retirada: usar el freno de mano al estacionar no cuenta como intento de derrape. Finaliza al terminar todos; esta modalidad no exige completar el estacionamiento posterior. El jugador de prueba usa piloto automático y se informa por separado de los cinco rivales.

| Rival | TURBO activo | Peticiones de derrape | Drift Boost ganado | Entradas en BURST |
|---|---:|---:|---:|---:|
| Luque | 16.28 s | 0 | 0 | 0 |
| Guille | 9.00 s | 0 | 0 | 0 |
| Dani | 13.87 s | 0 | 0 | 0 |
| Xavi | 9.97 s | 0 | 0 | 0 |
| Iris | 6.30 s | 0 | 0 | 0 |

Los cinco completan las dos vueltas. Ninguno acumula carga válida de derrape ni recibe aceleración de Drift Boost. Ninguno llega siquiera a preparar BURST en esta prueba. Por tanto, **actualmente los rivales aprovechan TURBO, pero no derrape/Drift Boost ni BURST en Centro LP**. No se modifica la estrategia de IA para esconder ese resultado.

El controlador sólo solicita derrape a los agresivos si coinciden un error angular moderado, suficiente anchura, velocidad actual sobre el mínimo y velocidad objetivo superior a 16 m/s. Esas condiciones no coinciden en esta carrera. La siguiente mejora de comportamiento requiere una estrategia de entrada, mantenimiento y salida del derrape; activar el freno de mano al azar no demuestra uso correcto.

BURST exige alcanzar el 95% del límite base y mantener acelerador durante el tiempo de preparación del coche. Los picos medidos aquí son aproximadamente 102–118 km/h, por debajo de los umbrales de APEX (166.25), VECTOR (175.75) y COMET (194.75 km/h). La ausencia de BURST en este circuito no prueba que el controlador sea incapaz de usarlo en una recta adecuada.

Informe detallado: `d3_ability_race_audit.json`. Incluye peticiones y calidad/carga de derrape, recompensas, tiempo de boost con condiciones de aceleración, preparación/entradas/bonificación de BURST, velocidad máxima y frames por corredor.

## BURST: prueba positiva de los cinco rivales

`godot_d3_abilities.gd` ejecuta cada combinación actual de auto y personalidad en una recta sintética plana de 2,500 m. Se usan el controlador rival, coche y habilidades reales; no se inyectan velocidad, combustible, carga ni estado BURST.

| Rival | BURST activo | Bonificación máxima del límite | Velocidad máxima |
|---|---:|---:|---:|
| Luque | 25.35 s | 45% | 297.26 km/h |
| Guille | 34.02 s | 30% | 227.50 km/h |
| Dani | 25.35 s | 45% | 297.26 km/h |
| Xavi | 31.13 s | 35% | 249.75 km/h |
| Iris | 34.98 s | 30% | 227.50 km/h |

Los cinco pasan: activan TURBO, obtienen BURST y circulan por encima de su límite base. Esta prueba demuestra capacidad en una recta larga; no demuestra uso de BURST en la carrera urbana ni uso de derrape por la IA. Informe: `d3_abilities_validation.json`.

## Repetir

Suite: `tests/run_d3.ps1 -RivalCounts 5 -AbilitiesAudit -Regression`. Añadir `-Traffic` para las pruebas de jugador inmóvil. Los procesos usan un perfil local aislado y ajustes temporales por PID; el piloto automático sólo existe en los scripts de prueba. No se ha realizado aceptación humana del cambio.
