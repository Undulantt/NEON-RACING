# FASE B.7-R — Integración de relieve geográfico real en La Paz, B.C.S.

## 1. Rol y contexto

Actúa como ingeniero senior especializado en Godot 4, generación procedural de mundos 3D, sistemas de información geográfica (GIS), geometría computacional y optimización de videojuegos.

Estamos desarrollando un videojuego arcade de carreras callejeras ficticias ambientado en La Paz, Baja California Sur, México.

El proyecto ya cuenta con un sistema de construcción automática de la ciudad que utiliza información geográfica real para generar carreteras, edificios y elementos urbanos.

Actualmente hemos completado o avanzado en la ampliación de la zona sur del mapa.

La siguiente tarea consiste en incorporar **relieve geográfico real**, utilizando modelos digitales de elevación para representar pendientes, colinas y diferencias de altura existentes en La Paz.

El objetivo es que las carreteras sigan el relieve de la ciudad y que el jugador pueda experimentar subidas, descensos y cambios de elevación reales mientras conduce.

**Esta fase no busca mejorar la estética del terreno, sino implementar correctamente su geometría, elevaciones, integración física y rendimiento.**

---

## 2. Principio fundamental: libertad de implementación

**IMPORTANTE: Tú conoces la arquitectura y el código actual del proyecto mejor que quien redactó estas especificaciones.**

Por tanto, las tecnologías, estructuras y procedimientos descritos a continuación son propuestas técnicas, NO requisitos arquitectónicos obligatorios.

Antes de implementar cualquier solución:

1. Inspecciona los sistemas que ya desarrollaste.
2. Identifica qué componentes pueden reutilizarse.
3. Evalúa el impacto de incorporar alturas en los sistemas existentes.
4. Compara las alternativas técnicas razonables.
5. Selecciona la solución que consideres más apropiada.

### Propuesta de mejoras y alternativas

**Si durante el desarrollo descubres un método más eficiente, estable, preciso, sencillo de mantener o mejor adaptado al código existente, debes proponerlo.**

Esto incluye alternativas para:

- Obtención y procesamiento de elevaciones.
- Construcción de geometría.
- Representación y carga del terreno.
- Adaptación de carreteras.
- Colocación de edificios.
- Generación de colisiones.
- División por sectores.
- Optimización de rendimiento.
- Organización del código y de los datos.

No debes seguir una instrucción técnica literalmente si detectas que existe una solución claramente superior.

Cuando propongas una alternativa relevante, explica:

- Qué problema resuelve.
- Qué implementación propones.
- Por qué es mejor que la alternativa original.
- Qué ventajas y desventajas tiene.
- Qué sistemas existentes afectaría.
- Qué riesgos introduce.
- Qué pruebas permiten comprobar que funciona.

Tienes libertad para realizar mejoras internas compatibles con el proyecto. Para sustituciones arquitectónicas importantes, refactorizaciones extensas o cambios que puedan romper funcionalidades existentes, presenta primero la propuesta y sus consecuencias antes de ejecutarla.

**El objetivo es conseguir la mejor implementación para este proyecto, no seguir rígidamente una arquitectura predeterminada.**

---

## 3. Estado del sistema actual

Antes de iniciar, verifica el estado real del repositorio.

Como referencia, el mundo utiliza:

- Datos de OpenStreetMap para generar carreteras.
- Contornos de edificios obtenidos de Overture y OSM.
- Información urbana de INEGI.
- Conversión de coordenadas geográficas a coordenadas locales métricas.
- Escala de 1 unidad de Godot = 1 metro.
- Generación de geometrías tridimensionales.
- Colisiones físicas para carreteras y construcciones.
- Carga y descarga de edificios por sectores.
- Preparación de información geográfica fuera del juego.
- Archivos locales para ejecutar el mundo sin conexión.

Históricamente, el sistema utilizaba:

- Sectores de 256 metros.
- Carga de edificios alrededor de 650 metros.
- Descarga alrededor de 850 metros.
- Colisiones cercanas dentro de 180 metros.
- F8 para ocultar o restaurar la ciudad.

Estos valores son referencias históricas, no una descripción necesariamente actualizada. Inspecciona primero los cambios realizados durante la expansión sur.

Actualmente existe o existía una plataforma plana de seguridad que deberá considerarse durante la integración.

**No des por hecho que estas configuraciones siguen siendo exactamente las mismas. El código actual es la fuente de verdad.**

---

# 4. Objetivo principal

Implementar un sistema de elevaciones geográficas reales que permita construir un mundo tridimensional coherente con la topografía de La Paz.

