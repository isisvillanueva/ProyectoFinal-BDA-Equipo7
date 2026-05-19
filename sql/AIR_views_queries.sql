-- ============================================================
-- QUERIES DE LAS VISTAS
-- hospital_db
-- ============================================================


-- v_actividad_sistema_por_usuario
-- ─────────────────────────────────────────────────
SELECT u.username,
    ru.rol_usuario,
    COUNT(a.id_auditoria) AS total_operaciones,
    MAX(a.fecha_hora_auditoria) AS ultima_actividad,
    COUNT(DISTINCT a.tabla_afectada) AS tablas_distintas_afectadas
FROM auditoria a
JOIN usuario u ON u.id_usuario = a.id_usuario
JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
JOIN roles_usuario ru ON ru.id_rol_usuario = ur.id_rol_usuario
GROUP BY u.id_usuario, u.username, ru.rol_usuario
ORDER BY COUNT(a.id_auditoria) DESC;


-- v_admin_areas_sin_responsable
-- ─────────────────────────────────────────────────
SELECT id_area,
    nombre_area,
    'Area sin responsable activo - requiere asignacion' AS alerta,
    (SELECT MAX(ra2.fecha_fin_responsable_area)
     FROM responsable_area ra2
     WHERE ra2.id_area = ar.id_area) AS fecha_ultimo_cierre
FROM area_registro ar
WHERE NOT EXISTS (
    SELECT 1 FROM responsable_area ra
    WHERE ra.id_area = ar.id_area
      AND ra.fecha_fin_responsable_area IS NULL
)
ORDER BY nombre_area;


-- v_admin_auditoria_reciente
-- ─────────────────────────────────────────────────
SELECT a.id_auditoria,
    a.tabla_afectada,
    a.accion_auditoria,
    a.id_registro_afectado,
    u.username AS ejecutado_por,
    a.origen_cambio,
    a.fecha_hora_auditoria,
    CASE
        WHEN a.accion_auditoria = 'DESACTIVACION' THEN 'Requiere revision - usuario desactivado'
        WHEN a.accion_auditoria = 'DELETE_LOGICO' THEN 'Requiere revision - baja logica registrada'
        WHEN a.accion_auditoria = 'ACTIVACION'    THEN 'Usuario o equipo reactivado'
        ELSE 'Operacion normal'
    END AS nivel_atencion
FROM auditoria a
JOIN usuario u ON u.id_usuario = a.id_usuario
ORDER BY a.fecha_hora_auditoria DESC;


-- v_admin_estado_ambulancias
-- ─────────────────────────────────────────────────
SELECT a.codigo_ambulancia,
    a.placa,
    ea.estado_ambulancia,
    a.activo_ambulancia,
    dg.codigo_gps,
    dg.activo_gps,
    (SELECT COUNT(*) FROM traslado_externo_equipo te
     WHERE te.id_ambulancia = a.id_ambulancia) AS total_traslados
FROM ambulancia a
JOIN estado_ambulancias ea ON ea.id_estado_ambulancia = a.id_estado_ambulancia
LEFT JOIN dispositivo_gps dg ON dg.id_ambulancia = a.id_ambulancia
ORDER BY ea.estado_ambulancia, a.codigo_ambulancia;


-- v_admin_inventario_equipos
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    me.nombre_modelo,
    ma.nombre_marca,
    te.tipo_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    ue.nombre_ubicacion,
    ar.nombre_area,
    e.activo_equipo,
    dn.activo_nfc,
    dn.codigo_uid_nfc
FROM equipo e
JOIN modelo_equipo me      ON me.id_modelo          = e.id_modelo
JOIN marca_equipo ma       ON ma.id_marca            = me.id_marca
JOIN tipo_equipos te       ON te.id_tipo_equipo      = e.id_tipo_equipo
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo    = e.id_estado_equipo
JOIN ubicacion_especifica ue ON ue.id_ubicacion      = e.id_ubicacion_administrativa_actual
JOIN area_registro ar      ON ar.id_area             = ue.id_area
LEFT JOIN dispositivo_nfc dn ON dn.id_equipo         = e.id_equipo
ORDER BY ar.nombre_area, ee.estado_equipo, e.codigo_interno;


-- v_alertas_preventivas
-- ─────────────────────────────────────────────────
SELECT e.id_equipo,
    e.nombre_equipo,
    e.codigo_interno,
    ce.criticidad_equipo,
    MAX(m.fecha_hora_mantenimiento) AS ultimo_mant,
    MAX(m.fecha_hora_mantenimiento) + INTERVAL '180 days' AS prox_mant_sugerido,
    CASE
        WHEN MAX(m.fecha_hora_mantenimiento) IS NULL THEN 'SIN REGISTRO'
        WHEN MAX(m.fecha_hora_mantenimiento) + INTERVAL '180 days' < NOW() THEN 'VENCIDO'
        ELSE 'POR VENCER'
    END AS estado_alerta
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
LEFT JOIN mantenimiento m ON m.id_equipo = e.id_equipo
WHERE e.activo_equipo = TRUE
GROUP BY e.id_equipo, e.nombre_equipo, e.codigo_interno, ce.criticidad_equipo
HAVING MAX(m.fecha_hora_mantenimiento) IS NULL
    OR MAX(m.fecha_hora_mantenimiento) + INTERVAL '180 days' <= NOW() + INTERVAL '30 days';


