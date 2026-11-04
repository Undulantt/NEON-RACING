# FASE C — Especificación de BURST, turbo, derrape y perfiles de vehículos

**Proyecto:** prototipo de carreras arcade en La Paz, B.C.S.  
**Estado:** propuesta de diseño para implementar y calibrar; **no son parámetros ya medidos**.  
**Alcance:** lógica de conducción y mecánicas; la selección visual de tres vehículos puede quedar preparada para la siguiente beta.

## 1. Principio de diseño

- **Aceleración normal:** lleva el automóvil hasta su velocidad máxima base.
- **Turbo:** consume una reserva y aporta aceleración extra, sin elevar por sí solo la velocidad máxima base.
- **Impulso de Derrape / DRIFT BOOST:** da una aceleración breve al completar un derrape controlado; no consume la reserva de turbo.
- **BURST:** al sostener una velocidad cercana a la máxima base durante varios segundos, permite que el límite máximo permitido aumente progresivamente mientras se mantenga aceleración continua.
- **Reinicio inmediato:** soltar el acelerador, frenar, chocar con pérdida relevante de velocidad o bajar del umbral de mantenimiento cancelan BURST sin margen de gracia. **Se restaura el límite base al instante, pero la velocidad física del coche disminuye gradualmente.** Nunca aplicar un `clamp` brusco a la velocidad real.

El juego busca carreras tipo *sprint*, con rectas suficientemente largas, cambios de nivel y algunas curvas urbanas de 90°. No es deseable que mantener el acelerador sin tomar decisiones sea siempre la estrategia óptima.

## 2. Estados de BURST

`NORMAL → PREPARACION → BURST → RECUPERACION → NORMAL`

| Estado | Comportamiento |
|---|---|
| `NORMAL` | Velocidad máxima permitida: `base_max_kmh`. No hay acumulación. |
| `PREPARACION` | Con acelerador presionado, sobre suelo, marcha adelante y velocidad longitudinal ≥ `0.95 × base_max_kmh`, acumular `arming_time_s`. |
| `BURST` | Al terminar el tiempo de preparación, la bonificación del límite crece según el tiempo real de BURST. La potencia del motor debe permitir aprovechar ese nuevo margen. |
| `RECUPERACION` | Se ha perdido BURST. El límite permitido vuelve inmediatamente a la velocidad base; la velocidad real excedente se reduce suavemente con resistencia adicional. No se puede rearmar hasta regresar a ≤ velocidad base y cumplir nuevamente las condiciones. |

### 2.1 Cancelación inmediata

BURST y el progreso de preparación se reinician a cero en el mismo paso de física cuando:

- El acelerador cae por debajo de un umbral configurable, inicialmente `0.85` de entrada analógica normalizada (usar controles coherentes para teclado y mando; permitir umbrales por dispositivo si es necesario).
- Se presiona el freno por encima de `0.10`.
- Se pierde velocidad longitudinal hasta quedar por debajo del `90 %` de la velocidad máxima base durante BURST (cifra inicial para calibrar; sin temporizador de gracia).
- Se cambia a reversa, el vehículo se detiene, reinicia o se produce una colisión cuya pérdida de velocidad activa el criterio anterior.
- Opcionalmente, despegue prolongado del suelo, a definir tras validar rampas y terreno real. Un salto mínimo sobre baches no debería castigar al usuario de forma errática.

**Nota de precisión:** la decisión del usuario es “reinicio inmediato”; los umbrales de lectura analógica y velocidad evitan falsos disparos por ruido físico y no constituyen un periodo de gracia temporal. Recomendar que el agente pruebe el comportamiento en teclado y mando.

### 2.2 Cálculo conceptual

Para el vehículo `v`, mientras BURST está activo:

`bonus(t) = min(burst_growth_per_sec * t, burst_max_bonus)`

`max_allowed_kmh(t) = base_max_kmh * (1 + bonus(t))`

Ejemplo: velocidad base de 185 km/h, crecimiento del 4 % de la base por segundo, tope del +35 %. Tras cinco segundos de BURST, el **límite permitido** será de 222 km/h; a los 8.75 segundos será de 249.75 km/h. No se garantiza que el coche alcance instantáneamente esos límites.

La curva del motor debe seguir entregando aceleración suficiente en la zona BURST. El aumento del límite no debe teletransportar ni sumar directamente velocidad.

### 2.3 Velocidad al cancelar

