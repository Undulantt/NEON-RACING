# Fase E — revisión visual a partir de referencias

## Dirección y alcance

Continuación del piloto `696db07`, retomada el 01/11/2026. El usuario rechazó la estética demasiado apagada y proporcionó tres referencias: avenida con palmeras y bordes cian, ciudad con iluminación magenta intensa y conducción con horizonte synthwave. Esta revisión prioriza exclusivamente la imagen; la música de prueba queda detenida por defecto.

Se mantiene el sector del Malecón, el mundo geográfico y el renderizador Compatibility. No se copian fotografías, modelos ni texturas de las referencias. Todo recurso nuevo es código/geometría procedural original.

## Cambios visibles

- Cielo violeta con horizonte magenta, bruma cromática estilizada y disco solar synthwave. Es una composición artística, no una simulación de hora solar.
- Resplandor de pantalla con tres lecturas de textura/mipmaps. El HUD queda por encima para conservar legibilidad.
- Asfalto con grano filtrado por distancia, brillo rasante, bandas de color y manchas luminosas. Son reflejos aproximados, **no espejos, SSR ni reflejos reales de coches/palmeras**.
- Bordes cian continuos, marcas longitudinales y manchas magenta que siguen la geometría de la avenida. Son señalización visual arcade; no datos de carriles oficiales.
- Farolas con brazo angular y palmeras de tronco curvo, secciones hexagonales y frondas divididas. Presupuesto de hasta diez luminarias; solo las dos más próximas emiten luz real.
- Ventanas rosa/cian y cornisas violetas en las fachadas del piloto; el resto de la ciudad no recibe esta decoración.
- Carrocería de cuña, alerón, lamas, ópticas traseras segmentadas y acentos cian. Se conservan ruedas, animación de dirección, turbo, frenos, dimensiones físicas y controlador. La cámara inicia en su modo cercano ya existente.

`RetroLook.gd` usa el sector y la vía de `config/night_pilot.json`, aplica materiales al cargar el sector vial y limita a 16 segmentos el shader. `RetroCar.gd` reemplaza únicamente la apariencia del vehículo en esta escena. La escena principal sigue intacta.

## Pruebas y progresión

Se corrigieron normales invertidas en la primera carrocería, aliasing del grano lejano y franjas del disco solar. Las primeras capturas emitieron dos avisos de textura GL al salir; al eliminar la creación redundante de dos cielos consecutivos, la siguiente captura terminó sin esos avisos.

Hashes de mapa, manifiestos de relieve/ciudad, controlador, cámara y configuración de conducción comparados con `phase_e_baseline_hashes.json`: sin cambios.

La medición guardada tras la revisión visual dio **2,573 ms / 388,64 FPS**, frente a **2,450 ms / 408,24 FPS** en la escena diurna equivalente: **+5,04 %** de tiempo medio. p95: 3,491 ms nocturno y 3,572 ms diurno. 217,83 MB estáticos frente a 214,22 MB; cero frames fuera del asfalto. Protocolo: RTX 4060 Ti, Compatibility, 1280×720, VSync desactivado, 540 frames de calentamiento y 1.080 frames por pasada; seis repeticiones del mismo tramo corto de aceleración. No representa toda la ciudad ni garantiza esas cifras en otro equipo. Informe actual: `phase_e_benchmark.json`; el piloto anterior queda en `phase_e_initial_benchmark.json`.

Validación renderizada final: PASS (`phase_e_retro_validation.json`). Trayectoria y velocidad idénticas (32,009 m/s), cero frames fuera del asfalto, turbo y FOV activos, F8 correcto, descarga/recarga de decoración exactamente una vez y música detenida. 548 ventanas, ocho acentos de neón y diez luminarias. Ejecución final sin errores de script ni avisos GL.

## Abrir y verificar

Abrir `scenes/NightPilot.tscn` en Godot y pulsar F6. Música detenida; sonidos existentes del coche y ambiente conservados.

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot-local-profile/retro-check'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/phase_e_retro.gd
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/benchmark_phase_e.gd
```

Capturas reales: [conducción](evidence/phase_e_retro_driver.png), [sector](evidence/phase_e_retro_sector.png).

## Límites artísticos pendientes

Es una segunda pasada de dirección artística, no una reproducción del acabado de los juegos de referencia. Persisten edificios genéricos, detalles limitados del coche y ausencia de reflejos geométricos reales. Falta revisar la composición y legibilidad en curvas durante una sesión humana. La extensión a otros barrios y un salto a modelos/materiales más elaborados requieren validar primero este resultado. No se presentan esas tareas como terminadas.
