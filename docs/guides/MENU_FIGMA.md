# Menú de Figma y preferencias gráficas

Implementación nativa en Godot 4.7.2 del diseño
[UI RAICING DARK LAPAZ](https://www.figma.com/design/J49HkD9RLXtIv2sJmowxIu/UI-RAICING-DARK-LAPAZ?node-id=16-2).
Referencias: menú `16:2`, créditos `30:2` y opciones `32:8`, todas de 1280 × 720.
Se consultaron contexto de diseño y renders de los tres frames. No se utiliza
una captura completa como interfaz: cada botón y control es interactivo.

## Componentes reutilizables

`scenes/ui/NeonButton.tscn` y `scripts/ui/NeonButton.gd` constituyen el botón
reutilizable. Es un `Button` nativo: conserva `pressed`, `toggled`, `disabled`,
`button_group`, atajos, teclado, ratón y mando. El componente no conoce GameFlow
ni decide qué acción se ejecuta. Puede usarse fuera del menú sin otro gestor.

```gdscript
var button = preload("res://scenes/ui/NeonButton.tscn").instantiate()
button.text = "CONTINUAR"
button.compact = false # 68 px; true utiliza 48 px y texto de 17 px
button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
button.pressed.connect(start_activity)
container.add_child(button)
```

El ancho es libre: el subrayado se adapta al espacio disponible. El texto largo
usa elipsis. `tab_style` configura el remate de las pestañas. La base es cian puro:
el subrayado y remate normales se dibujan sin el magenta del recurso original.
El rosa aparece solo al pasar el cursor o mantener pulsado el botón; seleccionar
una pestaña o recibir foco automáticamente no lo deja rosa. Para navegar con
teclado/mando se muestra una marca blanca de foco. Ningún estado del botón añade
un fondo oscuro o de selección. Los controles deshabilitados se atenúan.
El área interactiva comprende todo el rectángulo, no solo el texto.
Arial normal y negrita inclinada se resuelven mediante `SystemFont`; se mantienen
dos recursos compartidos en caché. Hay fuentes de respaldo para otros sistemas.
No se copiaron archivos de fuentes de Windows al proyecto.

`MenuPresentation.gd` controla composición, fondo, logo, marco, pestañas y
disposición. `MenuBackdrop.gd` dibuja el recorte sombreado del diseño. GameShell
conserva la navegación, IDs de botones, selección de vehículos y opciones
existentes. Las otras vistas del shell adoptan el mismo estilo y conservan
scroll para el contenido largo. La pausa dentro del mundo comparte ahora fondo, colores y botones mediante
`PauseSkin.gd`; conserva el mapa y sus acciones de conducción.

La composición conserva 16:9 y se centra dentro del área disponible. En otras
relaciones de aspecto se usan bandas oscuras, evitando recortar botones,
deformar el fondo o mostrar bordes y recortes fuera del frame. El proyecto
mantiene su configuración de escalado general; no se cambia la cámara del juego.

## Recursos

- Fondo original: `assets/ui/menu/backgorunds/Fondo main menu.png`. Se conserva
  el nombre de carpeta aportado por el usuario.
- Logo original: `assets/ui/menu/logos/TITULO.svg`, sin modificaciones.
- `TITULO.png`: copia transparente a 1200 × 400, renderizada desde el SVG con
  Chromium. El importador SVG de Godot representa de forma distinta los filtros
  de sombra interior del original y difumina las letras. Esta copia preserva
  la apariencia del recurso sin cambiar sus trazados. Se muestra en su slot
  lógico de 600 × 200 (300 × 100 en créditos).
- Barras, subrayados, remates y marco: SVG originales descargados de los assets
  que devuelve Figma, en `assets/ui/menu/components/`. Se conservan sus dimensiones
  raíz y se adaptan al rectángulo de cada control. No hay URLs temporales en el juego.

Para regenerar la copia del logo en Windows: ejecutar
`tools/rasterize_menu_logo.ps1`. Edge solo se necesita para regenerarla, no para
ejecutar ni exportar el juego. El perfil de renderizado se guarda en `.local/`.

Créditos configurables en `config/game_flow.json`: se incorporaron los tres
nombres y roles proporcionados en el diseño, respetando su escritura. La pantalla
mantiene un enlace a todas las fuentes, atribuciones y licencias del proyecto.
El retorno al menú funciona con el botón Regresar o Esc/B del mando.

## Audio del menú y botones

`MenuAudio.gd`, propiedad del GameFlow existente, conserva los reproductores
durante los cambios de pantalla. No se crea otro Autoload. Los botones Neon se
registran mediante el grupo `ui_feedback`; el shell registra también los controles
nativos (casillas, desplegables y enlaces), sin duplicar conexiones.

- `assets/audio/Button-Notification.wav`: sonido al pulsar un botón o elegir
  una entrada de un desplegable. Se conserva la cola original de 2.85 segundos
  aunque desaparezca la pantalla. Cuatro reproductores permiten solapamientos
  acotados; nivel individual -12 dB, bus **Effects**.
- `assets/audio/Main menu.mp3`: música en bucle compartida por **Principal,
  Jugar, selección de vehículo, Cómo jugar, Créditos y Opciones**. Se detiene
  con fundido al pasar a carga, conducción o carreras.
  Requiere que exista un shell visible, evitando que suene al abrir directamente
  una escena de desarrollo. Nivel base -8 dB, bus **Music**.
- Al entrar al conjunto de menús, el volumen sube desde silencio en **1.5 s**.
  Navegar entre sus pantallas no reinicia la canción ni el fundido en curso.
  Al abandonarlos baja en **0.45 s** antes de detenerse. El fundido interpola
  ganancia lineal suavemente, no modifica el volumen del bus del usuario.
- Volver rápidamente durante un fundido retoma la ganancia actual sin reiniciar
  ni apilar la canción. Salir y cerrar la ventana completan el fundido y liberan
  las voces del clic antes de cerrar. Se respetan General, Música y Efectos.

Los audios originales aportados por el usuario permanecen sin edición. La
duración completa del clic se conserva; no se añade sonido por pasar el cursor.
La validación inicial de `tests/godot_menu_audio.gd` aprobó **20/20** comprobaciones con renderizado:
base/hover/pulsación/selección, transparencia, una reproducción por pulsación,
continuidad, bucle, navegación rápida, ganancias y cierre limpio. Evidencia en
`.local/artifacts/menu_audio_validation.json` y `evidence/menu_feedback_*.png`.
La ampliación de música a los submenús se integró sin ejecutar pruebas, por
petición del usuario; ese informe corresponde al alcance anterior.

```powershell
godot --path . --script res://tests/godot_menu_audio.gd -- --capture-menu-audio
```

La actualización de [agua, pausa y FPS](CARRERAS_AGUA_PAUSA_FPS.md) añade
límites de 30/60/90 FPS y reducción de oleaje/partículas a las opciones gráficas.

## Gráficos: controles reales para el jugador

Opciones se divide en **Sonido**, **Gráficos** y **Pantalla**. Sonido conserva
los cuatro buses reales. Pantalla conserva modo de ventana y resoluciones.

Gráficos reutiliza los controladores de las herramientas SF, mediante
`GraphicsPreferences.gd`, sin instanciar el mundo dentro del menú:

| Ajuste | Efecto real |
|---|---|
| Reflejos y referencias de velocidad | Modos original/parcial/completo de `SpeedVisualFeedback` |
| Cantidad de humo y huellas | Cambia emisión y presupuestos máximos de SF.4 |
| Nubes neón | `NeonClouds.set_enabled`, incluyendo visibilidad del MultiMesh |
| Humo de derrape | Emisión y limpieza del lote SF.4 |
| Huellas de neumáticos | Registro, visualización y limpieza de las marcas |
| Carrocería y estelas BURST | Overlay y estelas SF.4; al apagarlo tampoco se activa el fallback antiguo de llamas |

Presupuestos bajo/normal/alto: humo **32/96/128** partículas máximas, emisión
**12/26/40** y huellas máximas **128/512/1024**. Son límites de presentación;
no cambian las condiciones de derrape, TURBO, BURST ni las estadísticas.
La cámara dinámica se mantiene independiente de los efectos de carrocería.
Tampoco se cambia el terreno, la geometría vial ni las colisiones de edificios.
El ajuste de reflejos no elimina toda la decoración estática de la ciudad.

`GameFlow` sigue siendo el propietario de preferencias y navegación. Guarda
la sección `graphics` en su `user://game_settings.cfg`. Cambiar volumen o pantalla
conserva esa sección. Los valores inválidos se rechazan o se sustituyen por
predeterminados al cargar. Los cambios se aplican al entrar al mundo y cuando
termina de prepararse NightStyle; también pueden aplicarse a un mundo activo
mediante la misma API. **Restaurar gráficos** devuelve los valores normales.

Sin preferencias gráficas guardadas se respetan las pruebas de desarrollo
existentes; el formulario toma sus valores efectivos iniciales. Después de usar
Gráficos, las preferencias del jugador tienen prioridad para este subconjunto.
No se sobrescriben los archivos de prueba `sf3_environment.cfg` o
`sf4_vehicle_vfx.cfg`. Los controles del desarrollador siguen disponibles para
los demás parámetros y para hacer ajustes temporales dentro de la sesión.

Reducir estos efectos puede ahorrar trabajo gráfico, pero no se promete una
tasa de FPS determinada ni se asume el rendimiento de otras computadoras.

## Validación

- Importación y análisis de Godot sin errores.
- Regresión completa D.1: **207/207**, con navegación, teclado/mando, audio,
  cambios de pantalla y conducción con los tres vehículos hasta volver al menú.
- D.1 con renderizado de interfaz: **69/69**.
- Diseño y gráficos: **44/44**, con capturas a 1280 × 720, 1600 × 900,
  1920 × 1080, 1600 × 720 y 960 × 720. Se prueban los botones visibles,
  guardado, tipos inválidos y aplicación a los controladores reales del mundo.
- Se comparan hashes de ArcadeCar, DrivingAbilities, perfil COMET y mapa al
  principio y al final de esa prueba. No cambian.
- Persistencia de gráficos en un segundo proceso de Godot: **5/5**, incluyendo
  la verificación del archivo y de los hashes protegidos.
- Una prueba histórica adicional `godot_sf4.gd` pasa sus comprobaciones
  funcionales, pero falla un guard de hash completo de `ArcadeCar.gd` contra
  `tests/fixtures/baselines/sf4_baseline.json`. Esa referencia es anterior al
  adaptador del COMET: el archivo actual coincide con el commit V.2 `607a02f`
  y no fue modificado en esta entrega. Se conserva ese fallo documentado,
  sin actualizar silenciosamente el baseline histórico.

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/godot_phase_d1.gd -- --passport-test
godot --path . --script res://tests/godot_phase_d1.gd -- --ui-only --capture-d1
godot --path . --script res://tests/godot_menu_design.gd -- --capture-menu --passport-test
godot --headless --path . --script res://tests/godot_menu_design.gd -- --verify-graphics
```

La última orden debe ejecutarse después de la prueba de diseño: comprueba
las preferencias guardadas en un proceso nuevo. Esa suite usa exclusivamente
`user://tests/menu/settings.cfg`, y `--passport-test` aísla el pasaporte.
Logs, JSON y capturas en `.local/artifacts/menu_*` y
`.local/artifacts/evidence/menu_*`; no se incluyen en Git.
