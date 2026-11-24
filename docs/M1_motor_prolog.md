# M1 · Motor lógico en Prolog (instrucciones para tu agente)

> **Lee esto primero.** Eres el agente de M1. Otros agentes trabajan ahora mismo, en paralelo, en el mismo repositorio. Tu trabajo es avanzar tu parte sin frenar ni romper a nadie y dejar por escrito lo que hiciste.
>
> 1. Antes de escribir nada, lee `docs/DISENO_v3.md` completo, luego `contracts/`, `docs/cambios/` y `docs/solicitudes/` (sección 1).
> 2. Escribe solo en las rutas de tu territorio. Todo lo demás es solo lectura (sección 2).
> 3. No borres nada: ni archivos, ni código, ni pruebas, ni reportes de otros. Nada de `rm`, `git reset --hard`, `git clean`, `git push --force` (sección 3).
> 4. No cambies lo que otros consumen (contratos, puertos, firmas públicas). Si hace falta un cambio, crea una solicitud en `docs/solicitudes/` (sección 8).
> 5. Si el diseño dice "a confirmar" o es ambiguo, no decidas por tu cuenta: elige lo más simple y reversible y anótalo en "Supuestos" de tu reporte (sección 5).
> 6. Al terminar cada sesión crea un reporte nuevo en `docs/cambios/` con la plantilla de la sección 7. Es obligatorio, incluso si no cambiaste nada.

## Tu rol

Construyes el motor que decide dónde va cada sesión. Haskell lo ejecuta como proceso externo (`swipl`): recibe un JSON por stdin y devuelve un JSON por stdout. No sabes nada de bases de datos, HTTP ni pantallas. Eres el miembro con más riesgo técnico del proyecto: de ti depende que el solver aguante el tamaño real.

## Tu territorio

- **Escribes:** `prolog_engine/**` (scripts `.pl`, pruebas, `README.md` propio) y, en `contracts/ejemplos/`, solo archivos nuevos con prefijo `m1_`.
- **Co-dueño con M2:** `contracts/motor.schema.json`. Puedes crear el borrador si no existe (con `status: borrador`); después cualquier cambio va por solicitud a M2.
- **Solo lectura:** todo lo demás, en especial `backend/`, `frontend/`, `contracts/openapi.yaml`, `.github/` y `Makefile`.

## Qué debes entregar, en este orden

1. **Spike de viabilidad (antes de congelar el contrato del motor).** Prueba `clpfd` con una instancia sintética realista (por ejemplo 400 secciones, 60 aulas, 150 profesores, 5 días y 15 turnos). Mide tiempo y memoria y documéntalo en tu reporte. Si no escala, no cambies de tecnología por tu cuenta: crea una solicitud a M2 con los números y una alternativa propuesta.
2. **Entrada y salida.** Lee el JSON de entrada y escribe el de salida exactamente como describe la sección "Motor Prolog" del diseño: `estado` (`optimo`, `factible`, `timeout`, `error`), `costo`, `asignaciones`, `sinAsignar` (solo ids), `tiempoMs`.
   - `stdout` contiene únicamente el JSON. Los logs van a `stderr`.
   - Si algo falla internamente, devuelve JSON con `estado: error` y un mensaje.
   - Supuesto por defecto: código de salida 0 si se produjo un JSON de salida (incluido `error`), distinto de 0 solo si el proceso no pudo producir JSON. Documéntalo en `prolog_engine/README.md` y repórtalo para que M2 lo alinee.
3. **Modelo CLP(FD).** Por cada sesión, variables de profesor, aula, día e inicio (en unidades de turno). Reglas duras H01 a H10 según la sección "Reglas":
   - Las `fijas` son inamovibles y cada campo salvo `sesionId` es opcional: fija solo lo que venga.
   - H10 usa `maxMinDia`, `maxMinSemana` y `descansoMinMin` por profesor; si faltan, no se aplica.
   - Solo trabajas con enteros. Haskell ya tradujo `tipoAula` y `edificio` a enteros.
4. **Objetivo lexicográfico.** Primero minimizar `|sinAsignar|` y luego el costo blando (S01 + S02 + S07). Calcula una cota para `M` mayor que cualquier costo blando posible. El `costo` de salida es solo la parte blanda. Sin este término, dejar todo sin asignar saldría "óptimo".
   - S07 usa `previas` (las asignaciones del horario base que no son fijas). Sin `previas`, S07 vale 0.
