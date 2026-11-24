# Arranque local (dueño: M3). Pensado para Linux, macOS o WSL2 en Windows.
# Variables útiles: HORARIO_PUERTO, HORARIO_BD, HORARIO_COORDINADOR_USUARIO, HORARIO_COORDINADOR_CONTRASENA,
# HORARIO_SWIPL, HORARIO_MOTOR_ARGS, HORARIO_MOTOR_DIR. Ver docs/SETUP.md.

STACK ?= stack
NPX ?= npx

.PHONY: dev backend backend-build backend-test mock frontend

# Levanta cada capa disponible: la API (que invoca el motor Prolog por trabajo) y el frontend si existe.
dev: backend-build
	@if [ -f frontend/package.json ]; then \
		echo "[dev] API en :$${HORARIO_PUERTO:-8080} y frontend con Vite"; \
		( cd backend && $(STACK) exec horario-servidor ) & \
		( cd frontend && npm run dev ); \
	else \
		echo "[dev] Sin frontend todavía: solo la API en :$${HORARIO_PUERTO:-8080}"; \
		cd backend && $(STACK) exec horario-servidor; \
	fi

backend-build:
	$(STACK) build

backend: backend-build
	cd backend && $(STACK) exec horario-servidor

backend-test:
	$(STACK) test

# Mock de la API desde el contrato, para trabajar sin backend (puerto 4010).
mock:
	$(NPX) prism mock contracts/openapi.yaml

frontend:
	cd frontend && npm run dev
