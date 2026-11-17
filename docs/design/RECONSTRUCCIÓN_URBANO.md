# FASE B.6 — RECONSTRUCCIÓN GEOGRÁFICA Y ENRIQUECIMIENTO URBANO

## 1. Rol y objetivo general

Actúa como un **ingeniero senior de desarrollo de videojuegos especializado en Godot 4, sistemas de información geográfica (GIS), generación procedural de entornos urbanos, geometría computacional y optimización de mundos 3D**.

Estás trabajando sobre un proyecto existente: un videojuego arcade de carreras clandestinas ficticias, ambientado en una representación de **La Paz, Baja California Sur, México**.

Tu objetivo es mejorar la precisión geográfica, urbanística y visual del mapa actual, permitiendo que un jugador reconozca las calles, construcciones y lugares importantes de La Paz mientras conduce.

**No debes reconstruir el proyecto desde cero ni sustituir sistemas que ya funcionan correctamente.**

Esta fase debe ampliar la arquitectura existente de generación urbana sin comprometer el rendimiento, la conducción ni la compatibilidad con futuras fases.

---

## 2. Estado actual del proyecto

El proyecto ya cuenta con un sistema funcional de generación geográfica dividido en dos etapas.

### 2.1. Preparación de datos

Los datos geográficos se descargan y procesan fuera de Godot.

Actualmente se utilizan:

- **OpenStreetMap:** calles, geometría vial y datos relacionados.
- **Overture Maps y OSM:** contornos reales de edificios.
- **INEGI:** manzanas urbanas utilizadas como referencia para generar construcciones ficticias.

Las fuentes originales se almacenan con información de procedencia y hashes de verificación.

### 2.2. Sistema de coordenadas

Los datos geográficos se convierten a coordenadas locales tomando como referencia un origen fijo de La Paz.

En Godot:

**1 unidad = 1 metro.**

Debes identificar y reutilizar exactamente el sistema de coordenadas, proyección, orientación de ejes y origen que ya utiliza el proyecto.

No crees una segunda transformación geográfica independiente.

### 2.3. Geometría vial

Las carreteras se generan mediante:

- Trazados obtenidos de OpenStreetMap.
- Anchuras reales cuando están disponibles.
- Anchuras estimadas cuando faltan datos.
- Unión geométrica de superficies viales antes de triangulación.
- Generación de colisiones físicas estáticas.

Estas funcionalidades deben conservarse.

### 2.4. Edificios actuales

El sistema dispone de los siguientes datos de referencia:

| Elemento | Cantidad |
|---|---:|
| Edificios de huellas reales | 7,612 |
| Construcciones ficticias | 167 |
| Superficie aproximada del mapa | 3 × 3 km |

Los edificios se crean mediante extrusión de polígonos, con paredes verticales y techos triangulados.

Los patios registrados se mantienen abiertos y las alturas son estimadas cuando faltan datos reales.

Estas cifras representan el estado inicial para comparar resultados; no son cantidades inmutables si se detectan errores documentados.

### 2.5. Carga por sectores

El sistema utiliza actualmente:

- 75 sectores de edificios.
- Tamaño de sector: 256 metros.
- Radio aproximado de carga: 650 metros.
- Radio aproximado de descarga: 850 metros.
- Radio de colisiones activas de edificios cercanos: 180 metros.

Las carreteras permanecen cargadas mientras el jugador circula.

La tecla **F8** permite ocultar y restaurar los edificios sin eliminar carreteras ni la plataforma de seguridad.

### 2.6. Limitaciones conocidas

Actualmente:

- Los edificios tienen apariencias muy básicas.
- Muchas alturas son estimadas.
- No existe una clasificación urbana suficientemente detallada.
- Los lugares importantes no siempre se distinguen del resto.
- No hay fachadas específicas según el tipo de construcción.
- La costa y el mar no están representados adecuadamente.
- El terreno utiliza una plataforma plana.
- Las elevaciones reales no están implementadas.
- La identidad retrofuturista definitiva se desarrollará posteriormente.

---

# 3. Objetivos de la nueva fase

Desarrollar un **sistema híbrido de reconstrucción urbana**, donde la geometría del mundo se construya utilizando información geográfica real y se complete mediante generación procedural cuando sea necesario.

El sistema deberá ser capaz de:

