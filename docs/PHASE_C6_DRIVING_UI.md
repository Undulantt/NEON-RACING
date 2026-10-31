# Fase C.6 — Conducción y HUD

## Ajustes

- Vehículo al 80% de su tamaño anterior: modelo, caja de colisión (1,44 × 0,96 × 3,28 m), puntos de soporte, sondeos de recuperación, suspensión visual, ruedas y emisores de humo.
- Terreno: límite normal de 28,8 m/s (103,68 km/h), frente a 32 m/s (115,2 km/h) en carretera. La reducción por exceso de velocidad fuera del asfalto se aplica a 3 m/s², sin frenada adicional del motor hacia el límite. Turbo a 44 m/s, carga de derrape y recompensa disponibles también en terreno con apoyo.
- Derrape: velocidad mínima de 7 m/s, frenado de mano de 9 m/s², banda válida de 8–60°, carga en 0,9 s a calidad completa y mínimo de 18% durante 0,3 s. Salida válida por debajo de 12° durante 0,1 s, con margen de 1,8 s. Sigue exigiendo giro y deslizamiento real; choques, trompos lentos, recuperación e inspección cancelan la carga.
- Impulso: aporte nominal máximo de 3 a **3,75 m/s** y duración de 0,9 a **1,125 s**, ambos +25%. El efecto depende de la carga. Shift sustituye el impulso sin acumularlos.
- HUD: minimapa de calles reales arriba a la izquierda, norte fijo, flecha con orientación del vehículo y nombre de calle. Velocímetro de aguja y lectura digital abajo a la derecha, reserva de turbo cian y carga/impulso dorado. Ayuda breve y créditos al pie; controles secundarios en pausa. Los instrumentos siguen los bordes del viewport al cambiar su tamaño.

## Validación

Godot 4.7.2, física a 60 Hz. Pasaron:

- `tests/godot_phase_c6.gd`: escala física/visual, incremento exacto del 25%, integración del minimapa, transición carretera/terreno, límite suave, turbo y derrape con recompensa en terreno.
- `tests/godot_drift_rewards.gd`: carga proporcional, teclado, pausa, humo, recompensa única, aumento real de velocidad, terreno, choques y recuperación. Carga de 36,2% a 0,75 s y 100% a 1,5 s; teclado digital 53,5%. En la misma salida, diferencia de +3,0 m/s tras medio segundo respecto a la salida sin premio.
- `tests/godot_phase_c.gd`: aceleración, límites, reserva, cámara, derrape e integración de HUD/pausa. La expectativa antigua que impedía turbo en terreno se actualizó a la nueva conducta.
- `tests/godot_slope_physics.gd`: pendientes, gravedad, despegue y aterrizaje.
- `tests/godot_road_edges.gd`: seis casos reales de salida y regreso al asfalto.

La transición al terreno midió 31,99997 → 30,50033 m/s en 0,5 s. Captura renderizada y revisada en `docs/evidence/phase_c6_hud.png`. Informes de C.6 en `docs/c6_validation.json`, `docs/c6_drift.log`, `docs/c6_driving.log`, `docs/c6_slopes.log` y `docs/c6_road_edges.log`.

La captura OpenGL se generó correctamente; el motor emitió un mensaje de inicialización de caché de shaders y seis referencias ObjectDB al cerrar la escena de captura. No hubo errores de script ni fallos de las aserciones. La valoración del tacto final queda para la prueba de juego.
