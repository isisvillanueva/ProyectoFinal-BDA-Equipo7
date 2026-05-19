-- ============================================================
-- DATOS SEMILLA (datos de prueba iniciales)
-- hospital_db
-- ============================================================


-- ambulancia
INSERT INTO ambulancia (id_ambulancia, codigo_ambulancia, placa, id_estado_ambulancia, activo_ambulancia) VALUES
(1, 'AMB-001', 'NLE-123-A', 1, TRUE),
(2, 'AMB-002', 'NLE-456-B', 1, TRUE);


-- area_registro
INSERT INTO area_registro (id_area, nombre_area) VALUES
(1, 'Urgencias'),
(2, 'UCI'),
(3, 'Quirófano'),
(4, 'Hospitalización'),
(5, 'Almacén Biomédico'),
(6, 'Neonatal');


-- categoria_equipos
INSERT INTO categoria_equipos (id_categoria_equipo, categoria_equipo) VALUES
(1, 'Diagnóstico'),
(2, 'Terapia'),
(3, 'Soporte Vital'),
(4, 'Monitoreo');


-- criticidad_equipos
INSERT INTO criticidad_equipos (id_criticidad_equipo, criticidad_equipo) VALUES
(1, 'Alta'),
(2, 'Media'),
(3, 'Baja');


-- estado_ambulancias
INSERT INTO estado_ambulancias (id_estado_ambulancia, estado_ambulancia) VALUES
(1, 'Activa'),
(2, 'En mantenimiento'),
(3, 'Fuera de servicio');


-- estado_asignacion
INSERT INTO estado_asignacion (id_estado_asignacion, estado_asignacion) VALUES
(1, 'Activa'),
(2, 'Finalizada'),
(3, 'Cancelada');


-- estado_cumplimiento_mantenimientos
INSERT INTO estado_cumplimiento_mantenimientos (id_estado_cumplimiento, estado_cumplimiento) VALUES
(1, 'Pendiente'),
(2, 'Cumplido'),
(3, 'Vencido'),
(4, 'Reprogramado');


-- estado_equipos
INSERT INTO estado_equipos (id_estado_equipo, estado_equipo) VALUES
(1, 'Disponible'),
(2, 'En uso'),
(3, 'En mantenimiento'),
(4, 'Fuera de servicio'),
(5, 'Retirado'),
(6, 'En préstamo');


-- turnos
INSERT INTO turnos (id_turno, nombre_turno, hora_inicio, hora_fin) VALUES
(1, 'Matutino',   '07:00:00', '15:00:00'),
(2, 'Vespertino', '15:00:00', '23:00:00'),
(3, 'Nocturno',   '23:00:00', '07:00:00');


-- roles_usuario
INSERT INTO roles_usuario (id_rol_usuario, rol_usuario) VALUES
(1, 'Administrador'),
(2, 'Enfermero'),
(3, 'Biomédico'),
(4, 'Médico'),
(5, 'Conductor');


-- especialidades_enfermero
INSERT INTO especialidades_enfermero (id_especialidad_enfermero, especialidad_enfermero) VALUES
(1, 'Cuidados Intensivos'),
(2, 'Urgencias'),
(3, 'Quirófano'),
(4, 'Hospitalización'),
(5, 'Neonatal');


-- especialidades_medico
INSERT INTO especialidades_medico (id_especialidad_medico, especialidad_medico) VALUES
(1, 'Medicina Interna'),
(2, 'Cardiología'),
(3, 'Pediatría'),
(4, 'Anestesiología'),
(5, 'Urgencias');


-- especialidad_area_enfermero
INSERT INTO especialidad_area_enfermero (id_especialidad_enfermero, id_area) VALUES
(1, 2),  -- Cuidados Intensivos → UCI
(2, 1),  -- Urgencias → Urgencias
(3, 3),  -- Quirófano → Quirófano
(4, 4),  -- Hospitalización → Hospitalización
(5, 6);  -- Neonatal → Neonatal


-- marca_equipo
INSERT INTO marca_equipo (id_marca, nombre_marca) VALUES
(1, 'Philips'),
(2, 'Baxter'),
(3, 'GE Healthcare'),
(4, 'Dräger'),
(5, 'Mindray');


