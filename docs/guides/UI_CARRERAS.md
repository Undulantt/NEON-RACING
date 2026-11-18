# HUD de carreras — Figma

Implementación del frame [UI DE CARRERAS, nodo 39:2](https://www.figma.com/design/J49HkD9RLXtIv2sJmowxIu/UI-RAICING-DARK-LAPAZ?node-id=39-2),
con contexto de diseño y render de referencia consultados. La captura de ciudad
del frame es referencia del mundo y del HUD existente; el juego sigue mostrando
la escena 3D en tiempo real. No se coloca esa captura encima de la carrera.

## Presentación

En el espacio lógico de 1280 × 720 del diseño:

| Indicador | Posición | Dato |
|---|---|---|
| Tiempo | X 1034, Y 20 | `RaceSession.elapsed`, formato minutos.segundos.centésimas |
| Vuelta | X 1090, Y 73 | `current_lap()` / `total_laps`; sprint muestra «Sin vueltas» |
| Posición | X 1090, Y 112 | `RaceCompetition.player_place()` / participantes reales |

Se reutiliza Arial negrita inclinada de 24 px, color `#f8f7fb`, del proveedor
de fuentes de la interfaz. Los dos acentos de tiempo son SVG originales del
frame: `assets/ui/race/time_underline.svg` (357 × 4) y `time_terminal.svg`
(36 × 11). Sus dimensiones raíz se conservan. La línea llega al borde derecho
y se recorta con el viewport tal como en Figma.

El bloque se ancla al borde derecho con sus separaciones de referencia. Así
acompaña la expansión del viewport en ultrapanorámico y el escalado general del
proyecto en 1080p/4:3. No crea fondos opacos ni captura entrada del coche.

El bloque anterior de texto con clasificación, checkpoint y distancia restante
deja de generarse durante la conducción de carrera. Se conservan los mensajes
de cuenta atrás y recuperación, la clasificación de resultados y su retorno.
Minimapa, velocímetro, turbo, derrape, BURST y las herramientas de desarrollo
existentes mantienen su presentación y sus datos. El HUD nuevo se oculta en
pausa, resultados y modo libre.

Los rótulos 3D sobre los rivales pertenecen al sistema anterior y permanecen
activos; pueden coincidir visualmente con la esquina del HUD según la cámara.
No se han cambiado sus posiciones o visibilidad en esta entrega.

## Arquitectura

- `scripts/ui/RaceHUD.gd`: lee la sesión y la competición, formatea los datos y
  compone los cinco elementos del diseño (tres textos y dos vectores). No avanza
  el reloj, concede vueltas, calcula progreso ni controla la conducción.
- `scripts/racing/RaceActivity.gd`: crea el HUD en su CanvasLayer existente y
  conserva únicamente los mensajes transitorios del antiguo label. El orden
  de checkpoints, recuperación y resultados no cambia.
- `tests/godot_race_hud.gd`: comprobaciones de integración y capturas. Las
  simulaciones de vuelta posterior y sprint son fixtures del test, no datos
  ficticios introducidos en el juego.

La posición mostrada utiliza la clasificación oficial ya implementada. Si no
hay una competición preparada se muestra un guion, sin inventar participantes.
Durante la cuenta atrás, el tiempo oficial permanece en cero; al pausar se
mantiene congelado. Los recursos se cargan localmente, sin URLs temporales ni
dependencias de Figma en ejecución.

## Validación

Godot 4.7.2, renderizador Compatibility:

- **29/29** comprobaciones del HUD: formato de reloj, lectura oficial de tiempo,
  vueltas y posición, eliminación del bloque anterior, conservación de
  instrumentos, pausa, recuperación, sprint, modo libre y selección del coche.
- Capturas y geometría revisadas en 1280 × 720, 1920 × 1080, 1600 × 720 y
  960 × 720. El anclaje mantiene los textos dentro del viewport.
- Hashes de ArcadeCar, RaceSession, RaceCompetition, perfil COMET y mapa
  idénticos antes y después de la prueba. No se reconstruye el mapa.
- Regresión existente de navegación y recuperación: **48/48**, incluyendo
  recuperación de tres segundos y rutas/checkpoints del mapa actual.

```powershell
godot --headless --path . --editor --import --quit
godot --path . --script res://tests/godot_race_hud.gd -- --capture-race-hud --passport-test
godot --headless --path . --script res://tests/godot_race_navigation.gd -- --passport-test
```

La prueba usa `user://tests/race_hud/settings.cfg`; `--passport-test` aísla los
descubrimientos del jugador. Evidencia local: `.local/artifacts/race_hud_validation.json`,
`race_hud_render.log`, `race_hud_navigation.log` y `evidence/race_hud_*.png`.
Los logs y las capturas permanecen fuera de Git según la política del proyecto.
