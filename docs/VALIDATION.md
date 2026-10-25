# Registro histórico de validación — Fase A

La fase B se documenta en [PHASE_B.md](PHASE_B.md). Para reproducir esta escena aislada usa `scenes/PhaseA.tscn`; este registro describe la entrega anterior.

Realizado el 23 de octubre de 2026 (UTC−07), con Godot 4.7.2.stable.official.ed1daf0bf y Python 3.13.7. **Fase A operativa; MVP completo pendiente. No se inició fase B.**

## Comandos ejecutados y resultado

| Comando desde la raíz | Resultado real |
|---|---|
| `python tools/fetch_osm.py` | Primera instancia falló TLS; segunda descargó 185,720 bytes originales. |
| `python tools/build_map.py` | 894 nodos, 1,162 tramos, 1,785 aristas dirigidas, 1 exclusión. |
| `python tools/validate_map.py` | PASS: origen, números, esquema, sentidos, topología, ruta, unión/triángulos y procedencia. |
| `python -B -m unittest discover -s tests -v` | 12 pruebas, todas OK; incluye regeneración determinista, recorte, -1, proyección, accesos, rechazo de NaN y dirección corrupta. |
| `Godot --headless --path . --editor --quit` | Código 0, sin errores de importación/GDScript. |
| `Godot --headless --path . --fixed-fps 60 --script tests/godot_phase_a.gd` | Código 0; informe guardado en `godot_validation.json`. |
| `Godot --path . -- --capture=...` | Render real GL Compatibility correcto en 1280×720; PNG revisados visualmente. |
| `Godot --path . -- --plan --capture=...` | Vista cenital comparada visualmente con dibujo independiente de los nodos/ways crudos. Coinciden curvas del paseo y conexiones urbanas. |

La ruta mide **2,325.347220 m**, respeta sentidos y usa aristas OSM reales. La sonda física (esfera, radio 0.45 m en CharacterBody3D, herramienta de prueba) recorrió **2,325.347157 m**, 22 cruces, a 30 m/s con paso físico 60 Hz, en 4,671 frames incluidos asentamiento. No perdió contacto: centro Y entre **0.450749 y 0.450998 m**. No es prueba de conducción de un automóvil.

Barrido adicional: **32,751 rayos** sobre centros y dos posiciones laterales al 80% del semiancho, espaciados como máximo 8 m, además de los **381 nodos de grado ≥3**. Un rayo de ancho cero no detecta una diagonal compartida en el extremo de `28783031:18` (`1434.582, 1223.144`). Se conservó explícitamente como `ray_edge_misses=1`; no se declaró que todos los rayos acertaran. Se dejó caer un cuerpo físico independiente exactamente en ese punto y se comprobó su apoyo durante el recorrido completo: **sin caída ni pérdida de contacto**. Si falta apoyo en cualquier prueba de caída, el script falla. La comparación geométrica offline además verifica cobertura completa sin huecos/solapamientos de área significativa (tolerancia 0.01 m² para la suma total).

Los fallos de rayos y la colocación de una esfera no demuestran ausencia de defectos arbitrariamente pequeños para otros cuerpos; el criterio comprobado es continuidad transitable para el cuerpo de prueba. Un vehículo futuro requerirá sus propias pruebas.

## Correcciones durante la validación

- La primera imagen mostró problemas de profundidad entre superficie y fondo a varios kilómetros. Se elevó el near de vista general a 5 m y se separó el fondo a Y=-2. La cara frontal final de la malla se verificó mediante render; la colisión conserva ambas caras. Las capturas finales muestran asfalto continuo.
- El barrido inicial marcó un único fallo sobre una arista. Se investigó en la geometría exportada y se añadió prueba física independiente, en lugar de omitir el punto o aumentar silenciosamente la tolerancia.
- Se añadió rechazo de cruces geométricos sin nodo compartido: el dataset actual contiene **cero** de esos cruces.

## Evidencia visual real

- [Vista general Godot](evidence/map_overview.png).
- [Vista cenital Godot](evidence/map_plan.png).
- [Referencia directa del snapshot OSM](evidence/raw_osm_reference.png): dibujo independiente de latitudes/longitudes originales, con Obregón en rojo; no utiliza el JSON procesado. No es una captura del sitio web OSM.
- [Superficie desde la cámara a 1.8 m](evidence/road_surface.png).
- [Informe físico completo](godot_validation.json).

La referencia independiente se generó una vez con Pillow disponible en el entorno; no es dependencia del juego ni del conversor obligatorio. El SHA-256 y la validación de todos los nodos OSM no recortados también verifican identidad cartográfica, más allá de la comparación visual.

## Alcance de lo comprobado y pendientes

- Verificados: extracción auténtica, apertura/importación en Godot, render, correspondencia visual con snapshot crudo, sentidos, escala, ruta dirigida, colisión estática y cruce de más de cinco intersecciones.
- Arranque local verificado usando solo JSON procesado; los scripts runtime no contienen solicitudes de red. **No se desconectó físicamente la red de Windows**. La independencia está respaldada por arquitectura y arranque sin fase de descarga, no por una prueba manual de desconexión.
- No se realizó una sesión manual prolongada de teclado/ratón; el recorrido de cámara se ejecutó para las capturas y el recorrido completo lo realizó la sonda automatizada. Los controles están implementados y documentados.
- Render en NVIDIA RTX 4060 Ti/OpenGL 3.3/NVIDIA 610.88, 1280×720. Mallas generadas: **74 sectores, 5,712 triángulos**, área asfalto **494,421.8051 m²**. Construcción de mallas medida entre 17 y 25 ms en ejecuciones verificadas; esto no incluye importación ni todo el arranque. Sin medición sostenida de FPS, draw calls o rendimiento a 1080p.
- La fecha base OSM es julio de 2026; no se comprobó contra relevamiento de campo ni contra cartografía más reciente.
- Anchos frecuentemente estimados, elevación plana estimada, sin costa/edificios. Fondo arena neutro sin colisión. No salir de la calzada con un vehículo futuro: no existe aún sistema de límites/recuperación.
- Sin relaciones de restricciones de giro ni carriles de navegación. La ruta es una verificación topológica dentro de la fase A; no una recomendación vial.
- No se probó ni implementó conducción arcade, carreras, CPU o HUD de carrera porque están fuera del encargo.

## Siguiente trabajo, sin implementar

1. Añadir el vehículo arcade y repetir la prueba de 22 cruces con sus dimensiones, velocidades y recuperación.
2. Antes de una carrera, incorporar restricciones de giro pertinentes y fijar checkpoints sobre aristas verificadas.
3. Añadir límites del mundo y suelo/ambientación solo con delimitaciones justificadas, conservando las pruebas de asfalto independientes.