- `burst_timer = 0` y `burst_bonus = 0` **en el mismo tick**.
- `max_allowed_kmh = base_max_kmh` inmediatamente.
- Si `actual_speed > base_max_kmh`, aplicar una **desaceleración excedente** progresiva y calibrable (`overspeed_recovery_decel_mps2`, referencia inicial 6–9 m/s², además de la resistencia normal), sin cambios instantáneos de velocidad. Preservar colisiones y dirección del vehículo.
- Mantener el estado `RECUPERACION` hasta volver al límite base; evitar reactivar BURST aprovechando el exceso de velocidad residual.
- Si el jugador frena, conservar el efecto normal de frenado, que puede ser más fuerte que la desaceleración de recuperación.

## 3. Interacción con el turbo

- Recurso independiente de BURST; indicador separado.
- Turbo agrega aceleración longitudinal mientras haya carga y sea accionado.
- Antes de BURST, el turbo **no rompe por sí mismo** la velocidad base; ayuda a alcanzarla y sostenerla.
- Durante BURST, el turbo ayuda a alcanzar la velocidad máxima dinámica (sin excederla de manera permanente).
- Usarlo no reduce el tiempo de preparación directamente: acelera la llegada al umbral, por lo que la preparación comienza antes.
- Recurso inicial sugerido: barra de `0–100` para VECTOR y referencias equivalentes para los otros perfiles; recuperación lenta en conducción normal y un componente adicional por derrape válido. Nunca regenerar mientras se consume.
- No conectar automáticamente el Impulso de Derrape al consumo de turbo; son recompensas separadas.

## 4. Impulso de Derrape (nombre sugerido: **DRIFT BOOST**)

Nombre recomendado para HUD: **DRIFT BOOST**. Es simple, fácilmente reconocible y distinto de BURST. Alternativas de diseño: **Impulso de Salida**, **Salida Perfecta**, **Reprise**. Mantener el término *derrape* para la técnica y *Drift Boost* para su recompensa.

### Activación

Se acumula una **calidad de derrape** solo cuando el automóvil está sobre suelo, avanza por encima de una velocidad mínima, tiene un ángulo de deslizamiento controlado y una duración suficiente. Valores iniciales a probar:

- Velocidad mínima: 55 km/h.
- Ángulo de deslizamiento (velocidad horizontal contra dirección frontal): aproximadamente 12°–35°.
- Duración mínima: 0.6 s.
- Excluir giros en falso, derrapes por rebote, trompos y pérdida total de control.
- La recompensa se entrega **una vez** al recuperar tracción / alinear el vehículo y salir del derrape, con pequeño cooldown para impedir explotación de pulsaciones repetidas.

### Recompensa

- Aplicar **aceleración adicional limitada en el tiempo**, no un teletransporte de velocidad.
- DRIFT BOOST funciona hasta el techo de velocidad permitido en ese momento. **No activa ni conserva BURST por sí solo**.
- Puede ayudar a recuperar velocidad después de una curva; más tarde, si se cumplen los requisitos, se inicia la preparación de BURST.
- La duración/potencia dependen del perfil del automóvil y, opcionalmente, de la calidad del derrape. Preferir pocos niveles claros a combos complejos en la primera versión.
- La recuperación de turbo a partir del derrape debe calibrarse independientemente para que no se produzca una fuente infinita de aceleración.

## 5. Tres perfiles iniciales para la beta (nombres provisionales)

No se requieren tres modelos finales en la Fase C. Sí se requiere preparar **tres configuraciones intercambiables** y reutilizables por el futuro selector de autos. La física y los controles deben ser compartidos.

### 5.1 Estadísticas visibles, escala 1–10 (comparativas, no unidades físicas)

| Atributo | VECTOR (equilibrado) | COMET (rectas) | APEX (derrapes) |
|---|---:|---:|---:|
| Velocidad máxima | 7 | 10 | 6 |
| Aceleración | 7 | 5 | 8 |
| Manejo | 7 | 4 | 9 |
| Frenado | 7 | 5 | 8 |
| Derrape | 7 | 4 | 10 |
| Turbo | 7 | 8 | 5 |
| Drift Boost | 6 | 4 | 10 |
| BURST | 7 | 10 | 6 |

**Estas puntuaciones deben derivarse de parámetros físicos explícitos**, nunca calcularse al revés a partir de una única fórmula genérica. La puntuación de BURST agrupa activación, crecimiento y bonificación máxima, por lo que debe acompañarse de datos numéricos en vistas de detalle.

