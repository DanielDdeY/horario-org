# Diseño v3 (simplificado): Sistema de Asignación de Horarios

Fecha: 2026-11-22. Este archivo es el contexto compartido de todos los agentes. Es de solo lectura para los agentes; solo los humanos lo modifican.

## Qué cambia respecto a v2

v3 conserva todas las funciones de v2 con menos piezas: tres contratos en vez de seis, dos puertos en Haskell en vez de cinco adaptadores y menos rutas de API. Siguen existiendo el módulo de profesores, el del coordinador, la generación automática, la edición manual, el horario desde cero y la publicación.

| Tema | v2 | v3 |
| --- | --- | --- |
| Contratos | A a F (seis archivos) | `openapi.yaml`, `motor.schema.json`, `reglas.md` |
| Puertos en Haskell | API, BD, Prolog, InMemory, FakeSolver | `Repositorio` y `Solver`; los dobles de prueba viven en los tests |
| Asignaciones fijas | `fijas`, `profesorFijoId`, `aulaFijaId` y `fijada` | `fijada` en la asignación; al motor solo llega `fijas`, con campos opcionales |
| Estados del motor | cinco, con una contradicción | `optimo`, `factible`, `timeout`, `error` |
| Motivos de `sinAsignar` | los calcula Prolog | los calcula Haskell contando candidatos |
| Edición manual | tres verbos más `/validar` | `POST /horarios/{id}/cambios` |
| Colegios | campos "preparados" en v1 | nada en v1; se añaden después como campos opcionales |
| Frontend | M4 visual y M5 lógica | M4 coordinador, M5 profesor y cliente API |

Hay tres correcciones de coherencia, sin funciones nuevas: el objetivo del motor penaliza lo no asignado, no se publica un horario con sesiones sin asignar, y los datos del periodo llevan `periodoId`.

Después de esa base se añadieron H10 (límites de carga del profesor), S07 (estabilidad), el desglose del costo, el modo completar y las pruebas de propiedades. Quedan descartados por simplicidad H11, H12, S03, S04, S06, la aprobación de aptitudes y disponibilidad por el coordinador y la bitácora de cambios.

## Alcance y funciones

El sistema asigna horarios de universidades resolviendo cruces de aulas y de disponibilidad docente. El MVP es solo universitario, con SQLite y sin Docker.

| Función | Quién | Qué hace |
| --- | --- | --- |
| Disponibilidad y cursos aptos | Profesor | Registra y edita solo los suyos (CRUD) |
| Configuración | Coordinador | Aulas, jornada, duración del turno, carga académica y pesos |
| Generación automática | Coordinador | Lanza el algoritmo; el resultado es un horario en borrador |
| Edición manual | Coordinador | Crea, mueve, borra y fija cualquier asignación, incluidas las generadas |
| Horario desde cero | Coordinador | Construye un horario vacío sin usar el algoritmo |
| Publicación | Coordinador | Publica un borrador sin violaciones duras ni sesiones sin asignar |
| Límites de carga | Coordinador | Define por profesor el máximo diario, el máximo semanal y el descanso mínimo; el profesor no puede cambiarlos |
| Modo completar | Coordinador | Ubica solo las sesiones pendientes de un horario y deja intactas las ya asignadas |
| Desglose del puntaje | Coordinador | Ve el costo por regla y por profesor para entender el puntaje y ajustar los pesos |

## Convenciones globales

Son obligatorias para todas las capas y evitan que cada una interprete los datos a su manera.

- **Tiempo:** minutos desde medianoche, de 0 a 1440. Las 8:00 son `480`. Nunca hay strings como `08:00` en contratos ni API; la interfaz formatea.
- **Intervalos:** semiabiertos `[inicio, fin)`. Una clase de 480 a 580 y otra de 580 a 680 no se cruzan, y un fin a medianoche vale 1440.
- **Días:** 1 = lunes, …, 7 = domingo.
- **IDs:** enteros positivos. Prolog solo ve enteros: Haskell traduce `tipoAula` y `edificio` (texto) a enteros antes de llamar al motor.
- **Turno:** lo define el coordinador (45, 50, 60, 90 min). Las clases empiezan en `inicioDiaMin + k × turnoMin` y su duración es múltiplo de `turnoMin`.
- **Reglas:** `H01`… (duras) y `S01`… (blandas) son los mismos códigos en Prolog, validador Haskell, API y UI.
- **JSON:** camelCase, UTF-8, con un campo `version`.
- **Profesores:** cada uno tiene un ID único.