1. Identificar lugares importantes y establecimientos reales dentro del sector existente.
2. Asociar esos lugares a edificios o parcelas cuando haya evidencia suficiente.
3. Mejorar la clasificación de las construcciones.
4. Representar diferentes tipos de edificios con geometrías simplificadas pero reconocibles.
5. Identificar y priorizar monumentos, espacios públicos y referencias culturales.
6. Representar de forma básica la costa y las áreas urbanas no edificadas.
7. Permitir corregir manualmente construcciones o lugares particulares sin modificar los datos originales.
8. Mantener un sistema reproducible, optimizado y compatible con las futuras expansiones del mapa.

**Prioridad principal:** fidelidad geográfica y reconocimiento de la ciudad antes que detalle arquitectónico.

El mapa continuará limitado inicialmente al sector actual de 3 × 3 km.

---

# 4. Fuentes geográficas

## 4.1. Overture Maps — Buildings

Utilizar la información que ya existe e inspeccionar si se están aprovechando todos los atributos disponibles.

Buscar, cuando existan:

- Identificador estable.
- Geometría del edificio.
- Altura.
- Número de pisos.
- Tipo de construcción.
- Procedencia.
- Otros atributos útiles para distinguir edificios.

Cuando un atributo no esté disponible, utilizar un valor estimado y registrar explícitamente que no es una medición real.

No sobrescribir información verificada con datos procedurales.

## 4.2. Microsoft Global ML Building Footprints

Evaluar este conjunto como una fuente complementaria para verificar edificios ausentes, mal representados o incompletos.

**Importante:** Overture puede incorporar contornos procedentes de Microsoft.

Por ello, no debes mezclar ambos conjuntos indiscriminadamente.

Antes de importar nuevos edificios:

1. Comparar los contornos existentes.
2. Identificar construcciones duplicadas.
3. Evaluar diferencias geométricas.
4. Incorporar únicamente geometrías adicionales o correcciones justificadas.
5. Conservar un registro de los cambios.

No añadas un edificio si su ubicación ya está representada correctamente.

## 4.3. Overture Maps — Places

Incorporar la capa de puntos de interés para identificar:

- Restaurantes y cafeterías.
- Hoteles y alojamientos.
- Tiendas y establecimientos comerciales.
- Escuelas.
- Hospitales y centros médicos.
- Instituciones públicas.
- Espacios culturales.
- Monumentos y sitios de interés.
- Otros establecimientos relevantes.

Inspecciona el esquema vigente de los datos antes de implementar su importador; no supongas que campos de versiones anteriores siguen disponibles.

## 4.4. INEGI — DENUE

Utilizar el Directorio Estadístico Nacional de Unidades Económicas como fuente complementaria para identificar establecimientos mexicanos.

Cuando la información esté disponible, obtener:

- Nombre del establecimiento.
- Actividad económica.
- Coordenadas.
- Identificador.
- Categoría.
- Otros atributos necesarios.

No necesitas representar todos los negocios.

Prioriza aquellos visibles desde las carreteras y aquellos que contribuyan al reconocimiento de La Paz.

## 4.5. OpenStreetMap

Aprovechar información adicional sobre:

- Parques y jardines.
- Plazas.
- Áreas peatonales.
- Estacionamientos.
- Espacios recreativos.
- Edificios públicos.
- Monumentos.
- Equipamiento urbano.
- Línea de costa.
- Usos del suelo y superficies urbanas.

Conservar y ampliar el procesamiento actual cuando sea necesario.

## 4.6. Google Maps y Google Earth

Google Maps puede utilizarse como herramienta de consulta o referencia visual únicamente dentro de los usos autorizados por sus términos.

**No implementar scraping de Google Maps, extracción de geometría de Google Earth, descarga de modelos 3D protegidos ni creación de una base local permanente de Places mediante mecanismos no autorizados.**

Priorizar conjuntos de datos abiertos que permitan su procesamiento y distribución dentro del videojuego, respetando sus licencias y atribuciones.

---

# 5. Etapa B.6.1 — Auditoría e integración de datos urbanos

## Objetivo

Crear una representación geográfica unificada y verificable de las construcciones, establecimientos y puntos de interés existentes.

## Implementación

Inspeccionar los archivos, scripts y formatos que ya utiliza el generador.

Crear o extender un proceso de preparación de datos que:

