# Rivales: nivel Experto

Implementado el 16 de noviembre de 2026. **El nivel Experto reduce entre 8.9% y 14.2% el tiempo de dos vueltas frente a Estándar en la comparación controlada con VECTOR.** No se modifican las estadísticas físicas del coche ni se garantiza que un jugador perfecto sea el único capaz de ganar.

## Uso

**Jugar → Modo carrera → seleccionar vehículo → Dificultad de los rivales → Experto.** El selector está debajo de la tabla de vehículos; la pantalla se puede desplazar. Experto es el valor inicial y la selección se guarda para futuras carreras, incluidas las iniciadas desde modo libre. Estándar sigue disponible. El nivel no se cambia durante una carrera.

Para pruebas automatizadas: `-- --ai-difficulty=expert` o `-- --ai-difficulty=standard`.

## Fundamento y alcance

[Turn 10, explicación de Drivatars de 2023](https://forza.net/news/forza-motorsport-drivatars-tire-physics), separa la línea de conducción del controlador y describe el trabajo sobre frenadas y velocidades de entrada/salida. Se aplica esa separación al planificar mejor el recorrido con los frenos y dirección del auto real. No se reproduce el entrenamiento por miles de vueltas de Forza.

[Turn 10, sistema multilínea de 2025](https://forza.net/news/forza-motorsport-drivatar-changes), propone alternativas y transiciones para circular con tráfico. Aquí inspira mantener corredores laterales y transiciones físicas de volante al intentar pasar. No se implementa su sistema privado de aprendizaje.

El objetivo es aumentar el ritmo sostenible y castigar pérdidas de velocidad mediante oportunidades reales. Exigir literalmente conducción perfecta requiere comparar con vueltas humanas; las referencias externas no certifican esa dificultad.

## Cambios implementados

- `RivalDifficulty.gd` prepara parámetros de decisión separados para Estándar/Experto. Experto utiliza más acelerador, menos reserva de TURBO y una planificación de frenado y velocidad de curva más exigente. Conserva diferencias de personalidad. Sus valores nunca se mezclan en `car.config`.
- La trayectoria experta redondea giros con radios de hasta 18 m, frente a 12 m en Estándar. Reduce el radio si falta longitud y conserva la comprobación de huella, asfalto y obstáculos; no modifica calles, edificios ni reglas de checkpoints. Una línea mejor puede aprovechar más espacio de una intersección, disponible también al jugador. La distancia oficial del circuito y los controles siguen siendo los mismos.
- El piloto solicita aceleración, frenado, volante, freno de mano y TURBO mediante el controlador físico habitual. No escribe posición, velocidad o carga de habilidades durante la conducción. Los límites de motor, aceleración, agarre, dirección, freno y BURST coinciden con el perfil disponible al jugador. No hay un multiplicador por distancia al jugador.
- Se corrige la referencia de progreso del vehículo que se intenta adelantar. Se usa la ventana de navegación del propio objetivo mediante una referencia débil; para un conductor humano cercano se usa proyección global. Se abandona un objetivo que se aleja demasiado. El contador sólo confirma un sobrepaso con más de 7 m de ventaja durante 0.5 s sobre un vehículo todavía compitiendo.
- Las transiciones de carril pasan por el desplazamiento lateral gradual del controlador. En Experto se elimina la reducción fija a 12 m/s al regresar de una línea lateral: siguen vigentes la curvatura real, el frenado anticipado, los vehículos próximos y la comprobación del espacio de incorporación.
- Los agresivos expertos tienen una secuencia de derrape: esperar una curva amplia y despejada, iniciar con velocidad suficiente, mantener carga válida, soltar y alinear, y aprovechar el boost ganado si sigue siendo seguro. Abortan por tráfico, exceso de deslizamiento o error lateral. Las curvas cerradas de Centro LP no obligan a activar una habilidad que sería contraproducente.

`GameFlow` guarda el nivel. El menú lo expone antes de la salida y rechaza niveles desconocidos o cambios durante una carrera. El selector no altera las estadísticas presentadas de VECTOR, COMET o APEX.

## Comparación directa de ritmo

Mismo VECTOR, mismo transform inicial por grupo, misma física, dos vueltas de Centro LP y ausencia de tráfico. Cambia el nivel de decisiones y la trayectoria que el piloto elige dentro de la carretera. Se mantienen las tres personalidades.

| Personalidad | Estándar | Experto | Reducción de tiempo |
|---|---:|---:|---:|
| Conservador | 78.453 s | 67.303 s | 14.2% |
| Equilibrado | 70.601 s | 62.559 s | 11.4% |
| Agresivo | 65.773 s | 59.909 s | 8.9% |

Las seis ejecuciones terminan sin salir del asfalto, tocar muros ni recuperar checkpoints. La configuración física coincide entre los niveles y con `VehicleProfiles`; el multiplicador de prueba permanece en ×1. Estas son vueltas automatizadas, no tiempos humanos ni una garantía de dificultad subjetiva.

Informes locales: `.local/artifacts/rival_acceptance_personalities_standard.json`, `rival_acceptance_personalities_expert.json` y `expert_mode_validation.json`.

## Tráfico con cinco rivales

En las tres carreras expertas de dos vueltas terminan los cinco NPC: parrilla normal con jugador automático, sin jugador en simulación/percepción, y sin jugador con la parrilla invertida. No hay salidas de asfalto, contactos con muros ni recuperaciones de checkpoints. Los coches mantienen contactos breves entre sí, por lo que no se afirma ausencia absoluta de incidentes.

Sin jugador, la parrilla normal da tiempos de 61.83–73.12 s; la invertida, 59.59–73.37 s. El resultado cambia con la salida y el tráfico. En el escenario normal con jugador automático, Luque termina en 61.80 s y el jugador de referencia en 74.45 s; ese jugador usa un piloto de prueba, no representa tu rendimiento.

La auditoría de las tres carreras informa **cero adelantamientos completados y cero corroborados**: desaparecen los seis falsos positivos de la versión anterior, pero esto no demuestra adelantamientos generales contra rivales igual de rápidos.

Una prueba controlada adicional enfrenta dos COMET físicos en una recta. El líder circula con un objetivo de 12 m/s y el perseguidor experto comienza 20 m detrás. El perseguidor se aparta hasta 3.87 m, completa el sobrepaso y llega a más de 25 m de ventaja; contador y medición coinciden, con cero contactos entre coches y misma física. No se inyecta velocidad ni se recolocan vehículos durante la conducción. El líder lento simula una pérdida de ritmo; no es una prueba de adelantamiento contra otro experto de igual velocidad.

Informes: `.local/artifacts/rival_acceptance_traffic_expert.json` y `expert_overtake.json`. La aceptación completa del punto de adelantamientos sigue pendiente.

## Derrape, Drift Boost y BURST

En la prueba circular amplia de radio 35 m, con el controlador rival real y dos vueltas:

| Rival agresivo | Recompensas reales de Drift Boost | Frames con boost previo y condiciones de aceleración |
|---|---:|---:|
| Luque, COMET | 3 | 118 |
| Dani, COMET | 3 | 118 |
| Iris, APEX | 3 | 35 |

Los frames de la última columna requieren que el impulso estuviera activo antes del paso físico, con acelerador, suelo, ausencia de freno y espacio bajo el límite de velocidad; no se cuentan sólo los frames de entrega de la recompensa. El máximo deslizamiento de los agresivos ronda 15.45–17.71°, dentro de las reglas originales. Los cinco terminan sin teletransportes ni maniobras de recuperación. Conservador y equilibrado mantienen conducción con agarre en esta prueba.

Los cinco también superan la prueba de TURBO/BURST en la recta plana de 2,500 m, obteniendo carga y estado mediante sus mandos reales. En Centro LP no se fuerza BURST: necesitan alcanzar su velocidad y tiempo de preparación originales.

Informes: `.local/artifacts/rival_acceptance_drift_probe.json` y `d3_abilities_validation.json`, ambos con `difficulty: expert`.

## Verificación y reproducción

Ejecutar `tests/run_expert_validation.ps1 -Regression`. `-SummarizeOnly` comprueba los informes existentes frente al código y calcula la comparación. `tests/run_rival_acceptance.ps1 -Difficulty expert` conserva la auditoría general y su veredicto separado de aceptación.

La validación del nivel pasa: comparación de tiempos, invariantes físicos, prueba de sobrepaso controlado, derrape efectivo de los agresivos, TURBO/BURST y selector. También pasan nueve comprobaciones de selección/guardado, trece de esfera, doce de reglas, doce de geometría y ochenta y siete del editor/vueltas. El selector se revisó en una captura renderizada: `.local/artifacts/evidence/expert_menu.png`.

La carrera completa de cinco rivales también pasa con despeje de meta, reinicio limpio, regreso al menú y transición desde/hacia modo libre. El piloto automático de esa prueba comparte la geometría del nivel seleccionado; conserva sus parámetros estándar de decisión. El archivo `ArcadeCar.gd` mantiene el mismo hash que antes de esta implementación.

Los resultados generados permanecen en `.local/artifacts/`. Los informes distinguen `passed` para validar esta implementación de `ai_acceptance_complete` y `human_difficulty_validated`, que permanecen en `false`.

## Lo que aún necesita una carrera humana

La IA experta es más rápida en estas pruebas, pero la sensación de justicia y el margen que deja al jugador aún no están aceptados. La conducción humana puede encontrar líneas o usar habilidades mejor que el controlador. Siguen pendientes adelantamientos consistentes entre rivales de ritmo similar, más circuitos y una comparación contigo en dos vueltas. La velocidad de una prueba automatizada no certifica una carrera divertida ni obliga por sí sola a conducir perfectamente.
