# Velocímetro, marchas y sonido de motor

Referencia aplicada únicamente al velocímetro: arco de RPM blanco con zona roja desde 6500, aguja dinámica, velocidad digital, marcha y reserva de turbo integrada como arco interior cian. El turbo mantiene su carga real y se ilumina al activarse. No cambia el minimapa ni la composición del resto del HUD.

La caja automática tiene siete marchas, neutral y reversa. La aguja sube con las RPM y cae durante cada subida de marcha; las reducciones incluyen un breve golpe de gas. No se agregan controles manuales. Los tres perfiles existentes usan la misma configuración de caja, calibrada a sus respectivas velocidades.

El motor usa dos bucles procedurales originales, con mezcla de carga y retención. Su tono sigue las mismas RPM que la aguja, con una transición suave, una breve descarga al subir de marcha y un repunte al reducir. Todos los sonidos nuevos pasan por el canal Motor de F7 y respetan M para silenciar.

La transmisión convierte el movimiento del controlador arcade en RPM para presentación y audio. Conserva las fuerzas, aceleración, límites, turbo, derrape y BURST existentes. El perfil APEX seleccionado en la escena se conserva. Parámetros: `config/powertrain_config.json`; implementación: `scripts/driving/AutomaticTransmission.gd`.

## Verificación

- `tests/godot_powertrain.gd`: los tres perfiles recorren las siete marchas, con seis caídas de RPM al subir y seis golpes de gas al reducir; comprueba HUD, audio, reversa, recuperación y pausa. El modelo también se prueba a 30, 60 y 120 Hz, incluyendo histéresis para evitar cambios repetidos cerca del umbral.
- Regresiones de BURST, conducción, pendientes y efectos nocturnos, más validación de datos urbanos. Informes `powertrain_validation.json`, `burst_validation.json`, `slope_physics_validation.json` y `phase_e_motion_validation.json`.
- `tests/capture_powertrain.gd`: arranque, aceleración y frenado reales con VECTOR en una calle C2 de la escena principal. Captura el canal Engine mediante AudioEffectCapture y verifica los seis cambios en cada sentido.
- `tools/analyze_engine_audio.py`: comprueba audio no vacío, ausencia de saturación y cambios de tono coherentes con las RPM. El avance de audio solo se convierte a mono, remuestrea y normaliza para escucharlo con comodidad; la grabación original conserva su volumen.

[Antes del cambio](evidence/tachometer_before_shift.png) · [Después del cambio](evidence/tachometer_after_shift.png) · [Séptima y BURST](evidence/tachometer_top_gear.png) · [Motor: aceleración y reducciones](evidence/engine_gear_changes_preview.wav).

El motor continúa siendo sintetizado; no utiliza una grabación de un automóvil real. Esta revisión añade expresividad a los cambios con un coste pequeño y sin descargar recursos de audio externos.
