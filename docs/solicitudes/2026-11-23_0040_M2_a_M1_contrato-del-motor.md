# M2 a M1 · Acuerdos del contrato del motor

- Fecha: 23 de noviembre de 2026, hora de Lima.
- Estado: decisiones aprobadas. Quedan pendientes los ajustes del esquema y del adaptador, y la verificación con SWI-Prolog.
- Alcance: M1 implementa el motor Prolog. M2 mantiene el núcleo y el adaptador Haskell.

## Decisiones aprobadas

1. **Salida exitosa.** M1 emite siempre un arreglo `versiones`, incluso si contiene una única solución. `maxVersiones` indica cuántas versiones se solicitan en total, de 1 a 4. Haskell mantiene la lectura del formato individual durante la transición.
2. **Fijas completas incompatibles.** Al regenerar conservando cambios o al completar, Haskell devuelve el conflicto antes de llamar al motor. El coordinador decide qué corregir. Prolog debe respetar las asignaciones obligatorias que sí recibe.
3. **Tiempo límite.** Si vence el tiempo con alguna solución válida, se devuelve un lote `factible` con las versiones distintas encontradas que asignan la misma cantidad de sesiones que la primera, ordenadas por costo blando. Una versión ya demostrada óptima conserva su estado `optimo`. El estado `timeout` se usa cuando vence el tiempo sin una solución válida.
4. **Ejecución y errores.** El motor recibe un JSON UTF-8 por `stdin` y responde con un JSON por `stdout`. Con código de salida 0, Haskell acepta el JSON válido y conserva `stderr` como diagnóstico. Un código distinto de 0 indica un fallo de ejecución. Una respuesta JSON con `estado: "error"` incluye `mensaje` y `tiempoMs`.
5. **Entrada.** Cada franja aprobada incluye `cursoId`, cada fija incluye `obligatoria` y cada solicitud incluye `maxVersiones`. Con `obligatoria: true` se requieren la sesión, el profesor, el aula, el día y el inicio. Con `false` se respetan los campos informados si la sesión se ubica. Una restricción parcial incompatible puede dejar la sesión pendiente.

## Coordinación pendiente

- **M1** debe indicar el comando exacto de `swipl` y su directorio de trabajo, e implementar el motor con estos acuerdos.
- **M2** debe reflejar los acuerdos en el [esquema JSON](../../contracts/motor.schema.json) y en el adaptador Haskell, incluido el tratamiento de `stderr` y de `tiempoMs` en los errores.
- **M1 y M2** deben verificar con el motor real H03 por curso, el catálogo H01–H09, S02 con pares consecutivos, S07 y la paridad del costo. El ejemplo de [entrada](../../contracts/ejemplos/m2_versiones_entrada.json) y [salida](../../contracts/ejemplos/m2_versiones_salida.json) muestra dos versiones. La [guía de lectura](../ANTES_DE_DESARROLLAR.md#decisiones-aprobadas-del-contrato-del-motor) enlaza los reportes con el contexto completo.
