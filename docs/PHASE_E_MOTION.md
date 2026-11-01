# Fase E — refinamiento de movimiento y contraste

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
