-- 0001 · Esquema inicial (M3).
-- Las migraciones aplicadas nunca se editan: cualquier cambio va en un archivo nuevo numerado.
-- Convenciones: minutos desde medianoche, intervalos [inicio, fin), días 1 a 7, IDs enteros.
-- El modo WAL y las claves foráneas los activa el servidor en cada conexión (ver docs/db.md).

CREATE TABLE categorias (
  id      INTEGER PRIMARY KEY,
  nombre  TEXT NOT NULL UNIQUE CHECK (length(nombre) > 0)
);

CREATE TABLE profesores (
  id            INTEGER PRIMARY KEY,
  nombre        TEXT NOT NULL CHECK (length(nombre) > 0),
  categoria_id  INTEGER NOT NULL REFERENCES categorias (id) ON DELETE RESTRICT
);

CREATE TABLE cursos (
  id            INTEGER PRIMARY KEY,
  codigo        TEXT NOT NULL UNIQUE CHECK (length(codigo) > 0),
  nombre        TEXT NOT NULL CHECK (length(nombre) > 0),
  categoria_id  INTEGER NOT NULL REFERENCES categorias (id) ON DELETE RESTRICT
);

-- Habilitación del profesor para dictar el curso (cursosAptos / cursosAprobados).
CREATE TABLE profesor_cursos (
  profesor_id  INTEGER NOT NULL REFERENCES profesores (id) ON DELETE CASCADE,
  curso_id     INTEGER NOT NULL REFERENCES cursos (id) ON DELETE RESTRICT,
  PRIMARY KEY (profesor_id, curso_id)
);

CREATE TABLE aulas (
  id         INTEGER PRIMARY KEY,
  codigo     TEXT NOT NULL UNIQUE CHECK (length(codigo) > 0),
  capacidad  INTEGER NOT NULL CHECK (capacidad >= 0),
  edificio   TEXT NOT NULL CHECK (length(edificio) > 0),
  piso       INTEGER NOT NULL,
  tipo       TEXT NOT NULL CHECK (length(tipo) > 0)
);

-- Configuración por período. Los recesos valen todos los días activos.
CREATE TABLE configuraciones (
  periodo_id            INTEGER PRIMARY KEY CHECK (periodo_id > 0),
  inicio_dia_min        INTEGER NOT NULL CHECK (inicio_dia_min BETWEEN 0 AND 1440),
  fin_dia_min           INTEGER NOT NULL CHECK (fin_dia_min BETWEEN 0 AND 1440),
  turno_min             INTEGER NOT NULL CHECK (turno_min IN (45, 50, 60, 90)),
  peso_hueco            INTEGER NOT NULL,
  peso_piso             INTEGER NOT NULL,
  peso_edificio         INTEGER NOT NULL,
  peso_estabilidad      INTEGER NOT NULL,
  tolerancia_hueco_min  INTEGER NOT NULL DEFAULT 0,
  consecutivo_max_min   INTEGER NOT NULL DEFAULT 30,
  timeout_seg           INTEGER NOT NULL
);

CREATE TABLE configuracion_dias (
  periodo_id  INTEGER NOT NULL REFERENCES configuraciones (periodo_id) ON DELETE CASCADE,
  orden       INTEGER NOT NULL,
  dia         INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 7),
  PRIMARY KEY (periodo_id, orden)
);

CREATE TABLE configuracion_recesos (
  periodo_id  INTEGER NOT NULL REFERENCES configuraciones (periodo_id) ON DELETE CASCADE,
  orden       INTEGER NOT NULL,
  inicio_min  INTEGER NOT NULL,
  fin_min     INTEGER NOT NULL,
  PRIMARY KEY (periodo_id, orden)
);

-- Disponibilidad general del profesor por período. La cabecera distingue
-- "registró una disponibilidad vacía" de "no registró disponibilidad".
CREATE TABLE disponibilidades (
  profesor_id  INTEGER NOT NULL REFERENCES profesores (id) ON DELETE CASCADE,
  periodo_id   INTEGER NOT NULL CHECK (periodo_id > 0),
  PRIMARY KEY (profesor_id, periodo_id)
);

