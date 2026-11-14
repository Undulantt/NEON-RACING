# SF.3 — Nubes 2D neón y referencias de desplazamiento

Fecha: 2026-11-13. Capa decorativa experimental, activa por defecto al entrar al mundo nocturno.

## Estilo y objetivo

La referencia facilitada por el usuario guía la segunda versión: nubes **planas, alargadas y recortadas por el viento**, con puntas angulosas, huecos horizontales y pequeñas franjas desprendidas. Se sustituyeron las primeras siluetas redondeadas por estas formas, con rosa/magenta menos blanquecino. No se copió la imagen ni se descargaron texturas.

El objetivo es dar una referencia visual en el cielo que cambie de perspectiva al recorrer la ciudad. Las nubes ocupan posiciones finitas dentro del mundo: no son una imagen pegada a la cámara ni una animación que simule aceleración cambiando la física.

Son decoración ficticia. No representan un registro meteorológico real de La Paz.

## Implementación

- `scripts/style/NeonClouds.gd`: distribución procedural por celdas con semilla fija; cuatro variantes, tamaños y alturas variables; deriva lenta por viento.
- `assets/textures/sf3_cloud_atlas.png`: atlas original RGBA de 512×128, con cuatro máscaras. Se genera offline con `tools/build_sf3_cloud_atlas.py` y Pillow; no hay generación de imágenes durante la conducción.
- `shaders/sf3_clouds.gdshader`: sprites planos orientados hacia la cámara, gradiente rosa, transparencia y desaparición gradual por distancia.
- `NightStyle.gd`: crea una sola instancia del controlador para el mundo; se libera al regresar al menú. Sirve para modo libre y carreras sin duplicar la lógica.
- `SpeedFeelPanel.gd`: añade un interruptor junto a la vista previa de la pestaña SF.3.

Se usa **un MultiMesh de 81 quads: 162 triángulos y un lote de dibujo adicional** en la vista comprobada. No hay un nodo por nube, luces, sombras, colisiones, partículas, ruido volumétrico ni postprocesado nuevo.

Las posiciones permanecen fijas respecto al mundo, salvo el viento configurado. El lote se recentra cuando la cámara cruza una celda y reutiliza los mismos IDs y posiciones para las nubes compartidas. No se vuelve a generar el campo en cada frame. El anillo exterior se recicla fuera del radio donde la opacidad ya es cero; el shader colapsa sus triángulos para evitar rasterizar rectángulos transparentes invisibles.

El atlas se muestrea una vez por fragmento. Se descartan sus zonas vacías y las nubes conservan la prueba de profundidad, de modo que los edificios opacos pueden ocultarlas. El AABB se define explícitamente para incluir el tamaño ampliado de los sprites, evitando recortes por el frustum.

La altitud mínima se adapta al máximo del relieve existente, incluyendo margen para la altura visual y su variación. No cambia el terreno, la cámara, la velocidad, las habilidades o la geometría geográfica. Las nubes son una capa independiente de los materiales de asfalto y mobiliario anteriores.

