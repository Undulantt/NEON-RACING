# B.6 — continuación: Places, DENUE y arquitectura

## Auditoría y plan retomado

Se retomó el checkpoint `d90962f`. Ya funcionaban la conducción, vías, proyección local (+X este, +Z sur), 7.779 edificios, 75 sectores, streaming, colisiones, costa, 300 POI OSM, categorías, overrides, seis registros emblemáticos y la Catedral básica. La especificación disponible es `RECONSTRUCCIÓN_URBANO.md`; no existe el nombre de archivo solicitado inicialmente.

Plan ejecutado incrementalmente: (1) adquirir y verificar fuentes públicas reales; (2) extender el importador existente con normalización y asociaciones conservadoras; (3) ampliar fachadas y Catedral; (4) regenerar, validar datos y comprobar Godot y rendimiento. No se reemplazaron los sistemas existentes.

## Fuentes y resultados

| Fuente | Snapshot | Registros dentro del mapa, con nombre |
|---|---|---:|
| OSM | XML local ya verificado | 300 |
| Overture Places | 2026-10-21.0 | 3.054 |
| DENUE BCS | Mayo 2026, metadatos 20/05/2026 | 2.482 |
| Total de registros de fuentes | No equivale a establecimientos únicos | 5.836 |

La descarga original Places contiene 3.055 entidades. El ZIP estatal DENUE contiene 42.577 filas, 2.484 dentro del área. Se excluyen registros sin nombre; se conservan los originales y las razones de exclusión. Los metadatos fijan URL, fecha, esquema observado y SHA-256. Las descargas públicas necesitaron acceso de red autorizado porque el entorno restringido no resolvía DNS. No se necesitó token DENUE.

Places usa `basic_category` y `taxonomy`, no el antiguo campo `categories`. El CSV DENUE observado requiere cp1252; su archivo de metadatos usa UTF-8 con BOM. Se corrigió la decodificación independiente de ambos archivos y se agregó una comprobación de acentos. Se conserva la actividad SCIAN, ubicación, dirección y fecha de alta; los contactos del archivo original no se incorporan al JSON normalizado.

Hay 689 registros asociados por contención única y 5.147 sin asociación. Los 1.368 registros Places con confianza insuficiente, ausente o cierre declarado se conservan para revisión y no clasifican edificios. La confianza de existencia de Places no se confunde con confianza geométrica. No se asocian POI a huellas ficticias.

Se registran 490 pares candidatos a duplicado por nombre normalizado y distancia de hasta 20 m. No son duplicados confirmados: no se fusionan ni se borran automáticamente. Las fuentes repetidas no dan votos adicionales a una categoría. La proximidad por sí sola sigue sin asignar una huella.

385 edificios tienen categoría: 164 comerciales, 113 restaurantes, 48 institucionales, 27 hoteles, 20 residenciales, 11 culturales y 2 industriales. Los 7.394 restantes siguen sin clasificación. Se conservan exactamente 7.779 huellas y sus controles de separación de calles/agua.

## Mejora visual y coste

Las fachadas clasificadas se orientan mediante la arista próxima a una calle existente. Ventanas superiores acotadas y divisiones de escaparate se agregan a la malla del sector después de capturar la geometría física. No añaden cuerpos de colisión ni nodos por ventana. Las entradas son ilustrativas, no verificadas.

La Catedral usa una sola malla con arcos, óculo, divisiones de campanarios, tejado a dos aguas, remates y cruces, siguiendo la monografía oficial citada en créditos. Dimensiones estimadas, sin precisión fotogramétrica. Los otros cinco registros mantienen su representación anterior; dos siguen sin asociación segura. No se inventaron edificios para completar el registro.

Durante el arranque se verifican los hashes de todos los datos B.6, pero solo se parsean los JSON de geografía y landmarks usados por el juego. El archivo de auditoría POI permanece local sin cargar miles de registros innecesarios en memoria del runtime.

## Reproducción

```powershell
$p = '.venv-urban/Scripts/python.exe'
$g = '..\..\Godot_v4.7.2-stable_win64_console.exe'
& $p tools/fetch_urban_sources.py places
& $p tools/fetch_urban_sources.py denue
& $p tools/build_landmark_model.py
& $p tools/build_urban_city.py --check-determinism
& $p tools/validate_urban_enrichment.py
& $p -m unittest discover -s tests -v
& $g --headless --path . --script tests/godot_phase_b6.gd
& $g --headless --path . --script tests/godot_phase_b5.gd
& $g --path . --fixed-fps 60 --script tests/benchmark_route_b6.gd
& $g --path . --fixed-fps 60 --script tests/capture_phase_b6.gd
```

