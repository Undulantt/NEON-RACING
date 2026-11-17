# D.3 — Competición beta: rivales y circuito de dos vueltas

**Aceptación pendiente:** la [auditoría de los cinco criterios](../design/RIVAL_AI_ACCEPTANCE_AUDIT.md) detecta falsos positivos en el contador de adelantamientos y falta de derrape del piloto rival. Las cifras históricas de `completed_passes` no certifican sobrepasos reales. No se da por terminada la IA.

**Revisión vigente de navegación y tráfico:** [D3_CONTINUOUS_AI.md](../design/D3_CONTINUOUS_AI.md). La descripción del controlador por checkpoints de esta entrega queda como historial; actualmente se sigue una trayectoria continua compartida con corredores laterales y frenado por curvatura.

## Estado

Implementada la carrera jugable de seis participantes. El menú Carrera y el punto de inicio del modo libre usan `centro_circuit_d3`: 626.097 m por vuelta, dos vueltas, 39 controles por vuelta, aproximadamente 1,252 m totales. Es un circuito ficticio trazado sobre calles reales del grafo OSM existente, próximo al Malecón, Antonio Mijares y Sebastián Lerdo de Tejada. No modifica la cartografía.

La implementación supera carreras físicas de dos vueltas con cinco rivales y pruebas de reinicio, menú y modo libre. **La aceptación completa de D.3 sigue pendiente de una carrera humana completa, de validar Drift Boost de la IA y de revisar rendimiento en tiempo real en el equipo objetivo.** No se ha avanzado a D.4.

## Auditoría y reutilización

| Sistema existente | Decisión |
|---|---|
| ArcadeCar / set_controls / external_control | Misma escena y controlador para jugador y rivales; la IA sólo escribe mandos |
| VECTOR, COMET, APEX / VehicleProfiles | Se reutilizan sin modificar estadísticas ni escalas de dificultad |
| DrivingAbilities / transmisión | Reserva TURBO, derrape, recompensas y BURST originales; sin inyectar carga o velocidad |
| RoadGraph / RaceStore / editor D.2 | Ruta cerrada generada por Store.create con tres anclas OSM; formato y validación canónica intactos |
| RaceSession | Una instancia por participante; se conservan controles barridos, orden, sentido y rechazo de teletransporte/altura inválida |
| RaceActivity / GameFlow | Preparación, cuenta regresiva, recuperación del jugador y flujo existentes; se añade el propietario de los rivales |
| Colisiones | Los coches estaban en capa 16 pero su máscara 15 excluía otros coches; ahora máscara 31 y comprobación de giro/pose 28 |
| Streaming vial y urbano | Vecindarios de todos los rivales además del jugador; se liberan al terminar la actividad |
| HUD / resultados | Se añaden clasificación completa, posición, tiempo de vuelta y tabla que continúa actualizándose tras la llegada del jugador |

No se reconstruye la ciudad, el editor, el sistema de vueltas ni la física.

## Arquitectura

`RaceCompetition.gd` posee las referencias a los seis corredores, cinco coches y cinco controladores `RivalDriver`. Mantiene una sesión por rival. `RaceActivity` conserva la sesión del jugador. Los relojes reciben el mismo delta de física y la misma duración de cuenta regresiva; todos permanecen inmovilizados durante ésta.

El controlador inicial apuntaba al siguiente checkpoint obligatorio con control proporcional angular. Eso evitaba saltarse las puertas de D.2 situadas en vértices, pero producía conducción rígida y lenta. La revisión continua conserva esas puertas como validación y calcula una curva físicamente comprobada que las cruza: véase el documento vigente enlazado arriba. No se escribe el transform durante la conducción.

La parrilla actual usa dos columnas y tres filas cuando la anchura y el apoyo físico lo permiten: 4.4 m entre columnas y 7 m entre filas. El jugador comparte la primera fila con un rival; los demás quedan detrás. Cada pose se consulta contra carretera y obstáculos. Las salidas estrechas conservan separación longitudinal. La parrilla está validada para este circuito; recorridos arbitrarios del editor necesitan comprobar su salida, sobre todo sprints cuya carretera no se prolongue detrás del inicio.

La clasificación ordena por llegada medida y desempate de llegada; después, vueltas, controles y proyección sobre el segmento real de la calle entre controles. Nunca usa distancia recta a meta. Las vueltas y la llegada usan la fracción del frame en la que se cruzó la puerta. Cada resultado incluye coche, nombre, estado, tiempos medidos y mejor vuelta; `elapsed_seconds` es null para quien aún no terminó.

Los rivales siguen conduciendo después de terminar el jugador para actualizar resultados. No se inventan tiempos ni se fuerza que todos terminen juntos. Los botones permiten salir antes, dejando identificados los pendientes.

## Personalidades y tráfico