## Arquitectura

Un solo ejecutable Haskell con dos puertos, `Repositorio` y `Solver`, basta para trabajar en paralelo. El dominio y los casos de uso no conocen SQLite, HTTP ni Prolog, y la dependencia apunta siempre hacia adentro: API → Casos de uso → Dominio.

```
Frontend (React + TS + Vite; tipos generados desde openapi.yaml; roles: profesor, coordinador)
   │  HTTP / JSON
   ▼
┌─ Servidor Haskell (un solo ejecutable) ─────────────┐
│  API REST            (Scotty, openapi.yaml, token)  │
│     ▼                                               │
│  Casos de uso        (generar, editar, validar,     │      ┌─ SQLite ── puerto Repositorio
│     │                 publicar)                     │ ───► │
│     ▼                                               │      └─ swipl (Prolog) ── puerto Solver
│  Dominio             (tipos puros + validador)      │         JSON por stdin y stdout
└─────────────────────────────────────────────────────┘
En pruebas, un repositorio en memoria y un solver falso reemplazan a SQLite y a swipl.
```

El servidor solo habla con SQLite y con swipl a través de dos puertos; en pruebas ambos se sustituyen por dobles.

```
horarios/
├── contracts/      openapi.yaml · motor.schema.json · reglas.md · ejemplos/
├── backend/        Domain/ · UseCases/ · Adapters/ (Api, Sqlite, Prolog) · test/ (dobles)
├── prolog_engine/  scripts .pl y pruebas
├── frontend/       React + TypeScript + Vite
└── docs/           SETUP.md
```

Cada capa se desarrolla contra un doble (mock de API, repositorio en memoria, solver falso), así nadie espera a nadie salvo por los tipos del dominio.

## Modelo de datos

Una **sesión** es una reunión semanal que hay que colocar en un día, una hora y un aula. El motor no distingue instituciones: solo recibe sesiones por ubicar.

| Entidad | Campos |
| --- | --- |
| `Configuracion` | `periodoId`, `diasActivos`, `inicioDiaMin`, `finDiaMin`, `turnoMin`, `recesos` (lista de `{inicioMin, finMin}`, valen todos los días), `pesos` (`hueco`, `piso`, `edificio`, `estabilidad`), `toleranciaHuecoMin` (0), `consecutivoMaxMin` (30), `timeoutSeg` |
| `Profesor` | `id`, `nombre`, `cursosAptos` (lista de `cursoId`), `limites` (opcional: `maxMinDia`, `maxMinSemana`, `descansoMinMin`) |
| `Disponibilidad` | `profesorId`, `periodoId`, `dia`, `inicioMin`, `finMin`; los intervalos que se solapan o se tocan se fusionan al guardar |
| `Aula` | `id`, `codigo`, `capacidad`, `edificio`, `piso`, `tipo` |
| `Curso` | `id`, `codigo`, `nombre` |
| `Seccion` | `id`, `cursoId`, `periodoId`, `codigo`, `matriculados`, `grupos` (cohortes), `sesiones` (cada una con `id`, `duracionMin` y `tipoAula`) |
| `Horario` | `id`, `periodoId`, `estado` (`borrador` o `publicado`), `origen` (`generado` o `manual`), `baseHorarioId` (opcional: horario del que se regeneró o completó), copia de la `configuracion`, `asignaciones`, `sinAsignar` (lista de `sesionId`) |
| `Asignacion` | `sesionId`, `profesorId`, `aulaId`, `dia`, `inicioMin`, `fijada`; el fin es `inicioMin` + duración de la sesión |

El tipo de aula vive solo en la sesión, porque un mismo curso puede tener teoría y laboratorio. `grupos` es una lista también en la sección, para que una sección pueda pertenecer a varias cohortes y H05 funcione en ambos casos.

Los `limites` pertenecen a cada profesor y solo los define el coordinador; el profesor no puede cambiarlos. Un límite sin definir no se aplica. `descansoMinMin` es el hueco mínimo entre dos sesiones consecutivas del mismo profesor el mismo día.

## Reglas

Las reglas duras invalidan el horario si se incumplen; las blandas solo penalizan el puntaje. Que toda sesión quede asignada es un criterio de completitud, no una regla: lo que no se ubica aparece en `sinAsignar`.

