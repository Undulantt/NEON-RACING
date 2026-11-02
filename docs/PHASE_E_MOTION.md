# Fase E — refinamiento de movimiento y contraste

## Corrección de picos en las uniones del neón

La captura del usuario reveló un defecto que la prueba de una sola pendiente no cubría: los rectángulos independientes podían sobresalir de su triángulo y cruzar una superficie con otra inclinación.

`RoadNeon.gd` ahora recorta una franja de anchura constante contra los triángulos reales de la carretera. Cada vértice obtiene su altura por interpolación de la superficie que lo sostiene, con separación vertical de 1,8 cm. Las uniones redondeadas cubren los extremos sin generar puntas. Una cuadrícula espacial limita los recortes a la zona próxima al borde; el trabajo se realiza al construir la decoración, no en cada cuadro. No cambia la geometría vial ni las colisiones.

Verificación acotada, atendiendo a la petición de reducir pruebas: prueba de pendientes consecutivas, continuidad y exclusión de cortes de sector (`phase_e_road_neon_validation.json`, PASS), más una ejecución renderizada del piloto mirando en sentido contrario al inicio. Captura revisada: [borde corregido](evidence/phase_e_neon_relief_fixed.png). No se repitió el benchmark general; las cifras de rendimiento siguientes corresponden a la revisión anterior.

## Corrección posterior — relieve, velocidad y rótulos

- Los bordes cian ahora se generan desde las aristas externas de la malla vial elevada (`RoadNeon.gd`), con un pequeño desplazamiento de 1,8 cm para evitar parpadeo por superposición. Se eliminan aristas compartidas y cortes artificiales de sector. Se conserva la malla física. La aplicación sigue limitada al sector piloto; no se ha extendido el estilo al mapa completo.
- Las líneas periféricas pasan de 1,25 a 1,8 px, aumentan moderadamente su longitud y su opacidad máxima de 0,48 a 0,68. Conservan las zonas de exclusión de carretera y HUD.
- Turbo añade desenfoque lateral gradual con mipmaps en el posprocesado existente. El centro permanece enfocado y los instrumentos se dibujan después. F4 también regula este efecto; al soltar turbo se desvanece.
- `CAFÉ / LA PAZ`, `BAHÍA · 24H` y `NOCHE AZUL` eran textos decorativos inventados, sin procedencia geográfica. Se retiran los tres. Los acentos geométricos de neón permanecen sin nombres; futuros rótulos comerciales deberán tener fuente y correspondencia verificable con el edificio.
- `phase_e_road_neon.gd`: PASS en superficie inclinada, cuatro bordes exteriores y ninguna diagonal interna; desviación respecto al plano y separación prevista menor de 0,000001 m. Verificación de exclusión del corte entre sectores.
- `phase_e_motion.gd`: PASS incluyendo activación/desaparición del desenfoque, ausencia de rótulos inventados y presencia de bordes elevados. `phase_e_retro.gd`: PASS, misma trayectoria, F8 y recarga. Capturas reales de conducción y sector actualizadas y revisadas.

Rendimiento: primera medición con lectura adicional de pantalla, +18,33 % sobre la escena diurna (fuera del margen de 15 %); se conserva en `phase_e_blur_initial_benchmark.json`. Tras reutilizar el mip del resplandor existente, la medición final con turbo dio 2,937 ms frente a 2,667 ms (+10,14 %, PASS), p95 4,110 ms y pico aislado 40,973 ms. No garantiza ausencia de tirones ni rendimiento equivalente en toda la ciudad.

Las cifras de la sección original siguiente son históricas; el informe de turbo se actualiza con esta revisión.

## Alcance y dirección

Prioridad del usuario: refinar estela de turbo y líneas dinámicas; posponer el modelo del coche para Blender. Se conservan controlador, cámara, geografía, colisiones, streaming y carrocería de la revisión anterior. Música fuera de este trabajo.

