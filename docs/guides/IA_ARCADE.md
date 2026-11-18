# Rivales arcade, checkpoints y parrilla

## Contenido y salidas

GRAND TOUR LA PAZ se ha retirado: se elimina su JSON, generador y pruebas
específicas. Centro LP conserva sus datos y sus dos vueltas. No se añaden
carreras sustitutivas. Las dos carreras del autor se integran en el catálogo y en modo libre; ver
[Circuito Forjadores y Arracón Malecón](CARRERAS_AGUA_PAUSA_FPS.md).
Los edificios UABCS, Pasaporte, geografía y calles permanecen en el proyecto.

Todas las carreras con la configuración normal de cinco rivales usan una
parrilla **2 columnas × 3 filas**. Los NPC ocupan los lugares 1–5 y el jugador
el sexto, detrás a la derecha. Hay 4.4 m entre columnas y 7 m entre filas.
Los seis coches son paralelos; el orden del HUD respeta esos lugares antes
de que exista progreso de carrera. Se actualiza el punto anterior de movimiento
después de colocar al jugador para evitar contar el cambio de parrilla como
un desplazamiento competitivo.

Se prueban posiciones cercanas a la salida, siempre antes del primer volumen
de checkpoint, con carrocería completa sobre asfalto y sin obstáculos. Si no
caben, la carga vuelve al menú con una explicación; no se utiliza una fila
única ni se colocan coches sobre edificios. Al crear recorridos conviene elegir
un tramo recto con espacio detrás de la salida. `--rivals=0` sigue disponible
para pruebas aisladas y conserva una única posición de jugador.

## Aros y validación comunes

`RaceGeometry.CHECKPOINT_SCALE` pasa de **1.3 a 1.95**: diámetro de aro y radio
de detección crecen **50 % respecto a la versión anterior**. La regla se aplica
por igual al jugador y a todos los NPC, incluidos circuitos antiguos y carreras
del editor. Se conserva el aspecto azul con transparencia degradada, la parte
sumergida y la separación de los controles. No se reescriben sus coordenadas.

La detección continúa siendo una esfera barrida 3D, sin colisión sólida.
Exige movimiento en el sentido permitido y checkpoints en orden. Sigue
rechazando saltos por teletransporte y movimientos con altura inválida. Un aro
más amplio puede admitir una línea que pase por su borde: es el efecto buscado,
no una excepción exclusiva de los rivales.

## Decisiones de conducción

`RivalDriver` mantiene las recuperaciones de salida y los retornos de accesos
estrechos de la revisión anterior. Añade decisiones de línea cada 3.5–6 s,
consultando corredores libres. Cada rival tiene su propio generador aleatorio;
`--ai-seed=730` permite repetir una prueba. No se añade una oscilación continua
del volante. En adelantamientos mantiene la línea elegida hasta completar la
maniobra y comprueba espacio antes de regresar.

Los recorridos abiertos conservan el desplazamiento lateral al apuntar al
siguiente checkpoint: ya no obligan a volver a su centro. También se corrige
el límite de seguimiento que frenaba un coche que ya circulaba al lado de su
oponente. Todos los perfiles pueden buscar adelantamientos; el perfil prudente
conserva mayor anticipación y separación.

Los límites de corredor aprovechan el ancho validable del checkpoint, con
pruebas físicas de asfalto y obstáculos. En carreteras todavía no cargadas se
mantiene inicialmente un margen conservador. Cuando los sectores llegan por
streaming, se comprueban los márgenes próximos: hasta cuatro muestras por
actualización, repartidas entre los rivales. Así un sector distante no conserva
para siempre un corredor de ancho cero calculado al comenzar la carrera.
No se reconstruye ni se carga el mapa completo para buscar una línea.

## Ventajas autorizadas de NPC

`RivalAssist.gd` modifica una copia de configuración de cada NPC de producción.
El jugador, los recursos de perfiles y `ArcadeCar.gd` no reciben esos cambios.
Estas ventajas son deliberadas y sustituyen el contrato anterior de igualdad
estricta de estadísticas entre jugador e IA.

