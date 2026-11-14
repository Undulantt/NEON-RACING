# SF.1.1 y SF.2.1 — TURBO visual, motor y viento

> Revisión posterior: el timbre B se sustituyó por bancos de combustión; consultar [motor revisado](SF21_MOTOR_COMBUSTION.md). Las capturas y cifras de esta página documentan la primera mezcla SF.2.1.

Entrega experimental para evaluación. Se conserva la base SF.1 aprobada y se detiene el desarrollo antes de SF.2.2. No se modifican físicas, transmisión, perfiles, velocidades ni cartografía. Las puntuaciones de SF.1 motivan intensificar la presentación, manteniendo su control y comodidad.

## Cómo comparar durante la conducción

F5 → Jugar → modo libre o carrera → vehículo. Abrir el laboratorio con **Ctrl + Alt + P**. Sus pestañas **Cámara** y **Audio** se ajustan con el ratón mientras se conduce; ningún control nuevo toma foco de teclado. Esc mantiene la pausa habitual y oculta el laboratorio. Se verificaron los atajos nativos manteniendo W pulsada.

Hay tres comparaciones independientes:

| Comparación | Uso |
|---|---|
| TURBO SF.1 / SF.1.1 | Mantener **Cámara B** y **FOV dinámico experimental** activados. En Cámara, comparar botones **+0%, +10%, +15%, +25%**. **0% conserva el TURBO aprobado de SF.1.** |
| Audio anterior / SF.2.1 | **Ctrl + Alt + O**, o botones **Audio A · anterior / Audio B · SF.2.1**. No altera cámara, conducción ni perfil. |
| Cámara anterior a SF.1 / cámara SF.1 | **Ctrl + Alt + B**, conservado de la entrega anterior. A vuelve a la cámara previa a SF.1, por lo que no es la comparación indicada para aislar el nuevo porcentaje de TURBO. |

En Audio, los interruptores **Motor continuo** y **Viento reactivo** permiten aislar esas capas en B. Los sonidos previos de cambio de marcha, neumáticos y boost se conservan en ambos modos; no se han sustituido por efectos SF.2.2. **M** mantiene el mute del automóvil existente. Los buses siguen respondiendo a Opciones y F7: motor en **Engine**, viento en **Effects**; **Music** permanece independiente.

Los botones fijos inferiores **Restab. cámara / Guardar cámara / Cargar cámara** afectan únicamente la cámara. Al final de la pestaña Audio hay **Restablecer audio / Guardar / Cargar**, independientes. Los archivos de prueba son:

- Cámara y porcentajes TURBO: `user://sf1_camera_experimental.cfg`.
- Motor/viento: `user://sf21_audio_experimental.cfg`.

Los argumentos `--sf2-original` y `--sf2-experimental`, después de `--`, fuerzan el modo de audio al iniciar. Los argumentos SF.1 de cámara siguen funcionando. Sin preferencias guardadas se inicia en cámara B, TURBO +25% y audio B.

## SF.1.1 — FOV de TURBO

Los parámetros nuevos se encuentran en `config/sf11_turbo_fov.json`; `config/sf1_camera_experimental.json` permanece idéntico. Sus valores se incorporan a la configuración del controlador existente, sin otro gestor ni Autoload.

| Preset | Objetivo a máxima normal, referencia 78° |
|---|---:|
| Anterior / +0% | 78° |
| +10% | 85.8° |
| +15% | 89.7° |
| +25% inicial | 97.5° |

Son **grados verticales**, con KEEP_HEIGHT. El incremento es literal sobre el objetivo TURBO anterior a la velocidad actual: `(FOV normal + incremento TURBO SF.1) × (1 + porcentaje/100)`. No se multiplica el FOV normal cuando TURBO está inactivo. Se conserva el cálculo normal 70–75° y la progresión BURST hasta 82°.

Se toma el **mayor** entre la envolvente SF.1 y el objetivo TURBO ampliado: no se suma además el incremento BURST. El porcentaje no se aplica repetidamente cada frame. La activación se filtra a **12/s** y la salida a **5/s**, configurables. La cámara también suaviza su FOV: en la prueba a 60 Hz alcanzó más de 96° dentro de 0.5 s, con salto máximo por paso aproximado de 1.66°. No hay un cambio instantáneo de perspectiva.

