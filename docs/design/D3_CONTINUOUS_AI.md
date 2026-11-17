# D.3 — Trayectoria continua y tráfico

**Veredicto vigente:** [auditoría de aceptación](RIVAL_AI_ACCEPTANCE_AUDIT.md). La IA continúa pendiente; los contadores de adelantamientos de esta entrega pueden dar falsos positivos y no sirven por sí solos como evidencia de un sobrepaso.

**Detección vigente:** [checkpoints esféricos y auditoría con la nueva alineación](CHECKPOINT_SPHERES_AND_AI_ABILITIES.md). Las referencias siguientes a puertas y mediciones previas describen la entrega original de la IA continua.

Revisión del 16 de noviembre de 2026. Sustituye la navegación de puerta en puerta de la primera D.3. Se conservan mapa, reglas de vueltas, coches y física.

La alineación vigente se encuentra en `config/rivals.json`: Luque (COMET, agresiva), Guille (APEX, conservador), Dani (COMET, agresiva), Xavi (VECTOR, equilibrado) e Iris (APEX, agresiva). Los resultados y capturas de este documento corresponden a la alineación anterior; no miden la nueva distribución de coches y personalidades.

## Referencias y decisiones

La fuente aportada por el usuario, [Turn 10: cambios de Drivatar, 30 de abril de 2025](https://forza.net/news/forza-motorsport-drivatar-changes), describe líneas alternativas y transiciones suaves para circular y adelantar con tráfico. Inspiró la separación entre trayectoria base, corredores laterales y comprobación de espacio al volver a una línea. Aquí son algoritmos geométricos locales; no se reproduce el entrenamiento ni la implementación privada de Forza.

[Turn 10: Drivatars y neumáticos, 17 de julio de 2023](https://forza.net/news/forza-motorsport-drivatars-tire-physics) distingue la línea y el controlador. Se mantiene esa separación: un objeto geométrico compartido y mandos independientes por coche. [Sony AI: entrenamiento de Gran Turismo Sophy](https://ai.sony/blog/training-the-worlds-fastest-gran-turismo-racer?hs_amp=true) utiliza información anticipada de la pista; aquí se adapta la anticipación a velocidad y capacidad de frenado. No se añade aprendizaje por refuerzo ni infraestructura de entrenamiento.

## Implementación

- `RaceTrajectory.gd` convierte la ruta vial en una trayectoria cerrada por distancia recorrida. Elimina subdivisiones casi rectas, redondea intersecciones y muestrea curvas y rectas. En Centro LP genera 351 muestras, 10 giros redondeados y 622.55 m geométricos. La distancia oficial de calle sigue siendo 626.097 m y las puertas oficiales siguen siendo obligatorias.
- Los arcos de giro se desplazan para cruzar las puertas situadas en las intersecciones. La huella del vehículo, el asfalto y los obstáculos estáticos comprueban la curva; un giro que no cabe conserva el vértice. Los corredores laterales se estrechan ante curvas, bordes y edificios, con transición anticipada. La línea elegida aporta su propia curvatura al cálculo de velocidad.
- `RivalDriver.gd` proyecta el coche sobre la trayectoria y calcula dirección mediante Pure Pursuit, compensando la dirección y reducción a velocidad del coche real. Mira más lejos a mayor velocidad y reduce la anticipación en giros. Una envolvente de frenado considera curvas futuras, pendiente, frenos, límite de giro y personalidad.
- Tráfico: proyección longitudinal/lateral común, separación según velocidad, elección de lado despejado, compromiso de adelantamiento y comprobación lateral/trasera antes de incorporarse. Cada coche conserva una preferencia lateral pequeña. Incluso un conservador puede rodear un vehículo detenido. Se permite avanzar despacio por el corredor elegido para no quedar inmóvil detrás del obstáculo.
- La vigilancia de atascos mide avance por la ruta; intenta separar contactos mediante marcha atrás/avance, sin teletransportar. Un control obligatorio perdido activa una recuperación excepcional sobre la ruta; no determina el objetivo normal del volante.
- Cada rival mantiene reloj, vueltas y controles propios; puede competir con el jugador parado. Tras terminar, un controlador privado continúa despacio hacia el lateral más próximo y forma una cola detrás de quienes ya se retiraron. Si no encuentra hueco seguro, continúa por la ruta. No cambia el tiempo, las vueltas ni la clasificación oficial.
- Los aros quedan parcialmente enterrados para verse como arcos; la parrilla ocupa dos columnas cuando hay espacio físico.

Se utilizan los mismos coches, límites, aceleración, frenos, TURBO y colisiones. Los parámetros de personalidad cambian decisiones y velocidad deseada; no añaden agarre ni potencia. No hay recuperación por teletransporte ni compensación artificial respecto al jugador.

## Validación reproducible

`tests/run_d3.ps1 -Traffic -Regression` ejecuta reglas, geometría, habilidades, cantidades de rivales, tráfico estacionario y regresión del editor. Cada proceso usa ajustes de prueba independientes.

`godot_d3_trajectory.gd` compara el mismo circuito con 70 y 20 controles: muestras, curvatura y corredores idénticos; recorre dos vueltas por centro y extremos laterales y valida todas las puertas en orden. También comprueba continuidad de cierre y proyección entre vueltas. Pasa 12 comprobaciones. Reglas: 12 comprobaciones. Editor/vueltas: 87 comprobaciones. TURBO y BURST pasan con física real en una recta sintética de 2,500 m; esa prueba no demuestra su uso durante el circuito urbano.

En la carrera normal automatizada de dos vueltas, los cinco NPC terminan en 80.80–88.95 s, frente a 92.46–140.96 s de la versión previa guardada en `d3_route_before.json`. No requieren marcha de recuperación ni corregir controles perdidos. El jugador de la prueba también lo conduce el nuevo controlador: su tiempo no representa una carrera humana. El informe incluye avances, adelantamientos, variación de volante y coste de actualización. Los valores de rendimiento obtenidos con pruebas simultáneas/headless no son una medición de FPS de juego real.

Las capturas `evidence/d3_route_*.png` muestran una carrera renderizada observando a Rayo. No constituyen aceptación por un jugador humano. La geometría continua también se mantiene al cambiar la densidad de controles.

El caso adicional con jugador inmóvil en el centro de la antigua parrilla en fila india termina con los cinco NPC en 85.16–94.56 s: todos validan dos vueltas y se estacionan, sin recuperación ni corrección de puerta perdida. El jugador conserva posición exacta y cero controles/vueltas. Informes: `d3_parked_legacy.json` y `d3_route_parked.log`.

Con la parrilla actual y el jugador inmóvil, terminan en 80.68–108.17 s. Faro necesita dos maniobras de recuperación; los otros cuatro no las necesitan. Todos completan las puertas, se retiran y el jugador permanece exactamente en su sitio. No se presenta esta prueba de tráfico como ausencia absoluta de incidentes. Informe: `d3_parked_grid.json`.

## Límites

La preferencia y las alternativas laterales son conservadoras en intersecciones: el objetivo es poder circular fuera del centro sin salirse del asfalto. No se promete conducción aprendida, defensa de posición sofisticada ni adelantamiento en cualquier hueco. Es necesario probar recorridos nuevos del editor, especialmente curvas muy cerradas, calles estrechas y cruces superpuestos.

La retirada usa el primer tramo del circuito como zona lateral y puede exigir continuar una vuelta si está ocupado. La zona y la parrilla necesitan validación al incorporar circuitos nuevos; no se promete estacionamiento general para cualquier recorrido del editor.

Siguen pendientes una carrera humana completa, valorar la dificultad subjetiva y validar Drift Boost competitivo en este circuito. La prueba urbana usa TURBO; no obtiene recompensas de drift ni entra en BURST. No se ha avanzado a D.4.