5. **Resultado aunque se acabe el tiempo.** `labeling([min(...)])` no entrega la mejor solución encontrada si se corta por tiempo. Implementa tu propio branch-and-bound que guarde el mejor resultado (por ejemplo con `nb_setval`) y respeta `timeoutSeg` con `call_with_time_limit`. `optimo` solo si se demostró; `factible` si se acabó el tiempo con una solución; `timeout` si no hubo ninguna.
6. **Determinismo.** La misma entrada produce la misma salida: orden estable de listas y heurísticas sin aleatoriedad. M5 lo usa para comparar contra el validador de Haskell.
7. **Pruebas.** En `prolog_engine/tests/` (plunit): corre cada JSON de `contracts/ejemplos/` y comprueba que la salida cumple el esquema y H01 a H10 con una verificación independiente escrita por ti. No dependas del validador de Haskell para tus pruebas.
8. **Ejemplos.** Añade en `contracts/ejemplos/` casos nuevos con prefijo `m1_` (entrada y salida esperada), al menos uno con `fijas`, uno con `previas`, uno con `sinAsignar` no vacío y uno con límites H10.

## Qué NO debes hacer

- No calcules los `motivos` de `sinAsignar`: los calcula Haskell contando candidatos. Tú solo devuelves los ids.
- No valides la coherencia fina de la entrada: Haskell la rechaza antes de llamarte. Solo defiéndete de entradas rotas con un `estado: error`.
- No leas bases de datos ni hagas HTTP. No uses átomos para ids ni para tipos.
- No cambies la definición de S01 por tu cuenta aunque sea difícil de modelar. El validador de Haskell debe coincidir con tu cálculo; si propones otra formulación (por ejemplo "hueco total del día menos tiempo ocupado"), pásala por solicitud a M2 con la equivalencia.

## Interfaces con otros miembros

| Con | Qué recibe de ti | Qué necesitas de él |
| --- | --- | --- |
| M2 | El comando exacto de ejecución, el esquema, los códigos de salida y ejemplos dorados | Acordar el esquema, confirmar el sentido de S01, S02 y S07 y el validador que replica tus reglas |
| M5 | Un motor determinista que sus pruebas de propiedades pueden ejecutar | Que te avise de contraejemplos (entradas que rompen una propiedad) |
| M3, M4 | Nada directo | Nada |

## Criterios de terminado

- El motor procesa todos los ejemplos con una salida válida y sin violaciones de H01 a H10.
- Respeta `timeoutSeg` y devuelve el estado correcto en cada caso.
- `prolog_engine/README.md` explica cómo ejecutarlo, los códigos de salida y los resultados del spike.
- Reporte creado en `docs/cambios/`.

---

# Reglas comunes para todos los agentes (obligatorias)

Estas reglas son iguales en los cinco archivos. Si algo de tu misión choca con ellas, gana la regla común: nunca pises el territorio de otro ni borres trabajo ajeno.

## 1. Lectura obligatoria antes de tocar nada

Lee, en este orden, y anota cada archivo leído para tu reporte:

1. `docs/DISENO_v3.md`, completo. Es la fuente de verdad del producto, las reglas, el motor, el flujo y la API.
2. `contracts/`: `reglas.md`, `openapi.yaml`, `motor.schema.json` y `ejemplos/`, los que existan. Si un archivo aún no existe, dilo en tu reporte; no inventes su contenido.
3. `docs/cambios/`: todos los reportes de otros miembros, del más antiguo al más reciente (el nombre empieza por fecha y hora). Apunta lo que afecta a tu capa.
4. `docs/solicitudes/`: las dirigidas a ti (`..._a_M1_...`) y las que tú enviaste, con sus respuestas.
5. El estado del repositorio: `git status`, `git log --oneline -20` y `git branch -a`.
6. Este archivo, completo.

Los archivos modificados sin commit que no sean tuyos pertenecen al trabajo en curso de otro agente: no los toques, no los incluyas en tus commits y no los reviertas.

## 2. Mapa de propiedad (quién puede escribir dónde)