El límite de TURBO empieza en **100°**, ajustable entre 82° y 115°. Es distinto del límite normal/BURST de SF.1. Al desactivar TURBO, cambiar preset o bajar un límite, el FOV actual converge suavemente; el objetivo queda limitado inmediatamente. A/B puede partir de un FOV anterior superior al nuevo límite durante esa convergencia.

El barrido del SpringArm adapta la esfera al plano cercano y la relación de aspecto; se amplió su margen de tamaño y la altura mínima de retracción según el techo del coche. La configuración inicial de 97.5° pasó la prueba contra pared a 21:9 sin introducir la cámara en el propio vehículo. La altura/distancia libres aprobadas siguen siendo 1.8/5.4 m. El 25% produce una perspectiva considerablemente más amplia: evaluar curvas y comodidad antes de adoptarlo como definitivo.

## SF.2.1 — Arquitectura de audio

`SpeedFeedbackController` sigue siendo el observador de presentación. Amplía su señal `telemetry_updated(snapshot)` con RPM, marcha, carga real, multiplicador de carga durante cambio, acelerador, límites RPM y estado de apoyo. También conserva velocidad, aceleración, TURBO/BURST y derrape para futuros consumidores.

Su hijo `scripts/feedback/SpeedAudioController.gd` consume esa instantánea; no aplica controles ni escribe RPM o habilidades. Configuración independiente: `config/sf21_audio_experimental.json`. El panel existente muestra sus parámetros, mezcla A/B, tono actual/objetivo, RPM, carga, viento y tiempo CPU. El porcentaje A/B indica cuánto audio B entra en la transición, no progreso de BURST.

Se reutilizan los dos bucles sintéticos de combustión de `DrivingFeedback.tone(0/3)`. B los presenta como:

- **Base/retención:** motor continuo, presente al ralentí, con variación por RPM y corte de carga durante los cambios.
- **Carga:** armónicos cuya ganancia sigue la carga de la transmisión y, moderadamente, la aceleración medida. Al levantar el pie disminuye, aunque la velocidad siga siendo alta.
- **Cuerpo grave:** el bucle base a medio tono relativo, con ganancia dependiente de la carga; aporta contenido grave sin un golpe o vibración constante.
- **Viento:** ruido original periódico filtrado, con intensidad y tono ligados a velocidad física.

El tono principal utiliza RPM reales / referencia de transmisión (3000 RPM), con escala y límite configurables. Los cambios de marcha y las reducciones se oyen a partir de las caídas/subidas de RPM existentes y de su multiplicador real de carga. No se añadió otra transmisión ni un reloj de revoluciones. Al soltar acelerador hay además una caída **acústica** configurable de hasta 500 RPM equivalentes, filtrada por carga y sin alterar el tacómetro. El motor no puede subir de tono indefinidamente con la velocidad.

El viento empieza suavemente a **45 km/h**, casi inaudible a baja velocidad; llega a intensidad normal 1 cerca de la máxima de cada perfil. Sobre esa velocidad puede crecer hasta **1.35** en función de la velocidad física y el margen BURST del perfil. Una bandera BURST sin desplazamiento no genera viento; tampoco hay un temporizador sonoro separado. Si se suelta el acelerador a gran velocidad, el viento sigue respondiendo al movimiento real mientras este disminuye.

Se utiliza [AudioStreamPlayer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html) sin posicionamiento para el coche del jugador, evitando depender de Doppler o de la distancia de una cámara que lo persigue. Los buses Engine/Effects ya existentes conservan volumen y mute; no se cambia el volumen de EUROBEAT. No hay filtros de bus nuevos, audio generado por muestra cada frame ni postprocesado gráfico.