Configuración: `config/rivals.json`. Cantidad predeterminada: cinco, editable entre cero y cinco. Distribución inicial:

| Rival | Coche | Personalidad |
|---|---|---|
| Luque | COMET | Agresiva |
| Guille | APEX | Conservador |
| Dani | COMET | Agresiva |
| Xavi | VECTOR | Equilibrado |
| Iris | APEX | Agresiva |

Alineación actualizada según la tabla del usuario. Las mediciones y capturas anteriores conservan los nombres y la distribución utilizados en aquellas pruebas.

Los perfiles cambian anticipación, velocidad deseada de esquina, pedal, distancia de seguridad, permiso para adelantar y reserva mínima de TURBO. No multiplican velocidad máxima, aceleración física, agarre ni frenos.

La detección de otros coches proyecta su separación longitudinal/lateral, ignora alturas diferentes y limita la velocidad de aproximación. Los adelantamientos requieren recta, anchura, espacio lateral y una pose segura con apoyo físico en el carril de destino. Se mantiene el carril de adelantamiento hasta dejar atrás el coche completo; el regreso al centro es progresivo. Los conservadores también rodean coches detenidos, aunque evitan adelantamientos competitivos a coches en marcha. Se mantienen las colisiones físicas. Rayos frontales detectan edificios y barreras. Ante bloqueo sostenido se intenta una reversa limitada con comprobación de obstáculo y apoyo detrás, sin recolocación. No equivale a planificación completa de tráfico urbano.

Los NPC usan el aspecto nocturno existente y etiquetas de nombre/coche. Su audio no espacial se silencia para evitar cinco motores 2D superpuestos; el audio del jugador sigue intacto. Audio espacial de rivales queda como mejora posterior.

## TURBO, derrape y BURST

- TURBO probado en los cinco rivales, consumiendo las reservas normales. El perfil cambia el umbral para pedirlo y la recta disponible.
- BURST: se mantiene el acelerador al alcanzar el límite físico para permitir su preparación normal; se pierde al frenar para una curva. La prueba física aislada de 2,500 m rectos obtiene TURBO y BURST, llega sin velocidad/carga inyectadas y alcanza 82.573 m/s con el COMET y su bonus BURST normal de 45%.
- En el circuito urbano de 626 m las rectas no dan para preparar BURST: cero frames de BURST medidos. Esto no se compensa con una bonificación artificial.
- El agresivo puede pedir freno de mano en una curva moderada, con velocidad suficiente y calle amplia. **No se ha validado una recompensa Drift Boost de la IA:** en este circuito las calles son demasiado estrechas para el margen seleccionado y el contador medido es cero. La solución pendiente es validar un recorrido más amplio y una trayectoria de curva continua que sostenga el derrape durante la duración y ángulo exigidos por DrivingAbilities; después ajustar la decisión de entrada/salida. No se concede recompensa directamente.

## Pruebas

Se ejecutó el motor Godot 4.7.2 local, con colisiones y relieve reales en la carrera. El jugador de las pruebas automáticas recibe mandos de un controlador de ensayo; esto **no es una prueba humana** ni incorpora autopiloto al jugador normal.

| Prueba | Resultado / evidencia |
|---|---|
| A: un rival, dos vueltas | Completada; `d3_validation_1.json` |
| B: dos rivales, dos vueltas | Completada; `d3_validation_2.json` |
| Configuración de tres rivales | Completada; `d3_validation_3.json` |
| C/D: cinco rivales + coche del jugador, dos vueltas | Todos terminan; `d3_validation_5.json` |
| Repetición de cinco rivales | Varias carreras; las últimas repiten los seis tiempos y no usan reaparecer |
| Parrilla y cuenta regresiva | Seis poses seguras e inmovilizadas; verificadas en el informe |
| Reinicio y limpieza | Seis cuerpos tras reiniciar; `d3_lifecycle_validation.json` |
| Menú y modo libre | Regresos y selección de coche conservada; mismo informe |
| Reglas de vuelta y clasificación | 12 comprobaciones; `d3_rules_validation.json` |
| Regresión editor/circuitos D.2 | 87 comprobaciones; `d3_regression_verified.log` |
| TURBO/BURST con conducción autónoma | Prueba física recta; `d3_abilities_validation.json` |
| Carrera renderizada | Los seis terminaron; `d3_visual.log` y capturas en `.local/artifacts/evidence/d3_*.png` |

Las reglas comprueban sentido inverso, salto de controles, cruzar sólo la meta, cruzarla repetidamente, salto de posición y altura inválida; se rechazan. También comprueban dos vueltas completas, tiempos finales inmutables y orden de clasificación.