| Parámetro | Configuración inicial |
|---|---|
| Recuperación de distancia | Empieza a 35 m; intensidad completa a 220 m detrás del jugador |
| Velocidad normal de remontada | Hasta +14 % en experto; +9.8 % en estándar |
| Ataque de adelantamiento | +6 % temporal de velocidad normal |
| Límite combinado de esas ayudas | +18 % experto; +14.4 % estándar |
| Transición de ayuda | 12 puntos porcentuales por segundo |
| Aceleración de remontada | Hasta +16 %, además del ataque de adelantamiento |
| Frenado | ×1.30 |
| Agarre lateral | ×1.20 |
| Respuesta de dirección | ×1.30 |
| Sensibilidad de dirección | ×1.10 |
| Límite de giro | ×1.12 |
| Preparación de BURST | 1 s, a partir del 90 % de la velocidad normal |
| Crecimiento de BURST | ×1.15 sobre el perfil |
| Tiempo de recarga TURBO | ×0.80 |

La ayuda de remontada usa progreso real de carrera, incluidas vueltas. Se
retira suavemente al remontar o terminar el jugador; no reduce artificialmente
la velocidad del líder. TURBO y BURST se ejecutan mediante las habilidades
reales, con sus señales y efectos existentes. El incremento máximo de +18 %
es la ayuda sobre el límite normal: BURST puede elevarlo adicionalmente según
el perfil. La planificación de curvas, el tráfico y las recuperaciones pueden
pedir una velocidad menor. No se inyectan estados visuales de BURST ni se
teletransportan rivales para alcanzarlo.

Los valores están en `config/rivals.json`, `arcade_assists`. Para desactivarlos
se puede poner `enabled=false` o ejecutar con `--ai-assists=off`. F6 muestra
telemetría, porcentaje de ayuda, distancia al jugador y decisiones de línea;
Ctrl+Alt+O permite observar rivales. Las pruebas heredadas de igualdad estricta
de estadísticas deben ejecutarse con las ayudas desactivadas.

## Recuperación y final de carrera

El aparcamiento de finalistas contempla el radio ampliado y las filas de
coches que ya se retiraron. No modifica tiempos o vueltas oficiales.
Si al usar R otro coche ocupa el último checkpoint, después de los tres
segundos se busca una posición segura lateral o hasta 8 m detrás. La búsqueda
no empuja al rival ni adelanta checkpoints y mantiene el punto exacto cuando
está disponible. La preparación inicial de la carrera conserva sus propias
comprobaciones y no utiliza esta excepción de recuperación.

## Pruebas

```powershell
godot --headless --path . --editor --import --quit
godot --headless --fixed-fps 60 --path . --script res://tests/godot_arcade_rivals.gd -- --passport-test
godot --headless --path . --script res://tests/godot_checkpoint_spheres.gd
godot --headless --path . --script res://tests/godot_d3_rules.gd
godot --headless --path . --script res://tests/godot_d3_trajectory.gd
godot --headless --fixed-fps 60 --path . --script res://tests/godot_phase_d3.gd -- --passport-test --ai-seed=730
godot --fixed-fps 60 --path . --script res://tests/godot_race_navigation.gd -- --passport-test --capture-navigation
```

Godot 4.7.2 Compatibility: pruebas arcade **40/40**; esferas **16/16**;
reglas de carrera **12/12**; trayectoria **12/12**. Los tres vehículos completan
133 controles de una pista sintética de prueba, rebasan físicamente a un coche
en movimiento de su mismo modelo, usan TURBO y BURST y no tienen contactos
entre coches ni teletransportes. El coche adelantado comienza a 120 m con el
progreso inicial correspondiente; no se modifica su progreso durante la
conducción. La ayuda de remontada observada llega aproximadamente al 6.9 % y
vuelve a cero al quedar delante. Se comprueban restauración de perfiles,+ aislamiento del jugador, sectores que llegan después de empezar, ambas
clases de parrilla y rechazo de una salida sin espacio.

Centro: seis finalistas y cinco NPC estacionados, dos vueltas, parrilla 2 × 3,
jugador sexto, sin teletransportes ni recuperaciones de checkpoints. La prueba
renderizada de navegación y recuperación con un rival bloqueando el punto de
retorno pasa **52/52** comprobaciones; encuentra un hueco lateral a 2 m sin
mover al bloqueador. Informes y capturas en `.local/artifacts/`.

Las pistas sintéticas no se distribuyen como carreras del juego. Los tiempos
de simulación fija no son un benchmark de FPS. Estas pruebas no sustituyen el
ajuste de diversión y dificultad con los recorridos del autor;
un paso ocupado o demasiado estrecho todavía puede obligar a esperar.