El sistema deberá:

1. Obtener datos de elevación reales.
2. Convertirlos al mismo sistema de coordenadas del mundo.
3. Construir un terreno tridimensional a partir de ellos.
4. Adaptar las carreteras a las pendientes.
5. Integrar correctamente las intersecciones.
6. Colocar los edificios a sus elevaciones correspondientes.
7. Mantener las colisiones y la conducción funcionales.
8. Representar correctamente el nivel del mar y las zonas costeras.
9. Integrarse con el sistema de carga por sectores.
10. Permitir ampliar el mapa sin reconstruir manualmente el relieve.

El objetivo no es conseguir precisión topográfica centimétrica, sino reproducir correctamente las pendientes y accidentes geográficos relevantes para un videojuego de conducción.

---

# 5. Etapa R.1 — Investigación y obtención de elevaciones

Investiga qué fuentes geográficas resultan más apropiadas para el área de La Paz.

Evalúa principalmente:

**INEGI — Continuo de Elevaciones Mexicano (CEM 4.0)**

Fuente candidata principal para obtener elevaciones sobre México.

**INEGI — Modelos digitales de terreno LiDAR**

Evaluar únicamente cuando exista cobertura comprobada en los sectores relevantes.

**Copernicus DEM GLO-30**

Fuente alternativa para zonas donde los datos anteriores sean inaccesibles, incompletos o menos apropiados.

No presupongas disponibilidad ni precisión sin verificar las fuentes.

### Requisitos

- Comprobar cobertura geográfica.
- Identificar resolución horizontal.
- Investigar precisión y limitaciones verticales.
- Comprobar el sistema de coordenadas.
- Identificar el datum vertical y las unidades.
- Revisar las licencias y atribuciones.
- Descargar únicamente los datos necesarios.

No confundir resolución de muestreo con precisión vertical.

Prioriza datos que puedan procesarse localmente y distribuirse de acuerdo con sus condiciones de uso.

---

# 6. Etapa R.2 — Sistema unificado de elevación

Implementa o adapta un componente centralizado que permita consultar la elevación del terreno utilizando coordenadas del mundo.

Debe poder responder a consultas equivalentes a:

`get_height_at(world_x, world_z)`

Esta es únicamente una propuesta de interfaz. Puedes utilizar otra organización si resulta más apropiada.

### Requisitos

- Mantener la conversión geográfica utilizada actualmente.
- Preservar la escala horizontal.
- Definir una referencia vertical coherente.
- Permitir interpolar entre muestras.
- Manejar correctamente regiones sin datos.
- Evitar saltos artificiales entre sectores.
- Distinguir elevaciones reales de valores estimados.
- Mantener resultados reproducibles.

Si el origen vertical del juego necesita modificarse, documenta la transformación para evitar inconsistencias.

No generes una segunda proyección independiente de la que utilizan las carreteras.

---

# 7. Etapa R.3 — Generación del terreno

Construye un terreno tridimensional que reproduzca las elevaciones obtenidas.

Puedes evaluar:

- Generación de mallas mediante `ArrayMesh`.
- Sistemas de heightmaps.
- `Terrain3D`, si resulta compatible y conveniente.
- Geometría precalculada por sectores.
- Cualquier otra solución mejor adaptada al proyecto.

**No es obligatorio utilizar Terrain3D ni instalar nuevos complementos.**

La elección debe fundamentarse en rendimiento, integración, estabilidad y mantenimiento.

### Requisitos

- Terreno continuo.
- Sin grietas visibles entre sectores.
- Colisiones coherentes con la superficie.
- Escala vertical realista.
- Integración con el sistema actual de streaming.
- Carga de geometría optimizada.
- Capacidad de ampliar el mundo progresivamente.

Evita reconstruir geometrías pesadas durante la conducción cuando puedan generarse previamente.

---

# 8. Etapa R.4 — Adaptación de las carreteras

Esta es una de las etapas más importantes.

Actualmente las calles se construyen utilizando geometría vial sobre un mundo principalmente plano.

Necesitamos adaptar esas superficies al relieve, manteniendo su transitabilidad.

### Requisitos

1. Conservar los trazados geográficos existentes.
2. Calcular las elevaciones correspondientes a las vías.
3. Generar pendientes suaves donde corresponda.
4. Resolver correctamente las intersecciones.
5. Evitar discontinuidades entre segmentos.
6. Mantener las colisiones físicas.
7. Prevenir desniveles artificiales que hagan saltar al vehículo.
8. Evitar que el terreno atraviese las carreteras.
9. Mantener la continuidad de los recorridos.