Los comandos de adquisición verifican el caché fijado. `--refresh` descarga otra copia y muestra el nuevo archivo de metadatos para inspeccionarlo y fijarlo explícitamente en `config/urban_enrichment.json`; no cambia el snapshot automáticamente. Partida y regeneración con caché funcionan sin red. Fuentes y licencias: `CREDITS_AND_LICENSES.md` y `data/licenses/`.

## Progreso y verificación

- Adquisición, normalización, asociaciones y arquitectura implementadas.
- 32 pruebas Python aprobadas, incluidas esquema real, SCIAN/taxonomía, confianza y rechazo de hash corrupto. Una fixture temporal falló por permisos y se sustituyó por un mock del hash; se repitió y pasó.
- Regeneración completa determinista después de corregir la codificación: PASS. Generación de Catedral repetida: hash idéntico.
- Validación geográfica: PASS, 22 superficies, cobertura completa, sin solapamientos de agua/edificios ni suelo/asfalto por encima de 0,01 m²; sin overrides huérfanos.
- Godot B.6: PASS, fachadas excluidas de la física, sustitución visual y Catedral en una malla. Godot B.5: PASS, streaming y F8, diferencia de movimiento 0 m / 0 m/s.
- Recorrido y rendimiento renderizados: PASS; métricas abajo.
- Regresión completa Godot de conducción: PASS, 9.384 frames físicos, teclado, aceleración/freno/reversa, recuperación, contacto de fachada, cámara, cuatro límites, pausa y menú. Informe: `phase_b5_driving_validation.json`. Pico de sector en esta prueba adicional: 22 ms.

## Límites

Los snapshots tienen fechas distintas y no garantizan que un negocio siga abierto. Las categorías son aproximaciones visuales. La mayoría de las huellas no tiene evidencia suficiente para clasificarse. No hay comprobación de campo, altimetría nueva, reconstrucción fotográfica de cada inmueble ni cambios de conducción. La estética neón y modelos detallados de los demás landmarks permanecen fuera de esta entrega.

## Resultado renderizado de esta continuación

Mismo recorrido, 1.197,93 m sobre ruta de 1.200,92 m, 14 cruces, 7.314 fotogramas por pasada, viewport 1280×720, Compatibility/OpenGL, RTX 4060 Ti. Ambas pasadas: cero frames fuera del asfalto o sin apoyo, cero contactos de pared, cero recuperaciones y cero sectores fallidos.

| Métrica | B.5 equivalente | B.6 con fuentes |
|---|---:|---:|
| FPS promedio | 119,920 | 119,888 |
| Tiempo medio (ms) | 8,339 | 8,341 |
| p95 (ms) | 8,651 | 8,632 |
| Máximo fotograma (ms) | 24,353 | 26,471 |
| Memoria estática máxima (MB) | 98,751 | 100,196 |
| Nodos máximos | 435 | 444 |
| Carga máxima sector (ms) | 8 | 21 |

Cambio de tiempo medio: 0,0273 %, dentro del objetivo de 15 %. La presentación limita a unos 120 FPS; no prueba margen GPU ni rendimiento en equipos inferiores. Memoria es el contador estático del motor, no RAM total/VRAM. Ambas pasadas comparten proceso y cachés. El pico de sector de 21 ms requiere seguimiento. La referencia anterior está preservada en `phase_b6_before_sources_benchmark.json`.

Informe actual: [recorrido](phase_b6_route_benchmark.json). Capturas reales revisadas: [Catedral](evidence/phase_b6_cathedral.png) y [costa](evidence/phase_b6_coast.png). La vista aérea refleja sectores cargados, no todos los edificios simultáneamente.

El benchmark terminó sin errores de shader. Una captura posterior reutilizando el perfil mostró errores `shader_gles3.cpp:802`; se repitió con un perfil APPDATA nuevo dentro de `.godot-local-profile` y terminó sin esos errores. No se considera resuelto permanentemente el comportamiento de caché del entorno. No hubo sesión humana prolongada de conducción.
