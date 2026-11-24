# Reporte de cambios: M5 · login mock y cierre de sesión

- Fecha y hora (UTC-5): 2026-11-24 14:03
- Miembro: M5
- Rama y commits: `feat/m5-frontend-profesor` · sin commits
- Estado: Completo

## Resumen

El login conserva la respuesta de OpenAPI sin alterarla. Solo en desarrollo con el proxy al puerto de Prism 4010, un usuario distinto de `coordinador` recibe una sesión docente simulada con `profesorId: 1`; para la API real no hay transformación.
Se mantuvo visible el cierre de sesión en las vistas de profesor y en el espacio de coordinador.

## Archivos

| Ruta | Acción (creado / modificado) | Qué cambió | Por qué |
| --- | --- | --- | --- |
| `frontend/vite.config.ts` | modificado | Lee `VITE_API_PROXY_TARGET`, conserva 4010 por defecto, cambia mock mode según destino y desactiva la adaptación en build de producción | Probar mock sin afectar la API real |
| `frontend/.env.example` | modificado | Documenta el destino por variable | Facilitar cambio a `http://localhost:8080` |
| `frontend/src/app/auth/AuthProvider.tsx` | modificado | Normaliza la sesión mock antes de persistirla | Permitir entrar al módulo profesor con el ejemplo estático de Prism |
| `frontend/src/app/auth/mockSession.ts` | creado | Aísla la simulación del rol exclusivamente del cliente | Mantener intacta la respuesta/contrato API |
| `frontend/src/app/auth/mockSession.test.ts` | creado | Prueba usuario profesor, coordinador y respuesta de API real | Cubrir el comportamiento de roles mock |
| `frontend/src/app/RouteGuards.tsx` | modificado | Añade botón visible de cerrar sesión a la vista reservada al coordinador; el botón de profesor ya está en su barra superior | Poder salir y cambiar de usuario desde ambas vistas |
| `frontend/README.md` | modificado | Explica el login mock, el modo real y el proxy por ambiente | Instrucciones locales coherentes con el comportamiento |
| `frontend/src/features/profesor/time.test.ts` | creado en el avance anterior de esta sesión | Pruebas de conversión HH:MM/minutos y fin del día | Asegurar el formato de disponibilidad |
| `frontend/.tsupgrader/runtime-validation/eval-plan.json` | creado en el avance anterior de esta sesión | Plan de build, lint, pruebas y HTTP probe | Reproducción de la validación |
| `docs/solicitudes/2026-11-24_1403_M5_a_M3_comando-prism.md` | creado | Solicita corregir el comando Prism que no se ejecuta en este entorno | Mantener SETUP como referencia utilizable |
| `docs/cambios/2026-11-24_1403_M5_login-mock-y-cierre.md` | creado | Registro de la sesión | Requisito de reporte M5 |

## Contratos e interfaces afectados

Ninguno. `contracts/openapi.yaml` no se modificó. La adaptación de rol ocurre solo en la sesión guardada en el cliente, cuando se detecta modo desarrollo con destino `:4010`.

## Cómo verificarlo

Desde `frontend/`:

- `npm run build`: correcto.
- `npm run lint`: correcto, sin avisos.
- `npm test`: correcto; 2 archivos y 7 pruebas pasan.
- Comprobación HTTP previa: `POST http://localhost:5173/api/auth/login` fue reenviado al mock y devolvió el ejemplo de rol `coordinador`; la transformación a rol profesor está cubierta por pruebas unitarias.
- El plan `.tsupgrader/runtime-validation/eval-plan.json` se ejecutó antes de este cambio y pasó 4/4 aserciones; tras los cambios de login se volvieron a ejecutar build, lint y tests directamente.
- `git diff --check`: correcto.

## Supuestos y decisiones tomadas

- El mock básico responde siempre con el ejemplo de coordinador. En vez de cambiar la respuesta o el contrato, se crea una copia de la sesión con rol `profesor` e ID 1 cuando el usuario no es `coordinador`.
- Modo mock se infiere del proxy al puerto 4010 en desarrollo; el destino real 8080 no aplica la adaptación. Un build de producción nunca activa esta simulación.
- El comando `npx prism mock ...` documentado no encontró ejecutable en esta máquina. El comando `npx @stoplight/prism-cli mock ...` sí levantó Prism en 4010; se envió solicitud a M3 porque SETUP es de su propiedad.

## Pendientes y bloqueos

- M3: atender `docs/solicitudes/2026-11-24_1403_M5_a_M3_comando-prism.md`.
- El mock genera datos de ejemplo; no representa autenticación real ni persistencia.
- La revisión e2e de navegador se omitió a petición de usar la alternativa HTTP probe, sin instalar Playwright aislado.

## Qué deben saber los otros agentes

- M1: nada.
- M2: nada.
- M3: la interfaz no cambia OpenAPI; el comando Prism alternativo comprobado está en la solicitud.
- M4: `AppRouter` acepta `coordinatorRoutes` como prop para inyectar rutas de coordinador; el placeholder tiene cierre de sesión.
- M5: usa `profesor1` (o cualquier usuario no coordinador) con Prism; la API real no aplica la simulación. Para salir, usa «Cerrar sesión».

## Archivos leídos como contexto

- `docs/ANTES_DE_DESARROLLAR.md`
- `docs/SETUP.md`
- `contracts/openapi.yaml`
- `docs/cambios/2026-11-23_0013_M2_dominio-y-reglas.md`
- `docs/cambios/2026-11-23_0040_M2_validador-y-casos-de-uso.md`
- `docs/cambios/2026-11-24_0345_M3_api-sqlite-y-trabajos.md`
- `docs/solicitudes/2026-11-23_0040_M2_a_M1_contrato-del-motor.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M2_integracion-repositorio.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M4_api-borrador.md`
- `docs/solicitudes/2026-11-24_0345_M3_a_M5_api-borrador-y-proxy.md`
- `docs/cambios/2026-11-24_1251_M5_bootstrap-frontend.md`
- `C:\Users\milag\Desktop\Descargas\guias-ia\M5_frontend_profesor_qa.md`
- `DISENO_v3.md` (adjunto del coordinador, leído en la conversación)
