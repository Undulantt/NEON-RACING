# Fase E — señalización continua sobre el relieve

## Causa y corrección

La captura de Forjadores mostraba dos problemas del shader anterior: una selección limitada a 64 ejes por sector dejaba algunos tramos fuera, y la distancia al segmento más cercano generaba contornos alrededor de sus extremos. Además, la iluminación base del asfalto dependía de esa selección, produciendo cambios rectangulares entre sectores. La cola de decoración podía dejar temporalmente sectores sin señalización.

Se elimina ese algoritmo por píxel. Las marcas se construyen fuera del juego desde los ejes conectados de cada calle, con los anchos arcade existentes. Se unen antes de dividirlas en sectores y los guiones se distribuyen por longitud recorrida, no por la coordenada Z ni por el origen de cada sector. Las calzadas de un solo sentido usan separadores discontinuos; la doble línea central se reserva para vías de doble sentido con al menos dos carriles. No se unen calzadas paralelas que no estén conectadas.

Los cruces se despejan con una máscara local para evitar líneas cruzadas, puntas y falsos cierres. Las bandas resultantes se recortan contra cada triángulo de asfalto y se elevan 2,5 cm para evitar superposición. Se conserva el contorno neón ya corregido. El material del asfalto es compartido y continuo en coordenadas del mundo, sin buscar el eje más próximo.

Las marcas y el borde neón se guardan en un solo recurso por sector, con materiales separados. RoadChunkManager anticipa su lectura en segundo plano y los incorpora cuando carga la carretera; no espera a la decoración de edificios. Se verifican las fuentes de mapa, anchos y geometría elevada. El shader ya no recorre 64 segmentos por píxel.

## Alcance y límites

Se prepararon 574 sectores viales: 554 contienen pintura. Los otros no tienen bandas elegibles con estas reglas (por ejemplo, tramos de un solo carril o geometría residual). Se procesaron 1.842 cadenas conectadas, 338 de un solo sentido, 3.616 nodos de cruce y 22.668 trazos discontinuos. Los recursos combinados ocupan 68,42 MB, frente a 58,93 MB de los bordes anteriores.

La señalización es estilizada y usa los datos disponibles de carriles, incluyendo estimaciones. No representa un levantamiento oficial de pintura vial. Los cruces y algunas vías estrechas quedan deliberadamente sin marcas longitudinales; eso no indica que falte asfalto. La fase de los guiones puede cambiar donde cambian los atributos de la vía, pero no se reinicia por cruzar un sector.

No se modificaron posiciones, anchuras físicas, relieve, edificios ni colisiones.

## Verificación acotada

- Comprobación independiente de 884 límites compartidos con pintura: sin diferencias de longitud pintada, tolerancia 0,1 mm (`phase_e_marking_seams.json`).
- Capturas reales de Forjadores, incluido el tramo `443101250:0` a unos 26 m de elevación y atravesando límites de sector: [tramo largo](evidence/phase_e_forjadores_continuous.png), [intersección](evidence/phase_e_forjadores_markings.png).
- Mismo recorrido de 246,396 m con el controlador real, 1.500 cuadros, 1280×720, Compatibility, VSync desactivado, simulación fija de 60 Hz. Media 4,157 ms, p95 7,039 ms, p99 16,351 ms, máximo 25,392 ms, 12 cuadros por encima de 16,7 ms y ninguno por encima de 33,3 ms. La media es ligeramente mayor que la medición anterior (3,789 ms), pero el pico es menor (antes 43,744 ms). No se afirma que toda la ciudad mantenga siempre 60 FPS.
- Cero recortes de neón durante el recorrido; 54 recursos cargados. Colisiones de farolas, palmeras, árboles y F8 siguen verificadas. Informe `phase_e_stream_markings.json`.

## Regenerar

La preparación se realiza una vez, fuera de la conducción. No hace falta ejecutarla para jugar con los recursos incluidos.

```powershell
# Si cambió la geometría vial, preparar primero los bordes:
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/bake_night_roads.gd
# Unir y pintar las calles, después proyectarlas sobre el relieve:
.venv-urban/Scripts/python.exe tools/build_road_markings.py
& '..\..\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/bake_road_markings.gd
# Comprobación enfocada en el defecto de unión entre sectores:
.venv-urban/Scripts/python.exe tests/check_road_marking_seams.py
```

Los polígonos intermedios quedan en `.godot-local-profile/road_markings/`; el juego solo carga los recursos comprimidos de `data/processed/night_roads/`.
