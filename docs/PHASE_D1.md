# Fase D.1 — Navegación y flujo principal

Nota de versión: este documento conserva la entrega original de D.1. [D.2](PHASE_D2.md) sustituye la carrera pendiente, la carga síncrona y el retorno mediante reconstrucción del mundo por carreras jugables, carga por etapas y reutilización de escena. La suite de regresión de menús se mantiene; los contratos de carrera se verifican ahora en la suite D.2.

F5 inicia **Neon Racing LP** en el menú principal. La interfaz es temporal y funcional; no pretende fijar la dirección artística de la fase E. La escena nocturna existente sigue siendo `scenes/Main.tscn` y se puede abrir directamente con F6 para desarrollo.

## Flujos disponibles

- Menú → Jugar → Modo libre → Selección de vehículo → Malecón. Esc abre la pausa; «Volver al menú principal» descarga el mundo y vuelve al menú.
- Menú → Jugar → Modo carrera → la misma selección → **Modo carrera · pendiente de D.2**. Permite cambiar el vehículo o regresar al menú. No se simulan salidas, vueltas, tiempos ni clasificaciones.
- Cómo jugar documenta los controles y mecánicas implementados. Opciones cambia los buses de audio y la ventana reales. Créditos muestra la información configurable y las licencias existentes. Salir cierra la aplicación de escritorio; se oculta en web.
- Teclado: flechas, Enter y Esc. Mando: dirección o stick izquierdo, A para aceptar y B para volver. Se conserva el control habitual del coche.

## Inspección y arquitectura elegida

El proyecto ya tenía perfiles VECTOR, COMET y APEX, un controlador `ArcadeCar`, generación/streaming del mundo, HUD con pausa y mezcla F7. No tenía un controlador central de navegación. Se reutilizan todos esos componentes; no se crean coches ni mundos por modo.

Se añade un único Autoload, `scripts/navigation/GameFlow.gd`, que mantiene modo, vehículo, estado, escena actual, origen de actividad, destino de retorno y contexto de sesión. `scripts/ui/GameShell.gd` presenta esas decisiones en una sola escena `scenes/ui/GameShell.tscn`. Las pantallas emiten órdenes al Autoload y observan sus señales; no cargan mundos por su cuenta. El HUD delega el regreso al mismo controlador.

Los estados son `main_menu`, `play_menu`, `vehicle_select`, `how_to_play`, `options`, `credits`, `loading`, `free_drive`, `race_pending`, `race` y `results`. `race` queda reservado para un proveedor futuro. Las transiciones bloquean órdenes duplicadas y despausan el árbol antes de cambiar de escena. La referencia al mundo es débil para no retener nodos descargados. Las solicitudes diferidas de foco verifican que la vista siga existiendo. La decoración nocturna comprueba su pertenencia al árbol tras sus esperas de inicialización.

La carga inicial del mundo sigue siendo síncrona, como antes: se muestra primero «Cargando», pero la ventana puede detenerse mientras se construye el sector. No se añade un segundo sistema de carga o streaming en esta fase.

## Vehículos y aparición

La pantalla compartida lee `VehicleProfiles.load_profile()` y los tres JSON existentes en `config/vehicles/`. Presenta las ocho estadísticas calculadas actuales, con la misma escala 1–10 del sistema existente: velocidad, aceleración, manejo, frenado, derrape, turbo, impulso de derrape y BURST. La velocidad base y el objetivo de 0–100 se etiquetan como parámetros de configuración, no como mediciones de la interfaz. No se modificaron los balances.

Los tres perfiles siguen usando la carrocería compartida del prototipo; la pantalla lo indica expresamente. Al crear el mundo, se establece el perfil antes de añadir el coche al árbol y se entrega la configuración a los mismos sistemas de conducción. En una sesión iniciada desde el menú, la selección tiene prioridad sobre el argumento de desarrollo `--vehicle`; iniciar directamente la escena mantiene su comportamiento de desarrollo.

`config/game_flow.json` configura el título, escenas, perfil inicial, créditos y aparición libre. El punto del Malecón se copia del spawn existente y verificado de Paseo Álvaro Obregón en `la_paz_environment.json`: X/Z aproximadamente `(113.036, -250.829)` metros, dirección `(0.382538, -0.923940)`. El controlador existente calcula el apoyo vertical sobre la vía y el relieve. El entorno se ajusta solamente en memoria antes de cargar los sectores; no se reescribe la cartografía.

## Opciones, créditos y persistencia

Se guardan el último vehículo, volúmenes Master/Music/Engine/Effects, modo de ventana y tamaño de ventana en `user://game_settings.cfg`. Los controles actúan sobre `AudioServer` y `Window`, incluyendo silencio a volumen cero. F7 comparte la misma autoridad de volumen y actualiza sus deslizadores. Se importan las preferencias anteriores de `night_audio.cfg` cuando aún no existe un valor nuevo.

Hay ventana, ventana sin bordes y pantalla completa. Los tamaños 1280×720, 1600×900 y 1920×1080 se aplican a la ventana; el selector de tamaño se desactiva en pantalla completa. Los controles de pantalla se desactivan con el servidor headless. No se añaden ajustes gráficos sin efecto.

El cambio del nombre del proyecto conservaría datos en otra carpeta si se utilizara el comportamiento predeterminado de Godot. Se configura un directorio de usuario personalizado para mantener la ruta anterior de Windows: `AppData/Roaming/Godot/app_userdata/La Paz After Dark - Fase C.6`. La prueba comprueba esa ruta. No se borra ni migra la información del usuario.

