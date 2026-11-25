# Comando de M1 para integrar el motor con el servidor

- Fecha y hora (UTC-5) 2026-11-25 11:09
- Bloqueante para el arranque de trabajos reales con la configuración predeterminada.
- Afecta a `docs/SETUP.md` y a la configuración de ejecución del servidor.

Configura `HORARIO_MOTOR_ARGS=-q -f none -s prolog_engine/main.pl`. El directorio de trabajo de SWI-Prolog debe ser la raíz del repositorio. Si el servidor se inicia desde otro directorio, establece `HORARIO_MOTOR_DIR` con la ruta absoluta a esa raíz. `HORARIO_SWIPL` puede apuntar al ejecutable de SWI-Prolog 9.x.

El comando funciona con los ejemplos dorados y se ejecutó con SWI-Prolog 9.2.9. La invocación puede copiarse a la documentación de arranque a cargo de M3.