| Código | Regla dura |
| --- | --- |
| H01 | Un profesor no dicta dos sesiones solapadas el mismo día |
| H02 | Dos sesiones no ocupan la misma aula en intervalos solapados |
| H03 | La sesión `[inicio, fin)` cabe completa en un intervalo de disponibilidad del profesor ese día |
| H04 | `matriculados` ≤ capacidad del aula |
| H05 | Un mismo grupo de alumnos no tiene dos sesiones solapadas |
| H06 | El profesor asignado está apto para el curso |
| H07 | El aula es del tipo que exige la sesión |
| H08 | La sesión empieza y dura múltiplos del turno, cabe en la jornada y no pisa recesos |
| H09 | Dos sesiones de la misma sección no van el mismo día |
| H10 | El profesor cumple los límites que el coordinador le fijó: la suma de duraciones por día no pasa de maxMinDia, la de la semana no pasa de maxMinSemana, y entre dos sesiones consecutivas del mismo día hay al menos descansoMinMin de hueco. Un límite sin definir no aplica |

**S01, minimizar huecos.** Para cada profesor y día se ordenan sus sesiones. Entre dos consecutivas:

```latex
S01 = pesoHueco \cdot \max(0,\ inicio_{sig} - fin_{ant} - toleranciaHuecoMin)
```

Tras una clase de 8:00 a 10:00, la de 10:00 a 12:00 cuesta 0 y la de 16:00 a 18:00 cuesta mucho más.

**S02, agrupación espacial.** Si dos sesiones del mismo profesor el mismo día quedan separadas por un hueco ≤ `consecutivoMaxMin`, se penaliza el desplazamiento:

```latex
S02 = pesoPiso \cdot |piso_A - piso_B| + pesoEdificio \cdot [edificio_A \neq edificio_B]
```

Ir del piso 1 al 5 cuesta más que del 1 al 2.

No se modela el tiempo de traslado entre edificios: S02 solo penaliza la distancia entre sesiones cercanas y no exige un tiempo mínimo de desplazamiento.

**S07, estabilidad.** Al regenerar a partir de un horario base, cada sesión no fijada que cambia de profesor, aula, día u hora respecto a ese horario suma `pesoEstabilidad`. Sin horario base, S07 vale 0.

```latex
S07 = pesoEstabilidad \cdot N_{cambios}
```

`N_cambios` es el número de sesiones no fijadas cuya asignación difiere de la del horario base. El costo de S07 se atribuye al profesor que tiene la sesión en el nuevo horario.

Los códigos H11, H12 y S03 a S06 quedan sin uso a propósito, para que la numeración del catálogo no cambie si se retoman.

**Objetivo del motor.** Primero ubicar el máximo de sesiones y luego minimizar lo blando, con `M` mayor que cualquier costo blando posible:

```latex
costo = M \cdot |sinAsignar| + \sum S01 + \sum S02 + \sum S07
```

Sin el término `M`, dejar todo sin asignar tendría costo mínimo.

## Motor Prolog

Haskell ejecuta `swipl` como proceso externo: JSON por stdin, JSON por stdout, todo en minutos y solo con enteros. El contrato vive en `motor.schema.json` con ejemplos dorados en `contracts/ejemplos/`.

Entrada (resumida):

```json
{
  "version": 1,
  "config": {
    "dias": [1,2,3,4,5], "inicioDiaMin": 480, "finDiaMin": 1230,
    "turnoMin": 50, "recesos": [],
    "pesos": {"hueco": 1, "piso": 2, "edificio": 10, "estabilidad": 5},
    "toleranciaHuecoMin": 0, "consecutivoMaxMin": 30, "timeoutSeg": 60
  },
  "profesores": [{"id": 1, "cursosAptos": [10, 11],
                  "maxMinDia": 360, "maxMinSemana": 1200, "descansoMinMin": 50}],
  "disponibilidades": [{"profesorId": 1, "dia": 1, "inicioMin": 480, "finMin": 720}],
  "aulas": [{"id": 301, "capacidad": 40, "edificio": 1, "piso": 3, "tipo": 1}],
  "sesiones": [{"id": 5001, "cursoId": 10, "seccionId": 900, "duracionMin": 100,
                "matriculados": 35, "tipoAula": 1, "grupos": [7]}],
  "fijas": [{"sesionId": 5002, "profesorId": 1, "aulaId": 301, "dia": 2, "inicioMin": 480}],
  "previas": [{"sesionId": 5001, "profesorId": 1, "aulaId": 301, "dia": 1, "inicioMin": 480}]
}
```

