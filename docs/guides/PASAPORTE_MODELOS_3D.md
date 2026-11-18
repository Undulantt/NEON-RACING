# Pasaporte ampliado y modelos geográficos

El catálogo tiene **6 lugares activos** asociados a los diez modelos de
`assets/3D/Edificios/`. La UABCS utiliza un único punto general dentro del campus;
se retiraron las cinco interacciones individuales sin modificar los edificios. Se conservan P para el libro,
E para registrar a baja velocidad y Ctrl+Alt+I para el editor manual. Las zonas
de interacción y destinos GPS están sobre calles existentes; no es necesario
subir escaleras. Los modelos aparecen en modo libre y carreras; el Pasaporte
sigue siendo exclusivo del modo libre y no registra visitas automáticamente.

## Colocaciones

| Modelo | Lugar / ID de Pasaporte | Base geográfica |
|---|---|---|
| Kiosco.glb | Kiosco del Malecón, poi_001 | Punto OSM histórico 9284265569 ya documentado |
| Church.glb | Catedral, poi_002 | Contorno OSM 155831066 |
| Theater.glb | Teatro de la Ciudad, poi_003 | Contorno OSM 155831068; referencia SIC teatro 12 |
| ElMolinito.glb | El Molinito, poi_004 | Nodo OSM 10805405566, `ref=Molinito`, `man_made=windpump` |
| ArtMuseum.glb | Museo de Arte de BCS, poi_005 | Contorno OSM 155831056 |
| — | UABCS, poi_006 | Vialidad contenida en el predio OSM 137201460 |
| UABCSRectoria.glb | Rectoría AD-19, poi_006 | Overture c5c01479-fb5a-46d8-9659-c1fd45b4c62a; correspondencia aproximada con el plano |
| UABCSGimnasioAuditorio.glb | Gimnasio AD-01, poi_006 | OSM 1342767403; plano y panorámicas institucionales |
| AD-46.glb | Sistemas II DSC-46, poi_006 | Overture 74a61aba-f87e-4ace-b55c-f63384618bee; correspondencia aproximada con el plano |
| UABCSGeneric1.glb | Edificio académico A, poi_006 | Overture c22792ec-8b0e-4a3d-a542-b5f197a853f5 |
| UABCSGeneric2.glb | Edificio académico B, poi_006 | OSM 666815700 |

## UABCS: evidencia y límites

