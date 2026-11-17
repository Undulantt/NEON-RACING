# Auditoría de aceptación de los rivales

**Actualización posterior:** [nivel Experto](RIVAL_EXPERT_MODE.md), con mayor ritmo medido, corrección del contador y Drift Boost demostrado en curvas amplias. La auditoría siguiente conserva los resultados históricos previos; la aceptación general continúa pendiente.

16 de noviembre de 2026. **Veredicto: la IA todavía no debe darse por terminada.** Se completaron las mediciones; aprobar la ejecución de la auditoría no equivale a aprobar la IA. Resultado estructurado: [rival_acceptance_verdict.json](../../.local/artifacts/rival_acceptance_verdict.json).

Esta revisión añade pruebas y documentación. Conserva el controlador de competición y sus parámetros. Los informes incluyen hashes SHA-256 del controlador, física y alineación para identificar qué versión fue medida.

## Los cinco criterios

| Criterio | Veredicto | Evidencia |
|---|---|---|
| Acelerador, freno y dirección físicos | Comprobado | Los cinco escriben mandos, frenan y giran; actualizar el piloto 60 veces con la física desactivada no mueve ni rota el coche ni cambia su velocidad. En carrera, desplazamiento y velocidad física coinciden dentro de 0.001 m, sin recuperaciones por teletransporte. |
| Salir de la línea y adelantar con fiabilidad | No aprobado | Se separan hasta 3.92 m de la línea y terminan las carreras, pero el contador interno declara seis adelantamientos que la medición independiente no corrobora. Hay contactos breves entre participantes. No se demuestra un adelantamiento competitivo completo y limpio con el criterio definido abajo. |
| Derrape, TURBO y BURST por sus reglas | Parcial; no aprobado en conjunto | TURBO funciona en carrera y BURST funciona con los cinco en una recta larga. No se obtiene derrape válido ni Drift Boost con el piloto rival en Centro LP ni en la prueba circular amplia. |
| Competir entre los cinco NPC | Comprobado | Todos terminan dos vueltas con el jugador fuera de percepción, colisión y simulación. Seleccionan otros NPC como objetivos, ajustan su circulación e intentan adelantarlos. Cambiar la parrilla cambia sus resultados. Esto no aprueba la calidad de esos adelantamientos. |
| Personalidades observables sin ventajas físicas | Comprobado en prueba controlada | VECTOR, salida idéntica, dos vueltas y pista libre: 78.453 s conservador, 70.601 s equilibrado, 65.773 s agresivo. Mismo archivo de física, configuración y multiplicador ×1. |

## Pruebas físicas y ausencia de movimiento sobre raíles

`RivalDriver.gd` decide objetivos, dirección, gas, freno, freno de mano y TURBO mediante `car.set_controls`. La asignación del transform en `RaceCompetition.prepare` coloca la parrilla antes de conducir. Durante la competición, el piloto no escribe posición, transform ni velocidad. `ArcadeCar._physics_process` integra aceleración, frenado, agarre y dirección, llama a `DrivingAbilities.tick` y termina el movimiento con `move_and_slide`.

La prueba congela el proceso físico de cada uno de los cinco coches, mantiene el vehículo habilitado y ejecuta 60 actualizaciones del controlador con una sesión de navegación en marcha. Los cinco piden acelerador y dirección, pero su transform y velocidad permanecen exactamente iguales. Después se restaura el controlador de competición antes de comenzar la cuenta regresiva.

Durante las carreras se observa el cambio de posición frente a `get_real_velocity()/60`, los mandos efectivos, los contactos y la configuración. El máximo residuo observado es aproximadamente 0.000000062 m. Los cinco usan acelerador, freno y dirección. Sus configuraciones coinciden con el perfil disponible al jugador; el modo de velocidad de prueba permanece desactivado y no se registran teletransportes. El contador de recuperación física del coche se distingue de las maniobras de marcha atrás del piloto.