Los colaboradores se editan en `credits.contributors` de `config/game_flow.json`, como objetos con `name` y `contribution`. La lista queda vacía hasta disponer de nombres autorizados. La pantalla incorpora `CREDITS_AND_LICENSES.md`; no se inventan contribuciones.

## Contratos preparados para las siguientes fases

| Entrada o dato | Contrato |
| --- | --- |
| `GameFlow.activity_context()` | Devuelve `mode`, `vehicle_id`, `activity_id`, `origin`, `return_destination` y `return_context`. |
| `race_requested(context)` | Notifica una solicitud. El futuro proveedor debe respetar la transición en curso. |
| `race_scene`, `default_race_id` en JSON | Vacíos hasta disponer de una carrera real. Al configurarse una escena se utiliza el estado `race`; esa escena consulta el contexto del Autoload. |
| `World.request_race(activity_id)` | Entrada para los futuros puntos interactivos; delega en `request_race_from_free_drive()`. No hay puntos nuevos colocados todavía. |
| `GameFlow.finish_activity(result)` | Recibe resultados externos no vacíos y abre la pantalla compartida. Puede presentar `summary`, `position` y `elapsed_seconds`; D.1 no produce esos datos. |
| `cancel_activity()` / `return_from_activity()` | Desde menú vuelve al menú; desde modo libre reconstruye el mundo con el mismo vehículo y contexto guardado. |

El retorno libre guarda una pose segura y la reserva de turbo. Recupera ese vehículo en esa ubicación con velocidad cero, evitando heredar aceleración o movimiento de la actividad. No preserva una simulación completa de tráfico, NPC, sesiones de carrera o progreso turístico: esos sistemas no se implementan aquí. El contrato de contexto evita que D.2/D.3 deban duplicar selección y navegación; D.4 podrá añadir sus propias actividades sin introducir interacciones turísticas prematuramente.

La pantalla de resultados sólo se alcanza hoy mediante la API de integración. La captura `d1_results_fixture.png` contiene un resultado inyectado por la prueba y lo identifica como tal: **no demuestra una carrera jugable**.

## Validación realizada

Godot **4.7.2.stable.official.ed1daf0bf**, física Jolt; validación con renderer OpenGL y NVIDIA RTX 4060 Ti además de ejecución headless.

| Validación | Resultado |
| --- | --- |
| Importación/editor headless | Sin errores de compilación/importación. |
| D.1 headless | **219 comprobaciones, 0 fallos**; `phase_d1_validation.json`. |
| D.1 con renderizado y capturas | **223 comprobaciones, 0 fallos**; `phase_d1_validation_render.json`. Incluye los cambios efectivos de ventana. |
| Regresión `godot_powertrain.gd` | Aprobada: perfiles, siete marchas y sincronización del motor/HUD. |
| Regresión `godot_burst.gd` | Aprobada: turbo, derrape y BURST de los tres perfiles. |
| Integridad de datos/controlador | Los diez SHA-256 de `d1_baseline.json` coinciden; informe `phase_d1_baseline_validation.json`. |

La prueba de D.1 recorre menús, retrocesos, comparación de 24 estadísticas, los tres vehículos en ambos modos, ajustes/persistencia, pausa, regreso al menú, cancelación y resultados de una actividad originada en modo libre. Comprueba posición, reserva de turbo, vehículo y ausencia de un mundo 3D retenido al volver al menú. Inyecta eventos nativos de teclado y mando en Godot; no sustituye una sesión manual prolongada con un mando físico.

Los tres perfiles arrancan en el Malecón, encuentran apoyo vial y avanzan con su configuración real: aproximadamente VECTOR 5.099, COMET 4.403 y APEX 5.533 m/s tras un segundo del ensayo controlado. Son verificaciones de funcionamiento, no nuevos objetivos de balance. Se revisaron visualmente las capturas; se corrigieron foco diferido en vistas reemplazadas, bindings de aceptación del mando y ancho de las etiquetas de la tabla y de los porcentajes.

Las pruebas de D.1 usan un archivo temporal de preferencias dentro de `tests/`, lo eliminan al terminar y restauran los valores originales en memoria. Las pruebas no sobrescriben las preferencias personales guardadas.

### Reproducir

Desde la raíz, sustituyendo `Godot` por la ruta del ejecutable:

```powershell
Godot --headless --path . --editor --quit
Godot --headless --path . --fixed-fps 60 --script tests/godot_phase_d1.gd
Godot --path . --fixed-fps 60 --script tests/godot_phase_d1.gd -- --capture-d1
Godot --headless --path . --fixed-fps 60 --script tests/godot_powertrain.gd
Godot --headless --path . --fixed-fps 60 --script tests/godot_burst.gd
```

Las capturas están en `docs/evidence/d1_*.png`: menú, ayuda, opciones, créditos, comparación de cada perfil, conducción libre de cada perfil, pantalla D.2 pendiente y resultado de fixture. No ejecutar dos pruebas D.1 simultáneas porque comparten el archivo temporal y los informes.

## Alcance de salida

Se cumplen los criterios de navegación de D.1: inicio en menú, botones funcionales, elección compartida, transmisión del perfil, Malecón, retorno y contratos de carrera, sin alterar geometría ni parámetros de conducción. Permanecen pendientes la carrera jugable (D.2), rivales NPC (D.3) y Pasaporte La Paz (D.4). No se implementan mecánicas provisionales para suplirlos.