1. Descargue o procese los puntos de interés del sector.
2. Normalice nombres, categorías e identificadores.
3. Convierta las coordenadas al sistema métrico existente.
4. Compare los registros procedentes de diferentes fuentes.
5. Identifique posibles duplicados.
6. Asocie puntos de interés con construcciones existentes.
7. Registre los casos ambiguos para revisión posterior.

### Asociación entre puntos de interés y edificios

No asumas que cada marcador representa una construcción independiente.

Un mismo edificio puede contener varios establecimientos.

La asociación debe considerar:

- Si el punto está dentro del contorno del edificio.
- Distancia al contorno.
- Dirección disponible.
- Categoría del lugar.
- Concordancia con otros registros.
- Posibles errores en las coordenadas.

Utiliza puntuaciones de confianza documentadas.

Si no existe suficiente evidencia, conserva el punto de interés sin asociarlo arbitrariamente.

## Salidas esperadas

Datos procesados que permitan consultar:

- Identificador del edificio.
- Geometría.
- Altura real o estimada.
- Categoría de construcción.
- Puntos de interés asociados.
- Fuente original.
- Calidad o confianza de asociación.
- Necesidad de revisión manual.

Estos datos deben almacenarse en un formato local compatible con el flujo actual del proyecto.

---

# 6. Etapa B.6.2 — Clasificación y reconstrucción arquitectónica

## Objetivo

Mejorar la variedad visual de los edificios sin necesidad de obtener modelos 3D externos de cada construcción.

## Categorías iniciales

Implementar como mínimo las siguientes categorías:

| Categoría | Tratamiento visual |
|---|---|
| Residencial | Viviendas de uno o varios niveles, techos planos y variaciones moderadas |
| Comercial | Fachadas con locales, escaparates y accesos |
| Restaurante | Frente comercial, ventanales y elementos distintivos |
| Hotel | Volumen adecuado a su tamaño, accesos y fachada diferenciada |
| Institucional | Geometría sobria y proporciones acordes con los datos disponibles |
| Cultural | Tratamiento especial cuando existan referencias verificadas |
| Industrial o almacén | Volúmenes anchos, techos sencillos y menos decoración |
| Desconocido | Geometría procedural genérica |

Estas categorías son reglas visuales, no afirmaciones de que un edificio concreto tiene esa arquitectura.

## Reglas de generación

El sistema debe utilizar:

- El contorno real del edificio como base.
- Su altura documentada cuando exista.
- Una estimación cuando la altura sea desconocida.
- La categoría urbana.
- La superficie de la construcción.
- El entorno y el uso del suelo cuando existan datos.
- Un generador determinista para las variaciones.

Las alturas estimadas deben estar sujetas a parámetros configurables.

El generador puede añadir:

- Ventanas simplificadas.
- Puertas.
- Divisiones de fachada.
- Colores de paredes.
- Techos.
- Toldos.
- Elementos arquitectónicos básicos.

No crear geometrías complejas innecesarias.

## Identidad arquitectónica de La Paz

Construir una biblioteca procedural orientada a las características visuales de La Paz.

Priorizar:

- Construcciones de baja altura donde corresponda.
- Techos predominantemente planos cuando sea coherente.
- Materiales y colores apropiados para una ciudad costera.
- Locales comerciales a nivel de calle.
- Bardas, patios y estacionamientos donde los datos lo permitan.
- Variaciones de edificios más grandes en corredores comerciales.

No aplicar una única distribución arquitectónica a toda la ciudad.

No inventar una altura exacta o una fachada específica de un lugar real basándose únicamente en su categoría.

## Restricciones geométricas

Los edificios no deben:

- Invadir las carreteras existentes.
- Ocupar el mar.
- Invadir parques o espacios protegidos conocidos.
- Bloquear el recorrido del jugador por errores de generación.
- Destruir patios interiores presentes en las geometrías originales.

Mantener la compatibilidad con polígonos complejos y huecos interiores.

---

# 7. Etapa B.6.3 — Lugares emblemáticos y puntos de referencia

## Objetivo

Incorporar un sistema que permita que determinados lugares de La Paz sean reconocibles durante la conducción.

## Sistema de landmarks

Crear un registro independiente de puntos de referencia importantes.

Cada landmark podrá definir:

- ID estable.
- Nombre.
- Coordenadas geográficas.
- Posición local en Godot.
- Categoría.
- Fuente de información.
- Geometría asociada, si existe.
- Modelo 3D personalizado opcional.
- Orientación y escala.
- Nivel de prioridad.
- Estado de verificación.

