# Fase B — decisiones y registro de validación

Implementación realizada el **23 de octubre de 2026, UTC−07**. Estado: **conducción libre funcional**, pruebas automáticas y renderizadas aprobadas; sesión manual prolongada pendiente. No se implementó fase C. El MVP completo sigue siendo parcial porque faltan carreras/rivales y pulido.

## Funcionalidad y decisiones

### Automóvil

`CharacterBody3D` de 1.8 × 1.2 × 4.1 m con caja de colisión, eje delantero -Z, gravedad y `move_and_slide()`. La raíz está a unos 0.6 m sobre el asfalto al apoyar. La carrocería, cabina, ruedas, faros y luces de freno se construyen con primitivas originales, sin marcas comerciales. No se simula suspensión ni vuelco: la conducción plana mantiene el coche erguido.

El controlador separa velocidad longitudinal y lateral. Acelerar/frenar aproxima gradualmente la velocidad deseada; el giro depende de velocidad, batalla y ángulo de dirección, limitado a alta velocidad. No rota detenido. El agarre aproxima la velocidad hacia la orientación del coche; el freno de mano lo reduce a 0.45 del normal y añade frenado. Las velocidades se expresan en m/s; el HUD usa la velocidad real de desplazamiento ×3.6. El giro propuesto se rechaza si la caja penetraría una fachada o barrera.

Parámetros en `config/driving_config.json`: avance 32 m/s (115.2 km/h), reversa 7 m/s, aceleración 11 m/s², freno 22 m/s², inercia 4 m/s², gravedad 22 m/s², velocidad fuera del asfalto 12 m/s. Son ajustes arcade, no mediciones de un coche real.

### Recuperación

Cada 0.5 s, con el coche apoyado sobre asfalto, se busca el centro del tramo más cercano. La posición candidata debe estar dentro del sector, libre de obstáculos y tener soporte de carretera bajo el centro y cuatro esquinas de la caja. Se alinea con el sentido del tramo; en vías bidireccionales se conserva el sentido más cercano al que llevaba el coche. La última candidata válida se guarda.

R restaura esa posición, pone velocidad y dirección de volante a cero y recoloca la cámara. Si ya no es válida se intenta el spawn; si tampoco es seguro, la operación se rechaza con error. También hay recuperación automática por caída bajo Y=-4, salida de límites o orientación invertida. Estas defensas no sustituyen las colisiones: las pruebas exigen **cero recuperaciones durante el recorrido conectado**.

### Cámara, controles y menú

SpringArm3D de 7.5 m con esfera de 0.25 m, margen 0.3 m y máscara contra entorno. Se excluye el coche. Posición ligada al coche para no retrasar el punto de barrido dentro de paredes; orientación interpolada. FOV de 70–77° según velocidad. Al recuperar, se reinicia la cámara sin interpolar desde el lugar anterior.

InputMap persistente en `project.godot`. WASD/flechas, espacio, R, Esc y C. E solo informa que las carreras corresponden a fase C. La vista aérea detiene el control del coche. HUD en CanvasLayer con fondo de contraste, velocidad, nombre de calle y atribución. La pausa congela la escena y mantiene su interfaz activa. Menú: continuar, volver al punto inicial y salir.

### Entorno y colisiones

Se conservó intacto el JSON vial de fase A. Su generador y RoadBuilder siguen compartidos. La antigua escena está en `scenes/PhaseA.tscn` y `PhaseAWorld.gd`; su prueba solo ve calzada, sin suelo auxiliar, por lo que un fondo nuevo no puede enmascarar fallos.

Se descargaron edificios OSM en consulta separada. Se aceptan únicamente ways cerrados válidos dentro del sector, de 15–15,000 m², en nivel cero, excluyendo techos aislados y construcciones. Cualquier huella que toque el asfalto estimado más 1 m de separación se **omite**, sin modificar su forma ni editar OSM. Resultado: **239 edificios, 44 exclusiones** registradas. No se importan relaciones multipolígono: el entorno no es un inventario completo de edificios.

Las alturas proceden de `height`, después `building:levels ×3.1`, o 1–3 niveles deterministas por ID. Se limitan a 2.8–10 m para el prototipo, marcando las estimaciones y estilizaciones. Fachadas y colores genéricos. Se triangulan techos y se extruyen paredes reales. Ventanas cosméticas sin colisión adicional. Agrupación por 41 sectores: un mesh con colores de vértice y un collider estático por sector. Son **19,509 triángulos de edificios** incluidos detalles, más **5,712 viales**.

