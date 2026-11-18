# Pasaporte La Paz — D.4

Esta guía conserva el alcance inicial de tres lugares. La ampliación actual,
sus once interacciones y los modelos geográficos se describen en
[Pasaporte y modelos 3D](PASAPORTE_MODELOS_3D.md).

Prototipo exclusivo del modo libre, con tres lugares reales y un editor manual
para desarrolladores. No añade recompensas, misiones ni modificaciones al coche.

## Uso del jugador

1. Entra a **Jugar → Modo libre** con cualquiera de los tres vehículos.
2. Pulsa **P** o abre **Esc → Pasaporte La Paz**.
3. Selecciona un lugar y pulsa **Marcar aproximación en el GPS**. Cierra el
   pasaporte con P/Esc; si entraste desde el mapa de pausa, vuelve al mapa pausado.
4. Sigue el GPS hasta el marcador turquesa sobre la calle. El minimapa muestra
   los puntos cercanos y el mapa de pausa permite ver los tres nombres.
5. Reduce a **3 m/s o menos (10.8 km/h)** dentro de un radio de **9 m**, con
   todo el vehículo sobre asfalto y apoyado en el suelo. Pulsa **E** cuando se
   muestre la indicación de registrar. La proximidad por sí sola no descubre.
6. Aparece la notificación y se desbloquea la ficha. P permite consultar
   descripción y fuentes. Los enlaces solo abren el navegador al pulsarlos.

El progreso pasa de 0/3 a 3/3. Repetir la interacción no cambia el registro.
Sal al menú y vuelve al modo libre, o reinicia el juego: deben conservarse los
lugares. No hay que subir a banquetas ni entrar a los edificios.

## Editor manual — Ctrl+Alt+I

Disponible al ejecutar el proyecto con Godot en desarrollo. También se abre
desde el botón **Editor de POI** del pasaporte. Pausa la simulación y conserva
el estado de pausa anterior al cerrar. No usa F8 ni comparte Ctrl+Alt+P con SF.

1. Selecciona uno de los registros o pulsa **Nuevo borrador**. El ID se genera
   una sola vez y es de solo lectura: el progreso depende de ese ID.
2. Completa nombre oficial, categoría, descripción propia y fuente HTTPS.
3. Escribe coordenadas verificadas o activa **Clic coloca lugar** y elige su
   posición en el mapa. El clic convierte las coordenadas métricas a latitud/
   longitud, pero **no demuestra que el lugar exista**. Contrasta su ubicación,
   indica el identificador OSM/ficha oficial y marca la casilla de verificación.
   Cambiar las coordenadas desmarca esa casilla. Rosa representa el lugar real.
4. Desactiva **Clic coloca lugar** y haz clic cerca de una calle para elegir su
   aproximación; también puedes usar **Zona en mi coche**. Turquesa representa
   la interacción. Arrastra con botón central/derecho y usa la rueda para zoom.
5. Usa **GPS a la zona**, cierra el editor y conduce hasta allí. Vuelve a abrirlo
   a menos de 80 m y pulsa **Probar zona**. Comprueba el espacio del coche y el
   apoyo en asfalto usando las colisiones cargadas; no mueve el automóvil.
6. Ajusta radio (4–15 m) y velocidad permitida (0–3 m/s). Una zona activa debe
   estar en la red vial transitable y a menos de 180 m del lugar real.
7. **Guardar borrador** conserva el trabajo incompleto y **Cargar borrador** lo
   recupera. **Aplicar local** valida y activa el catálogo para esta instalación.
   **Publicar proyecto** escribe el catálogo compartido del proyecto; solo está
   habilitado en desarrollo. Para compartirlo con Git usa ese último botón.

Durante D.4 se admiten **hasta tres POI activos**. Puedes crear más borradores
inactivos, pero para activar uno distinto debes desactivar otro. El editor no
inventa automáticamente lugares ni proporciona descubrimientos de prueba al
jugador. Cerrar sin guardar descarta las ediciones. Cambiar un ID mediante edición
externa equivale a crear otro lugar y no traslada el descubrimiento anterior.

## Datos y fuentes