## Niveles de fidelidad

**Nivel 1 — Prioridad máxima**

Lugares emblemáticos visibles desde los principales recorridos.

Deberán tener ubicación validada y una silueta reconocible mediante geometría simplificada.

**Nivel 2 — Prioridad intermedia**

Edificios y espacios urbanos identificables, como hoteles, mercados, centros comerciales o instalaciones públicas.

Se generarán utilizando reglas especiales de su categoría y datos disponibles.

**Nivel 3 — Construcciones secundarias**

Edificios residenciales y establecimientos menores.

Permanecerán principalmente bajo generación procedural.

## Selección inicial

Investigar y seleccionar entre cinco y diez puntos de referencia situados realmente dentro del sector actual de 3 × 3 km.

Dar preferencia a lugares cercanos a las carreteras transitables y a los futuros recorridos de carrera.

Los lugares propuestos deberán verificarse antes de incluirlos en el juego.

No inventar coordenadas ni suponer que un monumento está dentro del sector.

## Modelos especiales

El sistema deberá permitir sustituir un edificio procedural por un modelo personalizado `.glb` o por una escena de Godot.

La sustitución debe conservar su identificación geográfica y no alterar el resto del mapa.

No es necesario construir modelos arquitectónicos detallados en esta fase.

---

# 8. Etapa B.6.4 — Costa, espacios abiertos y terreno

## Objetivo

Mejorar la geografía visible, especialmente en el corredor costero, sin intentar todavía una simulación topográfica completa.

## Línea de costa

Obtener un contorno costero apropiado para el sector actual utilizando información geográfica autorizada.

Si el sector incluye parte del litoral:

- Delimitar tierra y mar.
- Evitar edificios sobre el agua.
- Generar una superficie de agua básica.
- Representar zonas costeras y áreas abiertas cuando existan datos.
- Evitar que el suelo plano se vea como tierra continua sobre el mar.

Las geometrías de costa deberán ajustarse al mismo sistema de coordenadas que el resto del mapa.

## Espacios urbanos

Representar de forma simplificada:

- Parques.
- Plazas.
- Explanadas.
- Estacionamientos.
- Terrenos vacíos registrados.
- Áreas peatonales.
- Zonas ajardinadas.

El sistema debe evitar rellenar automáticamente estas superficies con construcciones ficticias.

## Elevaciones

Evaluar fuentes de elevación abiertas y su precisión real para el área estudiada.

No modificar todavía todo el sistema de carreteras para introducir relieve sin comprobar su efecto en:

- Colisiones.
- Física de conducción.
- Intersecciones.
- Edificios.
- Plataforma de seguridad.

Si la incorporación de terreno real es demasiado invasiva, documentar una propuesta técnica y aplazarla a una fase posterior.

**La prioridad de esta etapa es corregir la separación visual entre tierra, agua y espacios urbanos.**

---

# 9. Etapa B.6.5 — Sistema de correcciones manuales

## Objetivo

Permitir mejorar lugares concretos sin modificar los datos originales ni perder los cambios después de regenerar el mapa.

Crear un archivo o conjunto de archivos de overrides geográficos.

Cada corrección podrá:

- Modificar la altura de un edificio.
- Cambiar su categoría.
- Cambiar su color o estilo visual.
- Ajustar posición u orientación cuando esté justificado.
- Corregir una asociación con un punto de interés.
- Desactivar una construcción incorrecta.
- Asignar un modelo personalizado.
- Marcar un edificio como prioritario.

## Requisitos

1. Nunca sobrescribir directamente los datos geográficos originales.
2. Aplicar las correcciones después del procesamiento automático.
3. Conservar identificadores estables siempre que sea posible.
4. Registrar la razón y procedencia de cada corrección.
5. Detectar overrides que hayan quedado huérfanos tras una actualización de datos.
6. Mantener el formato legible y versionable mediante Git.

No necesitas desarrollar un editor visual completo en esta fase si una herramienta simple de edición de datos resulta más eficiente.

No obstante, la arquitectura deberá permitir incorporar uno posteriormente.

---

# 10. Etapa B.6.6 — Integración y optimización en Godot

## Compatibilidad obligatoria

Preservar el sistema de sectores existente.

Configuración de referencia:

| Parámetro | Valor actual |
|---|---:|
| Tamaño de sector | 256 m |
| Radio de carga | 650 m |
| Radio de descarga | 850 m |
| Radio de colisiones | 180 m |