La ejecución renderizada se observó en marcha y en la segunda vuelta; se revisaron también la captura de resultados y el HUD. Era una ejecución previa a los últimos ajustes de seguridad y limpieza. El control de computadora se detuvo mediante Escape y no se enviaron más entradas a ventanas. **Falta validar manualmente una carrera completa con conducción humana, incluidos accidentes deliberados y los botones de resultados de la versión final.** Las capturas y la simulación no sustituyen esta validación.

## Incidentes encontrados y corregidos

1. Adelantar cerca de una curva costera podía sacar coches del asfalto. Ahora se exige recta y una pose física segura de destino. La reproducción fallida motivó estas restricciones; las repeticiones posteriores terminan con los seis.
2. Un coche terminado cerca de la meta provocaba frenado preventivo antes del plano de llegada. Se reduce la distancia de aproximación a coches inmovilizados, conservando el espacio físico y las colisiones.
3. Los coches que habían terminado podían ocupar la salida al reiniciar y hacer fallar la validación de aparición. GameFlow libera la competición anterior antes de validar la nueva parrilla.
4. F7 ya abre la mezcla de audio nocturna. La cámara de observación se trasladó a Ctrl+Alt+O para no compartir ese atajo.
5. Los primeros ensayos del editor no podían guardar en el user:// habitual por las restricciones del entorno. La repetición con APPDATA aislado dentro del proyecto pasó las 87 comprobaciones. No se cambiaron permisos ni ajustes del usuario.

## Rendimiento y alcance pendiente

Los cálculos de tráfico recorren como máximo otros cinco coches y la anticipación examina once puertas. El streaming consulta celdas locales de rivales, sin construir cinco ciudades ni buscar rutas A* por frame. La geometría vial y los datos del mapa se reutilizan.

La última medición headless de seis coches tardó aproximadamente 58 s de tiempo real para 316 s de simulación, con física fija a 60 Hz. El monitor de física de Godot, excluyendo carga/cuenta regresiva, registró percentil 95 de 20.24 ms y máximo de 30.65 ms. No es una medición aislada del coste de IA ni una certificación de 60 FPS renderizados; sigue pendiente medir frame time y stutter en tiempo real en el equipo objetivo. El informe JSON conserva los valores exactos de cada ejecución. En las repeticiones con uno y dos rivales se registraron picos aislados de aproximadamente 158 y 189 ms; su origen no está aislado. Estos picos requieren perfilado y no se consideran resuelta la fluidez ni la meta de 60 FPS.

La conducción de esquinas es deliberadamente prudente. El equilibrio competitivo y la velocidad media necesitan ajuste con un jugador humano. Las rutas del editor distintas del circuito distribuido, accidentes extremos y recuperación junto al agua requieren pruebas adicionales. Si un coche no logra terminar permanece indicado como En carrera; no se registra una llegada inventada.

## Cómo probar

Abrir el proyecto y elegir Jugar → Carrera → vehículo → iniciar. Desde modo libre, acercarse al punto de inicio y confirmar. No hay que regenerar datos.

- F6: telemetría, ruta común y líneas de objetivo de cada rival.
- Ctrl+Alt+O: recorrer cámara de los rivales y volver al jugador. La clasificación y los instrumentos siguen siendo del jugador.
- `--rivals=1`, `--rivals=3`, `--rivals=5`: cantidad temporal al ejecutar Godot; también admite dos para la prueba B.
- `config/rivals.json`: personalidades, alineación y cantidad persistente.

Desde PowerShell, `./tests/run_d3.ps1 -Regression` reproduce reglas, habilidades, cantidades 1/2/3/5 y ciclo de vida. Se puede pasar `-Godot <ruta al ejecutable>` y `-RivalCounts 1,5`. Usa un perfil de usuario aislado bajo `.godot-local-profile/d3-validation` y lo restaura al salir.

`tests/build_d3_circuit.gd` regenera únicamente el JSON del circuito con el Store de D.2; no es necesario para jugar. Las anclas son 6195649062, 313407104 y 313407631, con separación de controles de 20 m y sin contrasentido.

## Ajuste tras prueba humana: ritmo de IA y arcos

Se eliminó la penalización excesiva de velocidad ante errores de rumbo pequeños. En rectas, el objetivo mira entre 3 y 12 m después de una puerta colineal para evitar correcciones bruscas justo al pasarla. En intersecciones sigue siendo obligatorio cruzar la puerta antes de cambiar de calle. Las esquinas se abordan a 5.5 / 6.5 / 7.5 m/s según personalidad, con frenado menos anticipado y margen de 4 m. Se conservan estadísticas, colisiones, reservas y reglas de habilidades.

Comparación de dos vueltas con seis coches y el mismo controlador de ensayo:

| Rival | Antes | Ahora | Menos tiempo |
|---|---:|---:|---:|
| Brisa | 218.22 s | 94.54 s | 56.7% |
| Faro | 316.10 s | 162.51 s | 48.6% |
| Duna | 218.58 s | 96.17 s | 56.0% |
| Coral | 276.78 s | 99.93 s | 63.9% |
| Rayo | 277.82 s | 100.62 s | 63.8% |