No basta con asignar una elevación independiente a cada vértice.

Deberás evaluar si las carreteras necesitan subdivisiones adicionales, interpolación longitudinal o suavizado de pendientes.

### Situaciones especiales

Considera que:

- Los puentes pueden encontrarse por encima del terreno.
- Los pasos inferiores pueden tener una cota diferente.
- Los cruces deben tener geometría compatible.
- Las carreteras pueden requerir cortes o ajustes locales del terreno.

No aplanes indiscriminadamente todas las carreteras. Conserva las pendientes reales que contribuyan a la experiencia de conducción.

Cuando una elevación de baja resolución no represente correctamente una calle, prioriza la continuidad física y documenta el ajuste realizado.

---

# 9. Etapa R.5 — Integración de edificios

Los edificios existentes deberán posicionarse correctamente sobre el nuevo terreno.

### Requisitos

- Conservar sus coordenadas horizontales.
- Determinar la elevación correspondiente a cada construcción.
- Mantener las proporciones y alturas existentes.
- Evitar edificios flotantes.
- Evitar edificios enterrados.
- Conservar patios y geometrías interiores.
- Mantener las colisiones necesarias.

En terrenos inclinados, evalúa cómo representar una base o cimentación nivelada sin provocar deformaciones exageradas.

No deformes automáticamente los techos y paredes de las construcciones para ajustarlos a cada variación del terreno.

El sistema debe seguir siendo compatible con los edificios procedurales, landmarks y correcciones manuales existentes.

---

# 10. Etapa R.6 — Costa y nivel del mar

La Paz es una ciudad costera. El sistema debe mantener una relación coherente entre terreno, litoral y superficie del agua.

### Requisitos

- Establecer una referencia vertical consistente para el mar.
- Evitar que el terreno aparezca sobre el agua por errores de procesamiento.
- Evitar discontinuidades importantes en la costa.
- Mantener las zonas costeras transitables.
- Integrar cualquier representación de agua ya existente.
- Evitar que el sistema de elevaciones destruya la geometría costera anterior.

Si existen discrepancias entre el modelo de elevación y la geometría del litoral, evalúa una solución local justificada.

La integración de mareas, oleaje avanzado o agua físicamente simulada queda fuera de esta fase.

---

# 11. Etapa R.7 — Conducción y comportamiento físico

El sistema de conducción existente debe funcionar correctamente sobre las nuevas pendientes.

Verifica:

- Aceleración cuesta arriba.
- Frenado cuesta abajo.
- Estabilidad sobre superficies inclinadas.
- Dirección en curvas con pendiente.
- Contacto de las ruedas con la carretera.
- Comportamiento de suspensión, si existe.
- Transiciones entre superficies.
- Respuesta del coche en intersecciones.

No modifiques arbitrariamente los parámetros de conducción para compensar defectos geométricos.

Primero determina si un problema procede de la carretera, del terreno, de las colisiones o del controlador del vehículo.

Solo modifica la física del automóvil cuando exista una justificación clara y medible.

---

# 12. Etapa R.8 — Rendimiento y streaming

El mapa seguirá ampliándose, por lo que el relieve deberá funcionar tanto en el centro como en las zonas norte y sur.

### Requisitos

- Mantener o mejorar el sistema actual de sectores.
- Evitar cargar geometría innecesaria.
- Minimizar la generación durante el juego.
- Optimizar mallas y colisiones.
- Evitar pausas perceptibles al cambiar de sector.
- Preparar la arquitectura para expansiones futuras.

Si el sistema actual de sectores puede aprovecharse directamente, reutilízalo.

Si detectas que otra estrategia de partición o streaming es superior, presenta la propuesta con sus ventajas, costes y riesgos.

### Evaluación de rendimiento

Compara el sistema anterior y el nuevo.

Registra cuando sea posible:

- FPS.
- Tiempo de fotograma.
- Memoria.
- Tiempo de carga de sectores.
- Coste de colisiones.
- Cantidad de geometría generada.

Utiliza escenarios equivalentes.

No declares mejoras de rendimiento sin mediciones.

---

# 13. Estrategia de implementación incremental

No intentes convertir toda La Paz al nuevo sistema en una sola operación.

### Primera prueba: sector piloto

Selecciona un área del mapa que contenga un desnivel apreciable y una carretera transitable.

Implementa:

1. Datos de elevación.
2. Terreno 3D.
3. Carretera adaptada.
4. Colisiones.
5. Integración de edificios cercanos.
6. Prueba de conducción.