-- modelo_equipo
INSERT INTO modelo_equipo (id_modelo, nombre_modelo, id_marca) VALUES
(1, 'MX450',          1),
(2, 'Sigma Spectrum', 2),
(3, 'CARESCAPE B450', 3),
(4, 'Evita V300',     4),
(5, 'BeneHeart D3',   5);


-- tipo_equipos
INSERT INTO tipo_equipos (id_tipo_equipo, tipo_equipo, id_categoria_equipo) VALUES
(1, 'Monitor de signos vitales', 4),
(2, 'Bomba de infusión',         2),
(3, 'Desfibrilador',             3),
(4, 'Ventilador mecánico',       3),
(5, 'Electrocardiógrafo',        1);


-- prioridad_mantenimientos
INSERT INTO prioridad_mantenimientos (id_prioridad_mantenimiento, prioridad_mantenimiento) VALUES
(1, 'Alta'),
(2, 'Media'),
(3, 'Baja');


-- tipo_mantenimientos
INSERT INTO tipo_mantenimientos (id_tipo_mantenimiento, tipo_mantenimiento) VALUES
(1, 'Preventivo'),
(2, 'Correctivo'),
(3, 'Calibración'),
(4, 'Inspección');


-- tipo_resultado_mantenimientos
INSERT INTO tipo_resultado_mantenimientos (id_resultado_mantenimiento, resultado_mantenimiento) VALUES
(1, 'Exitoso'),
(2, 'Fallido'),
(3, 'Pendiente de revisión'),
(4, 'Requiere reemplazo');


-- tipo_movimientos
INSERT INTO tipo_movimientos (id_tipo_movimiento, tipo_movimiento) VALUES
(1, 'Traslado interno'),
(2, 'Reasignación'),
(3, 'Entrega a área'),
(4, 'Retiro de área');


-- tipo_procedimiento
INSERT INTO tipo_procedimiento (id_tipo_procedimiento, tipo_procedimiento) VALUES
(1, 'Monitoreo'),
(2, 'Infusión'),
(3, 'Soporte ventilatorio'),
(4, 'Reanimación'),
(5, 'Diagnóstico');


-- tipo_eventos_beacon
INSERT INTO tipo_eventos_beacon (id_tipo_evento_beacon, tipo_evento_beacon) VALUES
(1, 'Detección'),
(2, 'Pérdida de señal'),
(3, 'Reaparición');


-- tipo_eventos_nfc
INSERT INTO tipo_eventos_nfc (id_tipo_evento_nfc, tipo_evento_nfc) VALUES
(1, 'Lectura'),
(2, 'Verificación'),
(3, 'Asociación');


-- tipo_traslado_externo
INSERT INTO tipo_traslado_externo (id_tipo_traslado, tipo_traslado) VALUES
(2, 'Préstamo temporal');


-- ubicacion_especifica
INSERT INTO ubicacion_especifica (id_ubicacion, nombre_ubicacion, id_area) VALUES
(1, 'Sala Principal Urgencias', 1),
(2, 'Pasillo Urgencias',        1),
(3, 'Cama UCI-01',              2),
(4, 'Cama UCI-02',              2),
(5, 'Sala Quirófano',           3),
(6, 'Bodega Biomédica',         5),
(7, 'Sala Neonatal',            6);


-- zona_beacon
INSERT INTO zona_beacon (id_zona_beacon, nombre_zona_beacon, id_ubicacion) VALUES
(1, 'Zona A - Urgencias', 1),
(2, 'Zona B - UCI',       3),
(3, 'Zona C - Quirófano', 5);


-- dispositivo_gps
INSERT INTO dispositivo_gps (id_gps, codigo_gps, activo_gps, id_ambulancia) VALUES
(1, 'GPS-AMB-001', TRUE, 1),
(2, 'GPS-AMB-002', TRUE, 2);


-- dispositivo_beacon
INSERT INTO dispositivo_beacon (id_beacon, uuid_beacon, major_beacon, minor_beacon, activo_beacon, id_zona_beacon) VALUES
(1, 'BEACON-UUID-URGENCIAS', 1, 1, FALSE, 1),
(2, 'BEACON-UUID-UCI',       2, 1, TRUE,  2),
(3, 'BEACON-UUID-QUIR',      3, 1, FALSE, 3);