Plataforma neutral plana a Y=-0.08, ligeramente bajo el asfalto. Permite salir de calzada sin caer al vacío. No se presenta como tierra firme, costa o altimetría OSM. Cuatro barreras naranjas de 3 m de altura delimitan la bbox con margen de 30 m. Esas barreras son límites del juego, no infraestructura real.

Capas físicas: 1 calzada, 2 plataforma, 4 edificios, 8 límites, 16 jugador (valores de bitmask). La prueba de soporte sobre asfalto usa exclusivamente máscara 1; la recuperación no confunde la plataforma con una carretera.

## Procedencia

BBox común `[24.148,-110.334,24.170,-110.305]`, origen `[24.159,-110.3195]`, proyección equirectangular local, 1 m por unidad.

- Vías: snapshot `la_paz_roads_20261024T053545Z.json`, extracción local 23/10/2026 22:35:45 UTC−07; base 2026-07-15T15:22:01Z. Fuente Overpass Kumi. SHA-256 `a80c891a315fe1f0d1dc3f3dd74a040d41a8a68a94947925336a8754b0ee8142`.
- Edificios: `la_paz_buildings_20261024T062913Z.json`, extracción local 23/10/2026 23:29:13 UTC−07; base **2026-06-01T08:52:28Z**. Fuente `https://overpass.private.coffee/api/interpreter`. SHA-256 `e75bee4a4fb3e3158ba2e3a46a0e620dd38b5279110bbe5660e8279fb68405a8`.
- La primera consulta de edificios a Kumi agotó tiempo; overpass-api.de falló con certificado vencido. Se consultó el directorio público OSM y Private.coffee respondió correctamente, con TLS habilitado. No se falsificaron ni rellenaron huellas.
- Las fechas base difieren: el filtrado evita interferencias físicas entre snapshots, pero no corrige diferencias temporales cartográficas. No se realizó comprobación de campo.

El nuevo JSON `la_paz_environment.json` usa `schema_version=1`, SHA-256 del mapa vial, metadata/procedencia, límites, spawn, edificios/triángulos de techo/atributos, exclusiones y una ruta técnica de conducción. El juego rechaza un entorno generado contra otro hash de mapa. No se alteró el esquema vial de fase A.

## Pruebas ejecutadas

Entorno: Godot **4.7.2.stable.official.ed1daf0bf**, Python **3.13.7**, Shapely **2.1.2**, Windows, Jolt Physics, GL Compatibility, NVIDIA GeForce RTX 4060 Ti / controlador NVIDIA 610.88. Las rutas exactas y los comandos reproducibles están en README.

| Prueba | Resultado observado |
|---|---|
| `python -B -m unittest discover -s tests -v` | **16/16 OK**: 12 originales + 4 de entorno, procedencia, huellas idénticas a OSM, techos, separación vial, spawn y ruta auténtica. |
| Importación `--headless --editor --quit` | Código 0, sin errores de parseo/importación. |
| `tests/godot_phase_a.gd` | PASS; 32,751 rayos, 381 nodos de cruce, sonda 2,325.347 m. Se conserva el caso de rayo sobre diagonal y su apoyo físico independiente. |
| `tests/godot_phase_b.gd` headless | **PASS**, sin fallos, 9,384 frames en último informe. |
| Mismo test con render, `--visual-test` | **PASS**; capturas reales revisadas a 200, 600 y 1,000 m. Se ejecutó antes de los últimos ajustes de contraste y pruebas adicionales de menú. |

La ruta técnica de fase B mide **1,200.919 m** y el criterio de llegada es quedar a menos de 3 m del extremo: el coche alcanzó **1,197.928 m** de progreso. Recorrió Paseo Álvaro Obregón, 16 de Septiembre, Aquiles Serdán, Ignacio Ramírez y Melchor Ocampo (OSM usa dos variantes de nombre para 16 de Septiembre). Cruzó **14 nodos de intersección**. Desviación máxima respecto del eje: **2.068 m**; **0 frames fuera del asfalto**, **0 frames sin suelo**, **0 contactos con fachadas**, **0 recuperaciones** durante ese trayecto.