Se compararon el [plano oficial de 2022](https://www.uabcs.mx/dasc/wp-content/uploads/2022/10/Mapa-Campus-La-Paz-2022.pdf),
el [directorio del recorrido virtual](https://www.uabcs.mx/recorrido-virtual/menu.html)
y las huellas métricas ya recuperadas por SF.3. Se utilizaron accesos, glorietas,
orientación y orden relativo de los edificios. No se tomó un plano de proyectos
futuros como prueba de edificios construidos.

El [XML del gimnasio](https://www.uabcs.mx/recorrido-virtual/lapaz/gimnasio/pano.xml)
publica `(24.102083, -110.314333)` y `(24.102194, -110.314139)`: son posiciones
de captura, **no centros de edificio**. Las panorámicas consultadas de Rectoría
y Sistemas II no publican coordenadas; no se les atribuyen GPS inexistentes.
La fachada de Rectoría se orienta hacia el patio del plano, la del gimnasio
hacia el entorno de su panorama de acceso.

Las huellas son reales; su asociación con identidades del plano se declara
**aproximada**, especialmente Rectoría y Sistemas II. No se afirma un ajuste
topográfico del plano ni precisión arquitectónica. El archivo `AD-46.glb`
permanece con su nombre original; **DSC-46** es la clave institucional publicada.
Los dos archivos genéricos no identifican departamentos: representan dos huellas
académicas reales, sin inventarles una identidad. A/B son nombres del prototipo.
Se integran individualmente los cinco modelos, sin replicarlos por todo el campus.

`data/reference/uabcs_landmark_evidence.json` conserva correspondencias, confianza,
posiciones y hashes de las fuentes consultadas. El PDF y sus renders permanecen
locales; sus ilustraciones no se incorporan como texturas.

Otras fuentes: [Museo de Arte](https://muabcs.cultura-bcs.gob.mx/historia-del-recinto/),
[Kiosco, Turismo Municipal](https://turismo.lapaz.gob.mx/atractivos/kiosco-del-malecon-18),
[Catedral, Turismo Municipal](https://turismo.lapaz.gob.mx/atractivos/catedral-de-nuestra-senora-de-la-paz),
[Teatro de la Ciudad, SIC](https://sic.cultura.gob.mx/ficha.php?table=teatro&table_id=12).
Los textos son descripciones propias breves; no se descargan fotos para el juego.

## Arquitectura y geometría

- `inspect_landmark_models.gd` mide límites incorporando las transformaciones
  locales de Blender. `build_passport_landmarks.py` ajusta escala uniforme,
  centrado y orientación a las huellas fuente y al asfalto arcade existente.
  Dimensiones y orientación son adaptaciones estimadas. Se comprueba que las
  cajas horizontales no invadan asfalto ni la huella de coche de las interacciones.
- `data/passport/landmark_models.json` registra diez colocaciones y **ocho IDs
  sustituidos**. El museo no tenía volumen generado en su huella y ahora se
  incorpora desde el contorno OSM del XML. La Catedral sustituye dos volúmenes.
  `UrbanChunkManager.gd` deshabilita esos registros en memoria después del ajuste
  arcade: no genera su volumen, fachada ni colisión anteriores. Los datos fuente
  permanecen intactos y se conservan los demás edificios del campus.
- `LandmarkModels.gd` carga modelos a 900 m y los descarga a 1,150 m. Activa una
  caja de colisión conservadora a 240 m; no crea colisiones por cada triángulo.
  Una base ajustada al relieve evita flotación. No se exploran interiores ni
  escaleras. Respeta la visibilidad de ciudad; no añade luces ni sombras dinámicas.
  El mobiliario evita sus máscaras. No se modifica la física del automóvil.
- El kiosco trae una plaza de unos 80 m, postes y palmeras que invadirían la
  calzada arcade. Se omiten `Floor_001`, `Foundation_001`, `LightPoles` y
  `PalmTrees`; se conservan kiosco, cubierta, pilares, barandal y escaleras.
  El GLB original no se altera ni se extiende la plaza sobre carreteras o mar.
- Los marcadores `Passport_poi_*` y las instancias guardan `poi_id` y asociación
  al modelo. Se reutilizan interacción, progreso y navegación existentes, sin
  otro Autoload ni lógica duplicada de descubrimiento.

## Catálogo, editor y progreso

El límite provisional de tres lugares pasa a `PassportStore.MAX_ACTIVE=64`.
El catálogo sigue en schema 1 con `content_revision=3`. La migración añade los
lugares nuevos a catálogos locales anteriores sin sobrescribir textos editados
ni entradas desactivadas. Al guardarse desde el editor se conserva la revisión;
las eliminaciones posteriores no se reintroducen por esta migración. Los archivos
malformados siguen el rechazo y fallback existentes.

Los IDs poi_007 a poi_011 se retiran de catálogos locales y borradores al migrar.
Sus descubrimientos históricos se conservan en el archivo de progreso, pero no
cuentan como lugares activos. Los cinco modelos apuntan a poi_006.

Los IDs poi_001/002/003 se mantienen: el progreso sigue guardándose por ID,
sin borrar ni regalar visitas. El Teatro ahora toma la posición del contorno
OSM del modelo, conservando su ID y referencia SIC. Las interacciones nuevas
también son editables mediante la herramienta manual existente.

## Reproducción y validación

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tools/inspect_landmark_models.gd
.venv-urban/Scripts/python.exe tools/build_passport_landmarks.py
godot --path . --script res://tests/godot_passport_landmarks.gd -- --passport-test --capture-landmarks
godot --headless --path . --script res://tests/godot_passport_landmarks.gd -- --passport-test
godot --headless --path . --script res://tests/godot_phase_d1.gd -- --passport-test
```

`build_passport_pois.py` delega en el generador ampliado cuando existe este
manifiesto, evitando restaurar accidentalmente el catálogo inicial. Incluir
los JSON del Pasaporte y los recursos importados de los modelos en la exportación.

La validación de la entrega inicial tuvo 166 comprobaciones y 207 de navegación.
Tras consolidar la UABCS se comprueban los seis lugares con los tres perfiles, GPS por
calles existentes, apoyo físico, registro, duplicados, persistencia, migración,
libro, editor, modelos, supresión y punto principal dentro del predio UABCS.
Se revisan capturas individuales. La prueba histórica D.4 presupone tres lugares
y se conserva como referencia; esta suite sustituye sus expectativas de tamaño.

En las transiciones rápidas se detectó una reanudación de decoración tras salir
del árbol de escena. Se añadieron guardas de ciclo de vida a decoración, banquetas
y mobiliario, y se repitió la prueba sin referencias inválidas.

Informes: `.local/artifacts/passport_landmarks_*.log`,
`passport_landmarks_validation.json`, `evidence/landmark_*.png`. Progreso y ajustes
de pruebas aislados. No se realizó benchmark de recorrido ni exportación PCK;
las capturas no equivalen a una verificación topográfica del campus.
