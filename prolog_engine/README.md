# M1 · Motor Prolog

Desde la raíz de `horario-org`, con SWI-Prolog 9.x disponible, ejecuta:

```powershell
Get-Content -Raw contracts/ejemplos/m2_versiones_entrada.json | swipl -q -s prolog_engine/main.pl
```

Para integrarlo con el backend, usa `HORARIO_SWIPL=swipl`,
`HORARIO_MOTOR_ARGS=-q -s prolog_engine/main.pl` y la ruta absoluta de la raíz
del repositorio para `HORARIO_MOTOR_DIR`. El comando anterior con
`motor/main.pl` sigue disponible como entrada de compatibilidad.

El proceso lee un objeto JSON UTF-8 por stdin y escribe un objeto JSON UTF-8 por
stdout. Los diagnósticos del proceso van a stderr. Un JSON de respuesta implica
código de salida 0, incluso con `estado: "error"`. Un código distinto de 0
señala un fallo del proceso.

## Modelo y contrato

El buscador usa CLP(FD) para elegir profesor, aula, día e inicio en turnos.
Los dominios contienen las combinaciones compatibles con disponibilidad por
curso, capacidad, tipo de aula, jornada, recesos y fijaciones. Las restricciones
contra clases ya elegidas excluyen cruces de profesor, aula, grupo y sección.
Cada sesión aparece una vez en `asignaciones` o en `sinAsignar`.

La búsqueda primero maximiza las sesiones asignadas y después minimiza S01,
S02 y S07. Si vence `timeoutSeg`, devuelve el mejor lote encontrado o
`timeout` si todavía carece de una solución válida. El orden de exploración
es fijo. El tiempo exacto y los resultados alcanzados bajo el límite pueden
variar entre ejecuciones.

Se aplica el [contrato aprobado](../docs/ANTES_DE_DESARROLLAR.md#decisiones-aprobadas-del-contrato-del-motor),
con H01–H09 y hasta cuatro versiones distintas. Los motivos de las sesiones
pendientes se calculan en Haskell.

## Pruebas y viabilidad

```powershell
swipl -q -s prolog_engine/tests/motor_tests.pl -g run_tests -t halt
powershell.exe -NoProfile -ExecutionPolicy Bypass -File prolog_engine/tests/medir_viabilidad.ps1
```

Las pruebas ejecutan el motor como proceso externo, comparan los ejemplos
dorados e inspeccionan la salida con un verificador independiente de las reglas.
El segundo comando mide el tiempo y el pico de memoria residente en una
instancia reproducible de 400 secciones, 800 sesiones, 60 aulas, 150 profesores,
cinco días y 15 turnos por día antes de descontar un receso.

En Windows x64 con SWI-Prolog 9.2.9 y un límite de 10 s, devolvió una
versión `factible` con las 800 sesiones ubicadas, costo 12 926 y un pico
de memoria residente de 630,7 MiB. El motor informó 10 360 ms y el proceso
completo tardó 10 657 ms. La medición verifica que se obtuvo un horario completo
para esa instancia sintética, con el costo óptimo aún por demostrar.
