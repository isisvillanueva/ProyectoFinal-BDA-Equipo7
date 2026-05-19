-- =====================================================================
-- TRIGGERS Y FUNCIONES VINCULADAS - hospital_db
-- Extraídos de: hospital_db__3_.sql
-- Funciones (RETURNS trigger): 28
-- Triggers:                    34
--
-- Orden: primero funciones, después triggers (los triggers dependen
-- de las funciones, así que deben crearse primero).
-- =====================================================================


-- =====================================================================
-- 1) FUNCIONES DE TRIGGER
-- =====================================================================

--
-- Name: fn_actualizar_estado_equipo_por_mantenimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_actualizar_estado_equipo_por_mantenimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE equipo
    SET id_estado_equipo = CASE
        WHEN NEW.id_resultado_mantenimiento = 1 THEN 1  -- Exitoso        -> Disponible
        WHEN NEW.id_resultado_mantenimiento = 2 THEN 4  -- Fallido        -> Fuera de servicio
        WHEN NEW.id_resultado_mantenimiento = 3 THEN 3  -- Pend. revisión -> En mantenimiento
        WHEN NEW.id_resultado_mantenimiento = 4 THEN 4  -- Req. reemplazo -> Fuera de servicio
        ELSE id_estado_equipo
    END
    WHERE id_equipo = NEW.id_equipo;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_actualizar_estado_equipo_por_mantenimiento() OWNER TO postgres;


--
-- Name: fn_actualizar_ubicacion_equipo_por_movimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_actualizar_ubicacion_equipo_por_movimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE equipo
    SET id_ubicacion_administrativa_actual = NEW.id_ubicacion_destino
    WHERE id_equipo = NEW.id_equipo;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_actualizar_ubicacion_equipo_por_movimiento() OWNER TO postgres;


