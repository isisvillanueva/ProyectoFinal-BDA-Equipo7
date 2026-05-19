-- =====================================================================
-- VIEWS - hospital_db
-- Extraídas de: hospital_db__3_.sql
-- Total: 37 vistas
-- =====================================================================

--
-- Name: v_actividad_sistema_por_usuario; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_actividad_sistema_por_usuario AS
 SELECT u.username,
    ru.rol_usuario,
    count(a.id_auditoria) AS total_operaciones,
    max(a.fecha_hora_auditoria) AS ultima_actividad,
    count(DISTINCT a.tabla_afectada) AS tablas_distintas_afectadas
   FROM (((public.auditoria a
     JOIN public.usuario u ON ((u.id_usuario = a.id_usuario)))
     JOIN public.usuario_rol ur ON ((ur.id_usuario = u.id_usuario)))
     JOIN public.roles_usuario ru ON ((ru.id_rol_usuario = ur.id_rol_usuario)))
  GROUP BY u.id_usuario, u.username, ru.rol_usuario
  ORDER BY (count(a.id_auditoria)) DESC;


ALTER VIEW public.v_actividad_sistema_por_usuario OWNER TO postgres;


--
-- Name: v_admin_areas_sin_responsable; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_admin_areas_sin_responsable AS
 SELECT id_area,
    nombre_area,
    'Area sin responsable activo - requiere asignacion'::text AS alerta,
    ( SELECT max(ra2.fecha_fin_responsable_area) AS max
           FROM public.responsable_area ra2
          WHERE (ra2.id_area = ar.id_area)) AS fecha_ultimo_cierre
   FROM public.area_registro ar
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.responsable_area ra
          WHERE ((ra.id_area = ar.id_area) AND (ra.fecha_fin_responsable_area IS NULL)))))
  ORDER BY nombre_area;


ALTER VIEW public.v_admin_areas_sin_responsable OWNER TO postgres;


--
-- Name: v_admin_auditoria_reciente; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_admin_auditoria_reciente AS
 SELECT a.id_auditoria,
    a.tabla_afectada,
    a.accion_auditoria,
    a.id_registro_afectado,
    u.username AS ejecutado_por,
    a.origen_cambio,
    a.fecha_hora_auditoria,
        CASE
            WHEN ((a.accion_auditoria)::text = 'DESACTIVACION'::text) THEN 'Requiere revision - usuario desactivado'::text
            WHEN ((a.accion_auditoria)::text = 'DELETE_LOGICO'::text) THEN 'Requiere revision - baja logica registrada'::text
            WHEN ((a.accion_auditoria)::text = 'ACTIVACION'::text) THEN 'Usuario o equipo reactivado'::text
            ELSE 'Operacion normal'::text
        END AS nivel_atencion
   FROM (public.auditoria a
     JOIN public.usuario u ON ((u.id_usuario = a.id_usuario)))
  ORDER BY a.fecha_hora_auditoria DESC;


ALTER VIEW public.v_admin_auditoria_reciente OWNER TO postgres;


--
-- Name: v_admin_estado_ambulancias; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_admin_estado_ambulancias AS
 SELECT a.codigo_ambulancia,
    a.placa,
    ea.estado_ambulancia,
    a.activo_ambulancia,
    dg.codigo_gps,
    dg.activo_gps,
    ( SELECT count(*) AS count
           FROM public.traslado_externo_equipo te
          WHERE (te.id_ambulancia = a.id_ambulancia)) AS total_traslados
   FROM ((public.ambulancia a
     JOIN public.estado_ambulancias ea ON ((ea.id_estado_ambulancia = a.id_estado_ambulancia)))
     LEFT JOIN public.dispositivo_gps dg ON ((dg.id_ambulancia = a.id_ambulancia)))
  ORDER BY ea.estado_ambulancia, a.codigo_ambulancia;


ALTER VIEW public.v_admin_estado_ambulancias OWNER TO postgres;