No modificar estos valores sin una justificación respaldada por pruebas.

## Optimización

Aplicar técnicas apropiadas de Godot 4:

- Agrupación de geometrías estáticas cuando sea conveniente.
- `MultiMeshInstance3D` para elementos repetidos que compartan geometría y material.
- Reducción de detalles en construcciones lejanas.
- Generación de datos pesados fuera del juego.
- Minimización de reconstrucciones innecesarias durante la conducción.
- Carga progresiva de sectores cuando sea necesario.

Evitar que añadir ventanas, letreros o detalles procedurales multiplique innecesariamente los nodos y llamadas de dibujo.

La ciudad debe poder mostrarse sin bloquear perceptiblemente la conducción durante la carga de sectores.

## Colisiones

Mantener las colisiones únicamente donde sean útiles.

Los detalles decorativos de fachadas no deben generar automáticamente nuevos cuerpos físicos.

## Herramientas de depuración

Conservar **F8**.

Incorporar un modo adicional de depuración que permita consultar, como mínimo:

- Identificador de construcción.
- Fuente de datos.
- Categoría.
- Altura y si es estimada.
- Puntos de interés asociados.
- Sector al que pertenece.
- Presencia de overrides.
- Estado de confianza o validación.

Siempre que sea posible, permitir visualizar edificios y puntos de interés diferenciados por categoría o fuente.

---

# 11. Arquitectura y organización de datos

Antes de implementar, inspecciona la arquitectura existente.

No introduzcas estructuras redundantes si ya existen componentes equivalentes.

La solución debe distinguir claramente entre:

**A. Datos originales**

Archivos descargados y sus metadatos, sin modificación.

**B. Datos procesados**

Geometrías normalizadas, puntos de interés asociados, categorías y registros espaciales.

**C. Configuración procedural**

Reglas de alturas, fachadas, materiales y variaciones.

**D. Correcciones manuales**

Overrides persistentes que tengan prioridad sobre la generación automática.

**E. Representación dentro de Godot**

Mallas, materiales, colisiones y sectores de mundo.

**F. Validación**

Pruebas geográficas, métricas de calidad y comparaciones con resultados anteriores.

Mantener la generación reproducible utilizando semillas deterministas cuando corresponda.

El juego debe continuar funcionando exclusivamente con archivos locales ya preparados.

No incorporar dependencias obligatorias de servicios externos durante la partida.

---

# 12. Pruebas y criterios de calidad

## 12.1. Exactitud geográfica

Verificar que:

- Las calles y edificios compartan un sistema de coordenadas consistente.
- No existan desplazamientos sistemáticos entre capas.
- Las coordenadas de puntos de interés se transformen correctamente.
- Los edificios no invadan indebidamente las calzadas.
- Los edificios no aparezcan sobre zonas de agua identificadas.
- Los espacios protegidos se mantengan libres.

Crear pruebas automáticas para validar estas condiciones.

Las tolerancias geométricas deberán definirse y documentarse.

## 12.2. Datos y asociaciones

Verificar que:

- Los duplicados se detecten.
- Los puntos de interés ambiguos no se asignen de forma arbitraria.
- Las fuentes permanezcan registradas.
- Las categorías puedan inspeccionarse.
- Las alturas estimadas sean distinguibles de las reales.
- Las correcciones manuales se mantengan después de regenerar los datos.

Generar estadísticas de cobertura, duplicados y asociaciones.

## 12.3. Validación visual

Preparar comparaciones del mismo sector antes y después de la implementación.

Utilizar posiciones de cámara equivalentes.

Comparar:

- Distribución de edificios.
- Alturas.
- Categorías.
- Espacios abiertos.
- Costa.
- Lugares importantes.
- Coherencia entre calles y construcciones.

No considerar válida una mejora únicamente porque aumente el número de objetos.

## 12.4. Rendimiento

Antes de efectuar cambios importantes, medir el estado actual del proyecto.

Registrar:

- FPS promedio.
- Tiempo de fotograma.
- Tiempo de carga de sectores.
- Consumo de memoria.
- Cantidad de nodos y objetos físicos relevantes.

Después comparar utilizando un mismo recorrido reproducible.

Como objetivo inicial, evitar una degradación superior al 10–15 % del tiempo de fotograma respecto a la versión anterior, bajo condiciones equivalentes.

Si esto no es posible, identificar el motivo y optimizar antes de ampliar el alcance.

