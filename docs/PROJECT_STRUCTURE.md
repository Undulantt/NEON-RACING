# Estructura y política de Git

## Archivos compartidos

| Carpeta | Contenido |
|---|---|
| `scenes/`, `scripts/`, `shaders/` | Escenas y código del juego, separado por sistema |
| `assets/` | Recursos visuales y sonoros usados por el juego |
| `config/` | Configuración compartida de conducción, rivales y mundo |
| `data/processed/`, `data/races/`, `tracks/` | Datos del juego y circuitos |
| `data/raw/`, `data/reference/`, `data/licenses/` | Fuentes cartográficas, referencias y licencias necesarias para reproducir el mapa |
| `tools/` | Conversión, generación y validación de recursos |
| `tests/` | Pruebas, capturas y comandos para ejecutarlas |
| `tests/fixtures/baselines/` | Copias históricas y datos de comparación de las regresiones |
| `tests/fixtures/routes/` | Rutas de prueba compartidas y regenerables |
| `docs/` | Guías, diseño, arquitectura e historial |

`project.godot`, `README.md`, `CREDITS_AND_LICENSES.md`, el icono y los archivos
de configuración de Git permanecen en la raíz. Las rutas del juego y su escena
de inicio se conservan. Los archivos `.uid` y `.import` de recursos compartidos
se versionan: no deben ignorarse de forma global.

## Archivos locales

`.local/artifacts/` reúne informes JSON, logs y resultados de pruebas.
`.local/artifacts/evidence/` contiene capturas y audio de comprobación. Las
pruebas y herramientas escriben directamente en estas rutas. El esqueleto de
ambas carpetas se comparte mediante `.gitkeep`, por lo que existe al clonar.

`.local/.gdignore` evita que Godot importe capturas y copias auxiliares.
`tests/fixtures/baselines/.gdignore` evita que las copias de scripts históricos
se registren como código activo; las pruebas pueden leer sus bytes explícitamente.

Los cachés `.godot/`, los perfiles `.godot-local-profile/` y los entornos
`.venv*/` mantienen sus rutas convencionales y quedan excluidos de Git. También
se ignoran compilaciones en `build/`, `dist/` y `exports/`, logs, temporales,
credenciales de exportación, archivos `.env` y preferencias locales del editor.
Los ejemplos `.env.example` se pueden compartir.

## Cómo compartir cambios

Se comparten código, configuración, pruebas, fixtures, documentos útiles,
recursos del juego y las atribuciones de sus fuentes. Un informe nuevo o una
captura de depuración permanece local; si constituye una referencia indispensable,
se selecciona y se coloca explícitamente en una carpeta versionada apropiada.
Las fuentes de `data/raw/` no son basura: las herramientas y sus verificaciones
de procedencia dependen de ellas.

`.gitignore` impide agregar archivos nuevos; no elimina archivos ya registrados
ni borra versiones antiguas del historial. La reorganización deja las rutas
antiguas como eliminaciones y sus destinos compartidos como archivos nuevos;
Git puede reconocer los movimientos al preparar el commit. Los resultados
trasladados a `.local/` permanecen en disco y dejan de compartirse cuando se
registra esta reorganización. No se ha reescrito el historial de Git.

El inventario local `.local/organization-manifest.json` conserva las rutas
originales, destinos y SHA-256 anteriores al traslado para auditar la operación.
No se deben borrar todos los resultados locales sin revisar antes si una prueba
histórica consume un informe generado por otra prueba; algunos ensayos requieren
ejecutar primero su generador.

## Comprobaciones habituales

Desde la raíz, con Godot disponible en la ubicación esperada por los runners:

```powershell
./tests/run_d3.ps1 -RivalCounts 1
./tests/run_rival_acceptance.ps1
python -B -m unittest discover -s tests -v
git check-ignore -v .local/artifacts/d3_rules_validation.json
```

Las herramientas `tools/analyze_burst_routes.py` y
`tools/build_boundary_extension_routes.py` regeneran las rutas de prueba
versionadas; revisar esos cambios antes de registrarlos.