--
-- Name: v_admin_inventario_equipos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_admin_inventario_equipos AS
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
   FROM ((((((((public.equipo e
     JOIN public.modelo_equipo me ON ((me.id_modelo = e.id_modelo)))
     JOIN public.marca_equipo ma ON ((ma.id_marca = me.id_marca)))
     JOIN public.tipo_equipos te ON ((te.id_tipo_equipo = e.id_tipo_equipo)))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
     LEFT JOIN public.dispositivo_nfc dn ON ((dn.id_equipo = e.id_equipo)))
  ORDER BY ar.nombre_area, ee.estado_equipo, e.codigo_interno;


ALTER VIEW public.v_admin_inventario_equipos OWNER TO postgres;


--
-- Name: v_alertas_preventivas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_alertas_preventivas AS
 SELECT e.id_equipo,
    e.nombre_equipo,
    e.codigo_interno,
    ce.criticidad_equipo,
    max(m.fecha_hora_mantenimiento) AS ultimo_mant,
    (max(m.fecha_hora_mantenimiento) + '180 days'::interval) AS prox_mant_sugerido,
        CASE
            WHEN (max(m.fecha_hora_mantenimiento) IS NULL) THEN 'SIN REGISTRO'::text
            WHEN ((max(m.fecha_hora_mantenimiento) + '180 days'::interval) < now()) THEN 'VENCIDO'::text
            ELSE 'POR VENCER'::text
        END AS estado_alerta
   FROM ((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     LEFT JOIN public.mantenimiento m ON ((m.id_equipo = e.id_equipo)))
  WHERE (e.activo_equipo = true)
  GROUP BY e.id_equipo, e.nombre_equipo, e.codigo_interno, ce.criticidad_equipo
 HAVING ((max(m.fecha_hora_mantenimiento) IS NULL) OR ((max(m.fecha_hora_mantenimiento) + '180 days'::interval) <= (now() + '30 days'::interval)));


ALTER VIEW public.v_alertas_preventivas OWNER TO postgres;


--
-- Name: v_ambulancias_gps; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ambulancias_gps AS
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
    eg."precision" AS precision_gps,
    eg.fecha_hora_evento AS ultimo_ping
   FROM (((public.ambulancia a
     JOIN public.estado_ambulancias ea ON ((ea.id_estado_ambulancia = a.id_estado_ambulancia)))
     LEFT JOIN public.dispositivo_gps dg ON ((dg.id_ambulancia = a.id_ambulancia)))
     LEFT JOIN LATERAL ( SELECT evento_gps.latitud,
            evento_gps.longitud,
            evento_gps."precision",
            evento_gps.fecha_hora_evento
           FROM public.evento_gps
          WHERE (evento_gps.id_gps = dg.id_gps)
          ORDER BY evento_gps.fecha_hora_evento DESC
         LIMIT 1) eg ON (true));


ALTER VIEW public.v_ambulancias_gps OWNER TO postgres;


--
-- Name: v_asignaciones_activas; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_asignaciones_activas AS
 SELECT ae.id_asignacion,
    ae.id_persona_responsable,
    e.nombre_equipo,
    e.codigo_interno,
    ue.nombre_ubicacion,
    ae.fecha_inicio_asignacion,
    ae.observacion_asignacion
   FROM ((public.asignacion_equipo ae
     JOIN public.equipo e ON ((e.id_equipo = ae.id_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = ae.id_ubicacion)))
  WHERE (ae.fecha_fin_asignacion IS NULL);


ALTER VIEW public.v_asignaciones_activas OWNER TO postgres;


--
-- Name: v_biomedico_historial_mantenimientos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_biomedico_historial_mantenimientos AS
 SELECT m.id_biomedico,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS biomedico,
    e.codigo_interno,
    e.nombre_equipo,
    tm.tipo_mantenimiento,
    trm.resultado_mantenimiento,
    m.descripcion_mantenimiento,
    m.costo_mantenimiento,
    m.fecha_hora_mantenimiento,
    m.observacion_mantenimiento
   FROM (((((public.mantenimiento m
     JOIN public.equipo e ON ((e.id_equipo = m.id_equipo)))
     JOIN public.tipo_mantenimientos tm ON ((tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento)))
     JOIN public.tipo_resultado_mantenimientos trm ON ((trm.id_resultado_mantenimiento = m.id_resultado_mantenimiento)))
     JOIN public.biomedico b ON ((b.id_biomedico = m.id_biomedico)))
     JOIN public.persona p ON ((p.id_persona = b.id_persona)))
  ORDER BY m.fecha_hora_mantenimiento DESC;


ALTER VIEW public.v_biomedico_historial_mantenimientos OWNER TO postgres;


--
-- Name: v_carga_biomedico; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_carga_biomedico AS
 WITH mpb AS (
         SELECT b.id_biomedico,
            p.nombre_persona,
            p.apellido_persona,
            count(m.id_mantenimiento) AS total_mantenimientos,
            COALESCE(sum(m.costo_mantenimiento), (0)::numeric) AS costo_total
           FROM ((public.biomedico b
             JOIN public.persona p ON ((p.id_persona = b.id_persona)))
             LEFT JOIN public.mantenimiento m ON ((m.id_biomedico = b.id_biomedico)))
          GROUP BY b.id_biomedico, p.nombre_persona, p.apellido_persona
        ), prom AS (
         SELECT avg((mpb_1.total_mantenimientos)::numeric) AS promedio
           FROM mpb mpb_1
        )
 SELECT concat(mpb.nombre_persona, ' ', mpb.apellido_persona) AS biomedico,
    mpb.total_mantenimientos,
    mpb.costo_total,
    round(prom.promedio, 2) AS promedio_general,
        CASE
            WHEN ((mpb.total_mantenimientos)::numeric > prom.promedio) THEN 'Carga superior al promedio'::text
            ELSE 'Carga normal'::text
        END AS estado_carga
   FROM (mpb
     CROSS JOIN prom)
  ORDER BY mpb.total_mantenimientos DESC;


ALTER VIEW public.v_carga_biomedico OWNER TO postgres;


--
-- Name: v_discrepancia_ubicacion_iot; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_discrepancia_ubicacion_iot AS
 WITH ultima_beacon AS (
         SELECT eb.id_equipo,
            eb.id_beacon,
            eb.fecha_hora_evento,
            teb.tipo_evento_beacon,
            zb.nombre_zona_beacon,
            ue.id_ubicacion,
            ue.nombre_ubicacion,
            ar.nombre_area,
            row_number() OVER (PARTITION BY eb.id_equipo ORDER BY eb.fecha_hora_evento DESC) AS rn
           FROM (((((public.evento_beacon eb
             JOIN public.tipo_eventos_beacon teb ON ((teb.id_tipo_evento_beacon = eb.id_tipo_evento_beacon)))
             JOIN public.dispositivo_beacon db ON ((db.id_beacon = eb.id_beacon)))
             JOIN public.zona_beacon zb ON ((zb.id_zona_beacon = db.id_zona_beacon)))
             JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = zb.id_ubicacion)))
             JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
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
            WHEN (e.id_ubicacion_administrativa_actual <> uba.id_ubicacion) THEN 'Alerta: discrepancia detectada'::text
            ELSE 'Ok: ubicaciones coherentes'::text
        END AS resultado
   FROM (((public.equipo e
     JOIN ultima_beacon uba ON (((uba.id_equipo = e.id_equipo) AND (uba.rn = 1))))
     JOIN public.ubicacion_especifica uadm ON ((uadm.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro aadm ON ((aadm.id_area = uadm.id_area)))
  WHERE (e.activo_equipo = true);


ALTER VIEW public.v_discrepancia_ubicacion_iot OWNER TO postgres;


--
-- Name: v_disponibilidad_equipos_por_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_disponibilidad_equipos_por_area AS
 SELECT ar.nombre_area,
    COALESCE(concat(p_enf.nombre_persona, ' ', p_enf.apellido_persona), 'Sin responsable'::text) AS responsable_activo,
    count(e.id_equipo) AS total_equipos,
    sum(
        CASE
            WHEN ((ee.estado_equipo)::text = 'Disponible'::text) THEN 1
            ELSE 0
        END) AS equipos_disponibles,
    sum(
        CASE
            WHEN ((ee.estado_equipo)::text <> 'Disponible'::text) THEN 1
            ELSE 0
        END) AS equipos_no_disponibles,
    round(((100.0 * (sum(
        CASE
            WHEN ((ee.estado_equipo)::text = 'Disponible'::text) THEN 1
            ELSE 0
        END))::numeric) / (NULLIF(count(e.id_equipo), 0))::numeric), 2) AS porcentaje_disponibilidad
   FROM ((((((public.area_registro ar
     LEFT JOIN public.responsable_area ra ON (((ra.id_area = ar.id_area) AND (ra.fecha_fin_responsable_area IS NULL))))
     LEFT JOIN public.enfermero enf ON ((enf.id_enfermero = ra.id_enfermero)))
     LEFT JOIN public.persona p_enf ON ((p_enf.id_persona = enf.id_persona)))
     LEFT JOIN public.ubicacion_especifica ue ON ((ue.id_area = ar.id_area)))
     LEFT JOIN public.equipo e ON (((e.id_ubicacion_administrativa_actual = ue.id_ubicacion) AND (e.activo_equipo = true))))
     LEFT JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
  GROUP BY ar.id_area, ar.nombre_area, p_enf.nombre_persona, p_enf.apellido_persona
  ORDER BY (round(((100.0 * (sum(
        CASE
            WHEN ((ee.estado_equipo)::text = 'Disponible'::text) THEN 1
            ELSE 0
        END))::numeric) / (NULLIF(count(e.id_equipo), 0))::numeric), 2));


ALTER VIEW public.v_disponibilidad_equipos_por_area OWNER TO postgres;


--
-- Name: v_disponibilidad_por_tipo_equipo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_disponibilidad_por_tipo_equipo AS
 SELECT te.tipo_equipo,
    count(*) AS total,
    count(
        CASE
            WHEN ((ee.estado_equipo)::text = 'Disponible'::text) THEN 1
            ELSE NULL::integer
        END) AS disponibles
   FROM ((public.equipo e
     JOIN public.tipo_equipos te ON ((te.id_tipo_equipo = e.id_tipo_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
  WHERE (e.activo_equipo = true)
  GROUP BY te.tipo_equipo;


ALTER VIEW public.v_disponibilidad_por_tipo_equipo OWNER TO postgres;


--
-- Name: v_equipos_activos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_activos AS
 SELECT id_equipo,
    codigo_interno,
    nombre_equipo
   FROM public.equipo
  WHERE (activo_equipo = true);


ALTER VIEW public.v_equipos_activos OWNER TO postgres;


--
-- Name: v_equipos_alta_demanda; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_alta_demanda AS
 WITH uso AS (
         SELECT uso_clinico_equipo.id_equipo,
            count(*) AS total_usos
           FROM public.uso_clinico_equipo
          GROUP BY uso_clinico_equipo.id_equipo
        ), mant AS (
         SELECT mantenimiento.id_equipo,
            count(*) AS total_mant
           FROM public.mantenimiento
          GROUP BY mantenimiento.id_equipo
        )
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    COALESCE(u.total_usos, (0)::bigint) AS total_usos_clinicos,
    COALESCE(m.total_mant, (0)::bigint) AS total_mantenimientos
   FROM (((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     LEFT JOIN uso u ON ((u.id_equipo = e.id_equipo)))
     LEFT JOIN mant m ON ((m.id_equipo = e.id_equipo)))
  WHERE ((COALESCE(u.total_usos, (0)::bigint) >= 2) AND (COALESCE(m.total_mant, (0)::bigint) >= 1))
  ORDER BY COALESCE(u.total_usos, (0)::bigint) DESC;


ALTER VIEW public.v_equipos_alta_demanda OWNER TO postgres;


--
-- Name: v_equipos_candidatos_reemplazo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_candidatos_reemplazo AS
 WITH resumen AS (
         SELECT m.id_equipo,
            count(*) AS total_mantenimientos,
            sum(
                CASE
                    WHEN (m.id_resultado_mantenimiento = ANY (ARRAY[2, 3, 4])) THEN 1
                    ELSE 0
                END) AS desfavorables,
            sum(m.costo_mantenimiento) AS costo_acumulado,
            max(m.fecha_hora_mantenimiento) AS fecha_ultimo
           FROM public.mantenimiento m
          GROUP BY m.id_equipo
        ), uso_activo AS (
         SELECT uso_clinico_equipo.id_equipo,
            count(*) AS total_usos_activos
           FROM public.uso_clinico_equipo
          WHERE (uso_clinico_equipo.fecha_hora_fin IS NULL)
          GROUP BY uso_clinico_equipo.id_equipo
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
    COALESCE(ua.total_usos_activos, (0)::bigint) AS usos_clinicos_activos,
        CASE
            WHEN ((r.desfavorables >= 2) AND (r.costo_acumulado > (5000)::numeric)) THEN 'Candidato a evaluacion de baja'::text
            ELSE 'Sin alerta'::text
        END AS alerta_reemplazo
   FROM ((((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN resumen r ON ((r.id_equipo = e.id_equipo)))
     LEFT JOIN uso_activo ua ON ((ua.id_equipo = e.id_equipo)))
  WHERE (r.desfavorables >= 2);


ALTER VIEW public.v_equipos_candidatos_reemplazo OWNER TO postgres;


--
-- Name: v_equipos_criticos_no_disponibles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_criticos_no_disponibles AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    te.tipo_equipo,
    ee.estado_equipo,
    ue.nombre_ubicacion,
    ar.nombre_area
   FROM (((((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.tipo_equipos te ON ((te.id_tipo_equipo = e.id_tipo_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
  WHERE (((ce.criticidad_equipo)::text = 'Alta'::text) AND ((ee.estado_equipo)::text = ANY (ARRAY['En mantenimiento'::text, 'Fuera de servicio'::text, 'Retirado'::text, 'En préstamo'::text])) AND (e.activo_equipo = true))
  ORDER BY ar.nombre_area;


ALTER VIEW public.v_equipos_criticos_no_disponibles OWNER TO postgres;


--
-- Name: v_equipos_disponibles_uso_clinico; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_disponibles_uso_clinico AS
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ma.nombre_marca AS marca,
    te.tipo_equipo,
    ce.criticidad_equipo,
    ue.nombre_ubicacion,
    ar.nombre_area
   FROM (((((((public.equipo e
     JOIN public.tipo_equipos te ON ((te.id_tipo_equipo = e.id_tipo_equipo)))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
     JOIN public.modelo_equipo me ON ((me.id_modelo = e.id_modelo)))
     JOIN public.marca_equipo ma ON ((ma.id_marca = me.id_marca)))
  WHERE (((ee.estado_equipo)::text = 'Disponible'::text) AND (e.activo_equipo = true))
  ORDER BY ce.criticidad_equipo, ar.nombre_area, e.nombre_equipo;


ALTER VIEW public.v_equipos_disponibles_uso_clinico OWNER TO postgres;


--
-- Name: v_equipos_por_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_por_area AS
 SELECT ue.id_area,
    ar.nombre_area,
    e.codigo_interno,
    e.nombre_equipo,
    te.tipo_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    ue.nombre_ubicacion,
        CASE
            WHEN (ae.id_asignacion IS NOT NULL) THEN concat(p.nombre_persona, ' ', p.apellido_persona)
            ELSE 'Sin asignacion activa'::text
        END AS persona_asignada
   FROM (((((((public.equipo e
     JOIN public.tipo_equipos te ON ((te.id_tipo_equipo = e.id_tipo_equipo)))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
     LEFT JOIN public.asignacion_equipo ae ON (((ae.id_equipo = e.id_equipo) AND (ae.fecha_fin_asignacion IS NULL))))
     LEFT JOIN public.persona p ON ((p.id_persona = ae.id_persona_responsable)))
  WHERE (e.activo_equipo = true)
  ORDER BY ar.nombre_area, ee.estado_equipo, e.nombre_equipo;


ALTER VIEW public.v_equipos_por_area OWNER TO postgres;


--
-- Name: v_equipos_sin_evidencia_iot; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_equipos_sin_evidencia_iot AS
 WITH ultimo_nfc AS (
         SELECT dn.id_equipo,
            max(en.fecha_hora_evento) AS ultima_nfc
           FROM (public.dispositivo_nfc dn
             LEFT JOIN public.evento_nfc en ON ((en.id_nfc = dn.id_nfc)))
          GROUP BY dn.id_equipo
        ), ultimo_beacon AS (
         SELECT evento_beacon.id_equipo,
            max(evento_beacon.fecha_hora_evento) AS ultima_beacon
           FROM public.evento_beacon
          GROUP BY evento_beacon.id_equipo
        )
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    COALESCE(un.ultima_nfc, '1900-01-01 00:00:00'::timestamp without time zone) AS ultima_evidencia_nfc,
    COALESCE(ub.ultima_beacon, '1900-01-01 00:00:00'::timestamp without time zone) AS ultima_evidencia_beacon,
    GREATEST(COALESCE(un.ultima_nfc, '1900-01-01 00:00:00'::timestamp without time zone), COALESCE(ub.ultima_beacon, '1900-01-01 00:00:00'::timestamp without time zone)) AS ultima_evidencia_iot
   FROM (((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     LEFT JOIN ultimo_nfc un ON ((un.id_equipo = e.id_equipo)))
     LEFT JOIN ultimo_beacon ub ON ((ub.id_equipo = e.id_equipo)))
  WHERE ((e.activo_equipo = true) AND (GREATEST(COALESCE(un.ultima_nfc, '1900-01-01 00:00:00'::timestamp without time zone), COALESCE(ub.ultima_beacon, '1900-01-01 00:00:00'::timestamp without time zone)) < (now() - '12:00:00'::interval)))
  ORDER BY GREATEST(COALESCE(un.ultima_nfc, '1900-01-01 00:00:00'::timestamp without time zone), COALESCE(ub.ultima_beacon, '1900-01-01 00:00:00'::timestamp without time zone));


ALTER VIEW public.v_equipos_sin_evidencia_iot OWNER TO postgres;


--
-- Name: v_historial_responsable_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_historial_responsable_area AS
 SELECT ra.id_responsable_area,
    ar.nombre_area,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS enfermero_responsable,
    ee.especialidad_enfermero,
    t.nombre_turno,
    ra.fecha_inicio_responsable_area,
    ra.fecha_fin_responsable_area,
        CASE
            WHEN (ra.fecha_fin_responsable_area IS NULL) THEN 'Activo'::text
            ELSE 'Cerrado'::text
        END AS estado_responsabilidad,
    sum(
        CASE
            WHEN (ra.fecha_fin_responsable_area IS NULL) THEN 1
            ELSE 0
        END) OVER (PARTITION BY ra.id_area) AS responsables_activos_en_area
   FROM (((((public.responsable_area ra
     JOIN public.area_registro ar ON ((ar.id_area = ra.id_area)))
     JOIN public.enfermero enf ON ((enf.id_enfermero = ra.id_enfermero)))
     JOIN public.persona p ON ((p.id_persona = enf.id_persona)))
     JOIN public.especialidades_enfermero ee ON ((ee.id_especialidad_enfermero = enf.id_especialidad_enfermero)))
     JOIN public.turnos t ON ((t.id_turno = enf.id_turno)))
  ORDER BY ra.id_area, ra.fecha_inicio_responsable_area;


ALTER VIEW public.v_historial_responsable_area OWNER TO postgres;


--
-- Name: v_historial_tecnico_equipos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_historial_tecnico_equipos AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    count(m.id_mantenimiento) AS total_mantenimientos,
    sum(m.costo_mantenimiento) AS costo_acumulado,
    sum(
        CASE
            WHEN (m.id_resultado_mantenimiento = 1) THEN 1
            ELSE 0
        END) AS exitosos,
    sum(
        CASE
            WHEN (m.id_resultado_mantenimiento = ANY (ARRAY[2, 3, 4])) THEN 1
            ELSE 0
        END) AS desfavorables,
    round(((100.0 * (sum(
        CASE
            WHEN (m.id_resultado_mantenimiento = ANY (ARRAY[2, 3, 4])) THEN 1
            ELSE 0
        END))::numeric) / (NULLIF(count(m.id_mantenimiento), 0))::numeric), 2) AS porcentaje_desfavorable
   FROM (((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.mantenimiento m ON ((m.id_equipo = e.id_equipo)))
  GROUP BY e.id_equipo, e.codigo_interno, e.nombre_equipo, ce.criticidad_equipo, ee.estado_equipo
  ORDER BY (sum(
        CASE
            WHEN (m.id_resultado_mantenimiento = ANY (ARRAY[2, 3, 4])) THEN 1
            ELSE 0
        END)) DESC, (sum(m.costo_mantenimiento)) DESC;


ALTER VIEW public.v_historial_tecnico_equipos OWNER TO postgres;


--
-- Name: v_historial_traslados_externos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_historial_traslados_externos AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    a.codigo_ambulancia,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS conductor,
    te.fecha_salida,
    te.fecha_llegada,
    tt.tipo_traslado,
    te.motivo_traslado,
    te.observacion_traslado
   FROM ((((public.traslado_externo_equipo te
     JOIN public.equipo e ON ((e.id_equipo = te.id_equipo)))
     JOIN public.ambulancia a ON ((a.id_ambulancia = te.id_ambulancia)))
     JOIN public.persona p ON ((p.id_persona = te.id_persona_conductor)))
     JOIN public.tipo_traslado_externo tt ON ((tt.id_tipo_traslado = te.id_tipo_traslado)))
  ORDER BY te.fecha_salida DESC;


ALTER VIEW public.v_historial_traslados_externos OWNER TO postgres;


--
-- Name: v_historial_uso_clinico_por_persona; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_historial_uso_clinico_por_persona AS
 SELECT uce.id_uso_clinico,
    uce.id_persona_responsable_uso,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
    e.codigo_interno,
    e.nombre_equipo,
    tp.tipo_procedimiento,
    ar.nombre_area,
    t.nombre_turno,
    uce.fecha_hora_inicio,
    uce.fecha_hora_fin,
        CASE
            WHEN (uce.fecha_hora_fin IS NOT NULL) THEN round((EXTRACT(epoch FROM (uce.fecha_hora_fin - uce.fecha_hora_inicio)) / (3600)::numeric), 2)
            ELSE NULL::numeric
        END AS duracion_horas,
    uce.motivo_uso
   FROM (((((public.uso_clinico_equipo uce
     JOIN public.equipo e ON ((e.id_equipo = uce.id_equipo)))
     JOIN public.tipo_procedimiento tp ON ((tp.id_tipo_procedimiento = uce.id_tipo_procedimiento)))
     JOIN public.area_registro ar ON ((ar.id_area = uce.id_area)))
     JOIN public.turnos t ON ((t.id_turno = uce.id_turno)))
     JOIN public.persona p ON ((p.id_persona = uce.id_persona_responsable_uso)))
  ORDER BY uce.fecha_hora_inicio DESC;


ALTER VIEW public.v_historial_uso_clinico_por_persona OWNER TO postgres;


--
-- Name: v_mantenimiento_correctivo_estado_equipo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_mantenimiento_correctivo_estado_equipo AS
 WITH ultimo_correctivo AS (
         SELECT m.id_equipo,
            m.id_mantenimiento,
            m.id_biomedico,
            m.fecha_hora_mantenimiento,
            m.descripcion_mantenimiento,
            m.id_resultado_mantenimiento,
            m.costo_mantenimiento,
            row_number() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_mantenimiento DESC) AS rn
           FROM (public.mantenimiento m
             JOIN public.tipo_mantenimientos tm ON ((tm.id_tipo_mantenimiento = m.id_tipo_mantenimiento)))
          WHERE ((tm.tipo_mantenimiento)::text = 'Correctivo'::text)
        ), uso_activo AS (
         SELECT uso_clinico_equipo.id_equipo,
            count(*) AS total_usos_activos
           FROM public.uso_clinico_equipo
          WHERE (uso_clinico_equipo.fecha_hora_fin IS NULL)
          GROUP BY uso_clinico_equipo.id_equipo
        )
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ee.estado_equipo,
    uc.fecha_hora_mantenimiento,
    trm.resultado_mantenimiento,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS biomedico_responsable,
    uc.descripcion_mantenimiento,
    uc.costo_mantenimiento,
    COALESCE(ua.total_usos_activos, (0)::bigint) AS usos_clinicos_activos,
        CASE
            WHEN ((COALESCE(ua.total_usos_activos, (0)::bigint) = 0) AND ((ee.estado_equipo)::text = ANY (ARRAY['En mantenimiento'::text, 'Fuera de servicio'::text, 'Retirado'::text, 'En préstamo'::text]))) THEN 'Si'::text
            ELSE 'No'::text
        END AS uso_clinico_bloqueado
   FROM ((((((ultimo_correctivo uc
     JOIN public.equipo e ON (((e.id_equipo = uc.id_equipo) AND (uc.rn = 1))))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.tipo_resultado_mantenimientos trm ON ((trm.id_resultado_mantenimiento = uc.id_resultado_mantenimiento)))
     JOIN public.biomedico b ON ((b.id_biomedico = uc.id_biomedico)))
     JOIN public.persona p ON ((p.id_persona = b.id_persona)))
     LEFT JOIN uso_activo ua ON ((ua.id_equipo = e.id_equipo)));


ALTER VIEW public.v_mantenimiento_correctivo_estado_equipo OWNER TO postgres;


--
-- Name: v_mantenimientos_programados_pendientes; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_mantenimientos_programados_pendientes AS
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
            WHEN (mp.fecha_proximo_mantenimiento < now()) THEN 'vencido'::text
            WHEN (mp.fecha_proximo_mantenimiento <= (now() + '7 days'::interval)) THEN 'urgente'::text
            WHEN (mp.fecha_proximo_mantenimiento <= (now() + '30 days'::interval)) THEN 'proximo'::text
            ELSE 'al_dia'::text
        END AS alerta
   FROM ((((public.mantenimiento_programado mp
     JOIN public.equipo e ON ((e.id_equipo = mp.id_equipo)))
     JOIN public.tipo_mantenimientos tm ON ((tm.id_tipo_mantenimiento = mp.id_tipo_mantenimiento)))
     JOIN public.prioridad_mantenimientos pm ON ((pm.id_prioridad_mantenimiento = mp.id_prioridad_mantenimiento)))
     JOIN public.estado_cumplimiento_mantenimientos ec ON ((ec.id_estado_cumplimiento = mp.id_estado_cumplimiento)))
  WHERE ((mp.id_estado_cumplimiento = ANY (ARRAY[1, 3])) AND (e.activo_equipo = true));


ALTER VIEW public.v_mantenimientos_programados_pendientes OWNER TO postgres;


--
-- Name: v_mantenimientos_proximos_a_vencer; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_mantenimientos_proximos_a_vencer AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    tm.tipo_mantenimiento,
    pm.fecha_proximo_mantenimiento,
    pm.sla_horas,
    ec.estado_cumplimiento,
    ((pm.fecha_proximo_mantenimiento)::timestamp with time zone - now()) AS tiempo_restante,
    pm.observacion_programacion
   FROM ((((public.mantenimiento_programado pm
     JOIN public.equipo e ON ((e.id_equipo = pm.id_equipo)))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.tipo_mantenimientos tm ON ((tm.id_tipo_mantenimiento = pm.id_tipo_mantenimiento)))
     JOIN public.estado_cumplimiento_mantenimientos ec ON ((ec.id_estado_cumplimiento = pm.id_estado_cumplimiento)))
  WHERE ((pm.id_estado_cumplimiento = ANY (ARRAY[1, 3])) AND (pm.fecha_proximo_mantenimiento <= (now() + '30 days'::interval)))
  ORDER BY pm.fecha_proximo_mantenimiento;


ALTER VIEW public.v_mantenimientos_proximos_a_vencer OWNER TO postgres;


--
-- Name: v_mantenimientos_proximos_por_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_mantenimientos_proximos_por_area AS
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
   FROM (public.v_mantenimientos_proximos_a_vencer vmp
     JOIN public.v_equipos_por_area epa ON (((epa.codigo_interno)::text = (vmp.codigo_interno)::text)));


ALTER VIEW public.v_mantenimientos_proximos_por_area OWNER TO postgres;


--
-- Name: v_mantenimientos_vencidos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_mantenimientos_vencidos AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    tm.tipo_mantenimiento,
    pm.fecha_proximo_mantenimiento,
    pm.sla_horas,
    (now() - (pm.fecha_proximo_mantenimiento)::timestamp with time zone) AS tiempo_vencido,
    pm.observacion_programacion
   FROM (((public.mantenimiento_programado pm
     JOIN public.equipo e ON ((e.id_equipo = pm.id_equipo)))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.tipo_mantenimientos tm ON ((tm.id_tipo_mantenimiento = pm.id_tipo_mantenimiento)))
  WHERE ((pm.id_estado_cumplimiento = 1) AND (pm.fecha_proximo_mantenimiento < now()))
  ORDER BY pm.fecha_proximo_mantenimiento;


ALTER VIEW public.v_mantenimientos_vencidos OWNER TO postgres;


--
-- Name: v_mis_usos_clinicos; Type: VIEW; Schema: public; Owner: hospital_user
--

CREATE VIEW public.v_mis_usos_clinicos AS
 SELECT u.id_uso_clinico,
    u.id_persona_responsable_uso,
    e.nombre_equipo,
    e.codigo_interno,
    ee.estado_equipo,
    u.fecha_hora_inicio,
    u.fecha_hora_fin,
    ar.nombre_area
   FROM ((((public.uso_clinico_equipo u
     JOIN public.equipo e ON ((e.id_equipo = u.id_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)));


ALTER VIEW public.v_mis_usos_clinicos OWNER TO hospital_user;


--
-- Name: v_movimientos_recientes_por_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_movimientos_recientes_por_area AS
 SELECT ao.id_area AS id_area_origen,
    ad.id_area AS id_area_destino,
    e.codigo_interno,
    e.nombre_equipo,
    tm.tipo_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
    m.fecha_hora_movimiento,
    m.motivo_movimiento
   FROM (((((((public.movimiento m
     JOIN public.equipo e ON ((e.id_equipo = m.id_equipo)))
     JOIN public.tipo_movimientos tm ON ((tm.id_tipo_movimiento = m.id_tipo_movimiento)))
     JOIN public.ubicacion_especifica uo ON ((uo.id_ubicacion = m.id_ubicacion_origen)))
     JOIN public.area_registro ao ON ((ao.id_area = uo.id_area)))
     JOIN public.ubicacion_especifica ud ON ((ud.id_ubicacion = m.id_ubicacion_destino)))
     JOIN public.area_registro ad ON ((ad.id_area = ud.id_area)))
     JOIN public.persona p ON ((p.id_persona = m.id_persona_responsable_movimiento)))
  ORDER BY m.fecha_hora_movimiento DESC;


ALTER VIEW public.v_movimientos_recientes_por_area OWNER TO postgres;


--
-- Name: v_responsables_activos_por_area; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_responsables_activos_por_area AS
 SELECT ar.nombre_area,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS enfermero_responsable,
    ee.especialidad_enfermero,
    t.nombre_turno,
    t.hora_inicio,
    t.hora_fin,
    ra.fecha_inicio_responsable_area
   FROM (((((public.responsable_area ra
     JOIN public.area_registro ar ON ((ar.id_area = ra.id_area)))
     JOIN public.enfermero enf ON ((enf.id_enfermero = ra.id_enfermero)))
     JOIN public.persona p ON ((p.id_persona = enf.id_persona)))
     JOIN public.especialidades_enfermero ee ON ((ee.id_especialidad_enfermero = enf.id_especialidad_enfermero)))
     JOIN public.turnos t ON ((t.id_turno = enf.id_turno)))
  WHERE (ra.fecha_fin_responsable_area IS NULL)
  ORDER BY ar.nombre_area;


ALTER VIEW public.v_responsables_activos_por_area OWNER TO postgres;


--
-- Name: v_resumen_actividad_equipos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_resumen_actividad_equipos AS
 SELECT e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    e.activo_equipo,
    ( SELECT count(*) AS count
           FROM public.movimiento m
          WHERE (m.id_equipo = e.id_equipo)) AS total_movimientos,
    ( SELECT count(*) AS count
           FROM public.mantenimiento mt
          WHERE (mt.id_equipo = e.id_equipo)) AS total_mantenimientos,
    ( SELECT count(*) AS count
           FROM public.uso_clinico_equipo uce
          WHERE (uce.id_equipo = e.id_equipo)) AS total_usos_clinicos,
    ( SELECT count(*) AS count
           FROM (public.evento_nfc en
             JOIN public.dispositivo_nfc dn ON ((dn.id_nfc = en.id_nfc)))
          WHERE (dn.id_equipo = e.id_equipo)) AS total_eventos_nfc,
    ( SELECT count(*) AS count
           FROM public.evento_beacon eb
          WHERE (eb.id_equipo = e.id_equipo)) AS total_eventos_beacon
   FROM ((public.equipo e
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
  ORDER BY ( SELECT count(*) AS count
           FROM public.movimiento m
          WHERE (m.id_equipo = e.id_equipo)) DESC, ( SELECT count(*) AS count
           FROM public.mantenimiento mt
          WHERE (mt.id_equipo = e.id_equipo)) DESC;


ALTER VIEW public.v_resumen_actividad_equipos OWNER TO postgres;


--
-- Name: v_traslados_activos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_traslados_activos AS
 SELECT te.id_traslado_externo,
    te.fecha_salida,
    e.nombre_equipo,
    e.codigo_interno,
    a.codigo_ambulancia,
    a.placa,
    (((p.nombre_persona)::text || ' '::text) || (p.apellido_persona)::text) AS conductor,
    tt.tipo_traslado,
    te.motivo_traslado,
    te.observacion_traslado
   FROM ((((public.traslado_externo_equipo te
     JOIN public.equipo e ON ((e.id_equipo = te.id_equipo)))
     JOIN public.ambulancia a ON ((a.id_ambulancia = te.id_ambulancia)))
     JOIN public.persona p ON ((p.id_persona = te.id_persona_conductor)))
     JOIN public.tipo_traslado_externo tt ON ((tt.id_tipo_traslado = te.id_tipo_traslado)))
  WHERE (te.fecha_llegada IS NULL)
  ORDER BY te.fecha_salida DESC;


ALTER VIEW public.v_traslados_activos OWNER TO postgres;


--
-- Name: v_ultimo_movimiento_equipos_criticos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ultimo_movimiento_equipos_criticos AS
 WITH ultimo_movimiento AS (
         SELECT m.id_equipo,
            m.id_movimiento,
            m.fecha_hora_movimiento,
            m.id_persona_responsable_movimiento,
            m.id_tipo_movimiento,
            m.id_ubicacion_origen,
            m.id_ubicacion_destino,
            m.motivo_movimiento,
            row_number() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_movimiento DESC, m.id_movimiento DESC) AS rn
           FROM public.movimiento m
        )
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ce.criticidad_equipo,
    ee.estado_equipo,
    um.fecha_hora_movimiento,
    tm.tipo_movimiento,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS responsable_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    uea.nombre_ubicacion AS ubicacion_administrativa_actual,
    ara.nombre_area AS area_administrativa_actual,
    um.motivo_movimiento,
        CASE
            WHEN (e.id_ubicacion_administrativa_actual = um.id_ubicacion_destino) THEN 'Si'::text
            ELSE 'No'::text
        END AS equipo_quedo_en_area_correcta
   FROM (((((((((((ultimo_movimiento um
     JOIN public.equipo e ON (((e.id_equipo = um.id_equipo) AND (um.rn = 1))))
     JOIN public.criticidad_equipos ce ON ((ce.id_criticidad_equipo = e.id_criticidad_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.persona p ON ((p.id_persona = um.id_persona_responsable_movimiento)))
     JOIN public.tipo_movimientos tm ON ((tm.id_tipo_movimiento = um.id_tipo_movimiento)))
     JOIN public.ubicacion_especifica uo ON ((uo.id_ubicacion = um.id_ubicacion_origen)))
     JOIN public.area_registro ao ON ((ao.id_area = uo.id_area)))
     JOIN public.ubicacion_especifica ud ON ((ud.id_ubicacion = um.id_ubicacion_destino)))
     JOIN public.area_registro ad ON ((ad.id_area = ud.id_area)))
     JOIN public.ubicacion_especifica uea ON ((uea.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ara ON ((ara.id_area = uea.id_area)))
  WHERE ((ce.criticidad_equipo)::text = 'Alta'::text);


ALTER VIEW public.v_ultimo_movimiento_equipos_criticos OWNER TO postgres;


--
-- Name: v_ultimo_movimiento_por_equipo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ultimo_movimiento_por_equipo AS
 WITH um AS (
         SELECT m.id_equipo,
            m.id_movimiento,
            m.fecha_hora_movimiento,
            m.id_persona_responsable_movimiento,
            m.id_tipo_movimiento,
            m.id_ubicacion_origen,
            m.id_ubicacion_destino,
            m.motivo_movimiento,
            row_number() OVER (PARTITION BY m.id_equipo ORDER BY m.fecha_hora_movimiento DESC) AS rn
           FROM public.movimiento m
        )
 SELECT e.id_equipo,
    e.codigo_interno,
    e.nombre_equipo,
    ee.estado_equipo,
    um.fecha_hora_movimiento,
    concat(p.nombre_persona, ' ', p.apellido_persona) AS responsable_movimiento,
    tm.tipo_movimiento,
    uo.nombre_ubicacion AS ubicacion_origen,
    ao.nombre_area AS area_origen,
    ud.nombre_ubicacion AS ubicacion_destino,
    ad.nombre_area AS area_destino,
    um.motivo_movimiento
   FROM ((((((((um
     JOIN public.equipo e ON (((e.id_equipo = um.id_equipo) AND (um.rn = 1))))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.persona p ON ((p.id_persona = um.id_persona_responsable_movimiento)))
     JOIN public.tipo_movimientos tm ON ((tm.id_tipo_movimiento = um.id_tipo_movimiento)))
     JOIN public.ubicacion_especifica uo ON ((uo.id_ubicacion = um.id_ubicacion_origen)))
     JOIN public.area_registro ao ON ((ao.id_area = uo.id_area)))
     JOIN public.ubicacion_especifica ud ON ((ud.id_ubicacion = um.id_ubicacion_destino)))
     JOIN public.area_registro ad ON ((ad.id_area = ud.id_area)));


ALTER VIEW public.v_ultimo_movimiento_por_equipo OWNER TO postgres;


--
-- Name: v_usos_clinicos_area; Type: VIEW; Schema: public; Owner: hospital_user
--

CREATE VIEW public.v_usos_clinicos_area AS
 SELECT u.id_uso_clinico,
    (((p.nombre_persona)::text || ' '::text) || (p.apellido_persona)::text) AS persona,
    e.nombre_equipo,
    e.codigo_interno,
    ee.estado_equipo,
    u.fecha_hora_inicio,
    u.fecha_hora_fin,
    ar.id_area,
    ar.nombre_area
   FROM (((((public.uso_clinico_equipo u
     JOIN public.equipo e ON ((e.id_equipo = u.id_equipo)))
     JOIN public.estado_equipos ee ON ((ee.id_estado_equipo = e.id_estado_equipo)))
     JOIN public.ubicacion_especifica ue ON ((ue.id_ubicacion = e.id_ubicacion_administrativa_actual)))
     JOIN public.area_registro ar ON ((ar.id_area = ue.id_area)))
     JOIN public.persona p ON ((p.id_persona = u.id_persona_responsable_uso)));


ALTER VIEW public.v_usos_clinicos_area OWNER TO hospital_user;