-- persona
INSERT INTO persona (id_persona, nombre_persona, apellido_persona, correo_persona) VALUES
(1,  'Admin',    'Sistema',          'admin@hospital.com'),
(2,  'Carlos',   'García',           'c.garcia@hospital.com'),
(3,  'María',    'López',            'm.lopez@hospital.com'),
(4,  'Roberto',  'Ramírez',          'r.ramirez@hospital.com'),
(5,  'Juan',     'Pérez',            'j.perez@hospital.com'),
(6,  'Ana',      'Martínez',         'a.martinez@hospital.com'),
(7,  'Luis',     'Torres',           'l.torres@hospital.com'),
(8,  'Sandra',   'Flores',           's.flores@hospital.com'),
(9,  'Carmen',   'Vega',             'c.vega@hospital.com'),
(10, 'Patricia', 'Morales',          'p.morales@hospital.com'),
(11, 'Diana',    'Castillo',         'd.castillo@hospital.com');


-- usuario
INSERT INTO usuario (id_usuario, username, contrasenia, activo_usuario, id_persona) VALUES
(1,  'admin',    'hashed_admin123',   TRUE, 1),
(2,  'cgarcia',  'hashed_garcia123',  TRUE, 2),
(3,  'mlopez',   'hashed_lopez123',   TRUE, 3),
(4,  'rramirez', 'hashed_ramirez123', TRUE, 4),
(5,  'jperez',   'hashed_perez123',   TRUE, 5),
(6,  'amartinez','hashed_amtz123',    TRUE, 6),
(7,  'ltorres',  'hashed_torres123',  TRUE, 7),
(8,  'sflores',  'hashed_flores123',  TRUE, 8);


-- usuario_rol
INSERT INTO usuario_rol (id_usuario, id_rol_usuario) VALUES
(1, 1),  -- admin → Administrador
(2, 4),  -- cgarcia → Médico
(3, 2),  -- mlopez → Enfermero
(4, 3),  -- rramirez → Biomédico
(5, 5),  -- jperez → Conductor
(6, 2),  -- amartinez → Enfermero
(7, 4),  -- ltorres → Médico
(8, 2);  -- sflores → Enfermero


-- medico
INSERT INTO medico (id_medico, id_persona, id_especialidad_medico, id_turno) VALUES
(1, 2, 5, 1),  -- Carlos García → Urgencias → Matutino
(2, 7, 1, 2);  -- Luis Torres   → Medicina Interna → Vespertino


-- enfermero
INSERT INTO enfermero (id_enfermero, id_persona, id_especialidad_enfermero, id_turno) VALUES
(1, 3,  2, 1),  -- María López   → Urgencias → Matutino
(2, 6,  1, 2),  -- Ana Martínez  → Cuidados Intensivos → Vespertino
(3, 8,  2, 2),  -- Sandra Flores → Urgencias → Vespertino
(4, 9,  3, 1),  -- Carmen Vega   → Quirófano → Matutino
(5, 10, 4, 2),  -- Patricia Morales → Hospitalización → Vespertino
(6, 11, 5, 3);  -- Diana Castillo → Neonatal → Nocturno


-- biomedico
INSERT INTO biomedico (id_biomedico, id_persona, id_turno) VALUES
(1, 4, 1);  -- Roberto Ramírez → Matutino


-- equipo
INSERT INTO equipo (id_equipo, codigo_interno, nombre_equipo, id_modelo, numero_serie, id_tipo_equipo, id_criticidad_equipo, id_estado_equipo, id_ubicacion_administrativa_actual, activo_equipo) VALUES
(1, 'EQ-001', 'Monitor Philips MX450',   1, 'SN-PH-2024-001', 1, 1, 1, 1, TRUE),
(2, 'EQ-002', 'Ventilador Dräger Evita', 4, 'SN-DR-2024-002', 4, 1, 1, 3, TRUE),
(3, 'EQ-003', 'Bomba Baxter Sigma',      2, 'SN-BX-2024-003', 2, 2, 1, 1, TRUE),
(4, 'EQ-004', 'Desfibrilador Mindray D3',5, 'SN-MY-2024-004', 3, 1, 1, 3, TRUE),
(5, 'EQ-005', 'ECG GE CARESCAPE B450',  3, 'SN-GE-2024-005', 5, 3, 1, 3, TRUE);


