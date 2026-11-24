# Reporte de cambios: M5 · cierre QA profesor

- Fecha y hora (UTC-5): 2026-11-24 18:42
- Miembro: M5
- Rama y commits: `feat/m5-frontend-profesor` · sin commits
- Estado: Completo

## Resumen

Se finalizó el cierre de QA para el flujo docente: los cursos con datos de ejemplo `string` se muestran con una etiqueta identificable como mock sin cambiar el ID numérico enviado, y la validación de intervalos se separó para probarla directamente.
Se añadieron pruebas de pantalla para login, protección de rutas, disponibilidad y propuestas. Las guías vigentes indican que H10 y los límites docentes están retirados; no se implementaron.

## Archivos

| Ruta | Acción (creado / modificado) | Qué cambió | Por qué |
| --- | --- | --- | --- |
| `frontend/src/features/profesor/TeacherDashboard.tsx` | modificado | Usa validador compartido y etiqueta legible de curso mock en selector y cursos aptos; conserva el ID original para propuestas | Mejorar la lectura de fixtures sin modificar payloads |
| `frontend/src/features/profesor/availability.ts` | creado | Convierte y valida día y horas, límites 00:00–24:00 y rango semiabierto con fin posterior al inicio | Regla de disponibilidad verificable y reutilizable |
| `frontend/src/features/profesor/courseLabel.ts` | creado | Devuelve etiqueta normal para cursos reales y `Curso #ID (Mock)` cuando campos de ejemplo valen `string` | Claridad de datos mock |
| `frontend/src/features/profesor/availability.test.ts` | creado | Cubre franjas válidas, 24:00, día fuera de rango, horas mal formadas y rangos no positivos | Cubrir límites del contrato y validación de rango |
| `frontend/src/features/profesor/TeacherDashboard.test.tsx` | creado | Prueba carga de pantallas, etiqueta mock, guardado de disponibilidad en minutos, rechazo de rango igual y envío/recarga de propuesta | Cobertura de los flujos principales de profesor |
| `frontend/src/features/profesor/LoginPage.test.tsx` | creado | Prueba envío de credenciales y navegación al portal según rol devuelto | Cubrir el inicio de sesión |
| `frontend/src/features/profesor/time.test.ts` | modificado | Añade casos para hora 25:00 y minutos 60 | Verificar formato estricto HH:MM |
| `frontend/src/app/RouteGuards.test.tsx` | creado | Verifica redirección al login sin sesión y redirección de rol incompatible | Comprobar bloqueo de rutas protegidas |
| `frontend/package.json` | modificado | Usa utilidades de Testing Library y jsdom instaladas en esta sesión | Pruebas React DOM reproducibles |
| `frontend/package-lock.json` | modificado | Registra dependencias de testing añadidas | Instalación determinista |
| `docs/cambios/2026-11-24_1842_M5_cierre-qa-profesor.md` | creado | Reporte final de QA | Requisito de reporte M5 |

## Contratos e interfaces afectados

Ninguno. `contracts/openapi.yaml` no se modificó. El cuerpo de disponibilidad sigue enviando `dia`, `inicioMin` y `finMin` como enteros; la propuesta conserva `cursoId` numérico. Las etiquetas mock solo afectan la presentación.

## Cómo verificarlo

Desde `frontend/`:

- `npm run build`: correcto; TypeScript y bundle de producción finalizaron.
- `npm run lint`: correcto; Oxlint sin avisos.
- `npm test`: correcto; 6 archivos de prueba, 23 pruebas aprobadas, 0 fallidas.
- Las pruebas de UI usan funciones de API simuladas; no sustituyen la integración con una API real.

## Supuestos y decisiones tomadas

- Se considera mock un curso cuando `codigo` o `nombre` es exactamente el literal `string`, patrón de fixtures de Prism. Solo se cambia la etiqueta presentada; se conserva `course.id` como valor del `<option>` y `cursoId` del payload.
- Un intervalo debe tener día entre 1 y 7, hora de inicio entre 00:00 y 23:59, hora de fin entre 00:01 y 24:00 y `fin > inicio`. `24:00` se admite únicamente como fin y se envía como 1440, de acuerdo con minutos desde medianoche e intervalos `[inicio, fin)`.
- Se siguió `docs/ANTES_DE_DESARROLLAR.md` y el contrato vigente: H10 está retirado y no se implementan límites. La guía M5 adjunta aún los menciona en su lista histórica; la aclaración prioritaria y el contrato actual prevalecen.

## Pendientes y bloqueos

- No hay bloqueos para las pruebas frontend solicitadas.
- Las pruebas de integración contra la API real y el validador Haskell siguen siendo entregables de QA separados; este cierre verifica interfaz y payloads mediante dobles de API.

## Qué deben saber los otros agentes

- M1: nada.
- M2: nada.
- M3: no se modificó el contrato ni el backend.
- M4: no se modificaron sus rutas ni componentes.
- M5: las conversiones/validación viven en `frontend/src/features/profesor/availability.ts`; no añadir H10 ni límites.

## Archivos leídos como contexto

- `C:\Users\milag\Desktop\Descargas\guias-ia\M5_frontend_profesor_qa.md`
- `docs/ANTES_DE_DESARROLLAR.md`
- `contracts/openapi.yaml`
- `docs/SETUP.md`
- `docs/cambios/2026-11-23_0013_M2_dominio-y-reglas.md`
- `docs/cambios/2026-11-23_0040_M2_validador-y-casos-de-uso.md`
- `docs/cambios/2026-11-24_0345_M3_api-sqlite-y-trabajos.md`
- `docs/solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M2_integracion-repositorio.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M4_api-borrador.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M5_api-borrador-y-proxy.md`
- `docs/solicitudes/2026-11-24_1403_M5_a_M3_comando-prism.md`
- `docs/cambios/2026-11-24_1251_M5_bootstrap-frontend.md`
- `docs/cambios/2026-11-24_1403_M5_login-mock-y-cierre.md`
- `DISENO_v3.md` (adjunto del coordinador, leído en la conversación)
