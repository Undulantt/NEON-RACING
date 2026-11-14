# Revisión del motor — SF.2.1

Se sustituye el timbre de Audio B a partir del comentario del jugador: el motor anterior se percibía eléctrico. La revisión cambia las fuentes y su mezcla por RPM; conserva transmisión, física, velocidades, viento y cámara.

## Cambios

- Los tonos de combustión casi sinusoidales se sustituyen por cuatro muestras sintéticas originales: pulsos de encendido con amplitud/timing ligeramente irregulares, resonancias graves de escape y ruido de admisión/carga. Se generan fuera del juego con `tools/build_combustion_audio.py`; no usan grabaciones externas.
- Hay dos bancos de carga, referidos a **3000 y 6000 RPM**. Se mezclan progresivamente entre **3500 y 6500 RPM**, evitando depender de estirar una sola muestra a todas las revoluciones. El banco alto tiene más textura y brillo; ambos tienen el mismo RMS de fuente para no adelgazar el motor a altas RPM.
- Los dos bancos mantienen una frecuencia de pulsos coherente con las RPM reales. El banco alto se reproduce a la mitad del multiplicador del bajo porque su referencia es el doble. Se conserva el cuerpo grave independiente y la capa de retención.
- Las marchas siguen produciendo la caída real de RPM y el corte de carga existente. Al subir de marcha también retrocede suavemente la mezcla hacia el timbre de RPM más bajas; la reducción vuelve a seguir el golpe de revoluciones de la transmisión existente. No se añadieron marchas ficticias ni sonidos TURBO/BURST nuevos.
- Los cinco reproductores de B permanecen preparados; los bancos se cruzan sin reiniciar streams. La pestaña Audio muestra el porcentaje de **banco alto** para observar esa respuesta.

## Uso y ajustes

Iniciar normalmente con F5 y seleccionar **Audio B** mediante Ctrl+Alt+O, o desde Ctrl+Alt+P → Audio. Si había una configuración de prueba guardada muy distinta, usar **Restablecer audio**. Se conservan los ajustes de tono, carga, cuerpo, viento, volumen y transición. Audio A sigue siendo la mezcla original anterior a SF.1; no se modifica.

Rutas de muestras y referencias están en `config/combustion_audio_assets.json`. Los cuatro WAV mono de 4 segundos/22050 Hz se llaman `engine_combustion_coast`, `engine_combustion_load_low`, `engine_combustion_load_high` y `engine_combustion_body`, dentro de `assets/audio`. Son recursos sintéticos provisionales que podrán sustituirse por grabaciones autorizadas.

## Validación y escucha

- **110 comprobaciones** aprobadas con los tres perfiles: se añaden casos de ralentí con banco bajo, entrada al banco alto y retorno de timbre al subir marcha. Se mantienen las pruebas de FOV, estados, capas, guardado y 15 archivos protegidos por hash.
- Captura del mezclador real con VECTOR: aceleración, retención y frenado; **seis subidas y seis reducciones**, sin clipping ni desbordamiento de captura. La revisión no cambia su velocidad ni sus RPM mecánicas. El escenario usa exclusivamente suelo sintético de pruebas; no altera cartografía.
- Las muestras se normalizan por separado con margen de pico y sin desplazamiento DC. La igualación RMS de las copias de escucha sirve para comparar timbre y no modifica ganancias del juego.
- Se corrigió la limpieza del auxiliar de captura: detener voces, retirar el capturador y esperar la liberación de la escena antes de salir evita referencias de audio pendientes al cerrar Godot.

Para comparar el motor B previo y el revisado, con RMS igualado:

- [Motor B anterior](evidence/sf21_audio_B_matched.wav).
- [Motor B de combustión revisado](evidence/sf21r_audio_B_matched.wav).

Informes actuales: `sf21_validation.json`, `sf21r_audio_capture.json`, `sf21r_audio_analysis.json`, `combustion_sources.json` y `combustion_validation.json`. Las capturas previas SF.2.1 se conservan como referencia histórica. La valoración de potencia, peso y calidad del timbre sigue correspondiendo a la prueba del jugador.

Reproducción desde la raíz:

```powershell
python tools/build_combustion_audio.py
$godot = (Resolve-Path '..\..\Godot_v4.7.2-stable_win64_console.exe').Path
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf21.gd
& $godot --path . --max-fps 60 --script tests/capture_sf21_audio.gd -- --capture-engine-audio --combustion-review
python tools/analyze_sf21_audio.py --prefix sf21r
```

La entrega sigue en SF.2.1. No se avanza al audio específico de habilidades/neumáticos de SF.2.2.