CREATE TABLE disponibilidad_franjas (
  profesor_id  INTEGER NOT NULL,
  periodo_id   INTEGER NOT NULL,
  orden        INTEGER NOT NULL,
  dia          INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 7),
  inicio_min   INTEGER NOT NULL,
  fin_min      INTEGER NOT NULL,
  PRIMARY KEY (profesor_id, periodo_id, orden),
  FOREIGN KEY (profesor_id, periodo_id) REFERENCES disponibilidades (profesor_id, periodo_id) ON DELETE CASCADE
);

-- Propuestas del profesor y horarios docentes aprobados por el coordinador.
-- Como máximo una propuesta pendiente y un horario aprobado por profesor, curso y período.
CREATE TABLE horarios_docentes (
  id           INTEGER PRIMARY KEY,
  profesor_id  INTEGER NOT NULL REFERENCES profesores (id) ON DELETE CASCADE,
  curso_id     INTEGER NOT NULL REFERENCES cursos (id) ON DELETE CASCADE,
  periodo_id   INTEGER NOT NULL CHECK (periodo_id > 0),
  estado       TEXT NOT NULL CHECK (estado IN ('propuesto', 'aprobado')),
  UNIQUE (profesor_id, curso_id, periodo_id, estado)
);

CREATE TABLE horario_docente_franjas (
  horario_docente_id  INTEGER NOT NULL REFERENCES horarios_docentes (id) ON DELETE CASCADE,
  orden               INTEGER NOT NULL,
  dia                 INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 7),
  inicio_min          INTEGER NOT NULL,
  fin_min             INTEGER NOT NULL,
  PRIMARY KEY (horario_docente_id, orden)
);

CREATE TABLE secciones (
  id            INTEGER PRIMARY KEY,
  curso_id      INTEGER NOT NULL REFERENCES cursos (id) ON DELETE RESTRICT,
  periodo_id    INTEGER NOT NULL CHECK (periodo_id > 0),
  codigo        TEXT NOT NULL CHECK (length(codigo) > 0),
  matriculados  INTEGER NOT NULL CHECK (matriculados >= 0),
  UNIQUE (periodo_id, codigo)
);

CREATE TABLE seccion_grupos (
  seccion_id  INTEGER NOT NULL REFERENCES secciones (id) ON DELETE CASCADE,
  grupo_id    INTEGER NOT NULL CHECK (grupo_id > 0),
  PRIMARY KEY (seccion_id, grupo_id)
);

-- Una sesión cerrada no participa en los horarios; no se borra para conservar la trazabilidad.
CREATE TABLE sesiones (
  id           INTEGER PRIMARY KEY,
  seccion_id   INTEGER NOT NULL REFERENCES secciones (id) ON DELETE RESTRICT,
  orden        INTEGER NOT NULL,
  duracion_min INTEGER NOT NULL CHECK (duracion_min > 0),
  tipo_aula    TEXT NOT NULL CHECK (length(tipo_aula) > 0),
  cerrada      INTEGER NOT NULL DEFAULT 0 CHECK (cerrada IN (0, 1))
);

CREATE INDEX sesiones_por_seccion ON sesiones (seccion_id);

-- Horarios. `configuracion_json` es la copia de la configuración con la que se creó el horario.
CREATE TABLE horarios (
  id                  INTEGER PRIMARY KEY,
  periodo_id          INTEGER NOT NULL CHECK (periodo_id > 0),
  estado              TEXT NOT NULL CHECK (estado IN ('borrador', 'publicado')),
  origen              TEXT NOT NULL CHECK (origen IN ('manual', 'generado', 'regenerado', 'completado')),
  numero_version      INTEGER CHECK (numero_version BETWEEN 1 AND 4),
  politica            TEXT CHECK (politica IN ('conservar', 'descartar')),
  base_horario_id     INTEGER REFERENCES horarios (id) ON DELETE RESTRICT,
  configuracion_json  TEXT NOT NULL,
  creado_en           TEXT NOT NULL,
  actualizado_en      TEXT NOT NULL
);

CREATE INDEX horarios_por_periodo ON horarios (periodo_id, estado);