**Conservación de A:** `DrivingFeedback.gd` permanece idéntico. Sigue calculando sus voces originales y eventos. El nuevo controlador se procesa después (`process_priority=100`), y mezcla linealmente las dos voces continuas antiguas con B. Al terminar la transición hacia A deja de tocar sus ganancias. Los cuatro reproductores nuevos permanecen preparados a volumen cero en A para poder comparar sin reiniciar ni interrumpir bucles. Cambio de escena, pausa y `driving_enabled` silencian/pausan las nuevas capas; M también se respeta.

## Parámetros de audio iniciales

Todas las filas tienen control en vivo en Audio. Los cambios de volumen de capa se suavizan; la ganancia final también respeta mezcla A/B, mute y buses.

| Parámetro | Inicial |
|---|---:|
| Base/retención / carga / cuerpo | −22 / −19 / −25 dB |
| Escala de tono principal / cuerpo | 1.0 / 0.5 |
| Límite de tono principal | 2.7× |
| Caída acústica al soltar | 500 RPM equivalentes |
| Respuesta tono / carga | 14/s / 10/s |
| Ganancia base viento | −27 dB |
| Inicio / exponente viento | 45 km/h / 2 |
| Presión extra máxima sobre velocidad normal | +0.35 |
| Tono viento base / incremento | 0.85 / 0.35 |
| Respuesta viento / mezcla A-B | 4/s / 10/s |

Las ganancias son de presentación, no estadísticas definitivas. Los tres perfiles comparten por ahora el timbre provisional, pero usan sus propias velocidades, transmisión y progresión reales. La mezcla inicial B resultó **4.42 dB RMS más fuerte** en la captura de referencia. No atribuir toda la mejora percibida al timbre sin comparar volumen: se entregan también copias con RMS igualado.

## Recursos y sustituciones pendientes

No se añadieron grabaciones ajenas. El motor reutiliza síntesis original ya disponible; aún faltan bancos de grabaciones de ralentí, carga y retención adecuados para un acabado final. Su sustitución corresponde a los streams de las voces `coast`, `load` y `body` en `SpeedAudioController.configure`; el observador y la transmisión no necesitan cambiar.

`assets/audio/sf21_wind_placeholder.wav` es una muestra original de 2 s, mono, 22050 Hz, creada por `tools/build_sf21_wind.py` con ruido filtrado periódico y semilla fija. Se calcula fuera del juego, no durante la conducción. Es provisional: puede sustituirse por viento grabado de licencia compatible, con bucle limpio. Su carga y punto de bucle están localizados en el mismo configure. No es un nuevo sonido de propulsión TURBO.

Capturas del **mezclador real**: `docs/evidence/sf21_audio_A.wav` y `sf21_audio_B.wav`, 29 s por modo, estéreo 48 kHz. Corresponden a VECTOR real en un suelo sintético de pruebas: 1 s ralentí, 20 s aceleración, 2 s retención, 6 s frenado; el mando de freno/reversa puede acabar entrando en reversa. No son una conducción grabada en La Paz ni una reconstrucción del mapa.

Copias para escuchar A/B: [A con RMS igualado](evidence/sf21_audio_A_matched.wav), [B con RMS igualado](evidence/sf21_audio_B_matched.wav). Se convierten a mono 22.05 kHz y solo se iguala la ganancia RMS, sin EQ, cambio de tono ni compresión. RMS igualado no garantiza idéntica sonoridad perceptual. Sus ganancias de escucha **no se aplican al juego**. Los originales se conservan para inspección.

## Evaluación reproducible

Para probar en el tramo real ya preparado de SF.1:

```powershell
$godot = (Resolve-Path '..\..\Godot_v4.7.2-stable_win64_console.exe').Path
& $godot --path . --script tests/sf1_city.gd -- --manual-route
```

El recorrido sigue utilizando `extension_C2`, puntos OSM 25–42, 1693.97 m. El botón **Reiniciar tramo OSM (SF.1)** vuelve al mismo punto con VECTOR. No se creó una carrera nueva. En el flujo normal se pueden seleccionar también COMET y APEX.