| ID | Lugar | Latitud, longitud WGS84 | Aproximación métrica X, Z | Calle |
|---|---|---|---|---|
| poi_001 | Kiosco del Malecón | 24.163772, -110.3165411 | 311.196, -512.400 | Paseo Álvaro Obregón |
| poi_002 | Catedral de Nuestra Señora de La Paz | 24.1615924272, -110.3128939831 | 634.923, -315.299 | Revolución de 1910 |
| poi_003 | Teatro de la Ciudad | 24.147021132883, -110.31775828735 | 162.543, 1341.414 | Antonio Navarro |

Las coordenadas y las zonas de interacción son datos distintos. Distancia entre
ellos: 21.3, 44.5 y 17.0 m respectivamente. Los tres están dentro del mapa actual.
Origen del mapa: latitud 24.159, longitud -110.3195. Se reutiliza la proyección
local del proyecto: R=6,371,000 m, X hacia el este y Z hacia el sur.

- Kiosco: nodo histórico **9284265569** del snapshot OSM existente
  `data/raw/osm_map_c6_boundary_expansion.osm`, contrastado con la ubicación
  municipal en Obregón y 16 de Septiembre. Descripción basada en la
  [ficha de Turismo La Paz](https://turismo.lapaz.gob.mx/atractivos/kiosco-del-malecon-18).
- Catedral: centro del polígono OSM **155831066**. Identidad y ubicación en la
  [ficha municipal](https://turismo.lapaz.gob.mx/atractivos/catedral-de-nuestra-senora-de-la-paz).
  La fecha de colocación de la primera piedra también está documentada por
  [Sitios y Monumentos, Secretaría de Cultura](https://sitiosymonumentos.cultura.gob.mx/iii-estudios-monograficos/nuestra-senora-de-la-paz-catedral/).
- Teatro: coordenadas obtenidas del enlace cartográfico de la
  [ficha oficial SIC 12](https://sic.cultura.gob.mx/ficha.php?table=teatro&table_id=12),
  correspondiente a la Unidad Cultural Profesor Jesús Castro Agúndez. Se toma
  la fecha de inauguración del cuerpo de la ficha: 26 de enero de 1986. Su punto
  representativo difiere unos 114 m del centro del edificio OSM **155831068**;
  se conserva el punto publicado por SIC y una aproximación por Navarro.
  **No es el Teatro Juárez.**

Las fichas son paráfrasis breves. No se incorporaron fotografías ni se alteró
la geometría del mapa. Un marcador señala una interacción, no un modelo nuevo
del monumento. Las coordenadas no implican precisión topográfica de levantamiento.

## Arquitectura y archivos

Se reutilizan `GameFlow` para el estado libre/carrera, `RoadGraph` para las
aproximaciones, `FreeDriveNavigation` para GPS y `FreeDrivePause` para el acceso.
No se crea otro Autoload ni se duplica el sistema de navegación.

| Archivo | Responsabilidad |
|---|---|
| `data/passport/pois.json` | Tres lugares, coordenadas, textos, fuentes y zonas viales |
| `scripts/passport/PassportStore.gd` | Validación, proyección, escritura atómica y progreso por ID |
| `scripts/passport/PassportController.gd` | Interacción explícita, marcadores sin colisión, estado y apertura de pantallas |
| `scripts/passport/PassportBook.gd` | Listado, fichas desbloqueadas, contador y destinos GPS |
| `scripts/passport/PassportEditor.gd` | Autoría manual, borradores, validación y publicación |
| `scripts/passport/PassportEditorMap.gd` | Extensión del mapa de pausa para seleccionar coordenadas/zonas |
| `tools/build_passport_pois.py` | Construye el catálogo inicial desde fuentes existentes, sin regenerar el mundo |
| `tests/godot_phase_d4.gd` | Pruebas funcionales, aislamiento de guardado, capturas y medición |

Integración: cuatro líneas en `scripts/world/World.gd`, botón en
`scripts/ui/FreeDrivePause.gd` y dibujo de POI en `scripts/ui/PauseRoadMap.gd` y
`scripts/ui/DrivingMinimap.gd`. Los `.uid` correspondientes también se conservan.
La documentación se enlaza desde `docs/README.md`; las fuentes se atribuyen en
`CREDITS_AND_LICENSES.md`. Los cambios anteriores del proyecto se conservaron.

Persistencia separada:

- Catálogo compartido: `res://data/passport/pois.json`.
- Catálogo local con prioridad: `user://passport/catalog.json`.
- Trabajo del editor: `user://passport/draft.json`.
- Descubrimientos: `user://passport/progress.json`.

Godot resuelve `user://` en su carpeta de datos de usuario del proyecto. El
guardado usa temporal y respaldo `.bak`; el progreso intenta recuperar ese
respaldo si el archivo principal está dañado. Los IDs históricos desconocidos
se conservan aunque no cuenten en el catálogo activo. Si un catálogo local no
es compatible se muestra un aviso y se utiliza el compartido.

La huella de cada zona inicial se verifica offline contra el asfalto actual
(11 × 5.2 m) y en ejecución con las consultas existentes del automóvil. El editor
valida colisiones próximas sin instanciar coches auxiliares. Un cambio del mapa
invalida la versión del catálogo y exige revisar las aproximaciones. La comprobación
de fuentes del autor es declarativa; el editor no las verifica en Internet.

## Validación de la entrega

Godot 4.7.2 estable. Importación y análisis sin errores. Prueba D.4 con imagen:
**54 comprobaciones aprobadas**, incluyendo proyección, tres lugares accesibles
con VECTOR/COMET/APEX, E explícita, bloqueo por velocidad, deduplicación,
contador, pausa, editor, borradores, rechazo de IDs repetidos/cuarto activo,
recuperación de respaldo y persistencia tras recrear el mundo. Se verificó
además la persistencia en un segundo proceso de Godot: **1/1**.

Regresión existente `godot_race_navigation.gd`: **48/48**, incluyendo rutas,
checkpoints y recuperación de tres segundos. Se compararon SHA-256 de los
controladores de conducción, habilidades, perfiles, GameFlow, carrera, rival y
generación/streaming registrados al inicio: sin cambios por esta entrega.
La prueba visual terminó sin errores ni advertencias de ejecución.

En la RTX 4060 Ti, renderizador Compatibility, 1280 × 720 y coche detenido
cerca del teatro, el controlador tardó aproximadamente **0.014 ms por llamada**
en 5,000 muestras. Medición breve de 120 frames por estado: desactivado
mediana/p95 **8.64/15.68 ms**, activado **7.69/15.34 ms**. Esta comparación desactiva
el controlador y los marcadores, manteniendo el resto de la escena. La variación no demuestra
una mejora; no se aprecia una regresión en esta muestra. Hay tres mallas pequeñas
sin sombras ni cuerpos de colisión. La altura del marcador cercano se actualiza
cada 0.25 s para acompañar los sectores que carga el mundo.

Estas cifras no garantizan 60 FPS en otros equipos ni sustituyen una prueba
prolongada conduciendo por toda la ciudad. La interfaz es preliminar; la revisión
visual cubre 1280 × 720. Las descripciones y ubicaciones requieren revisión del
autor cuando se añadan otros lugares. No se añadieron modelos arquitectónicos.

Comandos desde la raíz (sustituye `godot` por la ruta de tu ejecutable):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/godot_phase_d4.gd -- --passport-test
godot --headless --path . --script res://tests/godot_phase_d4.gd -- --passport-test --verify-progress
godot --path . --script res://tests/godot_phase_d4.gd -- --passport-test --capture
godot --headless --path . --script res://tests/godot_race_navigation.gd -- --passport-test
```

Las pruebas D.4 requieren `--passport-test` y usan únicamente
`user://tests/d4/`; no descubren lugares ni editan el catálogo real del jugador.
El generador inicial se ejecuta con `.venv-urban/Scripts/python.exe
tools/build_passport_pois.py`; reemplaza el catálogo compartido, por lo que no
debe usarse para conservar un catálogo ya editado manualmente.

Informes y evidencia local: `.local/artifacts/d4_render.json`,
`d4_validation.json`, `d4_restart.json`, `d4_source_integrity.json`,
`race_navigation_validation.json` y capturas `evidence/d4_*.png`. Se mantienen
fuera de Git según la política del proyecto.
