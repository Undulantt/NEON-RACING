# Carreras publicadas, costa, pausa y límite de FPS

## Carreras del autor

El catálogo del menú y las entradas del mundo libre comparten estos recorridos:

| ID editable | Nombre visible | Formato guardado | Distancia | Controles |
|---|---|---|---:|---:|
| `circuito_forjadores` | Circuito Forjadores | Sprint sin vueltas | 6,520.30 m | 280 |
| `arracon_malecon` | Arracón Malecón | Sprint sin vueltas | 3,086.80 m | 151 |
| `centro_circuit_d3` | Centro LP · Copa neón | Circuito, 2 vueltas | 1,252.19 m totales | 39 por vuelta |

Los dos primeros proceden de los archivos publicados por el usuario en
`data/races/Circuito Forjadores.json` y `data/races/Arracon Malecon.json`.
Los originales se trasladan, sin modificar sus bytes, a
`data/reference/race_drafts/`. Las versiones del juego tienen nombres de archivo
coincidentes con sus IDs y registran procedencia y SHA-256 en `authoring_source`.
El segundo archivo se llamaba internamente «Recta Malecon» y se presenta con
el nombre solicitado. Se mantienen puntos, referencias OSM, controles,
separación, dirección, salida, meta, tipo y vueltas. El nombre «Circuito
Forjadores» no se interpreta como autorización para cerrar su ruta o añadir
vueltas: ambos archivos del autor están configurados como sprints.

Para modificar las versiones integradas en el editor, cargar los IDs de la
tabla. Guardar local crea una versión de prueba; publicar actualiza el contenido
del proyecto. Los borradores con IDs `carrera_...` siguen independientes.

`RaceActivity.entrances` carga las carreras del catálogo y valida cada una con
`RaceStore` y la red actual. Hay un cilindro rosa, nombre e interacción E/mando B
por recorrido; se elige el más próximo cuando el coche está detenido. Los
marcadores aparecen en minimapa y mapa de pausa. El desplegable de la pausa
permite fijar como destino cualquiera de sus salidas. Todos se ocultan durante
una carrera y vuelven al regresar al mundo libre. Se conserva el vehículo y el
origen de la actividad. Continúa vigente la parrilla 2 × 3 con jugador sexto.

## Agua y barrera

`CoastWater.gd` utiliza exactamente las 346 caras del agua existente de
`data/processed/relief/world/water.json`. El shader `coast_water.gdshader`
combina dos ondas, variación de normales y brillos de cresta; el desplazamiento
visual vertical máximo es aproximadamente 12 cm. Es una animación cosmética,
sin simulación hidrodinámica o nuevas elevaciones cartográficas. No usa
reflejos de pantalla, mapas de ruido grandes ni un mallado nuevo del océano.

Un emisor de 48 partículas reutiliza puntos comprobados dentro del agua, cerca
del jugador. Actualiza posiciones al desplazarse al menos 24 m y como máximo
cada 0.75 s; lejos de la costa no emite. Sus puntos no invaden calles o arena.

Las aristas no compartidas de los triángulos proporcionan 348 segmentos de
límite, incluidos los bordes del área cartografiada. Cada uno tiene una pared
de seguridad delgada en la capa de colisión 8, desplazada hacia el agua. Se
extiende de -8 a 512 m para impedir también atravesarla desde un salto. Dos
rieles de neón bajos hacen visible la delimitación; no se dibuja un muro alto.
La barrera permanece activa al reducir los efectos gráficos.

La comprobación geométrica de los recorridos del autor detectó **0 m dentro
del agua**. Arracón Malecón pasa a un mínimo de unos 15.98 m del contorno y
Forjadores a unos 2,639 m. No se modifica la costa, el terreno ni el asfalto.

## Pausa

`PauseSkin.gd` comparte imagen de fondo, Arial, colores cian y magenta y
`NeonButton.gd` con el menú principal. El magenta se reserva al estado de
interacción de los botones. La pausa de carrera conserva continuar,
recuperación de checkpoint, reinicio y abandono. Se presenta en una capa que
cubre el HUD de carrera.

La pausa libre conserva mapa, GPS, Pasaporte y recuperación. Incorpora el
selector de destino de carrera, borde cian y todos los botones visibles a
1280 × 720. El lienzo se adapta a la ventana; el mapa sigue admitiendo zoom y
arrastre. El catálogo se obtiene al abrir la pausa, después de que el mundo
termine de preparar sus sistemas. Pausar y continuar no sustituye el mundo ni
reinicia música o conducción.

## Gráficos y FPS

Opciones → Gráficos incluye **Sin límite / 30 / 60 / 90 FPS**. `fps_limit` se
guarda en las preferencias existentes y se aplica con `Engine.max_fps`, tanto
en menús como en conducción. No se modifica la frecuencia física del motor.
«Sin límite» conserva el comportamiento previo para quien no elija un límite.
La opción representa un máximo: el rendimiento del equipo y VSync pueden
mantener la frecuencia real por debajo de él.

«Oleaje y partículas del agua» permite sustituir el shader por el material
plano y ocultar partículas. La superficie y barrera siguen existiendo. Ambos
ajustes utilizan `GraphicsPreferences` y el guardado central de `GameFlow`;
no hay un segundo fichero de configuración.

## Validación

```powershell
godot --headless --path . --editor --import --quit
godot --headless --fixed-fps 60 --path . --script res://tests/godot_coast_release.gd -- --passport-test
godot --fixed-fps 60 --path . --script res://tests/godot_coast_release.gd -- --passport-test --capture-coast
godot --headless --fixed-fps 60 --path . --script res://tests/godot_authored_race_drive.gd -- --passport-test --ai-seed=730 --race-id=circuito_forjadores
godot --headless --fixed-fps 60 --path . --script res://tests/godot_authored_race_drive.gd -- --passport-test --ai-seed=730 --race-id=arracon_malecon
godot --headless --fixed-fps 60 --path . --script res://tests/godot_menu_design.gd -- --passport-test
```

Godot 4.7.2 Compatibility: integración renderizada **43/43** comprobaciones y
regresión de menú **24/24**. Se comprueban selección, ambas parrillas, formatos
originales, entrada desde modo libre, regreso con el mismo vehículo, marcador
más cercano, mapa y GPS, botones compartidos, guardado de los tres límites de
FPS, emisión dentro del agua, reducción de efectos y colisión de una forma
del tamaño del coche contra la costa. Los hashes del controlador, habilidades,
mapa, archivo de agua y circuito anterior no cambian durante las pruebas.

Las dos carreras completas se simularon con el coche físico de prueba y los
cinco rivales de producción: **6/6 finalistas en cada una, sin teletransportes**.
Forjadores finaliza entre 242.59 y 257.80 s; Arracón Malecón entre 112.58 y
133.01 s. Son tiempos con piloto automático de prueba y semilla fija, no un
ajuste definitivo de dificultad ni una medición de FPS del hardware.

Informes y capturas en `.local/artifacts/`: `coast_release_validation.json`,
`authored_drive_circuito_forjadores.json`, `authored_drive_arracon_malecon.json`,
`menu_design_validation.json` y `evidence/coast_release_*.png`. Las preferencias
de estas pruebas se aíslan del guardado de jugador.