### 5.2 Parámetros iniciales para jugar y calibrar

| Parámetro | VECTOR | COMET | APEX |
|---|---:|---:|---:|
| Velocidad máxima base | 185 km/h | 205 km/h | 175 km/h |
| Objetivo 0–100 km/h | 5.3 s | 6.1 s | 4.9 s |
| Desaceleración de frenado objetivo (orientativa) | 10 m/s² | 8.5 m/s² | 11.5 m/s² |
| Tiempo preparación BURST | 3.0 s | 3.5 s | 2.5 s |
| Crecimiento BURST | +4.0 % de base/s | +4.5 % de base/s | +5.5 % de base/s |
| Bonificación máxima BURST | +35 % | +45 % | +30 % |
| Límite máximo BURST (teórico) | 249.75 km/h | 297.25 km/h | 227.5 km/h |
| Tiempo para alcanzar el tope de bonificación | 8.75 s | 10 s | ≈5.45 s |
| Duración nominal de turbo continuo | 5 s | 6 s | 4 s |
| Aceleración extra nominal de turbo | +2.5 m/s² | +2.8 m/s² | +2.1 m/s² |
| Impulso de Derrape extra | +2.8 m/s² durante 0.9 s | +1.9 m/s² durante 0.7 s | +4.0 m/s² durante 1.25 s |

Los valores de aceleración, frenado y potencia de habilidades son **puntos de partida de diseño**: traducirlos a fuerzas, curvas o parámetros equivalentes según el controlador existente. No asumir que `VehicleBody3D`, `RigidBody3D` y un controlador cinemático se parametrizan igual.

**Personalidad de conducción:**

- **VECTOR:** fácil de aprender; competitivo en rutas mixtas, turbo equilibrado, BURST predecible.
- **COMET:** líder en rectas largas y velocidad BURST final; pierde tiempo en curvas de 90° por menor manejo, frenado y aceleración inicial.
- **APEX:** entra y sale de curvas con facilidad, acelera antes, obtiene el Drift Boost más fuerte y entra pronto en BURST; techo máximo menor, por lo que puede perder en rectas excepcionalmente largas.

### 5.3 Importante: altura y longitud real de las rutas

En calles urbanas, 205–297 km/h pueden consumir distancias grandes: a 200 km/h se recorren ≈56 metros cada segundo. No dar por supuesto que existen rectas continuas suficientes en los circuitos reales.

El agente deberá probar la duración y longitud de las rectas de La Paz disponibles en el juego para validar si BURST alcanza niveles interesantes antes de tener que frenar. Si un trazado no permite disfrutar BURST, ajustar preparación y crecimiento o diseñar una ruta *sprint* distinta, **sin deformar el mapa geográfico por comodidad**.

## 6. Implementación en Godot (adaptarse al proyecto real)

1. **Auditar primero** el controlador actual, acciones de entrada, física, terreno inclinado, suspensiones y UI. No reemplazarlo sin justificación.
2. Crear datos de configuración por vehículo (idealmente recursos propios `.tres` o formato existente) sin duplicar el controlador. Separar valores de física base y habilidades. No almacenar valores de interfaz como fuente de verdad.
3. Extraer una capa de habilidades capaz de calcular `current_speed_cap`, estado/timer BURST, carga turbo y evento de Drift Boost.
4. Calcular tiempos y fuerzas en `_physics_process(delta)` y usar segundos reales, no contar frames. Mantener constante el paso de física para pruebas comparables.
5. Medir **velocidad longitudinal de avance sobre el plano de conducción**, no solo magnitud total de `linear_velocity`, para que deslizarse lateralmente o caer no simule velocidad elegible para BURST. Respetar la orientación local real del modelo del coche.
6. Usar aceleración/fuerzas físicamente coherentes, resistencia progresiva, límites suaves y control estable a altas velocidades; no asignar instantáneamente una nueva velocidad.
7. Instrumentar señales/eventos (`burst_started`, `burst_ended(reason)`, `drift_boost_triggered`, `turbo_changed`) u otra interfaz equivalente. La UI/audio de Fase E pueden suscribirse sin alterar la física.
8. Mantener compatibilidad con rutas y pendientes del mapa real, streaming, colisiones y reaparición del vehículo.
9. Si el coche actual usa `VehicleBody3D`, recordar que Godot documenta limitaciones conocidas para física automotriz avanzada; **no cambiar de controlador por defecto**: medir el problema y proponer alternativas solo si hay evidencia.

