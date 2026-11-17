# SF.3 — Corrección de visibilidad y herramienta de comparación

La primera entrega tenía dos límites que hacían poco útil la comparación: al detenerse el coche la ganancia era cero y, al conducir, los refuerzos eran demasiado discretos. Multiplicar el brillo de bordes cian ya saturados tampoco producía suficiente diferencia. Las pruebas anteriores verificaban estados y restauración, pero no cuantificaban que los píxeles del suelo cambiasen.

## Correcciones

- **Base visible:** SF.3 mantiene una presencia ambiental mínima de 0.20 aun detenido, configurable con Visibilidad mínima. La ganancia de conducción ahora interpola entre esa base y 1 usando la envolvente original de velocidad/TURBO/BURST. La envolvente pública de SF.4 conserva sus valores anteriores.
- **Contraste real:** el asfalto tiene agregados y brillo más perceptibles. Los bordes usan contraste de color entre referencias claras y el cian de fondo, en vez de aumentar canales que ya estaban saturados. Marcas y cabezas de farola se aclaran sin cambiar sus mallas. Todo sigue fijo al mundo.
- **Vista previa estática:** aplica visualmente la intensidad configurada, aunque el coche esté detenido. Es transitoria, no se guarda y no simula velocidad, RPM, TURBO o BURST ni altera la señal física destinada a SF.4.
- **Diagnóstico:** Entorno muestra velocidad recibida, intensidad aplicada, enlaces de materiales y ausencia de adaptador/telemetría/intensidad/capas. Si falta el enlace explícito, el consumidor puede recuperar automáticamente el material nocturno compatible del mundo actual y conservar CityFurniture.
- **Interfaz:** los controles globales se llaman Cámara A/B; los presets de Entorno indican cuál está seleccionado. Restablecer SF.3 queda visible arriba de la lista, junto a la vista previa.

## Cómo comprobarlo sin conducir

1. Iniciar el juego y abrir **Ctrl+Alt+P → Entorno**.
2. Pulsar **Restablecer SF.3** para descartar fuerzas a cero guardadas en pruebas anteriores.
3. Marcar **Vista previa estática (sin conducir)**.
4. Comparar **Original** y **Completo**, dentro de esa pestaña. Revisar el suelo y los bordes próximos; Original anula también la vista previa.
5. Desmarcar la vista previa para evaluar la respuesta de conducción real.

Si aparece SIN ADAPTADOR, el panel ya no afirma silenciosamente que el efecto está aplicado: el escenario necesita el material nocturno compatible. La prueba reproducible usa el mundo normal del menú. Las escenas diurnas de diagnóstico no se convierten automáticamente a ese estilo.

## Validación

- **85 comprobaciones SF.3**, con casos nuevos para base visible, vista previa, selección inequívoca, reinicio y conservación de transform, velocidad, RPM y BURST.
- **67 comprobaciones SF.1** y atajos nativos manteniendo W, aprobados.
- Prueba nueva de GPU con el coche detenido: misma pose/cámara/decoración y dos regiones de asfalto que excluyen coche, cielo, indicadores y textos. Se comparan Original/Original de control, base detenida y vista previa. La diferencia de la base y de la vista previa debe superar el ruido entre dos originales. También se prueba la recuperación automática del enlace del mundo.
- Control de píxeles: Original/Original difiere aproximadamente 0.0000025 RGB; la base detenida 0.003495 y la vista previa 0.018429 (media absoluta por canal normalizada). Esto verifica un cambio de material real frente a la captura de control, sin convertir esas cifras en una puntuación perceptual.
- El benchmark estático actualizado aprobó el presupuesto, manteniendo las mismas 259 llamadas de dibujo en todos los modos. No certifica FPS durante un recorrido completo.
- Los 27 archivos protegidos de SF.3 conservan sus hashes. No cambian física, cámara, audio, mallas, colisiones ni datos geográficos.

Informes: `sf3_visibility_validation.json`, `sf3_validation.json`, `sf3_benchmark.json` y `sf3_visibility_regressions.json`. Evidencia: `evidence/sf3_fix_original.png`, `sf3_fix_stationary.png`, `sf3_fix_preview.png`, `sf3_fix_panel.png`.

```powershell
$godot = (Resolve-Path '..\..\Godot_v4.7.2-stable_win64_console.exe').Path
& $godot --headless --path . --fixed-fps 60 --script tests/godot_sf3.gd
& $godot --path . --script tests/capture_sf3_visibility.gd -- --benchmark
& $godot --path . --script tests/sf3_city.gd -- --benchmark
```

La captura estática demuestra aplicación real de materiales; no sustituye la evaluación personal del flujo óptico al conducir. La revisión continúa en SF.3, sin implementar la transformación del vehículo de SF.4.