-- dispositivo_nfc
INSERT INTO dispositivo_nfc (id_nfc, codigo_uid_nfc, id_equipo, activo_nfc) VALUES
(1, 'NFC-UID-EQ001', 1, TRUE),
(2, 'NFC-UID-EQ002', 2, TRUE),
(3, 'NFC-UID-EQ003', 3, TRUE),
(4, 'NFC-UID-EQ004', 4, TRUE),
(5, 'NFC-UID-EQ005', 5, TRUE);


-- responsable_area
INSERT INTO responsable_area (id_responsable_area, id_enfermero, id_area, fecha_inicio_responsable_area, fecha_fin_responsable_area) VALUES
(1, 1, 1, '2025-01-01 07:00:00', NULL),  -- María López → Urgencias
(2, 2, 2, '2025-01-01 15:00:00', NULL);  -- Ana Martínez → UCI


-- asignacion_equipo
INSERT INTO asignacion_equipo (id_asignacion, id_equipo, id_persona_responsable, id_ubicacion, fecha_inicio_asignacion, fecha_fin_asignacion, id_estado_asignacion, observacion_asignacion) VALUES
(1, 1, 3, 1, '2025-01-01 07:00:00', NULL, 1, 'Asignacion inicial monitor urgencias'),
(2, 2, 4, 3, '2025-01-01 07:00:00', NULL, 1, 'Asignacion inicial ventilador UCI'),
(3, 3, 3, 1, '2025-01-01 07:00:00', NULL, 1, 'Asignacion inicial bomba urgencias'),
(4, 4, 4, 3, '2025-01-01 07:00:00', NULL, 1, 'Asignacion inicial desfibrilador UCI'),
(5, 5, 6, 3, '2025-01-01 15:00:00', NULL, 1, 'Asignacion inicial ECG UCI');


-- mantenimiento_programado
INSERT INTO mantenimiento_programado (id_programacion, id_equipo, id_tipo_mantenimiento, frecuencia_dias, fecha_ultimo_mantenimiento, fecha_proximo_mantenimiento, id_prioridad_mantenimiento, sla_horas, id_estado_cumplimiento, observacion_programacion) VALUES
(1, 1, 1, 90,  '2024-10-01 08:00:00', '2025-01-01 08:00:00', 1, 4, 1, 'Preventivo trimestral monitor'),
(2, 2, 1, 180, '2024-07-01 08:00:00', '2025-01-01 08:00:00', 1, 8, 1, 'Preventivo semestral ventilador'),
(3, 3, 3, 365, '2024-01-01 08:00:00', '2025-01-01 08:00:00', 2, 8, 1, 'Calibración anual bomba'),
(4, 4, 1, 90,  '2024-10-01 08:00:00', '2025-01-01 08:00:00', 1, 4, 3, 'Preventivo vencido desfibrilador'),
(5, 5, 4, 180, '2024-07-01 08:00:00', '2025-01-01 08:00:00', 2, 8, 1, 'Inspección semestral ECG');


-- mantenimiento (datos de prueba históricos para el desfibrilador EQ-004)
INSERT INTO mantenimiento (id_mantenimiento, id_equipo, id_biomedico, fecha_hora_mantenimiento, id_programacion, id_tipo_mantenimiento, descripcion_mantenimiento, id_resultado_mantenimiento, costo_mantenimiento, observacion_mantenimiento) VALUES
(1, 4, 1, '2024-04-01 09:00:00', NULL, 2, 'Falla en condensador de descarga',              2, 4500.00, 'Equipo enviado a revision externa'),
(2, 4, 1, '2024-06-15 10:00:00', NULL, 2, 'Reincidencia en condensador, reparacion parcial',3, 3200.00, 'Pendiente refaccion importada'),
(3, 4, 1, '2024-09-20 11:00:00', NULL, 2, 'Tercera falla, sistema de carga inestable',      4, 1500.00, 'Se recomienda evaluacion para baja del equipo');