| Ruta | Dueño | Regla |
| --- | --- | --- |
| `docs/DISENO_v3.md`, `CODEOWNERS` | Humanos | Solo lectura para agentes |
| `contracts/openapi.yaml` | M3 | M4 y M5 lo consumen; cambios por solicitud a M3 |
| `contracts/motor.schema.json` | M1 y M2 | Cambios por acuerdo entre ambos, con solicitud |
| `contracts/reglas.md` | M2 crea el borrador si no existe, copiando fielmente la sección Reglas del diseño | Después, cambios solo por solicitud y aprobación humana |
| `contracts/ejemplos/` | M1 y M2 | Solo archivos nuevos con tu prefijo (`m1_`, `m2_`); nunca editar los existentes |
| `prolog_engine/` | M1 | |
| `backend/src/Domain/`, `backend/src/UseCases/`, `backend/src/Adapters/Prolog/` | M2 | |
| `backend/test/` (salvo `backend/test/property/`) | M2 | Dobles de prueba y pruebas de su capa |
| `backend/src/Adapters/Api/`, `backend/src/Adapters/Sqlite/`, `backend/app/`, `backend/migrations/` | M3 | |
| `Makefile`, `docs/SETUP.md`, `docs/db.md` | M3 | Otros piden cambios por solicitud |
| `backend/*.cabal`, `cabal.project` | M2 y M3 | Solo añadir líneas de tus propios módulos; no reordenar, no formatear, no quitar |
| `frontend/src/features/coordinador/`, `frontend/src/components/` | M4 | |
| `frontend/src/features/profesor/`, `frontend/src/api/`, `frontend/src/app/` | M5 | `frontend/src/app/` contiene el router y los proveedores |
| `frontend/package.json`, `frontend/vite.config.*`, `frontend/tsconfig*.json` | M5 | M4 puede añadir dependencias propias a `package.json` solo añadiendo líneas, y lo reporta |
| `.github/`, `backend/test/property/`, `benchmark/`, `tests/` | M5 | |
| `docs/cambios/`, `docs/solicitudes/` | Todos | Solo crear archivos nuevos propios; nunca editar los de otros |

Si necesitas escribir en una ruta que no es tuya, no lo hagas: crea una solicitud (sección 8).

## 3. Reglas de no interferencia y de no borrado

1. **Solo escribes en tus rutas.** Todo lo demás es lectura.
2. **No borras nada ajeno ni nada ya reportado.** Esto incluye archivos, carpetas, funciones, tipos, pruebas, líneas de configuración, contratos, ejemplos y reportes. Prohibido: `rm`, `rmdir`, `git rm`, `git reset --hard`, `git clean`, `git checkout -- .`, `git restore` sobre archivos ajenos, `git push --force`, `git branch -D`, `git stash drop`, y rebase de ramas compartidas.
3. **No sobrescribes archivos existentes sin leerlos antes.** Si un archivo ya existe y no es tuyo, no lo modifiques. Si es tuyo, edítalo con cambios mínimos; no lo reescribas entero.
4. **Para reemplazar algo, añade lo nuevo y marca lo viejo** con un comentario `DEPRECATED: <motivo> (reportado en <archivo de cambios>)`. Quitarlo lo decide un humano.
5. **Excepción única:** puedes borrar archivos temporales que tú mismo creaste en esta misma sesión y que nunca reportaste ni commiteaste.
6. **No cambias lo que otros consumen.** Contratos, puertos (`Repositorio`, `Solver`), firmas públicas, nombres de campos JSON, rutas de la API y códigos de regla son compatibles hacia atrás: solo se pueden añadir campos opcionales. Renombrar, quitar o cambiar el significado de algo existente requiere solicitud y aprobación humana.
7. **Contratos ya congelados:** si ya fueron aprobados por los humanos, solo cambios aditivos y aprobados. Si el contrato aún no existe y eres su dueño, puedes crear un borrador marcado como `status: borrador` y reportarlo.
8. **Archivos compartidos** (`*.cabal`, `package.json`, `Makefile`): solo añades líneas propias; no reordenas, no reformateas, no actualizas versiones de lo que ya está.
9. **Nada de formateo ni refactor masivo** fuera de lo que tú creaste. No muevas ni renombres archivos ajenos.
10. **No instales ni actualices herramientas globales** (GHC, SWI-Prolog, Node). Si necesitas otra versión, crea una solicitud.
11. **Un error en código ajeno no se arregla: se reporta.** Crea una solicitud al dueño con el diagnóstico (qué falla, cómo reproducirlo, archivo y línea).
12. **Conflicto entre fuentes:** gana `docs/DISENO_v3.md`. Si el diseño es ambiguo o marca algo como "a confirmar", aplica la sección 5.

## 4. Git

- Trabaja en una rama propia `m1/<tema-corto>` creada desde la rama principal actualizada. No toques ramas de otros.
- Haz commits pequeños con prefijo `[M1]`. Añade archivos por ruta explícita (`git add ruta/tuya`); nunca `git add -A` ni `git add .`.
- No hagas merge a la rama principal: deja la rama lista y pide revisión. Un humano la aprueba.
- No commitees secretos, bases de datos (`*.db`, `*.sqlite`), binarios, `node_modules`, `dist` ni carpetas de compilación.

## 5. Decisiones y supuestos

- Convenciones que no se negocian: minutos desde medianoche, intervalos `[inicio, fin)`, días 1 a 7, IDs enteros, códigos `H01...` y `S01...`, JSON en camelCase con `version`, y Prolog solo ve enteros.
- Las decisiones marcadas "a confirmar" y cualquier punto no definido en el diseño no los decides tú. Elige la opción más simple y reversible, impleméntala de forma aislada y regístrala en la sección "Supuestos" de tu reporte. Si afecta a otro miembro, además crea una solicitud.
- No inventes funciones, endpoints, campos ni reglas que el diseño no contenga. Si crees que falta algo, propónlo en una solicitud.
- Las funciones descartadas (H11, H12, S03, S04, S06, aprobación de aptitudes, bitácora de cambios) no se implementan.

