# Fase E — expansión a la ciudad

## Implementación

F5 / `Main.tscn` inicia ahora `NightCity.gd`, una extensión ligera del mundo existente. Conserva el punto de aparición, la geografía, el relieve, la conducción y las colisiones. El piloto sigue disponible por separado. `--day-world` permite abrir la escena principal sin la capa nocturna; el modo histórico sin sectores urbanos conserva su funcionamiento.

Se reutilizan NightStyle, RetroLook, RoadNeon, los efectos de conducción y los materiales existentes. La estética alcanza los sectores a medida que el sistema original los carga; no se instancian todas las fachadas ni todos los árboles de la ciudad a la vez. Las ventanas residenciales son cálidas y los acentos comerciales rosa/cian. No se añaden nombres de negocios.

El asfalto utiliza ejes locales con los anchos arcade existentes (hasta 64 segmentos por sector); los bordes se recortan sobre la malla elevada. La señalización es estilizada, no información oficial sobre carriles. Los límites artificiales de sector no reciben líneas transversales. La construcción del neón cede el control entre cuadros para evitar realizar toda la operación de una vez. Los sectores próximos se atienden primero; durante la carga inicial o un teletransporte puede verse aparecer decoración progresivamente.

## Farolas y vegetación

`CityFurniture.gd` comparte tres mallas originales: farola angular, palmera curva y árbol de copa facetada verde azulada. Se dibujan mediante MultiMesh por sector, sin sombras individuales ni colisiones adicionales.

- Candidatos deterministas a lo largo de vías transitables, aproximadamente cada 38 m, alternando lados. Se excluyen sendas, escalones, pistas y vías de servicio.
- Separación de extremos de tramo de al menos 10 m, aumentada según la anchura vial. Se comprueba además la distancia a las demás calles próximas para no ocupar intersecciones.
- Las bases quedan fuera del asfalto; las farolas se orientan hacia la calle. Las plantas se colocan más retiradas, en el lado opuesto al candidato de farola.
- Se comprueban las huellas de edificios de los sectores vecinos, ya ajustadas por el trazado arcade, con margen para la copa.
- Raycast contra el terreno cargado y rechazo de asfalto, ausencia de apoyo y pendientes fuertes. No se colocan elementos sobre agua sin soporte de terreno.
- Separación mínima de 10 m entre elementos, también al cruzar sectores, mediante un índice compartido que se limpia al descargar.
- Máximo por sector: 24 farolas y 14 plantas. Estos son límites, no objetivos: si no hay espacio adecuado, se omiten candidatos.
- Palmeras favorecidas en la vía del Malecón configurada y zonas bajas; árboles en las calles interiores. Son reglas artísticas, no un inventario botánico ni posiciones levantadas en campo.
- Cuatro luces reales como máximo en toda la escena, sin sombras y solo para farolas cercanas a menos de 70 m. F8 también las apaga. El resto mantiene su aspecto con materiales, sin luz dinámica individual.
- Vegetación visible hasta 280 m; farolas hasta 360 m. Las mallas y materiales se reutilizan; los nodos de decoración se descargan con el sector urbano.

## Verificación acotada

Prueba integrada en Godot 4.7.2, Compatibility, costa e interior, con capturas revisadas. Informe: `phase_e_city_validation.json`, PASS. Costa: 17 sectores decorados, 260 farolas, 19 palmeras y 97 árboles en el conjunto cargado (no todos visibles a la vez); tres luces activas. Interior: 31 sectores, 628 farolas y 243 árboles; cuatro luces activas. Se retiraron 16 sectores anteriores al desplazarse. Comprobados límites por sector, ausencia de colisiones nuevas y F8.

La primera revisión encontró dos problemas, corregidos: candidatos de plantas descartados por coincidir con farolas y una referencia compartida que vaciaba el índice de calles al pasar de sector.

La construcción inicial de neón llegó a ocupar 107 ms continuos. Tras repartirla entre cuadros, el mayor intervalo registrado fue 12,822 ms. El presupuesto de 4 ms es cooperativo, no una garantía estricta: recortes y subida de malla son operaciones indivisibles. El tiempo total de una construcción puede incluir varios cuadros (2,504 s máximos observados con esperas). No se realizó un benchmark general de conducción ni una inspección individual de los 541 sectores; estas cifras no garantizan ausencia de tirones en toda la ciudad.

Capturas: [conducción costera](evidence/phase_e_city_driver.png), [sector costero](evidence/phase_e_city_sector.png), [interior con árbol](evidence/phase_e_city_inland.png).

La geometría, datos y controlador se conservaron. Las ubicaciones de farolas y plantas son decorativas y conservadoras; ajustar densidad por barrio queda disponible sin rediseñar manualmente cada sector.
