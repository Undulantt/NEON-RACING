# Selector de vehículos con vista 3D

El selector compartido de modo libre y carrera presenta el vehículo a la
izquierda y sus ocho estadísticas a la derecha, siguiendo la referencia del
autor. Las barras blancas, bordes cian, tipografía y botones reutilizan la
identidad del menú actual. Los valores proceden de `VehicleProfiles`; no se
ajustan para que coincidan con los números del ejemplo.

## Uso

- Flechas inferiores: vehículo anterior/siguiente, con recorrido circular
  VECTOR → COMET → APEX.
- Arrastrar con botón izquierdo o derecho sobre el modelo: girar sobre su eje.
- Rueda dentro del visor: acercar o alejar.
- Sin interacción: rotación lenta, aproximadamente 8 grados por segundo.
  Después de soltar el ratón espera dos segundos antes de reanudarla.
- Continuar: conserva el vehículo y entra al modo libre o al selector de
  carreras. El modo carrera mantiene su control de dificultad.
- Regresar: vuelve a elegir modo sin perder la selección.

El neón superior es una geometría visible con un `SpotLight3D` real sobre el
automóvil. Una luz magenta lateral y una luz de relleno permiten leer sus
formas. No se activan sombras dinámicas ni postprocesado adicional.

## Implementación

- `VehicleSelection.gd`: disposición, flechas, nombre, dificultad, estadísticas
  y acciones de navegación.
- `VehicleStatBar.gd`: barras con terminación oblicua e índice numérico 1–10.
- `VehicleCycleButton.gd`: flechas nativas de Godot con foco de teclado/mando
  y estados cian/magenta.
- `CarShowroom.gd`: escenario privado en `SubViewport`, fondo transparente,
  cámara, peana, luces, rotación y zoom.
- `GameShell` conserva la selección central de `GameFlow` y los valores de
  los tres perfiles. `MenuPresentation` reserva el espacio del selector sin
  cambiar la composición del resto de pantallas.

La vista utiliza `CarVisual.build`, incluyendo los adaptadores y GLB que
ya utilizan los coches del juego. Solo instancia su presentación; no crea
controladores de conducción, colisiones del coche, habilidades o ciudad. Cada
modelo se centra y escala en la peana a partir de sus límites visuales, sin
modificar el archivo importado o su escala de conducción.

Los modelos se instancian una sola vez por apertura del selector y se reutilizan
al cambiar las flechas. Solo se muestra el seleccionado. El visor emplea su
propio `World3D`, MSAA 2× y resolución ligada al área de previsualización,
independiente del mapa. Se desactiva cuando se oculta y se libera al salir.
La rotación manual se cancela también al perder el foco de la ventana.

El encuadre predeterminado permite girar los tres coches completos. El zoom
de acercamiento permite inspeccionar detalles y puede recortar el modelo por
elección del usuario. La cámara de conducción y las físicas permanecen iguales.

## Validación

```powershell
godot --headless --path . --editor --import --quit
godot --fixed-fps 60 --path . --script res://tests/godot_vehicle_selector.gd -- --passport-test --capture-selector
godot --headless --fixed-fps 60 --path . --script res://tests/godot_phase_d1.gd -- --passport-test
godot --headless --fixed-fps 60 --path . --script res://tests/godot_menu_design.gd -- --passport-test
godot --headless --fixed-fps 60 --path . --script res://tests/godot_expert_menu.gd -- --passport-test
```

Godot 4.7.2 Compatibility: selector renderizado **59/59** comprobaciones;
navegación/conducción D.1 **210/210**. Pasan también las regresiones del menú
y de dificultad. Se verifican los modelos importados, las 24 estadísticas,
encuadre en 16 ángulos por coche, rotación automática, arrastre con eventos
reales de ratón, zoom, flechas circulares, reutilización de modelos, liberación
del visor y selección persistente. Se revisan capturas a 1280 × 720,
960 × 540 y 1920 × 1080.

Los hashes de `ArcadeCar`, habilidades, adaptador de modelos y tres perfiles
permanecen iguales. Las pruebas usan preferencias aisladas. Informes en
`.local/artifacts/vehicle_selector_*.log`, `vehicle_selector_validation.json`
y capturas en `evidence/vehicle_selector_*.png`. La prueba de simulación fija
verifica corrección; no constituye un benchmark de rendimiento del hardware.