La inspección encontró escapes de bloques y una ráfaga radial de 64 líneas en el HUD existente. Se mantiene ese comportamiento en la escena principal; el piloto activa un perfil específico con menos trazos laterales. No se añade otro HUD ni otro sistema de turbo.

Plan ejecutado: (1) reutilizar señales y estados existentes; (2) sustituir la representación del escape y añadir estelas acotadas; (3) despejar carretera e instrumentos; (4) equilibrar iluminación, asfalto y pequeños detalles comerciales; (5) verificar en Godot y registrar evidencia.

## Implementado

- Dos estelas en coordenadas del mundo siguen el recorrido del vehículo. Núcleo cian, halo azul y desvanecimiento progresivo; matiz lavanda para impulso de derrape. Vida de 0,20 s y máximo de 24 muestras, con una sola superficie de malla, sin luces ni colisiones nuevas.
- Escape ahusado y transparente, encendido suave y pulsación leve de 3 Hz. Reutiliza los dos emisores existentes. `TurboTrail.gd` está separado de la carrocería; al integrar Blender habrá que ajustar sus puntos de salida al modelo definitivo.
- Líneas periféricas finas, principalmente cian, con acentos magenta. Se excluyen centro, minimapa, indicadores y pie de pantalla. Se conserva la intensidad derivada del estado de conducción.
- **F4:** completos → sutiles → desactivados. Ajuste de sesión, no persistente. Pausa, recuperación, inspección y saltos de posición limpian o suspenden el efecto según corresponda.
- Menor dominante magenta y resplandor global, ventanas cálidas en edificios no comerciales y color comercial más contenido.
- Variación suave de rugosidad y brillo del asfalto. Los reflejos siguen siendo aproximaciones estilizadas; no se ha añadido SSR.
- Cinco fachadas comerciales reciben puerta, paños, montantes y marquesina superficial en una malla compartida. Límite de diez módulos por sector, sin alterar volúmenes ni colisiones.

## Verificación en Godot 4.7.2

- `phase_e_motion_validation.json`: PASS. Emisión, presupuesto de muestras (13 observadas), pausa, desaparición al soltar turbo, teletransporte sin puente, recuperación y ciclo F4.
- `phase_e_retro_validation.json`: PASS. Posición y velocidad idénticas entre escenas diurna/nocturna, cero cuadros fuera del asfalto, F8, descarga/recarga del sector y música detenida.
- Hashes de `phase_e_baseline_hashes.json`: sin diferencias. `RetroCar.gd` permanece sin modificaciones.
- Capturas renderizadas revisadas: [turbo a 149 km/h](evidence/phase_e_turbo_driver.png), [vista lateral](evidence/phase_e_turbo_trail.png), [sector](evidence/phase_e_retro_sector.png). Ejecuciones sin errores de script o shader.

Rendimiento: RTX 4060 Ti, Compatibility, 1280×720, VSync desactivado, simulación fija 60 Hz, 540 cuadros de calentamiento y 1.080 medidos por escena. Sin turbo: 2,653 ms nocturno frente a 2,495 ms diurno (+6,30 %). Con turbo activado durante 420 cuadros por escena: 2,763 ms nocturno frente a 2,855 ms diurno; p95 nocturno 3,935 ms. Hubo un pico aislado nocturno de 39,562 ms. La medición no demuestra una mejora general ni ausencia de tirones. Informes: `phase_e_benchmark.json` y `phase_e_motion_benchmark.json`.

Se repite un tramo corto de aceleración seis veces: no es una prueba de toda la ciudad. Sigue pendiente valorar comodidad y composición en curvas en una sesión de juego prolongada antes de extender el estilo a otros sectores.

## Reproducir

Abrir `scenes/NightPilot.tscn` y pulsar F6. Shift activa turbo; F4 cambia intensidad visual.

```powershell
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/phase_e_motion.gd
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/phase_e_retro.gd
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/benchmark_phase_e.gd -- --turbo
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/capture_neon_motion.gd
```
