# Motor de horarios M1

Desde la raíz del repositorio, con SWI-Prolog 9.x en el PATH:

```sh
swipl -q -f none -s prolog_engine/main.pl < contracts/ejemplos/m2_versiones_entrada.json
```

En PowerShell usa `Get-Content -Raw contracts/ejemplos/m2_versiones_entrada.json | swipl -q -f none -s prolog_engine/main.pl`. El proceso lee un documento JSON UTF-8 hasta EOF y escribe un solo JSON UTF-8 con salto de línea en stdout. Sale con código 0 cuando pudo emitir una respuesta, incluso con `estado: "error"`. Un código distinto de 0 indica un fallo del proceso o de escritura. Los diagnósticos del runtime salen por stderr.

Para iniciar el servidor desde otro directorio, configura `HORARIO_MOTOR_DIR` con la ruta absoluta a la raíz del repositorio. Usa `HORARIO_MOTOR_ARGS="-q -f none -s prolog_engine/main.pl"` y `HORARIO_SWIPL` con el ejecutable cuando esté fuera del PATH.

## Reglas y búsqueda

Se aplica el [contrato vigente de M2](../docs/ANTES_DE_DESARROLLAR.md#decisiones-aprobadas-del-contrato-del-motor) con H01 a H09. Las franjas corresponden a cada profesor, curso y día. H10 fue retirado por los acuerdos del equipo. Una fija obligatoria se trata como una asignación completa. Si se asigna una sesión con una restricción parcial, respeta todos los campos indicados. S07 cobra un cambio de ubicación únicamente a las sesiones movibles con una previa que sí quedan asignadas.

El dominio CLP(FD) de cada sesión contiene las combinaciones válidas de profesor, día y turno y un dominio separado de aulas. La búsqueda recorre primero las fijas obligatorias y después las sesiones con menos opciones. Un índice registra los turnos ocupados por profesor, aula y grupo, y los días ocupados por sección. Los minutos de inicio se calculan desde la hora inicial de la jornada.

La búsqueda acota el objetivo `M × pendientes + costo blando` y guarda hasta `maxVersiones` soluciones distintas con la menor cantidad de pendientes vista. M es uno más que la cota del costo de todas las sesiones. El costo blando usa pares consecutivos para S01 y S02 y se devuelve sin el término de pendientes. Los empates conservan el orden de descubrimiento. El orden es reproducible. El tiempo medido y las soluciones alcanzadas antes de un corte pueden variar entre ejecuciones.

Una respuesta exitosa siempre contiene `versiones`. El lote es `optimo` cuando la búsqueda completa o su cota prueban el resultado. Si vence el presupuesto y ya hay candidatos, el lote sale `factible` y conserva como `optimo` cada candidato que haya alcanzado la cota global. Sin candidatos devuelve `timeout`. Una entrada ilegible o unas fijas obligatorias inviables devuelven `error` con `mensaje` y `tiempoMs`, conforme al acuerdo de M2. El borrador del esquema aún excluye `tiempoMs` de la rama de error.

## Pruebas

```sh
swipl -q -f none -s prolog_engine/tests/motor_tests.pl -g run_tests -t halt
```

La suite ejecuta el proceso para cada par dorado de `contracts/ejemplos/`. Verifica por separado H01 a H09, fijas, cobertura, puntaje, orden de las alternativas y la respuesta ante una entrada rota.

## Spike de viabilidad

```sh
python prolog_engine/spike.py --sesiones-por-seccion 1 --timeout 5 | swipl -q -f none -s prolog_engine/main.pl
python prolog_engine/spike.py --sesiones-por-seccion 2 --timeout 5 | swipl -q -f none -s prolog_engine/main.pl
```

Cada instancia tiene 400 secciones, 60 aulas, 150 profesores, cinco días de 15 turnos, un receso, franjas escalonadas, cohortes y dos tipos de aula. Se midió el tiempo reportado por el motor, el tiempo de pared del proceso y el pico de memoria residente con `PeakWorkingSet64` muestreado cada 20 ms en Windows, usando SWI-Prolog 9.2.9.

| Sesiones | Ubicadas | Versiones | Estado | Motor | Proceso | Pico residente |
| ---: | ---: | ---: | --- | ---: | ---: | ---: |
| 400 | 400 | 4 | `factible` | 5.033 s | 5.414 s | 89.39 MiB |
| 800 | 800 | 4 | `factible` | 5.048 s | 5.414 s | 162.42 MiB |

En ambas instancias se ubicaron todas las sesiones. El óptimo de costo blando quedó sin demostrar dentro del presupuesto.