--
-- Name: fn_auditoria_generica(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_auditoria_generica() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_usuario    INT;
    v_accion        VARCHAR(50);
    v_valor_antes   TEXT := NULL;
    v_valor_despues TEXT := NULL;
    v_origen        TEXT;
    v_id_registro   INT;
    v_json_new      JSONB := NULL;
    v_json_old      JSONB := NULL;
BEGIN
    v_id_usuario := NULLIF(current_setting('app.id_usuario', TRUE), '')::INT;
    IF v_id_usuario IS NULL THEN
        v_id_usuario := 1;
        v_origen     := 'directo_bd';
    ELSE
        v_origen := COALESCE(
            NULLIF(current_setting('app.origen', TRUE), ''),
            'sistema'
        );
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_json_new      := row_to_json(NEW)::JSONB;
        v_valor_despues := v_json_new::TEXT;
        v_valor_antes   := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        v_json_new      := row_to_json(NEW)::JSONB;
        v_json_old      := row_to_json(OLD)::JSONB;
        v_valor_antes   := v_json_old::TEXT;
        v_valor_despues := v_json_new::TEXT;
    END IF;

    v_id_registro := CASE TG_TABLE_NAME
        WHEN 'equipo'            THEN COALESCE((v_json_new->>'id_equipo')::INT,            (v_json_old->>'id_equipo')::INT)
        WHEN 'usuario'           THEN COALESCE((v_json_new->>'id_usuario')::INT,           (v_json_old->>'id_usuario')::INT)
        WHEN 'persona'           THEN COALESCE((v_json_new->>'id_persona')::INT,           (v_json_old->>'id_persona')::INT)
        WHEN 'asignacion_equipo' THEN COALESCE((v_json_new->>'id_asignacion')::INT,        (v_json_old->>'id_asignacion')::INT)
        WHEN 'movimiento'        THEN COALESCE((v_json_new->>'id_movimiento')::INT,        (v_json_old->>'id_movimiento')::INT)
        WHEN 'mantenimiento'     THEN COALESCE((v_json_new->>'id_mantenimiento')::INT,     (v_json_old->>'id_mantenimiento')::INT)
        WHEN 'responsable_area'  THEN COALESCE((v_json_new->>'id_responsable_area')::INT,  (v_json_old->>'id_responsable_area')::INT)
    END;

    v_accion := CASE
        WHEN TG_OP = 'INSERT' THEN 'INSERT'
        WHEN TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'usuario' THEN
            CASE
                WHEN (v_json_old->>'activo_usuario')::BOOLEAN = FALSE
                 AND (v_json_new->>'activo_usuario')::BOOLEAN = TRUE  THEN 'ACTIVACION'
                WHEN (v_json_old->>'activo_usuario')::BOOLEAN = TRUE
                 AND (v_json_new->>'activo_usuario')::BOOLEAN = FALSE THEN 'DESACTIVACION'
                ELSE 'UPDATE'
            END
        WHEN TG_OP = 'UPDATE' AND TG_TABLE_NAME = 'equipo' THEN
            CASE
                WHEN (v_json_old->>'activo_equipo')::BOOLEAN = FALSE
                 AND (v_json_new->>'activo_equipo')::BOOLEAN = TRUE   THEN 'ACTIVACION'
                WHEN (v_json_old->>'activo_equipo')::BOOLEAN = TRUE
                 AND (v_json_new->>'activo_equipo')::BOOLEAN = FALSE  THEN 'DELETE_LOGICO'
                WHEN (v_json_old->>'id_estado_equipo')::INT <> 5
                 AND (v_json_new->>'id_estado_equipo')::INT = 5       THEN 'DELETE_LOGICO'
                ELSE 'UPDATE'
            END
        ELSE 'UPDATE'
    END;

    INSERT INTO auditoria (
        id_usuario, fecha_hora_auditoria, accion_auditoria,
        tabla_afectada, id_registro_afectado,
        valor_antes, valor_despues, origen_cambio
    ) VALUES (
        v_id_usuario, NOW(), v_accion,
        TG_TABLE_NAME, v_id_registro,
        v_valor_antes, v_valor_despues, v_origen
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_auditoria_generica() OWNER TO postgres;


--
-- Name: fn_devolver_equipo_tras_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_devolver_equipo_tras_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE equipo
    SET id_estado_equipo = 1
    WHERE id_equipo = NEW.id_equipo;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_devolver_equipo_tras_traslado() OWNER TO postgres;


--
-- Name: fn_retirar_equipo_tras_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_retirar_equipo_tras_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE equipo
    SET id_estado_equipo = 6
    WHERE id_equipo = NEW.id_equipo;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_retirar_equipo_tras_traslado() OWNER TO postgres;


--
-- Name: fn_validar_ambulancia_activa_para_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_ambulancia_activa_para_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_ambulancia INT;
BEGIN
    SELECT id_estado_ambulancia
    INTO v_estado_ambulancia
    FROM ambulancia
    WHERE id_ambulancia = NEW.id_ambulancia;

    IF v_estado_ambulancia IS NULL THEN
        RAISE EXCEPTION 'La ambulancia no existe o no tiene un estado asignado.';
    END IF;

    IF v_estado_ambulancia <> 1 THEN
        RAISE EXCEPTION 'La ambulancia no esta activa para realizar el traslado externo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_ambulancia_activa_para_traslado() OWNER TO postgres;


--
-- Name: fn_validar_beacon_activo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_beacon_activo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo_beacon
    INTO v_activo
    FROM dispositivo_beacon
    WHERE id_beacon = NEW.id_beacon;

    IF v_activo IS NOT TRUE THEN
        RAISE EXCEPTION 'No se puede registrar un evento beacon porque el dispositivo esta inactivo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_beacon_activo() OWNER TO postgres;


--
-- Name: fn_validar_condiciones_retiro_equipo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_condiciones_retiro_equipo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT id_estado_equipo
    INTO v_estado_equipo
    FROM equipo
    WHERE id_equipo = NEW.id_equipo;

    IF v_estado_equipo <> 1 THEN
        RAISE EXCEPTION
            'Solo se puede registrar un traslado externo para un equipo en estado Disponible. Estado actual: %.', v_estado_equipo;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_condiciones_retiro_equipo() OWNER TO postgres;


--
-- Name: fn_validar_conductor_autorizado_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_conductor_autorizado_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM usuario u
        JOIN usuario_rol ur ON u.id_usuario = ur.id_usuario
        JOIN roles_usuario ru ON ur.id_rol_usuario = ru.id_rol_usuario
        WHERE u.id_persona = NEW.id_persona_conductor
          AND u.activo_usuario = TRUE
          AND ru.rol_usuario = 'Conductor'
    ) THEN
        RAISE EXCEPTION 'La persona indicada como conductor no tiene un usuario activo con rol Conductor.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_conductor_autorizado_traslado() OWNER TO postgres;


--
-- Name: fn_validar_equipo_disponible_para_uso(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_equipo_disponible_para_uso() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT id_estado_equipo
    INTO v_estado_equipo
    FROM equipo
    WHERE id_equipo = NEW.id_equipo;

    IF v_estado_equipo IS NULL THEN
        RAISE EXCEPTION 'El equipo no existe o no tiene un estado asignado.';
    END IF;

    IF v_estado_equipo <> 1 THEN
        RAISE EXCEPTION 'El equipo no esta disponible para uso clinico. Estado actual: %.', v_estado_equipo;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_equipo_disponible_para_uso() OWNER TO postgres;


--
-- Name: fn_validar_equipo_no_retirado_en_evento_beacon(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_equipo_no_retirado_en_evento_beacon() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT id_estado_equipo
    INTO v_estado_equipo
    FROM equipo
    WHERE id_equipo = NEW.id_equipo;

    IF v_estado_equipo IS NULL THEN
        RAISE EXCEPTION 'No se pudo determinar el estado del equipo en el evento beacon.';
    END IF;

    IF v_estado_equipo = 5 THEN
        RAISE EXCEPTION 'No se puede registrar un evento beacon para un equipo retirado.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_equipo_no_retirado_en_evento_beacon() OWNER TO postgres;


--
-- Name: fn_validar_equipo_no_retirado_en_evento_nfc(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_equipo_no_retirado_en_evento_nfc() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT e.id_estado_equipo
    INTO v_estado_equipo
    FROM dispositivo_nfc dn
    JOIN equipo e ON dn.id_equipo = e.id_equipo
    WHERE dn.id_nfc = NEW.id_nfc;

    IF v_estado_equipo IS NULL THEN
        RAISE EXCEPTION 'No se pudo determinar el estado del equipo asociado al NFC.';
    END IF;

    IF v_estado_equipo = 5 THEN
        RAISE EXCEPTION 'No se puede registrar evento NFC para un equipo retirado.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_equipo_no_retirado_en_evento_nfc() OWNER TO postgres;


--
-- Name: fn_validar_equipo_no_retirado_en_movimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_equipo_no_retirado_en_movimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT id_estado_equipo INTO v_estado_equipo
    FROM equipo WHERE id_equipo = NEW.id_equipo;

    IF v_estado_equipo IS NULL THEN
        RAISE EXCEPTION 'No se pudo determinar el estado del equipo.';
    END IF;

    IF v_estado_equipo = 5 THEN
        RAISE EXCEPTION 'No se puede registrar movimiento para un equipo retirado.';
    END IF;

    IF v_estado_equipo = 6 THEN
        RAISE EXCEPTION 'No se puede registrar movimiento para un equipo que está en préstamo externo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_equipo_no_retirado_en_movimiento() OWNER TO postgres;


--
-- Name: fn_validar_equipo_sin_uso_clinico_activo_para_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_equipo_sin_uso_clinico_activo_para_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM uso_clinico_equipo
        WHERE id_equipo = NEW.id_equipo
          AND fecha_hora_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'No se puede registrar el traslado externo porque el equipo tiene un uso clinico activo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_equipo_sin_uso_clinico_activo_para_traslado() OWNER TO postgres;


--
-- Name: fn_validar_especialidad_responsable_area(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_especialidad_responsable_area() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_especialidad INT;
BEGIN
    -- Obtener especialidad del enfermero
    SELECT id_especialidad_enfermero
    INTO v_especialidad
    FROM enfermero
    WHERE id_enfermero = NEW.id_enfermero;

    -- Verificar que la especialidad corresponde al área
    IF NOT EXISTS (
        SELECT 1
        FROM especialidad_area_enfermero
        WHERE id_especialidad_enfermero = v_especialidad
          AND id_area = NEW.id_area
    ) THEN
        RAISE EXCEPTION
            'El enfermero no tiene la especialidad requerida para ser responsable de esta area. '
            'Verifique la tabla de correspondencia especialidad-area.';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_especialidad_responsable_area() OWNER TO postgres;


--
-- Name: fn_validar_gps_activo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_gps_activo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo_gps
    INTO v_activo
    FROM dispositivo_gps
    WHERE id_gps = NEW.id_gps;

    IF v_activo IS NOT TRUE THEN
        RAISE EXCEPTION 'No se puede registrar un evento GPS porque el dispositivo esta inactivo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_gps_activo() OWNER TO postgres;


--
-- Name: fn_validar_mantenimiento_biomedico(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_mantenimiento_biomedico() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM biomedico b
        JOIN usuario u ON u.id_persona = b.id_persona
        WHERE b.id_biomedico = NEW.id_biomedico
          AND u.activo_usuario = TRUE
    ) THEN
        RAISE EXCEPTION 'El mantenimiento solo puede ser registrado por un biomedico con usuario activo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_mantenimiento_biomedico() OWNER TO postgres;


--
-- Name: fn_validar_nfc_activo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_nfc_activo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_activo BOOLEAN;
BEGIN
    SELECT activo_nfc
    INTO v_activo
    FROM dispositivo_nfc
    WHERE id_nfc = NEW.id_nfc;

    IF v_activo IS NOT TRUE THEN
        RAISE EXCEPTION 'No se puede registrar un evento NFC porque el dispositivo esta inactivo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_nfc_activo() OWNER TO postgres;


--
-- Name: fn_validar_nfc_equipo_traslado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_nfc_equipo_traslado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM dispositivo_nfc
        WHERE id_nfc = NEW.id_nfc_equipo
          AND id_equipo = NEW.id_equipo
    ) THEN
        RAISE EXCEPTION 'El NFC registrado no corresponde al equipo indicado en el traslado externo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_nfc_equipo_traslado() OWNER TO postgres;


--
-- Name: fn_validar_origen_movimiento_coherente(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_origen_movimiento_coherente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ubicacion_actual INT;
BEGIN
    SELECT id_ubicacion_administrativa_actual
    INTO v_ubicacion_actual
    FROM equipo
    WHERE id_equipo = NEW.id_equipo;

    IF v_ubicacion_actual IS NULL THEN
        RAISE EXCEPTION 'El equipo no tiene una ubicacion administrativa actual registrada.';
    END IF;

    IF v_ubicacion_actual <> NEW.id_ubicacion_origen THEN
        RAISE EXCEPTION 'La ubicacion origen del movimiento no coincide con la ubicacion administrativa actual del equipo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_origen_movimiento_coherente() OWNER TO postgres;


--
-- Name: fn_validar_persona_responsable_movimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_persona_responsable_movimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM usuario u
        JOIN usuario_rol ur ON u.id_usuario = ur.id_usuario
        JOIN roles_usuario ru ON ur.id_rol_usuario = ru.id_rol_usuario
        WHERE u.id_persona = NEW.id_persona_responsable_movimiento
          AND u.activo_usuario = TRUE
          AND ru.rol_usuario IN ('Administrador', 'Médico', 'Enfermero', 'Biomédico')
    ) THEN
        RAISE EXCEPTION 'La persona responsable no tiene un usuario activo con rol autorizado para realizar movimientos.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_persona_responsable_movimiento() OWNER TO postgres;


--
-- Name: fn_validar_sin_uso_clinico_activo_para_mantenimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_sin_uso_clinico_activo_para_mantenimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    SELECT id_estado_equipo INTO v_estado_equipo
    FROM equipo WHERE id_equipo = NEW.id_equipo;

    IF v_estado_equipo = 6 THEN
        RAISE EXCEPTION 'No se puede registrar mantenimiento porque el equipo está actualmente en préstamo externo.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM uso_clinico_equipo
        WHERE id_equipo = NEW.id_equipo AND fecha_hora_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'No se puede registrar mantenimiento porque el equipo tiene un uso clinico activo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_sin_uso_clinico_activo_para_mantenimiento() OWNER TO postgres;


--
-- Name: fn_validar_traslape_asignacion_equipo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_traslape_asignacion_equipo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM asignacion_equipo
        WHERE id_equipo = NEW.id_equipo
          
          AND id_asignacion <> COALESCE(NEW.id_asignacion, -1)
          
          AND NEW.fecha_inicio_asignacion < COALESCE(fecha_fin_asignacion, 'infinity'::TIMESTAMP)
          
          AND fecha_inicio_asignacion < COALESCE(NEW.fecha_fin_asignacion, 'infinity'::TIMESTAMP)
    ) THEN
        RAISE EXCEPTION
            'Traslape de periodos de asignacion detectado para el equipo %. '
            'Verifique que la asignacion anterior esté cerrada correctamente antes de registrar una nueva.',
            NEW.id_equipo;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_traslape_asignacion_equipo() OWNER TO postgres;


--
-- Name: fn_validar_traslape_responsable_area(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_traslape_responsable_area() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM responsable_area
        WHERE id_area = NEW.id_area
          
          AND id_responsable_area <> COALESCE(NEW.id_responsable_area, -1)
          
          AND NEW.fecha_inicio_responsable_area < COALESCE(fecha_fin_responsable_area, 'infinity'::TIMESTAMP)
          
          AND fecha_inicio_responsable_area < COALESCE(NEW.fecha_fin_responsable_area, 'infinity'::TIMESTAMP)
    ) THEN
        RAISE EXCEPTION
            'Traslape de periodos detectado en area %. '
            'Verifique que el responsable anterior esté cerrado correctamente antes de registrar uno nuevo.',
            NEW.id_area;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_traslape_responsable_area() OWNER TO postgres;


--
-- Name: fn_validar_turno_mantenimiento(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_turno_mantenimiento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_turno   INT;
    v_hora_inicio TIME;
    v_hora_fin   TIME;
    v_hora_actual TIME := CURRENT_TIME;
BEGIN
    -- Obtener turno del biomédico
    SELECT b.id_turno INTO v_id_turno
    FROM biomedico b
    WHERE b.id_biomedico = NEW.id_biomedico;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Obtener horario del turno
    SELECT hora_inicio, hora_fin
    INTO v_hora_inicio, v_hora_fin
    FROM turnos
    WHERE id_turno = v_id_turno;

    -- Validar según tipo de turno
    IF v_hora_inicio < v_hora_fin THEN
        -- Turno normal
        IF v_hora_actual NOT BETWEEN v_hora_inicio AND v_hora_fin THEN
            RAISE EXCEPTION
                'El biomedico no esta en su turno activo. '
                'Turno asignado: % a %. Hora actual: %.',
                v_hora_inicio, v_hora_fin, v_hora_actual;
        END IF;
    ELSE
        -- Turno nocturno — cruza medianoche
        IF NOT (v_hora_actual >= v_hora_inicio OR v_hora_actual <= v_hora_fin) THEN
            RAISE EXCEPTION
                'El biomedico no esta en su turno activo. '
                'Turno asignado: % a %. Hora actual: %.',
                v_hora_inicio, v_hora_fin, v_hora_actual;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_turno_mantenimiento() OWNER TO postgres;


--
-- Name: fn_validar_turno_uso_clinico(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_turno_uso_clinico() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_turno   INT;
    v_hora_inicio TIME;
    v_hora_fin   TIME;
    v_hora_actual TIME := CURRENT_TIME;
BEGIN
    -- Buscar turno del médico
    SELECT m.id_turno INTO v_id_turno
    FROM medico m
    WHERE m.id_persona = NEW.id_persona_responsable_uso;

    -- Si no es médico buscar en enfermero
    IF NOT FOUND THEN
        SELECT e.id_turno INTO v_id_turno
        FROM enfermero e
        WHERE e.id_persona = NEW.id_persona_responsable_uso;
    END IF;

    -- Si no se encontró turno no aplica la validación
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Obtener horario del turno
    SELECT hora_inicio, hora_fin
    INTO v_hora_inicio, v_hora_fin
    FROM turnos
    WHERE id_turno = v_id_turno;

    -- Validar según tipo de turno
    -- Turno normal: inicio < fin (no cruza medianoche)
    -- Turno nocturno: inicio > fin (cruza medianoche)
    IF v_hora_inicio < v_hora_fin THEN
        -- Turno normal
        IF v_hora_actual NOT BETWEEN v_hora_inicio AND v_hora_fin THEN
            RAISE EXCEPTION
                'El personal no esta en su turno activo. '
                'Turno asignado: % a %. Hora actual: %.',
                v_hora_inicio, v_hora_fin, v_hora_actual;
        END IF;
    ELSE
        -- Turno nocturno — cruza medianoche
        IF NOT (v_hora_actual >= v_hora_inicio OR v_hora_actual <= v_hora_fin) THEN
            RAISE EXCEPTION
                'El personal no esta en su turno activo. '
                'Turno asignado: % a %. Hora actual: %.',
                v_hora_inicio, v_hora_fin, v_hora_actual;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_turno_uso_clinico() OWNER TO postgres;


--
-- Name: fn_validar_unico_uso_clinico_activo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_unico_uso_clinico_activo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM uso_clinico_equipo
        WHERE id_equipo = NEW.id_equipo
          AND fecha_hora_fin IS NULL
          AND (NEW.id_uso_clinico IS NULL OR id_uso_clinico <> NEW.id_uso_clinico)
    ) THEN
        RAISE EXCEPTION 'El equipo ya tiene un uso clinico activo sin cerrar.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_unico_uso_clinico_activo() OWNER TO postgres;


--
-- Name: fn_validar_uso_clinico_personal_autorizado(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_uso_clinico_personal_autorizado() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM medico m
        JOIN usuario u ON u.id_persona = m.id_persona
        WHERE m.id_persona = NEW.id_persona_responsable_uso
          AND u.activo_usuario = TRUE
    )
    AND NOT EXISTS (
        SELECT 1
        FROM enfermero e
        JOIN usuario u ON u.id_persona = e.id_persona
        WHERE e.id_persona = NEW.id_persona_responsable_uso
          AND u.activo_usuario = TRUE
    ) THEN
        RAISE EXCEPTION 'Solo un medico o enfermero con usuario activo puede registrar uso clinico del equipo.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_validar_uso_clinico_personal_autorizado() OWNER TO postgres;



-- =====================================================================
-- 2) TRIGGERS
-- =====================================================================

--
-- Name: mantenimiento trg_actualizar_estado_equipo_por_mantenimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_actualizar_estado_equipo_por_mantenimiento AFTER INSERT OR UPDATE ON public.mantenimiento FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_estado_equipo_por_mantenimiento();

--
-- Name: movimiento trg_actualizar_ubicacion_equipo_por_movimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_actualizar_ubicacion_equipo_por_movimiento AFTER INSERT OR UPDATE ON public.movimiento FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_ubicacion_equipo_por_movimiento();

--
-- Name: asignacion_equipo trg_auditoria_asignacion_equipo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_asignacion_equipo AFTER INSERT OR UPDATE ON public.asignacion_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: equipo trg_auditoria_equipo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_equipo AFTER INSERT OR UPDATE ON public.equipo FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: mantenimiento trg_auditoria_mantenimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_mantenimiento AFTER INSERT OR UPDATE ON public.mantenimiento FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: movimiento trg_auditoria_movimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_movimiento AFTER INSERT OR UPDATE ON public.movimiento FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: persona trg_auditoria_persona; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_persona AFTER INSERT OR UPDATE ON public.persona FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: responsable_area trg_auditoria_responsable_area; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_responsable_area AFTER INSERT OR UPDATE ON public.responsable_area FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: usuario trg_auditoria_usuario; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditoria_usuario AFTER INSERT OR UPDATE ON public.usuario FOR EACH ROW EXECUTE FUNCTION public.fn_auditoria_generica();

--
-- Name: traslado_externo_equipo trg_devolver_equipo_tras_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_devolver_equipo_tras_traslado AFTER UPDATE ON public.traslado_externo_equipo FOR EACH ROW WHEN (((old.fecha_llegada IS NULL) AND (new.fecha_llegada IS NOT NULL))) EXECUTE FUNCTION public.fn_devolver_equipo_tras_traslado();

--
-- Name: traslado_externo_equipo trg_retirar_equipo_tras_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_retirar_equipo_tras_traslado AFTER INSERT ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_retirar_equipo_tras_traslado();

--
-- Name: traslado_externo_equipo trg_validar_ambulancia_activa_para_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_ambulancia_activa_para_traslado BEFORE INSERT OR UPDATE ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_ambulancia_activa_para_traslado();

--
-- Name: evento_beacon trg_validar_beacon_activo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_beacon_activo BEFORE INSERT OR UPDATE ON public.evento_beacon FOR EACH ROW EXECUTE FUNCTION public.fn_validar_beacon_activo();

--
-- Name: traslado_externo_equipo trg_validar_condiciones_retiro_equipo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_condiciones_retiro_equipo BEFORE INSERT OR UPDATE ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_condiciones_retiro_equipo();

--
-- Name: traslado_externo_equipo trg_validar_conductor_autorizado_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_conductor_autorizado_traslado BEFORE INSERT OR UPDATE ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_conductor_autorizado_traslado();

--
-- Name: uso_clinico_equipo trg_validar_equipo_disponible_para_uso; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_equipo_disponible_para_uso BEFORE INSERT ON public.uso_clinico_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_disponible_para_uso();

--
-- Name: evento_beacon trg_validar_equipo_no_retirado_en_evento_beacon; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_equipo_no_retirado_en_evento_beacon BEFORE INSERT OR UPDATE ON public.evento_beacon FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_no_retirado_en_evento_beacon();

--
-- Name: evento_nfc trg_validar_equipo_no_retirado_en_evento_nfc; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_equipo_no_retirado_en_evento_nfc BEFORE INSERT OR UPDATE ON public.evento_nfc FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_no_retirado_en_evento_nfc();

--
-- Name: movimiento trg_validar_equipo_no_retirado_en_movimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_equipo_no_retirado_en_movimiento BEFORE INSERT OR UPDATE ON public.movimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_no_retirado_en_movimiento();

--
-- Name: traslado_externo_equipo trg_validar_equipo_sin_uso_clinico_activo_para_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_equipo_sin_uso_clinico_activo_para_traslado BEFORE INSERT OR UPDATE ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_sin_uso_clinico_activo_para_traslado();

--
-- Name: responsable_area trg_validar_especialidad_responsable_area; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_especialidad_responsable_area BEFORE INSERT OR UPDATE ON public.responsable_area FOR EACH ROW EXECUTE FUNCTION public.fn_validar_especialidad_responsable_area();

--
-- Name: evento_gps trg_validar_gps_activo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_gps_activo BEFORE INSERT OR UPDATE ON public.evento_gps FOR EACH ROW EXECUTE FUNCTION public.fn_validar_gps_activo();

--
-- Name: mantenimiento trg_validar_mantenimiento_biomedico; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_mantenimiento_biomedico BEFORE INSERT OR UPDATE ON public.mantenimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_mantenimiento_biomedico();

--
-- Name: evento_nfc trg_validar_nfc_activo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_nfc_activo BEFORE INSERT OR UPDATE ON public.evento_nfc FOR EACH ROW EXECUTE FUNCTION public.fn_validar_nfc_activo();

--
-- Name: traslado_externo_equipo trg_validar_nfc_equipo_traslado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_nfc_equipo_traslado BEFORE INSERT OR UPDATE ON public.traslado_externo_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_nfc_equipo_traslado();

--
-- Name: movimiento trg_validar_origen_movimiento_coherente; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_origen_movimiento_coherente BEFORE INSERT OR UPDATE ON public.movimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_origen_movimiento_coherente();

--
-- Name: movimiento trg_validar_persona_responsable_movimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_persona_responsable_movimiento BEFORE INSERT OR UPDATE ON public.movimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_persona_responsable_movimiento();

--
-- Name: mantenimiento trg_validar_sin_uso_clinico_activo_para_mantenimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_sin_uso_clinico_activo_para_mantenimiento BEFORE INSERT OR UPDATE ON public.mantenimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_sin_uso_clinico_activo_para_mantenimiento();

--
-- Name: asignacion_equipo trg_validar_traslape_asignacion_equipo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_traslape_asignacion_equipo BEFORE INSERT OR UPDATE ON public.asignacion_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_traslape_asignacion_equipo();

--
-- Name: responsable_area trg_validar_traslape_responsable_area; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_traslape_responsable_area BEFORE INSERT OR UPDATE ON public.responsable_area FOR EACH ROW EXECUTE FUNCTION public.fn_validar_traslape_responsable_area();

--
-- Name: mantenimiento trg_validar_turno_mantenimiento; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_turno_mantenimiento BEFORE INSERT ON public.mantenimiento FOR EACH ROW EXECUTE FUNCTION public.fn_validar_turno_mantenimiento();

--
-- Name: uso_clinico_equipo trg_validar_turno_uso_clinico; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_turno_uso_clinico BEFORE INSERT ON public.uso_clinico_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_turno_uso_clinico();

--
-- Name: uso_clinico_equipo trg_validar_unico_uso_clinico_activo; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_unico_uso_clinico_activo BEFORE INSERT OR UPDATE ON public.uso_clinico_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_unico_uso_clinico_activo();

--
-- Name: uso_clinico_equipo trg_validar_uso_clinico_personal_autorizado; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_uso_clinico_personal_autorizado BEFORE INSERT OR UPDATE ON public.uso_clinico_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_uso_clinico_personal_autorizado();