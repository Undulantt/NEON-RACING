> Revisión posterior: [señalización continua y carga junto con la carretera](PHASE_E_ROAD_MARKINGS.md). Los recursos actuales incluyen bordes y marcas; para regenerarlos hay que seguir ambos pasos de esa guía.

# Fase E — tirones, colisiones y arranque nocturno

## Diagnóstico y resultado

No había dos ciudades completas dibujándose: las mallas geográficas se reutilizaban y sus materiales se reemplazaban. Sí se generaban ventanas/detalles originales y luego decoración nocturna adicional, y el ambiente se preparaba inicialmente con ajustes diurnos. La escena principal ahora selecciona la apariencia nocturna antes de construir el mundo. UrbanChunkManager omite `category_facades` y `detail_windows` originales en ese modo; NightStyle es el único generador de esos detalles. Carreteras, edificios, cielo y luz direccional arrancan con materiales/ajustes nocturnos. Se conserva el modo diurno solo como opción explícita de diagnóstico, sin instanciar otro mundo simultáneo.

Se repitió el mismo recorrido de 246,396 m con el controlador real, simulación fija a 60 Hz, Compatibility, 1280×720, VSync desactivado y 1.500 cuadros medidos. Equipo: RTX 4060 Ti. Informes `phase_e_stream_before.json` y `phase_e_stream_after.json`.

| Medida | Antes | Después |
|---|---:|---:|
| Tiempo medio por cuadro | 5,987 ms | 3,789 ms |
| Percentil 95 | 10,422 ms | 6,633 ms |
| Percentil 99 | 76,201 ms | 22,243 ms |
| Pico máximo | 172,350 ms | 43,744 ms |
| Cuadros >33,3 ms | 20 | 1 |
| Cuadros >16,7 ms | 27 | 47 |

La mejora de los tirones grandes es clara en este recorrido, pero no equivale a 60 FPS perfectamente estables: queda un pico de carga y el trabajo distribuido aumentó los cuadros ligeramente por encima de 16,7 ms. No se afirma haber verificado toda la ciudad ni hardware diferente.

## Cambios de rendimiento

- Los bordes neón de los 574 sectores viales se preparan fuera del juego como ArrayMesh comprimidos: 58,93 MB en `data/processed/night_roads/`. Se cargan anticipadamente en segundo plano, con ocho solicitudes simultáneas y una caché acotada. La escena y el generador se verifican contra el manifiesto antes de utilizarlos; los modos sin caché válida conservan la generación incremental.
- En el recorrido final se cargaron 54 recursos preparados y hubo **cero recortes de neón durante la conducción**.
- Fachadas y candidatos de mobiliario reparten su construcción entre cuadros. La selección de fachada tiene un coste acotado incluso con huellas complejas.
- Las comprobaciones de edificios usan primero rectángulos de proximidad, conservan una caché de hasta 96 sectores y cargan los índices vecinos separadamente, en lugar de procesar varios en una sola comprobación.
- Las luces dinámicas de las farolas contribuían a los picos. Se sustituyen por hasta cuatro manchas suaves de iluminación en el shader del asfalto, manteniendo las luminarias visibles. Esta iluminación estilizada no ilumina físicamente fachadas o coches. Se conservan los faros reales del coche.
- La vegetación utiliza colores por cara y material sin iluminación dinámica, manteniendo la silueta facetada. F8 apaga también las manchas de luz.

Se conservaron informes intermedios para no ocultar resultados: generación incremental, caché síncrona, escena diurna y aislamiento sin farolas. Una ejecución intermedia reutilizó un perfil parcial y emitió avisos GL de caché; las mediciones finales usaron perfiles nuevos y terminaron sin errores de script/shader.

## Colisiones

Farolas, palmeras y árboles tienen cápsulas sencillas en postes y troncos; las palmeras usan varias secciones para aproximar la curvatura. Copas y hojas son visuales. Las formas se comparten en la ciudad y se agrupan en un cuerpo estático por sector, hijo directo del chunk urbano, para aprovechar sus reglas existentes de distancia, descarga y F8. También se añadieron cápsulas a los postes y palmeras del piloto antiguo.

Verificación final: rayos físicos y `CharacterBody3D.test_move` detectaron los tres tipos con el coche real; F8 desactivó las colisiones y manchas de luz. El recorrido mantuvo exactamente la misma distancia que antes. Los datos geográficos, el controlador y la configuración de conducción no se modificaron.

## Reproducir

F5 abre la escena principal directamente de noche.

```powershell
# Solo al modificar la geometría vial o el generador del neón:
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/bake_night_roads.gd
# Comparación corta de conducción y comprobación física:
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --path . --fixed-fps 60 --script tests/phase_e_stream_perf.gd
```

[Captura de la escena principal](evidence/phase_e_direct_night.png). La captura también verifica un solo WorldEnvironment y una sola luz direccional.
