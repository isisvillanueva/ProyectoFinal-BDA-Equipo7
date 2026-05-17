--
-- PostgreSQL database dump
--

\restrict BuAo9hq1T8QP3a6bHbhfL8X5z9cxY6BOEd9ozQdbkrug4uh1htyzVjoQ1eqCTga

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

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

--
-- Name: sp_asignar_equipo(integer, integer, integer, integer, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_asignar_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_ubicacion integer, OUT p_id_asignacion integer, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo     INT;
    v_asignacion_activa INT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT id_estado_equipo INTO v_estado_equipo
    FROM equipo
    WHERE id_equipo = p_id_equipo AND activo_equipo = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El equipo % no existe o está dado de baja.', p_id_equipo;
    END IF;

    IF v_estado_equipo <> 1 THEN
        RAISE EXCEPTION 'El equipo % no está disponible para asignación. Estado actual: %.', p_id_equipo, v_estado_equipo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM persona WHERE id_persona = p_id_persona_responsable) THEN
        RAISE EXCEPTION 'La persona % no existe.', p_id_persona_responsable;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ubicacion_especifica WHERE id_ubicacion = p_id_ubicacion) THEN
        RAISE EXCEPTION 'La ubicación % no existe.', p_id_ubicacion;
    END IF;

    -- Cerrar asignación activa anterior si existe
    SELECT id_asignacion INTO v_asignacion_activa
    FROM asignacion_equipo
    WHERE id_equipo = p_id_equipo AND fecha_fin_asignacion IS NULL;

    IF FOUND THEN
        UPDATE asignacion_equipo
        SET fecha_fin_asignacion = NOW(),
            id_estado_asignacion = 2
        WHERE id_asignacion = v_asignacion_activa;
    END IF;

    INSERT INTO asignacion_equipo (
        id_equipo, id_persona_responsable, id_ubicacion,
        fecha_inicio_asignacion, fecha_fin_asignacion,
        id_estado_asignacion, observacion_asignacion
    ) VALUES (
        p_id_equipo, p_id_persona_responsable, p_id_ubicacion,
        NOW(), NULL, 1, p_observacion
    )
    RETURNING id_asignacion INTO p_id_asignacion;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_asignar_equipo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_asignar_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_ubicacion integer, OUT p_id_asignacion integer, IN p_observacion text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_cambiar_estado_equipo(integer, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cambiar_estado_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nuevo_estado integer, OUT p_mensaje text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_actual  INT;
    v_nombre_estado  TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT id_estado_equipo INTO v_estado_actual
    FROM equipo
    WHERE id_equipo = p_id_equipo AND activo_equipo = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El equipo % no existe o está dado de baja.', p_id_equipo;
    END IF;

    IF v_estado_actual = 5 THEN
        RAISE EXCEPTION 'El equipo % está retirado y no puede cambiar de estado.', p_id_equipo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM estado_equipos WHERE id_estado_equipo = p_id_nuevo_estado) THEN
        RAISE EXCEPTION 'El estado % no existe en el catálogo.', p_id_nuevo_estado;
    END IF;

    UPDATE equipo
    SET id_estado_equipo = p_id_nuevo_estado
    WHERE id_equipo = p_id_equipo;

    SELECT estado_equipo INTO v_nombre_estado
    FROM estado_equipos WHERE id_estado_equipo = p_id_nuevo_estado;

    p_mensaje := 'Equipo ' || p_id_equipo || ' cambiado a estado: ' || v_nombre_estado;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_cambiar_estado_equipo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cambiar_estado_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nuevo_estado integer, OUT p_mensaje text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_cambiar_estado_usuario(integer, integer, boolean, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cambiar_estado_usuario(IN p_id_usuario integer, IN p_id_usuario_target integer, IN p_activo boolean, OUT p_mensaje text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_username TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF p_id_usuario = p_id_usuario_target AND p_activo = FALSE THEN
        RAISE EXCEPTION 'Un usuario no puede desactivarse a sí mismo.';
    END IF;

    SELECT username INTO v_username
    FROM usuario WHERE id_usuario = p_id_usuario_target;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario % no existe.', p_id_usuario_target;
    END IF;

    UPDATE usuario
    SET activo_usuario = p_activo
    WHERE id_usuario = p_id_usuario_target;

    p_mensaje := 'Usuario ' || v_username ||
        CASE WHEN p_activo THEN ' activado.' ELSE ' desactivado.' END;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_cambiar_estado_usuario: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cambiar_estado_usuario(IN p_id_usuario integer, IN p_id_usuario_target integer, IN p_activo boolean, OUT p_mensaje text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_cambiar_responsable_area(integer, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cambiar_responsable_area(IN p_id_usuario integer, IN p_id_area integer, IN p_id_enfermero_nuevo integer, OUT p_mensaje text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_responsable_actual INT;
    v_enfermero_actual   INT;
    v_nombre_area        TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT nombre_area INTO v_nombre_area
    FROM area_registro WHERE id_area = p_id_area;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El área % no existe.', p_id_area;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM enfermero e
        JOIN usuario u ON u.id_persona = e.id_persona
        WHERE e.id_enfermero = p_id_enfermero_nuevo
          AND u.activo_usuario = TRUE
    ) THEN
        RAISE EXCEPTION 'El enfermero % no existe o no tiene usuario activo.', p_id_enfermero_nuevo;
    END IF;

    -- Verificar responsable actual del área
    SELECT id_responsable_area, id_enfermero
    INTO v_responsable_actual, v_enfermero_actual
    FROM responsable_area
    WHERE id_area = p_id_area AND fecha_fin_responsable_area IS NULL;

    IF FOUND THEN
        IF v_enfermero_actual = p_id_enfermero_nuevo THEN
            RAISE EXCEPTION 'El enfermero % ya es el responsable activo de esta área.', p_id_enfermero_nuevo;
        END IF;

        -- Cerrar responsable actual del área
        UPDATE responsable_area
        SET fecha_fin_responsable_area = NOW()
        WHERE id_responsable_area = v_responsable_actual;
    END IF;

    -- Cerrar responsabilidad activa del nuevo enfermero en otra área si existe
    -- Esto previene violación del índice uq_responsable_por_enfermero
    UPDATE responsable_area
    SET fecha_fin_responsable_area = NOW()
    WHERE id_enfermero = p_id_enfermero_nuevo
      AND fecha_fin_responsable_area IS NULL
      AND id_area <> p_id_area;

    -- Registrar nuevo responsable
    INSERT INTO responsable_area (
        id_enfermero, id_area,
        fecha_inicio_responsable_area, fecha_fin_responsable_area
    ) VALUES (
        p_id_enfermero_nuevo, p_id_area, NOW(), NULL
    );

    p_mensaje := 'Responsable del área ' || v_nombre_area || ' actualizado correctamente.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_cambiar_responsable_area: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cambiar_responsable_area(IN p_id_usuario integer, IN p_id_area integer, IN p_id_enfermero_nuevo integer, OUT p_mensaje text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_cerrar_asignacion_equipo(integer, integer, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cerrar_asignacion_equipo(IN p_id_usuario integer, IN p_id_asignacion integer, OUT p_mensaje text, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_equipo INT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT id_equipo INTO v_id_equipo
    FROM asignacion_equipo
    WHERE id_asignacion = p_id_asignacion
      AND fecha_fin_asignacion IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La asignacion % no existe o ya fue cerrada.', p_id_asignacion;
    END IF;

    IF EXISTS (
        SELECT 1 FROM uso_clinico_equipo
        WHERE id_equipo = v_id_equipo
          AND fecha_hora_fin IS NULL
    ) THEN
        RAISE EXCEPTION 'No se puede cerrar la asignacion porque el equipo tiene un uso clinico activo.';
    END IF;

    UPDATE asignacion_equipo
    SET fecha_fin_asignacion = NOW(),
        id_estado_asignacion = 2,
        observacion_asignacion = COALESCE(p_observacion, observacion_asignacion)
    WHERE id_asignacion = p_id_asignacion;

    p_mensaje := 'Asignacion ' || p_id_asignacion ||
                 ' cerrada correctamente para equipo ' || v_id_equipo || '.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_cerrar_asignacion_equipo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cerrar_asignacion_equipo(IN p_id_usuario integer, IN p_id_asignacion integer, OUT p_mensaje text, IN p_observacion text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_cerrar_uso_clinico(integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cerrar_uso_clinico(IN p_id_usuario integer, IN p_id_uso_clinico integer, OUT p_mensaje text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_equipo    INT;
    v_fecha_inicio TIMESTAMP;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT id_equipo, fecha_hora_inicio
    INTO v_id_equipo, v_fecha_inicio
    FROM uso_clinico_equipo
    WHERE id_uso_clinico = p_id_uso_clinico
      AND fecha_hora_fin IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El uso clinico % no existe o ya fue cerrado.', p_id_uso_clinico;
    END IF;

    UPDATE uso_clinico_equipo
    SET fecha_hora_fin = NOW()
    WHERE id_uso_clinico = p_id_uso_clinico;

    -- Regresar equipo a estado Disponible (1)
    UPDATE equipo
    SET id_estado_equipo = 1
    WHERE id_equipo = v_id_equipo;

    p_mensaje := 'Uso clinico ' || p_id_uso_clinico ||
                 ' cerrado. Equipo ' || v_id_equipo ||
                 ' regresado a estado Disponible.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_cerrar_uso_clinico: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_cerrar_uso_clinico(IN p_id_usuario integer, IN p_id_uso_clinico integer, OUT p_mensaje text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_crear_persona(integer, text, text, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_crear_persona(IN p_id_usuario integer, IN p_nombre text, IN p_apellido text, IN p_correo text, OUT p_id_persona integer, OUT p_mensaje text, IN p_origen text DEFAULT 'web_admin'::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF p_nombre IS NULL OR trim(p_nombre) = '' THEN
        RAISE EXCEPTION 'El nombre de la persona es obligatorio.';
    END IF;

    IF p_apellido IS NULL OR trim(p_apellido) = '' THEN
        RAISE EXCEPTION 'El apellido de la persona es obligatorio.';
    END IF;

    IF p_correo IS NULL OR trim(p_correo) = '' THEN
        RAISE EXCEPTION 'El correo de la persona es obligatorio.';
    END IF;

    IF EXISTS (SELECT 1 FROM persona WHERE correo_persona = p_correo) THEN
        RAISE EXCEPTION 'correo duplicado: ya existe una persona con el correo %.', p_correo;
    END IF;

    INSERT INTO persona (nombre_persona, apellido_persona, correo_persona)
    VALUES (p_nombre, p_apellido, p_correo)
    RETURNING id_persona INTO p_id_persona;

    p_mensaje := 'Persona ' || p_nombre || ' ' || p_apellido || ' registrada con ID ' || p_id_persona;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_crear_persona: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_crear_persona(IN p_id_usuario integer, IN p_nombre text, IN p_apellido text, IN p_correo text, OUT p_id_persona integer, OUT p_mensaje text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_crear_usuario(integer, integer, text, text, integer, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: hospital_user
--

CREATE PROCEDURE public.sp_crear_usuario(IN p_id_usuario integer, IN p_id_persona integer, IN p_username text, IN p_contrasenia text, IN p_id_rol integer, IN p_id_especialidad integer, IN p_id_turno integer, IN p_origen text, OUT p_id_usuario_nuevo integer, OUT p_mensaje text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nombre_rol TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF p_username IS NULL OR trim(p_username) = '' THEN
        RAISE EXCEPTION 'El nombre de usuario es obligatorio.';
    END IF;

    IF p_contrasenia IS NULL OR trim(p_contrasenia) = '' THEN
        RAISE EXCEPTION 'La contraseña es obligatoria.';
    END IF;

    IF EXISTS (SELECT 1 FROM usuario WHERE username = p_username) THEN
        RAISE EXCEPTION 'username duplicado: el nombre de usuario "%" ya está en uso.', p_username;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM persona WHERE id_persona = p_id_persona) THEN
        RAISE EXCEPTION 'La persona con ID % no existe.', p_id_persona;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM roles_usuario WHERE id_rol_usuario = p_id_rol) THEN
        RAISE EXCEPTION 'El rol con ID % no existe.', p_id_rol;
    END IF;

    IF EXISTS (SELECT 1 FROM usuario WHERE id_persona = p_id_persona) THEN
        RAISE EXCEPTION 'persona ya tiene usuario: la persona seleccionada ya tiene un usuario asociado.';
    END IF;

    SELECT rol_usuario INTO v_nombre_rol FROM roles_usuario WHERE id_rol_usuario = p_id_rol;

    IF v_nombre_rol IN ('Médico', 'Enfermero') AND (p_id_especialidad IS NULL OR p_id_turno IS NULL) THEN
        RAISE EXCEPTION 'El rol % requiere especialidad y turno.', v_nombre_rol;
    END IF;

    IF v_nombre_rol = 'Biomédico' AND p_id_turno IS NULL THEN
        RAISE EXCEPTION 'El rol Biomédico requiere turno.';
    END IF;

    INSERT INTO usuario (username, contrasenia, activo_usuario, id_persona)
    VALUES (p_username, p_contrasenia, TRUE, p_id_persona)
    RETURNING id_usuario INTO p_id_usuario_nuevo;

    INSERT INTO usuario_rol (id_usuario, id_rol_usuario)
    VALUES (p_id_usuario_nuevo, p_id_rol);

    IF v_nombre_rol = 'Médico' THEN
        INSERT INTO medico (id_persona, id_especialidad_medico, id_turno)
        VALUES (p_id_persona, p_id_especialidad, p_id_turno);
    ELSIF v_nombre_rol = 'Enfermero' THEN
        INSERT INTO enfermero (id_persona, id_especialidad_enfermero, id_turno)
        VALUES (p_id_persona, p_id_especialidad, p_id_turno);
    ELSIF v_nombre_rol = 'Biomédico' THEN
        INSERT INTO biomedico (id_persona, id_turno)
        VALUES (p_id_persona, p_id_turno);
    END IF;

    p_mensaje := 'Usuario ' || p_username || ' creado con rol ' || v_nombre_rol;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_crear_usuario: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_crear_usuario(IN p_id_usuario integer, IN p_id_persona integer, IN p_username text, IN p_contrasenia text, IN p_id_rol integer, IN p_id_especialidad integer, IN p_id_turno integer, IN p_origen text, OUT p_id_usuario_nuevo integer, OUT p_mensaje text) OWNER TO hospital_user;

--
-- Name: sp_editar_usuario(integer, integer, text, text, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: hospital_user
--

CREATE PROCEDURE public.sp_editar_usuario(IN p_id_usuario_admin integer, IN p_id_usuario_target integer, IN p_username text, IN p_nueva_contrasenia text, IN p_id_especialidad integer, IN p_id_turno integer, IN p_origen text, OUT p_mensaje text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nombre_rol TEXT;
    v_id_persona INT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario_admin::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT u.id_persona, r.rol_usuario
    INTO v_id_persona, v_nombre_rol
    FROM usuario u
    JOIN usuario_rol ur ON ur.id_usuario = u.id_usuario
    JOIN roles_usuario r ON r.id_rol_usuario = ur.id_rol_usuario
    WHERE u.id_usuario = p_id_usuario_target;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El usuario con ID % no existe.', p_id_usuario_target;
    END IF;

    IF EXISTS (
        SELECT 1 FROM usuario
        WHERE username = p_username AND id_usuario <> p_id_usuario_target
    ) THEN
        RAISE EXCEPTION 'username duplicado: el nombre de usuario "%" ya está en uso.', p_username;
    END IF;

    -- Actualizar usuario
    IF p_nueva_contrasenia IS NOT NULL AND p_nueva_contrasenia <> '' THEN
        UPDATE usuario SET username = p_username, contrasenia = p_nueva_contrasenia
        WHERE id_usuario = p_id_usuario_target;
    ELSE
        UPDATE usuario SET username = p_username
        WHERE id_usuario = p_id_usuario_target;
    END IF;

    -- Upsert en tabla de perfil por rol
    IF v_nombre_rol = 'Médico' AND p_id_especialidad IS NOT NULL AND p_id_turno IS NOT NULL THEN
        INSERT INTO medico (id_persona, id_especialidad_medico, id_turno)
        VALUES (v_id_persona, p_id_especialidad, p_id_turno)
        ON CONFLICT (id_persona) DO UPDATE
            SET id_especialidad_medico = EXCLUDED.id_especialidad_medico,
                id_turno               = EXCLUDED.id_turno;

    ELSIF v_nombre_rol = 'Enfermero' AND p_id_especialidad IS NOT NULL AND p_id_turno IS NOT NULL THEN
        INSERT INTO enfermero (id_persona, id_especialidad_enfermero, id_turno)
        VALUES (v_id_persona, p_id_especialidad, p_id_turno)
        ON CONFLICT (id_persona) DO UPDATE
            SET id_especialidad_enfermero = EXCLUDED.id_especialidad_enfermero,
                id_turno                  = EXCLUDED.id_turno;

    ELSIF v_nombre_rol = 'Biomédico' AND p_id_turno IS NOT NULL THEN
        INSERT INTO biomedico (id_persona, id_turno)
        VALUES (v_id_persona, p_id_turno)
        ON CONFLICT (id_persona) DO UPDATE
            SET id_turno = EXCLUDED.id_turno;
    END IF;

    p_mensaje := 'Usuario actualizado correctamente.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_editar_usuario: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_editar_usuario(IN p_id_usuario_admin integer, IN p_id_usuario_target integer, IN p_username text, IN p_nueva_contrasenia text, IN p_id_especialidad integer, IN p_id_turno integer, IN p_origen text, OUT p_mensaje text) OWNER TO hospital_user;

--
-- Name: sp_historial_equipo(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_historial_equipo(IN p_id_usuario integer, IN p_id_equipo integer, INOUT p_resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);

    IF NOT EXISTS (SELECT 1 FROM equipo WHERE id_equipo = p_id_equipo) THEN
        RAISE EXCEPTION 'El equipo % no existe.', p_id_equipo;
    END IF;

    OPEN p_resultado FOR
        SELECT
            'Movimiento'             AS tipo_evento,
            m.fecha_hora_movimiento  AS fecha_hora,
            tm.tipo_movimiento       AS descripcion_tipo,
            uo.nombre_ubicacion      AS origen,
            ud.nombre_ubicacion      AS destino,
            CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
            m.motivo_movimiento      AS detalle,
            NULL::NUMERIC            AS costo
        FROM movimiento m
        JOIN tipo_movimientos tm     ON tm.id_tipo_movimiento  = m.id_tipo_movimiento
        JOIN ubicacion_especifica uo ON uo.id_ubicacion        = m.id_ubicacion_origen
        JOIN ubicacion_especifica ud ON ud.id_ubicacion        = m.id_ubicacion_destino
        JOIN persona p               ON p.id_persona           = m.id_persona_responsable_movimiento
        WHERE m.id_equipo = p_id_equipo

        UNION ALL

        SELECT
            'Mantenimiento'              AS tipo_evento,
            mt.fecha_hora_mantenimiento  AS fecha_hora,
            tm.tipo_mantenimiento        AS descripcion_tipo,
            NULL                         AS origen,
            trm.resultado_mantenimiento  AS destino,
            CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
            mt.descripcion_mantenimiento AS detalle,
            mt.costo_mantenimiento       AS costo
        FROM mantenimiento mt
        JOIN tipo_mantenimientos tm            ON tm.id_tipo_mantenimiento       = mt.id_tipo_mantenimiento
        JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = mt.id_resultado_mantenimiento
        JOIN biomedico b                       ON b.id_biomedico                 = mt.id_biomedico
        JOIN persona p                         ON p.id_persona                   = b.id_persona
        WHERE mt.id_equipo = p_id_equipo

        UNION ALL

        SELECT
            'Uso Clinico'                AS tipo_evento,
            uce.fecha_hora_inicio        AS fecha_hora,
            tp.tipo_procedimiento        AS descripcion_tipo,
            NULL                         AS origen,
            ar.nombre_area               AS destino,
            CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS responsable,
            uce.motivo_uso               AS detalle,
            NULL::NUMERIC                AS costo
        FROM uso_clinico_equipo uce
        JOIN tipo_procedimiento tp ON tp.id_tipo_procedimiento = uce.id_tipo_procedimiento
        JOIN area_registro ar      ON ar.id_area               = uce.id_area
        JOIN persona p             ON p.id_persona             = uce.id_persona_responsable_uso
        WHERE uce.id_equipo = p_id_equipo

        ORDER BY fecha_hora DESC;

END;
$$;


ALTER PROCEDURE public.sp_historial_equipo(IN p_id_usuario integer, IN p_id_equipo integer, INOUT p_resultado refcursor) OWNER TO postgres;

--
-- Name: sp_quitar_responsable_area(integer, integer, text); Type: PROCEDURE; Schema: public; Owner: hospital_user
--

CREATE PROCEDURE public.sp_quitar_responsable_area(IN p_id_usuario integer, IN p_id_enfermero integer, OUT p_mensaje text, IN p_origen text DEFAULT 'web_admin'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nombre_area TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT ar.nombre_area INTO v_nombre_area
    FROM responsable_area ra
    JOIN area_registro ar ON ar.id_area = ra.id_area
    WHERE ra.id_enfermero = p_id_enfermero
      AND ra.fecha_fin_responsable_area IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El enfermero % no es responsable activo de ningún área.', p_id_enfermero;
    END IF;

    UPDATE responsable_area
    SET fecha_fin_responsable_area = NOW()
    WHERE id_enfermero = p_id_enfermero
      AND fecha_fin_responsable_area IS NULL;

    p_mensaje := 'Responsabilidad de área "' || v_nombre_area || '" removida. El enfermero continúa activo en su perfil.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_quitar_responsable_area: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_quitar_responsable_area(IN p_id_usuario integer, IN p_id_enfermero integer, OUT p_mensaje text, IN p_origen text) OWNER TO hospital_user;

--
-- Name: sp_registrar_beacon(integer, character varying, integer, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: hospital_user
--

CREATE PROCEDURE public.sp_registrar_beacon(IN p_id_usuario integer, IN p_uuid character varying, IN p_major integer, IN p_minor integer, IN p_id_zona_beacon integer, OUT p_id_beacon integer, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF p_uuid IS NULL OR trim(p_uuid) = '' THEN
        RAISE EXCEPTION 'El UUID del beacon es obligatorio.';
    END IF;

    IF p_major < 0 OR p_minor < 0 THEN
        RAISE EXCEPTION 'Major y minor deben ser >= 0.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM zona_beacon WHERE id_zona_beacon = p_id_zona_beacon) THEN
        RAISE EXCEPTION 'La zona beacon % no existe.', p_id_zona_beacon;
    END IF;

    IF EXISTS (
        SELECT 1 FROM dispositivo_beacon
        WHERE uuid_beacon = p_uuid AND major_beacon = p_major AND minor_beacon = p_minor
    ) THEN
        RAISE EXCEPTION 'Ya existe un beacon con ese UUID/major/minor.';
    END IF;

    INSERT INTO dispositivo_beacon (uuid_beacon, major_beacon, minor_beacon, activo_beacon, id_zona_beacon)
    VALUES (p_uuid, p_major, p_minor, TRUE, p_id_zona_beacon)
    RETURNING id_beacon INTO p_id_beacon;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_beacon: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_beacon(IN p_id_usuario integer, IN p_uuid character varying, IN p_major integer, IN p_minor integer, IN p_id_zona_beacon integer, OUT p_id_beacon integer, IN p_origen text) OWNER TO hospital_user;

--
-- Name: sp_registrar_equipo(integer, character varying, character varying, integer, character varying, integer, integer, integer, character varying, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_registrar_equipo(IN p_id_usuario integer, IN p_codigo_interno character varying, IN p_nombre_equipo character varying, IN p_id_modelo integer, IN p_numero_serie character varying, IN p_id_tipo_equipo integer, IN p_id_criticidad integer, IN p_id_ubicacion integer, IN p_codigo_uid_nfc character varying, OUT p_id_equipo integer, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF p_codigo_interno IS NULL OR trim(p_codigo_interno) = '' THEN
        RAISE EXCEPTION 'El código interno del equipo es obligatorio.';
    END IF;

    IF p_nombre_equipo IS NULL OR trim(p_nombre_equipo) = '' THEN
        RAISE EXCEPTION 'El nombre del equipo es obligatorio.';
    END IF;

    IF EXISTS (SELECT 1 FROM equipo WHERE codigo_interno = p_codigo_interno) THEN
        RAISE EXCEPTION 'Ya existe un equipo con el codigo interno %.', p_codigo_interno;
    END IF;

    IF p_numero_serie IS NULL OR p_numero_serie = '' THEN
        RAISE EXCEPTION 'El numero de serie es obligatorio.';
    END IF;

    IF EXISTS (SELECT 1 FROM equipo WHERE numero_serie = p_numero_serie) THEN
        RAISE EXCEPTION 'Ya existe un equipo con el numero de serie %.', p_numero_serie;
    END IF;

    IF p_codigo_uid_nfc IS NOT NULL AND p_codigo_uid_nfc <> '' AND
       EXISTS (SELECT 1 FROM dispositivo_nfc WHERE codigo_uid_nfc = p_codigo_uid_nfc) THEN
        RAISE EXCEPTION 'El codigo NFC % ya esta registrado en otro equipo.', p_codigo_uid_nfc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM modelo_equipo WHERE id_modelo = p_id_modelo) THEN
        RAISE EXCEPTION 'El modelo % no existe.', p_id_modelo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tipo_equipos WHERE id_tipo_equipo = p_id_tipo_equipo) THEN
        RAISE EXCEPTION 'El tipo de equipo % no existe.', p_id_tipo_equipo;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM criticidad_equipos WHERE id_criticidad_equipo = p_id_criticidad) THEN
        RAISE EXCEPTION 'La criticidad % no existe.', p_id_criticidad;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ubicacion_especifica WHERE id_ubicacion = p_id_ubicacion) THEN
        RAISE EXCEPTION 'La ubicacion % no existe.', p_id_ubicacion;
    END IF;

    INSERT INTO equipo (
        codigo_interno, nombre_equipo, id_modelo,
        numero_serie, id_tipo_equipo, id_criticidad_equipo,
        id_estado_equipo, id_ubicacion_administrativa_actual,
        activo_equipo
    ) VALUES (
        p_codigo_interno, p_nombre_equipo, p_id_modelo,
        p_numero_serie, p_id_tipo_equipo, p_id_criticidad,
        1, p_id_ubicacion,
        TRUE
    )
    RETURNING id_equipo INTO p_id_equipo;

    IF p_codigo_uid_nfc IS NOT NULL AND p_codigo_uid_nfc <> '' THEN
        INSERT INTO dispositivo_nfc (codigo_uid_nfc, activo_nfc, id_equipo)
        VALUES (p_codigo_uid_nfc, TRUE, p_id_equipo);
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_equipo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_equipo(IN p_id_usuario integer, IN p_codigo_interno character varying, IN p_nombre_equipo character varying, IN p_id_modelo integer, IN p_numero_serie character varying, IN p_id_tipo_equipo integer, IN p_id_criticidad integer, IN p_id_ubicacion integer, IN p_codigo_uid_nfc character varying, OUT p_id_equipo integer, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_registrar_mantenimiento(integer, integer, integer, integer, text, integer, integer, numeric, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_registrar_mantenimiento(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_biomedico integer, IN p_id_tipo_mantenimiento integer, IN p_descripcion text, IN p_id_resultado_mantenimiento integer, OUT p_id_mantenimiento integer, IN p_id_programacion integer DEFAULT NULL::integer, IN p_costo numeric DEFAULT NULL::numeric, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_frecuencia_dias INT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF NOT EXISTS (SELECT 1 FROM equipo WHERE id_equipo = p_id_equipo) THEN
        RAISE EXCEPTION 'El equipo % no existe.', p_id_equipo;
    END IF;

    IF p_descripcion IS NULL OR trim(p_descripcion) = '' THEN
        RAISE EXCEPTION 'La descripción del mantenimiento es obligatoria.';
    END IF;

    IF p_id_programacion IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM mantenimiento_programado
            WHERE id_programacion = p_id_programacion
              AND id_equipo = p_id_equipo
        ) THEN
            RAISE EXCEPTION 'La programación % no corresponde al equipo %.', p_id_programacion, p_id_equipo;
        END IF;
    END IF;

    INSERT INTO mantenimiento (
        id_equipo, id_biomedico, fecha_hora_mantenimiento,
        id_programacion, id_tipo_mantenimiento,
        descripcion_mantenimiento, id_resultado_mantenimiento,
        costo_mantenimiento, observacion_mantenimiento
    ) VALUES (
        p_id_equipo, p_id_biomedico, NOW(),
        p_id_programacion, p_id_tipo_mantenimiento,
        p_descripcion, p_id_resultado_mantenimiento,
        p_costo, p_observacion
    )
    RETURNING id_mantenimiento INTO p_id_mantenimiento;

    IF p_id_programacion IS NOT NULL THEN
        SELECT frecuencia_dias INTO v_frecuencia_dias
        FROM mantenimiento_programado
        WHERE id_programacion = p_id_programacion;

        UPDATE mantenimiento_programado
        SET fecha_ultimo_mantenimiento  = NOW(),
            fecha_proximo_mantenimiento = NOW() + (v_frecuencia_dias || ' days')::INTERVAL,
            id_estado_cumplimiento      = 2
        WHERE id_programacion = p_id_programacion;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_mantenimiento: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_mantenimiento(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_biomedico integer, IN p_id_tipo_mantenimiento integer, IN p_descripcion text, IN p_id_resultado_mantenimiento integer, OUT p_id_mantenimiento integer, IN p_id_programacion integer, IN p_costo numeric, IN p_observacion text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_registrar_movimiento_equipo(integer, integer, integer, integer, integer, integer, text, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_registrar_movimiento_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable_movimiento integer, IN p_id_tipo_movimiento integer, IN p_id_ubicacion_origen integer, IN p_id_ubicacion_destino integer, OUT p_id_movimiento integer, IN p_motivo text DEFAULT NULL::text, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF NOT EXISTS (
        SELECT 1 FROM equipo
        WHERE id_equipo = p_id_equipo AND activo_equipo = TRUE
    ) THEN
        RAISE EXCEPTION 'El equipo % no existe o está dado de baja.', p_id_equipo;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tipo_movimientos WHERE id_tipo_movimiento = p_id_tipo_movimiento
    ) THEN
        RAISE EXCEPTION 'El tipo de movimiento % no existe.', p_id_tipo_movimiento;
    END IF;

    -- Triggers BEFORE validan: estado retirado, rol responsable, coherencia origen
    -- Trigger AFTER actualiza: ubicación administrativa del equipo
    INSERT INTO movimiento (
        id_equipo, id_persona_responsable_movimiento,
        fecha_hora_movimiento, id_tipo_movimiento,
        id_ubicacion_origen, id_ubicacion_destino,
        motivo_movimiento, observacion_movimiento
    ) VALUES (
        p_id_equipo, p_id_persona_responsable_movimiento,
        NOW(), p_id_tipo_movimiento,
        p_id_ubicacion_origen, p_id_ubicacion_destino,
        p_motivo, p_observacion
    )
    RETURNING id_movimiento INTO p_id_movimiento;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_movimiento_equipo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_movimiento_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable_movimiento integer, IN p_id_tipo_movimiento integer, IN p_id_ubicacion_origen integer, IN p_id_ubicacion_destino integer, OUT p_id_movimiento integer, IN p_motivo text, IN p_observacion text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_registrar_traslado_externo(integer, integer, integer, integer, integer, integer, text, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_registrar_traslado_externo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nfc_equipo integer, IN p_id_ambulancia integer, IN p_id_persona_conductor integer, IN p_id_tipo_traslado integer, OUT p_id_traslado integer, IN p_motivo text DEFAULT NULL::text, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    IF NOT EXISTS (
        SELECT 1 FROM equipo
        WHERE id_equipo = p_id_equipo AND activo_equipo = TRUE
    ) THEN
        RAISE EXCEPTION 'El equipo % no existe o está dado de baja.', p_id_equipo;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tipo_traslado_externo WHERE id_tipo_traslado = p_id_tipo_traslado
    ) THEN
        RAISE EXCEPTION 'El tipo de traslado % no existe.', p_id_tipo_traslado;
    END IF;

    -- Triggers BEFORE validan: NFC coherente, ambulancia activa,
    --                          conductor autorizado, sin uso clínico activo
    INSERT INTO traslado_externo_equipo (
        id_equipo, id_nfc_equipo, id_ambulancia,
        id_persona_conductor, fecha_salida, fecha_llegada,
        id_tipo_traslado, motivo_traslado, observacion_traslado
    ) VALUES (
        p_id_equipo, p_id_nfc_equipo, p_id_ambulancia,
        p_id_persona_conductor, NOW(), NULL,
        p_id_tipo_traslado, p_motivo, p_observacion
    )
    RETURNING id_traslado_externo INTO p_id_traslado;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_traslado_externo: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_traslado_externo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nfc_equipo integer, IN p_id_ambulancia integer, IN p_id_persona_conductor integer, IN p_id_tipo_traslado integer, OUT p_id_traslado integer, IN p_motivo text, IN p_observacion text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_registrar_uso_clinico(integer, integer, integer, integer, integer, integer, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_registrar_uso_clinico(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_area integer, IN p_id_turno integer, IN p_id_tipo_procedimiento integer, OUT p_id_uso_clinico integer, IN p_motivo text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_estado_equipo INT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT id_estado_equipo INTO v_estado_equipo
    FROM equipo
    WHERE id_equipo = p_id_equipo AND activo_equipo = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El equipo % no existe o esta dado de baja.', p_id_equipo;
    END IF;

    IF v_estado_equipo <> 1 THEN
        RAISE EXCEPTION 'El equipo % no esta disponible. Estado actual: %.', p_id_equipo, v_estado_equipo;
    END IF;

    -- Triggers BEFORE validan: personal autorizado, turno activo, uso unico activo
    INSERT INTO uso_clinico_equipo (
        id_equipo, id_persona_responsable_uso,
        fecha_hora_inicio, fecha_hora_fin,
        id_area, id_turno, id_tipo_procedimiento, motivo_uso
    ) VALUES (
        p_id_equipo, p_id_persona_responsable,
        NOW(), NULL,
        p_id_area, p_id_turno, p_id_tipo_procedimiento, p_motivo
    )
    RETURNING id_uso_clinico INTO p_id_uso_clinico;

    -- Cambiar estado del equipo a En uso (2)
    UPDATE equipo
    SET id_estado_equipo = 2
    WHERE id_equipo = p_id_equipo;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_registrar_uso_clinico: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_registrar_uso_clinico(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_area integer, IN p_id_turno integer, IN p_id_tipo_procedimiento integer, OUT p_id_uso_clinico integer, IN p_motivo text, IN p_origen text) OWNER TO postgres;

--
-- Name: sp_reporte_carga_biomedica(integer, timestamp without time zone, timestamp without time zone, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reporte_carga_biomedica(IN p_id_usuario integer, IN p_fecha_inicio timestamp without time zone, IN p_fecha_fin timestamp without time zone, INOUT p_resultado refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);

    IF p_fecha_inicio >= p_fecha_fin THEN
        RAISE EXCEPTION 'La fecha de inicio debe ser anterior a la fecha de fin.';
    END IF;

    OPEN p_resultado FOR
        SELECT
            CONCAT(p.nombre_persona, ' ', p.apellido_persona) AS biomedico,
            COUNT(m.id_mantenimiento)                          AS total_mantenimientos,
            SUM(CASE WHEN m.id_resultado_mantenimiento = 1
                THEN 1 ELSE 0 END)                             AS exitosos,
            SUM(CASE WHEN m.id_resultado_mantenimiento IN (2,3,4)
                THEN 1 ELSE 0 END)                             AS desfavorables,
            COALESCE(SUM(m.costo_mantenimiento), 0)            AS costo_total_gestionado,
            COALESCE(ROUND(AVG(m.costo_mantenimiento), 2), 0)  AS costo_promedio,
            MIN(m.fecha_hora_mantenimiento)                    AS primer_mantenimiento_periodo,
            MAX(m.fecha_hora_mantenimiento)                    AS ultimo_mantenimiento_periodo
        FROM biomedico b
        JOIN persona p ON p.id_persona = b.id_persona
        LEFT JOIN mantenimiento m ON m.id_biomedico = b.id_biomedico
            AND m.fecha_hora_mantenimiento BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP BY b.id_biomedico, p.nombre_persona, p.apellido_persona
        ORDER BY total_mantenimientos DESC;

END;
$$;


ALTER PROCEDURE public.sp_reporte_carga_biomedica(IN p_id_usuario integer, IN p_fecha_inicio timestamp without time zone, IN p_fecha_fin timestamp without time zone, INOUT p_resultado refcursor) OWNER TO postgres;

--
-- Name: sp_reprogramar_mantenimiento(integer, integer, timestamp without time zone, text, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reprogramar_mantenimiento(IN p_id_usuario integer, IN p_id_programacion integer, IN p_nueva_fecha timestamp without time zone, OUT p_mensaje text, IN p_observacion text DEFAULT NULL::text, IN p_origen text DEFAULT 'sistema'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_equipo           INT;
    v_estado_cumplimiento INT;
    v_nombre_equipo       TEXT;
BEGIN
    PERFORM set_config('app.id_usuario', p_id_usuario::TEXT, TRUE);
    PERFORM set_config('app.origen', p_origen, TRUE);

    SELECT mp.id_equipo, mp.id_estado_cumplimiento, e.nombre_equipo
    INTO v_id_equipo, v_estado_cumplimiento, v_nombre_equipo
    FROM mantenimiento_programado mp
    JOIN equipo e ON e.id_equipo = mp.id_equipo
    WHERE mp.id_programacion = p_id_programacion;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La programacion de mantenimiento % no existe.', p_id_programacion;
    END IF;

    IF v_estado_cumplimiento NOT IN (1, 3) THEN
        RAISE EXCEPTION 'Solo se pueden reprogramar mantenimientos en estado Pendiente o Vencido.';
    END IF;

    IF p_nueva_fecha <= NOW() THEN
        RAISE EXCEPTION 'La nueva fecha de mantenimiento debe ser una fecha futura.';
    END IF;

    UPDATE mantenimiento_programado
    SET fecha_proximo_mantenimiento = p_nueva_fecha,
        id_estado_cumplimiento      = 4,
        observacion_programacion    = COALESCE(p_observacion, observacion_programacion)
    WHERE id_programacion = p_id_programacion;

    p_mensaje := 'Mantenimiento del equipo ' || v_nombre_equipo ||
                 ' reprogramado para ' || p_nueva_fecha::TEXT || '.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_reprogramar_mantenimiento: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_reprogramar_mantenimiento(IN p_id_usuario integer, IN p_id_programacion integer, IN p_nueva_fecha timestamp without time zone, OUT p_mensaje text, IN p_observacion text, IN p_origen text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ambulancia; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ambulancia (
    id_ambulancia integer NOT NULL,
    codigo_ambulancia character varying(50) NOT NULL,
    placa character varying(50) NOT NULL,
    id_estado_ambulancia integer NOT NULL,
    activo_ambulancia boolean DEFAULT true NOT NULL
);


ALTER TABLE public.ambulancia OWNER TO postgres;

--
-- Name: ambulancia_id_ambulancia_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ambulancia_id_ambulancia_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ambulancia_id_ambulancia_seq OWNER TO postgres;

--
-- Name: ambulancia_id_ambulancia_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ambulancia_id_ambulancia_seq OWNED BY public.ambulancia.id_ambulancia;


--
-- Name: area_registro; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.area_registro (
    id_area integer NOT NULL,
    nombre_area character varying(100) NOT NULL
);


ALTER TABLE public.area_registro OWNER TO postgres;

--
-- Name: area_registro_id_area_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.area_registro_id_area_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.area_registro_id_area_seq OWNER TO postgres;

--
-- Name: area_registro_id_area_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.area_registro_id_area_seq OWNED BY public.area_registro.id_area;


--
-- Name: asignacion_equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.asignacion_equipo (
    id_asignacion integer NOT NULL,
    id_equipo integer NOT NULL,
    id_persona_responsable integer NOT NULL,
    id_ubicacion integer NOT NULL,
    fecha_inicio_asignacion timestamp without time zone NOT NULL,
    fecha_fin_asignacion timestamp without time zone,
    id_estado_asignacion integer NOT NULL,
    observacion_asignacion text,
    CONSTRAINT asignacion_equipo_check CHECK (((fecha_fin_asignacion IS NULL) OR (fecha_fin_asignacion >= fecha_inicio_asignacion)))
);


ALTER TABLE public.asignacion_equipo OWNER TO postgres;

--
-- Name: asignacion_equipo_id_asignacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.asignacion_equipo_id_asignacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.asignacion_equipo_id_asignacion_seq OWNER TO postgres;

--
-- Name: asignacion_equipo_id_asignacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.asignacion_equipo_id_asignacion_seq OWNED BY public.asignacion_equipo.id_asignacion;


--
-- Name: auditoria; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.auditoria (
    id_auditoria integer NOT NULL,
    id_usuario integer NOT NULL,
    fecha_hora_auditoria timestamp without time zone NOT NULL,
    accion_auditoria character varying(50) NOT NULL,
    tabla_afectada character varying(100) NOT NULL,
    id_registro_afectado integer NOT NULL,
    valor_antes text,
    valor_despues text,
    origen_cambio character varying(100) NOT NULL,
    CONSTRAINT auditoria_accion_auditoria_check CHECK (((accion_auditoria)::text = ANY (ARRAY[('INSERT'::character varying)::text, ('UPDATE'::character varying)::text, ('DELETE_LOGICO'::character varying)::text, ('ACTIVACION'::character varying)::text, ('DESACTIVACION'::character varying)::text])))
);


ALTER TABLE public.auditoria OWNER TO postgres;

--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.auditoria_id_auditoria_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.auditoria_id_auditoria_seq OWNER TO postgres;

--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.auditoria_id_auditoria_seq OWNED BY public.auditoria.id_auditoria;


--
-- Name: biomedico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.biomedico (
    id_biomedico integer NOT NULL,
    id_persona integer NOT NULL,
    id_turno integer NOT NULL
);


ALTER TABLE public.biomedico OWNER TO postgres;

--
-- Name: biomedico_id_biomedico_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.biomedico_id_biomedico_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.biomedico_id_biomedico_seq OWNER TO postgres;

--
-- Name: biomedico_id_biomedico_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.biomedico_id_biomedico_seq OWNED BY public.biomedico.id_biomedico;


--
-- Name: categoria_equipos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categoria_equipos (
    id_categoria_equipo integer NOT NULL,
    categoria_equipo character varying(50) NOT NULL
);


ALTER TABLE public.categoria_equipos OWNER TO postgres;

--
-- Name: categoria_equipos_id_categoria_equipo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categoria_equipos_id_categoria_equipo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categoria_equipos_id_categoria_equipo_seq OWNER TO postgres;

--
-- Name: categoria_equipos_id_categoria_equipo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categoria_equipos_id_categoria_equipo_seq OWNED BY public.categoria_equipos.id_categoria_equipo;


--
-- Name: criticidad_equipos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.criticidad_equipos (
    id_criticidad_equipo integer NOT NULL,
    criticidad_equipo character varying(50) NOT NULL
);


ALTER TABLE public.criticidad_equipos OWNER TO postgres;

--
-- Name: criticidad_equipos_id_criticidad_equipo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.criticidad_equipos_id_criticidad_equipo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.criticidad_equipos_id_criticidad_equipo_seq OWNER TO postgres;

--
-- Name: criticidad_equipos_id_criticidad_equipo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.criticidad_equipos_id_criticidad_equipo_seq OWNED BY public.criticidad_equipos.id_criticidad_equipo;


--
-- Name: dispositivo_beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dispositivo_beacon (
    id_beacon integer NOT NULL,
    uuid_beacon character varying(100) NOT NULL,
    major_beacon integer NOT NULL,
    minor_beacon integer NOT NULL,
    activo_beacon boolean DEFAULT true NOT NULL,
    id_zona_beacon integer NOT NULL,
    CONSTRAINT dispositivo_beacon_major_beacon_check CHECK ((major_beacon >= 0)),
    CONSTRAINT dispositivo_beacon_minor_beacon_check CHECK ((minor_beacon >= 0))
);


ALTER TABLE public.dispositivo_beacon OWNER TO postgres;

--
-- Name: dispositivo_beacon_id_beacon_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dispositivo_beacon_id_beacon_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispositivo_beacon_id_beacon_seq OWNER TO postgres;

--
-- Name: dispositivo_beacon_id_beacon_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dispositivo_beacon_id_beacon_seq OWNED BY public.dispositivo_beacon.id_beacon;


--
-- Name: dispositivo_gps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dispositivo_gps (
    id_gps integer NOT NULL,
    codigo_gps character varying(100) NOT NULL,
    activo_gps boolean DEFAULT true NOT NULL,
    id_ambulancia integer NOT NULL
);


ALTER TABLE public.dispositivo_gps OWNER TO postgres;

--
-- Name: dispositivo_gps_id_gps_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dispositivo_gps_id_gps_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispositivo_gps_id_gps_seq OWNER TO postgres;

--
-- Name: dispositivo_gps_id_gps_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dispositivo_gps_id_gps_seq OWNED BY public.dispositivo_gps.id_gps;


--
-- Name: dispositivo_nfc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dispositivo_nfc (
    id_nfc integer NOT NULL,
    codigo_uid_nfc character varying(100) NOT NULL,
    id_equipo integer NOT NULL,
    activo_nfc boolean DEFAULT true NOT NULL
);


ALTER TABLE public.dispositivo_nfc OWNER TO postgres;

--
-- Name: dispositivo_nfc_id_nfc_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.dispositivo_nfc_id_nfc_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dispositivo_nfc_id_nfc_seq OWNER TO postgres;

--
-- Name: dispositivo_nfc_id_nfc_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.dispositivo_nfc_id_nfc_seq OWNED BY public.dispositivo_nfc.id_nfc;


--
-- Name: enfermero; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enfermero (
    id_enfermero integer NOT NULL,
    id_persona integer NOT NULL,
    id_especialidad_enfermero integer NOT NULL,
    id_turno integer NOT NULL
);


ALTER TABLE public.enfermero OWNER TO postgres;

--
-- Name: enfermero_id_enfermero_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.enfermero_id_enfermero_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enfermero_id_enfermero_seq OWNER TO postgres;

--
-- Name: enfermero_id_enfermero_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.enfermero_id_enfermero_seq OWNED BY public.enfermero.id_enfermero;


--
-- Name: equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.equipo (
    id_equipo integer NOT NULL,
    codigo_interno character varying(50) NOT NULL,
    nombre_equipo character varying(100) NOT NULL,
    id_modelo integer NOT NULL,
    numero_serie character varying(100) NOT NULL,
    id_tipo_equipo integer NOT NULL,
    id_criticidad_equipo integer NOT NULL,
    id_estado_equipo integer NOT NULL,
    id_ubicacion_administrativa_actual integer NOT NULL,
    activo_equipo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.equipo OWNER TO postgres;

--
-- Name: equipo_id_equipo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.equipo_id_equipo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.equipo_id_equipo_seq OWNER TO postgres;

--
-- Name: equipo_id_equipo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.equipo_id_equipo_seq OWNED BY public.equipo.id_equipo;


--
-- Name: especialidad_area_enfermero; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.especialidad_area_enfermero (
    id_especialidad_enfermero integer NOT NULL,
    id_area integer NOT NULL
);


ALTER TABLE public.especialidad_area_enfermero OWNER TO postgres;

--
-- Name: especialidades_enfermero; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.especialidades_enfermero (
    id_especialidad_enfermero integer NOT NULL,
    especialidad_enfermero character varying(100) NOT NULL
);


ALTER TABLE public.especialidades_enfermero OWNER TO postgres;

--
-- Name: especialidades_enfermero_id_especialidad_enfermero_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.especialidades_enfermero_id_especialidad_enfermero_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.especialidades_enfermero_id_especialidad_enfermero_seq OWNER TO postgres;

--
-- Name: especialidades_enfermero_id_especialidad_enfermero_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.especialidades_enfermero_id_especialidad_enfermero_seq OWNED BY public.especialidades_enfermero.id_especialidad_enfermero;


--
-- Name: especialidades_medico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.especialidades_medico (
    id_especialidad_medico integer NOT NULL,
    especialidad_medico character varying(100) NOT NULL
);


ALTER TABLE public.especialidades_medico OWNER TO postgres;

--
-- Name: especialidades_medico_id_especialidad_medico_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.especialidades_medico_id_especialidad_medico_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.especialidades_medico_id_especialidad_medico_seq OWNER TO postgres;

--
-- Name: especialidades_medico_id_especialidad_medico_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.especialidades_medico_id_especialidad_medico_seq OWNED BY public.especialidades_medico.id_especialidad_medico;


--
-- Name: estado_ambulancias; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado_ambulancias (
    id_estado_ambulancia integer NOT NULL,
    estado_ambulancia character varying(50) NOT NULL
);


ALTER TABLE public.estado_ambulancias OWNER TO postgres;

--
-- Name: estado_ambulancias_id_estado_ambulancia_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.estado_ambulancias_id_estado_ambulancia_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estado_ambulancias_id_estado_ambulancia_seq OWNER TO postgres;

--
-- Name: estado_ambulancias_id_estado_ambulancia_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.estado_ambulancias_id_estado_ambulancia_seq OWNED BY public.estado_ambulancias.id_estado_ambulancia;


--
-- Name: estado_asignacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado_asignacion (
    id_estado_asignacion integer NOT NULL,
    estado_asignacion character varying(50) NOT NULL
);


ALTER TABLE public.estado_asignacion OWNER TO postgres;

--
-- Name: estado_asignacion_id_estado_asignacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.estado_asignacion_id_estado_asignacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estado_asignacion_id_estado_asignacion_seq OWNER TO postgres;

--
-- Name: estado_asignacion_id_estado_asignacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.estado_asignacion_id_estado_asignacion_seq OWNED BY public.estado_asignacion.id_estado_asignacion;


--
-- Name: estado_cumplimiento_mantenimientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado_cumplimiento_mantenimientos (
    id_estado_cumplimiento integer NOT NULL,
    estado_cumplimiento character varying(50) NOT NULL
);


ALTER TABLE public.estado_cumplimiento_mantenimientos OWNER TO postgres;

--
-- Name: estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq OWNER TO postgres;

--
-- Name: estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq OWNED BY public.estado_cumplimiento_mantenimientos.id_estado_cumplimiento;


--
-- Name: estado_equipos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estado_equipos (
    id_estado_equipo integer NOT NULL,
    estado_equipo character varying(50) NOT NULL
);


ALTER TABLE public.estado_equipos OWNER TO postgres;

--
-- Name: estado_equipos_id_estado_equipo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.estado_equipos_id_estado_equipo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.estado_equipos_id_estado_equipo_seq OWNER TO postgres;

--
-- Name: estado_equipos_id_estado_equipo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.estado_equipos_id_estado_equipo_seq OWNED BY public.estado_equipos.id_estado_equipo;


--
-- Name: evento_beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.evento_beacon (
    id_evento_beacon integer NOT NULL,
    id_beacon integer NOT NULL,
    id_equipo integer NOT NULL,
    fecha_hora_evento timestamp without time zone NOT NULL,
    id_tipo_evento_beacon integer NOT NULL
);


ALTER TABLE public.evento_beacon OWNER TO postgres;

--
-- Name: evento_beacon_id_evento_beacon_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.evento_beacon_id_evento_beacon_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evento_beacon_id_evento_beacon_seq OWNER TO postgres;

--
-- Name: evento_beacon_id_evento_beacon_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.evento_beacon_id_evento_beacon_seq OWNED BY public.evento_beacon.id_evento_beacon;


--
-- Name: evento_gps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.evento_gps (
    id_evento_gps integer NOT NULL,
    id_gps integer NOT NULL,
    fecha_hora_evento timestamp without time zone NOT NULL,
    latitud numeric NOT NULL,
    longitud numeric NOT NULL,
    "precision" numeric,
    CONSTRAINT evento_gps_latitud_check CHECK (((latitud >= ('-90'::integer)::numeric) AND (latitud <= (90)::numeric))),
    CONSTRAINT evento_gps_longitud_check CHECK (((longitud >= ('-180'::integer)::numeric) AND (longitud <= (180)::numeric))),
    CONSTRAINT evento_gps_precision_check CHECK ((("precision" IS NULL) OR ("precision" >= (0)::numeric)))
);


ALTER TABLE public.evento_gps OWNER TO postgres;

--
-- Name: evento_gps_id_evento_gps_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.evento_gps_id_evento_gps_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evento_gps_id_evento_gps_seq OWNER TO postgres;

--
-- Name: evento_gps_id_evento_gps_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.evento_gps_id_evento_gps_seq OWNED BY public.evento_gps.id_evento_gps;


--
-- Name: evento_nfc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.evento_nfc (
    id_evento_nfc integer NOT NULL,
    id_nfc integer NOT NULL,
    fecha_hora_evento timestamp without time zone NOT NULL,
    id_tipo_evento_nfc integer NOT NULL
);


ALTER TABLE public.evento_nfc OWNER TO postgres;

--
-- Name: evento_nfc_id_evento_nfc_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.evento_nfc_id_evento_nfc_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evento_nfc_id_evento_nfc_seq OWNER TO postgres;

--
-- Name: evento_nfc_id_evento_nfc_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.evento_nfc_id_evento_nfc_seq OWNED BY public.evento_nfc.id_evento_nfc;


--
-- Name: mantenimiento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mantenimiento (
    id_mantenimiento integer NOT NULL,
    id_equipo integer NOT NULL,
    id_biomedico integer NOT NULL,
    fecha_hora_mantenimiento timestamp without time zone NOT NULL,
    id_programacion integer,
    id_tipo_mantenimiento integer NOT NULL,
    descripcion_mantenimiento text NOT NULL,
    id_resultado_mantenimiento integer NOT NULL,
    costo_mantenimiento numeric,
    observacion_mantenimiento text,
    CONSTRAINT mantenimiento_costo_mantenimiento_check CHECK (((costo_mantenimiento IS NULL) OR (costo_mantenimiento >= (0)::numeric)))
);


ALTER TABLE public.mantenimiento OWNER TO postgres;

--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.mantenimiento_id_mantenimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mantenimiento_id_mantenimiento_seq OWNER TO postgres;

--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.mantenimiento_id_mantenimiento_seq OWNED BY public.mantenimiento.id_mantenimiento;


--
-- Name: mantenimiento_programado; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.mantenimiento_programado (
    id_programacion integer NOT NULL,
    id_equipo integer NOT NULL,
    id_tipo_mantenimiento integer NOT NULL,
    frecuencia_dias integer NOT NULL,
    fecha_ultimo_mantenimiento timestamp without time zone,
    fecha_proximo_mantenimiento timestamp without time zone NOT NULL,
    id_prioridad_mantenimiento integer NOT NULL,
    sla_horas integer NOT NULL,
    id_estado_cumplimiento integer NOT NULL,
    observacion_programacion text,
    CONSTRAINT mantenimiento_programado_check CHECK (((fecha_ultimo_mantenimiento IS NULL) OR (fecha_proximo_mantenimiento >= fecha_ultimo_mantenimiento))),
    CONSTRAINT mantenimiento_programado_frecuencia_dias_check CHECK ((frecuencia_dias > 0)),
    CONSTRAINT mantenimiento_programado_sla_horas_check CHECK ((sla_horas > 0))
);


ALTER TABLE public.mantenimiento_programado OWNER TO postgres;

--
-- Name: mantenimiento_programado_id_programacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.mantenimiento_programado_id_programacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mantenimiento_programado_id_programacion_seq OWNER TO postgres;

--
-- Name: mantenimiento_programado_id_programacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.mantenimiento_programado_id_programacion_seq OWNED BY public.mantenimiento_programado.id_programacion;


--
-- Name: marca_equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.marca_equipo (
    id_marca integer NOT NULL,
    nombre_marca character varying(100) NOT NULL
);


ALTER TABLE public.marca_equipo OWNER TO postgres;

--
-- Name: marca_equipo_id_marca_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.marca_equipo_id_marca_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.marca_equipo_id_marca_seq OWNER TO postgres;

--
-- Name: marca_equipo_id_marca_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.marca_equipo_id_marca_seq OWNED BY public.marca_equipo.id_marca;


--
-- Name: medico; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.medico (
    id_medico integer NOT NULL,
    id_persona integer NOT NULL,
    id_especialidad_medico integer NOT NULL,
    id_turno integer NOT NULL
);


ALTER TABLE public.medico OWNER TO postgres;

--
-- Name: medico_id_medico_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.medico_id_medico_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.medico_id_medico_seq OWNER TO postgres;

--
-- Name: medico_id_medico_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.medico_id_medico_seq OWNED BY public.medico.id_medico;


--
-- Name: modelo_equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.modelo_equipo (
    id_modelo integer NOT NULL,
    nombre_modelo character varying(100) NOT NULL,
    id_marca integer NOT NULL
);


ALTER TABLE public.modelo_equipo OWNER TO postgres;

--
-- Name: modelo_equipo_id_modelo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.modelo_equipo_id_modelo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.modelo_equipo_id_modelo_seq OWNER TO postgres;

--
-- Name: modelo_equipo_id_modelo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.modelo_equipo_id_modelo_seq OWNED BY public.modelo_equipo.id_modelo;


--
-- Name: movimiento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movimiento (
    id_movimiento integer NOT NULL,
    id_equipo integer NOT NULL,
    id_persona_responsable_movimiento integer NOT NULL,
    fecha_hora_movimiento timestamp without time zone NOT NULL,
    id_tipo_movimiento integer NOT NULL,
    id_ubicacion_origen integer NOT NULL,
    id_ubicacion_destino integer NOT NULL,
    motivo_movimiento text,
    observacion_movimiento text,
    CONSTRAINT movimiento_check CHECK ((id_ubicacion_origen <> id_ubicacion_destino))
);


ALTER TABLE public.movimiento OWNER TO postgres;

--
-- Name: movimiento_id_movimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.movimiento_id_movimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.movimiento_id_movimiento_seq OWNER TO postgres;

--
-- Name: movimiento_id_movimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.movimiento_id_movimiento_seq OWNED BY public.movimiento.id_movimiento;


--
-- Name: persona; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.persona (
    id_persona integer NOT NULL,
    nombre_persona character varying(100) NOT NULL,
    apellido_persona character varying(100) NOT NULL,
    correo_persona character varying(150) NOT NULL
);


ALTER TABLE public.persona OWNER TO postgres;

--
-- Name: persona_id_persona_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.persona_id_persona_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.persona_id_persona_seq OWNER TO postgres;

--
-- Name: persona_id_persona_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.persona_id_persona_seq OWNED BY public.persona.id_persona;


--
-- Name: prioridad_mantenimientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.prioridad_mantenimientos (
    id_prioridad_mantenimiento integer NOT NULL,
    prioridad_mantenimiento character varying(50) NOT NULL
);


ALTER TABLE public.prioridad_mantenimientos OWNER TO postgres;

--
-- Name: prioridad_mantenimientos_id_prioridad_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq OWNER TO postgres;

--
-- Name: prioridad_mantenimientos_id_prioridad_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq OWNED BY public.prioridad_mantenimientos.id_prioridad_mantenimiento;


--
-- Name: responsable_area; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.responsable_area (
    id_responsable_area integer NOT NULL,
    id_enfermero integer NOT NULL,
    id_area integer NOT NULL,
    fecha_inicio_responsable_area timestamp without time zone NOT NULL,
    fecha_fin_responsable_area timestamp without time zone,
    CONSTRAINT responsable_area_check CHECK (((fecha_fin_responsable_area IS NULL) OR (fecha_fin_responsable_area >= fecha_inicio_responsable_area)))
);


ALTER TABLE public.responsable_area OWNER TO postgres;

--
-- Name: responsable_area_id_responsable_area_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.responsable_area_id_responsable_area_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.responsable_area_id_responsable_area_seq OWNER TO postgres;

--
-- Name: responsable_area_id_responsable_area_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.responsable_area_id_responsable_area_seq OWNED BY public.responsable_area.id_responsable_area;


--
-- Name: roles_usuario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles_usuario (
    id_rol_usuario integer NOT NULL,
    rol_usuario character varying(50) NOT NULL
);


ALTER TABLE public.roles_usuario OWNER TO postgres;

--
-- Name: roles_usuario_id_rol_usuario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_usuario_id_rol_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_usuario_id_rol_usuario_seq OWNER TO postgres;

--
-- Name: roles_usuario_id_rol_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_usuario_id_rol_usuario_seq OWNED BY public.roles_usuario.id_rol_usuario;


--
-- Name: tipo_equipos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_equipos (
    id_tipo_equipo integer NOT NULL,
    tipo_equipo character varying(100) NOT NULL,
    id_categoria_equipo integer NOT NULL
);


ALTER TABLE public.tipo_equipos OWNER TO postgres;

--
-- Name: tipo_equipos_id_tipo_equipo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_equipos_id_tipo_equipo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_equipos_id_tipo_equipo_seq OWNER TO postgres;

--
-- Name: tipo_equipos_id_tipo_equipo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_equipos_id_tipo_equipo_seq OWNED BY public.tipo_equipos.id_tipo_equipo;


--
-- Name: tipo_eventos_beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_eventos_beacon (
    id_tipo_evento_beacon integer NOT NULL,
    tipo_evento_beacon character varying(100) NOT NULL
);


ALTER TABLE public.tipo_eventos_beacon OWNER TO postgres;

--
-- Name: tipo_eventos_beacon_id_tipo_evento_beacon_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_eventos_beacon_id_tipo_evento_beacon_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_eventos_beacon_id_tipo_evento_beacon_seq OWNER TO postgres;

--
-- Name: tipo_eventos_beacon_id_tipo_evento_beacon_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_eventos_beacon_id_tipo_evento_beacon_seq OWNED BY public.tipo_eventos_beacon.id_tipo_evento_beacon;


--
-- Name: tipo_eventos_nfc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_eventos_nfc (
    id_tipo_evento_nfc integer NOT NULL,
    tipo_evento_nfc character varying(100) NOT NULL
);


ALTER TABLE public.tipo_eventos_nfc OWNER TO postgres;

--
-- Name: tipo_eventos_nfc_id_tipo_evento_nfc_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_eventos_nfc_id_tipo_evento_nfc_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_eventos_nfc_id_tipo_evento_nfc_seq OWNER TO postgres;

--
-- Name: tipo_eventos_nfc_id_tipo_evento_nfc_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_eventos_nfc_id_tipo_evento_nfc_seq OWNED BY public.tipo_eventos_nfc.id_tipo_evento_nfc;


--
-- Name: tipo_mantenimientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_mantenimientos (
    id_tipo_mantenimiento integer NOT NULL,
    tipo_mantenimiento character varying(100) NOT NULL
);


ALTER TABLE public.tipo_mantenimientos OWNER TO postgres;

--
-- Name: tipo_mantenimientos_id_tipo_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_mantenimientos_id_tipo_mantenimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_mantenimientos_id_tipo_mantenimiento_seq OWNER TO postgres;

--
-- Name: tipo_mantenimientos_id_tipo_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_mantenimientos_id_tipo_mantenimiento_seq OWNED BY public.tipo_mantenimientos.id_tipo_mantenimiento;


--
-- Name: tipo_movimientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_movimientos (
    id_tipo_movimiento integer NOT NULL,
    tipo_movimiento character varying(100) NOT NULL
);


ALTER TABLE public.tipo_movimientos OWNER TO postgres;

--
-- Name: tipo_movimientos_id_tipo_movimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_movimientos_id_tipo_movimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_movimientos_id_tipo_movimiento_seq OWNER TO postgres;

--
-- Name: tipo_movimientos_id_tipo_movimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_movimientos_id_tipo_movimiento_seq OWNED BY public.tipo_movimientos.id_tipo_movimiento;


--
-- Name: tipo_procedimiento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_procedimiento (
    id_tipo_procedimiento integer NOT NULL,
    tipo_procedimiento character varying(100) NOT NULL
);


ALTER TABLE public.tipo_procedimiento OWNER TO postgres;

--
-- Name: tipo_procedimiento_id_tipo_procedimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_procedimiento_id_tipo_procedimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_procedimiento_id_tipo_procedimiento_seq OWNER TO postgres;

--
-- Name: tipo_procedimiento_id_tipo_procedimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_procedimiento_id_tipo_procedimiento_seq OWNED BY public.tipo_procedimiento.id_tipo_procedimiento;


--
-- Name: tipo_resultado_mantenimientos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_resultado_mantenimientos (
    id_resultado_mantenimiento integer NOT NULL,
    resultado_mantenimiento character varying(100) NOT NULL
);


ALTER TABLE public.tipo_resultado_mantenimientos OWNER TO postgres;

--
-- Name: tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq OWNER TO postgres;

--
-- Name: tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq OWNED BY public.tipo_resultado_mantenimientos.id_resultado_mantenimiento;


--
-- Name: tipo_traslado_externo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_traslado_externo (
    id_tipo_traslado integer NOT NULL,
    tipo_traslado character varying(50) NOT NULL
);


ALTER TABLE public.tipo_traslado_externo OWNER TO postgres;

--
-- Name: tipo_traslado_externo_id_tipo_traslado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tipo_traslado_externo_id_tipo_traslado_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tipo_traslado_externo_id_tipo_traslado_seq OWNER TO postgres;

--
-- Name: tipo_traslado_externo_id_tipo_traslado_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tipo_traslado_externo_id_tipo_traslado_seq OWNED BY public.tipo_traslado_externo.id_tipo_traslado;


--
-- Name: traslado_externo_equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.traslado_externo_equipo (
    id_traslado_externo integer NOT NULL,
    id_equipo integer NOT NULL,
    id_nfc_equipo integer NOT NULL,
    id_ambulancia integer NOT NULL,
    id_persona_conductor integer NOT NULL,
    fecha_salida timestamp without time zone NOT NULL,
    fecha_llegada timestamp without time zone,
    id_tipo_traslado integer NOT NULL,
    motivo_traslado text,
    observacion_traslado text,
    CONSTRAINT traslado_externo_equipo_check CHECK (((fecha_llegada IS NULL) OR (fecha_llegada >= fecha_salida)))
);


ALTER TABLE public.traslado_externo_equipo OWNER TO postgres;

--
-- Name: traslado_externo_equipo_id_traslado_externo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.traslado_externo_equipo_id_traslado_externo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.traslado_externo_equipo_id_traslado_externo_seq OWNER TO postgres;

--
-- Name: traslado_externo_equipo_id_traslado_externo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.traslado_externo_equipo_id_traslado_externo_seq OWNED BY public.traslado_externo_equipo.id_traslado_externo;


--
-- Name: turnos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.turnos (
    id_turno integer NOT NULL,
    nombre_turno character varying(50) NOT NULL,
    hora_inicio time without time zone NOT NULL,
    hora_fin time without time zone NOT NULL
);


ALTER TABLE public.turnos OWNER TO postgres;

--
-- Name: turnos_id_turno_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.turnos_id_turno_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.turnos_id_turno_seq OWNER TO postgres;

--
-- Name: turnos_id_turno_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.turnos_id_turno_seq OWNED BY public.turnos.id_turno;


--
-- Name: ubicacion_especifica; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.ubicacion_especifica (
    id_ubicacion integer NOT NULL,
    nombre_ubicacion character varying(100) NOT NULL,
    id_area integer NOT NULL
);


ALTER TABLE public.ubicacion_especifica OWNER TO postgres;

--
-- Name: ubicacion_especifica_id_ubicacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.ubicacion_especifica_id_ubicacion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ubicacion_especifica_id_ubicacion_seq OWNER TO postgres;

--
-- Name: ubicacion_especifica_id_ubicacion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.ubicacion_especifica_id_ubicacion_seq OWNED BY public.ubicacion_especifica.id_ubicacion;


--
-- Name: uso_clinico_equipo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.uso_clinico_equipo (
    id_uso_clinico integer NOT NULL,
    id_equipo integer NOT NULL,
    id_persona_responsable_uso integer NOT NULL,
    fecha_hora_inicio timestamp without time zone NOT NULL,
    fecha_hora_fin timestamp without time zone,
    id_area integer NOT NULL,
    id_turno integer NOT NULL,
    id_tipo_procedimiento integer NOT NULL,
    motivo_uso text,
    CONSTRAINT uso_clinico_equipo_check CHECK (((fecha_hora_fin IS NULL) OR (fecha_hora_fin >= fecha_hora_inicio)))
);


ALTER TABLE public.uso_clinico_equipo OWNER TO postgres;

--
-- Name: uso_clinico_equipo_id_uso_clinico_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.uso_clinico_equipo_id_uso_clinico_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.uso_clinico_equipo_id_uso_clinico_seq OWNER TO postgres;

--
-- Name: uso_clinico_equipo_id_uso_clinico_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.uso_clinico_equipo_id_uso_clinico_seq OWNED BY public.uso_clinico_equipo.id_uso_clinico;


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    username character varying(50) NOT NULL,
    contrasenia text NOT NULL,
    activo_usuario boolean DEFAULT true NOT NULL,
    id_persona integer NOT NULL
);


ALTER TABLE public.usuario OWNER TO postgres;

--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuario_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuario_id_usuario_seq OWNER TO postgres;

--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuario_id_usuario_seq OWNED BY public.usuario.id_usuario;


--
-- Name: usuario_rol; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuario_rol (
    id_usuario integer NOT NULL,
    id_rol_usuario integer NOT NULL
);


ALTER TABLE public.usuario_rol OWNER TO postgres;

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
-- Name: zona_beacon; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.zona_beacon (
    id_zona_beacon integer NOT NULL,
    nombre_zona_beacon character varying(100) NOT NULL,
    id_ubicacion integer NOT NULL
);


ALTER TABLE public.zona_beacon OWNER TO postgres;

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

--
-- Name: zona_beacon_id_zona_beacon_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.zona_beacon_id_zona_beacon_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.zona_beacon_id_zona_beacon_seq OWNER TO postgres;

--
-- Name: zona_beacon_id_zona_beacon_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.zona_beacon_id_zona_beacon_seq OWNED BY public.zona_beacon.id_zona_beacon;


--
-- Name: ambulancia id_ambulancia; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ambulancia ALTER COLUMN id_ambulancia SET DEFAULT nextval('public.ambulancia_id_ambulancia_seq'::regclass);


--
-- Name: area_registro id_area; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.area_registro ALTER COLUMN id_area SET DEFAULT nextval('public.area_registro_id_area_seq'::regclass);


--
-- Name: asignacion_equipo id_asignacion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo ALTER COLUMN id_asignacion SET DEFAULT nextval('public.asignacion_equipo_id_asignacion_seq'::regclass);


--
-- Name: auditoria id_auditoria; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria ALTER COLUMN id_auditoria SET DEFAULT nextval('public.auditoria_id_auditoria_seq'::regclass);


--
-- Name: biomedico id_biomedico; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.biomedico ALTER COLUMN id_biomedico SET DEFAULT nextval('public.biomedico_id_biomedico_seq'::regclass);


--
-- Name: categoria_equipos id_categoria_equipo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_equipos ALTER COLUMN id_categoria_equipo SET DEFAULT nextval('public.categoria_equipos_id_categoria_equipo_seq'::regclass);


--
-- Name: criticidad_equipos id_criticidad_equipo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.criticidad_equipos ALTER COLUMN id_criticidad_equipo SET DEFAULT nextval('public.criticidad_equipos_id_criticidad_equipo_seq'::regclass);


--
-- Name: dispositivo_beacon id_beacon; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_beacon ALTER COLUMN id_beacon SET DEFAULT nextval('public.dispositivo_beacon_id_beacon_seq'::regclass);


--
-- Name: dispositivo_gps id_gps; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_gps ALTER COLUMN id_gps SET DEFAULT nextval('public.dispositivo_gps_id_gps_seq'::regclass);


--
-- Name: dispositivo_nfc id_nfc; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_nfc ALTER COLUMN id_nfc SET DEFAULT nextval('public.dispositivo_nfc_id_nfc_seq'::regclass);


--
-- Name: enfermero id_enfermero; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero ALTER COLUMN id_enfermero SET DEFAULT nextval('public.enfermero_id_enfermero_seq'::regclass);


--
-- Name: equipo id_equipo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo ALTER COLUMN id_equipo SET DEFAULT nextval('public.equipo_id_equipo_seq'::regclass);


--
-- Name: especialidades_enfermero id_especialidad_enfermero; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_enfermero ALTER COLUMN id_especialidad_enfermero SET DEFAULT nextval('public.especialidades_enfermero_id_especialidad_enfermero_seq'::regclass);


--
-- Name: especialidades_medico id_especialidad_medico; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_medico ALTER COLUMN id_especialidad_medico SET DEFAULT nextval('public.especialidades_medico_id_especialidad_medico_seq'::regclass);


--
-- Name: estado_ambulancias id_estado_ambulancia; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_ambulancias ALTER COLUMN id_estado_ambulancia SET DEFAULT nextval('public.estado_ambulancias_id_estado_ambulancia_seq'::regclass);


--
-- Name: estado_asignacion id_estado_asignacion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_asignacion ALTER COLUMN id_estado_asignacion SET DEFAULT nextval('public.estado_asignacion_id_estado_asignacion_seq'::regclass);


--
-- Name: estado_cumplimiento_mantenimientos id_estado_cumplimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_cumplimiento_mantenimientos ALTER COLUMN id_estado_cumplimiento SET DEFAULT nextval('public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq'::regclass);


--
-- Name: estado_equipos id_estado_equipo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_equipos ALTER COLUMN id_estado_equipo SET DEFAULT nextval('public.estado_equipos_id_estado_equipo_seq'::regclass);


--
-- Name: evento_beacon id_evento_beacon; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_beacon ALTER COLUMN id_evento_beacon SET DEFAULT nextval('public.evento_beacon_id_evento_beacon_seq'::regclass);


--
-- Name: evento_gps id_evento_gps; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_gps ALTER COLUMN id_evento_gps SET DEFAULT nextval('public.evento_gps_id_evento_gps_seq'::regclass);


--
-- Name: evento_nfc id_evento_nfc; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_nfc ALTER COLUMN id_evento_nfc SET DEFAULT nextval('public.evento_nfc_id_evento_nfc_seq'::regclass);


--
-- Name: mantenimiento id_mantenimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento ALTER COLUMN id_mantenimiento SET DEFAULT nextval('public.mantenimiento_id_mantenimiento_seq'::regclass);


--
-- Name: mantenimiento_programado id_programacion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado ALTER COLUMN id_programacion SET DEFAULT nextval('public.mantenimiento_programado_id_programacion_seq'::regclass);


--
-- Name: marca_equipo id_marca; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.marca_equipo ALTER COLUMN id_marca SET DEFAULT nextval('public.marca_equipo_id_marca_seq'::regclass);


--
-- Name: medico id_medico; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico ALTER COLUMN id_medico SET DEFAULT nextval('public.medico_id_medico_seq'::regclass);


--
-- Name: modelo_equipo id_modelo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelo_equipo ALTER COLUMN id_modelo SET DEFAULT nextval('public.modelo_equipo_id_modelo_seq'::regclass);


--
-- Name: movimiento id_movimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento ALTER COLUMN id_movimiento SET DEFAULT nextval('public.movimiento_id_movimiento_seq'::regclass);


--
-- Name: persona id_persona; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.persona ALTER COLUMN id_persona SET DEFAULT nextval('public.persona_id_persona_seq'::regclass);


--
-- Name: prioridad_mantenimientos id_prioridad_mantenimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prioridad_mantenimientos ALTER COLUMN id_prioridad_mantenimiento SET DEFAULT nextval('public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq'::regclass);


--
-- Name: responsable_area id_responsable_area; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.responsable_area ALTER COLUMN id_responsable_area SET DEFAULT nextval('public.responsable_area_id_responsable_area_seq'::regclass);


--
-- Name: roles_usuario id_rol_usuario; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles_usuario ALTER COLUMN id_rol_usuario SET DEFAULT nextval('public.roles_usuario_id_rol_usuario_seq'::regclass);


--
-- Name: tipo_equipos id_tipo_equipo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_equipos ALTER COLUMN id_tipo_equipo SET DEFAULT nextval('public.tipo_equipos_id_tipo_equipo_seq'::regclass);


--
-- Name: tipo_eventos_beacon id_tipo_evento_beacon; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_beacon ALTER COLUMN id_tipo_evento_beacon SET DEFAULT nextval('public.tipo_eventos_beacon_id_tipo_evento_beacon_seq'::regclass);


--
-- Name: tipo_eventos_nfc id_tipo_evento_nfc; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_nfc ALTER COLUMN id_tipo_evento_nfc SET DEFAULT nextval('public.tipo_eventos_nfc_id_tipo_evento_nfc_seq'::regclass);


--
-- Name: tipo_mantenimientos id_tipo_mantenimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_mantenimientos ALTER COLUMN id_tipo_mantenimiento SET DEFAULT nextval('public.tipo_mantenimientos_id_tipo_mantenimiento_seq'::regclass);


--
-- Name: tipo_movimientos id_tipo_movimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_movimientos ALTER COLUMN id_tipo_movimiento SET DEFAULT nextval('public.tipo_movimientos_id_tipo_movimiento_seq'::regclass);


--
-- Name: tipo_procedimiento id_tipo_procedimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_procedimiento ALTER COLUMN id_tipo_procedimiento SET DEFAULT nextval('public.tipo_procedimiento_id_tipo_procedimiento_seq'::regclass);


--
-- Name: tipo_resultado_mantenimientos id_resultado_mantenimiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_resultado_mantenimientos ALTER COLUMN id_resultado_mantenimiento SET DEFAULT nextval('public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq'::regclass);


--
-- Name: tipo_traslado_externo id_tipo_traslado; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_traslado_externo ALTER COLUMN id_tipo_traslado SET DEFAULT nextval('public.tipo_traslado_externo_id_tipo_traslado_seq'::regclass);


--
-- Name: traslado_externo_equipo id_traslado_externo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo ALTER COLUMN id_traslado_externo SET DEFAULT nextval('public.traslado_externo_equipo_id_traslado_externo_seq'::regclass);


--
-- Name: turnos id_turno; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.turnos ALTER COLUMN id_turno SET DEFAULT nextval('public.turnos_id_turno_seq'::regclass);


--
-- Name: ubicacion_especifica id_ubicacion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ubicacion_especifica ALTER COLUMN id_ubicacion SET DEFAULT nextval('public.ubicacion_especifica_id_ubicacion_seq'::regclass);


--
-- Name: uso_clinico_equipo id_uso_clinico; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo ALTER COLUMN id_uso_clinico SET DEFAULT nextval('public.uso_clinico_equipo_id_uso_clinico_seq'::regclass);


--
-- Name: usuario id_usuario; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_id_usuario_seq'::regclass);


--
-- Name: zona_beacon id_zona_beacon; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona_beacon ALTER COLUMN id_zona_beacon SET DEFAULT nextval('public.zona_beacon_id_zona_beacon_seq'::regclass);


--
-- Data for Name: ambulancia; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ambulancia (id_ambulancia, codigo_ambulancia, placa, id_estado_ambulancia, activo_ambulancia) FROM stdin;
1	AMB-001	NLE-123-A	1	t
2	AMB-002	NLE-456-B	1	t
\.


--
-- Data for Name: area_registro; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.area_registro (id_area, nombre_area) FROM stdin;
1	Urgencias
2	UCI
3	Quirófano
4	Hospitalización
5	Almacén Biomédico
6	Neonatal
\.


--
-- Data for Name: asignacion_equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.asignacion_equipo (id_asignacion, id_equipo, id_persona_responsable, id_ubicacion, fecha_inicio_asignacion, fecha_fin_asignacion, id_estado_asignacion, observacion_asignacion) FROM stdin;
1	1	3	1	2025-01-01 07:00:00	\N	1	Asignacion inicial monitor urgencias
2	2	4	3	2025-01-01 07:00:00	\N	1	Asignacion inicial ventilador UCI
3	3	3	1	2025-01-01 07:00:00	\N	1	Asignacion inicial bomba urgencias
4	4	4	3	2025-01-01 07:00:00	\N	1	Asignacion inicial desfibrilador UCI
5	5	6	3	2025-01-01 15:00:00	\N	1	Asignacion inicial ECG UCI
12	6	3	2	2026-01-15 07:00:00	\N	1	Asignacion monitor pasillo urgencias
13	7	6	3	2026-01-15 15:00:00	\N	1	Asignacion bomba UCI
14	8	4	5	2026-02-01 07:00:00	\N	1	Asignacion ventilador bodega biomedica
15	9	4	5	2026-02-01 07:00:00	\N	1	Asignacion ECG bodega biomedica
16	10	6	4	2026-01-20 15:00:00	\N	1	Asignacion desfibrilador hospitalizacion
17	20	7	1	2026-05-15 16:24:57.15063	\N	1	Para la paciente Teresa
\.


--
-- Data for Name: auditoria; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.auditoria (id_auditoria, id_usuario, fecha_hora_auditoria, accion_auditoria, tabla_afectada, id_registro_afectado, valor_antes, valor_despues, origen_cambio) FROM stdin;
68	1	2026-04-18 18:17:34.189839	UPDATE	equipo	1	{"id_equipo": 1, "id_modelo": 1, "numero_serie": "SN-PH-2024-001", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX450", "codigo_interno": "EQ-001", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 1, "id_modelo": 1, "numero_serie": "SN-PH-2024-001", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX450", "codigo_interno": "EQ-001", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	escenario_1
69	1	2026-04-18 18:17:34.189839	INSERT	movimiento	8	\N	{"id_equipo": 1, "id_movimiento": 8, "motivo_movimiento": "Contingencia - paciente critico requiere monitoreo en UCI", "id_tipo_movimiento": 1, "id_ubicacion_origen": 1, "id_ubicacion_destino": 3, "fecha_hora_movimiento": "2026-04-18T18:17:34.189839", "observacion_movimiento": "Traslado autorizado por jefe de turno matutino", "id_persona_responsable_movimiento": 3}	escenario_1
70	1	2026-04-18 18:19:26.698235	UPDATE	responsable_area	1	{"id_area": 1, "id_enfermero": 1, "id_responsable_area": 1, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2025-01-01T07:00:00"}	{"id_area": 1, "id_enfermero": 1, "id_responsable_area": 1, "fecha_fin_responsable_area": "2026-04-18T18:19:26.698235", "fecha_inicio_responsable_area": "2025-01-01T07:00:00"}	escenario_3
71	1	2026-04-18 18:19:26.698235	INSERT	responsable_area	3	\N	{"id_area": 1, "id_enfermero": 3, "id_responsable_area": 3, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2026-04-18T18:19:26.698235"}	escenario_3
72	1	2026-04-18 18:21:32.836435	UPDATE	equipo	2	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	escenario_2
73	1	2026-04-18 18:21:32.836435	INSERT	mantenimiento	5	\N	{"id_equipo": 2, "id_biomedico": 1, "id_programacion": null, "id_mantenimiento": 5, "costo_mantenimiento": 3800.00, "id_tipo_mantenimiento": 2, "fecha_hora_mantenimiento": "2026-04-18T18:21:32.836435", "descripcion_mantenimiento": "Falla detectada en sensor de flujo y alarma de presion", "observacion_mantenimiento": "Requiere refaccion importada, tiempo estimado 5 dias", "id_resultado_mantenimiento": 3}	escenario_2
74	1	2026-04-18 18:23:30.838545	UPDATE	equipo	3	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	escenario_4
75	1	2026-04-18 18:23:30.838545	INSERT	movimiento	9	\N	{"id_equipo": 3, "id_movimiento": 9, "motivo_movimiento": "Correccion de ubicacion por discrepancia detectada con evidencia Beacon", "id_tipo_movimiento": 2, "id_ubicacion_origen": 1, "id_ubicacion_destino": 3, "fecha_hora_movimiento": "2026-04-18T18:23:30.838545", "observacion_movimiento": "Beacon confirmo equipo en UCI - se actualiza registro administrativo", "id_persona_responsable_movimiento": 3}	escenario_4
76	1	2026-04-18 18:54:17.778826	INSERT	equipo	6	\N	{"id_equipo": 6, "id_modelo": 1, "numero_serie": "SN-PH-2026-006", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX450 B", "codigo_interno": "EQ-006", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 2}	directo_bd
77	1	2026-04-18 18:54:17.778826	INSERT	equipo	7	\N	{"id_equipo": 7, "id_modelo": 2, "numero_serie": "SN-BX-2026-007", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma B", "codigo_interno": "EQ-007", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	directo_bd
78	1	2026-04-18 18:54:17.778826	INSERT	equipo	8	\N	{"id_equipo": 8, "id_modelo": 4, "numero_serie": "SN-DR-2026-008", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita B", "codigo_interno": "EQ-008", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	directo_bd
79	1	2026-04-18 18:54:17.778826	INSERT	equipo	9	\N	{"id_equipo": 9, "id_modelo": 3, "numero_serie": "SN-GE-2026-009", "activo_equipo": true, "nombre_equipo": "ECG GE CARESCAPE B", "codigo_interno": "EQ-009", "id_tipo_equipo": 5, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 5}	directo_bd
80	1	2026-04-18 18:54:17.778826	INSERT	equipo	10	\N	{"id_equipo": 10, "id_modelo": 5, "numero_serie": "SN-MY-2026-010", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3 B", "codigo_interno": "EQ-010", "id_tipo_equipo": 3, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 4}	directo_bd
83	1	2026-04-18 18:56:13.865309	INSERT	asignacion_equipo	14	\N	{"id_equipo": 8, "id_ubicacion": 5, "id_asignacion": 14, "fecha_fin_asignacion": null, "id_estado_asignacion": 1, "id_persona_responsable": 4, "observacion_asignacion": "Asignacion ventilador bodega biomedica", "fecha_inicio_asignacion": "2026-02-01T07:00:00"}	directo_bd
84	1	2026-04-18 18:56:13.865309	INSERT	asignacion_equipo	15	\N	{"id_equipo": 9, "id_ubicacion": 5, "id_asignacion": 15, "fecha_fin_asignacion": null, "id_estado_asignacion": 1, "id_persona_responsable": 4, "observacion_asignacion": "Asignacion ECG bodega biomedica", "fecha_inicio_asignacion": "2026-02-01T07:00:00"}	directo_bd
85	1	2026-04-18 18:56:13.865309	INSERT	asignacion_equipo	16	\N	{"id_equipo": 10, "id_ubicacion": 4, "id_asignacion": 16, "fecha_fin_asignacion": null, "id_estado_asignacion": 1, "id_persona_responsable": 6, "observacion_asignacion": "Asignacion desfibrilador hospitalizacion", "fecha_inicio_asignacion": "2026-01-20T15:00:00"}	directo_bd
103	1	2026-04-18 19:07:21.846831	INSERT	responsable_area	6	\N	{"id_area": 4, "id_enfermero": 5, "id_responsable_area": 6, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2026-01-01T15:00:00"}	directo_bd
104	1	2026-04-18 19:07:21.846831	INSERT	responsable_area	7	\N	{"id_area": 6, "id_enfermero": 6, "id_responsable_area": 7, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2026-01-01T23:00:00"}	directo_bd
86	1	2026-04-18 18:56:42.43122	UPDATE	equipo	1	{"id_equipo": 1, "id_modelo": 1, "numero_serie": "SN-PH-2024-001", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX450", "codigo_interno": "EQ-001", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 1, "id_modelo": 1, "numero_serie": "SN-PH-2024-001", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX450", "codigo_interno": "EQ-001", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	directo_bd
87	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	6	\N	{"id_equipo": 1, "id_biomedico": 1, "id_programacion": 1, "id_mantenimiento": 6, "costo_mantenimiento": 800.00, "id_tipo_mantenimiento": 1, "fecha_hora_mantenimiento": "2026-01-10T08:00:00", "descripcion_mantenimiento": "Revision general y limpieza de sensores", "observacion_mantenimiento": "Sin anomalias detectadas", "id_resultado_mantenimiento": 1}	directo_bd
88	1	2026-04-18 18:56:42.43122	UPDATE	equipo	2	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	directo_bd
89	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	7	\N	{"id_equipo": 2, "id_biomedico": 1, "id_programacion": 2, "id_mantenimiento": 7, "costo_mantenimiento": 1200.00, "id_tipo_mantenimiento": 1, "fecha_hora_mantenimiento": "2026-01-15T08:00:00", "descripcion_mantenimiento": "Calibracion de alarmas y revision de circuitos", "observacion_mantenimiento": "Funcionamiento optimo", "id_resultado_mantenimiento": 1}	directo_bd
90	1	2026-04-18 18:56:42.43122	UPDATE	equipo	3	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	directo_bd
91	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	8	\N	{"id_equipo": 3, "id_biomedico": 1, "id_programacion": 3, "id_mantenimiento": 8, "costo_mantenimiento": 600.00, "id_tipo_mantenimiento": 3, "fecha_hora_mantenimiento": "2026-02-01T08:00:00", "descripcion_mantenimiento": "Calibracion anual de flujo y presion", "observacion_mantenimiento": "Dentro de parametros normales", "id_resultado_mantenimiento": 1}	directo_bd
92	1	2026-04-18 18:56:42.43122	UPDATE	equipo	5	{"id_equipo": 5, "id_modelo": 3, "numero_serie": "SN-GE-2024-005", "activo_equipo": true, "nombre_equipo": "ECG GE CARESCAPE B450", "codigo_interno": "EQ-005", "id_tipo_equipo": 5, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 5, "id_modelo": 3, "numero_serie": "SN-GE-2024-005", "activo_equipo": true, "nombre_equipo": "ECG GE CARESCAPE B450", "codigo_interno": "EQ-005", "id_tipo_equipo": 5, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 3}	directo_bd
93	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	9	\N	{"id_equipo": 5, "id_biomedico": 1, "id_programacion": 5, "id_mantenimiento": 9, "costo_mantenimiento": 400.00, "id_tipo_mantenimiento": 4, "fecha_hora_mantenimiento": "2026-02-10T08:00:00", "descripcion_mantenimiento": "Inspeccion semestral de electrodos y cables", "observacion_mantenimiento": "Sin desgaste significativo", "id_resultado_mantenimiento": 1}	directo_bd
94	1	2026-04-18 18:56:42.43122	UPDATE	equipo	8	{"id_equipo": 8, "id_modelo": 4, "numero_serie": "SN-DR-2026-008", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita B", "codigo_interno": "EQ-008", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 8, "id_modelo": 4, "numero_serie": "SN-DR-2026-008", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita B", "codigo_interno": "EQ-008", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	directo_bd
95	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	10	\N	{"id_equipo": 8, "id_biomedico": 1, "id_programacion": null, "id_mantenimiento": 10, "costo_mantenimiento": 2800.00, "id_tipo_mantenimiento": 2, "fecha_hora_mantenimiento": "2026-03-15T08:00:00", "descripcion_mantenimiento": "Falla en valvula de exhalacion", "observacion_mantenimiento": "En espera de refaccion", "id_resultado_mantenimiento": 3}	directo_bd
96	1	2026-04-18 18:56:42.43122	UPDATE	equipo	10	{"id_equipo": 10, "id_modelo": 5, "numero_serie": "SN-MY-2026-010", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3 B", "codigo_interno": "EQ-010", "id_tipo_equipo": 3, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 4}	{"id_equipo": 10, "id_modelo": 5, "numero_serie": "SN-MY-2026-010", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3 B", "codigo_interno": "EQ-010", "id_tipo_equipo": 3, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 4}	directo_bd
97	1	2026-04-18 18:56:42.43122	INSERT	mantenimiento	11	\N	{"id_equipo": 10, "id_biomedico": 1, "id_programacion": null, "id_mantenimiento": 11, "costo_mantenimiento": 500.00, "id_tipo_mantenimiento": 1, "fecha_hora_mantenimiento": "2026-03-20T08:00:00", "descripcion_mantenimiento": "Revision de bateria y prueba de descarga", "observacion_mantenimiento": "Bateria al 95% de capacidad", "id_resultado_mantenimiento": 1}	directo_bd
98	1	2026-04-18 18:59:05.009327	DELETE_LOGICO	equipo	4	{"id_equipo": 4, "id_modelo": 5, "numero_serie": "SN-MY-2024-004", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3", "codigo_interno": "EQ-004", "id_tipo_equipo": 3, "id_estado_equipo": 4, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 4, "id_modelo": 5, "numero_serie": "SN-MY-2024-004", "activo_equipo": false, "nombre_equipo": "Desfibrilador Mindray D3", "codigo_interno": "EQ-004", "id_tipo_equipo": 3, "id_estado_equipo": 5, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	seeds_adicionales
99	1	2026-04-18 19:06:49.678861	INSERT	usuario	9	\N	{"username": "cvega", "id_persona": 9, "id_usuario": 9, "contrasenia": "hashed_vega123", "activo_usuario": true}	directo_bd
100	1	2026-04-18 19:06:49.678861	INSERT	usuario	10	\N	{"username": "pmorales", "id_persona": 10, "id_usuario": 10, "contrasenia": "hashed_morales123", "activo_usuario": true}	directo_bd
101	1	2026-04-18 19:06:49.678861	INSERT	usuario	11	\N	{"username": "dcastillo", "id_persona": 11, "id_usuario": 11, "contrasenia": "hashed_castillo123", "activo_usuario": true}	directo_bd
102	1	2026-04-18 19:07:21.846831	INSERT	responsable_area	5	\N	{"id_area": 3, "id_enfermero": 4, "id_responsable_area": 5, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2026-01-01T07:00:00"}	directo_bd
105	1	2026-05-15 02:16:35.980287	INSERT	equipo	11	\N	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	sistema
106	1	2026-05-15 02:39:55.33018	UPDATE	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 3, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
107	1	2026-05-15 02:41:07.293632	UPDATE	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 3, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 2, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
108	1	2026-05-15 19:59:35.757237	UPDATE	equipo	8	{"id_equipo": 8, "id_modelo": 4, "numero_serie": "SN-DR-2026-008", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita B", "codigo_interno": "EQ-008", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 8, "id_modelo": 4, "numero_serie": "SN-DR-2026-008", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita B", "codigo_interno": "EQ-008", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	web_admin
109	4	2026-05-15 14:17:00.925006	UPDATE	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 2, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 4, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	sistema
111	4	2026-05-15 14:50:51.587917	UPDATE	equipo	2	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	sistema
112	4	2026-05-15 14:50:51.587917	INSERT	mantenimiento	14	\N	{"id_equipo": 2, "id_biomedico": 1, "id_programacion": null, "id_mantenimiento": 14, "costo_mantenimiento": null, "id_tipo_mantenimiento": 3, "fecha_hora_mantenimiento": "2026-05-15T14:50:51.587917", "descripcion_mantenimiento": "Fallo complejo", "observacion_mantenimiento": null, "id_resultado_mantenimiento": 3}	sistema
113	1	2026-05-15 15:22:03.884248	DELETE_LOGICO	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 4, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": false, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 4, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
114	1	2026-05-15 15:46:26.253706	ACTIVACION	equipo	4	{"id_equipo": 4, "id_modelo": 5, "numero_serie": "SN-MY-2024-004", "activo_equipo": false, "nombre_equipo": "Desfibrilador Mindray D3", "codigo_interno": "EQ-004", "id_tipo_equipo": 3, "id_estado_equipo": 5, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 4, "id_modelo": 5, "numero_serie": "SN-MY-2024-004", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3", "codigo_interno": "EQ-004", "id_tipo_equipo": 3, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	web_admin
115	1	2026-05-15 15:46:28.697897	ACTIVACION	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": false, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 4, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
116	1	2026-05-15 15:48:51.11049	DELETE_LOGICO	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": true, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": false, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
117	1	2026-05-15 15:59:23.864399	UPDATE	equipo	10	{"id_equipo": 10, "id_modelo": 5, "numero_serie": "SN-MY-2026-010", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3 B", "codigo_interno": "EQ-010", "id_tipo_equipo": 3, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 4}	{"id_equipo": 10, "id_modelo": 5, "numero_serie": "SN-MY-2026-010", "activo_equipo": true, "nombre_equipo": "Desfibrilador Mindray D3 B", "codigo_interno": "EQ-010", "id_tipo_equipo": 3, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 4}	web_admin
118	1	2026-05-15 16:10:57.986132	INSERT	equipo	15	\N	{"id_equipo": 15, "id_modelo": 1, "numero_serie": null, "activo_equipo": true, "nombre_equipo": "Equipo de prueba", "codigo_interno": "EQ-500", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	web_admin
119	1	2026-05-15 16:21:28.12586	INSERT	equipo	18	\N	{"id_equipo": 18, "id_modelo": 1, "numero_serie": "SN-PRUEBA-999", "activo_equipo": true, "nombre_equipo": "Prueba libre", "codigo_interno": "EQ-999", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	web_admin
120	1	2026-05-15 16:22:49.156412	INSERT	equipo	19	\N	{"id_equipo": 19, "id_modelo": 1, "numero_serie": "SN-2026-1234", "activo_equipo": true, "nombre_equipo": "ffff", "codigo_interno": "EQ-500", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	web_admin
121	1	2026-05-15 16:23:20.780788	DELETE_LOGICO	equipo	19	{"id_equipo": 19, "id_modelo": 1, "numero_serie": "SN-2026-1234", "activo_equipo": true, "nombre_equipo": "ffff", "codigo_interno": "EQ-500", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 19, "id_modelo": 1, "numero_serie": "SN-2026-1234", "activo_equipo": false, "nombre_equipo": "ffff", "codigo_interno": "EQ-500", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 1}	web_admin
122	1	2026-05-15 16:24:07.823858	INSERT	equipo	20	\N	{"id_equipo": 20, "id_modelo": 1, "numero_serie": "SN-342-124", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX500", "codigo_interno": "EQ-777", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	web_admin
123	1	2026-05-15 16:24:57.15063	INSERT	asignacion_equipo	17	\N	{"id_equipo": 20, "id_ubicacion": 1, "id_asignacion": 17, "fecha_fin_asignacion": null, "id_estado_asignacion": 1, "id_persona_responsable": 7, "observacion_asignacion": "Para la paciente Teresa", "fecha_inicio_asignacion": "2026-05-15T16:24:57.15063"}	web_admin
124	6	2026-05-15 16:30:50.60133	UPDATE	equipo	3	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 1, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 3, "id_modelo": 2, "numero_serie": "SN-BX-2024-003", "activo_equipo": true, "nombre_equipo": "Bomba Baxter Sigma", "codigo_interno": "EQ-003", "id_tipo_equipo": 2, "id_estado_equipo": 2, "id_criticidad_equipo": 2, "id_ubicacion_administrativa_actual": 3}	web_responsable
128	1	2026-05-15 18:58:48.303832	INSERT	usuario	12	\N	{"username": "test_usr_temp2", "id_persona": 14, "id_usuario": 12, "contrasenia": "pass123", "activo_usuario": true}	test
129	1	2026-05-15 19:01:33.193711	INSERT	persona	15	\N	{"id_persona": 15, "correo_persona": "rbustani@hospital.com", "nombre_persona": "Roberto", "apellido_persona": "Sánchez Bustani"}	web_admin
130	1	2026-05-15 19:02:04.855461	INSERT	usuario	13	\N	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	web_admin
132	1	2026-05-15 19:12:48.42469	INSERT	usuario	14	\N	{"username": "test_medico_tmp", "id_persona": 16, "id_usuario": 14, "contrasenia": "pass123", "activo_usuario": true}	test
134	1	2026-05-15 19:13:22.481458	INSERT	usuario	15	\N	{"username": "ana_medico_tmp", "id_persona": 17, "id_usuario": 15, "contrasenia": "pass123", "activo_usuario": true}	test
135	1	2026-05-15 19:33:38.577382	UPDATE	responsable_area	2	{"id_area": 2, "id_enfermero": 2, "id_responsable_area": 2, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2025-01-01T15:00:00"}	{"id_area": 2, "id_enfermero": 2, "id_responsable_area": 2, "fecha_fin_responsable_area": "2026-05-15T19:33:38.577382", "fecha_inicio_responsable_area": "2025-01-01T15:00:00"}	test
136	1	2026-05-15 19:33:38.590329	INSERT	responsable_area	8	\N	{"id_area": 2, "id_enfermero": 2, "id_responsable_area": 8, "fecha_fin_responsable_area": null, "fecha_inicio_responsable_area": "2026-05-15T19:33:38.590329"}	test
137	1	2026-05-15 19:34:53.09847	UPDATE	usuario	3	{"username": "mlopez", "id_persona": 3, "id_usuario": 3, "contrasenia": "hashed_lopez123", "activo_usuario": true}	{"username": "mlopez", "id_persona": 3, "id_usuario": 3, "contrasenia": "hashed_lopez123", "activo_usuario": true}	test
138	1	2026-05-15 19:34:53.12083	UPDATE	usuario	3	{"username": "mlopez", "id_persona": 3, "id_usuario": 3, "contrasenia": "hashed_lopez123", "activo_usuario": true}	{"username": "mlopez", "id_persona": 3, "id_usuario": 3, "contrasenia": "hashed_lopez123", "activo_usuario": true}	test
139	1	2026-05-15 19:34:53.12586	UPDATE	usuario	2	{"username": "cgarcia", "id_persona": 2, "id_usuario": 2, "contrasenia": "hashed_garcia123", "activo_usuario": true}	{"username": "cgarcia", "id_persona": 2, "id_usuario": 2, "contrasenia": "hashed_garcia123", "activo_usuario": true}	test
140	1	2026-05-15 19:34:53.132672	UPDATE	usuario	2	{"username": "cgarcia", "id_persona": 2, "id_usuario": 2, "contrasenia": "hashed_garcia123", "activo_usuario": true}	{"username": "cgarcia", "id_persona": 2, "id_usuario": 2, "contrasenia": "hashed_garcia123", "activo_usuario": true}	test
141	1	2026-05-15 19:48:47.945288	UPDATE	usuario	13	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	web_admin
142	13	2026-05-15 19:50:24.588395	UPDATE	equipo	20	{"id_equipo": 20, "id_modelo": 1, "numero_serie": "SN-342-124", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX500", "codigo_interno": "EQ-777", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 20, "id_modelo": 1, "numero_serie": "SN-342-124", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX500", "codigo_interno": "EQ-777", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 3}	web_enfermero
143	13	2026-05-15 19:50:24.588395	INSERT	movimiento	12	\N	{"id_equipo": 20, "id_movimiento": 12, "motivo_movimiento": "Para la paciente teresa", "id_tipo_movimiento": 3, "id_ubicacion_origen": 1, "id_ubicacion_destino": 3, "fecha_hora_movimiento": "2026-05-15T19:50:24.588395", "observacion_movimiento": null, "id_persona_responsable_movimiento": 15}	web_enfermero
144	1	2026-05-15 19:57:06.971105	UPDATE	usuario	13	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	web_admin
145	1	2026-05-15 19:57:56.912523	UPDATE	usuario	13	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	{"username": "rbustani", "id_persona": 15, "id_usuario": 13, "contrasenia": "hashed_rbustani", "activo_usuario": true}	web_admin
146	13	2026-05-15 19:59:26.560466	UPDATE	equipo	20	{"id_equipo": 20, "id_modelo": 1, "numero_serie": "SN-342-124", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX500", "codigo_interno": "EQ-777", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 20, "id_modelo": 1, "numero_serie": "SN-342-124", "activo_equipo": true, "nombre_equipo": "Monitor Philips MX500", "codigo_interno": "EQ-777", "id_tipo_equipo": 1, "id_estado_equipo": 2, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 3}	web_enfermero
147	1	2026-05-15 20:45:54.492521	UPDATE	usuario	4	{"username": "rramirez", "id_persona": 4, "id_usuario": 4, "contrasenia": "hashed_ramirez123", "activo_usuario": true}	{"username": "rramirez", "id_persona": 4, "id_usuario": 4, "contrasenia": "hashed_ramirez123", "activo_usuario": true}	web_admin
148	1	2026-05-16 06:46:10.184902	UPDATE	equipo	11	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "", "activo_equipo": false, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	{"id_equipo": 11, "id_modelo": 1, "numero_serie": "SN-PH-2026-011", "activo_equipo": false, "nombre_equipo": "pipi", "codigo_interno": "EQ-011", "id_tipo_equipo": 1, "id_estado_equipo": 1, "id_criticidad_equipo": 3, "id_ubicacion_administrativa_actual": 1}	directo_bd
149	4	2026-05-16 15:07:17.027499	UPDATE	equipo	2	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 3}	{"id_equipo": 2, "id_modelo": 4, "numero_serie": "SN-DR-2024-002", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita", "codigo_interno": "EQ-002", "id_tipo_equipo": 4, "id_estado_equipo": 3, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 6}	sistema
150	4	2026-05-16 15:07:17.027499	INSERT	movimiento	13	\N	{"id_equipo": 2, "id_movimiento": 13, "motivo_movimiento": "Equipo en mantenimiento trasladado a Bodega Biomédica", "id_tipo_movimiento": 1, "id_ubicacion_origen": 3, "id_ubicacion_destino": 6, "fecha_hora_movimiento": "2026-05-16T15:07:17.027499", "observacion_movimiento": "Corrección de ubicación: ventilador en mantenimiento debe estar en bodega biomédica, no en área clínica", "id_persona_responsable_movimiento": 4}	sistema
151	1	2026-05-16 21:30:43.664428	INSERT	equipo	21	\N	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	web_admin
\.


--
-- Data for Name: biomedico; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.biomedico (id_biomedico, id_persona, id_turno) FROM stdin;
1	4	1
\.


--
-- Data for Name: categoria_equipos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categoria_equipos (id_categoria_equipo, categoria_equipo) FROM stdin;
1	Diagnóstico
2	Terapia
3	Soporte Vital
4	Monitoreo
\.


--
-- Data for Name: criticidad_equipos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.criticidad_equipos (id_criticidad_equipo, criticidad_equipo) FROM stdin;
1	Alta
2	Media
3	Baja
\.


--
-- Data for Name: dispositivo_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dispositivo_beacon (id_beacon, uuid_beacon, major_beacon, minor_beacon, activo_beacon, id_zona_beacon) FROM stdin;
3	BEACON-UUID-QUIR	3	1	f	3
2	BEACON-UUID-UCI	2	1	t	2
1	BEACON-UUID-URGENCIAS	1	1	f	1
8	4E6ED5AB-B3ED-4E10-8247-C5F5524D4B21	12	13	t	3
\.


--
-- Data for Name: dispositivo_gps; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dispositivo_gps (id_gps, codigo_gps, activo_gps, id_ambulancia) FROM stdin;
1	GPS-AMB-001	t	1
2	GPS-AMB-002	t	2
\.


--
-- Data for Name: dispositivo_nfc; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.dispositivo_nfc (id_nfc, codigo_uid_nfc, id_equipo, activo_nfc) FROM stdin;
2	NFC-UID-EQ002	2	t
3	NFC-UID-EQ003	3	t
5	NFC-UID-EQ005	5	t
6	NFC-UID-EQ006	6	t
7	NFC-UID-EQ007	7	t
8	NFC-UID-EQ008	8	t
9	NFC-UID-EQ009	9	t
10	NFC-UID-EQ010	10	t
4	NFC-UID-EQ004	4	f
11		11	t
12	15CB503D	21	t
1	15:CB:50:3D	1	f
\.


--
-- Data for Name: enfermero; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.enfermero (id_enfermero, id_persona, id_especialidad_enfermero, id_turno) FROM stdin;
2	6	1	2
3	8	2	2
4	9	3	1
5	10	4	2
6	11	5	3
1	3	2	1
7	15	2	2
\.


--
-- Data for Name: equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.equipo (id_equipo, codigo_interno, nombre_equipo, id_modelo, numero_serie, id_tipo_equipo, id_criticidad_equipo, id_estado_equipo, id_ubicacion_administrativa_actual, activo_equipo) FROM stdin;
6	EQ-006	Monitor Philips MX450 B	1	SN-PH-2026-006	1	1	1	2	t
7	EQ-007	Bomba Baxter Sigma B	2	SN-BX-2026-007	2	2	1	3	t
9	EQ-009	ECG GE CARESCAPE B	3	SN-GE-2026-009	5	3	1	5	t
1	EQ-001	Monitor Philips MX450	1	SN-PH-2024-001	1	1	1	3	t
5	EQ-005	ECG GE CARESCAPE B450	3	SN-GE-2024-005	5	3	1	3	t
8	EQ-008	Ventilador Dräger Evita B	4	SN-DR-2026-008	4	1	1	5	t
4	EQ-004	Desfibrilador Mindray D3	5	SN-MY-2024-004	3	1	1	3	t
10	EQ-010	Desfibrilador Mindray D3 B	5	SN-MY-2026-010	3	1	2	4	t
19	EQ-500	ffff	1	SN-2026-1234	1	2	1	1	f
3	EQ-003	Bomba Baxter Sigma	2	SN-BX-2024-003	2	2	2	3	t
20	EQ-777	Monitor Philips MX500	1	SN-342-124	1	3	2	3	t
11	EQ-011	pipi	1	SN-PH-2026-011	1	3	1	1	f
2	EQ-002	Ventilador Dräger Evita	4	SN-DR-2024-002	4	1	3	6	t
21	EQ-012	Ventilador Dräger Evita C	4	SN-DR-2026-012	4	1	1	5	t
\.


--
-- Data for Name: especialidad_area_enfermero; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.especialidad_area_enfermero (id_especialidad_enfermero, id_area) FROM stdin;
1	2
2	1
3	3
4	4
5	6
\.


--
-- Data for Name: especialidades_enfermero; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.especialidades_enfermero (id_especialidad_enfermero, especialidad_enfermero) FROM stdin;
1	Cuidados Intensivos
2	Urgencias
3	Quirófano
4	Hospitalización
5	Neonatal
\.


--
-- Data for Name: especialidades_medico; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.especialidades_medico (id_especialidad_medico, especialidad_medico) FROM stdin;
1	Medicina Interna
2	Cardiología
3	Pediatría
4	Anestesiología
5	Urgencias
\.


--
-- Data for Name: estado_ambulancias; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.estado_ambulancias (id_estado_ambulancia, estado_ambulancia) FROM stdin;
1	Activa
2	En mantenimiento
3	Fuera de servicio
\.


--
-- Data for Name: estado_asignacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.estado_asignacion (id_estado_asignacion, estado_asignacion) FROM stdin;
1	Activa
2	Finalizada
3	Cancelada
\.


--
-- Data for Name: estado_cumplimiento_mantenimientos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.estado_cumplimiento_mantenimientos (id_estado_cumplimiento, estado_cumplimiento) FROM stdin;
1	Pendiente
2	Cumplido
3	Vencido
4	Reprogramado
\.


--
-- Data for Name: estado_equipos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.estado_equipos (id_estado_equipo, estado_equipo) FROM stdin;
1	Disponible
2	En uso
3	En mantenimiento
4	Fuera de servicio
5	Retirado
6	En préstamo
\.


--
-- Data for Name: evento_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.evento_beacon (id_evento_beacon, id_beacon, id_equipo, fecha_hora_evento, id_tipo_evento_beacon) FROM stdin;
1	2	3	2026-04-18 16:12:55.114792	1
2	1	1	2026-02-01 08:00:00	1
3	1	6	2026-02-01 07:30:00	1
4	2	2	2026-01-15 15:00:00	1
5	2	7	2026-03-01 15:00:00	1
6	3	9	2026-02-15 08:00:00	1
7	1	1	2026-03-01 08:00:00	3
8	2	5	2026-02-10 15:00:00	1
9	8	21	2026-05-17 04:40:19.429817	1
\.


--
-- Data for Name: evento_gps; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.evento_gps (id_evento_gps, id_gps, fecha_hora_evento, latitud, longitud, "precision") FROM stdin;
2	1	2026-02-15 10:00:00	25.6714	-100.3090	4.5
3	1	2026-02-15 10:30:00	25.6720	-100.3085	3.8
4	1	2026-03-01 14:00:00	25.6710	-100.3095	5.0
5	2	2026-03-10 09:00:00	25.6718	-100.3088	4.2
6	2	2026-03-10 09:30:00	25.6722	-100.3082	3.5
7	1	2026-02-15 10:00:00	25.6714	-100.3090	4.5
8	1	2026-02-15 10:30:00	25.6720	-100.3085	3.8
9	1	2026-03-01 14:00:00	25.6710	-100.3095	5.0
10	2	2026-03-10 09:00:00	25.6718	-100.3088	4.2
11	2	2026-03-10 09:30:00	25.6722	-100.3082	3.5
\.


--
-- Data for Name: evento_nfc; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.evento_nfc (id_evento_nfc, id_nfc, fecha_hora_evento, id_tipo_evento_nfc) FROM stdin;
1	1	2026-02-01 08:05:00	1
2	1	2026-02-15 09:05:00	1
3	2	2026-01-15 08:10:00	2
4	3	2026-02-05 10:05:00	1
5	5	2026-01-20 08:05:00	1
6	6	2026-02-01 07:35:00	1
7	7	2026-03-01 15:05:00	1
8	12	2026-05-16 22:04:06.364146	1
9	12	2026-05-16 22:05:59.252759	1
10	12	2026-05-16 22:13:19.226511	1
11	12	2026-05-16 22:14:00.434979	1
12	12	2026-05-16 23:09:40.947449	1
13	12	2026-05-16 23:14:19.185889	1
14	12	2026-05-16 23:56:57.5334	1
15	12	2026-05-17 00:01:29.793216	1
16	12	2026-05-17 00:15:59.084577	1
17	12	2026-05-17 00:45:53.372141	1
18	12	2026-05-17 01:12:32.726338	1
19	12	2026-05-17 03:41:38.482484	1
20	12	2026-05-17 04:40:19.429817	1
\.


--
-- Data for Name: mantenimiento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.mantenimiento (id_mantenimiento, id_equipo, id_biomedico, fecha_hora_mantenimiento, id_programacion, id_tipo_mantenimiento, descripcion_mantenimiento, id_resultado_mantenimiento, costo_mantenimiento, observacion_mantenimiento) FROM stdin;
1	4	1	2024-04-01 09:00:00	\N	2	Falla en condensador de descarga	2	4500.00	Equipo enviado a revision externa
2	4	1	2024-06-15 10:00:00	\N	2	Reincidencia en condensador, reparacion parcial	3	3200.00	Pendiente refaccion importada
3	4	1	2024-09-20 11:00:00	\N	2	Tercera falla, sistema de carga inestable	4	1500.00	Se recomienda evaluacion para baja del equipo
5	2	1	2026-04-18 18:21:32.836435	\N	2	Falla detectada en sensor de flujo y alarma de presion	3	3800.00	Requiere refaccion importada, tiempo estimado 5 dias
6	1	1	2026-01-10 08:00:00	1	1	Revision general y limpieza de sensores	1	800.00	Sin anomalias detectadas
7	2	1	2026-01-15 08:00:00	2	1	Calibracion de alarmas y revision de circuitos	1	1200.00	Funcionamiento optimo
8	3	1	2026-02-01 08:00:00	3	3	Calibracion anual de flujo y presion	1	600.00	Dentro de parametros normales
9	5	1	2026-02-10 08:00:00	5	4	Inspeccion semestral de electrodos y cables	1	400.00	Sin desgaste significativo
10	8	1	2026-03-15 08:00:00	\N	2	Falla en valvula de exhalacion	3	2800.00	En espera de refaccion
11	10	1	2026-03-20 08:00:00	\N	1	Revision de bateria y prueba de descarga	1	500.00	Bateria al 95% de capacidad
13	11	1	2026-05-15 14:17:00.925006	\N	3	Error interno en la maquina	2	\N	\N
14	2	1	2026-05-15 14:50:51.587917	\N	3	Fallo complejo	3	\N	\N
\.


--
-- Data for Name: mantenimiento_programado; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.mantenimiento_programado (id_programacion, id_equipo, id_tipo_mantenimiento, frecuencia_dias, fecha_ultimo_mantenimiento, fecha_proximo_mantenimiento, id_prioridad_mantenimiento, sla_horas, id_estado_cumplimiento, observacion_programacion) FROM stdin;
1	1	1	90	2024-10-01 08:00:00	2025-01-01 08:00:00	1	4	1	Preventivo trimestral monitor
2	2	1	180	2024-07-01 08:00:00	2025-01-01 08:00:00	1	8	1	Preventivo semestral ventilador
3	3	3	365	2024-01-01 08:00:00	2025-01-01 08:00:00	2	8	1	Calibración anual bomba
4	4	1	90	2024-10-01 08:00:00	2025-01-01 08:00:00	1	4	3	Preventivo vencido desfibrilador
5	5	4	180	2024-07-01 08:00:00	2025-01-01 08:00:00	2	8	1	Inspección semestral ECG
6	6	1	90	2026-01-10 08:00:00	2026-04-10 08:00:00	1	4	1	Preventivo trimestral monitor B
7	7	3	365	2026-01-15 08:00:00	2027-01-15 08:00:00	2	8	2	Calibracion anual bomba B - cumplida
8	8	2	30	2026-03-15 08:00:00	2026-04-15 08:00:00	1	4	1	Seguimiento correctivo ventilador B
9	9	4	180	2026-02-15 08:00:00	2026-08-15 08:00:00	3	8	2	Inspeccion ECG B - cumplida
10	10	1	90	2026-03-20 08:00:00	2026-06-20 08:00:00	1	4	2	Preventivo desfibrilador B - cumplido
\.


--
-- Data for Name: marca_equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.marca_equipo (id_marca, nombre_marca) FROM stdin;
1	Philips
2	Baxter
3	GE Healthcare
4	Dräger
5	Mindray
\.


--
-- Data for Name: medico; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.medico (id_medico, id_persona, id_especialidad_medico, id_turno) FROM stdin;
2	7	1	2
1	2	5	1
\.


--
-- Data for Name: modelo_equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.modelo_equipo (id_modelo, nombre_modelo, id_marca) FROM stdin;
1	MX450	1
2	Sigma Spectrum	2
3	CARESCAPE B450	3
4	Evita V300	4
5	BeneHeart D3	5
\.


--
-- Data for Name: movimiento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.movimiento (id_movimiento, id_equipo, id_persona_responsable_movimiento, fecha_hora_movimiento, id_tipo_movimiento, id_ubicacion_origen, id_ubicacion_destino, motivo_movimiento, observacion_movimiento) FROM stdin;
8	1	3	2026-04-18 18:17:34.189839	1	1	3	Contingencia - paciente critico requiere monitoreo en UCI	Traslado autorizado por jefe de turno matutino
9	3	3	2026-04-18 18:23:30.838545	2	1	3	Correccion de ubicacion por discrepancia detectada con evidencia Beacon	Beacon confirmo equipo en UCI - se actualiza registro administrativo
12	20	15	2026-05-15 19:50:24.588395	3	1	3	Para la paciente teresa	\N
13	2	4	2026-05-16 15:07:17.027499	1	3	6	Equipo en mantenimiento trasladado a Bodega Biomédica	Corrección de ubicación: ventilador en mantenimiento debe estar en bodega biomédica, no en área clínica
\.


--
-- Data for Name: persona; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.persona (id_persona, nombre_persona, apellido_persona, correo_persona) FROM stdin;
1	Admin	Sistema	admin@hospital.com
2	Carlos	García	c.garcia@hospital.com
3	María	López	m.lopez@hospital.com
4	Roberto	Ramírez	r.ramirez@hospital.com
5	Juan	Pérez	j.perez@hospital.com
6	Ana	Martínez	a.martinez@hospital.com
7	Luis	Torres	l.torres@hospital.com
8	Sandra	Flores	s.flores@hospital.com
9	Carmen	Vega	c.vega@hospital.com
10	Patricia	Morales	p.morales@hospital.com
11	Diana	Castillo	d.castillo@hospital.com
15	Roberto	Sánchez Bustani	rbustani@hospital.com
\.


--
-- Data for Name: prioridad_mantenimientos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.prioridad_mantenimientos (id_prioridad_mantenimiento, prioridad_mantenimiento) FROM stdin;
1	Alta
2	Media
3	Baja
\.


--
-- Data for Name: responsable_area; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.responsable_area (id_responsable_area, id_enfermero, id_area, fecha_inicio_responsable_area, fecha_fin_responsable_area) FROM stdin;
1	1	1	2025-01-01 07:00:00	2026-04-18 18:19:26.698235
3	3	1	2026-04-18 18:19:26.698235	\N
5	4	3	2026-01-01 07:00:00	\N
6	5	4	2026-01-01 15:00:00	\N
7	6	6	2026-01-01 23:00:00	\N
2	2	2	2025-01-01 15:00:00	2026-05-15 19:33:38.577382
8	2	2	2026-05-15 19:33:38.590329	\N
\.


--
-- Data for Name: roles_usuario; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles_usuario (id_rol_usuario, rol_usuario) FROM stdin;
1	Administrador
2	Enfermero
3	Biomédico
4	Médico
5	Conductor
\.


--
-- Data for Name: tipo_equipos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_equipos (id_tipo_equipo, tipo_equipo, id_categoria_equipo) FROM stdin;
1	Monitor de signos vitales	4
2	Bomba de infusión	2
3	Desfibrilador	3
4	Ventilador mecánico	3
5	Electrocardiógrafo	1
\.


--
-- Data for Name: tipo_eventos_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_eventos_beacon (id_tipo_evento_beacon, tipo_evento_beacon) FROM stdin;
1	Detección
2	Pérdida de señal
3	Reaparición
\.


--
-- Data for Name: tipo_eventos_nfc; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_eventos_nfc (id_tipo_evento_nfc, tipo_evento_nfc) FROM stdin;
1	Lectura
2	Verificación
3	Asociación
\.


--
-- Data for Name: tipo_mantenimientos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_mantenimientos (id_tipo_mantenimiento, tipo_mantenimiento) FROM stdin;
1	Preventivo
2	Correctivo
3	Calibración
4	Inspección
\.


--
-- Data for Name: tipo_movimientos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_movimientos (id_tipo_movimiento, tipo_movimiento) FROM stdin;
1	Traslado interno
2	Reasignación
3	Entrega a área
4	Retiro de área
\.


--
-- Data for Name: tipo_procedimiento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_procedimiento (id_tipo_procedimiento, tipo_procedimiento) FROM stdin;
1	Monitoreo
2	Infusión
3	Soporte ventilatorio
4	Reanimación
5	Diagnóstico
\.


--
-- Data for Name: tipo_resultado_mantenimientos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_resultado_mantenimientos (id_resultado_mantenimiento, resultado_mantenimiento) FROM stdin;
1	Exitoso
2	Fallido
3	Pendiente de revisión
4	Requiere reemplazo
\.


--
-- Data for Name: tipo_traslado_externo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_traslado_externo (id_tipo_traslado, tipo_traslado) FROM stdin;
2	Préstamo temporal
\.


--
-- Data for Name: traslado_externo_equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.traslado_externo_equipo (id_traslado_externo, id_equipo, id_nfc_equipo, id_ambulancia, id_persona_conductor, fecha_salida, fecha_llegada, id_tipo_traslado, motivo_traslado, observacion_traslado) FROM stdin;
\.


--
-- Data for Name: turnos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.turnos (id_turno, nombre_turno, hora_inicio, hora_fin) FROM stdin;
1	Matutino	07:00:00	15:00:00
2	Vespertino	15:00:00	23:00:00
3	Nocturno	23:00:00	07:00:00
\.


--
-- Data for Name: ubicacion_especifica; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.ubicacion_especifica (id_ubicacion, nombre_ubicacion, id_area) FROM stdin;
1	Sala Principal Urgencias	1
2	Pasillo Urgencias	1
3	Cama UCI-01	2
4	Cama UCI-02	2
5	Sala Quirófano	3
6	Bodega Biomédica	5
7	Sala Neonatal	6
\.


--
-- Data for Name: uso_clinico_equipo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.uso_clinico_equipo (id_uso_clinico, id_equipo, id_persona_responsable_uso, fecha_hora_inicio, fecha_hora_fin, id_area, id_turno, id_tipo_procedimiento, motivo_uso) FROM stdin;
6	1	2	2026-02-01 08:00:00	2026-02-01 10:30:00	1	1	1	Monitoreo paciente con trauma craneoencefalico
7	1	2	2026-02-15 09:00:00	2026-02-15 11:00:00	1	1	1	Monitoreo paciente con infarto agudo
8	1	3	2026-03-01 08:30:00	2026-03-01 09:45:00	1	1	5	Diagnostico paciente con arritmia
9	3	2	2026-02-05 10:00:00	2026-02-05 14:00:00	1	1	2	Infusion de medicamento vasopresor
10	3	3	2026-02-20 08:00:00	2026-02-20 12:00:00	1	1	2	Infusion de antibiotico endovenoso
11	5	2	2026-01-20 08:00:00	2026-01-20 08:30:00	2	1	5	Electrocardiograma de control postoperatorio
12	5	7	2026-02-10 15:00:00	2026-02-10 15:30:00	2	2	5	Electrocardiograma paciente con dolor toracico
13	7	7	2026-03-01 15:00:00	2026-03-01 19:00:00	2	2	2	Infusion de sedante para paciente critico
14	7	6	2026-03-10 15:00:00	2026-03-10 23:00:00	2	2	2	Infusion de nutricion parenteral
15	10	2	2026-03-25 09:00:00	2026-03-25 09:15:00	4	1	4	Reanimacion de emergencia paciente con fibrilacion
21	20	15	2026-05-15 19:59:26.560466	\N	2	1	1	\N
\.


--
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuario (id_usuario, username, contrasenia, activo_usuario, id_persona) FROM stdin;
1	admin	hashed_admin123	t	1
5	jperez	hashed_perez123	t	5
6	amartinez	hashed_amtz123	t	6
7	ltorres	hashed_torres123	t	7
8	sflores	hashed_flores123	t	8
9	cvega	hashed_vega123	t	9
10	pmorales	hashed_morales123	t	10
11	dcastillo	hashed_castillo123	t	11
3	mlopez	hashed_lopez123	t	3
2	cgarcia	hashed_garcia123	t	2
13	rbustani	hashed_rbustani	t	15
4	rramirez	hashed_ramirez123	t	4
\.


--
-- Data for Name: usuario_rol; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuario_rol (id_usuario, id_rol_usuario) FROM stdin;
1	1
2	4
3	2
4	3
5	5
6	2
7	4
8	2
9	2
10	2
11	2
13	2
\.


--
-- Data for Name: zona_beacon; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.zona_beacon (id_zona_beacon, nombre_zona_beacon, id_ubicacion) FROM stdin;
1	Zona A - Urgencias	1
2	Zona B - UCI	3
3	Zona C - Quirófano	5
\.


--
-- Name: ambulancia_id_ambulancia_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ambulancia_id_ambulancia_seq', 2, true);


--
-- Name: area_registro_id_area_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.area_registro_id_area_seq', 6, true);


--
-- Name: asignacion_equipo_id_asignacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.asignacion_equipo_id_asignacion_seq', 17, true);


--
-- Name: auditoria_id_auditoria_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.auditoria_id_auditoria_seq', 151, true);


--
-- Name: biomedico_id_biomedico_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.biomedico_id_biomedico_seq', 3, true);


--
-- Name: categoria_equipos_id_categoria_equipo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categoria_equipos_id_categoria_equipo_seq', 4, true);


--
-- Name: criticidad_equipos_id_criticidad_equipo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.criticidad_equipos_id_criticidad_equipo_seq', 3, true);


--
-- Name: dispositivo_beacon_id_beacon_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dispositivo_beacon_id_beacon_seq', 8, true);


--
-- Name: dispositivo_gps_id_gps_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dispositivo_gps_id_gps_seq', 2, true);


--
-- Name: dispositivo_nfc_id_nfc_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.dispositivo_nfc_id_nfc_seq', 12, true);


--
-- Name: enfermero_id_enfermero_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.enfermero_id_enfermero_seq', 8, true);


--
-- Name: equipo_id_equipo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.equipo_id_equipo_seq', 21, true);


--
-- Name: especialidades_enfermero_id_especialidad_enfermero_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.especialidades_enfermero_id_especialidad_enfermero_seq', 5, true);


--
-- Name: especialidades_medico_id_especialidad_medico_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.especialidades_medico_id_especialidad_medico_seq', 5, true);


--
-- Name: estado_ambulancias_id_estado_ambulancia_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.estado_ambulancias_id_estado_ambulancia_seq', 3, true);


--
-- Name: estado_asignacion_id_estado_asignacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.estado_asignacion_id_estado_asignacion_seq', 3, true);


--
-- Name: estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq', 4, true);


--
-- Name: estado_equipos_id_estado_equipo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.estado_equipos_id_estado_equipo_seq', 5, true);


--
-- Name: evento_beacon_id_evento_beacon_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evento_beacon_id_evento_beacon_seq', 9, true);


--
-- Name: evento_gps_id_evento_gps_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evento_gps_id_evento_gps_seq', 11, true);


--
-- Name: evento_nfc_id_evento_nfc_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evento_nfc_id_evento_nfc_seq', 20, true);


--
-- Name: mantenimiento_id_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.mantenimiento_id_mantenimiento_seq', 14, true);


--
-- Name: mantenimiento_programado_id_programacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.mantenimiento_programado_id_programacion_seq', 10, true);


--
-- Name: marca_equipo_id_marca_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.marca_equipo_id_marca_seq', 5, true);


--
-- Name: medico_id_medico_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.medico_id_medico_seq', 3, true);


--
-- Name: modelo_equipo_id_modelo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.modelo_equipo_id_modelo_seq', 5, true);


--
-- Name: movimiento_id_movimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.movimiento_id_movimiento_seq', 13, true);


--
-- Name: persona_id_persona_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.persona_id_persona_seq', 17, true);


--
-- Name: prioridad_mantenimientos_id_prioridad_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq', 3, true);


--
-- Name: responsable_area_id_responsable_area_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.responsable_area_id_responsable_area_seq', 8, true);


--
-- Name: roles_usuario_id_rol_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_usuario_id_rol_usuario_seq', 5, true);


--
-- Name: tipo_equipos_id_tipo_equipo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_equipos_id_tipo_equipo_seq', 5, true);


--
-- Name: tipo_eventos_beacon_id_tipo_evento_beacon_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_eventos_beacon_id_tipo_evento_beacon_seq', 3, true);


--
-- Name: tipo_eventos_nfc_id_tipo_evento_nfc_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_eventos_nfc_id_tipo_evento_nfc_seq', 3, true);


--
-- Name: tipo_mantenimientos_id_tipo_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_mantenimientos_id_tipo_mantenimiento_seq', 4, true);


--
-- Name: tipo_movimientos_id_tipo_movimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_movimientos_id_tipo_movimiento_seq', 4, true);


--
-- Name: tipo_procedimiento_id_tipo_procedimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_procedimiento_id_tipo_procedimiento_seq', 5, true);


--
-- Name: tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq', 4, true);


--
-- Name: tipo_traslado_externo_id_tipo_traslado_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_traslado_externo_id_tipo_traslado_seq', 3, true);


--
-- Name: traslado_externo_equipo_id_traslado_externo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.traslado_externo_equipo_id_traslado_externo_seq', 2, true);


--
-- Name: turnos_id_turno_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.turnos_id_turno_seq', 3, true);


--
-- Name: ubicacion_especifica_id_ubicacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.ubicacion_especifica_id_ubicacion_seq', 7, true);


--
-- Name: uso_clinico_equipo_id_uso_clinico_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.uso_clinico_equipo_id_uso_clinico_seq', 21, true);


--
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 15, true);


--
-- Name: zona_beacon_id_zona_beacon_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.zona_beacon_id_zona_beacon_seq', 3, true);


--
-- Name: ambulancia ambulancia_codigo_ambulancia_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ambulancia
    ADD CONSTRAINT ambulancia_codigo_ambulancia_key UNIQUE (codigo_ambulancia);


--
-- Name: ambulancia ambulancia_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ambulancia
    ADD CONSTRAINT ambulancia_pkey PRIMARY KEY (id_ambulancia);


--
-- Name: ambulancia ambulancia_placa_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ambulancia
    ADD CONSTRAINT ambulancia_placa_key UNIQUE (placa);


--
-- Name: area_registro area_registro_nombre_area_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.area_registro
    ADD CONSTRAINT area_registro_nombre_area_key UNIQUE (nombre_area);


--
-- Name: area_registro area_registro_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.area_registro
    ADD CONSTRAINT area_registro_pkey PRIMARY KEY (id_area);


--
-- Name: asignacion_equipo asignacion_equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo
    ADD CONSTRAINT asignacion_equipo_pkey PRIMARY KEY (id_asignacion);


--
-- Name: auditoria auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id_auditoria);


--
-- Name: biomedico biomedico_id_persona_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.biomedico
    ADD CONSTRAINT biomedico_id_persona_key UNIQUE (id_persona);


--
-- Name: biomedico biomedico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.biomedico
    ADD CONSTRAINT biomedico_pkey PRIMARY KEY (id_biomedico);


--
-- Name: categoria_equipos categoria_equipos_categoria_equipo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_equipos
    ADD CONSTRAINT categoria_equipos_categoria_equipo_key UNIQUE (categoria_equipo);


--
-- Name: categoria_equipos categoria_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_equipos
    ADD CONSTRAINT categoria_equipos_pkey PRIMARY KEY (id_categoria_equipo);


--
-- Name: criticidad_equipos criticidad_equipos_criticidad_equipo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.criticidad_equipos
    ADD CONSTRAINT criticidad_equipos_criticidad_equipo_key UNIQUE (criticidad_equipo);


--
-- Name: criticidad_equipos criticidad_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.criticidad_equipos
    ADD CONSTRAINT criticidad_equipos_pkey PRIMARY KEY (id_criticidad_equipo);


--
-- Name: dispositivo_beacon dispositivo_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_beacon
    ADD CONSTRAINT dispositivo_beacon_pkey PRIMARY KEY (id_beacon);


--
-- Name: dispositivo_beacon dispositivo_beacon_uuid_beacon_major_beacon_minor_beacon_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_beacon
    ADD CONSTRAINT dispositivo_beacon_uuid_beacon_major_beacon_minor_beacon_key UNIQUE (uuid_beacon, major_beacon, minor_beacon);


--
-- Name: dispositivo_gps dispositivo_gps_codigo_gps_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_codigo_gps_key UNIQUE (codigo_gps);


--
-- Name: dispositivo_gps dispositivo_gps_id_ambulancia_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_id_ambulancia_key UNIQUE (id_ambulancia);


--
-- Name: dispositivo_gps dispositivo_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_pkey PRIMARY KEY (id_gps);


--
-- Name: dispositivo_nfc dispositivo_nfc_codigo_uid_nfc_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_nfc
    ADD CONSTRAINT dispositivo_nfc_codigo_uid_nfc_key UNIQUE (codigo_uid_nfc);


--
-- Name: dispositivo_nfc dispositivo_nfc_id_equipo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_nfc
    ADD CONSTRAINT dispositivo_nfc_id_equipo_key UNIQUE (id_equipo);


--
-- Name: dispositivo_nfc dispositivo_nfc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_nfc
    ADD CONSTRAINT dispositivo_nfc_pkey PRIMARY KEY (id_nfc);


--
-- Name: enfermero enfermero_id_persona_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero
    ADD CONSTRAINT enfermero_id_persona_key UNIQUE (id_persona);


--
-- Name: enfermero enfermero_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero
    ADD CONSTRAINT enfermero_pkey PRIMARY KEY (id_enfermero);


--
-- Name: equipo equipo_codigo_interno_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_codigo_interno_key UNIQUE (codigo_interno);


--
-- Name: equipo equipo_numero_serie_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_numero_serie_key UNIQUE (numero_serie);


--
-- Name: equipo equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_pkey PRIMARY KEY (id_equipo);


--
-- Name: especialidad_area_enfermero especialidad_area_enfermero_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidad_area_enfermero
    ADD CONSTRAINT especialidad_area_enfermero_pkey PRIMARY KEY (id_especialidad_enfermero, id_area);


--
-- Name: especialidades_enfermero especialidades_enfermero_especialidad_enfermero_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_enfermero
    ADD CONSTRAINT especialidades_enfermero_especialidad_enfermero_key UNIQUE (especialidad_enfermero);


--
-- Name: especialidades_enfermero especialidades_enfermero_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_enfermero
    ADD CONSTRAINT especialidades_enfermero_pkey PRIMARY KEY (id_especialidad_enfermero);


--
-- Name: especialidades_medico especialidades_medico_especialidad_medico_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_medico
    ADD CONSTRAINT especialidades_medico_especialidad_medico_key UNIQUE (especialidad_medico);


--
-- Name: especialidades_medico especialidades_medico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidades_medico
    ADD CONSTRAINT especialidades_medico_pkey PRIMARY KEY (id_especialidad_medico);


--
-- Name: estado_ambulancias estado_ambulancias_estado_ambulancia_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_ambulancias
    ADD CONSTRAINT estado_ambulancias_estado_ambulancia_key UNIQUE (estado_ambulancia);


--
-- Name: estado_ambulancias estado_ambulancias_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_ambulancias
    ADD CONSTRAINT estado_ambulancias_pkey PRIMARY KEY (id_estado_ambulancia);


--
-- Name: estado_asignacion estado_asignacion_estado_asignacion_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_asignacion
    ADD CONSTRAINT estado_asignacion_estado_asignacion_key UNIQUE (estado_asignacion);


--
-- Name: estado_asignacion estado_asignacion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_asignacion
    ADD CONSTRAINT estado_asignacion_pkey PRIMARY KEY (id_estado_asignacion);


--
-- Name: estado_cumplimiento_mantenimientos estado_cumplimiento_mantenimientos_estado_cumplimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_cumplimiento_mantenimientos
    ADD CONSTRAINT estado_cumplimiento_mantenimientos_estado_cumplimiento_key UNIQUE (estado_cumplimiento);


--
-- Name: estado_cumplimiento_mantenimientos estado_cumplimiento_mantenimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_cumplimiento_mantenimientos
    ADD CONSTRAINT estado_cumplimiento_mantenimientos_pkey PRIMARY KEY (id_estado_cumplimiento);


--
-- Name: estado_equipos estado_equipos_estado_equipo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_equipos
    ADD CONSTRAINT estado_equipos_estado_equipo_key UNIQUE (estado_equipo);


--
-- Name: estado_equipos estado_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estado_equipos
    ADD CONSTRAINT estado_equipos_pkey PRIMARY KEY (id_estado_equipo);


--
-- Name: evento_beacon evento_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_beacon
    ADD CONSTRAINT evento_beacon_pkey PRIMARY KEY (id_evento_beacon);


--
-- Name: evento_gps evento_gps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_gps
    ADD CONSTRAINT evento_gps_pkey PRIMARY KEY (id_evento_gps);


--
-- Name: evento_nfc evento_nfc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_nfc
    ADD CONSTRAINT evento_nfc_pkey PRIMARY KEY (id_evento_nfc);


--
-- Name: mantenimiento mantenimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_pkey PRIMARY KEY (id_mantenimiento);


--
-- Name: mantenimiento_programado mantenimiento_programado_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado
    ADD CONSTRAINT mantenimiento_programado_pkey PRIMARY KEY (id_programacion);


--
-- Name: marca_equipo marca_equipo_nombre_marca_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.marca_equipo
    ADD CONSTRAINT marca_equipo_nombre_marca_key UNIQUE (nombre_marca);


--
-- Name: marca_equipo marca_equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.marca_equipo
    ADD CONSTRAINT marca_equipo_pkey PRIMARY KEY (id_marca);


--
-- Name: medico medico_id_persona_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_id_persona_key UNIQUE (id_persona);


--
-- Name: medico medico_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_pkey PRIMARY KEY (id_medico);


--
-- Name: modelo_equipo modelo_equipo_nombre_modelo_id_marca_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelo_equipo
    ADD CONSTRAINT modelo_equipo_nombre_modelo_id_marca_key UNIQUE (nombre_modelo, id_marca);


--
-- Name: modelo_equipo modelo_equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelo_equipo
    ADD CONSTRAINT modelo_equipo_pkey PRIMARY KEY (id_modelo);


--
-- Name: movimiento movimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_pkey PRIMARY KEY (id_movimiento);


--
-- Name: persona persona_correo_persona_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.persona
    ADD CONSTRAINT persona_correo_persona_key UNIQUE (correo_persona);


--
-- Name: persona persona_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.persona
    ADD CONSTRAINT persona_pkey PRIMARY KEY (id_persona);


--
-- Name: prioridad_mantenimientos prioridad_mantenimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prioridad_mantenimientos
    ADD CONSTRAINT prioridad_mantenimientos_pkey PRIMARY KEY (id_prioridad_mantenimiento);


--
-- Name: prioridad_mantenimientos prioridad_mantenimientos_prioridad_mantenimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.prioridad_mantenimientos
    ADD CONSTRAINT prioridad_mantenimientos_prioridad_mantenimiento_key UNIQUE (prioridad_mantenimiento);


--
-- Name: responsable_area responsable_area_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.responsable_area
    ADD CONSTRAINT responsable_area_pkey PRIMARY KEY (id_responsable_area);


--
-- Name: roles_usuario roles_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles_usuario
    ADD CONSTRAINT roles_usuario_pkey PRIMARY KEY (id_rol_usuario);


--
-- Name: roles_usuario roles_usuario_rol_usuario_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles_usuario
    ADD CONSTRAINT roles_usuario_rol_usuario_key UNIQUE (rol_usuario);


--
-- Name: tipo_equipos tipo_equipos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_equipos
    ADD CONSTRAINT tipo_equipos_pkey PRIMARY KEY (id_tipo_equipo);


--
-- Name: tipo_equipos tipo_equipos_tipo_equipo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_equipos
    ADD CONSTRAINT tipo_equipos_tipo_equipo_key UNIQUE (tipo_equipo);


--
-- Name: tipo_eventos_beacon tipo_eventos_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_beacon
    ADD CONSTRAINT tipo_eventos_beacon_pkey PRIMARY KEY (id_tipo_evento_beacon);


--
-- Name: tipo_eventos_beacon tipo_eventos_beacon_tipo_evento_beacon_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_beacon
    ADD CONSTRAINT tipo_eventos_beacon_tipo_evento_beacon_key UNIQUE (tipo_evento_beacon);


--
-- Name: tipo_eventos_nfc tipo_eventos_nfc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_nfc
    ADD CONSTRAINT tipo_eventos_nfc_pkey PRIMARY KEY (id_tipo_evento_nfc);


--
-- Name: tipo_eventos_nfc tipo_eventos_nfc_tipo_evento_nfc_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_eventos_nfc
    ADD CONSTRAINT tipo_eventos_nfc_tipo_evento_nfc_key UNIQUE (tipo_evento_nfc);


--
-- Name: tipo_mantenimientos tipo_mantenimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_mantenimientos
    ADD CONSTRAINT tipo_mantenimientos_pkey PRIMARY KEY (id_tipo_mantenimiento);


--
-- Name: tipo_mantenimientos tipo_mantenimientos_tipo_mantenimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_mantenimientos
    ADD CONSTRAINT tipo_mantenimientos_tipo_mantenimiento_key UNIQUE (tipo_mantenimiento);


--
-- Name: tipo_movimientos tipo_movimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_movimientos
    ADD CONSTRAINT tipo_movimientos_pkey PRIMARY KEY (id_tipo_movimiento);


--
-- Name: tipo_movimientos tipo_movimientos_tipo_movimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_movimientos
    ADD CONSTRAINT tipo_movimientos_tipo_movimiento_key UNIQUE (tipo_movimiento);


--
-- Name: tipo_procedimiento tipo_procedimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_procedimiento
    ADD CONSTRAINT tipo_procedimiento_pkey PRIMARY KEY (id_tipo_procedimiento);


--
-- Name: tipo_procedimiento tipo_procedimiento_tipo_procedimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_procedimiento
    ADD CONSTRAINT tipo_procedimiento_tipo_procedimiento_key UNIQUE (tipo_procedimiento);


--
-- Name: tipo_resultado_mantenimientos tipo_resultado_mantenimientos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_resultado_mantenimientos
    ADD CONSTRAINT tipo_resultado_mantenimientos_pkey PRIMARY KEY (id_resultado_mantenimiento);


--
-- Name: tipo_resultado_mantenimientos tipo_resultado_mantenimientos_resultado_mantenimiento_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_resultado_mantenimientos
    ADD CONSTRAINT tipo_resultado_mantenimientos_resultado_mantenimiento_key UNIQUE (resultado_mantenimiento);


--
-- Name: tipo_traslado_externo tipo_traslado_externo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_traslado_externo
    ADD CONSTRAINT tipo_traslado_externo_pkey PRIMARY KEY (id_tipo_traslado);


--
-- Name: tipo_traslado_externo tipo_traslado_externo_tipo_traslado_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_traslado_externo
    ADD CONSTRAINT tipo_traslado_externo_tipo_traslado_key UNIQUE (tipo_traslado);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_pkey PRIMARY KEY (id_traslado_externo);


--
-- Name: turnos turnos_nombre_turno_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.turnos
    ADD CONSTRAINT turnos_nombre_turno_key UNIQUE (nombre_turno);


--
-- Name: turnos turnos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.turnos
    ADD CONSTRAINT turnos_pkey PRIMARY KEY (id_turno);


--
-- Name: ubicacion_especifica ubicacion_especifica_nombre_ubicacion_id_area_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ubicacion_especifica
    ADD CONSTRAINT ubicacion_especifica_nombre_ubicacion_id_area_key UNIQUE (nombre_ubicacion, id_area);


--
-- Name: ubicacion_especifica ubicacion_especifica_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ubicacion_especifica
    ADD CONSTRAINT ubicacion_especifica_pkey PRIMARY KEY (id_ubicacion);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_pkey PRIMARY KEY (id_uso_clinico);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- Name: usuario_rol usuario_rol_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_pkey PRIMARY KEY (id_usuario, id_rol_usuario);


--
-- Name: usuario usuario_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_username_key UNIQUE (username);


--
-- Name: zona_beacon zona_beacon_nombre_zona_beacon_id_ubicacion_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona_beacon
    ADD CONSTRAINT zona_beacon_nombre_zona_beacon_id_ubicacion_key UNIQUE (nombre_zona_beacon, id_ubicacion);


--
-- Name: zona_beacon zona_beacon_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona_beacon
    ADD CONSTRAINT zona_beacon_pkey PRIMARY KEY (id_zona_beacon);


--
-- Name: idx_asignacion_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asignacion_equipo ON public.asignacion_equipo USING btree (id_equipo);


--
-- Name: idx_asignacion_persona; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asignacion_persona ON public.asignacion_equipo USING btree (id_persona_responsable);


--
-- Name: idx_asignacion_ubicacion; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_asignacion_ubicacion ON public.asignacion_equipo USING btree (id_ubicacion);


--
-- Name: idx_auditoria_tabla; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auditoria_tabla ON public.auditoria USING btree (tabla_afectada);


--
-- Name: idx_auditoria_usuario; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_auditoria_usuario ON public.auditoria USING btree (id_usuario);


--
-- Name: idx_equipo_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_equipo_estado ON public.equipo USING btree (id_estado_equipo);


--
-- Name: idx_equipo_modelo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_equipo_modelo ON public.equipo USING btree (id_modelo);


--
-- Name: idx_equipo_tipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_equipo_tipo ON public.equipo USING btree (id_tipo_equipo);


--
-- Name: idx_equipo_ubicacion; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_equipo_ubicacion ON public.equipo USING btree (id_ubicacion_administrativa_actual);


--
-- Name: idx_evento_beacon_beacon; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_evento_beacon_beacon ON public.evento_beacon USING btree (id_beacon);


--
-- Name: idx_evento_beacon_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_evento_beacon_equipo ON public.evento_beacon USING btree (id_equipo);


--
-- Name: idx_evento_gps_gps; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_evento_gps_gps ON public.evento_gps USING btree (id_gps);


--
-- Name: idx_evento_nfc_nfc; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_evento_nfc_nfc ON public.evento_nfc USING btree (id_nfc);


--
-- Name: idx_mantenimiento_biomedico; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_mantenimiento_biomedico ON public.mantenimiento USING btree (id_biomedico);


--
-- Name: idx_mantenimiento_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_mantenimiento_equipo ON public.mantenimiento USING btree (id_equipo);


--
-- Name: idx_movimiento_destino; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movimiento_destino ON public.movimiento USING btree (id_ubicacion_destino);


--
-- Name: idx_movimiento_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movimiento_equipo ON public.movimiento USING btree (id_equipo);


--
-- Name: idx_movimiento_origen; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movimiento_origen ON public.movimiento USING btree (id_ubicacion_origen);


--
-- Name: idx_movimiento_persona; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movimiento_persona ON public.movimiento USING btree (id_persona_responsable_movimiento);


--
-- Name: idx_traslado_ambulancia; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_traslado_ambulancia ON public.traslado_externo_equipo USING btree (id_ambulancia);


--
-- Name: idx_traslado_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_traslado_equipo ON public.traslado_externo_equipo USING btree (id_equipo);


--
-- Name: idx_uso_equipo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_uso_equipo ON public.uso_clinico_equipo USING btree (id_equipo);


--
-- Name: idx_uso_persona; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_uso_persona ON public.uso_clinico_equipo USING btree (id_persona_responsable_uso);


--
-- Name: uq_asignacion_equipo_activa; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_asignacion_equipo_activa ON public.asignacion_equipo USING btree (id_equipo) WHERE (fecha_fin_asignacion IS NULL);


--
-- Name: uq_mantenimiento_programado_pendiente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_mantenimiento_programado_pendiente ON public.mantenimiento_programado USING btree (id_equipo, id_tipo_mantenimiento) WHERE (id_estado_cumplimiento = 1);


--
-- Name: uq_responsable_area_activo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_responsable_area_activo ON public.responsable_area USING btree (id_area) WHERE (fecha_fin_responsable_area IS NULL);


--
-- Name: uq_responsable_por_enfermero; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_responsable_por_enfermero ON public.responsable_area USING btree (id_enfermero) WHERE (fecha_fin_responsable_area IS NULL);


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

CREATE TRIGGER trg_validar_equipo_disponible_para_uso BEFORE INSERT OR UPDATE ON public.uso_clinico_equipo FOR EACH ROW EXECUTE FUNCTION public.fn_validar_equipo_disponible_para_uso();


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


--
-- Name: ambulancia ambulancia_id_estado_ambulancia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ambulancia
    ADD CONSTRAINT ambulancia_id_estado_ambulancia_fkey FOREIGN KEY (id_estado_ambulancia) REFERENCES public.estado_ambulancias(id_estado_ambulancia);


--
-- Name: asignacion_equipo asignacion_equipo_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo
    ADD CONSTRAINT asignacion_equipo_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: asignacion_equipo asignacion_equipo_id_estado_asignacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo
    ADD CONSTRAINT asignacion_equipo_id_estado_asignacion_fkey FOREIGN KEY (id_estado_asignacion) REFERENCES public.estado_asignacion(id_estado_asignacion);


--
-- Name: asignacion_equipo asignacion_equipo_id_persona_responsable_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo
    ADD CONSTRAINT asignacion_equipo_id_persona_responsable_fkey FOREIGN KEY (id_persona_responsable) REFERENCES public.persona(id_persona);


--
-- Name: asignacion_equipo asignacion_equipo_id_ubicacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asignacion_equipo
    ADD CONSTRAINT asignacion_equipo_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.ubicacion_especifica(id_ubicacion);


--
-- Name: auditoria auditoria_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.auditoria
    ADD CONSTRAINT auditoria_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: biomedico biomedico_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.biomedico
    ADD CONSTRAINT biomedico_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona);


--
-- Name: biomedico biomedico_id_turno_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.biomedico
    ADD CONSTRAINT biomedico_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.turnos(id_turno);


--
-- Name: dispositivo_beacon dispositivo_beacon_id_zona_beacon_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_beacon
    ADD CONSTRAINT dispositivo_beacon_id_zona_beacon_fkey FOREIGN KEY (id_zona_beacon) REFERENCES public.zona_beacon(id_zona_beacon);


--
-- Name: dispositivo_gps dispositivo_gps_id_ambulancia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_gps
    ADD CONSTRAINT dispositivo_gps_id_ambulancia_fkey FOREIGN KEY (id_ambulancia) REFERENCES public.ambulancia(id_ambulancia);


--
-- Name: dispositivo_nfc dispositivo_nfc_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dispositivo_nfc
    ADD CONSTRAINT dispositivo_nfc_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: enfermero enfermero_id_especialidad_enfermero_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero
    ADD CONSTRAINT enfermero_id_especialidad_enfermero_fkey FOREIGN KEY (id_especialidad_enfermero) REFERENCES public.especialidades_enfermero(id_especialidad_enfermero);


--
-- Name: enfermero enfermero_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero
    ADD CONSTRAINT enfermero_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona);


--
-- Name: enfermero enfermero_id_turno_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enfermero
    ADD CONSTRAINT enfermero_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.turnos(id_turno);


--
-- Name: equipo equipo_id_criticidad_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_id_criticidad_equipo_fkey FOREIGN KEY (id_criticidad_equipo) REFERENCES public.criticidad_equipos(id_criticidad_equipo);


--
-- Name: equipo equipo_id_estado_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_id_estado_equipo_fkey FOREIGN KEY (id_estado_equipo) REFERENCES public.estado_equipos(id_estado_equipo);


--
-- Name: equipo equipo_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.modelo_equipo(id_modelo);


--
-- Name: equipo equipo_id_tipo_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_id_tipo_equipo_fkey FOREIGN KEY (id_tipo_equipo) REFERENCES public.tipo_equipos(id_tipo_equipo);


--
-- Name: equipo equipo_id_ubicacion_administrativa_actual_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.equipo
    ADD CONSTRAINT equipo_id_ubicacion_administrativa_actual_fkey FOREIGN KEY (id_ubicacion_administrativa_actual) REFERENCES public.ubicacion_especifica(id_ubicacion);


--
-- Name: especialidad_area_enfermero especialidad_area_enfermero_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidad_area_enfermero
    ADD CONSTRAINT especialidad_area_enfermero_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.area_registro(id_area);


--
-- Name: especialidad_area_enfermero especialidad_area_enfermero_id_especialidad_enfermero_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.especialidad_area_enfermero
    ADD CONSTRAINT especialidad_area_enfermero_id_especialidad_enfermero_fkey FOREIGN KEY (id_especialidad_enfermero) REFERENCES public.especialidades_enfermero(id_especialidad_enfermero);


--
-- Name: evento_beacon evento_beacon_id_beacon_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_beacon
    ADD CONSTRAINT evento_beacon_id_beacon_fkey FOREIGN KEY (id_beacon) REFERENCES public.dispositivo_beacon(id_beacon);


--
-- Name: evento_beacon evento_beacon_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_beacon
    ADD CONSTRAINT evento_beacon_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: evento_beacon evento_beacon_id_tipo_evento_beacon_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_beacon
    ADD CONSTRAINT evento_beacon_id_tipo_evento_beacon_fkey FOREIGN KEY (id_tipo_evento_beacon) REFERENCES public.tipo_eventos_beacon(id_tipo_evento_beacon);


--
-- Name: evento_gps evento_gps_id_gps_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_gps
    ADD CONSTRAINT evento_gps_id_gps_fkey FOREIGN KEY (id_gps) REFERENCES public.dispositivo_gps(id_gps);


--
-- Name: evento_nfc evento_nfc_id_nfc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_nfc
    ADD CONSTRAINT evento_nfc_id_nfc_fkey FOREIGN KEY (id_nfc) REFERENCES public.dispositivo_nfc(id_nfc);


--
-- Name: evento_nfc evento_nfc_id_tipo_evento_nfc_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.evento_nfc
    ADD CONSTRAINT evento_nfc_id_tipo_evento_nfc_fkey FOREIGN KEY (id_tipo_evento_nfc) REFERENCES public.tipo_eventos_nfc(id_tipo_evento_nfc);


--
-- Name: mantenimiento mantenimiento_id_biomedico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_biomedico_fkey FOREIGN KEY (id_biomedico) REFERENCES public.biomedico(id_biomedico);


--
-- Name: mantenimiento mantenimiento_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: mantenimiento mantenimiento_id_programacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_programacion_fkey FOREIGN KEY (id_programacion) REFERENCES public.mantenimiento_programado(id_programacion);


--
-- Name: mantenimiento mantenimiento_id_resultado_mantenimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_resultado_mantenimiento_fkey FOREIGN KEY (id_resultado_mantenimiento) REFERENCES public.tipo_resultado_mantenimientos(id_resultado_mantenimiento);


--
-- Name: mantenimiento mantenimiento_id_tipo_mantenimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento
    ADD CONSTRAINT mantenimiento_id_tipo_mantenimiento_fkey FOREIGN KEY (id_tipo_mantenimiento) REFERENCES public.tipo_mantenimientos(id_tipo_mantenimiento);


--
-- Name: mantenimiento_programado mantenimiento_programado_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado
    ADD CONSTRAINT mantenimiento_programado_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: mantenimiento_programado mantenimiento_programado_id_estado_cumplimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado
    ADD CONSTRAINT mantenimiento_programado_id_estado_cumplimiento_fkey FOREIGN KEY (id_estado_cumplimiento) REFERENCES public.estado_cumplimiento_mantenimientos(id_estado_cumplimiento);


--
-- Name: mantenimiento_programado mantenimiento_programado_id_prioridad_mantenimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado
    ADD CONSTRAINT mantenimiento_programado_id_prioridad_mantenimiento_fkey FOREIGN KEY (id_prioridad_mantenimiento) REFERENCES public.prioridad_mantenimientos(id_prioridad_mantenimiento);


--
-- Name: mantenimiento_programado mantenimiento_programado_id_tipo_mantenimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.mantenimiento_programado
    ADD CONSTRAINT mantenimiento_programado_id_tipo_mantenimiento_fkey FOREIGN KEY (id_tipo_mantenimiento) REFERENCES public.tipo_mantenimientos(id_tipo_mantenimiento);


--
-- Name: medico medico_id_especialidad_medico_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_id_especialidad_medico_fkey FOREIGN KEY (id_especialidad_medico) REFERENCES public.especialidades_medico(id_especialidad_medico);


--
-- Name: medico medico_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona);


--
-- Name: medico medico_id_turno_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.medico
    ADD CONSTRAINT medico_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.turnos(id_turno);


--
-- Name: modelo_equipo modelo_equipo_id_marca_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelo_equipo
    ADD CONSTRAINT modelo_equipo_id_marca_fkey FOREIGN KEY (id_marca) REFERENCES public.marca_equipo(id_marca);


--
-- Name: movimiento movimiento_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: movimiento movimiento_id_persona_responsable_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_id_persona_responsable_movimiento_fkey FOREIGN KEY (id_persona_responsable_movimiento) REFERENCES public.persona(id_persona);


--
-- Name: movimiento movimiento_id_tipo_movimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_id_tipo_movimiento_fkey FOREIGN KEY (id_tipo_movimiento) REFERENCES public.tipo_movimientos(id_tipo_movimiento);


--
-- Name: movimiento movimiento_id_ubicacion_destino_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_id_ubicacion_destino_fkey FOREIGN KEY (id_ubicacion_destino) REFERENCES public.ubicacion_especifica(id_ubicacion);


--
-- Name: movimiento movimiento_id_ubicacion_origen_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movimiento
    ADD CONSTRAINT movimiento_id_ubicacion_origen_fkey FOREIGN KEY (id_ubicacion_origen) REFERENCES public.ubicacion_especifica(id_ubicacion);


--
-- Name: responsable_area responsable_area_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.responsable_area
    ADD CONSTRAINT responsable_area_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.area_registro(id_area);


--
-- Name: responsable_area responsable_area_id_enfermero_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.responsable_area
    ADD CONSTRAINT responsable_area_id_enfermero_fkey FOREIGN KEY (id_enfermero) REFERENCES public.enfermero(id_enfermero);


--
-- Name: tipo_equipos tipo_equipos_id_categoria_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_equipos
    ADD CONSTRAINT tipo_equipos_id_categoria_equipo_fkey FOREIGN KEY (id_categoria_equipo) REFERENCES public.categoria_equipos(id_categoria_equipo);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_id_ambulancia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_id_ambulancia_fkey FOREIGN KEY (id_ambulancia) REFERENCES public.ambulancia(id_ambulancia);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_id_nfc_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_id_nfc_equipo_fkey FOREIGN KEY (id_nfc_equipo) REFERENCES public.dispositivo_nfc(id_nfc);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_id_persona_conductor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_id_persona_conductor_fkey FOREIGN KEY (id_persona_conductor) REFERENCES public.persona(id_persona);


--
-- Name: traslado_externo_equipo traslado_externo_equipo_id_tipo_traslado_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.traslado_externo_equipo
    ADD CONSTRAINT traslado_externo_equipo_id_tipo_traslado_fkey FOREIGN KEY (id_tipo_traslado) REFERENCES public.tipo_traslado_externo(id_tipo_traslado);


--
-- Name: ubicacion_especifica ubicacion_especifica_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.ubicacion_especifica
    ADD CONSTRAINT ubicacion_especifica_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.area_registro(id_area);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_id_area_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_id_area_fkey FOREIGN KEY (id_area) REFERENCES public.area_registro(id_area);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_id_equipo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_id_equipo_fkey FOREIGN KEY (id_equipo) REFERENCES public.equipo(id_equipo);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_id_persona_responsable_uso_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_id_persona_responsable_uso_fkey FOREIGN KEY (id_persona_responsable_uso) REFERENCES public.persona(id_persona);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_id_tipo_procedimiento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_id_tipo_procedimiento_fkey FOREIGN KEY (id_tipo_procedimiento) REFERENCES public.tipo_procedimiento(id_tipo_procedimiento);


--
-- Name: uso_clinico_equipo uso_clinico_equipo_id_turno_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.uso_clinico_equipo
    ADD CONSTRAINT uso_clinico_equipo_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.turnos(id_turno);


--
-- Name: usuario usuario_id_persona_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_id_persona_fkey FOREIGN KEY (id_persona) REFERENCES public.persona(id_persona);


--
-- Name: usuario_rol usuario_rol_id_rol_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_rol_usuario_fkey FOREIGN KEY (id_rol_usuario) REFERENCES public.roles_usuario(id_rol_usuario);


--
-- Name: usuario_rol usuario_rol_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario_rol
    ADD CONSTRAINT usuario_rol_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuario(id_usuario);


--
-- Name: zona_beacon zona_beacon_id_ubicacion_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona_beacon
    ADD CONSTRAINT zona_beacon_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.ubicacion_especifica(id_ubicacion);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT ALL ON SCHEMA public TO hospital_user;


--
-- Name: FUNCTION fn_actualizar_estado_equipo_por_mantenimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_actualizar_estado_equipo_por_mantenimiento() TO hospital_user;


--
-- Name: FUNCTION fn_actualizar_ubicacion_equipo_por_movimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_actualizar_ubicacion_equipo_por_movimiento() TO hospital_user;


--
-- Name: FUNCTION fn_auditoria_generica(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_auditoria_generica() TO hospital_user;


--
-- Name: FUNCTION fn_devolver_equipo_tras_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_devolver_equipo_tras_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_retirar_equipo_tras_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_retirar_equipo_tras_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_validar_ambulancia_activa_para_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_ambulancia_activa_para_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_validar_beacon_activo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_beacon_activo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_condiciones_retiro_equipo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_condiciones_retiro_equipo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_conductor_autorizado_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_conductor_autorizado_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_validar_equipo_disponible_para_uso(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_equipo_disponible_para_uso() TO hospital_user;


--
-- Name: FUNCTION fn_validar_equipo_no_retirado_en_evento_beacon(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_equipo_no_retirado_en_evento_beacon() TO hospital_user;


--
-- Name: FUNCTION fn_validar_equipo_no_retirado_en_evento_nfc(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_equipo_no_retirado_en_evento_nfc() TO hospital_user;


--
-- Name: FUNCTION fn_validar_equipo_no_retirado_en_movimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_equipo_no_retirado_en_movimiento() TO hospital_user;


--
-- Name: FUNCTION fn_validar_equipo_sin_uso_clinico_activo_para_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_equipo_sin_uso_clinico_activo_para_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_validar_especialidad_responsable_area(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_especialidad_responsable_area() TO hospital_user;


--
-- Name: FUNCTION fn_validar_gps_activo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_gps_activo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_mantenimiento_biomedico(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_mantenimiento_biomedico() TO hospital_user;


--
-- Name: FUNCTION fn_validar_nfc_activo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_nfc_activo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_nfc_equipo_traslado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_nfc_equipo_traslado() TO hospital_user;


--
-- Name: FUNCTION fn_validar_origen_movimiento_coherente(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_origen_movimiento_coherente() TO hospital_user;


--
-- Name: FUNCTION fn_validar_persona_responsable_movimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_persona_responsable_movimiento() TO hospital_user;


--
-- Name: FUNCTION fn_validar_sin_uso_clinico_activo_para_mantenimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_sin_uso_clinico_activo_para_mantenimiento() TO hospital_user;


--
-- Name: FUNCTION fn_validar_traslape_asignacion_equipo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_traslape_asignacion_equipo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_traslape_responsable_area(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_traslape_responsable_area() TO hospital_user;


--
-- Name: FUNCTION fn_validar_turno_mantenimiento(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_turno_mantenimiento() TO hospital_user;


--
-- Name: FUNCTION fn_validar_turno_uso_clinico(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_turno_uso_clinico() TO hospital_user;


--
-- Name: FUNCTION fn_validar_unico_uso_clinico_activo(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_unico_uso_clinico_activo() TO hospital_user;


--
-- Name: FUNCTION fn_validar_uso_clinico_personal_autorizado(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.fn_validar_uso_clinico_personal_autorizado() TO hospital_user;


--
-- Name: PROCEDURE sp_asignar_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_ubicacion integer, OUT p_id_asignacion integer, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_asignar_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_ubicacion integer, OUT p_id_asignacion integer, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_cambiar_estado_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nuevo_estado integer, OUT p_mensaje text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cambiar_estado_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nuevo_estado integer, OUT p_mensaje text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_cambiar_estado_usuario(IN p_id_usuario integer, IN p_id_usuario_target integer, IN p_activo boolean, OUT p_mensaje text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cambiar_estado_usuario(IN p_id_usuario integer, IN p_id_usuario_target integer, IN p_activo boolean, OUT p_mensaje text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_cambiar_responsable_area(IN p_id_usuario integer, IN p_id_area integer, IN p_id_enfermero_nuevo integer, OUT p_mensaje text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cambiar_responsable_area(IN p_id_usuario integer, IN p_id_area integer, IN p_id_enfermero_nuevo integer, OUT p_mensaje text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_cerrar_asignacion_equipo(IN p_id_usuario integer, IN p_id_asignacion integer, OUT p_mensaje text, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cerrar_asignacion_equipo(IN p_id_usuario integer, IN p_id_asignacion integer, OUT p_mensaje text, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_cerrar_uso_clinico(IN p_id_usuario integer, IN p_id_uso_clinico integer, OUT p_mensaje text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cerrar_uso_clinico(IN p_id_usuario integer, IN p_id_uso_clinico integer, OUT p_mensaje text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_crear_persona(IN p_id_usuario integer, IN p_nombre text, IN p_apellido text, IN p_correo text, OUT p_id_persona integer, OUT p_mensaje text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_crear_persona(IN p_id_usuario integer, IN p_nombre text, IN p_apellido text, IN p_correo text, OUT p_id_persona integer, OUT p_mensaje text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_historial_equipo(IN p_id_usuario integer, IN p_id_equipo integer, INOUT p_resultado refcursor); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_historial_equipo(IN p_id_usuario integer, IN p_id_equipo integer, INOUT p_resultado refcursor) TO hospital_user;


--
-- Name: PROCEDURE sp_registrar_equipo(IN p_id_usuario integer, IN p_codigo_interno character varying, IN p_nombre_equipo character varying, IN p_id_modelo integer, IN p_numero_serie character varying, IN p_id_tipo_equipo integer, IN p_id_criticidad integer, IN p_id_ubicacion integer, IN p_codigo_uid_nfc character varying, OUT p_id_equipo integer, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_registrar_equipo(IN p_id_usuario integer, IN p_codigo_interno character varying, IN p_nombre_equipo character varying, IN p_id_modelo integer, IN p_numero_serie character varying, IN p_id_tipo_equipo integer, IN p_id_criticidad integer, IN p_id_ubicacion integer, IN p_codigo_uid_nfc character varying, OUT p_id_equipo integer, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_registrar_mantenimiento(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_biomedico integer, IN p_id_tipo_mantenimiento integer, IN p_descripcion text, IN p_id_resultado_mantenimiento integer, OUT p_id_mantenimiento integer, IN p_id_programacion integer, IN p_costo numeric, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_registrar_mantenimiento(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_biomedico integer, IN p_id_tipo_mantenimiento integer, IN p_descripcion text, IN p_id_resultado_mantenimiento integer, OUT p_id_mantenimiento integer, IN p_id_programacion integer, IN p_costo numeric, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_registrar_movimiento_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable_movimiento integer, IN p_id_tipo_movimiento integer, IN p_id_ubicacion_origen integer, IN p_id_ubicacion_destino integer, OUT p_id_movimiento integer, IN p_motivo text, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_registrar_movimiento_equipo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable_movimiento integer, IN p_id_tipo_movimiento integer, IN p_id_ubicacion_origen integer, IN p_id_ubicacion_destino integer, OUT p_id_movimiento integer, IN p_motivo text, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_registrar_traslado_externo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nfc_equipo integer, IN p_id_ambulancia integer, IN p_id_persona_conductor integer, IN p_id_tipo_traslado integer, OUT p_id_traslado integer, IN p_motivo text, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_registrar_traslado_externo(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_nfc_equipo integer, IN p_id_ambulancia integer, IN p_id_persona_conductor integer, IN p_id_tipo_traslado integer, OUT p_id_traslado integer, IN p_motivo text, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_registrar_uso_clinico(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_area integer, IN p_id_turno integer, IN p_id_tipo_procedimiento integer, OUT p_id_uso_clinico integer, IN p_motivo text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_registrar_uso_clinico(IN p_id_usuario integer, IN p_id_equipo integer, IN p_id_persona_responsable integer, IN p_id_area integer, IN p_id_turno integer, IN p_id_tipo_procedimiento integer, OUT p_id_uso_clinico integer, IN p_motivo text, IN p_origen text) TO hospital_user;


--
-- Name: PROCEDURE sp_reporte_carga_biomedica(IN p_id_usuario integer, IN p_fecha_inicio timestamp without time zone, IN p_fecha_fin timestamp without time zone, INOUT p_resultado refcursor); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_reporte_carga_biomedica(IN p_id_usuario integer, IN p_fecha_inicio timestamp without time zone, IN p_fecha_fin timestamp without time zone, INOUT p_resultado refcursor) TO hospital_user;


--
-- Name: PROCEDURE sp_reprogramar_mantenimiento(IN p_id_usuario integer, IN p_id_programacion integer, IN p_nueva_fecha timestamp without time zone, OUT p_mensaje text, IN p_observacion text, IN p_origen text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_reprogramar_mantenimiento(IN p_id_usuario integer, IN p_id_programacion integer, IN p_nueva_fecha timestamp without time zone, OUT p_mensaje text, IN p_observacion text, IN p_origen text) TO hospital_user;


--
-- Name: TABLE ambulancia; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.ambulancia TO hospital_user;


--
-- Name: SEQUENCE ambulancia_id_ambulancia_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.ambulancia_id_ambulancia_seq TO hospital_user;


--
-- Name: TABLE area_registro; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.area_registro TO hospital_user;


--
-- Name: SEQUENCE area_registro_id_area_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.area_registro_id_area_seq TO hospital_user;


--
-- Name: TABLE asignacion_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.asignacion_equipo TO hospital_user;


--
-- Name: SEQUENCE asignacion_equipo_id_asignacion_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.asignacion_equipo_id_asignacion_seq TO hospital_user;


--
-- Name: TABLE auditoria; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.auditoria TO hospital_user;


--
-- Name: SEQUENCE auditoria_id_auditoria_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.auditoria_id_auditoria_seq TO hospital_user;


--
-- Name: TABLE biomedico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.biomedico TO hospital_user;


--
-- Name: SEQUENCE biomedico_id_biomedico_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.biomedico_id_biomedico_seq TO hospital_user;


--
-- Name: TABLE categoria_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.categoria_equipos TO hospital_user;


--
-- Name: SEQUENCE categoria_equipos_id_categoria_equipo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.categoria_equipos_id_categoria_equipo_seq TO hospital_user;


--
-- Name: TABLE criticidad_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.criticidad_equipos TO hospital_user;


--
-- Name: SEQUENCE criticidad_equipos_id_criticidad_equipo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.criticidad_equipos_id_criticidad_equipo_seq TO hospital_user;


--
-- Name: TABLE dispositivo_beacon; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.dispositivo_beacon TO hospital_user;


--
-- Name: SEQUENCE dispositivo_beacon_id_beacon_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.dispositivo_beacon_id_beacon_seq TO hospital_user;


--
-- Name: TABLE dispositivo_gps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.dispositivo_gps TO hospital_user;


--
-- Name: SEQUENCE dispositivo_gps_id_gps_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.dispositivo_gps_id_gps_seq TO hospital_user;


--
-- Name: TABLE dispositivo_nfc; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.dispositivo_nfc TO hospital_user;


--
-- Name: SEQUENCE dispositivo_nfc_id_nfc_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.dispositivo_nfc_id_nfc_seq TO hospital_user;


--
-- Name: TABLE enfermero; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.enfermero TO hospital_user;


--
-- Name: SEQUENCE enfermero_id_enfermero_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.enfermero_id_enfermero_seq TO hospital_user;


--
-- Name: TABLE equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.equipo TO hospital_user;


--
-- Name: SEQUENCE equipo_id_equipo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.equipo_id_equipo_seq TO hospital_user;


--
-- Name: TABLE especialidad_area_enfermero; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.especialidad_area_enfermero TO hospital_user;


--
-- Name: TABLE especialidades_enfermero; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.especialidades_enfermero TO hospital_user;


--
-- Name: SEQUENCE especialidades_enfermero_id_especialidad_enfermero_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.especialidades_enfermero_id_especialidad_enfermero_seq TO hospital_user;


--
-- Name: TABLE especialidades_medico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.especialidades_medico TO hospital_user;


--
-- Name: SEQUENCE especialidades_medico_id_especialidad_medico_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.especialidades_medico_id_especialidad_medico_seq TO hospital_user;


--
-- Name: TABLE estado_ambulancias; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estado_ambulancias TO hospital_user;


--
-- Name: SEQUENCE estado_ambulancias_id_estado_ambulancia_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.estado_ambulancias_id_estado_ambulancia_seq TO hospital_user;


--
-- Name: TABLE estado_asignacion; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estado_asignacion TO hospital_user;


--
-- Name: SEQUENCE estado_asignacion_id_estado_asignacion_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.estado_asignacion_id_estado_asignacion_seq TO hospital_user;


--
-- Name: TABLE estado_cumplimiento_mantenimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estado_cumplimiento_mantenimientos TO hospital_user;


--
-- Name: SEQUENCE estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.estado_cumplimiento_mantenimientos_id_estado_cumplimiento_seq TO hospital_user;


--
-- Name: TABLE estado_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.estado_equipos TO hospital_user;


--
-- Name: SEQUENCE estado_equipos_id_estado_equipo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.estado_equipos_id_estado_equipo_seq TO hospital_user;


--
-- Name: TABLE evento_beacon; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.evento_beacon TO hospital_user;


--
-- Name: SEQUENCE evento_beacon_id_evento_beacon_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.evento_beacon_id_evento_beacon_seq TO hospital_user;


--
-- Name: TABLE evento_gps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.evento_gps TO hospital_user;


--
-- Name: SEQUENCE evento_gps_id_evento_gps_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.evento_gps_id_evento_gps_seq TO hospital_user;


--
-- Name: TABLE evento_nfc; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.evento_nfc TO hospital_user;


--
-- Name: SEQUENCE evento_nfc_id_evento_nfc_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.evento_nfc_id_evento_nfc_seq TO hospital_user;


--
-- Name: TABLE mantenimiento; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.mantenimiento TO hospital_user;


--
-- Name: SEQUENCE mantenimiento_id_mantenimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.mantenimiento_id_mantenimiento_seq TO hospital_user;


--
-- Name: TABLE mantenimiento_programado; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.mantenimiento_programado TO hospital_user;


--
-- Name: SEQUENCE mantenimiento_programado_id_programacion_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.mantenimiento_programado_id_programacion_seq TO hospital_user;


--
-- Name: TABLE marca_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.marca_equipo TO hospital_user;


--
-- Name: SEQUENCE marca_equipo_id_marca_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.marca_equipo_id_marca_seq TO hospital_user;


--
-- Name: TABLE medico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.medico TO hospital_user;


--
-- Name: SEQUENCE medico_id_medico_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.medico_id_medico_seq TO hospital_user;


--
-- Name: TABLE modelo_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.modelo_equipo TO hospital_user;


--
-- Name: SEQUENCE modelo_equipo_id_modelo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.modelo_equipo_id_modelo_seq TO hospital_user;


--
-- Name: TABLE movimiento; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.movimiento TO hospital_user;


--
-- Name: SEQUENCE movimiento_id_movimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.movimiento_id_movimiento_seq TO hospital_user;


--
-- Name: TABLE persona; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.persona TO hospital_user;


--
-- Name: SEQUENCE persona_id_persona_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.persona_id_persona_seq TO hospital_user;


--
-- Name: TABLE prioridad_mantenimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.prioridad_mantenimientos TO hospital_user;


--
-- Name: SEQUENCE prioridad_mantenimientos_id_prioridad_mantenimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.prioridad_mantenimientos_id_prioridad_mantenimiento_seq TO hospital_user;


--
-- Name: TABLE responsable_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.responsable_area TO hospital_user;


--
-- Name: SEQUENCE responsable_area_id_responsable_area_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.responsable_area_id_responsable_area_seq TO hospital_user;


--
-- Name: TABLE roles_usuario; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.roles_usuario TO hospital_user;


--
-- Name: SEQUENCE roles_usuario_id_rol_usuario_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.roles_usuario_id_rol_usuario_seq TO hospital_user;


--
-- Name: TABLE tipo_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_equipos TO hospital_user;


--
-- Name: SEQUENCE tipo_equipos_id_tipo_equipo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_equipos_id_tipo_equipo_seq TO hospital_user;


--
-- Name: TABLE tipo_eventos_beacon; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_eventos_beacon TO hospital_user;


--
-- Name: SEQUENCE tipo_eventos_beacon_id_tipo_evento_beacon_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_eventos_beacon_id_tipo_evento_beacon_seq TO hospital_user;


--
-- Name: TABLE tipo_eventos_nfc; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_eventos_nfc TO hospital_user;


--
-- Name: SEQUENCE tipo_eventos_nfc_id_tipo_evento_nfc_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_eventos_nfc_id_tipo_evento_nfc_seq TO hospital_user;


--
-- Name: TABLE tipo_mantenimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_mantenimientos TO hospital_user;


--
-- Name: SEQUENCE tipo_mantenimientos_id_tipo_mantenimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_mantenimientos_id_tipo_mantenimiento_seq TO hospital_user;


--
-- Name: TABLE tipo_movimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_movimientos TO hospital_user;


--
-- Name: SEQUENCE tipo_movimientos_id_tipo_movimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_movimientos_id_tipo_movimiento_seq TO hospital_user;


--
-- Name: TABLE tipo_procedimiento; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_procedimiento TO hospital_user;


--
-- Name: SEQUENCE tipo_procedimiento_id_tipo_procedimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_procedimiento_id_tipo_procedimiento_seq TO hospital_user;


--
-- Name: TABLE tipo_resultado_mantenimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_resultado_mantenimientos TO hospital_user;


--
-- Name: SEQUENCE tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_resultado_mantenimientos_id_resultado_mantenimiento_seq TO hospital_user;


--
-- Name: TABLE tipo_traslado_externo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tipo_traslado_externo TO hospital_user;


--
-- Name: SEQUENCE tipo_traslado_externo_id_tipo_traslado_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tipo_traslado_externo_id_tipo_traslado_seq TO hospital_user;


--
-- Name: TABLE traslado_externo_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.traslado_externo_equipo TO hospital_user;


--
-- Name: SEQUENCE traslado_externo_equipo_id_traslado_externo_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.traslado_externo_equipo_id_traslado_externo_seq TO hospital_user;


--
-- Name: TABLE turnos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.turnos TO hospital_user;


--
-- Name: SEQUENCE turnos_id_turno_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.turnos_id_turno_seq TO hospital_user;


--
-- Name: TABLE ubicacion_especifica; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.ubicacion_especifica TO hospital_user;


--
-- Name: SEQUENCE ubicacion_especifica_id_ubicacion_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.ubicacion_especifica_id_ubicacion_seq TO hospital_user;


--
-- Name: TABLE uso_clinico_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.uso_clinico_equipo TO hospital_user;


--
-- Name: SEQUENCE uso_clinico_equipo_id_uso_clinico_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.uso_clinico_equipo_id_uso_clinico_seq TO hospital_user;


--
-- Name: TABLE usuario; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usuario TO hospital_user;


--
-- Name: SEQUENCE usuario_id_usuario_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.usuario_id_usuario_seq TO hospital_user;


--
-- Name: TABLE usuario_rol; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.usuario_rol TO hospital_user;


--
-- Name: TABLE v_actividad_sistema_por_usuario; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_actividad_sistema_por_usuario TO hospital_user;


--
-- Name: TABLE v_admin_areas_sin_responsable; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_admin_areas_sin_responsable TO hospital_user;


--
-- Name: TABLE v_admin_auditoria_reciente; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_admin_auditoria_reciente TO hospital_user;


--
-- Name: TABLE v_admin_estado_ambulancias; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_admin_estado_ambulancias TO hospital_user;


--
-- Name: TABLE v_admin_inventario_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_admin_inventario_equipos TO hospital_user;


--
-- Name: TABLE v_alertas_preventivas; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_alertas_preventivas TO hospital_user;


--
-- Name: TABLE v_asignaciones_activas; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_asignaciones_activas TO hospital_user;


--
-- Name: TABLE v_biomedico_historial_mantenimientos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_biomedico_historial_mantenimientos TO hospital_user;


--
-- Name: TABLE v_carga_biomedico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_carga_biomedico TO hospital_user;


--
-- Name: TABLE zona_beacon; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.zona_beacon TO hospital_user;


--
-- Name: TABLE v_discrepancia_ubicacion_iot; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_discrepancia_ubicacion_iot TO hospital_user;


--
-- Name: TABLE v_disponibilidad_equipos_por_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_disponibilidad_equipos_por_area TO hospital_user;


--
-- Name: TABLE v_disponibilidad_por_tipo_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_disponibilidad_por_tipo_equipo TO hospital_user;


--
-- Name: TABLE v_equipos_activos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_activos TO hospital_user;


--
-- Name: TABLE v_equipos_alta_demanda; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_alta_demanda TO hospital_user;


--
-- Name: TABLE v_equipos_candidatos_reemplazo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_candidatos_reemplazo TO hospital_user;


--
-- Name: TABLE v_equipos_criticos_no_disponibles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_criticos_no_disponibles TO hospital_user;


--
-- Name: TABLE v_equipos_disponibles_uso_clinico; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_disponibles_uso_clinico TO hospital_user;


--
-- Name: TABLE v_equipos_por_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_por_area TO hospital_user;


--
-- Name: TABLE v_equipos_sin_evidencia_iot; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_equipos_sin_evidencia_iot TO hospital_user;


--
-- Name: TABLE v_historial_responsable_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_historial_responsable_area TO hospital_user;


--
-- Name: TABLE v_historial_tecnico_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_historial_tecnico_equipos TO hospital_user;


--
-- Name: TABLE v_historial_traslados_externos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_historial_traslados_externos TO hospital_user;


--
-- Name: TABLE v_historial_uso_clinico_por_persona; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_historial_uso_clinico_por_persona TO hospital_user;


--
-- Name: TABLE v_mantenimiento_correctivo_estado_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_mantenimiento_correctivo_estado_equipo TO hospital_user;


--
-- Name: TABLE v_mantenimientos_programados_pendientes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_mantenimientos_programados_pendientes TO hospital_user;


--
-- Name: TABLE v_mantenimientos_proximos_a_vencer; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_mantenimientos_proximos_a_vencer TO hospital_user;


--
-- Name: TABLE v_mantenimientos_proximos_por_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_mantenimientos_proximos_por_area TO hospital_user;


--
-- Name: TABLE v_mantenimientos_vencidos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_mantenimientos_vencidos TO hospital_user;


--
-- Name: TABLE v_movimientos_recientes_por_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_movimientos_recientes_por_area TO hospital_user;


--
-- Name: TABLE v_responsables_activos_por_area; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_responsables_activos_por_area TO hospital_user;


--
-- Name: TABLE v_resumen_actividad_equipos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_resumen_actividad_equipos TO hospital_user;


--
-- Name: TABLE v_ultimo_movimiento_equipos_criticos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_ultimo_movimiento_equipos_criticos TO hospital_user;


--
-- Name: TABLE v_ultimo_movimiento_por_equipo; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_ultimo_movimiento_por_equipo TO hospital_user;


--
-- Name: SEQUENCE zona_beacon_id_zona_beacon_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.zona_beacon_id_zona_beacon_seq TO hospital_user;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO hospital_user;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO hospital_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: hospital_user
--

ALTER DEFAULT PRIVILEGES FOR ROLE hospital_user IN SCHEMA public GRANT ALL ON TABLES TO hospital_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO hospital_user;


--
-- PostgreSQL database dump complete
--

\unrestrict BuAo9hq1T8QP3a6bHbhfL8X5z9cxY6BOEd9ozQdbkrug4uh1htyzVjoQ1eqCTga