1. Cámara B, preset TURBO 0%, audio A. Acelerar, mantener máxima, soltar acelerador y frenar.
2. Repetir con audio B sin cambiar cámara ni perfil. Usar los interruptores para comparar motor solo, viento solo y ambos. Probar también con EUROBEAT a su volumen habitual.
3. Fijar el mismo audio y comparar TURBO 0/10/15/25% en pasadas equivalentes. Observar el velocímetro y conservar la misma entrada de acelerador al alternar.
4. Para juzgar solo timbre/respuesta, escuchar las copias A/B con RMS igualado o ajustar las ganancias en vivo. Registrar potencia, peso, fatiga del tono, lectura de cambios y si el viento tapa música/motor.

Las nuevas pruebas se ejecutan desde la raíz:

```powershell
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf21.gd
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf1.gd
& $godot --headless --path . --fixed-fps 60 --script tests/sf1_city.gd -- --manual-smoke
& $godot --path . --max-fps 60 --script tests/capture_sf21_audio.gd -- --capture-engine-audio
python tools/analyze_sf21_audio.py
& $godot --path . --script tests/benchmark_sf21.gd -- --benchmark
```

Se conservaron y ejecutaron además las suites D.1, navegación de carreras y transmisión. El flag `--capture-engine-audio` es solo de pruebas: permite crear streams reales también al usar un backend headless; las pruebas normales headless verifican telemetría sin simular que han escuchado audio.

## Resultados técnicos y límites

- **101 comprobaciones SF.1.1/SF.2.1 aprobadas:** presets literales, límites y transiciones, BURST sin acumulación, respuesta por RPM/carga, caída acústica, viento por velocidad, independencia de capas, persistencia, panel, pausa y hashes. Cámara ampliada probada contra pared y techo propio a 21:9.
- **67 comprobaciones SF.1 aprobadas**, con preset 0% para sus valores de referencia. La reproducción física A/B de los tres perfiles sigue dando diferencia máxima cero. **207 de D.1 y 48 de navegación**, más transmisión existente, aprobadas.
- **15 archivos protegidos idénticos SHA-256**, incluidos controlador, habilidades, transmisión, audio anterior, tres perfiles, configuración SF.1, entradas, VFX y cartografía (`sf21_baseline.json`).
- **Captura real A/B aprobada:** seis subidas y seis reducciones por pasada, misma velocidad máxima de prueba ≈235.947 km/h y estados físicos finales, sin frames de audio descartados. Pico digital A ≈0.0414, B ≈0.0953: sin clipping en esa captura sin música. Estos picos no certifican todas las mezclas posibles del usuario.
- **Benchmark de referencia aprobado:** RTX 4060 Ti, 1280×720, Compatibility, VSync desactivado. Ciudad existente, misma cámara/pose y telemetría sintética 180 km/h/6500 RPM, A/B/B/A, 3 s de calentamiento y 600 frames por muestra. Medias A ≈2.670 ms y B ≈2.352 ms; la diferencia negativa puede ser variabilidad del sistema y **no demuestra una mejora de rendimiento**. Cálculo de audio observado ≈18–26 µs. A también calcula objetivos para poder alternar sin saltos: no es una comparación contra un ejecutable SF.1 sin el módulo. No mide streaming durante un recorrido completo ni garantiza 60 FPS en otras máquinas.

Informes: `sf21_validation.json`, `sf21_audio_capture.json`, `sf21_audio_analysis.json`, `sf21_benchmark.json` y `sf21_regressions.json`. Capturas de interfaz: `evidence/sf21_audio_panel.png`, `evidence/sf11_turbo_panel.png`. En las capturas del benchmark se usa telemetría sintética expresamente para aislar presentación; la grabación de audio usa física real.

La calidad y comodidad finales requieren la evaluación del jugador, especialmente +25% de FOV y equilibrio motor/viento/EUROBEAT. No se probaron todas las calles, relaciones de aspecto o combinaciones extremas de parámetros. El timbre sintético de motor y el viento provisional son el principal límite de calidad de esta entrega.

**SF.2.2 permanece pendiente:** nuevos ataques TURBO, identidad/entrada/salida BURST y nuevas capas de neumáticos. Sus datos ya están disponibles en la instantánea compartida, pero no se añadieron cues, golpes, partículas ni vibraciones. Esperar resultados de esta primera prueba antes de implementarlos.