El conductor automático existe **solo en el script de pruebas**. Da aceleración y volante al mismo controlador de producción, sin imponer posiciones/velocidades durante el recorrido ni crear un rival del juego. Se recoloca el coche únicamente al iniciar casos independientes de prueba, como el choque o la reversa.

Resultados del coche:

- Avance máximo medido: **31.9983 m/s**; reversa: **-7.0000 m/s**.
- Frenado desde velocidad máxima: **87 frames a 60 Hz**, aproximadamente 1.45 s.
- Deslizamiento angular de referencia: 0.124 rad normal, 0.258 rad con freno de mano.
- Giro en reposo rechazado por la prueba; aceleración, freno, reversa y velocidad HUD aprobados.
- Eventos físicos enviados a InputMap dentro de Godot: W, Down, S, A, R, Up, Space; Escape comprobó pausa/continuar. También se activaron los botones de menú y reinicio mediante sus señales de interfaz.
- **8 recuperaciones** esperadas entre pruebas de tecla, caídas, recuperación manual y reinicio de menú; ninguna en la ruta.
- Choque sostenido contra fachada OSM: caja detenida a **2.0524 m** del plano de fachada, velocidad final menor a 0.2 m/s. No penetró la pared.
- Cámara al poner una fachada detrás del coche: brazo reducido a **2.8326 m**, frente a sus 7.5 m libres.
- Los **cuatro límites** detuvieron el coche. Pausa congeló posición; continuar restauró aceleración. C cambió entre inspección y persecución.

Informes: [headless](phase_b_validation.json), [render](phase_b_validation_render.json), [regresión A](godot_validation.json).

### Evidencia visual

[Estado final con HUD legible](evidence/phase_b_spawn_final.png). Recorrido renderizado: [16 de Septiembre](evidence/phase_b_drive_0.png), [Aquiles Serdán](evidence/phase_b_drive_1.png), [Melchor Ocampo](evidence/phase_b_drive_2.png). Son imágenes del viewport real de Godot. Las tres de recorrido preceden a la mejora final de contraste del HUD y ajuste de iluminación; la geometría y física son las mismas.

### Rendimiento observado

Se ejecutó `tests/benchmark_phase_b.gd`: calentamiento de 2 s y muestra de 10 s, escena de spawn. Última muestra: **115.9 FPS promedio**, p95 **8.88 ms**, máximo **149.677 ms**, aproximadamente **164 draw calls**, **14,973 primitivas visibles**, **411 nodos**. Construcción del mundo en esa ejecución: 107 ms (no todo el arranque).

**No es un benchmark estable a 1080p.** Aunque se solicitó 1920×1080, el gestor de ventanas cambió las dimensiones; la textura final fue **2690×1414** (otra ejecución terminó en 2831×1563). Además había interacción del entorno de escritorio durante las mediciones. Se conserva el informe real en [phase_b_benchmark.json](phase_b_benchmark.json), sin extrapolar una garantía de 60 FPS ni un rendimiento de carrera. Para comparar hardware se requiere repetir con tamaño fijo y sin ventanas de pruebas adicionales.

## Pendientes y límites

- La habilidad de control de escritorio devolvió capturas de otra ventana incluso tras activar la ventana Godot seleccionada. Se detuvo ese intento sin enviar teclas a un destino incierto. **No se afirma una prueba manual prolongada con teclado del escritorio.** Sí se verificaron las entradas físicas dentro de Godot y la conducción renderizada automatizada.
- No se desconectó físicamente Windows de Internet. El juego no contiene adquisición de red y se ejecutó con archivos procesados locales.
- La plataforma neutra incluye toda la bbox como soporte técnico; no demuestra dónde hay costa/tierra. No hay mar modelado.
- Edificios incompletos según cobertura OSM, sin multipolígonos, alturas frecuentemente estimadas. Sin árboles, tráfico, banqueta detallada o modelos emblemáticos. El vehículo es un modelo procedural básico.
- No hay física avanzada, suspensión ni choque con deformación. El ajuste fino de sensación de manejo requiere una sesión humana.
- No hay carrera, checkpoints, rivales ni clasificación. La ruta de prueba no es una carrera ni una recomendación de conducción en calles reales.

Siguiente trabajo por impacto: (1) revisión humana del manejo y ajuste de sensibilidad/freno de mano; (2) solo con autorización, fase C con ruta/checkpoints/restricciones de giro y dos rivales; (3) ambientación y benchmark controlado al llegar a fase D.