En `fijas` cada campo salvo `sesionId` es opcional: una fija puede cerrar solo el profesor, solo el aula o solo el día y la hora, y el motor decide el resto. Esto reemplaza a `profesorFijoId` y `aulaFijaId`. El motor las trata como inamovibles; Haskell verifica antes su coherencia entre sí.

`previas` son las asignaciones no fijas del horario base y solo sirven para calcular S07; el motor puede moverlas. `maxMinDia`, `maxMinSemana` y `descansoMinMin` son opcionales por profesor: si faltan, H10 no se aplica en ese punto. En el modo completar no hay `previas`, porque todo lo ya asignado llega como `fijas`. El `costo` de salida es solo la parte blanda (S01, S02 y S07); el término `M` del objetivo es interno.

Salida:

```json
{
  "version": 1,
  "estado": "factible",
  "costo": 12,
  "asignaciones": [{"sesionId": 5001, "profesorId": 1, "aulaId": 301, "dia": 1, "inicioMin": 480}],
  "sinAsignar": [5003],
  "tiempoMs": 1840
}
```

| Estado | Significado |
| --- | --- |
| `optimo` | Resultado demostrado óptimo según el objetivo de la sección Reglas |
| `factible` | Se agotó el tiempo; esta es la mejor solución encontrada |
| `timeout` | Se agotó el tiempo sin ninguna solución |
| `error` | Fallo interno del motor, con un mensaje |

Un resultado es completo cuando `sinAsignar` viene vacío; en cualquier otro caso es parcial, sea `optimo` o `factible`. La entrada incoherente nunca llega al motor, porque Haskell la rechaza antes.

Haskell mata el proceso `swipl` si pasa `timeoutSeg` más un margen, y limita `timeoutSeg` a un máximo configurado en el servidor.

## Flujos

**Generar un horario.** Es asíncrono: `POST /horarios/generar` responde 202 con un `jobId` y el frontend consulta `GET /trabajos/{jobId}`.

1. Haskell reúne profesores, disponibilidades, aulas, secciones y configuración. Si se indica un `baseHorarioId`, copia sus asignaciones fijadas.
2. Valida la entrada: duraciones múltiplos del turno, IDs coherentes, fijas compatibles entre sí y con los límites H10. Si algo falla, responde con errores claros sin llamar al motor.
3. Traduce a JSON (textos a enteros) y ejecuta `swipl`.
4. El motor resuelve con `clpfd`, aplica H01 a H10 y minimiza el objetivo. Si se agota el tiempo, devuelve la mejor solución encontrada.
5. Haskell ejecuta el validador como segunda verificación. Si encuentra una violación dura en la salida del motor, el trabajo termina en `error` y no guarda nada. Si todo está bien, guarda un nuevo horario en borrador; nunca sobrescribe uno anterior.

**Modos de generación.** `POST /horarios/generar` recibe `periodoId`, `modo` y, opcionalmente, `baseHorarioId`.

- `generar` (por defecto): sin base parte de cero. Con base respeta solo las asignaciones fijadas y reubica el resto; los cambios respecto al horario base se penalizan con S07.
- `completar`: exige `baseHorarioId`, que puede ser un horario manual o generado. Todas sus asignaciones llegan al motor como `fijas`, así que solo se ubican las sesiones de `sinAsignar`. Nada de lo ya asignado se mueve.

**Editar a mano.** El coordinador crea, mueve y borra asignaciones en un horario vacío o generado, con `POST /horarios/{id}/cambios`.

- Cada cambio se valida con el validador puro de Haskell, que devuelve violaciones duras (`Hxx`) y puntaje blando. Con `simular=true` valida sin guardar, para previsualizar un arrastre en la grilla.
- Un borrador puede guardarse con violaciones, que la UI marca en rojo.
- El coordinador puede fijar asignaciones (`fijada = true`). Al volver a ejecutar el algoritmo las fijadas se respetan y solo se reubica el resto.

**Publicar.** `POST /horarios/{id}/publicar` exige cero violaciones duras y `sinAsignar` vacío.

**Sin solución.** El motor no responde solo "error": devuelve un resultado parcial con `sinAsignar`. Haskell explica cada sesión sin ubicar contando candidatos, con un código de regla y un detalle legible, por ejemplo "H04: ninguna aula con capacidad ≥ 60 (la mayor tiene 45)". Así el coordinador sabe qué corregir.

**Explicar el puntaje.** Cada horario consultado o simulado trae su `puntaje`, que calcula el validador de Haskell igual para horarios generados y manuales. Así el coordinador ve qué regla y qué profesor pesan más, y ajusta los pesos de la configuración antes de regenerar.