CREATE TABLE asignaciones (
  horario_id   INTEGER NOT NULL REFERENCES horarios (id) ON DELETE CASCADE,
  orden        INTEGER NOT NULL,
  sesion_id    INTEGER NOT NULL REFERENCES sesiones (id) ON DELETE RESTRICT,
  profesor_id  INTEGER NOT NULL REFERENCES profesores (id) ON DELETE RESTRICT,
  aula_id      INTEGER NOT NULL REFERENCES aulas (id) ON DELETE RESTRICT,
  dia          INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 7),
  inicio_min   INTEGER NOT NULL CHECK (inicio_min BETWEEN 0 AND 1440),
  fijada       INTEGER NOT NULL CHECK (fijada IN (0, 1)),
  origen       TEXT NOT NULL CHECK (origen IN ('manual', 'automatica')),
  PRIMARY KEY (horario_id, orden),
  UNIQUE (horario_id, sesion_id)
);

CREATE INDEX asignaciones_por_sesion ON asignaciones (sesion_id);

CREATE TABLE horario_sin_asignar (
  horario_id  INTEGER NOT NULL REFERENCES horarios (id) ON DELETE CASCADE,
  orden       INTEGER NOT NULL,
  sesion_id   INTEGER NOT NULL REFERENCES sesiones (id) ON DELETE RESTRICT,
  PRIMARY KEY (horario_id, orden),
  UNIQUE (horario_id, sesion_id)
);

CREATE INDEX sin_asignar_por_sesion ON horario_sin_asignar (sesion_id);

-- Avisos por cambios de disponibilidad sobre clases publicadas.
-- Un aviso tiene dos destinatarios: el profesor afectado y el coordinador.
CREATE TABLE avisos (
  id           INTEGER PRIMARY KEY,
  horario_id   INTEGER NOT NULL REFERENCES horarios (id) ON DELETE CASCADE,
  sesion_id    INTEGER NOT NULL,
  profesor_id  INTEGER NOT NULL,
  aula_id      INTEGER NOT NULL,
  dia          INTEGER NOT NULL CHECK (dia BETWEEN 1 AND 7),
  inicio_min   INTEGER NOT NULL,
  creado_en    TEXT NOT NULL
);

CREATE INDEX avisos_por_profesor ON avisos (profesor_id);

-- Usuarios: la contraseña se guarda solo como hash bcrypt (incluye la sal).
CREATE TABLE usuarios (
  id               INTEGER PRIMARY KEY,
  usuario          TEXT NOT NULL UNIQUE CHECK (length(usuario) > 0),
  hash_contrasena  TEXT NOT NULL,
  rol              TEXT NOT NULL CHECK (rol IN ('profesor', 'coordinador')),
  profesor_id      INTEGER UNIQUE REFERENCES profesores (id) ON DELETE CASCADE,
  CHECK ((rol = 'profesor') = (profesor_id IS NOT NULL))
);

-- Tokens de sesión: solo se guarda el SHA-256 del token, nunca el token.
CREATE TABLE tokens (
  hash_token  TEXT PRIMARY KEY,
  usuario_id  INTEGER NOT NULL REFERENCES usuarios (id) ON DELETE CASCADE,
  expira_en   TEXT NOT NULL
);

-- Trabajos asíncronos de generación. Persisten para sobrevivir a un reinicio.
CREATE TABLE trabajos (
  id               INTEGER PRIMARY KEY,
  estado           TEXT NOT NULL CHECK (estado IN ('pendiente', 'ejecutando', 'terminado', 'error')),
  periodo_id       INTEGER NOT NULL,
  modo             TEXT NOT NULL CHECK (modo IN ('generar', 'completar')),
  base_horario_id  INTEGER,
  politica         TEXT CHECK (politica IN ('conservar', 'descartar')),
  max_versiones    INTEGER NOT NULL CHECK (max_versiones BETWEEN 1 AND 4),
  resultado_json   TEXT,
  error_json       TEXT,
  creado_en        TEXT NOT NULL,
  actualizado_en   TEXT NOT NULL
);

CREATE INDEX trabajos_por_estado ON trabajos (estado);
