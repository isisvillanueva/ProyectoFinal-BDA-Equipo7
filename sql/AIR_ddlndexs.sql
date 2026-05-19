CREATE DATABASE hospital_db;

-- \c hospital_db;
-- =========================
-- 1. BASE HUMANA
-- =========================

CREATE TABLE persona (
    id_persona SERIAL PRIMARY KEY,
    nombre_persona VARCHAR(100) NOT NULL,
    apellido_persona VARCHAR(100) NOT NULL,
    correo_persona VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE roles_usuario (
    id_rol_usuario SERIAL PRIMARY KEY,
    rol_usuario VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE usuario (
    id_usuario SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    contrasenia TEXT NOT NULL,
    activo_usuario BOOLEAN NOT NULL DEFAULT TRUE,
    id_persona INT NOT NULL,
    FOREIGN KEY (id_persona) REFERENCES persona(id_persona)
);

CREATE TABLE usuario_rol (
    id_usuario INT NOT NULL,
    id_rol_usuario INT NOT NULL,
    PRIMARY KEY (id_usuario, id_rol_usuario),
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    FOREIGN KEY (id_rol_usuario) REFERENCES roles_usuario(id_rol_usuario)
);

CREATE TABLE turnos (
    id_turno SERIAL PRIMARY KEY,
    nombre_turno VARCHAR(50) NOT NULL UNIQUE,
    hora_inicio TIME NOT NULL,
    hora_fin TIME NOT NULL
);

CREATE TABLE especialidades_medico (
    id_especialidad_medico SERIAL PRIMARY KEY,
    especialidad_medico VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE especialidades_enfermero (
    id_especialidad_enfermero SERIAL PRIMARY KEY,
    especialidad_enfermero VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE medico (
    id_medico SERIAL PRIMARY KEY,
    id_persona INT NOT NULL UNIQUE,
    id_especialidad_medico INT NOT NULL,
    id_turno INT NOT NULL,
    FOREIGN KEY (id_persona) REFERENCES persona(id_persona),
    FOREIGN KEY (id_especialidad_medico) REFERENCES especialidades_medico(id_especialidad_medico),
    FOREIGN KEY (id_turno) REFERENCES turnos(id_turno)
);

CREATE TABLE enfermero (
    id_enfermero SERIAL PRIMARY KEY,
    id_persona INT NOT NULL UNIQUE,
    id_especialidad_enfermero INT NOT NULL,
    id_turno INT NOT NULL,
    FOREIGN KEY (id_persona) REFERENCES persona(id_persona),
    FOREIGN KEY (id_especialidad_enfermero) REFERENCES especialidades_enfermero(id_especialidad_enfermero),
    FOREIGN KEY (id_turno) REFERENCES turnos(id_turno)
);

CREATE TABLE biomedico (
    id_biomedico SERIAL PRIMARY KEY,
    id_persona INT NOT NULL UNIQUE,
    id_turno INT NOT NULL,
    FOREIGN KEY (id_persona) REFERENCES persona(id_persona),
    FOREIGN KEY (id_turno) REFERENCES turnos(id_turno)
);


-- =========================
-- 2. ESTRUCTURA ESPACIAL
-- =========================

CREATE TABLE area_registro (
    id_area SERIAL PRIMARY KEY,
    nombre_area VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE ubicacion_especifica (
    id_ubicacion SERIAL PRIMARY KEY,
    nombre_ubicacion VARCHAR(100) NOT NULL,
    id_area INT NOT NULL,
    UNIQUE (nombre_ubicacion, id_area),
    FOREIGN KEY (id_area) REFERENCES area_registro(id_area)
);

CREATE TABLE zona_beacon (
    id_zona_beacon SERIAL PRIMARY KEY,
    nombre_zona_beacon VARCHAR(100) NOT NULL,
    id_ubicacion INT NOT NULL,
    UNIQUE (nombre_zona_beacon, id_ubicacion),
    FOREIGN KEY (id_ubicacion) REFERENCES ubicacion_especifica(id_ubicacion)
);


-- =========================
-- 3. CATÁLOGOS DEL ACTIVO
-- =========================

CREATE TABLE categoria_equipos (
    id_categoria_equipo SERIAL PRIMARY KEY,
    categoria_equipo VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE tipo_equipos (
    id_tipo_equipo SERIAL PRIMARY KEY,
    tipo_equipo VARCHAR(100) NOT NULL UNIQUE,
    id_categoria_equipo INT NOT NULL,
    FOREIGN KEY (id_categoria_equipo) REFERENCES categoria_equipos(id_categoria_equipo)
);

CREATE TABLE criticidad_equipos (
    id_criticidad_equipo SERIAL PRIMARY KEY,
    criticidad_equipo VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE estado_equipos (
    id_estado_equipo SERIAL PRIMARY KEY,
    estado_equipo VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE marca_equipo (
    id_marca SERIAL PRIMARY KEY,
    nombre_marca VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE modelo_equipo (
    id_modelo SERIAL PRIMARY KEY,
    nombre_modelo VARCHAR(100) NOT NULL,
    id_marca INT NOT NULL,
    UNIQUE (nombre_modelo, id_marca),
    FOREIGN KEY (id_marca) REFERENCES marca_equipo(id_marca)
);


-- =========================
-- 4. ACTIVO PRINCIPAL
-- =========================

CREATE TABLE equipo (
    id_equipo SERIAL PRIMARY KEY,
    codigo_interno VARCHAR(50) NOT NULL UNIQUE,
    nombre_equipo VARCHAR(100) NOT NULL,
    id_modelo INT NOT NULL,
    numero_serie VARCHAR(100) NOT NULL UNIQUE,
    id_tipo_equipo INT NOT NULL,
    id_criticidad_equipo INT NOT NULL,
    id_estado_equipo INT NOT NULL,
    id_ubicacion_administrativa_actual INT NOT NULL,
    activo_equipo BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_modelo) REFERENCES modelo_equipo(id_modelo),
    FOREIGN KEY (id_tipo_equipo) REFERENCES tipo_equipos(id_tipo_equipo),
    FOREIGN KEY (id_criticidad_equipo) REFERENCES criticidad_equipos(id_criticidad_equipo),
    FOREIGN KEY (id_estado_equipo) REFERENCES estado_equipos(id_estado_equipo),
    FOREIGN KEY (id_ubicacion_administrativa_actual) REFERENCES ubicacion_especifica(id_ubicacion)
);


-- =========================
-- 5. RELACIONES OPERATIVAS
-- =========================

CREATE TABLE especialidad_area_enfermero (
    id_especialidad_enfermero INT NOT NULL,
    id_area                   INT NOT NULL,
    PRIMARY KEY (id_especialidad_enfermero, id_area),
    FOREIGN KEY (id_especialidad_enfermero)
        REFERENCES especialidades_enfermero(id_especialidad_enfermero),
    FOREIGN KEY (id_area)
        REFERENCES area_registro(id_area)
);

CREATE TABLE responsable_area (
    id_responsable_area SERIAL PRIMARY KEY,
    id_enfermero INT NOT NULL,
    id_area INT NOT NULL,
    fecha_inicio_responsable_area TIMESTAMP NOT NULL,
    fecha_fin_responsable_area TIMESTAMP,
    CHECK (
        fecha_fin_responsable_area IS NULL
        OR fecha_fin_responsable_area >= fecha_inicio_responsable_area
    ),
    FOREIGN KEY (id_enfermero) REFERENCES enfermero(id_enfermero),
    FOREIGN KEY (id_area) REFERENCES area_registro(id_area)
);

CREATE TABLE estado_asignacion (
    id_estado_asignacion SERIAL PRIMARY KEY,
    estado_asignacion VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE asignacion_equipo (
    id_asignacion SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_persona_responsable INT NOT NULL,
    id_ubicacion INT NOT NULL,
    fecha_inicio_asignacion TIMESTAMP NOT NULL,
    fecha_fin_asignacion TIMESTAMP,
    id_estado_asignacion INT NOT NULL,
    observacion_asignacion TEXT,
    CHECK (
        fecha_fin_asignacion IS NULL
        OR fecha_fin_asignacion >= fecha_inicio_asignacion
    ),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_persona_responsable) REFERENCES persona(id_persona),
    FOREIGN KEY (id_ubicacion) REFERENCES ubicacion_especifica(id_ubicacion),
    FOREIGN KEY (id_estado_asignacion) REFERENCES estado_asignacion(id_estado_asignacion)
);

CREATE TABLE tipo_movimientos (
    id_tipo_movimiento SERIAL PRIMARY KEY,
    tipo_movimiento VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE movimiento (
    id_movimiento SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_persona_responsable_movimiento INT NOT NULL,
    fecha_hora_movimiento TIMESTAMP NOT NULL,
    id_tipo_movimiento INT NOT NULL,
    id_ubicacion_origen INT NOT NULL,
    id_ubicacion_destino INT NOT NULL,
    motivo_movimiento TEXT,
    observacion_movimiento TEXT,
    CHECK (id_ubicacion_origen <> id_ubicacion_destino),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_persona_responsable_movimiento) REFERENCES persona(id_persona),
    FOREIGN KEY (id_tipo_movimiento) REFERENCES tipo_movimientos(id_tipo_movimiento),
    FOREIGN KEY (id_ubicacion_origen) REFERENCES ubicacion_especifica(id_ubicacion),
    FOREIGN KEY (id_ubicacion_destino) REFERENCES ubicacion_especifica(id_ubicacion)
);

CREATE TABLE tipo_procedimiento (
    id_tipo_procedimiento SERIAL PRIMARY KEY,
    tipo_procedimiento VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE uso_clinico_equipo (
    id_uso_clinico SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_persona_responsable_uso INT NOT NULL,
    fecha_hora_inicio TIMESTAMP NOT NULL,
    fecha_hora_fin TIMESTAMP,
    id_area INT NOT NULL,
    id_turno INT NOT NULL,
    id_tipo_procedimiento INT NOT NULL,
    motivo_uso TEXT,
    CHECK (
        fecha_hora_fin IS NULL
        OR fecha_hora_fin >= fecha_hora_inicio
    ),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_persona_responsable_uso) REFERENCES persona(id_persona),
    FOREIGN KEY (id_area) REFERENCES area_registro(id_area),
    FOREIGN KEY (id_turno) REFERENCES turnos(id_turno),
    FOREIGN KEY (id_tipo_procedimiento) REFERENCES tipo_procedimiento(id_tipo_procedimiento)
);


-- =========================
-- 6. MANTENIMIENTO
-- =========================

CREATE TABLE tipo_mantenimientos (
    id_tipo_mantenimiento SERIAL PRIMARY KEY,
    tipo_mantenimiento VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE tipo_resultado_mantenimientos (
    id_resultado_mantenimiento SERIAL PRIMARY KEY,
    resultado_mantenimiento VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE prioridad_mantenimientos (
    id_prioridad_mantenimiento SERIAL PRIMARY KEY,
    prioridad_mantenimiento VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE estado_cumplimiento_mantenimientos (
    id_estado_cumplimiento SERIAL PRIMARY KEY,
    estado_cumplimiento VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE mantenimiento_programado (
    id_programacion SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_tipo_mantenimiento INT NOT NULL,
    frecuencia_dias INT NOT NULL CHECK (frecuencia_dias > 0),
    fecha_ultimo_mantenimiento TIMESTAMP,
    fecha_proximo_mantenimiento TIMESTAMP NOT NULL,
    id_prioridad_mantenimiento INT NOT NULL,
    sla_horas INT NOT NULL CHECK (sla_horas > 0),
    id_estado_cumplimiento INT NOT NULL,
    observacion_programacion TEXT,
    CHECK (
        fecha_ultimo_mantenimiento IS NULL
        OR fecha_proximo_mantenimiento >= fecha_ultimo_mantenimiento
    ),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_tipo_mantenimiento) REFERENCES tipo_mantenimientos(id_tipo_mantenimiento),
    FOREIGN KEY (id_prioridad_mantenimiento) REFERENCES prioridad_mantenimientos(id_prioridad_mantenimiento),
    FOREIGN KEY (id_estado_cumplimiento) REFERENCES estado_cumplimiento_mantenimientos(id_estado_cumplimiento)
);

CREATE TABLE mantenimiento (
    id_mantenimiento SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_biomedico INT NOT NULL,
    fecha_hora_mantenimiento TIMESTAMP NOT NULL,
    id_programacion INT,
    id_tipo_mantenimiento INT NOT NULL,
    descripcion_mantenimiento TEXT NOT NULL,
    id_resultado_mantenimiento INT NOT NULL,
    costo_mantenimiento NUMERIC CHECK (costo_mantenimiento IS NULL OR costo_mantenimiento >= 0),
    observacion_mantenimiento TEXT,
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_biomedico) REFERENCES biomedico(id_biomedico),
    FOREIGN KEY (id_programacion) REFERENCES mantenimiento_programado(id_programacion),
    FOREIGN KEY (id_tipo_mantenimiento) REFERENCES tipo_mantenimientos(id_tipo_mantenimiento),
    FOREIGN KEY (id_resultado_mantenimiento) REFERENCES tipo_resultado_mantenimientos(id_resultado_mantenimiento)
);


-- =========================
-- 7. DISPOSITIVOS Y EVENTOS NFC/BEACON
-- =========================

CREATE TABLE dispositivo_nfc (
    id_nfc SERIAL PRIMARY KEY,
    codigo_uid_nfc VARCHAR(100) NOT NULL UNIQUE,
    id_equipo INT NOT NULL UNIQUE,
    activo_nfc BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo)
);

CREATE TABLE tipo_eventos_nfc (
    id_tipo_evento_nfc SERIAL PRIMARY KEY,
    tipo_evento_nfc VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE evento_nfc (
    id_evento_nfc SERIAL PRIMARY KEY,
    id_nfc INT NOT NULL,
    fecha_hora_evento TIMESTAMP NOT NULL,
    id_tipo_evento_nfc INT NOT NULL,
    FOREIGN KEY (id_nfc) REFERENCES dispositivo_nfc(id_nfc),
    FOREIGN KEY (id_tipo_evento_nfc) REFERENCES tipo_eventos_nfc(id_tipo_evento_nfc)
);

CREATE TABLE dispositivo_beacon (
    id_beacon SERIAL PRIMARY KEY,
    uuid_beacon VARCHAR(100) NOT NULL,
    major_beacon INT NOT NULL CHECK (major_beacon >= 0),
    minor_beacon INT NOT NULL CHECK (minor_beacon >= 0),
    activo_beacon BOOLEAN NOT NULL DEFAULT TRUE,
    id_zona_beacon INT NOT NULL,
    UNIQUE (uuid_beacon, major_beacon, minor_beacon),
    FOREIGN KEY (id_zona_beacon) REFERENCES zona_beacon(id_zona_beacon)
);

CREATE TABLE tipo_eventos_beacon (
    id_tipo_evento_beacon SERIAL PRIMARY KEY,
    tipo_evento_beacon VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE evento_beacon (
    id_evento_beacon SERIAL PRIMARY KEY,
    id_beacon INT NOT NULL,
    id_equipo INT NOT NULL,
    fecha_hora_evento TIMESTAMP NOT NULL,
    id_tipo_evento_beacon INT NOT NULL,
    FOREIGN KEY (id_beacon) REFERENCES dispositivo_beacon(id_beacon),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_tipo_evento_beacon) REFERENCES tipo_eventos_beacon(id_tipo_evento_beacon)
);


-- =========================
-- 8. AMBULANCIA Y GPS
-- =========================

CREATE TABLE estado_ambulancias (
    id_estado_ambulancia SERIAL PRIMARY KEY,
    estado_ambulancia VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE ambulancia (
    id_ambulancia SERIAL PRIMARY KEY,
    codigo_ambulancia VARCHAR(50) NOT NULL UNIQUE,
    placa VARCHAR(50) NOT NULL UNIQUE,
    id_estado_ambulancia INT NOT NULL,
    activo_ambulancia BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (id_estado_ambulancia) REFERENCES estado_ambulancias(id_estado_ambulancia)
);

CREATE TABLE dispositivo_gps (
    id_gps SERIAL PRIMARY KEY,
    codigo_gps VARCHAR(100) NOT NULL UNIQUE,
    activo_gps BOOLEAN NOT NULL DEFAULT TRUE,
    id_ambulancia INT NOT NULL UNIQUE,
    FOREIGN KEY (id_ambulancia) REFERENCES ambulancia(id_ambulancia)
);

CREATE TABLE evento_gps (
    id_evento_gps SERIAL PRIMARY KEY,
    id_gps INT NOT NULL,
    fecha_hora_evento TIMESTAMP NOT NULL,
    latitud NUMERIC NOT NULL CHECK (latitud >= -90 AND latitud <= 90),
    longitud NUMERIC NOT NULL CHECK (longitud >= -180 AND longitud <= 180),
    precision NUMERIC CHECK (precision IS NULL OR precision >= 0),
    FOREIGN KEY (id_gps) REFERENCES dispositivo_gps(id_gps)
);


-- =========================
-- 9. TRASLADO EXTERNO
-- =========================

CREATE TABLE tipo_traslado_externo (
    id_tipo_traslado SERIAL PRIMARY KEY,
    tipo_traslado VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE traslado_externo_equipo (
    id_traslado_externo SERIAL PRIMARY KEY,
    id_equipo INT NOT NULL,
    id_nfc_equipo INT NOT NULL,
    id_ambulancia INT NOT NULL,
    id_persona_conductor INT NOT NULL,
    fecha_salida TIMESTAMP NOT NULL,
    fecha_llegada TIMESTAMP,
    id_tipo_traslado INT NOT NULL,
    motivo_traslado TEXT,
    observacion_traslado TEXT,
    CHECK (
        fecha_llegada IS NULL
        OR fecha_llegada >= fecha_salida
    ),
    FOREIGN KEY (id_equipo) REFERENCES equipo(id_equipo),
    FOREIGN KEY (id_nfc_equipo) REFERENCES dispositivo_nfc(id_nfc),
    FOREIGN KEY (id_ambulancia) REFERENCES ambulancia(id_ambulancia),
    FOREIGN KEY (id_persona_conductor) REFERENCES persona(id_persona),
    FOREIGN KEY (id_tipo_traslado) REFERENCES tipo_traslado_externo(id_tipo_traslado)
);


-- =========================
-- 10. AUDITORÍA
-- =========================

CREATE TABLE auditoria (
    id_auditoria SERIAL PRIMARY KEY,
    id_usuario INT NOT NULL,
    fecha_hora_auditoria TIMESTAMP NOT NULL,
    accion_auditoria VARCHAR(50) NOT NULL CHECK (
        accion_auditoria IN ('INSERT', 'UPDATE', 'DELETE_LOGICO', 'ACTIVACION', 'DESACTIVACION')
    ),
    tabla_afectada VARCHAR(100) NOT NULL,
    id_registro_afectado INT NOT NULL,
    valor_antes TEXT,
    valor_despues TEXT,
    origen_cambio VARCHAR(100) NOT NULL,
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
);

