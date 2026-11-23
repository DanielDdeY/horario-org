# M2 a M1 · Revisar el contrato del motor

- Fecha: 23 de noviembre de 2026, hora de Lima.
- Bloquea: la integración con el proceso real de SWI-Prolog.
- Afecta: `contracts/motor.schema.json`, el puerto JSON y `Adapters.Prolog.Proceso`.

Revisar el borrador y confirmar el comando de ejecución de `swipl`, su directorio de trabajo y los códigos de salida. El adaptador escribe un JSON UTF-8 por stdin, cierra la entrada y lee el JSON por stdout. Los mensajes de stderr se informan como error del proceso.

El borrador propone `cursoId` en las disponibilidades aprobadas, `obligatoria` para distinguir asignaciones que se retienen de restricciones parciales, y `maxVersiones` entre 1 y 4. La salida exitosa puede usar la forma individual de v3 o un arreglo `versiones` ordenado por costo. Todas las versiones del arreglo deben ser distintas y ubicar la misma cantidad de sesiones. El ejemplo `contracts/ejemplos/m2_versiones_entrada.json` y su salida ilustran una búsqueda con dos soluciones.

Validar en conjunto H03 por curso, la retirada de H10, el cálculo consecutivo de S02, las asignaciones previas de S07 y la paridad del costo. Confirmar también el significado de `factible` por versión cuando vence el tiempo y ya existe alguna solución. Si el motor usa otra forma de indicar avisos o errores, acordar esa diferencia antes de congelar el contrato.