```json
{
  "total": 12, "sinAsignar": 1,
  "porRegla": [{"codigo": "S01", "costo": 8}, {"codigo": "S02", "costo": 4}, {"codigo": "S07", "costo": 0}],
  "porProfesor": [{"profesorId": 1, "S01": 5, "S02": 2, "S07": 0}, {"profesorId": 2, "S01": 3, "S02": 2, "S07": 0}]
}
```

`total` suma solo lo blando; las sesiones sin asignar se cuentan aparte.

## API REST

La API cubre todas las funciones con menos rutas porque la disponibilidad, los cursos aptos, las secciones y las sesiones viajan dentro de su recurso. Los tipos de TypeScript se generan desde `openapi.yaml` y no se escriben a mano.

| Método y ruta | Uso | Quién |
| --- | --- | --- |
| `POST /auth/login` | Autenticación con token | Todos |
| `GET/POST/DELETE /profesores` | Listar, crear y borrar profesores | Coordinador |
| `GET/PUT /profesores/{id}` | Datos, disponibilidad, cursos aptos y `limites` del profesor; los `limites` solo los modifica el coordinador | Profesor (solo el suyo) y coordinador |
| `GET/POST/PUT/DELETE /aulas` | Aulas | Coordinador |
| `GET/POST/PUT/DELETE /cursos` y `/cursos/{id}/secciones` | Carga académica: cursos, secciones, sesiones y grupos | Coordinador |
| `GET/PUT /configuracion` | Jornada, turno, recesos y pesos | Coordinador |
| `POST /horarios` | Crear un horario vacío | Coordinador |
| `GET /horarios` y `GET /horarios/{id}` | Listar y consultar; el detalle incluye `sinAsignar`, violaciones y `puntaje` desglosado por regla y por profesor | Coordinador |
| `POST /horarios/generar` | Lanza el algoritmo con `modo` `generar` o `completar` y un `baseHorarioId` opcional; responde 202 con `jobId` | Coordinador |
| `GET /trabajos/{jobId}` | Estado de la generación y resultado | Coordinador |
| `POST /horarios/{id}/cambios` | Crear, mover, borrar o fijar asignaciones; `simular=true` valida sin guardar | Coordinador |
| `POST /horarios/{id}/publicar` | Cambia el estado a `publicado` | Coordinador |

Los errores tienen un formato uniforme: `{ "codigo": "...", "mensaje": "...", "detalles": [...] }`.

## Plan de trabajo

Cinco miembros trabajan en paralelo contra dobles de prueba; el único bloqueo real son los tipos del dominio, que M2 publica primero.

| Miembro | Entrega | Trabaja contra |
| --- | --- | --- |
| M1 Motor Prolog | `prolog_engine/`: lectura de JSON, H01 a H10, S01, S02 y S07, fijas, previas, `timeoutSeg`, estados de salida | JSON de `ejemplos/` y `swipl` directo |
| M2 Núcleo Haskell | Primero tipos y puertos vacíos (1 a 2 días); después casos de uso, validador puro con desglose del costo, diagnóstico de `sinAsignar`, modo completar y adaptador Prolog | Solver falso y repositorio en memoria |
| M3 Infraestructura | API conforme a `openapi.yaml`, SQLite, trabajos asíncronos, autenticación y esquema de BD | Tipos y puertos de M2 |
| M4 Frontend coordinador | Configuración, cursos y secciones, límites de carga por profesor, grilla interactiva (arrastrar, soltar, fijar), marcas de violación, desglose del puntaje y botón de modo completar | Mock de API desde `openapi.yaml` |
| M5 Frontend profesor y QA | Pantallas del profesor, cliente de API y CI desde el día 1; pruebas de propiedades con QuickCheck y pruebas de integración con el validador como oráculo de la salida real de Prolog | El mismo mock |

**Fases**

1. **Contratos (1 a 2 días, todos).** Se redactan `openapi.yaml`, `motor.schema.json` con tres ejemplos y `reglas.md`. Antes de congelar el contrato del motor, M1 prueba una instancia realista para confirmar que `clpfd` aguanta el tamaño esperado.
2. **Trabajo en paralelo.** Cada capa pasa sus pruebas de contrato contra mocks.
3. **Integración.** Se reemplazan los mocks de abajo hacia arriba: Prolog con Haskell, luego BD y API, luego frontend.
4. **Endurecimiento.** Pruebas de extremo a extremo, rendimiento del solver con el benchmark y ajuste de pesos.
5. **Colegios (etapa 2).** Planes de estudio, grupos, recesos obligatorios y la regla de grilla completa, añadidos como campos opcionales.

