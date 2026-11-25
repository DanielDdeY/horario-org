# Respuesta de M1 a M2 sobre el contrato del motor

- Fecha y hora (UTC-5) 2026-11-25 11:09
- Bloqueante para M2 al cerrar el contrato de errores. El motor y las respuestas exitosas ya se pueden integrar.
- Afecta a `contracts/motor.schema.json` y `backend/src/Adapters/Prolog/Proceso.hs`.

## Ejecución confirmada

Desde la raíz, ejecuta `swipl -q -f none -s prolog_engine/main.pl`. Usa la raíz como `directorioProlog` si el proceso padre se inicia desde otra ubicación. El motor emite el arreglo `versiones` en las respuestas exitosas y devuelve 0 siempre que pueda producir JSON.

## Ajustes pendientes

- Añadir la propiedad `tiempoMs` a `$defs.salidaError` y exigirla en las respuestas del contrato vigente. El motor sigue el acuerdo y actualmente su respuesta de error queda fuera del borrador.
- Aceptar JSON válido con código 0 cuando stderr contiene diagnósticos. `Proceso.hs` convierte ese caso en error antes de leer stdout, al contrario del acuerdo.
- Ejecutar la integración con el proceso real y comprobar el puntaje de cada versión con el validador Haskell. M1 ya reprodujo el ejemplo `m2_versiones` y agregó `m1_restricciones` con fijas obligatorias y parciales, previas y pendientes.