-- uso_clinico_equipo (datos de prueba iniciales)
INSERT INTO uso_clinico_equipo (id_uso_clinico, id_equipo, id_persona_responsable_uso, fecha_hora_inicio, fecha_hora_fin, id_area, id_turno, id_tipo_procedimiento, motivo_uso) VALUES
(6,  1, 2, '2026-02-01 08:00:00', '2026-02-01 10:30:00', 1, 1, 1, 'Monitoreo paciente con trauma craneoencefalico'),
(7,  1, 2, '2026-02-15 09:00:00', '2026-02-15 11:00:00', 1, 1, 1, 'Monitoreo paciente con infarto agudo'),
(8,  1, 3, '2026-03-01 08:30:00', '2026-03-01 09:45:00', 1, 1, 5, 'Diagnostico paciente con arritmia'),
(9,  3, 2, '2026-02-05 10:00:00', '2026-02-05 14:00:00', 1, 1, 2, 'Infusion de medicamento vasopresor'),
(10, 3, 3, '2026-02-20 08:00:00', '2026-02-20 12:00:00', 1, 1, 2, 'Infusion de antibiotico endovenoso'),
(11, 5, 2, '2026-01-20 08:00:00', '2026-01-20 08:30:00', 2, 1, 5, 'Electrocardiograma de control postoperatorio'),
(12, 5, 7, '2026-02-10 15:00:00', '2026-02-10 15:30:00', 2, 2, 5, 'Electrocardiograma paciente con dolor toracico'),
(13, 7, 7, '2026-03-01 15:00:00', '2026-03-01 19:00:00', 2, 2, 2, 'Infusion de sedante para paciente critico'),
(14, 7, 6, '2026-03-10 15:00:00', '2026-03-10 23:00:00', 2, 2, 2, 'Infusion de nutricion parenteral'),
(15, 10, 2,'2026-03-25 09:00:00', '2026-03-25 09:15:00', 4, 1, 4, 'Reanimacion de emergencia paciente con fibrilacion');


-- evento_beacon (datos de prueba iniciales)
INSERT INTO evento_beacon (id_evento_beacon, id_beacon, id_equipo, fecha_hora_evento, id_tipo_evento_beacon) VALUES
(1, 2, 3, '2026-04-18 16:12:55', 1),
(2, 1, 1, '2026-02-01 08:00:00', 1),
(3, 1, 6, '2026-02-01 07:30:00', 1),
(4, 2, 2, '2026-01-15 15:00:00', 1),
(5, 2, 7, '2026-03-01 15:00:00', 1),
(6, 3, 9, '2026-02-15 08:00:00', 1),
(7, 1, 1, '2026-03-01 08:00:00', 3),
(8, 2, 5, '2026-02-10 15:00:00', 1);


-- evento_nfc (datos de prueba iniciales)
INSERT INTO evento_nfc (id_evento_nfc, id_nfc, fecha_hora_evento, id_tipo_evento_nfc) VALUES
(1, 1, '2026-02-01 08:05:00', 1),
(2, 1, '2026-02-15 09:05:00', 1),
(3, 2, '2026-01-15 08:10:00', 2),
(4, 3, '2026-02-05 10:05:00', 1),
(5, 5, '2026-01-20 08:05:00', 1),
(6, 6, '2026-02-01 07:35:00', 1),
(7, 7, '2026-03-01 15:05:00', 1);


-- evento_gps (datos de prueba iniciales)
INSERT INTO evento_gps (id_evento_gps, id_gps, fecha_hora_evento, latitud, longitud, precision) VALUES
(2, 1, '2026-02-15 10:00:00', 25.6714, -100.3090, 4.5),
(3, 1, '2026-02-15 10:30:00', 25.6720, -100.3085, 3.8),
(4, 1, '2026-03-01 14:00:00', 25.6710, -100.3095, 5.0),
(5, 2, '2026-03-10 09:00:00', 25.6718, -100.3088, 4.2),
(6, 2, '2026-03-10 09:30:00', 25.6722, -100.3082, 3.5);