No ocultar problemas de rendimiento ni presentar cifras de pruebas que no se hayan ejecutado.

## 12.5. Pruebas de regresión

Confirmar que:

- El automóvil puede recorrer las carreteras existentes.
- Las colisiones funcionan.
- Las curvas e intersecciones siguen siendo transitables.
- F8 continúa funcionando.
- Los sectores se cargan y descargan correctamente.
- El proyecto se abre sin errores relevantes.
- El mapa mantiene su escala y orientación.

---

# 13. Priorización de implementación

Desarrollar en el siguiente orden:

| Prioridad | Trabajo |
|---|---|
| P0 | Auditar el sistema actual y registrar una línea base |
| P0 | Importar y normalizar puntos de interés |
| P0 | Asociar puntos de interés y edificios sin introducir duplicados |
| P0 | Implementar clasificación y fachadas procedurales simples |
| P0 | Crear overrides persistentes |
| P1 | Mejorar la costa, espacios abiertos y lugares importantes |
| P1 | Incorporar entre cinco y diez landmarks verificados |
| P1 | Optimizar y validar el sistema actualizado |
| P2 | Evaluar elevaciones reales |
| P2 | Incorporar modelos arquitectónicos más detallados |

Las tareas P2 no son requisitos para cerrar esta fase.

Tampoco forma parte de esta fase terminar la estética neón ochentera. Esa responsabilidad permanece en la **Fase E — Identidad visual y sonora**.

---

# 14. Criterios de salida de la Fase B.6

La fase se considerará completada cuando:

1. El mapa actual de 3 × 3 km continúe funcionando.
2. Se hayan integrado puntos de interés reales desde fuentes compatibles.
3. Exista una clasificación de edificios que afecte visiblemente a su apariencia.
4. Los edificios reconocidos como comercios, hoteles u otras categorías dejen de representarse exclusivamente como bloques genéricos.
5. Exista un sistema de lugares emblemáticos extensible.
6. Se haya mejorado la representación de costa y espacios abiertos presentes en el sector, cuando los datos lo permitan.
7. Se puedan corregir construcciones específicas sin alterar las fuentes originales.
8. La generación siga siendo determinista y reproducible.
9. Los datos estén disponibles localmente durante la partida.
10. El rendimiento y las mecánicas previamente implementadas se mantengan dentro de los objetivos acordados.
11. Se documenten las limitaciones, datos no verificados y mejoras pendientes.

**El objetivo final no es recrear cada casa con exactitud fotográfica. Es construir una representación geográficamente coherente y visualmente reconocible de La Paz.**

---

# 15. Flujo de trabajo obligatorio del agente

Antes de escribir código:

1. Inspecciona el repositorio real.
2. Identifica las herramientas existentes de descarga y procesamiento geográfico.
3. Localiza el generador de geometría y el cargador de sectores.
4. Revisa la implementación de colisiones.
5. Identifica el sistema de coordenadas.
6. Revisa los datos disponibles y las licencias correspondientes.
7. Evalúa cuáles de los requisitos ya están parcialmente implementados.
8. Establece una línea base de funcionamiento y rendimiento.

Después:

- Divide el trabajo en cambios pequeños y verificables.
- No elimines implementaciones existentes sin necesidad.
- Prioriza extender componentes actuales.
- Documenta cualquier cambio estructural.
- Ejecuta pruebas después de cada etapa.
- Mantén actualizada la documentación técnica.
- Utiliza Git para conservar puntos de restauración.
- Informa de las limitaciones encontradas sin inventar resultados.

Si una fuente externa no puede descargarse o verificarse, no fabriques datos para simular que la integración funcionó. Utiliza datos locales existentes para las pruebas y documenta claramente la limitación.

## Entregables finales

Al completar la fase proporciona:

1. Código implementado e integrado.
2. Scripts de preparación geográfica actualizados.
3. Datos procesados de prueba.
4. Sistema de categorías y fachadas.
5. Sistema de landmarks.
6. Sistema de overrides.
7. Herramientas de depuración.
8. Resultados de validación.
9. Comparación de rendimiento.
10. Documentación de fuentes y licencias.
11. Resumen de cambios y tareas pendientes.

**Comienza auditando el proyecto existente y proponiendo el plan de implementación basado en los archivos reales. Después ejecuta las etapas P0 de manera incremental, sin iniciar todavía los trabajos P2.**