**Cómo se verifica cada capa**

- M1: el motor produce, para cada JSON de `ejemplos/`, una salida válida según el esquema que respeta H01 a H10.
- M2: el adaptador parsea las salidas doradas y el validador detecta violaciones en casos preparados.
- M3: la API respeta `openapi.yaml` y los repositorios cumplen el puerto.
- M4 y M5: cada pantalla funciona con datos del mock y de `ejemplos/`.

**Pruebas de propiedades y benchmark (M5, con M1 y M2).** Un generador de QuickCheck produce instancias aleatorias pequeñas y válidas según `motor.schema.json`, ejecuta el motor real y comprueba con el validador de Haskell estas propiedades:

- La salida no tiene violaciones duras (H01 a H10).
- El `costo` del motor coincide con el costo blando que calcula Haskell.
- Todas las `fijas` quedan respetadas.
- Cada sesión aparece una sola vez, asignada o en `sinAsignar`.

Estas pruebas corren en CI con pocas instancias por ejecución. El benchmark va aparte: ejecuta el motor sobre instancias públicas de timetabling universitario y sobre datos reales anonimizados de una facultad, y registra estado, costo, `sinAsignar` y tiempo para vigilar el rendimiento del solver. Las instancias públicas se convierten antes al formato de `motor.schema.json`.

**Reglas del equipo.** Cada miembro es dueño de su carpeta (`CODEOWNERS`). Los cambios a `contracts/` van por PR con aprobación de todos los consumidores. Las ramas son cortas, con PR y al menos una revisión.

**Entorno sin Docker.** SWI-Prolog 9.x, GHCup (GHC y Cabal o Stack), Node.js 20+ y SQLite, que es un archivo y no necesita servidor. En Windows se usa WSL2. `docs/SETUP.md` tiene los pasos y `make dev` levanta cada capa; el mock de API es `npx prism mock contracts/openapi.yaml`.

## Decisiones

Las seis decisiones de v2 se mantienen. Las nuevas de v3 están marcadas "a confirmar" y conviene cerrarlas antes de congelar los contratos.

| Decisión | Resolución | Origen |
| --- | --- | --- |
| Reglas H05 a H09 | Aprobadas; H05 (cruce de grupo) es esencial | v2 |
| Borradores con violaciones | Se guardan, pero no se publican | v2 |
| Autenticación | Login simple con token, dos roles, una institución | v2 |
| Framework de API | Scotty; Servant si el equipo domina tipos avanzados | v2 |
| Frontend | React + TypeScript + Vite | v2 |
| Valores por defecto | `consecutivoMaxMin` 30 y `toleranciaHuecoMin` 0, ajustables | v2 |
| Objetivo del motor | Lexicográfico: primero sesiones asignadas, luego costo blando | v3, a confirmar |
| Salida del motor con violación dura | El trabajo termina en `error` y no guarda nada | v3, a confirmar |
| Reparto del frontend | Por pantallas (coordinador y profesor), no visual contra lógica | v3, a confirmar |
| Colegios | Sin campos preparados en v1; se añaden después como opcionales | v3, a confirmar |
| Límites de carga (H10) | Por profesor y definidos solo por el coordinador; un límite sin definir no se aplica. El descanso mínimo se entiende como el hueco mínimo entre dos sesiones consecutivas del mismo día | v3, a confirmar |
| Estabilidad (S07) | Penaliza cada sesión no fijada cuyo profesor, aula, día u hora cambia respecto al horario base | v3, a confirmar |
| Desglose y modo completar | El validador de Haskell calcula el desglose por regla y por profesor; completar fija todo lo ya asignado y ubica solo lo pendiente | v3 |
| Pruebas de propiedades y benchmark | QuickCheck contra el validador en CI; benchmark aparte con instancias públicas y datos reales anonimizados de una facultad, que aún hay que conseguir | v3, pendiente |
| Descartado por simplicidad | H11 (traslado entre edificios), H12, S03, S04, S06 (el profesor equilibra su carga con su disponibilidad), aprobación de aptitudes y disponibilidad, bitácora de cambios | v3 |

Siguen fuera de v3, por añadir funciones: la importación masiva desde Excel o CSV y las vistas y la exportación del horario publicado.