Informes: [rival_acceptance_traffic.json](../../.local/artifacts/rival_acceptance_traffic.json), [rival_acceptance_personalities.json](../../.local/artifacts/rival_acceptance_personalities.json).

## Adelantamientos: discrepancia encontrada

Se probaron tres carreras completas de dos vueltas sobre el mundo real del proyecto:

| Escenario | NPC que terminan | Maniobras solicitadas | Completadas según el piloto | Corroboradas por medición | Encuentros con contacto | Contacto acumulado por pares |
|---|---:|---:|---:|---:|---:|---:|
| Parrilla normal y jugador con piloto de prueba | 5/5 | 5 | 2 | 0 | 9 | 1.10 s |
| Cinco NPC, sin jugador en simulación/percepción | 5/5 | 4 | 1 | 0 | 5 | 0.67 s |
| Cinco NPC con sus posiciones de salida invertidas | 5/5 | 5 | 3 | 0 | 2 | 0.28 s |

La separación lateral durante las maniobras llega a aproximadamente 3.92 m, de modo que los coches sí abandonan la línea. En estas carreras no se registran contactos con muros ni frames fuera de asfalto. Los contactos entre coches son breves; estas medidas no justifican describirlos como choques graves constantes, pero tampoco certifican adelantamientos seguros.

La medición exige que el atacante empiece detrás y después mantenga más de 7 m de ventaja durante 0.5 s, con ambos vehículos todavía compitiendo. Usa el progreso continuo propio de cada piloto y excluye pasar coches ya retirados. Una posición a la par o un roce no bastan. Se registran contactos del par y separación lateral durante la maniobra. Los siete controles del oráculo de medición incluyen un adelantamiento positivo, ventaja insuficiente, pérdida de ventaja y falsos contadores: [rival_acceptance_measurement_validation.json](../../.local/artifacts/rival_acceptance_measurement_validation.json).

La discrepancia tiene una causa concreta en `RivalDriver.update`: el vehículo adelantado se proyecta sobre la ruta usando la ventana local del atacante. El objetivo puede permanecer comprometido durante decenas de segundos y alejarse de esa ventana; entonces su proyección aparenta estar detrás aunque su progreso propio sigue delante. Por ejemplo, en la salida normal Dani e Iris reciben un adelantamiento completado sobre Luque sin conseguir una ventaja positiva real sobre él. **El contador `completed_passes` de informes anteriores no prueba por sí solo que se haya adelantado a otro rival.**

El siguiente ajuste de conducción debe corregir esa referencia de progreso, abandonar o replantear objetivos demasiado lejanos y demostrar la maniobra hasta completar un sobrepaso real. Esta auditoría identifica el defecto; no lo oculta cambiando el criterio o otorgando velocidad extra.

Los encuentros agrupan interrupciones de contacto de hasta 0.5 s para no contar cada rebote como un choque nuevo. Los informes conservan también las secuencias contiguas y duración por pareja. No se midieron fuerza del impacto, daños ni comodidad subjetiva.

## Habilidades: capacidad frente a uso efectivo

- **Centro LP:** los cinco usan TURBO; cero peticiones de derrape, cero carga válida, cero recompensas de Drift Boost y cero BURST. Ya estaba registrado en [la auditoría de habilidades](CHECKPOINT_SPHERES_AND_AI_ABILITIES.md).
- **Curva continua de radio 35 m:** cinco pruebas con dos vueltas cada una, asfalto amplio, sin tráfico ni paredes, y trayectoria circular muestreada como entrada de navegación. El mismo `RivalDriver` mueve el coche con sus mandos: los cinco terminan, pero ninguno pide derrape ni obtiene carga, recompensa o boost. El deslizamiento máximo es de aproximadamente 1.98–2.75°, inferior al mínimo válido de 12°. No hay mandos de derrape programados por el test ni estado de habilidad inyectado. Informe: [rival_acceptance_drift_probe.json](../../.local/artifacts/rival_acceptance_drift_probe.json).
- **Recta plana de 2,500 m:** cada combinación actual de auto y personalidad obtiene TURBO y BURST con física real. Se mantiene BURST aproximadamente 25–35 s y se supera el límite base con las bonificaciones originales de cada coche. No se inyecta carga ni velocidad. Informe: [d3_abilities_validation.json](../../.local/artifacts/d3_abilities_validation.json), nueva ejecución en `rival_acceptance_burst.log`.
- **Control positivo del sistema de derrape:** el APEX conducido con mandos programados sí gana Drift Boost; esa prueba confirma el sistema físico y el checkpoint esférico, pero no la capacidad del piloto rival. No se usa para aprobar este punto.