Valida este sector antes de ampliar el sistema.

### Segunda prueba: conexión entre sectores

Comprueba que el terreno, las carreteras y las colisiones mantienen continuidad al cruzar los límites de carga.

### Tercera prueba: integración urbana

Aplica el sistema a una región mayor que combine construcciones, intersecciones y espacios abiertos.

### Cuarta prueba: integración general

Extiende el sistema a los sectores actuales del mundo, incluyendo la ampliación sur.

Evita modificar simultáneamente todos los sistemas sin disponer de pruebas intermedias.

---

# 14. Compatibilidad y seguridad

Preserva las funcionalidades existentes del proyecto:

- Conducción libre.
- Controles del automóvil.
- Carreteras.
- Edificios.
- Colisiones.
- Sistema de sectores.
- Herramientas de depuración.
- Sistema de generación procedural.
- Datos geográficos previamente procesados.

No sobrescribas los datos originales.

Mantén la posibilidad de comparar el mundo anterior con el nuevo, por ejemplo mediante una opción de depuración o una rama de Git.

Si la plataforma plana anterior debe sustituirse, asegúrate de que no queden superficies físicas duplicadas que interfieran con el vehículo.

No elimines un sistema anterior hasta verificar su reemplazo.

---

# 15. Criterios de aceptación

La fase podrá considerarse terminada cuando:

- [ ] El proyecto utiliza datos reales de elevación verificados.
- [ ] El terreno representa las pendientes de las zonas implementadas.
- [ ] Los sectores del terreno no presentan grietas ni saltos relevantes.
- [ ] Las carreteras se adaptan correctamente al relieve.
- [ ] Las intersecciones mantienen continuidad física.
- [ ] Los edificios se encuentran correctamente posicionados.
- [ ] El mar y la costa conservan una referencia vertical coherente.
- [ ] El automóvil puede recorrer pendientes sin errores graves.
- [ ] Las colisiones funcionan correctamente.
- [ ] El streaming sigue funcionando.
- [ ] La generación puede reproducirse desde los datos locales.
- [ ] Las herramientas de depuración anteriores continúan funcionando.
- [ ] El rendimiento es aceptable y está documentado.
- [ ] Se han ejecutado pruebas de regresión.
- [ ] La arquitectura permite ampliar el relieve a nuevas zonas.

No marques tareas como completadas si no pudieron verificarse.

---

# 16. Entregables esperados

Al finalizar, proporciona:

1. Código de integración de elevaciones.
2. Scripts de preparación y conversión geográfica.
3. Datos de elevación procesados para el mundo actual.
4. Sistema de generación o importación del terreno.
5. Integración de carreteras y edificios.
6. Colisiones actualizadas.
7. Documentación de fuentes y referencias verticales.
8. Pruebas realizadas y resultados.
9. Comparación de rendimiento.
10. Limitaciones identificadas.
11. Recomendaciones de optimización futura.

Actualiza la documentación técnica del proyecto para que otros agentes puedan comprender y mantener el sistema.

---

# 17. Instrucciones finales

Antes de comenzar la implementación, **realiza una auditoría del código existente y presenta tu propuesta técnica**.

Tu propuesta debe responder:

1. ¿Cuál es la mejor fuente de elevación disponible para nuestro mapa?
2. ¿Qué sistemas actuales deberán modificarse?
3. ¿Podemos reutilizar el sistema de generación geográfica y sectores?
4. ¿Conviene generar nuestras propias mallas o utilizar un complemento especializado?
5. ¿Cómo evitaremos romper las carreteras existentes?
6. ¿Cómo resolveremos la integración de edificios y colisiones?
7. ¿Cuál es la estrategia más eficiente para incorporar el relieve?
8. ¿Qué alternativas técnicas encontraste y por qué recomiendas una sobre las otras?

**No necesito que sigas una solución predeterminada. Necesito que evalúes técnicamente el proyecto y elijas el procedimiento más eficiente y mantenible.**

Si descubres una oportunidad para simplificar la arquitectura, reducir el procesamiento, aumentar el rendimiento o mejorar la precisión geográfica, debes indicarlo.

Si una propuesta original resulta innecesariamente compleja, puedes descartarla justificadamente.

Si identificas riesgos importantes, comunícalos antes de realizar cambios destructivos.

Después de presentar y validar la estrategia, implementa la solución progresivamente, ejecutando pruebas y documentando cada etapa.

**El resultado esperado es un sistema funcional de relieve real, adaptado a la arquitectura actual del videojuego y preparado para futuras expansiones de La Paz.**