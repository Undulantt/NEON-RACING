> Revisión posterior: [dirección visual basada en referencias](PHASE_E_RETRO.md). Este documento conserva el primer piloto y sus mediciones.

# Fase E — piloto nocturno del Malecón

## Auditoría y dirección inicial (31/10/2026)

Base actual: `a979f45`, fase C.6, mundo ampliado con relieve, 62.410 volúmenes y 541 sectores urbanos. Ya existían turbo, recompensa por derrape, partículas, luces emisivas del coche, cámara con FOV dinámico y sonidos procedurales de motor/neumáticos/boost. Se reutilizan. `project.godot` tenía una modificación previa y no se incluye en esta entrega.

Dirección propuesta antes de implementar: azul profundo en cielo y fachadas, ventanas ámbar, acentos cian/magenta exclusivamente en comercios, iluminación acotada sin sombras adicionales, legibilidad vial por encima del brillo. Un único sector `0_-1`, junto al Malecón/Paseo Álvaro Obregón. Escena independiente heredada del mundo existente, sin cambios estructurales del generador.

## Implementación

Abrir `scenes/NightPilot.tscn` y pulsar F6. La escena principal sigue siendo la existente. Alternativa:

```powershell
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . scenes/NightPilot.tscn
```

- `NightPilot.gd` carga el mundo con relieve, sitúa el coche sobre el asfalto y aplica el perfil visual. No modifica datos ni el controlador.
- `NightStyle.gd` configura cielo nocturno y luz lunar. Solo el sector elegido recibe materiales azul/violeta, ventanas y un máximo de ocho acentos comerciales. No se ilumina cada vivienda con un nodo de luz.
- Detalles de fachada agrupados en una malla; farolas, palmeras estilizadas y reflectores viales en otras dos. Tres letreros como máximo. Geometría adicional exclusivamente visual, sin colisiones.
- Alumbrado derivado de la línea y anchura vial existentes, fuera del asfalto. Máximo seis farolas, dos activas cerca del jugador; un haz compartido por los faros. Sin sombras dinámicas nocturnas, SSR, volumetría ni dependencia de bloom. Material luminoso sin sombreado para Compatibility.
- Alturas de decoración tomadas del relieve; fachada anclada a la cota existente. La apariencia sigue el ciclo de carga/descarga y F8 del sector.
- Se reutilizan luces traseras/freno, llamas del turbo, partículas de derrape, líneas de velocidad y cámara dinámica de C.6.
- Las palmeras, luminarias y nombres de letreros son decoración ficticia; no un levantamiento de equipamiento o negocios reales.

## Audio

F7 abre/cierra los controles independientes Música, Motor y Efectos/ambiente. Las preferencias se guardan en `user://night_audio.cfg`. El motor y los efectos existentes se enrutan a buses dedicados. La música no controla la física.

`config/night_pilot.json` acepta pistas para `free_drive` y `race`; `NightAudio.set_music_state()` es la entrada para una futura carrera. Ambas usan hoy la misma demostración. No se implementan carreras ni transiciones musicales adaptativas en esta etapa. WAV y recursos AudioStream importados son sustituibles por pistas originales/licenciadas. La música y el ambiente se pausan con el juego.

Incluye dos recursos originales generados por `tools/build_night_audio.py`: estudio synth a 160 BPM (12 segundos, percusión, bajo y motivo propio) y ruido de oleaje sintetizado. Son placeholders, no una producción EUROBEAT terminada ni grabaciones reales. No hay samples, melodías ni archivos de terceros. Créditos en `CREDITS_AND_LICENSES.md`.

## Extensión

Cambiar sector, spawn y vía de paseo en `config/night_pilot.json` permite aplicar las mismas reglas a otro piloto sin modelar sus edificios manualmente. Antes de ampliar simultáneamente a muchos sectores, convertir el límite de luces en un presupuesto global. El cielo nocturno afecta a la escena completa; la decoración solo al sector piloto.

## Registro incremental