## 6. Pruebas

- Ejecuta las pruebas de tu capa antes de reportar y copia el comando y el resultado en el reporte.
- No desactives, no borres y no debilites pruebas existentes para que pasen.
- Si una prueba falla por una causa ajena a tu capa, repórtala con una solicitud; no la arregles tú.

## 7. Entregable obligatorio: reporte de cambios

Al final de cada sesión crea un archivo nuevo `docs/cambios/AAAA-MM-DD_HHMM_M1_<tema-corto>.md`. Usa la hora local UTC-5; el tema va en minúsculas, con guiones y sin espacios, por ejemplo `docs/cambios/2026-11-23_0930_M1_primer-avance.md`. Crea la carpeta si no existe.

- Es un archivo nuevo en cada sesión. Nunca edites un reporte ya creado, ni los de otros ni los tuyos. Si algo cambia, crea otro con título "Corrección de ...".
- Escríbelo para que otro agente que solo lea este reporte pueda continuar o integrarse sin preguntarte nada.
- Hazlo aunque no hayas cambiado nada: indica "Sin cambios" y el motivo (por ejemplo, un bloqueo).

Plantilla:

```markdown
# Reporte de cambios: M1 · <tema>

- Fecha y hora (UTC-5): AAAA-MM-DD HH:MM
- Miembro: M1
- Rama y commits: <rama> · <hashes cortos>
- Estado: Completo | Parcial | Bloqueado | Sin cambios

## Resumen
<2 o 3 líneas: qué se logró y por qué importa a los demás>

## Archivos
| Ruta | Acción (creado / modificado) | Qué cambió | Por qué |
| --- | --- | --- | --- |
(nunca "eliminado": no se borra nada)

## Contratos e interfaces afectados
<Ninguno, o lista exacta: ruta, campo o función, si es solo aditivo y quién debe enterarse>

## Cómo verificarlo
<Comandos exactos y resultado obtenido>

## Supuestos y decisiones tomadas
<Todo lo que decidiste porque el diseño no lo definía o decía "a confirmar", con la alternativa descartada>

## Pendientes y bloqueos
<Qué falta, quién debe hacer qué, solicitudes abiertas (rutas de los archivos)>

## Qué deben saber los otros agentes
- M1: ...
- M2: ...
- M3: ...
- M4: ...
- M5: ...
(Indica "nada" donde no aplique)

## Archivos leídos como contexto
<Lista de archivos y reportes leídos al empezar>
```

## 8. Solicitudes entre miembros

Cuando necesites algo de otro miembro (un campo nuevo, un cambio de contrato, una corrección en su capa), no lo implementes tú. Crea `docs/solicitudes/AAAA-MM-DD_HHMM_M1_a_<M destino>_<tema>.md`:

```markdown
# Solicitud de M1 a <M destino>: <tema>

- Fecha y hora (UTC-5): AAAA-MM-DD HH:MM
- Bloqueante: sí | no (si es sí, di qué parte de tu trabajo detiene)
- Afecta a: <rutas o contratos>

## Qué necesito
## Por qué (referencia a la sección de docs/DISENO_v3.md)
## Propuesta concreta (campos, firmas, ejemplo JSON)
## Impacto en otras capas
```

- Si eres el destinatario, responde creando otro archivo `..._<tu M>_a_<M origen>_re_<tema>.md`. Nunca edites la solicitud original.
- Una solicitud bloqueante no te detiene del todo: sigue con las partes que no dependen de ella.

## 9. Lista de comprobación antes de terminar

- [ ] Leí el diseño, `contracts/`, `docs/cambios/` y `docs/solicitudes/` antes de empezar.
- [ ] Solo escribí en mis rutas.
- [ ] No borré, renombré ni moví nada ajeno; no reescribí archivos de otros.
- [ ] Mis cambios a contratos o interfaces son solo aditivos y están reportados.
- [ ] Las pruebas de mi capa pasan y el reporte incluye el comando y el resultado.
- [ ] Los supuestos están anotados y, si afectan a otros, hay solicitud.
- [ ] Creé el reporte nuevo en `docs/cambios/` con todas las secciones.
- [ ] Mis commits están en mi rama, con mis rutas explícitas y sin secretos ni binarios.

## 10. Si te bloqueas

No improvises fuera de tu territorio. Termina lo que sí puedes hacer, escribe el reporte con Estado "Bloqueado" y crea la solicitud correspondiente. Un reporte claro de un bloqueo vale más que un cambio en la capa de otro.
