# Frontend M5

Aplicación React + TypeScript + Vite. El cliente usa los tipos generados desde
`../contracts/openapi.yaml`; no edites manualmente `src/api/schema.d.ts`.

## Desarrollo con Prism

Desde la raíz del repositorio, en una terminal:

```powershell
npx prism mock contracts/openapi.yaml
```

En otra terminal:

```powershell
Set-Location .\frontend
npm run dev
```

Abre la URL que imprime Vite (por defecto `http://localhost:5173`). El proxy
`/api` reenvía a `http://localhost:4010` y elimina el prefijo antes de enviar la
solicitud a Prism.

Para cambiar el destino del proxy en la sesión actual de PowerShell:

```powershell
$env:VITE_API_PROXY_TARGET = 'http://localhost:8080'
npm run dev
```

La variable también se puede establecer en `.env.local` a partir de
`.env.example`. La API real no envía CORS; el proxy de Vite permite usar
`/api/...` en ambos casos.

El ejemplo de `POST /auth/login` en el contrato es de coordinador. Para entrar
al módulo de profesor con Prism, usa cualquier nombre de usuario distinto de
`coordinador` (por ejemplo `profesor1`). En modo mock, la interfaz adapta la
respuesta de ejemplo a una sesión docente con `profesorId: 1`; esta adaptación
no cambia el contrato. Se habilita automáticamente cuando el destino configurado
usa el puerto `4010`, y no se aplica cuando el proxy apunta a la API real (`8080`).

## Tipos OpenAPI

Desde `frontend/`:

```powershell
npm run api:types
```

## Validación

```powershell
npm run build
npm run lint
```