1. Auditoría de sistemas C.6 y hashes de protección guardados en `phase_e_baseline_hashes.json`.
2. Escena independiente, decoración, faros, audio y controles implementados.
3. Primer render: se detectaron farolas sobre el asfalto y aviso F7 bajo el minimapa. Se corrigieron con anchura vial real y reubicación del texto.
4. Errores iniciales de inferencia de tipos GDScript corregidos. Importación de editor mostró el aviso de guardado seguro del entorno; pruebas runtime usan perfil APPDATA local limpio.
5. Prueba visual inicialmente desfasada un frame por las esperas de captura. Se reseteó el estado físico antes de cada pasada; comparación renderizada aprobada.
6. Primer benchmark: +29,8 % de tiempo medio, con pico de 260 ms. Se redujo presupuesto de luces y se añadió calentamiento en movimiento. No se acepta ese primer resultado como rendimiento final.

## Validación final

- Godot renderizado: PASS. Un sector decorado, 548 ventanas, ocho acentos, seis farolas (solo dos activas), ausencia de colisiones añadidas.
- Trayectoria de aceleración diurna/nocturna idéntica hasta 32,009 m/s (~115 km/h), cero frames fuera del asfalto. Turbo visual y FOV dinámico existentes: PASS.
- F8 oculta decoración; descarga y recarga por distancia vuelven a decorarla exactamente una vez: PASS.
- Buses independientes, silenciamiento musical, persistencia de volúmenes, apertura/cierre por F7 y selección de estado de carrera: PASS. [Captura de mezcla](evidence/phase_e_audio.png).
- SHA-256 del controlador, cámara, configuración de conducción, mapa y manifiestos de relieve/ciudad: sin cambios. Recursos WAV reproducibles byte por byte, 12 s mono/22.050 Hz, sin saturación PCM.
- Capturas reales revisadas: [conducción](evidence/phase_e_driver.png) y [sector](evidence/phase_e_sector.png). No se hizo una sesión humana prolongada ni una prueba auditiva humana.

| Medida | Día actual | Piloto nocturno |
|---|---:|---:|
| Tiempo medio | 2,400 ms | 2,530 ms |
| FPS promedio sin VSync | 416,74 | 395,21 |
| p95 | 3,567 ms | 3,752 ms |
| Máximo | 7,808 ms | 5,372 ms |
| Memoria estática máxima | 214,54 MB | 217,50 MB |
| Nodos máximos | 541 | 569 |

Aumento medio: **5,45 %**, dentro de 15 %. RTX 4060 Ti, Compatibility, 1280×720; seis repeticiones del mismo tramo de aceleración (~57 m), 1.080 frames renderizados por modo, simulación fija de 60 Hz, VSync desactivado y 540 frames de calentamiento en movimiento. Ambas pasadas comparten proceso/cachés. No equivale a FPS garantizados en otros equipos ni a un recorrido por toda la ciudad; memoria es el contador estático del motor. Picos iniciales de compilación/carga quedan fuera de la muestra caliente.

La segunda medición, antes de quitar sombras lunares, dio +19,13 % y se conserva en `phase_e_benchmark_pre_shadow_optimization.json`. Desactivar las sombras nocturnas redujo ese coste sin añadir o alterar colisiones; la luz puede atravesar geometría porque no tiene oclusión por sombras. Es un compromiso del piloto.

Repetición:

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot-local-profile/phase-e-new-profile'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/phase_e_pilot.gd
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/benchmark_phase_e.gd
```

Informes: `phase_e_validation.json`, `phase_e_benchmark.json`. El estado final se guarda como checkpoint Git local; no se cambia la escena principal.

## Pendientes de dirección artística

Validación humana de curvas a alta velocidad, mezcla sonora y comodidad visual; música EUROBEAT completa y licenciada/original; transiciones musicales de carrera; luces/reflejos más elaborados según presupuesto gráfico. Revisar el diseño del piloto antes de extenderlo al resto del mapa. No se incorporan carreras nuevas ni se alteran landmarks, costa, relieve o dimensiones de edificios.