Todos completaron las dos vueltas sin reaparecer. Reinicio, regreso al menú y regreso al modo libre también pasaron. Faro aún pierde tiempo en tráfico y hace maniobras de recuperación; los tiempos no representan equilibrio de dificultad definitivo. Informes conservados: `d3_speed_before.json`, `d3_speed_after.json`, `d3_speed_validation.log`.

Los aros ahora entierran la mitad del radio en la carretera, frente a un cuarto anterior. Se conserva el ancho del paso a nivel del suelo, reduciendo la altura visible para que parezcan arcos. La geometría y el flujo se verifican con `godot_race_navigation.gd`; sigue pendiente revisar visualmente el nuevo aspecto en juego.

Repetición del ajuste: los seis volvieron a completar las dos vueltas. Cuatro rivales repitieron tiempos de 94.54–100.62 s y Faro terminó en 165.51 s. El coche de ensayo tardó más al reincorporarse, por lo que la recuperación y el tráfico siguen siendo áreas de ajuste. La regresión de navegación y geometría pasó 48 comprobaciones (`d3_arch_validation.log`).

## Corrección de bloqueos con jugador inmóvil

La prueba humana detectó una dependencia práctica del jugador: salida en fila india, conservadores incapaces de rodear un coche parado y comprobaciones de reversa demasiado amplias. Se corrigieron también el uso doble del desplazamiento de carril al medir separación y la vuelta prematura al centro antes de despejar el obstáculo.

Cambios:

- Parrilla de dos columnas sobre el circuito distribuido, con poses físicas comprobadas. No se colocan seis vehículos lateralmente sobre una carretera estrecha.
- Rodeo de coches parados disponible para todas las personalidades. Se consideran ambos lados, espacio entre coches, apoyo en puntos de entrada y destino, y distancia a la siguiente curva. La maniobra se inicia con más de 45 m de recta disponible y se abandona a 30 m de una curva; la velocidad durante el desplazamiento lateral se limita a 12 m/s.
- El objetivo lateral de la maniobra se fija desde el inicio; suavizar primero ese objetivo hacía que el coche llegara al parachoques antes de empezar a separarse. El movimiento sigue suavizado por la dirección y la física normales del vehículo.
- Detección de falta de progreso incluso si el coche sigue moviéndose en círculos. Recuperación con reversa, avance si esa salida está libre y cesión de espacio a un vehículo que está atravesado. Los contactos existentes pueden separarse sin que el margen de consulta impida toda maniobra; se rechazan nuevas superposiciones y las colisiones siguen activas.
- Los NPC que terminan el circuito despejan la meta y estacionan al lado de la primera recta. Utilizan acelerador, dirección y frenos; no se cambian sus poses. Sus resultados quedan congelados al cruzar la meta. El jugador conserva el control de resultados habitual.

Pruebas físicas finales, con la ciudad y las colisiones reales:

| Escenario | Resultado |
|---|---|
| Jugador quieto en parrilla nueva | Cinco rivales terminan dos vueltas y estacionan; jugador recorre 0.0 m y no pasa controles |
| Jugador quieto en el centro y fila india forzada | Cinco rivales lo rodean al arrancar y al regresar; todos terminan y estacionan; jugador recorre 0.0 m |
| Carrera normal con seis coches | Los seis terminan; los cinco NPC despejan la trayectoria |
| Reinicio / menú / modo libre | Sin duplicados; coche seleccionado conservado |

En la parrilla nueva, los NPC terminaron entre 94.76 y 172.65 s. En la antigua fila forzada, entre 101.16 y 143.13 s. La clasificación del jugador parado permanece en carrera: no se inventa su llegada ni se avanza su progreso. Los informes exigen poses iniciales seguras, cuenta regresiva inmovilizada, dos vueltas ordenadas y los cinco coches estacionados. Ningún coche necesitó reaparecer.

Evidencia: `d3_parked_grid.json`, `d3_parked_legacy.json`, `d3_validation_5.json`, `d3_lifecycle_validation.json` y los logs correspondientes. Son pruebas automáticas de física; falta revisar visualmente la nueva parrilla, los adelantamientos y el estacionamiento en una partida humana. Las maniobras extremas en calles arbitrarias siguen fuera de esta validación. Los ensayos finales se ejecutaron concurrentemente y sus tiempos de CPU no sirven para comparar rendimiento con las mediciones anteriores.

Reproducción: `./tests/run_d3.ps1 -RivalCounts 5 -Traffic`. `--stationary-player` mantiene al jugador detenido; `--single-file-grid` fuerza la fila antigua sólo en el ensayo para impedir que un simple cambio de parrilla oculte el problema.