Referencias técnicas oficiales: https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html ; https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html

### Pseudocódigo de transición (conceptual)

```text
on_physics_tick(delta):
  read_inputs()
  forward_kmh = measured_forward_speed_kmh()
  if throttle_released OR brake_pressed OR reverse OR severe_loss_of_speed:
      reset_burst_immediately()
  else if state == BURST:
      burst_seconds += delta
      allowed_cap = base_cap * (1 + min(growth * burst_seconds, max_bonus))
  else if state == RECOVERY:
      allowed_cap = base_cap
      apply_smooth_overspeed_deceleration(delta)
      if forward_kmh <= base_cap:
          state = NORMAL
  else if can_arm_burst(forward_kmh, throttle, grounded):
      state = PREPARATION
      arming_seconds += delta
      if arming_seconds >= arming_time:
          state = BURST
          burst_seconds = 0
  else:
      state = NORMAL
      arming_seconds = 0

  update_turbo(delta)
  update_drift_and_reward(delta)
  drive_with_physical_forces(allowed_cap, turbo, drift_boost, delta)
```

Es pseudocódigo: el orden real puede cambiar para evitar efectos de un tick de latencia. Asegurar que cancelar BURST tiene prioridad sobre aumentar su bonificación.

## 7. HUD y feedback mínimo de Fase C

- Velocímetro digital en km/h con velocidad real.
- Indicador de **velocidad máxima base** y límite dinámico BURST (como cifras o barra contextual).
- Barra de preparación BURST; cambio claro de estado al activarse.
- Indicador de BURST activo y bonificación porcentual actual.
- Barra de turbo con consumo y recuperación.
- Indicador breve de DRIFT BOOST obtenido; evitar efectos visuales invasivos.
- Versión provisional sin estética final; luces/estelas/sonidos definitivos para Fase E.

## 8. Pruebas de balance y criterios de aceptación

Pruebas automáticas o instrumentadas:

- BURST se arma solo al alcanzar condiciones y mantenerlas el tiempo configurado.
- Soltar acelerador o frenar cancela BURST en el **mismo tick** y reinicia sus temporizadores.
- Al cancelar, no existe teleport de posición ni salto instantáneo de velocidad física; el límite permitido sí vuelve a su valor base.
- Mantener dirección/velocidad lateral o caer no llena la preparación indebidamente.
- Turbo no permite exceder el límite normal si BURST está inactivo.
- Drift Boost solo se otorga en salida de derrape válido, una vez por evento, y no produce ganancias infinitas al alternar inputs.
- No hay valores NaN o velocidades fuera de control tras choques, pendientes, respawns o cambios de sector.
- El HUD muestra estados y valores coherentes con el controlador.
- Cada coche puede completar al menos una ruta larga y una de curvas; comparar tiempos y secciones con la misma IA o piloto de prueba.
- Probar en los fotogramas físicos configurados del proyecto y evaluar en 30, 60 y 120 FPS de render sin alterar indebidamente el resultado.

**Balance:** no tratar los números propuestos como definitivos. Registrar tiempo medio en recta de 500 m y 1 km, un circuito de curvas de 90°, y una ruta mixta; ajustar para que los tres arquetipos sean competitivos en **algún** recorrido, sin exigir igualdad en todos.

## 9. Orden de desarrollo y conexión con la beta

**Fase C (ahora):** implementar sistema BURST, turbo, Drift Boost, parámetros por vehículo, HUD básico y pruebas de manejo. Usar modelos temporales si hace falta.

**Próxima beta:** menú de selección de uno de tres vehículos al iniciar, nombres y modelos definitivos si están disponibles, presentación comparativa de ocho atributos y persistencia de la elección de automóvil. Para evitar rehacer la física, este menú debe consumir las configuraciones ya preparadas en C.

**Fase E:** efectos definitivos de velocidad, sonido BURST, música EUROBEAT original/licenciada, cámaras y estética retrofuturista.

## 10. Instrucción al agente

Lee primero el proyecto real y propone una arquitectura compatible con su controlador existente. Los parámetros anteriores son hipótesis de diseño, no verdades técnicas. Si encuentras una integración más eficiente, más estable o más divertida, explícala con ventajas, desventajas y pruebas; tienes libertad para sugerirla. **No hagas sustituciones profundas sin comunicar sus riesgos y su justificación.** Implementa primero BURST en el automóvil actual, después Drift Boost y turbo integrado; finalmente crea los tres perfiles y valida el balance.