-- v_ambulancias_gps
-- ─────────────────────────────────────────────────
SELECT a.id_ambulancia,
    a.codigo_ambulancia,
    a.placa,
    ea.estado_ambulancia,
    a.activo_ambulancia,
    dg.id_gps,
    dg.codigo_gps,
    dg.activo_gps,
    eg.latitud,
    eg.longitud,
    eg.precision AS precision_gps,
    eg.fecha_hora_evento AS ultimo_ping
FROM ambulancia a
JOIN estado_ambulancias ea ON ea.id_estado_ambulancia = a.id_estado_ambulancia
LEFT JOIN dispositivo_gps dg ON dg.id_ambulancia = a.id_ambulancia
LEFT JOIN LATERAL (
    SELECT latitud, longitud, precision, fecha_hora_evento
    FROM evento_gps
    WHERE id_gps = dg.id_gps
    ORDER BY fecha_hora_evento DESC
    LIMIT 1
) eg ON TRUE;


-- v_asignaciones_activas
-- ─────────────────────────────────────────────────
SELECT ae.id_asignacion,
    ae.id_persona_responsable,
    e.nombre_equipo,
    e.codigo_interno,
    ue.nombre_ubicacion,
    ae.fecha_inicio_asignacion,
    ae.observacion_asignacion
FROM asignacion_equipo ae
JOIN equipo e              ON e.id_equipo  = ae.id_equipo
JOIN ubicacion_especifica ue ON ue.id_ubicacion = ae.id_ubicacion
WHERE ae.fecha_fin_asignacion IS NULL;


-- v_biomedico_historial_mantenimientos
-- ─────────────────────────────────────────────────
SELECT m.id_biomedico,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS biomedico,
    e.codigo_interno,
    e.nombre_equipo,
    tm.tipo_mantenimiento,
    trm.resultado_mantenimiento,
    m.descripcion_mantenimiento,
    m.costo_mantenimiento,
    m.fecha_hora_mantenimiento,
    m.observacion_mantenimiento
FROM mantenimiento m
JOIN equipo e                         ON e.id_equipo               = m.id_equipo
JOIN tipo_mantenimientos tm           ON tm.id_tipo_mantenimiento   = m.id_tipo_mantenimiento
JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento
JOIN biomedico b                      ON b.id_biomedico             = m.id_biomedico
JOIN persona p                        ON p.id_persona               = b.id_persona
ORDER BY m.fecha_hora_mantenimiento DESC;


-- v_carga_biomedico
-- ─────────────────────────────────────────────────
WITH mpb AS (
    SELECT b.id_biomedico,
        p.nombre_persona,
        p.apellido_persona,
        COUNT(m.id_mantenimiento) AS total_mantenimientos,
        COALESCE(SUM(m.costo_mantenimiento), 0) AS costo_total
    FROM biomedico b
    JOIN persona p ON p.id_persona = b.id_persona
    LEFT JOIN mantenimiento m ON m.id_biomedico = b.id_biomedico
    GROUP BY b.id_biomedico, p.nombre_persona, p.apellido_persona
),
prom AS (
    SELECT AVG(mpb.total_mantenimientos) AS promedio FROM mpb
)
SELECT CONCAT(mpb.nombre_persona, ' ', mpb.apellido_persona) AS biomedico,
    mpb.total_mantenimientos,
    mpb.costo_total,
    ROUND(prom.promedio, 2) AS promedio_general,
    CASE
        WHEN mpb.total_mantenimientos > prom.promedio THEN 'Carga superior al promedio'
        ELSE 'Carga normal'
    END AS estado_carga
FROM mpb CROSS JOIN prom
ORDER BY mpb.total_mantenimientos DESC;