Por tanto, la capacidad de TURBO/BURST queda demostrada en condiciones adecuadas. El derrape de los rivales permanece pendiente. La ausencia de BURST en Centro LP es coherente con no alcanzar sus umbrales de velocidad y no debe corregirse activándolo por fuerza o cambiando sus reglas.

## Personalidades con el mismo auto

Cada prueba comienza desde el mismo transform exacto con VECTOR, misma carga inicial de TURBO, misma trayectoria, sin tráfico ni jugador. Se conservan aceleración, límite, agarre, frenos y habilidades del perfil de jugador. La configuración física tiene el mismo hash (`2053028900`) en las tres ejecuciones y se vuelve a comparar durante la carrera. Cambian exclusivamente los parámetros de decisión del piloto.

| Personalidad | Dos vueltas | Tiempo con freno aplicado | Tiempo con TURBO | Pico de velocidad |
|---|---:|---:|---:|---:|
| Conservador | 78.453 s | 27.03 s | 12.90 s | 103.9 km/h |
| Equilibrado | 70.601 s | 25.70 s | 13.23 s | 115.0 km/h |
| Agresivo | 65.773 s | 23.40 s | 13.38 s | 125.3 km/h |

No hay contactos ni salidas de asfalto en estas tres pruebas. Los parámetros `anticipation`, `throttle`, `gap`, reserva de TURBO y aceleración lateral **deseada** cambian decisiones. La aceleración lateral deseada limita la velocidad planificada: no añade agarre a los neumáticos. Los diferentes tiempos de la alineación habitual no permiten atribuir todo a personalidad porque COMET, VECTOR y APEX también difieren entre sí; por eso se realizó este control con el mismo auto.

Sin jugador, la parrilla normal produce tiempos de 69.46–89.39 s; con posiciones invertidas, 66.60–86.11 s y cambia el ganador. Esto demuestra sensibilidad a posición/tráfico, no garantiza carreras divertidas ni demuestra variación espontánea: el controlador sigue siendo determinista.

## Diversión y aceptación humana

La implementación utiliza geometría y reglas de conducción, no un piloto entrenado con aprendizaje por refuerzo. Sophy y el sistema multilínea de Forza son referencias de diseño; las puntuaciones de aplicabilidad de la imagen no son evaluaciones de esta implementación.

La aceptación debe valorar si los rivales resultan legibles, dejan espacio al compartir una curva y permiten responder a una maniobra. Rapidez, precisión o terminar siempre no certifican diversión. La sensación de justicia, la presión del rival y la variedad necesitan carreras humanas completas de dos vueltas. No se ha añadido azar al volante ni errores artificiales para simular diversión, y esta auditoría no declara aprobada esa experiencia.

## Reproducir

Ejecutar `tests/run_rival_acceptance.ps1`. Ejecuta tres carreras con tráfico, tres comparaciones de personalidad, cinco casos de curva continua y cinco de TURBO/BURST, además de calibrar la medición independiente. Usa un perfil de datos aislado y ajustes temporales por proceso.

`-SummarizeOnly` regenera el veredicto desde los informes comprobando sus hashes frente al código y configuración actuales. Un código de salida correcto significa que las mediciones se completaron; consultar `acceptance_approved` y `human_fun_validated`, actualmente ambos `false`, para el veredicto de aceptación.