Documentación técnica consultada: [MultiMesh de Godot](https://docs.godotengine.org/en/stable/classes/class_multimesh.html) y [shaders espaciales](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

## Controles

- **Ctrl+Alt+C:** mostrar/ocultar las nubes durante la conducción.
- **Ctrl+Alt+P → pestaña SF.3 → Nubes 2D rosa neón:** el mismo interruptor, sincronizado con el atajo.
- **`--sf3-no-clouds`:** iniciar el mundo con esta capa desactivada; puede activarse después con el interruptor.

Los modos Original/Parcial/Completo existentes siguen controlando el tratamiento del entorno anterior; las nubes tienen su interruptor independiente. La configuración temporal del interruptor se reinicia al crear otro mundo; no se guarda sobre las preferencias del jugador. El viento se detiene al pausar el árbol del juego.

## Valores iniciales de la versión basada en la referencia

Editar `config/sf3_clouds.json` y reiniciar la escena para cambiar la distribución.

| Parámetro | Valor |
|---|---:|
| Semilla | 20261113 |
| Celda | 650 m |
| Radio de cuadrícula | 4: campo fijo de 9×9 |
| Radio visible | 2,100 m, con fundido desde el 72% |
| Altitud solicitada | 380 m, elevada automáticamente si el relieve lo requiere |
| Variación vertical | ±40 m |
| Ancho del quad | 360–650 m |
| Alto del quad | 75–110 m |
| Viento X/Z | 1.5 / 0.4 m/s |
| Opacidad máxima configurada | 0.65, modulada por variante y distancia |
| Color superior/inferior | `ef73c9` / `b82e94` |

Las dimensiones son del quad completo; la silueta ocupa una parte del atlas. El componente limita radio de cuadrícula a 2–5 y el radio visible al margen seguro de reciclaje. Mantener tamaños y alturas coherentes con el margen del AABB al experimentar con valores extremos.

## Pruebas y reproducción

Con el ejecutable Godot 4.7.2 del proyecto:

```text
--headless --path . --editor --import --quit
--headless --path . --script res://tests/sf3_clouds.gd -- --benchmark
--path . --script res://tests/sf3_clouds.gd -- --benchmark
```

La prueba inicia una partida real desde el menú y usa la avenida OSM existente de la prueba SF.1. Comprueba el límite de instancias, ausencia de colisiones/sombras, anclaje al mundo, cambio de proyección al mover la cámara, continuidad al cruzar celdas, viento, interruptor/atajo y conservación del estado del automóvil.

La comparación renderizada usa idéntica pose/cámara/ciudad, 1280×720 Compatibility, VSync desactivado, orden A/B/B/A, dos segundos de estabilización y 600 frames por muestra. Presupuesto del piloto: aumento medio del p95 entre modos inferior a 0.5 ms. Son vistas fijas; no se interpretan como FPS garantizados durante todo el recorrido.

Archivos de evidencia:

- `docs/sf3_clouds_validation.json`: comprobaciones de comportamiento sin render.
- `docs/sf3_clouds_render_validation.json`: comprobaciones y tiempos con render.
- `docs/evidence/sf3_clouds_off.png` y `sf3_clouds_on.png`: misma vista sin/con la capa.

La primera prueba de las siluetas redondeadas excedió el margen elegido. Se redujo el trabajo invisible del anillo exterior y se amplió el muestreo antes de repetir la comparación. El acabado final alargado se vuelve a medir; los informes vigentes corresponden a esa versión.

## Límites y siguiente evaluación

Los sprites funcionan mejor desde la cámara de conducción; una cámara aérea por encima de su altitud puede revelar su naturaleza plana. No son nubes volumétricas ni producen sombras sobre la ciudad. La transparencia dentro de un MultiMesh no ordena cada nube como un objeto independiente; se usan siluetas de baja densidad y tintes similares para reducir artefactos de solapamiento.

La sensación de desplazamiento es moderada y depende de la dirección, distancia y cantidad de cielo visible. No se exageró el movimiento en TURBO/BURST ni se añadió vibración. Primero conviene evaluar el estilo y paralaje personalmente; el siguiente ajuste puede ser densidad, tamaño o altitud, manteniendo el mismo lote.

## Resultado de la versión final

Las 13 comprobaciones sin render y 14 con render pasan. En la RTX 4060 Ti, las muestras A/B/B/A registraron:

| Modo | Mediana (ms) | p95 (ms) | Draw calls |
|---|---:|---:|---:|
| Sin nubes | 1.994 | 2.710 | 244 |
| Nubes | 1.912 | 2.470 | 245 |
| Nubes | 1.855 | 2.194 | 245 |
| Sin nubes | 2.028 | 3.546 | 244 |

CPU de actualización estable: 0.871 µs de media en 1,000 llamadas sin cambio de celda; no incluye la regeneración al cruzarla. El atlas PNG ocupa 10,589 bytes y 256 KiB de RGBA sin comprimir.

No se detectó una regresión en este muestreo; las diferencias favorables de tiempo están dentro de la variabilidad de la prueba y **no demuestran que añadir nubes mejore los FPS**. La comparación sirve como control de coste en una vista, no como garantía en todos los equipos o recorridos.

Regresiones: las 48 comprobaciones existentes de navegación/carreras pasan con nubes integradas. La suite histórica SF.3 pasa 84 de 85: queda la comparación de hash de `CityFurniture.gd`, que fue modificado en la recuperación de edificios de la entrega anterior y no se editó en esta entrega de nubes. Se conserva ese fallo de referencia sin reescribir el baseline para ocultarlo; no es un error de ejecución del shader. El atlas se regeneró idéntico byte por byte. Resumen: `sf3_clouds_regressions.json`.