-- v_discrepancia_ubicacion_iot
-- ─────────────────────────────────────────────────
WITH ultima_beacon AS (
    SELECT eb.id_equipo,
        eb.id_beacon,
        eb.fecha_hora_evento,
        teb.tipo_evento_beacon,
        zb.nombre_zona_beacon,
        ue.id_ubicacion,
        ue.nombre_ubicacion,
        ar.nombre_area,
        ROW_NUMBER() OVER (PARTITION BY eb.id_equipo ORDER BY eb.fecha_hora_evento DESC) AS rn
    FROM evento_beacon eb
    JOIN tipo_eventos_beacon teb ON teb.id_tipo_evento_beacon = eb.id_tipo_evento_beacon
    JOIN dispositivo_beacon db   ON db.id_beacon              = eb.id_beacon
    JOIN zona_beacon zb          ON zb.id_zona_beacon         = db.id_zona_beacon
    JOIN ubicacion_especifica ue ON ue.id_ubicacion           = zb.id_ubicacion
    JOIN area_registro ar        ON ar.id_area                = ue.id_area
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    uadm.nombre_ubicacion AS ubicacion_administrativa,
    aadm.nombre_area AS area_administrativa,
    uba.nombre_ubicacion AS ubicacion_evidencia_beacon,
    uba.nombre_area AS area_evidencia_beacon,
    uba.fecha_hora_evento AS fecha_ultima_evidencia_beacon,
    CASE
        WHEN e.id_ubicacion_administrativa_actual <> uba.id_ubicacion THEN 'Alerta: discrepancia detectada'
        ELSE 'Ok: ubicaciones coherentes'
    END AS resultado
FROM equipo e
JOIN ultima_beacon uba        ON uba.id_equipo = e.id_equipo AND uba.rn = 1
JOIN ubicacion_especifica uadm ON uadm.id_ubicacion = e.id_ubicacion_administrativa_actual
JOIN area_registro aadm        ON aadm.id_area = uadm.id_area
WHERE e.activo_equipo = TRUE;


-- v_disponibilidad_equipos_por_area
-- ─────────────────────────────────────────────────
SELECT ar.nombre_area,
    COALESCE(CONCAT(p_enf.nombre_persona, ' ', p_enf.apellido_persona), 'Sin responsable') AS responsable_activo,
    COUNT(e.id_equipo) AS total_equipos,
    SUM(CASE WHEN ee.estado_equipo = 'Disponible' THEN 1 ELSE 0 END) AS equipos_disponibles,
    SUM(CASE WHEN ee.estado_equipo <> 'Disponible' THEN 1 ELSE 0 END) AS equipos_no_disponibles,
    ROUND(
        100.0 * SUM(CASE WHEN ee.estado_equipo = 'Disponible' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(e.id_equipo), 0),
    2) AS porcentaje_disponibilidad
FROM area_registro ar
LEFT JOIN responsable_area ra     ON ra.id_area = ar.id_area AND ra.fecha_fin_responsable_area IS NULL
LEFT JOIN enfermero enf           ON enf.id_enfermero = ra.id_enfermero
LEFT JOIN persona p_enf           ON p_enf.id_persona = enf.id_persona
LEFT JOIN ubicacion_especifica ue ON ue.id_area = ar.id_area
LEFT JOIN equipo e                ON e.id_ubicacion_administrativa_actual = ue.id_ubicacion AND e.activo_equipo = TRUE
LEFT JOIN estado_equipos ee       ON ee.id_estado_equipo = e.id_estado_equipo
GROUP BY ar.id_area, ar.nombre_area, p_enf.nombre_persona, p_enf.apellido_persona
ORDER BY porcentaje_disponibilidad;


-- v_disponibilidad_por_tipo_equipo
-- ─────────────────────────────────────────────────
SELECT te.tipo_equipo,
    COUNT(*) AS total,
    COUNT(CASE WHEN ee.estado_equipo = 'Disponible' THEN 1 END) AS disponibles
FROM equipo e
JOIN tipo_equipos te   ON te.id_tipo_equipo   = e.id_tipo_equipo
JOIN estado_equipos ee ON ee.id_estado_equipo = e.id_estado_equipo
WHERE e.activo_equipo = TRUE
GROUP BY te.tipo_equipo;


-- v_equipos_activos
-- ─────────────────────────────────────────────────
SELECT id_equipo,
    codigo_interno,
    nombre_equipo
FROM equipo
WHERE activo_equipo = TRUE;


-- v_equipos_alta_demanda
-- ─────────────────────────────────────────────────
WITH uso AS (
    SELECT id_equipo, COUNT(*) AS total_usos
    FROM uso_clinico_equipo
    GROUP BY id_equipo
),
mant AS (
    SELECT id_equipo, COUNT(*) AS total_mant
    FROM mantenimiento
    GROUP BY id_equipo
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    COALESCE(u.total_usos, 0) AS total_usos_clinicos,
    COALESCE(m.total_mant, 0) AS total_mantenimientos
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
LEFT JOIN uso u  ON u.id_equipo = e.id_equipo
LEFT JOIN mant m ON m.id_equipo = e.id_equipo
WHERE COALESCE(u.total_usos, 0) >= 2
  AND COALESCE(m.total_mant, 0) >= 1
ORDER BY COALESCE(u.total_usos, 0) DESC;


-- v_equipos_candidatos_reemplazo
-- ─────────────────────────────────────────────────
WITH resumen AS (
    SELECT m.id_equipo,
        COUNT(*) AS total_mantenimientos,
        SUM(CASE WHEN m.id_resultado_mantenimiento IN (2,3,4) THEN 1 ELSE 0 END) AS desfavorables,
        SUM(m.costo_mantenimiento) AS costo_acumulado,
        MAX(m.fecha_hora_mantenimiento) AS fecha_ultimo
    FROM mantenimiento m
    GROUP BY m.id_equipo
),
uso_activo AS (
    SELECT id_equipo, COUNT(*) AS total_usos_activos
    FROM uso_clinico_equipo
    WHERE fecha_hora_fin IS NULL
    GROUP BY id_equipo
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    r.total_mantenimientos,
    r.desfavorables AS mantenimientos_desfavorables,
    r.costo_acumulado,
    r.fecha_ultimo AS fecha_ultimo_mantenimiento,
    COALESCE(ua.total_usos_activos, 0) AS usos_clinicos_activos,
    CASE
        WHEN r.desfavorables >= 2 AND r.costo_acumulado > 5000 THEN 'Candidato a evaluacion de baja'
        ELSE 'Sin alerta'
    END AS alerta_reemplazo
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN resumen r             ON r.id_equipo             = e.id_equipo
LEFT JOIN uso_activo ua    ON ua.id_equipo            = e.id_equipo
WHERE r.desfavorables >= 2;


-- v_equipos_criticos_no_disponibles
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    te.tipo_equipo,
    ee.estado_equipo,
    ue.nombre_ubicacion,
    ar.nombre_area
FROM equipo e
JOIN criticidad_equipos ce   ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN tipo_equipos te          ON te.id_tipo_equipo       = e.id_tipo_equipo
JOIN estado_equipos ee        ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN ubicacion_especifica ue  ON ue.id_ubicacion         = e.id_ubicacion_administrativa_actual
JOIN area_registro ar         ON ar.id_area              = ue.id_area
WHERE ce.criticidad_equipo = 'Alta'
  AND ee.estado_equipo IN ('En mantenimiento', 'Fuera de servicio', 'Retirado', 'En préstamo')
  AND e.activo_equipo = TRUE
ORDER BY ar.nombre_area;


-- v_equipos_disponibles_uso_clinico
-- ─────────────────────────────────────────────────
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ma.nombre_marca AS marca,
    te.tipo_equipo,
    ce.criticidad_equipo,
    ue.nombre_ubicacion,
    ar.nombre_area
FROM equipo e
JOIN tipo_equipos te          ON te.id_tipo_equipo       = e.id_tipo_equipo
JOIN criticidad_equipos ce    ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee        ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN ubicacion_especifica ue  ON ue.id_ubicacion         = e.id_ubicacion_administrativa_actual
JOIN area_registro ar         ON ar.id_area              = ue.id_area
JOIN modelo_equipo me         ON me.id_modelo            = e.id_modelo
JOIN marca_equipo ma          ON ma.id_marca             = me.id_marca
WHERE ee.estado_equipo = 'Disponible'
  AND e.activo_equipo = TRUE
ORDER BY ce.criticidad_equipo, ar.nombre_area, e.nombre_equipo;


-- v_equipos_por_area
-- ─────────────────────────────────────────────────
SELECT ue.id_area,
    ar.nombre_area,
    e.codigo_interno,
    e.nombre_equipo,
    te.tipo_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    ue.nombre_ubicacion,
    CASE
        WHEN ae.id_asignacion IS NOT NULL THEN CONCAT(p.nombre_persona, ' ', p.apellido_persona)
        ELSE 'Sin asignacion activa'
    END AS persona_asignada
FROM equipo e
JOIN tipo_equipos te         ON te.id_tipo_equipo       = e.id_tipo_equipo
JOIN criticidad_equipos ce   ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee       ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN ubicacion_especifica ue ON ue.id_ubicacion         = e.id_ubicacion_administrativa_actual
JOIN area_registro ar        ON ar.id_area              = ue.id_area
LEFT JOIN asignacion_equipo ae ON ae.id_equipo = e.id_equipo AND ae.fecha_fin_asignacion IS NULL
LEFT JOIN persona p            ON p.id_persona = ae.id_persona_responsable
WHERE e.activo_equipo = TRUE
ORDER BY ar.nombre_area, ee.estado_equipo, e.nombre_equipo;


-- v_equipos_sin_evidencia_iot
-- ─────────────────────────────────────────────────
WITH ultimo_nfc AS (
    SELECT dn.id_equipo, MAX(en.fecha_hora_evento) AS ultima_nfc
    FROM dispositivo_nfc dn
    LEFT JOIN evento_nfc en ON en.id_nfc = dn.id_nfc
    GROUP BY dn.id_equipo
),
ultimo_beacon AS (
    SELECT id_equipo, MAX(fecha_hora_evento) AS ultima_beacon
    FROM evento_beacon
    GROUP BY id_equipo
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    COALESCE(un.ultima_nfc,    '1900-01-01') AS ultima_evidencia_nfc,
    COALESCE(ub.ultima_beacon, '1900-01-01') AS ultima_evidencia_beacon,
    GREATEST(
        COALESCE(un.ultima_nfc,    '1900-01-01'),
        COALESCE(ub.ultima_beacon, '1900-01-01')
    ) AS ultima_evidencia_iot
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
LEFT JOIN ultimo_nfc un    ON un.id_equipo = e.id_equipo
LEFT JOIN ultimo_beacon ub ON ub.id_equipo = e.id_equipo
WHERE e.activo_equipo = TRUE
  AND GREATEST(
        COALESCE(un.ultima_nfc,    '1900-01-01'),
        COALESCE(ub.ultima_beacon, '1900-01-01')
      ) < NOW() - INTERVAL '12 hours'
ORDER BY ultima_evidencia_iot;


-- v_historial_responsable_area
-- ─────────────────────────────────────────────────
SELECT ra.id_responsable_area,
    ar.nombre_area,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS enfermero_responsable,
    ee.especialidad_enfermero,
    t.nombre_turno,
    ra.fecha_inicio_responsable_area,
    ra.fecha_fin_responsable_area,
    CASE
        WHEN ra.fecha_fin_responsable_area IS NULL THEN 'Activo'
        ELSE 'Cerrado'
    END AS estado_responsabilidad,
    SUM(CASE WHEN ra.fecha_fin_responsable_area IS NULL THEN 1 ELSE 0 END)
        OVER (PARTITION BY ra.id_area) AS responsables_activos_en_area
FROM responsable_area ra
JOIN area_registro ar            ON ar.id_area                  = ra.id_area
JOIN enfermero enf               ON enf.id_enfermero            = ra.id_enfermero
JOIN persona p                   ON p.id_persona                = enf.id_persona
JOIN especialidades_enfermero ee ON ee.id_especialidad_enfermero = enf.id_especialidad_enfermero
JOIN turnos t                    ON t.id_turno                  = enf.id_turno
ORDER BY ra.id_area, ra.fecha_inicio_responsable_area;


-- v_historial_tecnico_equipos
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    COUNT(m.id_mantenimiento) AS total_mantenimientos,
    SUM(m.costo_mantenimiento) AS costo_acumulado,
    SUM(CASE WHEN m.id_resultado_mantenimiento = 1 THEN 1 ELSE 0 END) AS exitosos,
    SUM(CASE WHEN m.id_resultado_mantenimiento IN (2,3,4) THEN 1 ELSE 0 END) AS desfavorables,
    ROUND(
        100.0 * SUM(CASE WHEN m.id_resultado_mantenimiento IN (2,3,4) THEN 1 ELSE 0 END)
        / NULLIF(COUNT(m.id_mantenimiento), 0),
    2) AS porcentaje_desfavorable
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN mantenimiento m       ON m.id_equipo             = e.id_equipo
GROUP BY e.id_equipo, e.codigo_interno, e.nombre_equipo, ce.criticidad_equipo, ee.estado_equipo
ORDER BY desfavorables DESC, costo_acumulado DESC;


-- v_historial_traslados_externos
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    a.codigo_ambulancia,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS conductor,
    te.fecha_salida,
    te.fecha_llegada,
    tt.tipo_traslado,
    te.motivo_traslado,
    te.observacion_traslado
FROM traslado_externo_equipo te
JOIN equipo e               ON e.id_equipo    = te.id_equipo
JOIN ambulancia a           ON a.id_ambulancia = te.id_ambulancia
JOIN persona p              ON p.id_persona    = te.id_persona_conductor
JOIN tipo_traslado_externo tt ON tt.id_tipo_traslado = te.id_tipo_traslado
ORDER BY te.fecha_salida DESC;


-- v_historial_uso_clinico_por_persona
-- ─────────────────────────────────────────────────
SELECT uce.id_uso_clinico,
    uce.id_persona_responsable_uso,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
    e.codigo_interno,
    e.nombre_equipo,
    tp.tipo_procedimiento,
    ar.nombre_area,
    t.nombre_turno,
    uce.fecha_hora_inicio,
    uce.fecha_hora_fin,
    CASE
        WHEN uce.fecha_hora_fin IS NOT NULL
        THEN ROUND(EXTRACT(EPOCH FROM (uce.fecha_hora_fin - uce.fecha_hora_inicio)) / 3600, 2)
        ELSE NULL
    END AS duracion_horas,
    uce.motivo_uso
FROM uso_clinico_equipo uce
JOIN equipo e            ON e.id_equipo             = uce.id_equipo
JOIN tipo_procedimiento tp ON tp.id_tipo_procedimiento = uce.id_tipo_procedimiento
JOIN area_registro ar    ON ar.id_area              = uce.id_area
JOIN turnos t            ON t.id_turno              = uce.id_turno
JOIN persona p           ON p.id_persona            = uce.id_persona_responsable_uso
ORDER BY uce.fecha_hora_inicio DESC;


-- v_mantenimiento_correctivo_estado_equipo
-- ─────────────────────────────────────────────────
WITH ultimo_correctivo AS (
    SELECT m.id_equipo,
        m.id_mantenimiento,
        m.id_biomedico,
        m.fecha_hora_mantenimiento,
        m.descripcion_mantenimiento,
        m.id_resultado_mantenimiento,
        m.costo_mantenimiento,
        ROW_NUMBER() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_mantenimiento DESC) AS rn
    FROM mantenimiento m
    JOIN tipo_mantenimientos tm ON tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento
    WHERE tm.tipo_mantenimiento = 'Correctivo'
),
uso_activo AS (
    SELECT id_equipo, COUNT(*) AS total_usos_activos
    FROM uso_clinico_equipo
    WHERE fecha_hora_fin IS NULL
    GROUP BY id_equipo
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ee.estado_equipo,
    uc.fecha_hora_mantenimiento,
    trm.resultado_mantenimiento,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS biomedico_responsable,
    uc.descripcion_mantenimiento,
    uc.costo_mantenimiento,
    COALESCE(ua.total_usos_activos, 0) AS usos_clinicos_activos,
    CASE
        WHEN COALESCE(ua.total_usos_activos, 0) = 0
         AND ee.estado_equipo IN ('En mantenimiento','Fuera de servicio','Retirado','En préstamo')
        THEN 'Si'
        ELSE 'No'
    END AS uso_clinico_bloqueado
FROM ultimo_correctivo uc
JOIN equipo e                         ON e.id_equipo = uc.id_equipo AND uc.rn = 1
JOIN estado_equipos ee                ON ee.id_estado_equipo = e.id_estado_equipo
JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = uc.id_resultado_mantenimiento
JOIN biomedico b                      ON b.id_biomedico = uc.id_biomedico
JOIN persona p                        ON p.id_persona   = b.id_persona
LEFT JOIN uso_activo ua               ON ua.id_equipo   = e.id_equipo;


-- v_mantenimientos_programados_pendientes
-- ─────────────────────────────────────────────────
SELECT mp.id_programacion,
    e.id_equipo,
    e.nombre_equipo,
    e.codigo_interno,
    tm.tipo_mantenimiento,
    pm.prioridad_mantenimiento,
    ec.estado_cumplimiento,
    mp.fecha_proximo_mantenimiento,
    mp.fecha_ultimo_mantenimiento,
    mp.frecuencia_dias,
    mp.sla_horas,
    mp.observacion_programacion,
    CASE
        WHEN mp.fecha_proximo_mantenimiento < NOW()                          THEN 'vencido'
        WHEN mp.fecha_proximo_mantenimiento <= NOW() + INTERVAL '7 days'    THEN 'urgente'
        WHEN mp.fecha_proximo_mantenimiento <= NOW() + INTERVAL '30 days'   THEN 'proximo'
        ELSE 'al_dia'
    END AS alerta
FROM mantenimiento_programado mp
JOIN equipo e                                ON e.id_equipo               = mp.id_equipo
JOIN tipo_mantenimientos tm                  ON tm.id_tipo_mantenimiento  = mp.id_tipo_mantenimiento
JOIN prioridad_mantenimientos pm             ON pm.id_prioridad_mantenimiento = mp.id_prioridad_mantenimiento
JOIN estado_cumplimiento_mantenimientos ec   ON ec.id_estado_cumplimiento = mp.id_estado_cumplimiento
WHERE mp.id_estado_cumplimiento IN (1, 3)
  AND e.activo_equipo = TRUE;


-- v_mantenimientos_proximos_a_vencer
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    tm.tipo_mantenimiento,
    pm.fecha_proximo_mantenimiento,
    pm.sla_horas,
    ec.estado_cumplimiento,
    pm.fecha_proximo_mantenimiento::TIMESTAMPTZ - NOW() AS tiempo_restante,
    pm.observacion_programacion
FROM mantenimiento_programado pm
JOIN equipo e                              ON e.id_equipo               = pm.id_equipo
JOIN criticidad_equipos ce                 ON ce.id_criticidad_equipo   = e.id_criticidad_equipo
JOIN tipo_mantenimientos tm                ON tm.id_tipo_mantenimiento  = pm.id_tipo_mantenimiento
JOIN estado_cumplimiento_mantenimientos ec ON ec.id_estado_cumplimiento = pm.id_estado_cumplimiento
WHERE pm.id_estado_cumplimiento IN (1, 3)
  AND pm.fecha_proximo_mantenimiento <= NOW() + INTERVAL '30 days'
ORDER BY pm.fecha_proximo_mantenimiento;


-- v_mantenimientos_proximos_por_area
-- ─────────────────────────────────────────────────
SELECT epa.id_area,
    epa.nombre_area,
    vmp.codigo_interno,
    vmp.nombre_equipo,
    vmp.criticidad_equipo,
    vmp.tipo_mantenimiento,
    vmp.fecha_proximo_mantenimiento,
    vmp.sla_horas,
    vmp.estado_cumplimiento,
    vmp.tiempo_restante,
    vmp.observacion_programacion
FROM v_mantenimientos_proximos_a_vencer vmp
JOIN v_equipos_por_area epa ON epa.codigo_interno = vmp.codigo_interno;


-- v_mantenimientos_vencidos
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    tm.tipo_mantenimiento,
    pm.fecha_proximo_mantenimiento,
    pm.sla_horas,
    NOW() - pm.fecha_proximo_mantenimiento::TIMESTAMPTZ AS tiempo_vencido,
    pm.observacion_programacion
FROM mantenimiento_programado pm
JOIN equipo e               ON e.id_equipo              = pm.id_equipo
JOIN criticidad_equipos ce  ON ce.id_criticidad_equipo  = e.id_criticidad_equipo
JOIN tipo_mantenimientos tm ON tm.id_tipo_mantenimiento = pm.id_tipo_mantenimiento
WHERE pm.id_estado_cumplimiento = 1
  AND pm.fecha_proximo_mantenimiento < NOW()
ORDER BY pm.fecha_proximo_mantenimiento;


-- v_mis_usos_clinicos
-- ─────────────────────────────────────────────────
SELECT u.id_uso_clinico,
    u.id_persona_responsable_uso,
    e.nombre_equipo,
    e.codigo_interno,
    ee.estado_equipo,
    u.fecha_hora_inicio,
    u.fecha_hora_fin,
    ar.nombre_area
FROM uso_clinico_equipo u
JOIN equipo e              ON e.id_equipo         = u.id_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo = e.id_estado_equipo
JOIN ubicacion_especifica ue ON ue.id_ubicacion   = e.id_ubicacion_administrativa_actual
JOIN area_registro ar      ON ar.id_area          = ue.id_area;


-- v_movimientos_recientes_por_area
-- ─────────────────────────────────────────────────
SELECT ao.id_area AS id_area_origen,
    ad.id_area AS id_area_destino,
    e.codigo_interno,
    e.nombre_equipo,
    tm.tipo_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
    m.fecha_hora_movimiento,
    m.motivo_movimiento
FROM movimiento m
JOIN equipo e              ON e.id_equipo          = m.id_equipo
JOIN tipo_movimientos tm   ON tm.id_tipo_movimiento = m.id_tipo_movimiento
JOIN ubicacion_especifica uo ON uo.id_ubicacion    = m.id_ubicacion_origen
JOIN area_registro ao      ON ao.id_area           = uo.id_area
JOIN ubicacion_especifica ud ON ud.id_ubicacion    = m.id_ubicacion_destino
JOIN area_registro ad      ON ad.id_area           = ud.id_area
JOIN persona p             ON p.id_persona         = m.id_persona_responsable_movimiento
ORDER BY m.fecha_hora_movimiento DESC;


-- v_responsables_activos_por_area
-- ─────────────────────────────────────────────────
SELECT ar.nombre_area,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS enfermero_responsable,
    ee.especialidad_enfermero,
    t.nombre_turno,
    t.hora_inicio,
    t.hora_fin,
    ra.fecha_inicio_responsable_area
FROM responsable_area ra
JOIN area_registro ar            ON ar.id_area                  = ra.id_area
JOIN enfermero enf               ON enf.id_enfermero            = ra.id_enfermero
JOIN persona p                   ON p.id_persona                = enf.id_persona
JOIN especialidades_enfermero ee ON ee.id_especialidad_enfermero = enf.id_especialidad_enfermero
JOIN turnos t                    ON t.id_turno                  = enf.id_turno
WHERE ra.fecha_fin_responsable_area IS NULL
ORDER BY ar.nombre_area;


-- v_resumen_actividad_equipos
-- ─────────────────────────────────────────────────
SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    e.activo_equipo,
    (SELECT COUNT(*) FROM movimiento m        WHERE m.id_equipo = e.id_equipo)  AS total_movimientos,
    (SELECT COUNT(*) FROM mantenimiento mt    WHERE mt.id_equipo = e.id_equipo) AS total_mantenimientos,
    (SELECT COUNT(*) FROM uso_clinico_equipo uce WHERE uce.id_equipo = e.id_equipo) AS total_usos_clinicos,
    (SELECT COUNT(*) FROM evento_nfc en
     JOIN dispositivo_nfc dn ON dn.id_nfc = en.id_nfc
     WHERE dn.id_equipo = e.id_equipo) AS total_eventos_nfc,
    (SELECT COUNT(*) FROM evento_beacon eb WHERE eb.id_equipo = e.id_equipo) AS total_eventos_beacon
FROM equipo e
JOIN criticidad_equipos ce ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo     = e.id_estado_equipo
ORDER BY total_movimientos DESC, total_mantenimientos DESC;


-- v_traslados_activos
-- ─────────────────────────────────────────────────
SELECT te.id_traslado_externo,
    te.fecha_salida,
    e.nombre_equipo,
    e.codigo_interno,
    a.codigo_ambulancia,
    a.placa,
    p.nombre_persona || ' ' || p.apellido_persona AS conductor,
    tt.tipo_traslado,
    te.motivo_traslado,
    te.observacion_traslado
FROM traslado_externo_equipo te
JOIN equipo e               ON e.id_equipo     = te.id_equipo
JOIN ambulancia a           ON a.id_ambulancia = te.id_ambulancia
JOIN persona p              ON p.id_persona    = te.id_persona_conductor
JOIN tipo_traslado_externo tt ON tt.id_tipo_traslado = te.id_tipo_traslado
WHERE te.fecha_llegada IS NULL
ORDER BY te.fecha_salida DESC;


-- v_ultimo_movimiento_equipos_criticos
-- ─────────────────────────────────────────────────
WITH ultimo_movimiento AS (
    SELECT m.id_equipo,
        m.id_movimiento,
        m.fecha_hora_movimiento,
        m.id_persona_responsable_movimiento,
        m.id_tipo_movimiento,
        m.id_ubicacion_origen,
        m.id_ubicacion_destino,
        m.motivo_movimiento,
        ROW_NUMBER() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_movimiento DESC, m.id_movimiento DESC) AS rn
    FROM movimiento m
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    um.fecha_hora_movimiento,
    tm.tipo_movimiento,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    uea.nombre_ubicacion AS ubicacion_administrativa_actual,
    ara.nombre_area AS area_administrativa_actual,
    um.motivo_movimiento,
    CASE
        WHEN e.id_ubicacion_administrativa_actual = um.id_ubicacion_destino THEN 'Si'
        ELSE 'No'
    END AS equipo_quedo_en_area_correcta
FROM ultimo_movimiento um
JOIN equipo e                ON e.id_equipo = um.id_equipo AND um.rn = 1
JOIN criticidad_equipos ce   ON ce.id_criticidad_equipo = e.id_criticidad_equipo
JOIN estado_equipos ee       ON ee.id_estado_equipo     = e.id_estado_equipo
JOIN persona p               ON p.id_persona            = um.id_persona_responsable_movimiento
JOIN tipo_movimientos tm     ON tm.id_tipo_movimiento   = um.id_tipo_movimiento
JOIN ubicacion_especifica uo ON uo.id_ubicacion         = um.id_ubicacion_origen
JOIN area_registro ao        ON ao.id_area              = uo.id_area
JOIN ubicacion_especifica ud ON ud.id_ubicacion         = um.id_ubicacion_destino
JOIN area_registro ad        ON ad.id_area              = ud.id_area
JOIN ubicacion_especifica uea ON uea.id_ubicacion       = e.id_ubicacion_administrativa_actual
JOIN area_registro ara        ON ara.id_area            = uea.id_area
WHERE ce.criticidad_equipo = 'Alta';


-- v_ultimo_movimiento_por_equipo
-- ─────────────────────────────────────────────────
WITH um AS (
    SELECT m.id_equipo,
        m.id_movimiento,
        m.fecha_hora_movimiento,
        m.id_persona_responsable_movimiento,
        m.id_tipo_movimiento,
        m.id_ubicacion_origen,
        m.id_ubicacion_destino,
        m.motivo_movimiento,
        ROW_NUMBER() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_movimiento DESC) AS rn
    FROM movimiento m
)
SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ee.estado_equipo,
    um.fecha_hora_movimiento,
    CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable_movimiento,
    tm.tipo_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    um.motivo_movimiento
FROM um
JOIN equipo e              ON e.id_equipo         = um.id_equipo AND um.rn = 1
JOIN estado_equipos ee     ON ee.id_estado_equipo = e.id_estado_equipo
JOIN persona p             ON p.id_persona        = um.id_persona_responsable_movimiento
JOIN tipo_movimientos tm   ON tm.id_tipo_movimiento = um.id_tipo_movimiento
JOIN ubicacion_especifica uo ON uo.id_ubicacion   = um.id_ubicacion_origen
JOIN area_registro ao      ON ao.id_area          = uo.id_area
JOIN ubicacion_especifica ud ON ud.id_ubicacion   = um.id_ubicacion_destino
JOIN area_registro ad      ON ad.id_area          = ud.id_area;


-- v_usos_clinicos_area
-- ─────────────────────────────────────────────────
SELECT u.id_uso_clinico,
    p.nombre_persona || ' ' || p.apellido_persona AS persona,
    e.nombre_equipo,
    e.codigo_interno,
    ee.estado_equipo,
    u.fecha_hora_inicio,
    u.fecha_hora_fin,
    ar.id_area,
    ar.nombre_area
FROM uso_clinico_equipo u
JOIN equipo e              ON e.id_equipo         = u.id_equipo
JOIN estado_equipos ee     ON ee.id_estado_equipo = e.id_estado_equipo
JOIN ubicacion_especifica ue ON ue.id_ubicacion   = e.id_ubicacion_administrativa_actual
JOIN area_registro ar      ON ar.id_area          = ue.id_area
JOIN persona p             ON p.id_persona        = u.id_persona_responsable_uso;
