# BURST — cuenta regresiva y efectos de velocidad

Implementación sobre los tres perfiles actuales. Se conserva la paleta original: el filtro negativo y sus controles fueron retirados.

## Elegir perfil en Godot

1. Abrir `scenes/cars/PlayerCar.tscn`.
2. Seleccionar el nodo raíz `PlayerCar`.
3. En el Inspector, cambiar **Vehicle Profile** a **VECTOR**, **COMET** o **APEX**.
4. Guardar la escena y ejecutar con **F5**.

La opción `--vehicle=COMET` o `--vehicle=APEX` al iniciar sigue funcionando y tiene prioridad sobre el valor guardado en la escena. El futuro selector de autos puede llamar `apply_vehicle_profile(id)` en reposo. Esta entrega no añade un menú de selección dentro del juego.

## Cuenta y cámara

El HUD central muestra **3 → 2 → 1 → BURST**. Se deriva del temporizador real de preparación, sin retrasar ni anticipar la activación física. COMET muestra la cuenta en sus tres últimos segundos; APEX, cuya preparación dura 2,5 s, muestra el 3 durante la primera fracción. Al perder las condiciones, la cuenta desaparece y vuelve a empezar con la preparación siguiente. El texto BURST permanece 0,7 s al activarse y luego despeja el centro.

La cámara abre el FOV progresivamente durante la preparación, hacia 86°. Durante los dos primeros segundos activos apunta gradualmente hacia 95°, y el crecimiento del bonus puede añadir hasta 3° más. Se usan transiciones exponenciales independientes del render. Al cancelar, el FOV vuelve de forma suave al correspondiente a la conducción normal. Cámara cercana/lejana y turbo siguen funcionando.

## Llamas y velocidad

- Dos líneas continuas de fuego rosa se depositan desde el contacto de las ruedas traseras reales. Cada lado conserva su propia trayectoria y une puntos consecutivos, también en curvas, en lugar de emitir figuras separadas en el centro del coche.
- Cada segmento tiene una base luminosa sobre el pavimento y dos superficies verticales cruzadas con máscara de fuego turbulenta. Ancho nominal 0,34 m y altura máxima 0,75 m; el centro entre ambas huellas permanece libre.
- Una sola malla compartida y un material aditivo sin luces ni sombras adicionales, con hasta **128 segmentos entre ambos lados**. Se muestrea al desplazarse al menos 0,55 m; los segmentos escalan con la distancia real para evitar huecos. Cada uno dura 0,9 s. La captura real tuvo 110 segmentos, aproximadamente 55 por huella.
- Las consultas físicas de cada rueda adaptan las huellas al apoyo y a las pendientes. Las edades normalizadas conservan precisión en sesiones largas. La ondulación y el desvanecido se congelan al pausar.
- La estela deja de emitirse al salir de BURST o volar. Recuperar, cambiar de perfil, inspeccionar o apagar efectos limpia las marcas; al perder apoyo se interrumpe la unión para evitar conectar posiciones lejanas.
- Las líneas de velocidad se multiplican, alargan y aceleran durante BURST, con halo rosa y núcleo claro. La prueba mostró **64 trazos visibles** frente a **11 del turbo** en el instante medido. Hay 144 candidatos radiales, filtrados para proteger minimapa, indicadores, ayuda y zona central de conducción.
- **F4** conserva los modos completos/sutiles/desactivados de la ciudad nocturna y afecta a llamas, partículas y nueva respuesta de cámara. La entrada y salida se suavizan; no hay destellos ni inversión de colores.

Ajustes de presentación separados de la física en `config/burst_effects.json`. No cambian motor, velocidades, preparación BURST ni perfiles.

## Validación

`tests/godot_burst_vfx.gd` pasó cuenta 3/2/1 para los tres perfiles, cancelación, FOV gradual, estela real en plano y pendiente, presupuesto de segmentos, continuidad de ambas huellas, separación real entre ruedas, seguimiento de curvas, mayor densidad de trazos, pausa, efectos desactivados, recuperación y precisión de edades tras una hora simulada. La verificación renderizada compara además la imagen con el fuego visible y oculto; detectó 4.717 muestras rosas diferentes a resolución reducida. FOV observado: 81,83° preparando y 94,72° activo, con un mayor incremento medido de 0,101° por paso durante el ensayo.

`tests/capture_burst_vfx.gd` registró una conducción física desde reposo por el tramo alineado real de C2 en `Main.tscn`. Capturó 3, 2 y 1, luego BURST a 199,77 km/h, FOV 93,81° y 110 segmentos de fuego apoyados en las dos huellas. Las capturas son `docs/evidence/burst_vfx_countdown_3.png`, `_2.png`, `_1.png`, `burst_vfx_active.png` y `burst_vfx_ground_detail.png` y `burst_vfx_wheel_fire_side.png`. La pose solo se congela al final para inspeccionar la estela desde arriba.

También pasaron la regresión de conducción `godot_phase_c.gd` y los controles de estelas, pausa, recuperación, desenfoque y modos F4 de `phase_e_motion.gd`. Los hashes de las fuentes físicas previas permanecen intactos.

`tests/benchmark_burst_vfx.gd` comparó normal/BURST/BURST/normal con cámara y geometría fijas, a 1280×720, Compatibility y VSync desactivado, en una RTX 4060 Ti. Cada etapa tuvo 150 fotogramas de calentamiento y 360 muestras; BURST se forzó únicamente para medir los efectos con **128 segmentos**, más que las observadas normalmente.

Medias agregadas: **2.08 ms normal** y **3.08 ms con BURST**; diferencia de **1.01 ms** y **2 llamadas de dibujo** adicionales. Esta prueba incluye el coste del ensayo y no representa FPS de recorrer toda la ciudad ni una garantía para otro equipo. Informe completo: `docs/burst_vfx_benchmark.json`.

Informes: `burst_vfx_validation.json`, `burst_vfx_render_validation.json`, `burst_vfx_benchmark.json`, `burst_vfx_driving.log` y `burst_vfx_motion.log`. La captura OpenGL conservó el aviso de inicialización de caché de shaders ya observado; los shaders de estos efectos compilaron y renderizaron sin errores.

```powershell
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location) '.godot/test_userdata'
& $g --headless --path . --fixed-fps 60 --script tests/godot_burst_vfx.gd
& $g --path . --fixed-fps 60 --script tests/capture_burst_vfx.gd
& $g --path . --fixed-fps 60 --script tests/benchmark_burst_vfx.gd
```
