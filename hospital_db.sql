--
-- PostgreSQL database dump
--

\restrict FrQF3yEITzUTB6UUzyeG2wCh50eGHKfTSSHirfOgQM2lNfZKEBPoGXmXrLo1310

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
-- Name: sp_cerrar_traslado(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cerrar_traslado(IN p_id_traslado integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE traslado_externo_equipo
    SET fecha_llegada = NOW()
    WHERE id_traslado_externo = p_id_traslado
      AND fecha_llegada IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Traslado % no encontrado o ya cerrado', p_id_traslado;
    END IF;
END;
$$;


ALTER PROCEDURE public.sp_cerrar_traslado(IN p_id_traslado integer) OWNER TO postgres;

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
-- Name: sp_eliminar_beacon(integer, integer, text); Type: PROCEDURE; Schema: public; Owner: hospital_user
--

CREATE PROCEDURE public.sp_eliminar_beacon(IN p_id_usuario integer, IN p_id_beacon integer, OUT p_mensaje text, IN p_origen text DEFAULT 'web_admin'::text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_existe         BOOLEAN;
    v_eventos_vinc   INTEGER;
BEGIN
    SELECT EXISTS(SELECT 1 FROM dispositivo_beacon WHERE id_beacon = p_id_beacon)
    INTO v_existe;

    IF NOT v_existe THEN
        RAISE EXCEPTION 'sp_eliminar_beacon: El beacon con id % no existe.', p_id_beacon;
    END IF;

    SELECT COUNT(*) INTO v_eventos_vinc
    FROM evento_beacon
    WHERE id_beacon = p_id_beacon;

    IF v_eventos_vinc > 0 THEN
        RAISE EXCEPTION
            'sp_eliminar_beacon: No se puede eliminar un beacon con % evento(s) registrado(s). Desactívalo en su lugar.',
            v_eventos_vinc;
    END IF;

    DELETE FROM dispositivo_beacon WHERE id_beacon = p_id_beacon;
    p_mensaje := 'Beacon eliminado correctamente.';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'sp_eliminar_beacon: %', SQLERRM;
END;
$$;


ALTER PROCEDURE public.sp_eliminar_beacon(IN p_id_usuario integer, IN p_id_beacon integer, OUT p_mensaje text, IN p_origen text) OWNER TO hospital_user;

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

    DROP TABLE IF EXISTS tmp_historial;
    CREATE TEMP TABLE tmp_historial (
        tipo_evento      TEXT,
        fecha_hora       TIMESTAMP,
        descripcion_tipo TEXT,
        origen           TEXT,
        destino          TEXT,
        responsable      TEXT,
        detalle          TEXT,
        costo            NUMERIC
    );

    INSERT INTO tmp_historial
    SELECT 'Movimiento', m.fecha_hora_movimiento, tm.tipo_movimiento,
           uo.nombre_ubicacion, ud.nombre_ubicacion,
           CONCAT(p.nombre_persona, ' ', p.apellido_persona),
           m.motivo_movimiento, NULL::NUMERIC
    FROM movimiento m
    JOIN tipo_movimientos tm     ON tm.id_tipo_movimiento  = m.id_tipo_movimiento
    JOIN ubicacion_especifica uo ON uo.id_ubicacion        = m.id_ubicacion_origen
    JOIN ubicacion_especifica ud ON ud.id_ubicacion        = m.id_ubicacion_destino
    JOIN persona p               ON p.id_persona           = m.id_persona_responsable_movimiento
    WHERE m.id_equipo = p_id_equipo;

    INSERT INTO tmp_historial
    SELECT 'Mantenimiento', mt.fecha_hora_mantenimiento, tm.tipo_mantenimiento,
           NULL, trm.resultado_mantenimiento,
           CONCAT(p.nombre_persona, ' ', p.apellido_persona),
           mt.descripcion_mantenimiento, mt.costo_mantenimiento
    FROM mantenimiento mt
    JOIN tipo_mantenimientos tm            ON tm.id_tipo_mantenimiento       = mt.id_tipo_mantenimiento
    JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = mt.id_resultado_mantenimiento
    JOIN biomedico b                       ON b.id_biomedico                 = mt.id_biomedico
    JOIN persona p                         ON p.id_persona                   = b.id_persona
    WHERE mt.id_equipo = p_id_equipo;

    INSERT INTO tmp_historial
    SELECT 'Uso Clinico', uce.fecha_hora_inicio, tp.tipo_procedimiento,
           NULL, ar.nombre_area,
           CONCAT(p.nombre_persona, ' ', p.apellido_persona),
           uce.motivo_uso, NULL::NUMERIC
    FROM uso_clinico_equipo uce
    JOIN tipo_procedimiento tp ON tp.id_tipo_procedimiento = uce.id_tipo_procedimiento
    JOIN area_registro ar      ON ar.id_area               = uce.id_area
    JOIN persona p             ON p.id_persona             = uce.id_persona_responsable_uso
    WHERE uce.id_equipo = p_id_equipo;

    OPEN p_resultado FOR
        SELECT * FROM tmp_historial ORDER BY fecha_hora DESC;
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

    -- Contexto del mantenimiento a registrar
    DROP TABLE IF EXISTS tmp_mant_ctx;
    CREATE TEMP TABLE tmp_mant_ctx (
        id_equipo                  INT,
        nombre_equipo              VARCHAR,
        id_biomedico               INT,
        biomedico                  TEXT,
        tipo_mantenimiento         VARCHAR,
        id_resultado_mantenimiento INT,
        resultado_mantenimiento    VARCHAR,
        costo                      NUMERIC
    );

    INSERT INTO tmp_mant_ctx
    SELECT
        e.id_equipo, e.nombre_equipo,
        b.id_biomedico,
        CONCAT(p.nombre_persona, ' ', p.apellido_persona),
        tm.tipo_mantenimiento,
        trm.id_resultado_mantenimiento,
        trm.resultado_mantenimiento,
        p_costo
    FROM equipo e
    JOIN biomedico b                       ON b.id_biomedico             = p_id_biomedico
    JOIN persona p                         ON p.id_persona               = b.id_persona
    JOIN tipo_mantenimientos tm            ON tm.id_tipo_mantenimiento   = p_id_tipo_mantenimiento
    JOIN tipo_resultado_mantenimientos trm ON trm.id_resultado_mantenimiento = p_id_resultado_mantenimiento
    WHERE e.id_equipo = p_id_equipo;

    INSERT INTO mantenimiento (
        id_equipo, id_biomedico, fecha_hora_mantenimiento,
        id_programacion, id_tipo_mantenimiento,
        descripcion_mantenimiento, id_resultado_mantenimiento,
        costo_mantenimiento, observacion_mantenimiento
    )
    SELECT
        ctx.id_equipo, ctx.id_biomedico, NOW(),
        p_id_programacion, p_id_tipo_mantenimiento,
        p_descripcion, ctx.id_resultado_mantenimiento,
        ctx.costo, p_observacion
    FROM tmp_mant_ctx ctx
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

    -- Contexto del movimiento a registrar
    DROP TABLE IF EXISTS tmp_mov_ctx;
    CREATE TEMP TABLE tmp_mov_ctx (
        id_equipo        INT,
        nombre_equipo    VARCHAR,
        nombre_origen    VARCHAR,
        area_origen      VARCHAR,
        nombre_destino   VARCHAR,
        area_destino     VARCHAR,
        tipo_movimiento  VARCHAR,
        responsable      TEXT
    );

    INSERT INTO tmp_mov_ctx
    SELECT
        e.id_equipo, e.nombre_equipo,
        uo.nombre_ubicacion, ao.nombre_area,
        ud.nombre_ubicacion, ad.nombre_area,
        tm.tipo_movimiento,
        CONCAT(p.nombre_persona, ' ', p.apellido_persona)
    FROM equipo e
    JOIN ubicacion_especifica uo ON uo.id_ubicacion        = p_id_ubicacion_origen
    JOIN area_registro ao        ON ao.id_area             = uo.id_area
    JOIN ubicacion_especifica ud ON ud.id_ubicacion        = p_id_ubicacion_destino
    JOIN area_registro ad        ON ad.id_area             = ud.id_area
    JOIN tipo_movimientos tm     ON tm.id_tipo_movimiento  = p_id_tipo_movimiento
    JOIN persona p               ON p.id_persona           = p_id_persona_responsable_movimiento
    WHERE e.id_equipo = p_id_equipo AND e.activo_equipo = TRUE;

    -- Triggers BEFORE validan: estado retirado, rol responsable, coherencia origen
    -- Trigger AFTER actualiza: ubicación administrativa del equipo
    INSERT INTO movimiento (
        id_equipo, id_persona_responsable_movimiento,
        fecha_hora_movimiento, id_tipo_movimiento,
        id_ubicacion_origen, id_ubicacion_destino,
        motivo_movimiento, observacion_movimiento
    )
    SELECT
        ctx.id_equipo, p_id_persona_responsable_movimiento,
        NOW(), p_id_tipo_movimiento,
        p_id_ubicacion_origen, p_id_ubicacion_destino,
        p_motivo, p_observacion
    FROM tmp_mov_ctx ctx
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

    DROP TABLE IF EXISTS tmp_carga_bio;
    CREATE TEMP TABLE tmp_carga_bio (
        biomedico                    TEXT,
        total_mantenimientos         BIGINT,
        exitosos                     BIGINT,
        desfavorables                BIGINT,
        costo_total_gestionado       NUMERIC,
        costo_promedio               NUMERIC,
        primer_mantenimiento_periodo TIMESTAMP,
        ultimo_mantenimiento_periodo TIMESTAMP
    );

    INSERT INTO tmp_carga_bio
    SELECT
        CONCAT(p.nombre_persona, ' ', p.apellido_persona),
        COUNT(m.id_mantenimiento),
        SUM(CASE WHEN m.id_resultado_mantenimiento = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN m.id_resultado_mantenimiento IN (2,3,4) THEN 1 ELSE 0 END),
        COALESCE(SUM(m.costo_mantenimiento), 0),
        COALESCE(ROUND(AVG(m.costo_mantenimiento), 2), 0),
        MIN(m.fecha_hora_mantenimiento),
        MAX(m.fecha_hora_mantenimiento)
    FROM biomedico b
    JOIN persona p ON p.id_persona = b.id_persona
    LEFT JOIN mantenimiento m
           ON m.id_biomedico = b.id_biomedico
          AND m.fecha_hora_mantenimiento BETWEEN p_fecha_inicio AND p_fecha_fin
    GROUP BY b.id_biomedico, p.nombre_persona, p.apellido_persona;

    OPEN p_resultado FOR
        SELECT * FROM tmp_carga_bio ORDER BY total_mantenimientos DESC;
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
152	9	2026-05-17 14:16:57.62747	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
153	9	2026-05-17 14:27:55.36769	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
154	9	2026-05-17 14:32:22.070984	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
155	9	2026-05-17 14:32:45.154803	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
156	9	2026-05-18 13:38:14.89184	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
157	9	2026-05-18 13:38:43.643232	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
160	7	2026-05-18 21:27:32.336796	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
161	7	2026-05-18 21:28:07.954203	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
162	7	2026-05-18 21:42:53.285023	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
163	7	2026-05-18 21:43:01.797136	UPDATE	equipo	21	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 2, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	{"id_equipo": 21, "id_modelo": 4, "numero_serie": "SN-DR-2026-012", "activo_equipo": true, "nombre_equipo": "Ventilador Dräger Evita C", "codigo_interno": "EQ-012", "id_tipo_equipo": 4, "id_estado_equipo": 1, "id_criticidad_equipo": 1, "id_ubicacion_administrativa_actual": 5}	flutter_movil
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
10	8	21	2026-05-17 12:39:59.550822	1
11	8	21	2026-05-17 12:59:35.968938	1
12	8	21	2026-05-17 13:06:14.486825	1
13	8	21	2026-05-17 13:07:15.780725	1
14	8	21	2026-05-17 13:08:06.281659	1
15	8	21	2026-05-17 13:08:08.78919	1
16	8	21	2026-05-17 13:08:10.643449	1
17	8	21	2026-05-17 13:14:03.028161	1
18	8	21	2026-05-17 13:14:10.668848	1
19	8	21	2026-05-17 14:04:02.066532	1
20	8	21	2026-05-17 14:06:22.532207	1
21	8	21	2026-05-17 14:09:07.979438	1
22	8	21	2026-05-17 14:16:49.970858	1
23	8	21	2026-05-17 14:17:51.270267	1
24	8	21	2026-05-17 14:18:20.898344	1
25	8	21	2026-05-17 14:27:51.481176	1
26	8	21	2026-05-17 14:32:12.668904	1
27	8	21	2026-05-17 14:32:39.16097	1
28	8	21	2026-05-18 13:35:22.135414	1
29	8	21	2026-05-18 13:38:19.612724	1
30	8	21	2026-05-18 21:27:24.417452	1
31	8	21	2026-05-18 21:27:39.098911	1
32	8	21	2026-05-18 21:42:49.908078	1
33	8	21	2026-05-18 21:42:59.548367	1
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
12	1	2026-05-17 17:08:34.695512	25.79473006026952	-100.1806352884656	11.77
13	1	2026-05-17 17:08:34.96311	25.79473006026952	-100.1806352884656	11.9
14	1	2026-05-17 17:08:35.202102	25.79473006026952	-100.1806352884656	11.9
15	1	2026-05-17 17:08:35.442373	25.79473006026952	-100.1806352884656	11.9
16	1	2026-05-17 17:08:35.679302	25.79473006026952	-100.1806352884656	11.9
17	1	2026-05-17 17:08:35.915845	25.79473006026952	-100.1806352884656	11.9
18	1	2026-05-17 17:08:36.16468	25.79473006026952	-100.1806352884656	11.9
19	1	2026-05-17 17:08:36.405938	25.79473006026952	-100.1806352884656	11.9
20	1	2026-05-17 17:08:36.650613	25.79473006026952	-100.1806352884656	11.9
21	1	2026-05-17 17:08:36.889426	25.79473006026952	-100.1806352884656	11.9
22	1	2026-05-17 17:08:37.134348	25.79473006026952	-100.1806352884656	11.9
23	1	2026-05-17 17:08:37.404373	25.79473006026952	-100.1806352884656	11.9
24	1	2026-05-17 17:08:37.651639	25.79473006026952	-100.1806352884656	11.9
25	1	2026-05-17 17:08:37.929358	25.79473006026952	-100.1806352884656	11.9
26	1	2026-05-17 17:08:38.19893	25.79473006026952	-100.1806352884656	11.9
27	1	2026-05-17 17:08:38.45526	25.79473006026952	-100.1806352884656	11.9
28	1	2026-05-17 17:08:38.696715	25.79473006026952	-100.1806352884656	11.9
29	1	2026-05-17 17:08:38.947905	25.79473006026952	-100.1806352884656	11.9
30	1	2026-05-17 17:08:39.1852	25.79473006026952	-100.1806352884656	11.9
31	1	2026-05-17 17:08:39.434385	25.79473006026952	-100.1806352884656	11.9
32	1	2026-05-17 17:08:39.674631	25.79473006026952	-100.1806352884656	11.9
33	1	2026-05-17 17:08:39.920873	25.79473006026952	-100.1806352884656	11.9
34	1	2026-05-17 17:08:40.168906	25.79473006026952	-100.1806352884656	11.9
35	1	2026-05-17 17:08:40.413155	25.79473006026952	-100.1806352884656	11.9
36	1	2026-05-17 17:08:40.65214	25.79473006026952	-100.1806352884656	11.9
37	1	2026-05-17 17:08:40.906513	25.79473006026952	-100.1806352884656	11.9
38	1	2026-05-17 17:08:41.168557	25.79473006026952	-100.1806352884656	11.9
39	1	2026-05-17 17:08:41.412953	25.79473006026952	-100.1806352884656	11.9
40	1	2026-05-17 17:08:41.65873	25.79473006026952	-100.1806352884656	11.9
41	1	2026-05-17 17:08:41.90177	25.79473006026952	-100.1806352884656	11.9
42	1	2026-05-17 17:08:42.180071	25.79473006026952	-100.1806352884656	11.9
43	1	2026-05-17 17:08:42.43362	25.79473006026952	-100.1806352884656	11.9
44	1	2026-05-17 17:08:42.688016	25.79473006026952	-100.1806352884656	11.9
45	1	2026-05-17 17:08:42.930911	25.79473006026952	-100.1806352884656	11.9
46	1	2026-05-17 17:08:43.175599	25.79473006026952	-100.1806352884656	11.9
47	1	2026-05-17 17:08:43.440024	25.79473006026952	-100.1806352884656	11.9
48	1	2026-05-17 17:08:43.690389	25.79473006026952	-100.1806352884656	11.9
49	1	2026-05-17 17:08:43.945184	25.79473006026952	-100.1806352884656	11.9
50	1	2026-05-17 17:08:44.187977	25.79473006026952	-100.1806352884656	11.9
51	1	2026-05-17 17:08:44.437307	25.79473006026952	-100.1806352884656	11.9
52	1	2026-05-17 17:08:44.682267	25.79473006026952	-100.1806352884656	11.9
53	1	2026-05-17 17:08:44.941834	25.79473006026952	-100.1806352884656	11.9
54	1	2026-05-17 17:08:45.189424	25.79473006026952	-100.1806352884656	11.9
55	1	2026-05-17 17:08:45.449327	25.79473006026952	-100.1806352884656	11.9
56	1	2026-05-17 17:08:45.684914	25.79473006026952	-100.1806352884656	11.9
57	1	2026-05-17 17:08:45.924142	25.79473006026952	-100.1806352884656	11.9
58	1	2026-05-17 17:08:46.180884	25.79473006026952	-100.1806352884656	11.9
59	1	2026-05-17 17:08:46.420739	25.79473006026952	-100.1806352884656	11.9
60	1	2026-05-17 17:08:46.653617	25.79473006026952	-100.1806352884656	11.9
61	1	2026-05-17 17:08:46.88802	25.79473006026952	-100.1806352884656	11.9
62	1	2026-05-17 17:08:47.125736	25.79473006026952	-100.1806352884656	11.9
63	1	2026-05-17 17:08:47.368713	25.79473006026952	-100.1806352884656	11.9
64	1	2026-05-17 17:08:47.618277	25.79473006026952	-100.1806352884656	11.9
65	1	2026-05-17 17:08:47.863905	25.79473006026952	-100.1806352884656	11.9
66	1	2026-05-17 17:08:48.112637	25.79473006026952	-100.1806352884656	11.9
67	1	2026-05-17 17:08:48.356842	25.79473006026952	-100.1806352884656	11.9
68	1	2026-05-17 17:08:48.605998	25.79473006026952	-100.1806352884656	11.9
69	1	2026-05-17 17:08:48.843955	25.79473006026952	-100.1806352884656	11.9
70	1	2026-05-17 17:08:49.091978	25.79473006026952	-100.1806352884656	11.9
71	1	2026-05-17 17:08:49.335852	25.79473006026952	-100.1806352884656	11.9
72	1	2026-05-17 17:08:49.579237	25.79473006026952	-100.1806352884656	11.9
73	1	2026-05-17 17:08:49.823853	25.79473006026952	-100.1806352884656	11.9
74	1	2026-05-17 17:08:50.065913	25.79473006026952	-100.1806352884656	11.9
75	1	2026-05-17 17:08:50.317502	25.79473006026952	-100.1806352884656	11.9
76	1	2026-05-17 17:08:50.564157	25.79473006026952	-100.1806352884656	11.9
77	1	2026-05-17 17:08:50.801995	25.79473006026952	-100.1806352884656	11.9
78	1	2026-05-17 17:08:51.035685	25.79473006026952	-100.1806352884656	11.9
79	1	2026-05-17 17:08:51.283473	25.79473006026952	-100.1806352884656	11.9
80	1	2026-05-17 17:08:51.540727	25.79473006026952	-100.1806352884656	11.9
81	1	2026-05-17 17:08:51.78144	25.79473006026952	-100.1806352884656	11.9
82	1	2026-05-17 17:08:52.026102	25.79473006026952	-100.1806352884656	11.9
83	1	2026-05-17 17:08:52.276121	25.79473006026952	-100.1806352884656	11.9
84	1	2026-05-17 17:08:52.51876	25.79473006026952	-100.1806352884656	11.9
85	1	2026-05-17 17:08:52.76697	25.79473006026952	-100.1806352884656	11.9
86	1	2026-05-17 17:08:53.018125	25.79473006026952	-100.1806352884656	11.9
87	1	2026-05-17 17:08:53.269548	25.79473006026952	-100.1806352884656	11.9
88	1	2026-05-17 17:10:00.209105	25.79473006026952	-100.1806352884656	11.9
89	1	2026-05-17 17:10:00.470289	25.79473006026952	-100.1806352884656	11.9
90	1	2026-05-17 17:10:00.739628	25.79473006026952	-100.1806352884656	11.9
91	1	2026-05-17 17:10:00.992282	25.79473006026952	-100.1806352884656	11.9
92	1	2026-05-17 17:10:01.241224	25.79473006026952	-100.1806352884656	11.9
93	1	2026-05-17 17:10:01.492159	25.79473006026952	-100.1806352884656	11.9
94	1	2026-05-17 17:10:01.736917	25.79473006026952	-100.1806352884656	11.9
95	1	2026-05-17 17:10:01.991739	25.79473006026952	-100.1806352884656	11.9
96	1	2026-05-17 17:10:02.234428	25.79473006026952	-100.1806352884656	11.9
97	1	2026-05-17 17:10:02.498791	25.79473006026952	-100.1806352884656	11.9
98	1	2026-05-17 17:10:02.767307	25.79473006026952	-100.1806352884656	11.9
99	1	2026-05-17 17:10:03.02742	25.79473006026952	-100.1806352884656	11.9
100	1	2026-05-17 17:10:03.280282	25.79473006026952	-100.1806352884656	11.9
101	1	2026-05-17 17:10:03.538064	25.79473006026952	-100.1806352884656	11.9
102	1	2026-05-17 17:10:03.791854	25.79473006026952	-100.1806352884656	11.9
103	1	2026-05-17 17:10:04.043847	25.79473006026952	-100.1806352884656	11.9
104	1	2026-05-17 17:10:10.083788	25.79473006026952	-100.1806352884656	11.9
105	1	2026-05-17 17:10:12.399467	25.79473006026952	-100.1806352884656	11.9
106	1	2026-05-17 17:11:00.251437	25.79473006026952	-100.1806352884656	11.9
107	1	2026-05-17 17:12:00.183054	25.79473006026952	-100.1806352884656	11.9
108	1	2026-05-17 17:16:00.255372	25.79473006026952	-100.1806352884656	11.9
109	1	2026-05-17 17:16:00.508727	25.79473006026952	-100.1806352884656	11.9
110	1	2026-05-17 17:16:00.76422	25.79473006026952	-100.1806352884656	11.9
111	1	2026-05-17 17:16:01.018698	25.79473006026952	-100.1806352884656	11.9
112	1	2026-05-17 17:17:00.18795	25.79473006026952	-100.1806352884656	11.9
113	1	2026-05-17 17:18:00.314644	25.79473006026952	-100.1806352884656	11.9
114	1	2026-05-17 17:19:00.243066	25.79473006026952	-100.1806352884656	11.9
115	1	2026-05-17 17:20:00.280041	25.79473006026952	-100.1806352884656	11.9
116	1	2026-05-17 17:21:00.196315	25.79473006026952	-100.1806352884656	11.9
117	1	2026-05-17 19:46:00.167957	25.79473006026952	-100.1806352884656	11.9
118	1	2026-05-17 19:46:02.640061	25.79473006026952	-100.1806352884656	11.9
119	1	2026-05-17 19:47:02.513268	25.79473006026952	-100.1806352884656	11.9
120	1	2026-05-17 19:48:02.585613	25.79473006026952	-100.1806352884656	11.9
121	1	2026-05-17 19:49:02.494424	25.79473006026952	-100.1806352884656	11.9
122	1	2026-05-17 19:50:02.636284	25.79473006026952	-100.1806352884656	11.9
123	1	2026-05-17 19:51:02.634213	25.79473006026952	-100.1806352884656	11.9
124	1	2026-05-17 19:52:02.529989	25.79473006026952	-100.1806352884656	11.9
125	1	2026-05-17 19:53:02.667149	25.79473006026952	-100.1806352884656	11.9
126	1	2026-05-17 19:54:02.717027	25.79473006026952	-100.1806352884656	11.9
127	1	2026-05-17 19:55:02.509772	25.79473006026952	-100.1806352884656	11.9
128	1	2026-05-17 19:56:02.609872	25.79473006026952	-100.1806352884656	11.9
129	1	2026-05-17 19:57:02.641194	25.79473006026952	-100.1806352884656	11.9
130	1	2026-05-17 19:58:02.615807	25.79473006026952	-100.1806352884656	11.9
131	1	2026-05-17 19:59:02.620668	25.79473006026952	-100.1806352884656	11.9
132	1	2026-05-17 20:00:02.649469	25.79473006026952	-100.1806352884656	11.9
133	1	2026-05-17 20:01:02.547682	25.79473006026952	-100.1806352884656	11.9
134	1	2026-05-17 20:02:02.574886	25.79473006026952	-100.1806352884656	11.9
135	1	2026-05-18 13:45:32.226141	25.79237725090293	-100.177764044652	5.11
136	1	2026-05-18 13:45:32.647488	25.79222050251794	-100.177885353105	5.06
137	1	2026-05-18 13:45:33.148896	25.79215037721003	-100.177937249211	5.29
138	1	2026-05-18 13:45:33.581273	25.79209619828822	-100.1779806064484	5.24
139	1	2026-05-18 13:45:34.002693	25.79204734709652	-100.178009278863	5.67
140	1	2026-05-18 13:45:34.468972	25.79196576018661	-100.1780577144753	6.15
141	1	2026-05-18 13:45:34.946875	25.7919231860041	-100.1780890385134	6.35
142	1	2026-05-18 13:45:35.357735	25.79187789717917	-100.1781230049966	6.17
143	1	2026-05-18 13:45:35.796928	25.79173492767649	-100.1782142229919	5.89
144	1	2026-05-18 13:45:36.244909	25.79165515847038	-100.1782668345978	5.82
145	1	2026-05-18 13:45:36.682207	25.79157198939943	-100.1783193578641	5.89
146	1	2026-05-18 13:45:37.142658	25.79147587425674	-100.1783835317249	5.71
147	1	2026-05-18 13:45:37.587969	25.79116201540748	-100.1785871869959	5.06
148	1	2026-05-18 13:45:38.0509	25.7908414159244	-100.1787991285714	5.97
149	1	2026-05-18 13:45:38.48895	25.79074228764534	-100.1788657242498	6.61
150	1	2026-05-18 13:45:39.32226	25.79052037514485	-100.1790292753822	7.63
151	1	2026-05-18 13:45:39.729451	25.7904388199708	-100.1791029422806	8.16
152	1	2026-05-18 13:45:40.150129	25.79041549476909	-100.1791236752987	7.18
153	1	2026-05-18 13:45:40.642038	25.79033751725694	-100.1791781006542	5.55
154	1	2026-05-18 13:45:41.06522	25.7902932087902	-100.1792083111181	5.37
155	1	2026-05-18 13:45:42.083859	25.79024860999526	-100.1792404645342	4.86
156	1	2026-05-18 13:45:42.511516	25.79016315926983	-100.1792701739984	4.36
157	1	2026-05-18 13:45:42.991292	25.79009024785329	-100.1793131733026	4.86
158	1	2026-05-18 13:45:43.443133	25.78992719878553	-100.1794117907557	5.1
159	1	2026-05-18 13:45:43.857849	25.7898357057409	-100.1794667904275	5.22
160	1	2026-05-18 13:45:44.254885	25.78973749262676	-100.1795253720414	5.95
161	1	2026-05-18 13:45:44.686621	25.78963932814593	-100.1795792353409	6.75
162	1	2026-05-18 13:45:45.123155	25.78941567585115	-100.1796852158782	6.05
163	1	2026-05-18 13:45:45.55746	25.78918849305189	-100.1798164223158	7.09
164	1	2026-05-18 13:45:45.954404	25.78906118206885	-100.1798947649789	7.61
165	1	2026-05-18 13:45:46.363455	25.78893843364894	-100.1799697876192	8.83
166	1	2026-05-18 13:45:46.812452	25.78869090472746	-100.1801217661649	9.46
167	1	2026-05-18 13:45:47.504094	25.78856955792329	-100.1801911146241	10.84
168	1	2026-05-18 13:45:47.922535	25.78845508335462	-100.1802639635231	11.62
169	1	2026-05-18 13:45:48.339421	25.78836159415813	-100.1803321494184	12.43
170	1	2026-05-18 13:45:48.768153	25.78826180213228	-100.1803997439279	13.53
171	1	2026-05-18 13:45:49.217127	25.78815392490417	-100.1804643495529	15.01
172	1	2026-05-18 13:45:49.631401	25.78804509341003	-100.1805300235736	16.22
173	1	2026-05-18 13:45:50.006371	25.78768441952661	-100.1807628359368	17.13
174	1	2026-05-18 13:45:50.433348	25.78763016232315	-100.1807669587479	6.79
175	1	2026-05-18 13:45:50.873019	25.78750537995328	-100.1808351263636	6.22
176	1	2026-05-18 13:45:51.32828	25.78746536518388	-100.180889770821	7.0
177	1	2026-05-18 13:45:51.759561	25.7873782938808	-100.1809565658734	9.17
178	1	2026-05-18 13:45:52.183933	25.78733260850551	-100.1809896506839	9.66
179	1	2026-05-18 13:45:52.636257	25.78727952368509	-100.1810280940879	8.52
180	1	2026-05-18 13:45:53.111575	25.78727169463183	-100.1810337637964	8.04
181	1	2026-05-18 13:45:53.569937	25.78728319170817	-100.1810141941547	6.67
182	1	2026-05-18 13:45:54.049797	25.7872895294126	-100.1810207106693	6.29
183	1	2026-05-18 13:45:54.481874	25.7872883201826	-100.18103078473	5.54
184	1	2026-05-18 13:45:54.921353	25.78729562764397	-100.1810298607513	5.42
185	1	2026-05-18 13:45:55.383517	25.7873079387214	-100.1810240959936	5.12
186	1	2026-05-18 13:45:55.853155	25.78731407738805	-100.1810260216428	5.9
187	1	2026-05-18 13:45:56.281284	25.78731045029397	-100.181030275318	6.28
188	1	2026-05-18 13:45:56.737847	25.78730115106641	-100.1810391551383	6.65
189	1	2026-05-18 13:45:57.209351	25.78730113099875	-100.1810451368017	7.59
190	1	2026-05-18 13:45:57.663959	25.7873061868347	-100.1810267011195	7.33
191	1	2026-05-18 13:45:58.112879	25.78729598295863	-100.1810283336874	6.44
192	1	2026-05-18 13:45:58.564286	25.78729957391342	-100.18102246245	6.24
193	1	2026-05-18 13:45:59.020971	25.78729198692267	-100.1810262363493	6.04
194	1	2026-05-18 13:45:59.733357	25.78728311772268	-100.1810263465905	6.12
195	1	2026-05-18 13:46:00.18524	25.78727721214189	-100.1810323293102	6.31
196	1	2026-05-18 13:46:00.633252	25.78724350185072	-100.1810550190946	6.3
197	1	2026-05-18 13:46:01.098352	25.78722106731097	-100.181075717847	6.92
198	1	2026-05-18 13:46:01.547326	25.78718925007826	-100.1810977270617	6.86
199	1	2026-05-18 13:46:01.990246	25.78715457303885	-100.181123881364	6.74
200	1	2026-05-18 13:46:02.404121	25.78713677456765	-100.181179416014	6.87
201	1	2026-05-18 13:46:02.840367	25.7870980705307	-100.1812254335515	7.14
202	1	2026-05-18 13:46:03.281173	25.78707559075152	-100.1812521611003	7.89
203	1	2026-05-18 13:46:03.73822	25.78704049433656	-100.1812938893215	8.86
204	1	2026-05-18 13:46:04.160085	25.78700841082172	-100.1813320353274	9.52
205	1	2026-05-18 13:46:04.585773	25.78692557068653	-100.1814435757987	8.12
206	1	2026-05-18 13:46:05.046182	25.78685263460931	-100.1815641104555	7.77
207	1	2026-05-18 13:46:05.503477	25.78675455892195	-100.1817278831621	6.71
208	1	2026-05-18 13:46:05.941215	25.78672226357815	-100.1817931087596	7.39
209	1	2026-05-18 13:46:06.393127	25.7866844436213	-100.1818606999474	8.02
210	1	2026-05-18 13:46:06.838981	25.78666431254477	-100.1818985101002	8.54
211	1	2026-05-18 13:46:07.285229	25.78662895481586	-100.181954578717	8.52
212	1	2026-05-18 13:46:07.787605	25.78661904103226	-100.1820056386622	9.53
213	1	2026-05-18 13:46:08.241003	25.78642154713612	-100.1820111484866	10.81
214	1	2026-05-18 13:46:08.674937	25.7863703772225	-100.1819774027668	11.7
215	1	2026-05-18 13:46:09.160717	25.78625551089335	-100.1818942715776	12.58
216	1	2026-05-18 13:46:09.607783	25.78619463873612	-100.1818470798374	11.73
217	1	2026-05-18 13:46:10.031683	25.78611636435808	-100.181811034202	11.83
218	1	2026-05-18 13:46:10.484779	25.78603262039401	-100.1817586542384	11.7
219	1	2026-05-18 13:46:10.949631	25.785966095963	-100.1817175182346	11.42
220	1	2026-05-18 13:46:11.382266	25.78589815959873	-100.1816755091468	10.38
221	1	2026-05-18 13:46:11.835776	25.7857578528714	-100.1815900443629	8.53
222	1	2026-05-18 13:46:12.264899	25.78569290171822	-100.181548199009	8.05
223	1	2026-05-18 13:46:12.693904	25.78561580864362	-100.1814994670457	7.62
224	1	2026-05-18 13:46:13.209445	25.78554579689617	-100.1814549387595	7.68
225	1	2026-05-18 13:46:13.713985	25.78547140682711	-100.1814076258133	7.46
226	1	2026-05-18 13:46:14.285214	25.78533083602632	-100.1813341026837	4.96
227	1	2026-05-18 13:46:14.740049	25.78527510589057	-100.1813034535909	4.98
228	1	2026-05-18 13:46:15.26073	25.7852335450184	-100.1812831323914	5.05
229	1	2026-05-18 13:46:15.762444	25.78519791230696	-100.1812619044241	5.25
230	1	2026-05-18 13:46:16.407483	25.78516723593276	-100.1812426941233	5.54
231	1	2026-05-18 13:46:16.866929	25.78512538393225	-100.1812082948884	5.36
232	1	2026-05-18 13:46:17.324443	25.78510663947654	-100.1811942923218	5.61
233	1	2026-05-18 13:46:17.794658	25.78508439244235	-100.1811771153722	5.86
234	1	2026-05-18 13:50:32.064175	25.78506173777729	-100.1811615943771	6.18
235	1	2026-05-18 13:50:32.579733	25.78503661080108	-100.1811461580667	6.15
236	1	2026-05-18 13:50:33.091587	25.785012651777	-100.1811331341326	5.86
237	1	2026-05-18 13:50:33.603329	25.78499683254115	-100.1811167188969	6.15
238	1	2026-05-18 13:50:34.051913	25.78497749318507	-100.181103882643	6.67
239	1	2026-05-18 13:50:34.563868	25.78496170603286	-100.1810899370434	7.13
240	1	2026-05-18 13:50:35.02398	25.78493993928487	-100.1810769109274	7.64
241	1	2026-05-18 13:50:35.470855	25.78491738145421	-100.1810640631229	8.02
242	1	2026-05-18 13:50:35.914673	25.78490170678587	-100.181049873528	8.73
243	1	2026-05-18 13:50:36.366512	25.78486660744782	-100.1810265942273	9.58
244	1	2026-05-18 13:50:36.795895	25.78485301001464	-100.1810202361806	10.23
245	1	2026-05-18 13:50:37.279465	25.7848312605922	-100.1810086487422	10.87
246	1	2026-05-18 13:50:37.830723	25.78478456822691	-100.1809713045953	11.85
247	1	2026-05-18 13:50:38.295053	25.78477785128434	-100.1809643460995	12.44
248	1	2026-05-18 13:50:38.725136	25.78474951540953	-100.1809505105566	13.15
249	1	2026-05-18 13:50:39.228073	25.78472087514627	-100.1809268149486	13.34
250	1	2026-05-18 13:50:39.748353	25.78467125820931	-100.1808938079856	13.66
251	1	2026-05-18 13:50:40.203723	25.78462112087014	-100.1808835451581	13.77
252	1	2026-05-18 13:50:40.646689	25.78457540225611	-100.1808558976324	13.94
253	1	2026-05-18 13:50:41.275674	25.78454168763831	-100.1808232109588	14.05
254	1	2026-05-18 13:50:41.796946	25.78442368363519	-100.1807636436281	14.23
255	1	2026-05-18 13:50:42.234335	25.78439131311541	-100.1807457065356	14.44
256	1	2026-05-18 13:50:42.66443	25.78435490658316	-100.1807238095247	14.72
257	1	2026-05-18 13:50:43.124209	25.78426329455825	-100.1806761809811	15.06
258	1	2026-05-18 13:50:43.594762	25.78414038766705	-100.1805947961106	15.5
259	1	2026-05-18 13:50:44.045334	25.7840970370869	-100.1805845981232	15.55
260	1	2026-05-18 13:50:44.532053	25.78401286070691	-100.1805267403322	15.46
261	1	2026-05-18 13:50:45.174802	25.78382232009918	-100.1804093719952	11.06
262	1	2026-05-18 13:50:45.626329	25.78374241249597	-100.1803513014071	7.19
263	1	2026-05-18 13:50:46.100601	25.78364331767141	-100.1802920091452	6.25
264	1	2026-05-18 13:50:46.543034	25.78355628318586	-100.1802408032969	5.78
265	1	2026-05-18 13:50:47.054914	25.78335825243276	-100.1801202629179	5.43
266	1	2026-05-18 13:50:47.56307	25.78325980491992	-100.1800632486265	5.72
267	1	2026-05-18 13:50:48.033393	25.78316024215879	-100.1800328267258	4.38
268	1	2026-05-18 13:50:48.511525	25.7830510336682	-100.1799726059195	4.48
269	1	2026-05-18 13:50:48.978321	25.78295374788627	-100.1799145410409	4.4
270	1	2026-05-18 13:50:49.417813	25.78286453322196	-100.179860112825	4.37
271	1	2026-05-18 13:50:49.845416	25.78276991381869	-100.1798041828118	4.33
272	1	2026-05-18 13:50:50.287591	25.78256447486434	-100.1796959481655	4.64
273	1	2026-05-18 13:50:50.739412	25.78245262469726	-100.1796347110477	4.97
274	1	2026-05-18 13:50:51.313282	25.78234146963207	-100.1795709160443	5.6
275	1	2026-05-18 13:50:51.755927	25.78222930613234	-100.1795041248667	5.96
276	1	2026-05-18 13:50:52.301978	25.78199624845572	-100.1793572507479	6.75
277	1	2026-05-18 13:50:52.744144	25.78186950623533	-100.1792872000852	7.28
278	1	2026-05-18 13:50:53.26304	25.78175205855145	-100.1792093276668	6.4
279	1	2026-05-18 13:50:53.764292	25.78136406363767	-100.1789705135689	6.57
280	1	2026-05-18 13:50:54.195408	25.78123507491106	-100.1788845898916	6.06
281	1	2026-05-18 13:50:54.641351	25.78110218613908	-100.1788108285155	8.92
282	1	2026-05-18 13:50:55.095061	25.78096807679833	-100.1787411579431	7.31
283	1	2026-05-18 13:50:55.545704	25.78083181863579	-100.1786704377995	7.82
284	1	2026-05-18 13:50:56.257804	25.78070993752427	-100.1785842993557	8.41
285	1	2026-05-18 13:50:56.957279	25.78058144350603	-100.1785016846524	8.94
286	1	2026-05-18 13:50:57.375226	25.78032682869071	-100.1783378573118	9.81
287	1	2026-05-18 13:50:57.814404	25.78020525341594	-100.1782593749538	10.27
288	1	2026-05-18 13:50:58.491377	25.78009213086096	-100.1781883878905	10.53
289	1	2026-05-18 13:50:59.024913	25.7799961688375	-100.178124045566	8.46
290	1	2026-05-18 13:50:59.643049	25.7799075830898	-100.1780676125748	8.68
291	1	2026-05-18 13:51:00.682517	25.77982121919112	-100.1780118347434	8.6
292	1	2026-05-18 13:51:01.560282	25.77975715104706	-100.1779665305463	8.77
293	1	2026-05-18 13:51:01.994872	25.77969902099747	-100.1779282467606	9.09
294	1	2026-05-18 13:51:02.452002	25.77959168684432	-100.1778973689562	9.6
295	1	2026-05-18 13:51:02.883718	25.77953794010636	-100.1779129292761	9.88
296	1	2026-05-18 13:51:03.323995	25.77944103411235	-100.1779606335601	10.0
297	1	2026-05-18 13:51:03.75523	25.77940288978804	-100.1780130336435	9.76
298	1	2026-05-18 13:51:04.229072	25.77939404439543	-100.178048466352	9.93
299	1	2026-05-18 13:51:04.678022	25.7793705419959	-100.1781426117844	10.34
300	1	2026-05-18 13:51:05.130845	25.77935647473385	-100.1781985117881	10.64
301	1	2026-05-18 13:51:05.624517	25.77930549683082	-100.178310780025	7.33
302	1	2026-05-18 13:51:06.123892	25.7792865848957	-100.1783640626732	6.94
303	1	2026-05-18 13:51:06.564775	25.77926787650895	-100.1784123211922	7.29
304	1	2026-05-18 13:51:07.086381	25.77927066671822	-100.1784769954701	7.27
305	1	2026-05-18 13:51:07.533503	25.77925589340299	-100.1785283100569	7.98
306	1	2026-05-18 13:51:07.972897	25.77922468144359	-100.1786332256375	9.3
307	1	2026-05-18 13:51:08.414054	25.77920816736777	-100.1786845412559	9.58
308	1	2026-05-18 13:51:08.861621	25.77919093160616	-100.1787402179692	9.96
309	1	2026-05-18 13:51:09.310426	25.77915794206888	-100.1788615389325	10.18
310	1	2026-05-18 13:51:09.768614	25.77913949095726	-100.1789427052134	10.53
311	1	2026-05-18 13:51:10.222338	25.77911851785058	-100.1789964056853	10.61
312	1	2026-05-18 13:51:10.654129	25.77907542269279	-100.1790991355867	11.4
313	1	2026-05-18 13:51:11.170545	25.77907741566583	-100.1791698925852	9.88
314	1	2026-05-18 13:51:11.613494	25.7790629387191	-100.1792130836245	9.33
315	1	2026-05-18 13:51:12.060377	25.77899522698422	-100.1793752204834	9.59
316	1	2026-05-18 13:51:12.492551	25.77897784756259	-100.1794626500796	10.27
317	1	2026-05-18 13:51:13.04288	25.77897256109049	-100.1794968405249	9.63
318	1	2026-05-18 13:51:13.561424	25.77897023506432	-100.1794980437615	8.65
319	1	2026-05-18 13:51:14.022481	25.77893799090298	-100.1795796775838	8.98
320	1	2026-05-18 13:51:14.455351	25.77892589643674	-100.1796080570833	8.98
321	1	2026-05-18 13:51:14.974348	25.77891495994372	-100.1796286376552	8.82
322	1	2026-05-18 13:51:15.434188	25.77889674122512	-100.1796769775684	9.2
323	1	2026-05-18 13:51:15.86292	25.77888511990279	-100.1797600858171	7.35
324	1	2026-05-18 13:51:16.296158	25.77875509659663	-100.1798880199369	8.19
325	1	2026-05-18 13:51:16.719024	25.77873299623983	-100.1799164378416	6.88
326	1	2026-05-18 13:51:17.13306	25.77870887642893	-100.1800035498877	7.09
327	1	2026-05-18 13:51:17.587613	25.77869277424307	-100.1801064249334	7.3
328	1	2026-05-18 13:51:18.01966	25.77866767984904	-100.1802190213702	7.77
329	1	2026-05-18 13:51:18.53967	25.77861776222859	-100.1804849252899	8.95
330	1	2026-05-18 13:51:18.94077	25.77858726844095	-100.180626830987	9.74
331	1	2026-05-18 13:51:19.387585	25.77851315204915	-100.180871306491	10.68
332	1	2026-05-18 13:51:19.843943	25.77848521354719	-100.1809907760704	11.0
333	1	2026-05-18 13:53:14.383001	25.77837462765956	-100.1811781968864	12.23
334	1	2026-05-18 13:53:14.8706	25.77834618653847	-100.181302533848	10.27
335	1	2026-05-18 13:53:15.287771	25.77815684867529	-100.1816374698173	7.06
336	1	2026-05-18 13:53:15.733279	25.77808829644324	-100.1818097332703	6.24
337	1	2026-05-18 13:53:16.2241	25.77802795131963	-100.1819677332783	5.42
338	1	2026-05-18 13:53:16.65903	25.77798199446706	-100.1821149144837	5.4
339	1	2026-05-18 13:53:17.083772	25.77792954310114	-100.1822676676863	5.24
340	1	2026-05-18 13:53:17.514677	25.77787945831222	-100.1824091611766	5.22
341	1	2026-05-18 13:53:17.94105	25.77783830577796	-100.1825648277163	5.4
342	1	2026-05-18 13:53:18.412099	25.77778535221651	-100.182703163187	5.82
343	1	2026-05-18 13:53:18.882306	25.77774163429352	-100.1828511761723	6.5
344	1	2026-05-18 13:53:19.374773	25.77764546068827	-100.1831609039915	10.41
345	1	2026-05-18 13:53:19.821271	25.7776011411613	-100.183309974861	8.55
346	1	2026-05-18 13:53:20.260469	25.77756040393013	-100.1834616661388	9.3
347	1	2026-05-18 13:53:20.674954	25.77751307695895	-100.18362991955	10.46
348	1	2026-05-18 13:53:21.116229	25.77746714122931	-100.1838036005817	9.98
349	1	2026-05-18 13:53:21.528899	25.7773822444311	-100.1841032937338	11.87
350	1	2026-05-18 13:53:22.004503	25.7773167017802	-100.184235535083	12.03
351	1	2026-05-18 13:53:22.557054	25.77720180607482	-100.1844472795633	9.7
352	1	2026-05-18 13:53:23.057643	25.77713356895079	-100.1847124886897	7.52
353	1	2026-05-18 13:53:23.533805	25.77696278375527	-100.1850761177271	5.92
354	1	2026-05-18 13:53:24.020955	25.7768601789308	-100.1852549620794	5.43
355	1	2026-05-18 13:53:24.475002	25.77676018010538	-100.185432348832	4.66
356	1	2026-05-18 13:53:25.026647	25.7766515791374	-100.1855867541935	4.15
357	1	2026-05-18 13:53:25.489569	25.77653703089236	-100.1857553254485	3.86
358	1	2026-05-18 13:53:25.927956	25.77641311133344	-100.1859135134552	3.81
359	1	2026-05-18 13:53:26.341802	25.77628267683363	-100.1860756226242	3.95
360	1	2026-05-18 13:53:26.79629	25.77614097485204	-100.1862197290513	3.95
361	1	2026-05-18 13:53:27.345957	25.77583845958442	-100.1865097264874	4.08
362	1	2026-05-18 13:53:28.212208	25.775675941404	-100.1866443718096	4.66
363	1	2026-05-18 13:53:28.652192	25.77551050051557	-100.1867761554558	5.23
364	1	2026-05-18 13:53:29.097711	25.77534021275891	-100.18690170887	5.97
365	1	2026-05-18 13:53:29.517295	25.77513693807723	-100.1870198999552	6.28
366	1	2026-05-18 13:53:29.955542	25.77494436836852	-100.1871083979215	5.56
367	1	2026-05-18 13:53:30.446137	25.77474951035395	-100.1871938707806	4.97
368	1	2026-05-18 13:53:30.878212	25.77456575789348	-100.1872943674061	4.24
369	1	2026-05-18 13:53:31.304179	25.77438746394249	-100.1873902484311	4.11
370	1	2026-05-18 13:53:31.776355	25.77421497099487	-100.1874846450241	4.04
371	1	2026-05-18 13:53:32.213527	25.77400587858439	-100.1875803664195	3.89
372	1	2026-05-18 13:53:32.654487	25.7738295782521	-100.1876818430571	3.95
373	1	2026-05-18 13:53:33.093647	25.77365274501999	-100.1877822861049	4.07
374	1	2026-05-18 13:53:33.526406	25.77329148161052	-100.1879776959305	4.21
375	1	2026-05-18 13:53:33.979105	25.77312080024518	-100.1880764229514	4.8
376	1	2026-05-18 13:53:34.501721	25.77295245547921	-100.1881769051296	5.41
377	1	2026-05-18 13:53:34.94078	25.77278599787483	-100.1882689027097	6.07
378	1	2026-05-18 13:53:35.372617	25.77261291559699	-100.1884041269837	5.63
379	1	2026-05-18 13:53:35.76811	25.77244205753779	-100.1884986749618	5.73
380	1	2026-05-18 13:53:36.302993	25.77210532890982	-100.1886863724901	6.82
381	1	2026-05-18 13:53:36.8249	25.77193931409773	-100.1887674537467	7.76
382	1	2026-05-18 13:53:37.65456	25.77160655399653	-100.188919024437	8.74
383	1	2026-05-18 13:53:38.34068	25.77144468290233	-100.1890092785798	9.24
384	1	2026-05-18 13:53:38.838008	25.77124232714907	-100.1891071355657	8.41
385	1	2026-05-18 13:53:39.3244	25.77105334042849	-100.1892288743778	8.26
386	1	2026-05-18 13:53:39.774539	25.77086459441984	-100.189333041685	8.53
387	1	2026-05-18 13:53:40.236296	25.77070087555756	-100.189430341713	9.34
388	1	2026-05-18 13:53:40.698901	25.77049777834282	-100.1895403121437	9.0
389	1	2026-05-18 13:53:41.124903	25.76996437078125	-100.1898098924627	10.93
390	1	2026-05-18 13:53:41.615666	25.76979278134995	-100.1899012850928	11.83
391	1	2026-05-18 13:53:42.102346	25.76961940401394	-100.189994385805	12.88
392	1	2026-05-18 13:53:42.564439	25.76944391435748	-100.1900888481399	13.68
393	1	2026-05-18 13:53:43.010312	25.76927521246407	-100.1901822310405	14.93
394	1	2026-05-18 13:53:43.434549	25.76911931591371	-100.1902983636076	15.08
395	1	2026-05-18 13:53:43.878075	25.76895328844819	-100.1904131571216	15.84
396	1	2026-05-18 13:53:44.338013	25.76848561372553	-100.1905521882313	14.94
397	1	2026-05-18 13:53:44.794631	25.76832453483246	-100.1906490415064	15.79
398	1	2026-05-18 13:53:45.234702	25.767909404081	-100.1909924351257	10.78
399	1	2026-05-18 13:53:45.718483	25.76767707967977	-100.1910906729341	8.59
400	1	2026-05-18 13:53:46.152621	25.76746564015156	-100.1911792172867	8.09
401	1	2026-05-18 13:53:46.593895	25.76706915112578	-100.1913587066796	8.67
402	1	2026-05-18 13:53:47.044858	25.76686863480634	-100.1914591154756	8.89
403	1	2026-05-18 13:53:47.504629	25.76668017316752	-100.1915409426849	8.86
404	1	2026-05-18 13:53:47.962122	25.76648147859702	-100.1916429188411	7.94
405	1	2026-05-18 13:53:48.409692	25.76626614749907	-100.191748917919	5.97
406	1	2026-05-18 13:53:48.835329	25.76605838844847	-100.1918587429096	5.9
407	1	2026-05-18 13:53:49.282775	25.76583697841208	-100.1919729187701	5.35
408	1	2026-05-18 13:53:49.70161	25.76562100481046	-100.1920957616653	5.26
409	1	2026-05-18 13:53:50.153688	25.76540725705711	-100.1922114479553	5.13
410	1	2026-05-18 13:53:50.689595	25.76519537522911	-100.1923274640707	5.15
411	1	2026-05-18 13:53:51.645562	25.76498117047553	-100.1924419379093	4.99
412	1	2026-05-18 13:53:52.09037	25.76478110546963	-100.1925633250543	5.64
413	1	2026-05-18 13:53:52.542631	25.76458686256621	-100.1926855220065	6.3
414	1	2026-05-18 13:53:52.999202	25.76418450159205	-100.1929309974587	7.9
415	1	2026-05-18 13:53:53.454258	25.76398778485094	-100.1930293305839	8.06
416	1	2026-05-18 13:53:53.876764	25.76379365676415	-100.1931327235268	8.94
417	1	2026-05-18 13:53:54.303579	25.76360256327546	-100.1932368061367	10.1
418	1	2026-05-18 13:53:54.766241	25.76341540606331	-100.1933391897498	11.24
419	1	2026-05-18 13:53:55.203376	25.76316951908235	-100.1934752254791	8.45
420	1	2026-05-18 13:53:55.646698	25.76290434421496	-100.1936154204115	6.91
421	1	2026-05-18 13:53:56.086521	25.76265354650537	-100.1937228506128	5.78
422	1	2026-05-18 13:53:56.537622	25.76245010918529	-100.1938317040823	6.03
423	1	2026-05-18 13:53:56.974075	25.762222339867	-100.193950315086	5.51
424	1	2026-05-18 13:53:57.435534	25.76181246597966	-100.1941669331568	6.0
425	1	2026-05-18 13:53:57.871034	25.7615939290879	-100.1942709168564	5.74
426	1	2026-05-18 13:53:58.348959	25.76139132837735	-100.1943779105711	5.79
427	1	2026-05-18 13:53:58.868454	25.7611803178539	-100.1944894408365	5.77
428	1	2026-05-18 13:53:59.335658	25.76097730705527	-100.1945936516332	5.93
429	1	2026-05-18 13:53:59.782861	25.76076311816694	-100.1947174680004	5.84
430	1	2026-05-18 13:54:00.352567	25.76054523052825	-100.1948446236225	5.66
431	1	2026-05-18 13:54:00.816378	25.76032481323055	-100.1949647307976	5.54
432	1	2026-05-18 13:57:32.534007	25.76012231901313	-100.1950653140731	5.74
433	1	2026-05-18 13:57:33.080939	25.7597380319761	-100.1952818421013	10.11
434	1	2026-05-18 13:57:33.961069	25.75954002454422	-100.1953908616349	7.6
435	1	2026-05-18 13:57:34.541407	25.75936210612692	-100.1955017787095	8.5
436	1	2026-05-18 13:57:35.227035	25.75900707912514	-100.1957022566328	10.4
437	1	2026-05-18 13:57:35.720992	25.75866989733112	-100.1958577605133	6.68
438	1	2026-05-18 13:57:36.207327	25.75842660449239	-100.1959754507009	5.71
439	1	2026-05-18 13:57:36.644598	25.75823308530035	-100.196087397609	6.29
440	1	2026-05-18 13:57:37.104093	25.75802591115402	-100.1961879501478	6.1
441	1	2026-05-18 13:57:37.593827	25.75781329267234	-100.1962890149251	6.01
442	1	2026-05-18 13:57:38.205144	25.75736856014883	-100.1965090376063	5.28
443	1	2026-05-18 13:57:38.990451	25.75712730200065	-100.1966244423992	4.42
444	1	2026-05-18 13:57:39.466384	25.75692512657614	-100.1967371346325	4.39
445	1	2026-05-18 13:57:39.921771	25.75673654295905	-100.1968387527383	4.86
446	1	2026-05-18 13:57:40.373759	25.75654860679051	-100.1969395705541	6.61
447	1	2026-05-18 13:57:40.824596	25.75636481431829	-100.197039472847	5.93
448	1	2026-05-18 13:57:41.28034	25.75617043039262	-100.1971370142348	7.81
449	1	2026-05-18 13:57:41.73552	25.75597095560221	-100.1972335168391	6.81
450	1	2026-05-18 13:57:42.191984	25.75578846459489	-100.1973356174369	7.59
451	1	2026-05-18 13:57:42.638918	25.75559308511521	-100.1974574680231	7.01
452	1	2026-05-18 13:57:43.207431	25.75536754784727	-100.1975853553052	5.92
453	1	2026-05-18 13:57:43.643221	25.75490775183135	-100.1978428435337	4.48
454	1	2026-05-18 13:57:44.099476	25.75449611857436	-100.1980623531301	3.98
455	1	2026-05-18 13:57:44.590881	25.75428915969078	-100.1981640789261	3.81
456	1	2026-05-18 13:57:45.071301	25.75410437983792	-100.1982634931968	4.27
457	1	2026-05-18 13:57:45.508647	25.75392187259648	-100.1983597767419	4.49
458	1	2026-05-18 13:57:45.982209	25.75374914277145	-100.1984491284607	4.76
459	1	2026-05-18 13:57:46.428075	25.75358703057223	-100.1985284089727	4.98
460	1	2026-05-18 13:57:46.878228	25.75344721600576	-100.1986081680243	4.75
461	1	2026-05-18 13:57:47.348049	25.75331424274163	-100.1986765172683	4.73
462	1	2026-05-18 13:57:47.788807	25.75319129090187	-100.1987557292522	3.9
463	1	2026-05-18 13:57:48.2713	25.75305852394936	-100.1988174414306	4.2
464	1	2026-05-18 13:57:48.728467	25.75294527664953	-100.1988726667358	4.08
465	1	2026-05-18 13:57:49.176193	25.75283011934185	-100.1989265736061	4.27
466	1	2026-05-18 13:57:49.599535	25.75273200046897	-100.1989677709232	4.47
467	1	2026-05-18 13:57:50.143917	25.75259445422666	-100.1990465157327	4.49
468	1	2026-05-18 13:57:50.606386	25.7525498008264	-100.1991341020937	3.95
469	1	2026-05-18 13:57:51.084976	25.75246893746125	-100.1991787546317	3.99
470	1	2026-05-18 13:57:51.560158	25.75243124110557	-100.1992043661128	4.09
471	1	2026-05-18 13:57:52.010028	25.75230059733042	-100.1992759987046	4.57
472	1	2026-05-18 13:57:52.460412	25.75226278600165	-100.1992911536918	4.75
473	1	2026-05-18 13:57:52.892894	25.75222553892328	-100.1993069114249	5.1
474	1	2026-05-18 13:57:53.33664	25.75218233102132	-100.1993324756749	5.45
475	1	2026-05-18 13:57:53.802214	25.75213767481818	-100.1993638782566	6.04
476	1	2026-05-18 13:57:54.245515	25.75208613855992	-100.1993982970403	6.71
477	1	2026-05-18 13:57:54.729715	25.75202912274307	-100.1994376621005	7.3
478	1	2026-05-18 13:57:55.195659	25.75197135803563	-100.1994759773749	8.05
479	1	2026-05-18 13:57:55.640831	25.75191000621045	-100.1995113703328	7.69
480	1	2026-05-18 13:57:56.175644	25.75185513604964	-100.1995459444243	8.49
481	1	2026-05-18 13:57:56.630764	25.75179192900789	-100.1995824129234	9.34
482	1	2026-05-18 13:57:57.09174	25.75173619919194	-100.1996087112248	10.39
483	1	2026-05-18 13:57:57.547434	25.75167034313554	-100.1996414515444	10.87
484	1	2026-05-18 13:57:57.99414	25.75161205850348	-100.1996752921463	11.63
485	1	2026-05-18 13:57:58.464357	25.75156544488389	-100.1997039648269	12.47
486	1	2026-05-18 13:57:58.958719	25.75142421819453	-100.1997581786264	9.0
487	1	2026-05-18 13:57:59.412995	25.75136364398309	-100.1997958102271	9.85
488	1	2026-05-18 13:57:59.843209	25.75127579165218	-100.1998424849082	10.26
489	1	2026-05-18 13:58:00.272523	25.7512036530212	-100.1998877384221	10.79
490	1	2026-05-18 13:58:00.684383	25.75113625419602	-100.1999197195453	10.28
491	1	2026-05-18 13:58:01.136333	25.75106351070336	-100.1999611182788	10.65
492	1	2026-05-18 13:58:01.598297	25.75099985152065	-100.2000034342119	11.53
493	1	2026-05-18 13:58:02.060407	25.7509181483163	-100.2000465856508	11.88
494	1	2026-05-18 13:58:02.490721	25.75084353970454	-100.2000953036938	12.58
495	1	2026-05-18 13:58:02.94117	25.75077527512616	-100.2001412498642	13.4
496	1	2026-05-18 13:58:03.386685	25.75051893043855	-100.2002256317535	13.49
497	1	2026-05-18 13:58:04.042951	25.7502856868695	-100.2003596288318	10.1
498	1	2026-05-18 13:58:04.820123	25.75004918463965	-100.2004984273101	8.7
499	1	2026-05-18 13:58:05.283094	25.74995218564435	-100.2005567931942	9.39
500	1	2026-05-18 13:58:05.750039	25.7498511174516	-100.2006127861149	10.0
501	1	2026-05-18 13:58:06.280281	25.74975097445408	-100.2006712814397	10.73
502	1	2026-05-18 13:58:06.734733	25.74964973864063	-100.2007225511529	11.49
503	1	2026-05-18 13:58:07.183461	25.74954872161835	-100.2007638498712	12.24
504	1	2026-05-18 13:58:07.94819	25.74936168314746	-100.2008480793497	13.58
505	1	2026-05-18 13:58:08.46523	25.74909040975362	-100.2009835560291	15.41
506	1	2026-05-18 13:58:08.913298	25.74898648782452	-100.2010724787301	15.55
507	1	2026-05-18 13:58:09.450017	25.74881337148432	-100.2011947058336	11.57
508	1	2026-05-18 13:58:09.945267	25.74853319838726	-100.2013596037654	10.43
509	1	2026-05-18 13:58:10.602413	25.74833217162604	-100.2014892450065	10.35
510	1	2026-05-18 13:58:11.042935	25.74821934318239	-100.2015423698793	10.55
511	1	2026-05-18 13:58:11.512911	25.74791817423904	-100.2016584328869	26.09
512	1	2026-05-18 13:58:11.998066	25.7478117144502	-100.2017648884188	14.28
513	1	2026-05-18 13:58:12.689123	25.74772516176045	-100.2018308479418	10.93
514	1	2026-05-18 13:58:13.153959	25.74758557903245	-100.2019019562212	10.58
515	1	2026-05-18 13:58:13.72424	25.74745567390736	-100.2019731664211	10.26
516	1	2026-05-18 13:58:14.551955	25.7472663751419	-100.2020679595594	9.36
517	1	2026-05-18 13:58:15.539867	25.74677756327367	-100.2022939862749	9.36
518	1	2026-05-18 13:58:16.206129	25.74655163161665	-100.2023926254018	5.64
519	1	2026-05-18 13:58:17.095421	25.74635714393966	-100.2024954253414	5.37
520	1	2026-05-18 13:58:17.635992	25.74627499125567	-100.2025446079448	5.83
521	1	2026-05-18 13:58:18.112254	25.7461929710749	-100.2025955247512	9.72
522	1	2026-05-18 13:58:18.757937	25.74610570680157	-100.2026441794922	8.26
523	1	2026-05-18 13:58:19.202208	25.74601869125008	-100.2026960371339	7.54
524	1	2026-05-18 13:58:19.634011	25.74593042436208	-100.2027497035055	9.41
525	1	2026-05-18 13:58:20.082709	25.74584085957548	-100.2028046501999	8.92
526	1	2026-05-18 13:58:20.543207	25.74573996981899	-100.2028376214955	9.72
527	1	2026-05-18 13:58:20.992624	25.74554632037136	-100.2029373989198	11.18
528	1	2026-05-18 13:58:21.453077	25.74545347004958	-100.2029849411908	12.13
529	1	2026-05-18 13:58:21.910602	25.74526483005152	-100.2030816357942	13.52
530	1	2026-05-18 13:58:22.334051	25.74517595232804	-100.2031272905258	13.3
531	1	2026-05-18 14:02:32.146776	25.74508256758448	-100.2031746419944	13.22
532	1	2026-05-18 14:02:32.678668	25.74499830247508	-100.2032364775788	13.51
533	1	2026-05-18 14:02:33.223908	25.7448983227575	-100.2032830242669	14.12
534	1	2026-05-18 14:02:33.67228	25.74479904953977	-100.2033297277358	14.68
535	1	2026-05-18 14:02:34.131018	25.74469963865069	-100.2033821994651	15.45
536	1	2026-05-18 14:02:34.570789	25.74459225063716	-100.2034255011649	15.82
537	1	2026-05-18 14:02:35.012599	25.74450559631912	-100.2034802341411	16.23
538	1	2026-05-18 14:02:35.42805	25.74440918601938	-100.2034902724007	15.92
539	1	2026-05-18 14:02:35.824725	25.74431388624397	-100.2035299608188	16.18
540	1	2026-05-18 14:02:36.276525	25.74410138249745	-100.2036872902535	9.6
541	1	2026-05-18 14:02:36.751199	25.74391853495973	-100.2037971759436	7.48
542	1	2026-05-18 14:02:37.208315	25.74364814282669	-100.2039268110023	6.66
543	1	2026-05-18 14:02:37.616951	25.74340826101459	-100.2040539623598	6.27
544	1	2026-05-18 14:02:38.042562	25.74309576239678	-100.2042185939738	7.51
545	1	2026-05-18 14:02:38.510632	25.74299104011795	-100.2042738658715	8.14
546	1	2026-05-18 14:02:38.95188	25.74280129906422	-100.2043740102275	7.72
547	1	2026-05-18 14:02:39.404773	25.74260070058013	-100.2044792860763	7.9
548	1	2026-05-18 14:02:39.881171	25.74233175866339	-100.2046213277367	10.57
549	1	2026-05-18 14:02:40.363847	25.74221333650165	-100.2046837168814	7.66
550	1	2026-05-18 14:02:40.853031	25.74209841817849	-100.2047442297404	11.32
551	1	2026-05-18 14:02:41.30579	25.74193230863938	-100.204990956556	20.42
552	1	2026-05-18 14:02:41.778877	25.74183109798981	-100.2050603562211	12.58
553	1	2026-05-18 14:02:42.215588	25.74160129756946	-100.2051587709805	30.29
554	1	2026-05-18 14:02:42.721234	25.74145314049248	-100.2051832097225	9.49
555	1	2026-05-18 14:02:43.160829	25.74134558683184	-100.2052627380716	9.52
556	1	2026-05-18 14:02:43.627537	25.74117146179283	-100.2053825000296	8.43
557	1	2026-05-18 14:02:44.106777	25.74096273467382	-100.2053554689109	8.72
558	1	2026-05-18 14:02:44.567283	25.74083702789043	-100.205420515399	8.08
559	1	2026-05-18 14:02:45.023835	25.74044868800979	-100.205613039189	9.37
560	1	2026-05-18 14:02:45.49124	25.74025164873549	-100.2057415644267	8.0
561	1	2026-05-18 14:02:45.95219	25.7400740544845	-100.2058629123369	8.15
562	1	2026-05-18 14:02:46.409305	25.73994745571058	-100.2059538483304	6.7
563	1	2026-05-18 14:02:46.883425	25.73974895408557	-100.2060712699423	6.4
564	1	2026-05-18 14:02:47.348964	25.73957189908098	-100.2061816701867	6.34
565	1	2026-05-18 14:02:47.918318	25.73939297155484	-100.2062863039449	6.16
566	1	2026-05-18 14:02:48.444174	25.73924543736032	-100.206361388459	7.56
567	1	2026-05-18 14:02:48.909124	25.73902974462588	-100.2064701484419	7.95
568	1	2026-05-18 14:02:49.380266	25.73869472520019	-100.2066054701515	8.63
569	1	2026-05-18 14:02:50.044979	25.73831489787177	-100.2068000475272	6.22
570	1	2026-05-18 14:03:32.263875	25.73814156099771	-100.2068883393832	5.61
571	1	2026-05-18 14:03:32.779636	25.7378071602045	-100.2070572498926	4.47
572	1	2026-05-18 14:03:33.268462	25.73764391431797	-100.2071365358579	4.44
573	1	2026-05-18 14:03:33.735936	25.73717453860043	-100.2073706865426	4.75
574	1	2026-05-18 14:03:34.192683	25.73700018878351	-100.2074478070652	4.33
575	1	2026-05-18 14:03:34.621903	25.73685630209808	-100.2075235653193	4.96
576	1	2026-05-18 14:03:35.054913	25.73670516669447	-100.2076037814211	5.15
577	1	2026-05-18 14:03:35.503941	25.73639210452196	-100.2077541730392	4.5
578	1	2026-05-18 14:03:36.353689	25.73624807897294	-100.2078354509224	3.95
579	1	2026-05-18 14:03:36.967695	25.7358357233517	-100.2080382508277	3.88
580	1	2026-05-18 14:03:37.464512	25.73556974115052	-100.2081855517708	3.64
581	1	2026-05-18 14:03:37.949551	25.73543271139296	-100.208269534356	3.81
582	1	2026-05-18 14:03:38.434224	25.73513390974434	-100.2084608681521	4.28
583	1	2026-05-18 14:03:38.930615	25.73497651590946	-100.2085553507801	4.33
584	1	2026-05-18 14:03:39.415405	25.73480301624882	-100.2086495213153	4.28
585	1	2026-05-18 14:03:39.95529	25.73463327613745	-100.2087463428998	4.26
586	1	2026-05-18 14:03:40.431703	25.73446409450078	-100.208834977089	4.38
587	1	2026-05-18 14:03:40.885497	25.73430504294435	-100.2089268529165	4.89
588	1	2026-05-18 14:03:41.327922	25.7340025574211	-100.2090935950228	6.26
589	1	2026-05-18 14:03:41.777784	25.73384574111584	-100.2091544956055	5.92
590	1	2026-05-18 14:03:42.22388	25.73369337555509	-100.209230377643	5.56
591	1	2026-05-18 14:03:42.700578	25.73355766775413	-100.2092895263716	5.52
592	1	2026-05-18 14:03:43.154274	25.73343193343328	-100.2093343247648	5.23
593	1	2026-05-18 14:03:43.606288	25.73332740016872	-100.2093783657677	5.3
594	1	2026-05-18 14:03:44.054728	25.73323441779473	-100.2094334867673	5.47
595	1	2026-05-18 14:03:44.504606	25.73314885207582	-100.2094794854685	5.14
596	1	2026-05-18 14:03:44.957469	25.73306141838582	-100.2095263279121	5.04
597	1	2026-05-18 14:03:45.426525	25.73289964777805	-100.2096119719087	8.53
598	1	2026-05-18 14:03:45.93577	25.73282617471679	-100.2096516127708	4.89
599	1	2026-05-18 14:03:46.456115	25.73268119214977	-100.2097290643593	4.5
600	1	2026-05-18 14:03:46.898044	25.73258958170156	-100.2097778364258	4.78
601	1	2026-05-18 14:03:47.406399	25.73252392992305	-100.209844059786	4.09
602	1	2026-05-18 14:03:47.854098	25.73243849049454	-100.20990478931	4.67
603	1	2026-05-18 14:03:48.32132	25.73229532191177	-100.2099942247215	4.57
604	1	2026-05-18 14:03:48.819066	25.73216630703435	-100.2100490178407	3.98
605	1	2026-05-18 14:03:49.26603	25.7320992247944	-100.2100774840039	3.79
606	1	2026-05-18 14:03:49.815506	25.73189557521999	-100.2101710028532	4.21
607	1	2026-05-18 14:03:50.26733	25.73182734852941	-100.2102115581375	4.34
608	1	2026-05-18 14:03:50.706505	25.73168251620839	-100.2102843215579	4.13
609	1	2026-05-18 14:03:51.170701	25.73153134252503	-100.210356995391	4.06
610	1	2026-05-18 14:03:51.616514	25.73123297229007	-100.2105164866674	3.77
611	1	2026-05-18 14:03:52.073345	25.73115106965933	-100.210568048227	4.0
612	1	2026-05-18 14:03:52.549372	25.73106562315744	-100.2106181557919	4.32
613	1	2026-05-18 14:03:53.011175	25.73097885622764	-100.2106756896002	4.49
614	1	2026-05-18 14:03:53.427563	25.730787895874	-100.2107904022483	4.61
615	1	2026-05-18 14:03:53.887059	25.73068188036855	-100.210848065751	4.55
616	1	2026-05-18 14:03:54.365926	25.73058076754778	-100.2109046179833	4.34
617	1	2026-05-18 14:03:54.825534	25.73036394765575	-100.2110178455626	4.23
618	1	2026-05-18 14:03:55.26418	25.73024923581234	-100.2110762465254	4.24
619	1	2026-05-18 14:03:55.739844	25.72991977453508	-100.2112596633189	4.45
620	1	2026-05-18 14:03:56.453522	25.72980238828209	-100.2113190128978	4.34
621	1	2026-05-18 14:03:56.922155	25.72968926781351	-100.2113764543601	4.25
622	1	2026-05-18 14:03:57.397842	25.7295731377234	-100.2114395009802	4.22
623	1	2026-05-18 14:03:57.863361	25.72946044565373	-100.2114963425516	4.15
624	1	2026-05-18 14:03:58.352453	25.7292536982768	-100.2116031960838	4.31
625	1	2026-05-18 14:03:58.984113	25.72913808256671	-100.2116599381883	4.13
626	1	2026-05-18 14:03:59.547922	25.72902197342057	-100.2117174708478	4.04
627	1	2026-05-18 14:04:00.012512	25.72881045753065	-100.2118359552697	4.52
628	1	2026-05-18 14:04:00.544164	25.728566500076	-100.2119790036088	4.28
629	1	2026-05-18 14:06:32.117454	25.72844698204849	-100.2120548587497	4.63
630	1	2026-05-18 14:06:32.554669	25.72832514793424	-100.2121337624479	5.08
631	1	2026-05-18 14:06:33.287255	25.72803531198061	-100.2123179274527	5.49
632	1	2026-05-18 14:06:33.725499	25.72787951512064	-100.2124148107138	4.72
633	1	2026-05-18 14:06:34.233433	25.72771819159731	-100.2124938392274	4.46
634	1	2026-05-18 14:06:34.728376	25.72756937514713	-100.2125803837063	4.86
635	1	2026-05-18 14:06:35.24379	25.7272612383891	-100.2127572118806	5.05
636	1	2026-05-18 14:06:35.697818	25.72710771201051	-100.2128424683168	5.71
637	1	2026-05-18 14:06:36.129801	25.72680688820757	-100.2130176943981	7.22
638	1	2026-05-18 14:06:36.562194	25.72664623752827	-100.2131085483577	7.82
639	1	2026-05-18 14:06:37.00021	25.72625307922542	-100.2133209002905	7.86
640	1	2026-05-18 14:06:37.499573	25.7260305981549	-100.2134237428857	6.94
641	1	2026-05-18 14:06:38.015172	25.72562925573642	-100.2136072374526	6.4
642	1	2026-05-18 14:06:38.463619	25.7254513716344	-100.2136965478735	6.88
643	1	2026-05-18 14:06:38.932796	25.72489399043084	-100.2139743762382	7.37
644	1	2026-05-18 14:06:39.440017	25.72470036520814	-100.2140634396403	6.78
645	1	2026-05-18 14:06:39.877156	25.72450163063478	-100.2141332982015	5.96
646	1	2026-05-18 14:06:40.335349	25.72431386912966	-100.2142191100282	6.69
647	1	2026-05-18 14:06:40.754116	25.72413616605686	-100.2143199301975	6.63
648	1	2026-05-18 14:06:41.186105	25.72381460241311	-100.2145235098555	4.46
649	1	2026-05-18 14:06:41.632666	25.72348993583526	-100.2146824677691	3.93
650	1	2026-05-18 14:06:42.069729	25.72333885766565	-100.2147491796919	3.89
651	1	2026-05-18 14:06:42.530197	25.72320412049281	-100.2148251176326	3.86
652	1	2026-05-18 14:06:42.961603	25.72307610684081	-100.2148864183138	3.76
653	1	2026-05-18 14:06:43.401091	25.7229510656429	-100.2149389445992	3.92
654	1	2026-05-18 14:06:43.849304	25.72284192592396	-100.2149870120246	3.98
655	1	2026-05-18 14:06:44.289901	25.72274482274406	-100.21502863351	4.03
656	1	2026-05-18 14:06:44.719467	25.72262906847386	-100.215102900472	3.75
657	1	2026-05-18 14:06:45.157719	25.72258843842273	-100.2151223890735	3.75
658	1	2026-05-18 14:06:45.594906	25.72246572816792	-100.2151455385001	4.88
659	1	2026-05-18 14:06:46.19628	25.72240645811362	-100.2151601325148	5.46
660	1	2026-05-18 14:06:46.650108	25.72234457764267	-100.2151827530584	6.19
661	1	2026-05-18 14:06:47.102163	25.7222754015221	-100.2152056189127	6.95
662	1	2026-05-18 14:06:47.54134	25.72222197840567	-100.2152462427668	7.8
663	1	2026-05-18 14:06:48.006764	25.72216290109197	-100.215287653557	8.75
664	1	2026-05-18 14:06:48.448387	25.72209767731798	-100.2153382821693	9.58
665	1	2026-05-18 14:06:48.881772	25.72203521006546	-100.2153872104708	10.52
666	1	2026-05-18 14:07:32.274273	25.72197093401453	-100.2154301066904	11.51
667	1	2026-05-18 14:07:32.733236	25.72194876822603	-100.2154789190777	11.74
668	1	2026-05-18 14:07:33.223936	25.72189297271852	-100.2155373919221	12.12
669	1	2026-05-18 14:07:33.703182	25.72185805273367	-100.2155547647898	12.67
670	1	2026-05-18 14:07:34.205802	25.72180440208102	-100.2155786490095	12.93
671	1	2026-05-18 14:07:34.680225	25.72173492817571	-100.2156249762627	14.18
672	1	2026-05-18 14:07:35.247566	25.72166534539983	-100.215673462243	15.74
673	1	2026-05-18 14:07:35.763444	25.72159979813069	-100.2157165579405	16.67
674	1	2026-05-18 14:07:36.250896	25.72159193514197	-100.2157192444413	15.4
675	1	2026-05-18 14:07:36.725001	25.72153999690698	-100.2157539269233	16.64
676	1	2026-05-18 14:07:37.198792	25.72150854081674	-100.2158071769891	17.12
677	1	2026-05-18 14:07:37.660725	25.72168802631357	-100.2156483186451	12.65
678	1	2026-05-18 14:07:38.102739	25.72164946465778	-100.2156397038006	7.7
679	1	2026-05-18 14:07:38.610885	25.72162157730945	-100.2156539538009	8.11
680	1	2026-05-18 14:07:39.095893	25.7215897165975	-100.2156666772664	8.68
681	1	2026-05-18 14:07:39.594661	25.72156868341134	-100.2156843344269	9.37
682	1	2026-05-18 14:07:40.162344	25.72154176374694	-100.2156999737003	10.12
683	1	2026-05-18 14:07:40.650149	25.72152132183235	-100.2157188104179	10.5
684	1	2026-05-18 14:07:41.126778	25.72149226802063	-100.2157315057864	10.68
685	1	2026-05-18 14:07:41.611916	25.72145154003259	-100.2157627886956	10.16
686	1	2026-05-18 14:07:42.072218	25.7214302790734	-100.2157789530533	10.37
687	1	2026-05-18 14:07:42.542969	25.72140410845336	-100.2157984153186	10.24
688	1	2026-05-18 14:07:43.048005	25.72137628909481	-100.2158186253454	10.95
689	1	2026-05-18 14:07:43.567611	25.72133192434012	-100.2158429105723	10.95
690	1	2026-05-18 14:07:44.084445	25.72125240604393	-100.2158543918257	8.72
691	1	2026-05-18 14:07:44.591876	25.72122648164491	-100.2158702963794	9.17
692	1	2026-05-18 14:07:45.082805	25.72119972208173	-100.2158869512332	9.82
693	1	2026-05-18 14:07:45.582256	25.72117128987853	-100.215904531916	10.35
694	1	2026-05-18 14:07:46.07986	25.7211463897229	-100.2159187455848	9.73
695	1	2026-05-18 14:07:46.554895	25.72111186048316	-100.2159447337277	10.38
696	1	2026-05-18 14:07:47.043617	25.72108899101936	-100.2159616935902	10.04
697	1	2026-05-18 14:07:47.518958	25.72105326663833	-100.2159863445077	10.28
698	1	2026-05-18 14:07:47.994559	25.72102219009584	-100.2160025684013	10.71
699	1	2026-05-18 14:07:48.469424	25.72098567581988	-100.2160125229439	11.25
700	1	2026-05-18 14:07:48.959736	25.72096162411922	-100.2160259872151	11.46
701	1	2026-05-18 14:07:49.437933	25.7209395665287	-100.2160379067419	11.86
702	1	2026-05-18 14:07:50.055197	25.72092202340296	-100.2160536194905	11.79
703	1	2026-05-18 14:07:50.510732	25.72076708295189	-100.2161570499259	11.65
704	1	2026-05-18 14:07:50.962092	25.72073515306062	-100.2161682983772	11.93
705	1	2026-05-18 14:07:51.417565	25.7207187911243	-100.2161721338258	12.31
706	1	2026-05-18 14:07:51.980042	25.72070372331511	-100.2161841156155	12.5
707	1	2026-05-18 14:07:52.512736	25.72070020854913	-100.2161879417201	12.05
708	1	2026-05-18 14:07:53.003312	25.72069941242384	-100.2161801112085	11.53
709	1	2026-05-18 14:07:53.651935	25.72067885694564	-100.2161751208016	11.1
710	1	2026-05-18 14:07:54.115098	25.72066731402426	-100.2161744650804	11.06
711	1	2026-05-18 14:07:54.616596	25.72059054756388	-100.2162346906356	9.39
712	1	2026-05-18 14:07:55.125915	25.72058162729295	-100.2162423146486	9.65
713	1	2026-05-18 14:07:55.657322	25.72056753721635	-100.2162522055474	9.81
714	1	2026-05-18 14:07:56.179808	25.72055608496747	-100.2162610509613	10.0
715	1	2026-05-18 14:07:56.705895	25.72054130301919	-100.2162705535597	10.3
716	1	2026-05-18 14:07:57.261203	25.72047469958256	-100.2163383665522	11.12
717	1	2026-05-18 14:07:57.849722	25.72043712876237	-100.2163443200861	11.7
718	1	2026-05-18 14:07:58.3773	25.72041005236589	-100.2163597155166	12.46
719	1	2026-05-18 14:07:58.971822	25.72038296713021	-100.2163751159602	12.87
720	1	2026-05-18 14:07:59.669004	25.7203516034057	-100.2163929491363	13.65
721	1	2026-05-18 14:08:00.175584	25.72031675720647	-100.2164127624015	14.51
722	1	2026-05-18 14:08:00.68192	25.72024031731381	-100.2164562255267	15.77
723	1	2026-05-18 14:08:01.207433	25.72019853769298	-100.2164799810759	16.52
724	1	2026-05-18 14:08:01.695363	25.72004100756716	-100.2165689526999	16.74
725	1	2026-05-18 14:08:02.202033	25.71978507034623	-100.2166689374337	7.88
726	1	2026-05-18 14:08:02.676463	25.7196898199254	-100.216720189136	8.14
727	1	2026-05-18 14:10:32.098252	25.71950910142522	-100.2168372070082	7.0
728	1	2026-05-18 14:10:32.698103	25.71930850065404	-100.2169724071934	6.32
729	1	2026-05-18 14:10:33.131491	25.71918021729011	-100.2170365692009	5.75
730	1	2026-05-18 14:10:33.73005	25.71908719279026	-100.2171109049022	5.41
731	1	2026-05-18 14:10:34.333072	25.71898693304366	-100.217182537868	4.93
732	1	2026-05-18 14:10:34.949804	25.71888861495061	-100.2172457770617	4.72
733	1	2026-05-18 14:10:35.396335	25.71878313178701	-100.2172922043218	4.81
734	1	2026-05-18 14:10:35.819978	25.7186759807212	-100.2173604017529	4.93
735	1	2026-05-18 14:10:36.251189	25.71856521533005	-100.2174211371406	5.07
736	1	2026-05-18 14:10:36.678088	25.7184442769034	-100.2174212792419	4.96
737	1	2026-05-18 14:10:37.242973	25.71823684462823	-100.2175412079246	4.9
738	1	2026-05-18 14:10:37.694233	25.71811932455354	-100.2175702188825	5.28
739	1	2026-05-18 14:10:38.328926	25.7179927937032	-100.2176080488993	5.02
740	1	2026-05-18 14:10:38.773385	25.71786646247786	-100.2176656741455	5.41
741	1	2026-05-18 14:10:39.190441	25.71760782342772	-100.2178036190786	5.05
742	1	2026-05-18 14:10:39.622308	25.71747717266423	-100.2178737027703	5.3
743	1	2026-05-18 14:10:40.060944	25.71732752146763	-100.2179622294509	5.15
744	1	2026-05-18 14:10:40.511323	25.71718443728759	-100.2180437093229	5.44
745	1	2026-05-18 14:10:40.941483	25.71702230709586	-100.2181307002277	5.19
746	1	2026-05-18 14:10:41.371552	25.71685935846943	-100.2182053791195	4.95
747	1	2026-05-18 14:10:41.81101	25.71651550046074	-100.2183837229991	4.41
748	1	2026-05-18 14:10:42.223645	25.71602844232277	-100.218626126678	4.91
749	1	2026-05-18 14:10:42.653055	25.71570774575872	-100.2187690980388	5.14
750	1	2026-05-18 14:10:43.248957	25.71557115602436	-100.2188599694273	4.67
751	1	2026-05-18 14:10:43.675293	25.71542529002	-100.218926509885	4.65
752	1	2026-05-18 14:10:44.11067	25.71515637444844	-100.2190581433998	4.74
753	1	2026-05-18 14:10:44.540966	25.71502396509656	-100.2191281207964	4.76
754	1	2026-05-18 14:10:44.979772	25.71476469744999	-100.2192680097881	4.62
755	1	2026-05-18 14:10:45.418072	25.71463936572784	-100.2193352586084	4.37
756	1	2026-05-18 14:10:45.864229	25.71437772570955	-100.2194817122581	4.32
757	1	2026-05-18 14:10:46.325664	25.71424877530893	-100.2195578194523	4.24
758	1	2026-05-18 14:10:46.805421	25.71410678612534	-100.2196370771902	4.2
759	1	2026-05-18 14:10:47.250261	25.71397050895716	-100.219715367239	4.22
760	1	2026-05-18 14:10:47.854626	25.71383028471244	-100.2197963619395	4.56
761	1	2026-05-18 14:10:48.306597	25.71369071321315	-100.2198779500618	4.59
762	1	2026-05-18 14:10:48.763705	25.71326617710621	-100.2200990390882	5.61
763	1	2026-05-18 14:10:49.246623	25.71312044290666	-100.2201661372414	5.78
764	1	2026-05-18 14:10:49.713848	25.71297674262427	-100.2202447507354	6.46
765	1	2026-05-18 14:12:47.578962	25.71282711755646	-100.2203309228687	6.69
766	1	2026-05-18 14:12:48.022059	25.71267535903234	-100.2204160716136	6.79
767	1	2026-05-18 14:12:48.455564	25.71236137510052	-100.2205921678458	4.86
768	1	2026-05-18 14:12:48.891368	25.71220070872205	-100.220684670857	5.34
769	1	2026-05-18 14:12:49.298658	25.71203779100712	-100.2207747146025	5.15
770	1	2026-05-18 14:12:49.75438	25.71187722441501	-100.2208599317744	4.86
771	1	2026-05-18 14:12:50.183742	25.71159539513052	-100.2210109338963	6.15
772	1	2026-05-18 14:12:50.603929	25.71146070088455	-100.2210764182263	6.88
773	1	2026-05-18 14:12:51.032633	25.71119359716871	-100.2212102284166	8.18
774	1	2026-05-18 14:12:51.451179	25.71094673872558	-100.2213410494132	8.14
775	1	2026-05-18 14:12:51.903655	25.71059865992216	-100.2215141169063	7.63
776	1	2026-05-18 14:12:52.353791	25.71047670516914	-100.2215933516977	6.28
777	1	2026-05-18 14:12:52.782926	25.71038216963479	-100.2216417204025	5.62
778	1	2026-05-18 14:12:53.206607	25.71016982400086	-100.2217427329545	5.57
779	1	2026-05-18 14:12:53.632072	25.71006035605482	-100.2217977166483	5.81
780	1	2026-05-18 14:12:54.067613	25.70983661429002	-100.2219087041629	6.61
781	1	2026-05-18 14:12:54.492217	25.70974556475878	-100.221999172887	6.0
782	1	2026-05-18 14:12:54.920515	25.7096272808671	-100.2220581672389	6.62
783	1	2026-05-18 14:12:55.349898	25.7095286793529	-100.2221102660213	6.97
784	1	2026-05-18 14:12:55.787387	25.70941818679943	-100.2221671343047	7.42
785	1	2026-05-18 14:12:56.210162	25.70935850231382	-100.2221889040901	6.73
786	1	2026-05-18 14:12:56.651847	25.70918092253	-100.2222799082243	6.27
787	1	2026-05-18 14:12:57.091032	25.70908301978004	-100.2223469994792	5.74
788	1	2026-05-18 14:12:57.524869	25.70896903927991	-100.2224093141325	6.03
789	1	2026-05-18 14:12:57.942389	25.70877046605041	-100.2225137265203	6.13
790	1	2026-05-18 14:12:58.366065	25.70865607499055	-100.2225733066746	6.43
791	1	2026-05-18 14:12:58.794938	25.7085294188473	-100.2226537767193	7.09
792	1	2026-05-18 14:12:59.349884	25.70840169252727	-100.2227292071944	7.83
793	1	2026-05-18 14:12:59.77523	25.70827092583529	-100.2228094351224	8.51
794	1	2026-05-18 14:13:00.193589	25.70802677539272	-100.2229362044136	9.35
795	1	2026-05-18 14:13:00.621792	25.70775946698783	-100.2230782376375	10.29
796	1	2026-05-18 14:13:01.083944	25.7076277878728	-100.2231521613721	10.49
797	1	2026-05-18 14:13:01.509796	25.7074943431172	-100.2232109651029	11.15
798	1	2026-05-18 14:13:01.943811	25.70723132994316	-100.2233388057124	11.37
799	1	2026-05-18 14:13:02.380025	25.70669964007611	-100.2236050390621	11.29
800	1	2026-05-18 14:13:02.801962	25.70613191177477	-100.2239264859429	7.77
801	1	2026-05-18 14:13:03.233287	25.70567056770544	-100.2241723783838	5.9
802	1	2026-05-18 14:13:03.643583	25.70550864144844	-100.2242539007375	5.79
803	1	2026-05-18 14:13:04.045725	25.70518605259144	-100.2244394014834	5.49
804	1	2026-05-18 14:13:04.481429	25.70501682573411	-100.2245349038693	5.77
805	1	2026-05-18 14:13:04.902759	25.70484873433232	-100.2246277055983	5.96
806	1	2026-05-18 14:13:05.335855	25.70467142677812	-100.2247369764472	5.75
807	1	2026-05-18 14:13:05.776602	25.70415091656615	-100.2250375706988	6.94
808	1	2026-05-18 14:13:06.18179	25.7037787607951	-100.2252365543051	6.56
809	1	2026-05-18 14:13:06.592089	25.70357569547895	-100.2253402299297	6.07
810	1	2026-05-18 14:13:07.025388	25.70335062942333	-100.2254397821217	5.32
811	1	2026-05-18 14:13:07.457729	25.70298361405104	-100.2256471155371	4.87
812	1	2026-05-18 14:13:07.89491	25.70280954556271	-100.2257503896642	5.29
813	1	2026-05-18 14:13:08.335184	25.7024711515833	-100.2259402981224	5.8
814	1	2026-05-18 14:13:08.785723	25.70230197306743	-100.2260162748489	5.66
815	1	2026-05-18 14:13:09.210281	25.70213699315514	-100.2260994912374	5.43
816	1	2026-05-18 14:13:09.659855	25.70197098857108	-100.2261722785355	5.12
817	1	2026-05-18 14:13:10.082867	25.7018070682268	-100.2262476235635	4.86
818	1	2026-05-18 14:13:10.508132	25.70149961118504	-100.2264130553821	4.48
819	1	2026-05-18 14:13:10.938293	25.70135108443854	-100.2264873201589	4.45
820	1	2026-05-18 14:13:11.351901	25.70106735361573	-100.2266346279181	5.46
821	1	2026-05-18 14:13:11.760166	25.70078055981467	-100.2267864276649	5.76
822	1	2026-05-18 14:13:12.183693	25.70062740416849	-100.2268611757701	5.46
823	1	2026-05-18 14:13:12.597166	25.70048021646053	-100.2269567030225	5.38
824	1	2026-05-18 14:13:13.020381	25.70032408826955	-100.2270422266997	5.28
825	1	2026-05-18 14:13:13.462035	25.70016776523757	-100.2271289489185	4.88
826	1	2026-05-18 14:18:16.577667	25.70000647604921	-100.227218738677	4.71
827	1	2026-05-18 14:18:17.02132	25.69984670716997	-100.2273061194491	4.63
828	1	2026-05-18 14:18:17.489581	25.69968427558655	-100.2273966164624	4.25
829	1	2026-05-18 14:18:17.907352	25.69951821169036	-100.2274884562902	3.92
830	1	2026-05-18 14:18:18.340476	25.69919429515385	-100.227654113874	3.79
831	1	2026-05-18 14:18:18.77504	25.69903275552943	-100.2277508630108	3.81
832	1	2026-05-18 14:18:19.208654	25.69886961243942	-100.2278530304565	3.66
833	1	2026-05-18 14:18:19.645955	25.69871693483471	-100.2279636259967	3.87
834	1	2026-05-18 14:18:20.08571	25.6985647425442	-100.2280778215971	4.12
835	1	2026-05-18 14:18:20.532833	25.69841370547184	-100.2281965055957	4.17
836	1	2026-05-18 14:18:20.991484	25.69826295850682	-100.2283274075845	4.41
837	1	2026-05-18 14:18:21.444901	25.69810557284845	-100.228466702112	4.37
838	1	2026-05-18 14:18:21.880222	25.69796024234737	-100.2286140602818	4.5
839	1	2026-05-18 14:18:22.332909	25.69783030327815	-100.2287628297747	4.71
840	1	2026-05-18 14:18:22.7868	25.69770015108272	-100.2289114600626	4.75
841	1	2026-05-18 14:18:23.218429	25.69756935769099	-100.2290559742845	4.54
842	1	2026-05-18 14:18:23.656653	25.69744091916477	-100.2292082109575	4.28
843	1	2026-05-18 14:18:24.101248	25.69711616124112	-100.2296365820567	4.5
844	1	2026-05-18 14:18:24.555732	25.69696282980847	-100.2298934666272	4.89
845	1	2026-05-18 14:18:24.987128	25.69689698513502	-100.2300048192423	5.48
846	1	2026-05-18 14:18:25.427048	25.69684446483815	-100.2301078195101	6.16
847	1	2026-05-18 14:18:25.877448	25.69679787205457	-100.2302359786543	4.99
848	1	2026-05-18 14:18:26.352734	25.69674013810307	-100.2303465182346	5.52
849	1	2026-05-18 14:18:26.776878	25.69667960768852	-100.2304622779655	6.22
850	1	2026-05-18 14:18:27.201434	25.69664788517197	-100.2305200091618	5.98
851	1	2026-05-18 14:18:27.631581	25.6966128096478	-100.2306016444773	6.1
852	1	2026-05-18 14:18:28.06715	25.69651683373041	-100.2308776479559	7.94
853	1	2026-05-18 14:18:28.532205	25.69645086705332	-100.2311033629464	10.66
854	1	2026-05-18 14:18:28.996761	25.69644099690725	-100.2311810369304	9.16
855	1	2026-05-18 14:18:29.440719	25.69643194744775	-100.2312195082372	11.08
856	1	2026-05-18 14:18:29.867675	25.6964117570467	-100.2312975081355	10.49
857	1	2026-05-18 14:18:30.294363	25.69641537399973	-100.2313288271379	13.99
858	1	2026-05-18 14:18:30.733957	25.69639825009336	-100.2314095515843	11.99
859	1	2026-05-18 14:18:31.185735	25.69638118846626	-100.2314665310126	13.08
860	1	2026-05-18 14:18:31.629074	25.69636143394487	-100.2315601597342	14.02
861	1	2026-05-18 14:18:32.124327	25.69634103139198	-100.2316718315165	15.09
862	1	2026-05-18 14:18:32.611386	25.69629502424742	-100.2319065724069	18.06
863	1	2026-05-18 14:18:33.551108	25.69627921727276	-100.2320146465659	19.32
864	1	2026-05-18 14:18:33.996049	25.69623090131498	-100.2320616754266	17.06
865	1	2026-05-18 14:18:34.44949	25.69625305027092	-100.2319925431887	17.2
866	1	2026-05-18 14:18:35.425793	25.69625274586134	-100.2320040043956	17.33
867	1	2026-05-18 14:18:35.865556	25.69622262689784	-100.2321315208833	12.74
868	1	2026-05-18 14:18:36.299055	25.69619256741814	-100.2322390395168	12.54
869	1	2026-05-18 14:18:36.85685	25.6960800567866	-100.2325989841304	11.47
870	1	2026-05-18 14:18:37.779103	25.69601486911638	-100.2327743764324	7.86
871	1	2026-05-18 14:18:38.211239	25.69598385921885	-100.2329012050596	6.96
872	1	2026-05-18 14:18:38.647188	25.69595302572803	-100.2330307317388	6.77
873	1	2026-05-18 14:18:39.102918	25.69592561621718	-100.233150479045	6.93
874	1	2026-05-18 14:18:39.532582	25.69589586446944	-100.2332502428351	6.72
875	1	2026-05-18 14:18:40.048882	25.69586147430579	-100.2333793918686	6.59
876	1	2026-05-18 14:18:40.519426	25.69578517545299	-100.2336335938425	7.04
877	1	2026-05-18 14:18:41.679889	25.69574425905419	-100.2337923352506	7.02
878	1	2026-05-18 14:18:42.099725	25.69571301311034	-100.2339524743176	6.91
879	1	2026-05-18 14:18:43.109625	25.69554840089355	-100.2344866500987	6.2
880	1	2026-05-18 14:18:43.575915	25.69550651089818	-100.2346326485495	6.36
881	1	2026-05-18 14:18:44.337252	25.69545924103431	-100.2347728846567	6.51
882	1	2026-05-18 14:18:44.766073	25.69536388771271	-100.2350231488987	5.96
883	1	2026-05-18 14:18:45.20414	25.69524763106887	-100.2354313747188	5.73
884	1	2026-05-18 14:18:45.665984	25.69520155279849	-100.2355680884904	5.63
885	1	2026-05-18 14:18:46.109823	25.6951060958978	-100.2358528627228	5.61
886	1	2026-05-18 14:18:46.526983	25.6950617070137	-100.2359959377566	5.64
887	1	2026-05-18 14:18:46.939889	25.69501283988835	-100.2361513530158	5.69
888	1	2026-05-18 14:18:47.360926	25.69496126206213	-100.2363055695609	6.11
889	1	2026-05-18 14:18:47.788149	25.69489206987524	-100.2366658332017	5.05
890	1	2026-05-18 14:18:48.279217	25.69484621621016	-100.2368220967068	5.6
891	1	2026-05-18 14:18:48.698689	25.69479539486526	-100.2369728015272	6.16
892	1	2026-05-18 14:18:49.486103	25.69470959227481	-100.2372410417383	7.6
893	1	2026-05-18 14:18:49.939121	25.69461661186	-100.2374921806756	9.02
894	1	2026-05-18 14:18:50.392157	25.6945726774213	-100.2376195650527	9.92
895	1	2026-05-18 14:18:50.841393	25.69453706288698	-100.2377676993869	10.54
896	1	2026-05-18 14:18:51.309012	25.69449543123635	-100.2379030128963	10.93
897	1	2026-05-18 14:18:51.738427	25.69435814392246	-100.2383258766111	6.35
898	1	2026-05-18 14:18:52.224473	25.69427538561336	-100.238556327891	5.36
899	1	2026-05-18 14:18:52.681366	25.69423639313895	-100.238676655427	5.23
900	1	2026-05-18 14:18:53.145294	25.69419431426351	-100.2387950524257	5.66
901	1	2026-05-18 14:18:53.5907	25.69414067872484	-100.2389075119938	6.16
902	1	2026-05-18 14:18:54.096965	25.69407951351022	-100.2390175930206	6.78
903	1	2026-05-18 14:18:54.539679	25.69399776742836	-100.2391143576756	7.4
904	1	2026-05-18 14:18:54.97229	25.69390174067549	-100.239203828435	8.19
905	1	2026-05-18 14:18:55.409953	25.69379049432224	-100.239245058552	8.53
906	1	2026-05-18 14:18:55.842422	25.69367991029234	-100.2392526742405	8.6
907	1	2026-05-18 14:18:56.334594	25.69343583811249	-100.2392413566511	5.82
908	1	2026-05-18 14:18:57.138721	25.69320331509254	-100.2392007199042	5.79
909	1	2026-05-18 14:18:57.983892	25.69310922842532	-100.2391898506903	5.39
910	1	2026-05-18 14:18:58.487574	25.69291016953831	-100.2391483912237	5.2
911	1	2026-05-18 14:18:59.38915	25.69280735564779	-100.2391285665625	4.9
912	1	2026-05-18 14:19:00.829929	25.69269540428246	-100.2391124247721	4.46
913	1	2026-05-18 14:19:01.264307	25.69257601489857	-100.2391007613374	4.44
914	1	2026-05-18 14:19:01.712382	25.69244012624389	-100.239088798488	4.32
915	1	2026-05-18 14:19:02.147712	25.69229386292477	-100.2390698048696	4.31
916	1	2026-05-18 14:19:02.579093	25.69214458049784	-100.2390500265203	4.52
917	1	2026-05-18 14:19:03.027586	25.69185632816085	-100.239015587478	5.33
918	1	2026-05-18 14:19:03.7276	25.69171489402787	-100.2389954238805	5.74
919	1	2026-05-18 14:19:04.250397	25.69158490217805	-100.2389723322097	6.05
920	1	2026-05-18 14:19:04.746764	25.69144095877392	-100.2389561972284	6.74
921	1	2026-05-18 14:19:05.21472	25.69129791112027	-100.2389426248362	8.72
922	1	2026-05-18 14:19:05.694488	25.69098165978214	-100.2388877279013	9.79
923	1	2026-05-18 14:19:06.203366	25.69089036238985	-100.2388693375182	10.65
924	1	2026-05-18 14:20:32.261599	25.6907690422928	-100.2388772417021	7.37
925	1	2026-05-18 14:22:32.06644	25.69067754930504	-100.2388545838999	7.18
926	1	2026-05-18 14:22:32.528636	25.69036874155789	-100.2388908143642	8.71
927	1	2026-05-18 14:22:32.968251	25.69028055165199	-100.2389306623758	9.08
928	1	2026-05-18 14:22:33.414351	25.69020286857532	-100.2389997720533	9.56
929	1	2026-05-18 14:22:33.840264	25.69015349927501	-100.2390909745184	10.77
930	1	2026-05-18 14:22:34.300278	25.69013497114737	-100.2391990836487	12.14
931	1	2026-05-18 14:22:34.718348	25.69008728962273	-100.2392989180779	12.98
932	1	2026-05-18 14:22:35.151556	25.69007336178113	-100.2394411317441	13.91
933	1	2026-05-18 14:22:35.576607	25.690049310711	-100.2396073376424	13.65
934	1	2026-05-18 14:22:36.022813	25.69003721928666	-100.2397416796019	15.4
935	1	2026-05-18 14:22:36.435533	25.69003014722447	-100.2398337240325	13.5
936	1	2026-05-18 14:22:36.865299	25.69002000410224	-100.2399608910193	14.17
937	1	2026-05-18 14:22:37.306788	25.69007420386874	-100.2400451818948	14.57
938	1	2026-05-18 14:22:37.726205	25.69010346693991	-100.2404689670773	16.23
939	1	2026-05-18 14:22:38.15883	25.69013340461705	-100.240598315905	17.21
940	1	2026-05-18 14:22:38.588351	25.69027066622784	-100.2410321655873	6.74
941	1	2026-05-18 14:22:39.039031	25.69031819685663	-100.2411681648509	5.04
942	1	2026-05-18 14:22:39.466882	25.69039278755407	-100.2414445647538	4.61
943	1	2026-05-18 14:22:39.910986	25.6904365239175	-100.2416045649214	4.32
944	1	2026-05-18 14:22:40.368311	25.69055840533052	-100.2419276476874	4.92
945	1	2026-05-18 14:22:40.810407	25.69062165433763	-100.2420757775335	5.05
946	1	2026-05-18 14:22:41.231325	25.6907417021697	-100.2423708710521	4.64
947	1	2026-05-18 14:22:41.675486	25.69078297394361	-100.24253215977	4.5
948	1	2026-05-18 14:22:42.207514	25.69080830555001	-100.2426988999911	4.78
949	1	2026-05-18 14:22:42.762875	25.69082171354994	-100.2428703192845	5.28
950	1	2026-05-18 14:22:43.203907	25.69084247883928	-100.2430374702987	5.38
951	1	2026-05-18 14:22:43.62701	25.69086553754956	-100.2432257505056	5.98
952	1	2026-05-18 14:22:44.126569	25.69089140651759	-100.2436059326911	7.81
953	1	2026-05-18 14:22:44.563413	25.69089191630626	-100.243804359806	9.48
954	1	2026-05-18 14:22:45.009715	25.69089578898193	-100.244012798225	10.76
955	1	2026-05-18 14:22:45.465248	25.69086289561189	-100.2441979985296	12.11
956	1	2026-05-18 14:22:46.138664	25.69085830023734	-100.2443944936275	12.84
957	1	2026-05-18 14:22:46.781839	25.69082417953202	-100.2445914534983	13.88
958	1	2026-05-18 14:22:47.200617	25.69070774922621	-100.2450035747013	17.53
959	1	2026-05-18 14:22:47.624023	25.69045815213864	-100.2455977969668	20.4
960	1	2026-05-18 14:22:48.060418	25.69025472467037	-100.2459441037547	16.06
961	1	2026-05-18 14:22:48.490273	25.69014986243073	-100.2461176101488	15.96
962	1	2026-05-18 14:22:48.918548	25.69003784853897	-100.246283107622	16.97
963	1	2026-05-18 14:22:49.359318	25.68990727967836	-100.2464398678959	18.19
964	1	2026-05-18 14:22:49.787024	25.68977372234968	-100.2465786805	19.56
965	1	2026-05-18 14:22:50.219151	25.68952916535288	-100.2468080136876	14.66
966	1	2026-05-18 14:22:50.659667	25.68934455882941	-100.2468839945139	11.2
967	1	2026-05-18 14:22:51.0784	25.68907742653541	-100.247099335947	6.0
968	1	2026-05-18 14:22:51.514553	25.68894587210315	-100.2472040656762	5.16
969	1	2026-05-18 14:22:51.956696	25.68880261561655	-100.247319735131	4.44
970	1	2026-05-18 14:22:52.382205	25.68865548760015	-100.2474528237459	4.06
971	1	2026-05-18 14:22:52.805227	25.68850805439367	-100.2475740754361	3.71
972	1	2026-05-18 14:22:53.239594	25.68835543829245	-100.2477079758411	4.05
973	1	2026-05-18 14:22:53.664443	25.68805929130988	-100.2479618528263	3.93
974	1	2026-05-18 14:22:54.099921	25.68790747564717	-100.2480945502347	4.41
975	1	2026-05-18 14:22:54.506874	25.68776056991242	-100.2482347911842	4.72
976	1	2026-05-18 14:22:54.933554	25.68761701482817	-100.2483747179096	4.3
977	1	2026-05-18 14:22:55.424131	25.68745896882317	-100.2485151293067	4.04
978	1	2026-05-18 14:22:55.857063	25.68729789625371	-100.2486564832926	3.83
979	1	2026-05-18 14:22:56.275903	25.68713796339808	-100.2487940985731	3.76
980	1	2026-05-18 14:22:56.72812	25.68697289118109	-100.2489443040314	4.04
981	1	2026-05-18 14:22:57.175598	25.68665498240785	-100.249238739617	3.91
982	1	2026-05-18 14:22:57.66944	25.68647500515332	-100.2493911675877	3.61
983	1	2026-05-18 14:22:58.084325	25.68631993385202	-100.2495452187785	3.78
984	1	2026-05-18 14:22:58.527525	25.68617749775932	-100.2497087823186	4.11
985	1	2026-05-18 14:22:58.968281	25.68604158559016	-100.2498818565806	4.28
986	1	2026-05-18 14:22:59.403896	25.68591536645954	-100.2500668377559	4.83
987	1	2026-05-18 14:22:59.829099	25.68580076927369	-100.2502613164504	5.55
988	1	2026-05-18 14:23:00.264908	25.68550354025651	-100.2508623551019	6.06
989	1	2026-05-18 14:23:00.686199	25.68542274567589	-100.2510779162463	6.79
990	1	2026-05-18 14:23:01.126926	25.68535660657271	-100.2512892074256	7.48
991	1	2026-05-18 14:23:01.559674	25.68530681428414	-100.2515117867016	8.09
992	1	2026-05-18 14:23:02.011534	25.68527591618324	-100.251740572497	9.03
993	1	2026-05-18 14:23:02.434966	25.68524203654506	-100.2519878053974	9.3
994	1	2026-05-18 14:23:16.208297	25.68522225847926	-100.252236839755	7.69
995	1	2026-05-18 14:23:16.699454	25.68523168507081	-100.2524891762637	8.18
996	1	2026-05-18 14:23:17.152225	25.6852535143017	-100.2527267675887	8.6
997	1	2026-05-18 14:23:17.599174	25.68529598033732	-100.2529704035402	8.86
998	1	2026-05-18 14:23:18.034472	25.68531433688896	-100.2532160257379	6.52
999	1	2026-05-18 14:23:18.46785	25.68536830091576	-100.2534636948743	6.0
1000	1	2026-05-18 14:23:18.923692	25.6854126027884	-100.2537097521586	6.49
1001	1	2026-05-18 14:23:19.347054	25.68544862330688	-100.2539623515636	6.94
1002	1	2026-05-18 14:23:19.75767	25.68550688215831	-100.2544628765788	7.86
1003	1	2026-05-18 14:23:20.239808	25.68554693803151	-100.254719457068	8.41
1004	1	2026-05-18 14:23:20.666552	25.68559109562682	-100.2549715672932	9.22
1005	1	2026-05-18 14:23:21.093124	25.68563642037874	-100.2552212250064	9.1
1006	1	2026-05-18 14:23:21.53398	25.68567210484201	-100.2556731214122	8.38
1007	1	2026-05-18 14:23:21.963097	25.68569380834075	-100.2559020087355	9.1
1008	1	2026-05-18 14:23:22.396857	25.68569013967792	-100.2561189731928	9.86
1009	1	2026-05-18 14:23:22.82476	25.6856685618785	-100.2563570609951	10.35
1010	1	2026-05-18 14:23:23.881768	25.68563448324292	-100.2566044198713	10.69
1011	1	2026-05-18 14:23:24.475254	25.68559048790712	-100.2568902051598	7.9
1012	1	2026-05-18 14:23:24.882519	25.68555759610002	-100.2571323436979	7.97
1013	1	2026-05-18 14:23:25.323925	25.68550011940419	-100.2573585835665	7.89
1014	1	2026-05-18 14:23:25.752329	25.68545430671075	-100.2575988221386	7.79
1015	1	2026-05-18 14:23:26.227964	25.68542795187302	-100.2578494584223	7.43
1016	1	2026-05-18 14:23:26.657058	25.6853874806737	-100.2580703543368	6.53
1017	1	2026-05-18 14:23:27.098784	25.68533637010177	-100.2583240216986	6.13
1018	1	2026-05-18 14:23:27.556066	25.68526068893357	-100.2585708915864	5.76
1019	1	2026-05-18 14:23:28.006864	25.68516785540558	-100.2587930767046	6.3
1020	1	2026-05-18 14:25:10.080053	25.68495085745074	-100.2592133119092	8.19
1021	1	2026-05-18 14:25:10.590682	25.68483155074098	-100.2594166607725	9.18
1022	1	2026-05-18 14:25:11.169827	25.68468352904485	-100.2595920090533	10.46
1023	1	2026-05-18 14:25:11.606492	25.68454091678032	-100.2597770508948	11.73
1024	1	2026-05-18 14:25:12.087665	25.68438656599578	-100.2599492065014	13.0
1025	1	2026-05-18 14:25:12.544787	25.68405433237558	-100.2603198992463	13.56
1026	1	2026-05-18 14:25:12.975442	25.6837182125867	-100.2606572617671	13.41
1027	1	2026-05-18 14:25:13.483197	25.68355868488782	-100.2608417672433	13.83
1028	1	2026-05-18 14:25:13.950607	25.68339508399351	-100.2610549418033	13.1
1029	1	2026-05-18 14:25:14.39808	25.68298341509535	-100.26153585632	13.22
1030	1	2026-05-18 14:25:14.822952	25.68290241380609	-100.2617157313445	15.36
1031	1	2026-05-18 14:25:15.281043	25.68282180281661	-100.2620529500453	18.96
1032	1	2026-05-18 14:25:15.719773	25.68279491997938	-100.2622549338857	21.4
1033	1	2026-05-18 14:25:16.149458	25.68275893334227	-100.2625124512488	21.45
1034	1	2026-05-18 14:25:16.587729	25.68273761366121	-100.2626988262513	17.59
1035	1	2026-05-18 14:25:17.22062	25.68265824175927	-100.263148345148	16.32
1036	1	2026-05-18 14:25:17.635486	25.68261845141809	-100.263380427948	14.73
1037	1	2026-05-18 14:25:18.033467	25.68255017889398	-100.2639773914854	8.17
1038	1	2026-05-18 14:25:18.458769	25.68247961784595	-100.2644743740985	8.3
1039	1	2026-05-18 14:25:18.901284	25.68245132432573	-100.2647217009457	7.28
1040	1	2026-05-18 14:25:19.348384	25.68242650164045	-100.264975914176	5.08
1041	1	2026-05-18 14:25:19.843581	25.68239411837907	-100.2652049812027	4.29
1042	1	2026-05-18 14:25:20.276699	25.68237464544713	-100.2654771868031	4.01
1043	1	2026-05-18 14:25:20.729179	25.68236624934664	-100.2657301136089	4.43
1044	1	2026-05-18 14:25:21.157693	25.68236383508652	-100.2659835886541	5.1
1045	1	2026-05-18 14:25:21.578763	25.68237641769212	-100.2664926119258	5.46
1046	1	2026-05-18 14:25:21.997172	25.68243510721928	-100.2672199349776	7.15
1047	1	2026-05-18 14:25:22.448103	25.68245456376069	-100.2674670466253	13.59
1048	1	2026-05-18 14:25:22.881601	25.68247232151544	-100.26771153912	15.72
1049	1	2026-05-18 14:25:23.291333	25.68248827034296	-100.267951790389	11.83
1050	1	2026-05-18 14:25:23.773037	25.68252029730595	-100.2686397828059	5.51
1051	1	2026-05-18 14:25:24.207415	25.68251876662616	-100.2688576692682	4.9
1052	1	2026-05-18 14:25:24.640661	25.68252696001598	-100.2692774663789	5.42
1053	1	2026-05-18 14:25:25.036517	25.68251791621043	-100.2694900393178	6.46
1054	1	2026-05-18 14:25:25.449219	25.68249195812793	-100.2696814845891	7.08
1055	1	2026-05-18 14:25:25.879335	25.68248138650246	-100.2698670126532	7.26
1056	1	2026-05-18 14:25:26.395922	25.68246696311462	-100.2700656578139	7.45
1057	1	2026-05-18 14:25:26.837075	25.68244151461062	-100.2702574142872	7.48
1058	1	2026-05-18 14:25:27.259647	25.68241094335135	-100.2704401968198	7.55
1059	1	2026-05-18 14:25:27.692987	25.68237939983642	-100.2706052164338	6.68
1060	1	2026-05-18 14:25:28.127922	25.68235176818166	-100.2707434810679	5.64
1061	1	2026-05-18 14:25:28.575979	25.68232397081811	-100.2708930090986	4.83
1062	1	2026-05-18 14:25:29.017866	25.68230957466194	-100.2710396429668	4.4
1063	1	2026-05-18 14:25:29.436546	25.68227770506521	-100.271166293281	4.23
1064	1	2026-05-18 14:25:29.846739	25.68224155766962	-100.2712849289768	4.22
1065	1	2026-05-18 14:25:30.277624	25.68219654205357	-100.2714168228741	4.51
1066	1	2026-05-18 14:25:30.695453	25.68215363931176	-100.2715419941571	5.08
1067	1	2026-05-18 14:25:31.128266	25.68211764537785	-100.2716737309663	5.37
1068	1	2026-05-18 14:25:31.563409	25.682024062441	-100.2719335832297	5.86
1069	1	2026-05-18 14:25:31.999761	25.68197323191094	-100.2720523119258	5.76
1070	1	2026-05-18 14:25:32.440048	25.68191220374009	-100.2721777911274	5.23
1071	1	2026-05-18 14:25:32.857458	25.68184168037429	-100.2722935232859	5.85
1072	1	2026-05-18 14:25:33.27869	25.68176445888608	-100.2724058801614	6.18
1073	1	2026-05-18 14:25:33.789182	25.6816721703604	-100.2725015311793	6.68
1074	1	2026-05-18 14:25:34.212264	25.68159786303349	-100.2725690611275	6.3
1075	1	2026-05-18 14:25:34.623128	25.68151297178193	-100.2726529533909	6.96
1076	1	2026-05-18 14:25:35.063052	25.68145803836869	-100.2726774607613	5.74
1077	1	2026-05-18 14:25:35.494382	25.68123035865496	-100.2728872658343	3.53
1078	1	2026-05-18 14:25:35.927327	25.68111645835632	-100.2729682164737	3.76
1079	1	2026-05-18 14:25:36.367155	25.68101489056667	-100.2730565778045	4.37
1080	1	2026-05-18 14:25:36.814493	25.68092801741659	-100.2731703809972	4.92
1081	1	2026-05-18 14:25:37.27799	25.68083952660151	-100.2732771993776	5.53
1082	1	2026-05-18 14:25:37.785188	25.68066581376546	-100.2734952959178	7.11
1083	1	2026-05-18 14:25:38.444641	25.68053820158451	-100.2736863797809	7.33
1084	1	2026-05-18 14:25:38.887551	25.68049129451689	-100.2737813209304	7.6
1085	1	2026-05-18 14:25:39.30802	25.68045590639181	-100.2738727958448	7.22
1086	1	2026-05-18 14:25:39.757186	25.68041656137198	-100.2739486475456	5.69
1087	1	2026-05-18 14:25:40.186703	25.6803846425732	-100.2740440396347	5.96
1088	1	2026-05-18 14:25:40.609007	25.68032751379994	-100.274130625416	5.9
1089	1	2026-05-18 14:25:41.037021	25.68030632758241	-100.2742616582724	6.38
1090	1	2026-05-18 14:25:41.466104	25.68018224264863	-100.2744644439202	7.16
1091	1	2026-05-18 14:25:41.898406	25.6801134262009	-100.2745671595045	7.94
1092	1	2026-05-18 14:25:42.325924	25.68004297191356	-100.2746673847779	6.95
1093	1	2026-05-18 14:28:09.992093	25.67988959796565	-100.2748440298886	7.25
1094	1	2026-05-18 14:28:10.434331	25.67981482554264	-100.2749097625687	6.32
1095	1	2026-05-18 14:28:10.875656	25.67975873796258	-100.2749680616879	6.27
1096	1	2026-05-18 14:28:11.312221	25.67972301210666	-100.2750012493919	5.95
1097	1	2026-05-18 14:28:11.849581	25.67969162818493	-100.2750397905962	5.62
1098	1	2026-05-18 14:28:12.329994	25.6796375375979	-100.2750697731053	6.12
1099	1	2026-05-18 14:28:12.781086	25.67959470509282	-100.2750987929718	6.44
1100	1	2026-05-18 14:28:13.192158	25.67954402951764	-100.2751312438341	7.09
1101	1	2026-05-18 14:28:13.627155	25.67950534496975	-100.2751441584219	7.48
1102	1	2026-05-18 14:28:14.104661	25.67942624297379	-100.2751937259299	6.86
1103	1	2026-05-18 14:28:14.553408	25.67932360046915	-100.275221945825	7.71
1104	1	2026-05-18 14:28:15.013588	25.67926524475806	-100.2752437819022	8.43
1105	1	2026-05-18 14:28:15.444153	25.6792044697811	-100.275271820782	9.25
1106	1	2026-05-18 14:28:15.877403	25.6791396318743	-100.2753070091756	10.02
1107	1	2026-05-18 14:28:16.315651	25.67907259917894	-100.2753384669064	10.76
1108	1	2026-05-18 14:28:16.757312	25.67901570415647	-100.2754036495689	11.22
1109	1	2026-05-18 14:28:17.180227	25.67898030832015	-100.2753712228935	10.23
1110	1	2026-05-18 14:28:17.642483	25.67888399649143	-100.2753583963642	9.17
1111	1	2026-05-18 14:28:18.095036	25.67878437037229	-100.2753743563571	8.32
1112	1	2026-05-18 14:28:18.551201	25.67874435955711	-100.2753638152057	6.97
1113	1	2026-05-18 14:28:18.977156	25.67869195460466	-100.2753675666296	6.63
1114	1	2026-05-18 14:28:19.455936	25.67862886476254	-100.2753991515689	6.87
1115	1	2026-05-18 14:28:19.908262	25.67850992461921	-100.2754561397847	7.47
1116	1	2026-05-18 14:28:20.346976	25.67844729546819	-100.2754821784462	7.78
1117	1	2026-05-18 14:28:20.797079	25.67837855769126	-100.2755421199205	5.91
1118	1	2026-05-18 14:28:21.220953	25.67831518763164	-100.275566525167	4.6
1119	1	2026-05-18 14:59:14.266196	25.65	-100.4	5.0
1120	1	2026-05-18 15:01:08.453651	25.65	-100.4	5.0
1121	1	2026-05-18 15:01:24.31374	25.65	-100.4	5.0
1122	1	2026-05-18 15:03:18.755546	25.67823727977026	-100.2756079235727	4.41
1123	1	2026-05-18 15:03:19.236245	25.67817122212543	-100.2756432263827	4.86
1124	1	2026-05-18 15:03:19.762941	25.67809373982311	-100.275661749224	6.04
1125	1	2026-05-18 15:03:20.241579	25.677898102841	-100.2757544767881	4.57
1126	1	2026-05-18 15:03:20.677481	25.67781642635827	-100.2758008421455	5.15
1127	1	2026-05-18 15:03:21.159231	25.67774997018056	-100.2758383868195	4.49
1128	1	2026-05-18 15:03:21.644521	25.67766995751246	-100.2758905082629	4.76
1129	1	2026-05-18 15:03:22.076333	25.67760122884381	-100.2759440174819	4.94
1130	1	2026-05-18 15:03:22.527449	25.67752684732067	-100.2759754532352	4.73
1131	1	2026-05-18 15:03:22.937565	25.67746544140277	-100.2760168689383	4.15
1132	1	2026-05-18 15:03:23.364201	25.6773934374467	-100.2760675832219	4.73
1133	1	2026-05-18 15:03:23.802947	25.67733511706358	-100.2761043556649	3.85
1134	1	2026-05-18 15:03:24.287975	25.67727830299598	-100.2761415220158	4.39
1135	1	2026-05-18 15:03:24.736089	25.67721540406523	-100.2761847107395	3.8
1136	1	2026-05-18 15:03:25.261708	25.67711258632104	-100.2762595412051	4.13
1137	1	2026-05-18 15:03:25.6964	25.67706150658695	-100.2762924826908	4.57
1138	1	2026-05-18 15:03:26.124956	25.67701061517652	-100.2763307601276	4.79
1139	1	2026-05-18 15:03:26.562488	25.67690757367112	-100.2764206156994	5.52
1140	1	2026-05-18 15:03:27.029358	25.67676083015096	-100.2765232503327	3.19
1141	1	2026-05-18 15:03:27.448869	25.67670391657508	-100.2765778812995	2.91
1142	1	2026-05-18 15:03:27.900955	25.67664770134092	-100.2766332759672	3.13
1143	1	2026-05-18 15:03:28.339762	25.67636332353005	-100.2769513220668	4.51
1144	1	2026-05-18 15:03:28.768035	25.67628905901685	-100.2770139751804	4.88
1145	1	2026-05-18 15:03:29.218885	25.67617576588606	-100.2771563582156	2.85
1146	1	2026-05-18 15:03:29.656042	25.67610172097358	-100.2772286717444	3.09
1147	1	2026-05-18 15:03:30.097015	25.67596999392772	-100.2773921807379	3.78
1148	1	2026-05-18 15:03:30.552299	25.67590767108666	-100.2774771764508	14.19
1149	1	2026-05-18 15:03:31.021006	25.6757682074163	-100.2776777638263	7.12
1150	1	2026-05-18 15:03:31.463207	25.67564233818912	-100.2778905510156	13.9
1151	1	2026-05-18 15:03:31.918966	25.67561052278506	-100.2779570011744	5.15
1152	1	2026-05-18 15:03:32.365341	25.67555635326958	-100.278053594056	4.27
1153	1	2026-05-18 15:03:32.804072	25.67550600979299	-100.2781572505449	4.16
1154	1	2026-05-18 15:03:33.281052	25.67546500488259	-100.2782385352982	3.83
1155	1	2026-05-18 15:03:33.753803	25.67542349532663	-100.2783268311315	3.91
1156	1	2026-05-18 15:03:34.18322	25.6753481615478	-100.2785023192035	4.48
1157	1	2026-05-18 15:03:34.62392	25.67531438198423	-100.2785824543303	4.47
1158	1	2026-05-18 15:03:35.057936	25.67526390419339	-100.2786377644903	3.56
1159	1	2026-05-18 15:03:35.482262	25.67519979332903	-100.2787737502672	4.11
1160	1	2026-05-18 15:03:35.921235	25.67510572449067	-100.2789987408735	5.07
1161	1	2026-05-18 15:03:36.37133	25.67506823306402	-100.2791510860663	5.97
1162	1	2026-05-18 15:03:36.792961	25.67502085447087	-100.2793031389228	6.75
1163	1	2026-05-18 15:03:37.230583	25.67499966368608	-100.2793803701744	7.34
1164	1	2026-05-18 15:03:37.647779	25.67498677070117	-100.2794814592117	5.31
1165	1	2026-05-18 15:03:38.072528	25.67496992460661	-100.2795752388283	5.17
1166	1	2026-05-18 15:03:38.531973	25.6749552668387	-100.2796586160787	5.15
1167	1	2026-05-18 15:03:38.972137	25.67494039807139	-100.2797415303938	5.21
1168	1	2026-05-18 15:03:39.429136	25.67492368170894	-100.2798158415109	5.27
1169	1	2026-05-18 15:03:39.873032	25.67489467633393	-100.2799306895288	4.4
1170	1	2026-05-18 15:03:40.306214	25.67487984102072	-100.2800208575254	4.09
1171	1	2026-05-18 15:03:40.778923	25.67488362800351	-100.2800869514703	4.27
1172	1	2026-05-18 15:03:41.233321	25.67487622620332	-100.2801440756363	4.41
1173	1	2026-05-18 15:03:41.710344	25.67486918006737	-100.2802025493767	4.39
1174	1	2026-05-18 15:03:42.145809	25.67484209828491	-100.2802537941893	3.52
1175	1	2026-05-18 15:03:42.615386	25.67483711649715	-100.2803249059904	4.12
1176	1	2026-05-18 15:03:43.061803	25.67483504973722	-100.2803917898443	4.52
1177	1	2026-05-18 15:03:43.52231	25.67483367626436	-100.2804625359379	4.61
1178	1	2026-05-18 15:03:43.997432	25.6748109198897	-100.2805353831945	4.78
1179	1	2026-05-18 15:03:44.466977	25.67480822581039	-100.2805897666395	4.69
1180	1	2026-05-18 15:03:45.024328	25.6748020740821	-100.280651330537	4.59
1181	1	2026-05-18 15:03:45.547411	25.67479668042229	-100.2807093050877	4.11
1182	1	2026-05-18 15:03:45.985854	25.67478838192586	-100.2807644898754	3.91
1183	1	2026-05-18 15:03:46.443561	25.67478095118916	-100.2808173432901	4.09
1184	1	2026-05-18 15:03:46.915272	25.67478095118916	-100.2808173432901	4.09
1185	1	2026-05-18 15:03:47.426372	25.67478095118916	-100.2808173432901	4.09
1186	1	2026-05-18 15:03:47.919968	25.67384256674912	-100.2846489378809	9.57
1187	1	2026-05-18 15:03:48.383147	25.6738298145507	-100.284725658617	9.45
1188	1	2026-05-18 15:03:48.825291	25.67381279940751	-100.2847463847729	9.23
1189	1	2026-05-18 15:03:49.275419	25.67380851156195	-100.2847674452875	9.07
1190	1	2026-05-18 15:03:49.743536	25.67381434682618	-100.2847623938075	8.86
1191	1	2026-05-18 15:03:50.224687	25.67381268165664	-100.2847952167524	8.66
1192	1	2026-05-18 15:03:50.631769	25.67379619143096	-100.2848076716938	8.5
1193	1	2026-05-18 15:03:51.074237	25.67379165811816	-100.2848315702677	8.4
1194	1	2026-05-18 15:03:51.51229	25.67378862872257	-100.2848560901575	8.35
1195	1	2026-05-18 15:03:51.961421	25.67378652801002	-100.2848755260606	8.16
1196	1	2026-05-18 15:03:52.4278	25.67378239897124	-100.2849212929463	8.01
1197	1	2026-05-18 15:03:52.89254	25.67375891323861	-100.2849545044388	7.83
1198	1	2026-05-18 15:03:53.345215	25.67374441565897	-100.2850050256998	7.53
1199	1	2026-05-18 15:03:53.918679	25.67372993022618	-100.2850655463222	7.22
1200	1	2026-05-18 15:03:54.407349	25.673718638584	-100.2851108513685	6.82
1201	1	2026-05-18 15:03:54.868406	25.67367387431598	-100.2851947194207	6.3
1202	1	2026-05-18 15:03:55.362692	25.67364428084925	-100.2852681199245	5.84
1203	1	2026-05-18 15:03:55.826659	25.67363606472954	-100.2852928528582	5.76
1204	1	2026-05-18 15:03:56.419543	25.67363621285847	-100.2853053344898	5.72
1205	1	2026-05-18 15:03:57.068875	25.67363426236152	-100.2853236646334	5.61
1206	1	2026-05-18 15:03:57.51126	25.67361279045462	-100.2853469229942	5.53
1207	1	2026-05-18 15:03:58.002413	25.67361376909139	-100.2853523100524	5.93
1208	1	2026-05-18 15:03:58.467298	25.67361431043192	-100.2853586932096	5.73
1209	1	2026-05-18 15:03:59.018944	25.67361302839088	-100.2853770504176	5.5
1210	1	2026-05-18 15:03:59.500125	25.67361662789068	-100.2853822698128	5.55
1211	1	2026-05-18 15:03:59.958571	25.67360177619541	-100.2853694364312	5.16
1212	1	2026-05-18 15:04:00.390125	25.67361157923536	-100.285349380613	5.35
1213	1	2026-05-18 15:04:00.813063	25.67360902236117	-100.2853919620347	5.09
1214	1	2026-05-18 15:04:01.332491	25.67359754291724	-100.2854315472176	4.95
1215	1	2026-05-18 15:04:01.742225	25.67357103921331	-100.285450013739	4.85
1216	1	2026-05-18 15:04:02.163822	25.67355278490334	-100.2855003924925	4.92
1217	1	2026-05-18 15:04:02.584632	25.67353845523978	-100.2855414343815	4.82
1218	1	2026-05-18 15:04:03.041408	25.6735247495148	-100.2855852644267	5.37
1219	1	2026-05-18 15:04:03.491659	25.67350945120849	-100.2856333605098	5.01
1220	1	2026-05-18 15:04:03.921266	25.67349876193355	-100.285681488438	5.64
1221	1	2026-05-18 15:10:19.023595	25.67346549230841	-100.2857087991283	5.19
1222	1	2026-05-18 15:10:19.584714	25.67342809090703	-100.2858176950384	6.78
1223	1	2026-05-18 15:10:20.002341	25.67342029190033	-100.2858227784085	7.23
1224	1	2026-05-18 15:10:20.443834	25.67342487575061	-100.2858129242528	7.17
1225	1	2026-05-18 15:10:20.884857	25.67342626956384	-100.2858141751058	7.49
1226	1	2026-05-18 15:10:21.316082	25.67342621009843	-100.2858209328272	7.26
1227	1	2026-05-18 15:10:21.755484	25.67342491918638	-100.2858383408572	7.11
1228	1	2026-05-18 15:10:22.199964	25.67342361952628	-100.2858267645729	6.99
1229	1	2026-05-18 15:10:22.632169	25.67342832357826	-100.2858297821998	6.57
1230	1	2026-05-18 15:10:23.078567	25.67341173474763	-100.2858417261423	6.24
1231	1	2026-05-18 15:10:23.52139	25.6734092378506	-100.2858548248173	6.16
1232	1	2026-05-18 15:10:23.92324	25.6734023261733	-100.2858814251567	5.95
1233	1	2026-05-18 15:10:24.364415	25.67338997586925	-100.2859235420296	5.83
1234	1	2026-05-18 15:10:24.893145	25.67335635932399	-100.2859776168262	5.62
1235	1	2026-05-18 15:10:25.34981	25.67334210898847	-100.2860201264665	5.97
1236	1	2026-05-18 15:10:25.777117	25.67331690574137	-100.2860903919548	7.32
1237	1	2026-05-18 15:10:26.222162	25.67330489913182	-100.2861238418454	7.81
1238	1	2026-05-18 15:10:26.682933	25.67329300012513	-100.2861579593541	8.44
1239	1	2026-05-18 15:10:27.105659	25.67328011841226	-100.2861976614842	9.11
1240	1	2026-05-18 15:10:27.521445	25.67324728359465	-100.2862242735794	9.02
1241	1	2026-05-18 15:10:28.022697	25.67322655511983	-100.2862691480244	9.24
1242	1	2026-05-18 15:10:28.46134	25.67321486184753	-100.2862939302021	9.49
1243	1	2026-05-18 15:10:28.907818	25.67319432616183	-100.2863409805351	9.81
1244	1	2026-05-18 15:10:29.456435	25.67316547210109	-100.2864120456344	11.32
1245	1	2026-05-18 15:10:29.883319	25.67316004002526	-100.2864365197136	11.8
1246	1	2026-05-18 15:10:30.33041	25.67316138778535	-100.2864392892235	12.56
1247	1	2026-05-18 15:10:30.752209	25.67314331080669	-100.2864916802268	13.96
1248	1	2026-05-18 15:10:31.234761	25.67313375864162	-100.2865250232811	14.91
1249	1	2026-05-18 15:10:31.692943	25.67311078485362	-100.2865220212624	13.72
1250	1	2026-05-18 15:10:32.115306	25.67310244713681	-100.2865403490201	14.52
1251	1	2026-05-18 15:10:32.552953	25.67309338347925	-100.28656133958	15.28
1252	1	2026-05-18 15:10:33.033123	25.67307162029887	-100.2866140726559	16.42
1253	1	2026-05-18 15:51:27.443659	25.67283401502442	-100.2872017708057	61.32
1254	1	2026-05-18 15:51:27.93011	25.67279135894267	-100.2873485990718	31.67
1255	1	2026-05-18 15:51:28.371159	25.67277121535789	-100.2874200877481	30.48
1256	1	2026-05-18 15:51:28.808144	25.67275756854323	-100.2874676366007	30.52
1257	1	2026-05-18 15:51:29.255964	25.67274465749727	-100.2874937590442	10.89
1258	1	2026-05-18 15:51:29.689935	25.67273384219736	-100.2875451550869	11.46
1259	1	2026-05-18 15:51:30.130344	25.67272440500372	-100.2876022534948	11.93
1260	1	2026-05-18 15:51:30.557614	25.67269616922988	-100.2876497486546	11.87
1261	1	2026-05-18 15:51:30.989991	25.67267728874399	-100.2877139456166	12.25
1262	1	2026-05-18 15:51:31.428062	25.67263368818601	-100.2878598954309	12.73
1263	1	2026-05-18 15:51:31.868163	25.67261361375732	-100.2879651997762	15.46
1264	1	2026-05-18 15:51:32.327211	25.67259289356148	-100.288100407359	13.16
1265	1	2026-05-18 15:51:32.76641	25.67262815013293	-100.2878883609127	8.99
1266	1	2026-05-18 15:51:33.221156	25.67260934389134	-100.287949695052	8.29
1267	1	2026-05-18 15:51:33.665917	25.67259382183948	-100.2879996757981	12.07
1268	1	2026-05-18 15:51:34.119109	25.67257413518813	-100.2880705932259	12.66
1269	1	2026-05-18 15:51:34.587766	25.672563782881	-100.2881086014306	11.32
1270	1	2026-05-18 15:51:35.033519	25.67255270194483	-100.2881593923747	10.14
1271	1	2026-05-18 15:51:35.547845	25.67254021539853	-100.2882275762132	9.69
1272	1	2026-05-18 15:51:36.002172	25.67253222579742	-100.2882628076856	10.13
1273	1	2026-05-18 15:51:36.422329	25.67256887861845	-100.2881185075579	7.07
1274	1	2026-05-18 15:51:36.873219	25.67256415488447	-100.2881251811052	6.63
1275	1	2026-05-18 15:51:37.333712	25.67255805110084	-100.2881337419791	6.0
1276	1	2026-05-18 15:51:37.867556	25.67254264265641	-100.2881839905705	6.37
1277	1	2026-05-18 15:51:38.348461	25.67252653828498	-100.2882395530661	6.84
1278	1	2026-05-18 15:51:38.80247	25.67250159673458	-100.288362027124	7.53
1279	1	2026-05-18 15:51:39.266886	25.67247094955234	-100.2884991992003	8.74
1280	1	2026-05-18 15:51:39.718165	25.67246404980952	-100.2885521318584	8.92
1281	1	2026-05-18 15:51:40.196884	25.67243562175979	-100.2886712161956	9.14
1282	1	2026-05-18 15:51:40.655596	25.67241453866419	-100.2887315049762	9.78
1283	1	2026-05-18 15:51:41.099801	25.67239758313162	-100.2887969800518	10.37
1284	1	2026-05-18 15:51:41.538792	25.67236296484007	-100.288897152618	9.98
1285	1	2026-05-18 15:51:41.973649	25.6723556782131	-100.2889339607106	10.38
1286	1	2026-05-18 15:51:42.429691	25.67233210232	-100.2890267397844	11.0
1287	1	2026-05-18 15:51:42.913308	25.67232237354905	-100.2890457433539	9.34
1288	1	2026-05-18 15:51:43.352094	25.6723193464031	-100.2890522286071	9.37
1289	1	2026-05-18 15:51:43.823786	25.67232472974989	-100.2890553343228	9.35
1290	1	2026-05-18 15:51:44.294333	25.67232896934866	-100.2890494436771	9.35
1291	1	2026-05-18 15:51:44.739153	25.6723314024116	-100.2890495360739	9.48
1292	1	2026-05-18 15:51:45.368854	25.67236819576631	-100.2889286492106	8.81
1293	1	2026-05-18 15:51:45.818581	25.672387781409	-100.2889174409907	7.59
1294	1	2026-05-18 15:51:46.267538	25.67238189824052	-100.2888778873611	6.9
1295	1	2026-05-18 15:51:46.676575	25.67238641458038	-100.2888611565633	6.62
1296	1	2026-05-18 15:51:47.118293	25.67238531334321	-100.2888652369374	6.36
1297	1	2026-05-18 15:51:47.58815	25.67238149242699	-100.2888793918412	6.78
1298	1	2026-05-18 15:51:48.057949	25.67237931390186	-100.2888874623835	6.44
1299	1	2026-05-18 15:51:48.520362	25.67237931389394	-100.2888874623809	6.42
1300	1	2026-05-18 15:51:49.023609	25.67238645935656	-100.2888609914727	9.77
1301	1	2026-05-18 15:51:49.458593	25.67238360663474	-100.2888715595784	10.01
1302	1	2026-05-18 15:51:49.902885	25.67238083277661	-100.2888818355739	10.22
1303	1	2026-05-18 15:51:50.393731	25.67237716526137	-100.288895422143	11.5
1304	1	2026-05-18 15:51:50.894004	25.67237340764193	-100.2889093425427	10.88
1305	1	2026-05-18 15:51:51.34299	25.67235386779147	-100.2889817294437	11.1
1306	1	2026-05-18 15:51:51.796396	25.67231960630408	-100.2891071174533	7.51
1307	1	2026-05-18 15:51:52.262299	25.67230669407986	-100.2891564902168	7.45
1308	1	2026-05-18 15:51:52.753502	25.67229002112571	-100.2892133220025	7.23
1309	1	2026-05-18 15:51:53.259915	25.67226589094944	-100.2892940721364	7.64
1310	1	2026-05-18 15:51:53.709548	25.67225241843376	-100.2893346985573	8.27
1311	1	2026-05-18 15:51:54.17509	25.67224139542103	-100.2893679384964	8.31
1312	1	2026-05-18 15:51:54.658116	25.67223060799699	-100.2893985901267	8.15
1313	1	2026-05-18 15:51:55.158149	25.67221646390055	-100.289398755439	6.98
1314	1	2026-05-18 15:51:55.583103	25.67220828568432	-100.2894174751423	7.26
1315	1	2026-05-18 15:51:56.016313	25.67219763621729	-100.2894431848917	7.67
1316	1	2026-05-18 15:51:56.498023	25.67218884583666	-100.289468591174	8.12
1317	1	2026-05-18 15:51:56.917659	25.67218286696257	-100.2894902620811	8.29
1318	1	2026-05-18 15:51:57.327083	25.67218180738071	-100.2894933837492	8.66
1319	1	2026-05-18 15:51:57.816812	25.6721634698124	-100.2895641359952	10.19
1320	1	2026-05-18 15:51:58.245698	25.67215935644427	-100.2895984688712	10.54
1321	1	2026-05-18 15:51:58.661007	25.67215011056512	-100.2896157464076	10.99
1322	1	2026-05-18 15:51:59.098514	25.67213748190979	-100.2896571462353	11.22
1323	1	2026-05-18 15:51:59.543816	25.67210421264979	-100.2897059648481	9.64
1324	1	2026-05-18 15:51:59.974338	25.67209640085392	-100.2897259913313	9.74
1325	1	2026-05-18 15:52:00.398574	25.6721045148855	-100.2897063326286	9.44
1326	1	2026-05-18 15:52:00.813598	25.67209835957301	-100.2897271459037	9.77
1327	1	2026-05-18 15:52:01.239306	25.67209985191257	-100.2897252535671	10.01
1328	1	2026-05-18 15:52:01.714854	25.67209408373562	-100.2897694868914	8.96
1329	1	2026-05-18 15:52:02.157098	25.67209408373562	-100.2897694868914	9.16
1330	1	2026-05-18 15:52:02.586732	25.67209408373562	-100.2897694868914	9.18
1331	1	2026-05-18 15:52:03.025656	25.67209408373562	-100.2897694868914	7.74
1332	1	2026-05-18 15:52:03.454965	25.67210158617163	-100.2897143074162	6.73
1333	1	2026-05-18 15:52:03.93795	25.67209701520911	-100.2897270772132	6.58
1334	1	2026-05-18 15:52:04.367299	25.67209247076541	-100.2897390732779	6.6
1335	1	2026-05-18 15:52:04.795262	25.67208813011774	-100.2897536859021	6.64
1336	1	2026-05-18 15:52:05.224043	25.67208179912761	-100.2897743141194	6.66
1337	1	2026-05-18 15:52:05.655408	25.67207735680533	-100.2897907154897	6.81
1338	1	2026-05-18 15:52:06.081362	25.67207513013108	-100.2897972276664	6.87
1339	1	2026-05-18 15:52:06.50431	25.67208006653808	-100.2897880303926	6.96
1340	1	2026-05-18 15:52:06.925241	25.67205104718148	-100.2898395654197	6.48
1341	1	2026-05-18 15:52:07.35424	25.67204526223428	-100.2898524970089	6.61
1342	1	2026-05-18 15:52:07.902836	25.67202641594731	-100.2898984632351	5.84
1343	1	2026-05-18 15:52:08.318597	25.67202417658128	-100.289904572782	4.9
1344	1	2026-05-18 15:52:08.751486	25.67202032776943	-100.2899139636852	4.91
1345	1	2026-05-18 15:52:09.200973	25.67202501830872	-100.2899135692857	5.1
1346	1	2026-05-18 15:52:09.656541	25.67202496497439	-100.2899167708842	5.24
1347	1	2026-05-18 15:52:10.154196	25.67202766264894	-100.2899176143085	5.68
1348	1	2026-05-18 15:53:27.481476	25.67201211744759	-100.2899383948727	5.24
1349	1	2026-05-18 15:53:27.961236	25.67198134757683	-100.2900219466307	7.37
1350	1	2026-05-18 15:53:28.415839	25.67198333901155	-100.29002393925	7.24
1351	1	2026-05-18 15:53:28.895803	25.67198333901155	-100.29002393925	6.84
1352	1	2026-05-18 17:52:22.760528	25.67200485671531	-100.2899947028124	6.77
1353	1	2026-05-18 17:52:23.048712	25.67198594745726	-100.2900509039683	6.85
1354	1	2026-05-18 17:52:23.332091	25.67195228267695	-100.2901294439211	6.45
1355	1	2026-05-18 17:52:23.581653	25.67193449523804	-100.2901770755577	6.3
1356	1	2026-05-18 17:52:23.836578	25.67191130066565	-100.2902390795891	6.06
1357	1	2026-05-18 17:52:24.092445	25.6719008320742	-100.2902883691486	6.13
1358	1	2026-05-18 17:52:24.36611	25.67188585814746	-100.2904304409286	7.29
1359	1	2026-05-18 17:52:24.620311	25.67186644885146	-100.290473576639	7.62
1360	1	2026-05-18 17:52:24.881522	25.67185229992187	-100.2905088377323	8.15
1361	1	2026-05-18 17:52:25.148105	25.67178357151126	-100.2906566517882	9.83
1362	1	2026-05-18 17:52:25.390813	25.67176204078919	-100.2907311623012	10.67
1363	1	2026-05-18 17:52:25.637838	25.67175967868199	-100.2907749098664	10.63
1364	1	2026-05-18 17:52:25.875423	25.67173202865747	-100.2908371275334	9.19
1365	1	2026-05-18 17:52:26.127274	25.67172294336421	-100.2908678311092	8.76
1366	1	2026-05-18 17:52:26.383691	25.67170481559339	-100.2908906077855	7.66
1367	1	2026-05-18 17:52:26.650448	25.6716939066179	-100.2909409925554	7.79
1368	1	2026-05-18 17:52:26.9039	25.67168285298861	-100.2909789106743	7.57
1369	1	2026-05-18 17:52:27.172537	25.67167226008618	-100.2910062065856	8.13
1370	1	2026-05-18 17:52:27.433281	25.67166669453375	-100.2910340596371	8.57
1371	1	2026-05-18 17:52:27.685055	25.67166184323069	-100.2910309933401	8.19
1372	1	2026-05-18 17:52:27.937121	25.67165373510768	-100.2910294003471	7.85
1373	1	2026-05-18 17:52:28.197827	25.67165409841292	-100.2910466641188	7.09
1374	1	2026-05-18 17:52:28.455224	25.67163458054767	-100.291057840273	7.0
1375	1	2026-05-18 17:52:28.702567	25.67162222012078	-100.2910841034815	6.66
1376	1	2026-05-18 17:52:28.952336	25.67160217267695	-100.2911555347147	6.4
1377	1	2026-05-18 17:52:29.196479	25.67157513354353	-100.2912140254681	6.43
1378	1	2026-05-18 17:52:29.452735	25.67156852565083	-100.2912396610103	6.55
1379	1	2026-05-18 17:52:29.72255	25.67156067018815	-100.2912606197302	6.69
1380	1	2026-05-18 17:52:29.973669	25.67153769948418	-100.2913406818037	6.42
1381	1	2026-05-18 17:52:30.229574	25.67151502135483	-100.2914045495386	6.33
1382	1	2026-05-18 17:52:30.472008	25.67150742811536	-100.2914337741078	6.34
1383	1	2026-05-18 17:52:30.723051	25.67145241433037	-100.2915592587657	7.02
1384	1	2026-05-18 17:52:30.983583	25.67143691749796	-100.2916163337197	7.79
1385	1	2026-05-18 17:52:31.241385	25.67143313643507	-100.2916471618916	7.95
1386	1	2026-05-18 17:52:31.493475	25.67142745805112	-100.2916664188729	8.35
1387	1	2026-05-18 17:52:31.747293	25.67141908464565	-100.2916788924397	8.63
1388	1	2026-05-18 17:52:32.019536	25.6713868630983	-100.291746162531	9.35
1389	1	2026-05-18 17:52:32.288207	25.67134440859589	-100.2918877463119	9.82
1390	1	2026-05-18 17:52:32.550375	25.67133769139093	-100.291913910305	9.99
1391	1	2026-05-18 17:52:32.801799	25.67134285201959	-100.2919304188326	10.36
1392	1	2026-05-18 17:52:33.053148	25.67134193789281	-100.2919349251043	10.7
1393	1	2026-05-18 17:52:33.314813	25.67133666432639	-100.2919409616149	10.05
1394	1	2026-05-18 17:52:33.556852	25.67132856801526	-100.2919390060446	10.23
1395	1	2026-05-18 17:52:33.808825	25.67132611221422	-100.2919543584018	10.38
1396	1	2026-05-18 17:52:34.09139	25.67127920924626	-100.2919455396069	7.27
1397	1	2026-05-18 17:52:34.351235	25.67128185994436	-100.291946812198	7.4
1398	1	2026-05-18 17:52:34.601864	25.67127888325734	-100.2919626227646	8.04
1399	1	2026-05-18 17:52:34.855087	25.67126993891299	-100.2920225478894	10.06
1400	1	2026-05-18 17:52:35.113084	25.67126670379261	-100.2920465344952	10.84
1401	1	2026-05-18 17:52:35.368598	25.67126139545617	-100.2920667565448	11.79
1402	1	2026-05-18 17:52:35.62487	25.67125762877322	-100.2920941545464	12.61
1403	1	2026-05-18 17:52:35.871081	25.67124772876286	-100.2921192075919	13.56
1404	1	2026-05-18 17:52:36.124738	25.67124163851335	-100.292151355411	14.59
1405	1	2026-05-18 17:52:36.376195	25.67123969162747	-100.2921763135851	15.49
1406	1	2026-05-18 17:52:36.62342	25.67122824838991	-100.2921768763677	13.08
1407	1	2026-05-18 17:52:36.874625	25.67122786403066	-100.2921738598609	12.87
1408	1	2026-05-18 17:52:37.146734	25.67119523674639	-100.2922148782893	13.16
1409	1	2026-05-18 17:52:37.407887	25.67115059713395	-100.2923623494529	10.5
1410	1	2026-05-18 17:52:37.664631	25.67115035431971	-100.2923750248034	10.94
1411	1	2026-05-18 17:52:37.918799	25.67115880323576	-100.292394677639	10.93
1412	1	2026-05-18 17:52:38.172767	25.67115643446344	-100.2924153094567	10.76
1413	1	2026-05-18 17:52:38.422032	25.67115655350729	-100.2924223441936	11.07
1414	1	2026-05-18 17:52:38.683367	25.67115848180142	-100.2924238158519	11.83
1415	1	2026-05-18 17:52:38.932512	25.6711564276736	-100.2924181063601	12.31
1416	1	2026-05-18 17:52:39.187838	25.67112617723204	-100.2924593100249	10.59
1417	1	2026-05-18 17:52:39.43754	25.67112426412201	-100.2924614481219	8.55
1418	1	2026-05-18 17:52:39.689288	25.67112426412201	-100.2924614481219	7.52
1419	1	2026-05-18 17:52:39.968165	25.67111055015013	-100.2924770192797	7.45
1420	1	2026-05-18 17:52:40.269313	25.67110590857206	-100.2925360802157	7.45
1421	1	2026-05-18 17:52:40.530248	25.67110633966504	-100.2925772570176	7.83
1422	1	2026-05-18 17:52:40.786342	25.67109851794353	-100.2926134521686	8.11
1423	1	2026-05-18 17:52:41.160685	25.67108152808795	-100.2926800484507	8.41
1424	1	2026-05-18 17:52:41.430461	25.67106793982349	-100.2927080025664	8.66
1425	1	2026-05-18 17:52:41.680504	25.67105977581148	-100.2927414328312	8.99
1426	1	2026-05-18 17:52:41.939894	25.67104799163085	-100.2927676761659	9.5
1427	1	2026-05-18 17:52:42.191993	25.67104573189938	-100.2928017301729	10.18
1428	1	2026-05-18 17:52:42.449156	25.67097522334845	-100.2930030116838	10.24
1429	1	2026-05-18 17:52:42.712611	25.67089651780441	-100.2930914351699	9.79
1430	1	2026-05-18 17:52:42.968796	25.6708330899656	-100.2932095263253	8.29
1431	1	2026-05-18 17:52:43.23079	25.67081287606418	-100.2932581057459	8.6
1432	1	2026-05-18 17:52:43.496312	25.67081297566445	-100.2932785203202	8.93
1433	1	2026-05-18 17:52:43.776139	25.67080655376175	-100.2932802816638	9.21
1434	1	2026-05-18 17:52:44.035703	25.67080900312692	-100.2932938002212	9.54
1435	1	2026-05-18 17:52:44.295725	25.6708074564663	-100.2932889760512	10.13
1436	1	2026-05-18 17:52:44.538112	25.67080737878882	-100.2932995805279	10.95
1437	1	2026-05-18 17:52:44.793876	25.6708000146598	-100.2933089851608	11.88
1438	1	2026-05-18 17:52:45.046332	25.67078803909703	-100.2933108230158	13.25
1439	1	2026-05-18 17:52:45.299491	25.67078357096502	-100.2933324310691	14.65
1440	1	2026-05-18 17:52:45.551128	25.67077940098158	-100.2933457025767	15.77
1441	1	2026-05-18 17:52:45.802875	25.67079493356261	-100.2934697233677	15.24
1442	1	2026-05-18 17:52:46.06448	25.67065007563371	-100.2935503162499	12.28
1443	1	2026-05-18 17:52:46.340326	25.67065774734185	-100.2935610098542	12.93
1444	1	2026-05-18 17:52:46.603475	25.67066659555949	-100.2935787806571	12.76
1445	1	2026-05-18 17:52:46.864046	25.67062627540528	-100.2936757127329	10.42
1446	1	2026-05-18 17:52:47.111826	25.67058983405569	-100.2937108427772	9.61
1447	1	2026-05-18 17:52:47.381194	25.67059611911846	-100.2937603257241	10.01
1448	1	2026-05-18 17:52:47.648434	25.6705946515855	-100.2937739422891	10.23
1449	1	2026-05-18 17:52:47.905387	25.6705905367892	-100.2937722385674	10.38
1450	1	2026-05-18 17:52:48.160887	25.67058395599323	-100.2937801055865	10.46
1451	1	2026-05-18 17:52:48.423276	25.67057631135461	-100.2938023764292	10.73
1452	1	2026-05-18 23:01:21.942695	25.67058075816255	-100.2938205429946	10.88
1453	1	2026-05-18 23:01:22.283297	25.67054897951114	-100.2938626120043	10.19
1454	1	2026-05-18 23:01:22.536603	25.67054901111712	-100.2938776390763	10.67
1455	1	2026-05-18 23:01:22.809822	25.67054096814913	-100.2938962856319	10.96
1456	1	2026-05-18 23:01:23.058506	25.67053111532487	-100.293922301628	11.27
1457	1	2026-05-18 23:01:23.328021	25.67049979149716	-100.294021823889	12.03
1458	1	2026-05-18 23:01:23.562805	25.67048338250378	-100.2941009957687	11.73
1459	1	2026-05-18 23:01:23.828578	25.67045603823658	-100.2941591401761	11.56
1460	1	2026-05-18 23:01:24.092509	25.67044329537195	-100.294197302773	11.77
1461	1	2026-05-18 23:01:24.352341	25.6704201141248	-100.2942853076571	12.56
1462	1	2026-05-18 23:01:24.616644	25.67039084575631	-100.2943349863789	13.93
1463	1	2026-05-18 23:01:25.427407	25.67039210423575	-100.2943318667896	12.73
1464	1	2026-05-18 23:01:27.063019	25.67037778762451	-100.294371091936	11.58
1465	1	2026-05-18 23:01:27.293477	25.67037043469989	-100.2944132423475	11.81
1466	1	2026-05-18 23:01:27.535182	25.67034759503203	-100.2944473034908	12.72
1467	1	2026-05-18 23:01:27.793068	25.67034237650742	-100.2944770554277	13.94
1468	1	2026-05-18 23:01:28.036133	25.67032953551341	-100.2945307882931	14.94
1469	1	2026-05-18 23:01:28.28796	25.67031482359133	-100.2945171742142	14.28
1470	1	2026-05-18 23:01:28.534474	25.67030119190041	-100.2945459252233	14.72
1471	1	2026-05-18 23:01:28.812708	25.67028669192618	-100.2945808251298	14.89
1472	1	2026-05-18 23:01:29.063926	25.67028125758014	-100.2945963387505	15.61
1473	1	2026-05-18 23:01:29.292506	25.67026715451472	-100.2946360647198	15.66
1474	1	2026-05-18 23:01:29.52716	25.67023913101489	-100.2947037449551	14.4
1475	1	2026-05-18 23:01:29.789966	25.67022363165227	-100.2947480595823	14.41
1476	1	2026-05-18 23:01:30.026247	25.67020904184684	-100.2947941349944	14.52
1477	1	2026-05-18 23:01:30.264366	25.67018660539702	-100.2948526604593	13.5
1478	1	2026-05-18 23:01:30.531666	25.67016241185825	-100.294947320253	10.19
1479	1	2026-05-18 23:01:30.771655	25.6701456950987	-100.2949951336734	9.25
1480	1	2026-05-18 23:01:31.03226	25.67012082789364	-100.295009418246	8.54
1481	1	2026-05-18 23:01:31.268054	25.67010197010591	-100.2951010017365	8.79
1482	1	2026-05-18 23:01:31.533207	25.67004279358044	-100.2952176763529	7.94
1483	1	2026-05-18 23:01:31.786918	25.67000327137528	-100.295322611639	6.39
1484	1	2026-05-18 23:01:32.056938	25.66996291436495	-100.2954305865028	5.21
1485	1	2026-05-18 23:01:32.296881	25.66995560206112	-100.2954426698276	6.04
1486	1	2026-05-18 23:01:32.550076	25.66994707080152	-100.2954631596111	6.48
1487	1	2026-05-18 23:01:32.813651	25.66994619752628	-100.2954750688558	7.21
1488	1	2026-05-18 23:01:33.116841	25.66993490752259	-100.2955171695632	7.68
1489	1	2026-05-18 23:01:33.357715	25.66992818895964	-100.2955434367086	8.45
1490	1	2026-05-18 23:01:33.593247	25.66989146995586	-100.2956189015139	8.85
1491	1	2026-05-18 23:01:33.85305	25.66987604189159	-100.2956671402436	9.62
1492	1	2026-05-18 23:01:34.098482	25.66982552701657	-100.2958375367006	11.35
1493	1	2026-05-18 23:01:34.371773	25.66980794481306	-100.2959071115281	14.13
1494	1	2026-05-18 23:01:34.62809	25.66979744473747	-100.2959448390917	16.24
1495	1	2026-05-18 23:01:34.885126	25.66975741544234	-100.2960664882948	10.84
1496	1	2026-05-18 23:01:35.127923	25.66971977049766	-100.2961675252531	8.27
1497	1	2026-05-18 23:01:35.365359	25.6697093969265	-100.2962228800097	8.53
1498	1	2026-05-18 23:01:35.605733	25.66970097257203	-100.2962581875903	9.29
1499	1	2026-05-18 23:01:35.858861	25.66965753088827	-100.29636802503	9.04
1500	1	2026-05-18 23:01:36.099169	25.66964657929405	-100.2964159460913	9.93
1501	1	2026-05-18 23:01:36.352201	25.66963524094792	-100.2964634544917	10.85
1502	1	2026-05-18 23:01:36.620772	25.66959919895427	-100.2964882447429	9.41
1503	1	2026-05-18 23:01:36.865059	25.66955134322798	-100.2965906041772	10.7
1504	1	2026-05-18 23:01:37.117866	25.66952750488139	-100.2966433963819	11.59
1505	1	2026-05-18 23:01:37.365769	25.6695116426609	-100.2967292903229	13.4
1506	1	2026-05-18 23:01:37.598338	25.66950417498372	-100.296749974509	14.2
1507	1	2026-05-18 23:01:37.858492	25.66948196989597	-100.296762921448	15.14
1508	1	2026-05-18 23:01:38.105111	25.6694795159745	-100.2968286661645	17.22
1509	1	2026-05-18 23:01:38.341436	25.66947253525091	-100.2968707022661	18.4
1510	1	2026-05-18 23:01:38.584298	25.66943585822466	-100.2969876820564	18.97
1511	1	2026-05-18 23:01:38.839648	25.66941542291329	-100.2970587548489	17.81
1512	1	2026-05-18 23:01:39.072662	25.66934039730751	-100.2972781432775	18.6
1513	1	2026-05-18 23:01:39.304249	25.66929952615628	-100.2973443000176	19.49
1514	1	2026-05-18 23:01:39.541578	25.6692260736174	-100.2975300754575	19.15
1515	1	2026-05-18 23:01:39.796835	25.66908482595197	-100.2978891251465	19.85
1516	1	2026-05-18 23:01:40.0388	25.66841814596402	-100.2993147753999	13.87
1517	1	2026-05-18 23:01:40.315169	25.66824139193987	-100.299630087403	10.64
1518	1	2026-05-18 23:01:40.563062	25.66815900624386	-100.2997880350517	13.82
1519	1	2026-05-18 23:01:40.805526	25.66797739739221	-100.3001177649287	19.54
1520	1	2026-05-18 23:01:41.058872	25.66791391023782	-100.3002347096532	21.42
1521	1	2026-05-18 23:01:41.307205	25.6678471940644	-100.3003689632056	23.38
1522	1	2026-05-18 23:01:41.565726	25.66769706278762	-100.3006578524601	21.59
1523	1	2026-05-18 23:01:41.804916	25.66760491292488	-100.3007718010983	20.08
1524	1	2026-05-18 23:01:42.062881	25.66754108303578	-100.3009390339166	17.39
1525	1	2026-05-18 23:01:42.321441	25.66736645877713	-100.3012466056851	15.04
1526	1	2026-05-18 23:01:42.572958	25.66728009931222	-100.3013920102231	13.84
1527	1	2026-05-18 23:01:42.834166	25.66719183250257	-100.301571259189	9.82
1528	1	2026-05-18 23:01:43.074243	25.66709943030492	-100.3017512065738	8.91
1529	1	2026-05-18 23:01:43.337187	25.66699753074515	-100.3019414940318	8.28
1530	1	2026-05-18 23:01:43.57758	25.66681438667542	-100.3023089998313	8.04
1531	1	2026-05-18 23:01:43.846873	25.66671644148637	-100.3025090884861	8.02
1532	1	2026-05-18 23:01:44.096721	25.66662621905798	-100.3026921222231	12.39
1533	1	2026-05-18 23:01:44.354785	25.66654677301191	-100.3028743953975	13.9
1534	1	2026-05-18 23:01:44.600625	25.66647091181218	-100.3030603529449	14.14
1535	1	2026-05-18 23:01:44.867522	25.66638118576906	-100.3032331514781	14.21
1536	1	2026-05-18 23:01:45.122821	25.66628823084501	-100.3034125411989	14.24
1537	1	2026-05-18 23:01:45.38357	25.66619531424354	-100.3035828255301	14.99
1538	1	2026-05-18 23:01:45.636974	25.66600670953067	-100.3038575505248	15.46
1539	1	2026-05-18 23:01:45.899388	25.66573806540778	-100.3041835129042	18.53
1540	1	2026-05-18 23:01:46.138898	25.66562833452352	-100.30430284527	20.92
1541	1	2026-05-18 23:01:46.403209	25.66552462203175	-100.3044121753443	23.07
1542	1	2026-05-18 23:01:46.641357	25.66540020610501	-100.3045390106731	25.86
1543	1	2026-05-18 23:01:46.895393	25.66530438781919	-100.3046693017451	28.27
1544	1	2026-05-18 23:01:47.139389	25.66529411353646	-100.3046833565537	28.82
1545	1	2026-05-18 23:01:47.388005	25.66533335994981	-100.3046296660065	30.08
1546	1	2026-05-18 23:01:47.625036	25.66529748297202	-100.3046787472591	31.16
1547	1	2026-05-18 23:01:47.874668	25.66529218603359	-100.3046859933477	29.11
1548	1	2026-05-18 23:01:48.114368	25.6650724677714	-100.3049791957913	22.61
1549	1	2026-05-18 23:01:48.370623	25.66501365381002	-100.3050619304774	23.64
1550	1	2026-05-18 23:03:05.88601	25.66498277712627	-100.3051023672446	22.7
1551	1	2026-05-18 23:04:21.728364	25.66491642016556	-100.3051946962625	24.09
1552	1	2026-05-18 23:04:21.99408	25.66487936421972	-100.30525359349	25.08
1553	1	2026-05-18 23:04:22.267682	25.66483513569929	-100.3053245714411	26.32
1554	1	2026-05-18 23:04:22.523515	25.66481440222493	-100.3053241734327	16.68
1555	1	2026-05-18 23:04:22.77237	25.66479334852399	-100.3053542389138	16.74
1556	1	2026-05-18 23:04:23.04419	25.66471706039316	-100.3054624968223	15.45
1557	1	2026-05-18 23:04:23.333159	25.6646148593696	-100.3056075734938	14.56
1558	1	2026-05-18 23:04:23.56102	25.66453194246636	-100.3057215145891	11.15
1559	1	2026-05-18 23:04:23.801317	25.66447662864647	-100.3058076482171	9.77
1560	1	2026-05-18 23:04:24.060562	25.6644239230324	-100.3058994080884	8.96
1561	1	2026-05-18 23:04:24.300025	25.66430837183206	-100.3061128449811	8.26
1562	1	2026-05-18 23:04:24.604649	25.66425624636901	-100.3062014557915	8.14
1563	1	2026-05-18 23:04:24.88773	25.66417923789654	-100.3063378705886	8.05
1564	1	2026-05-18 23:04:25.140559	25.664092589637	-100.3064883716144	8.02
1565	1	2026-05-18 23:04:25.407349	25.66393909322002	-100.3067691132305	8.0
1566	1	2026-05-18 23:04:25.663531	25.66388606446935	-100.3068878048266	8.0
1567	1	2026-05-18 23:04:25.900357	25.66389040535898	-100.3070460403416	8.0
1568	1	2026-05-18 23:04:26.148673	25.66381064171526	-100.3073150564363	8.0
1569	1	2026-05-18 23:04:26.38656	25.66378398584035	-100.3074441960225	11.12
1570	1	2026-05-18 23:04:26.645644	25.66374935266046	-100.3075779445945	10.05
1571	1	2026-05-18 23:04:26.910575	25.66370696685591	-100.3076994697102	12.16
1572	1	2026-05-18 23:04:27.154623	25.66366285545737	-100.3078303787768	14.45
1573	1	2026-05-18 23:04:27.412164	25.66362050215792	-100.3079753045639	14.34
1574	1	2026-05-18 23:04:27.668768	25.66361390677728	-100.3081115947109	18.25
1575	1	2026-05-18 23:04:27.921091	25.6635518642812	-100.3085069367124	9.52
1576	1	2026-05-18 23:04:28.171479	25.66352247164202	-100.3086843938392	9.37
1577	1	2026-05-18 23:04:28.438992	25.66349382790099	-100.3089087660182	8.24
1578	1	2026-05-18 23:04:28.704768	25.66344494220523	-100.3091653419337	8.11
1579	1	2026-05-18 23:05:47.199322	25.66341266877595	-100.3093570539642	15.47
1580	1	2026-05-18 23:05:47.463465	25.66344345191108	-100.3097417200204	13.12
1581	1	2026-05-18 23:05:47.735981	25.66350020097987	-100.3101277446868	18.02
1582	1	2026-05-18 23:05:47.995456	25.66354945674632	-100.3102724115933	15.64
1583	1	2026-05-18 23:05:48.303218	25.66359423386477	-100.3108453954343	22.0
1584	1	2026-05-18 23:05:48.552065	25.66369861579597	-100.3110799923976	20.44
1585	1	2026-05-18 23:05:48.803574	25.66378924578604	-100.3111799373677	15.91
1586	1	2026-05-18 23:05:49.071304	25.66384019621671	-100.3113449214148	18.49
1587	1	2026-05-18 23:05:49.328255	25.66388899267601	-100.3115061683043	21.39
1588	1	2026-05-18 23:05:49.585096	25.66393750194091	-100.3116600944348	24.54
1589	1	2026-05-18 23:05:49.843157	25.66396658044268	-100.3118211916518	27.57
1590	1	2026-05-18 23:05:50.122736	25.66391774957716	-100.3116580516331	25.77
1591	1	2026-05-18 23:05:50.413492	25.66392997171691	-100.3116552617605	17.95
1592	1	2026-05-18 23:05:50.688734	25.66393380218544	-100.311706187026	11.65
1593	1	2026-05-18 23:05:50.944298	25.66395060549415	-100.3117867171206	12.37
1594	1	2026-05-18 23:05:51.212992	25.6639685591209	-100.311876190603	12.98
1595	1	2026-05-18 23:05:51.518882	25.66401241621137	-100.3121324184431	14.18
1596	1	2026-05-18 23:05:51.808956	25.66401911051884	-100.3122198361848	14.64
1597	1	2026-05-18 23:05:52.11692	25.66402036302295	-100.3122757578764	12.14
1598	1	2026-05-18 23:05:52.388176	25.66402714574453	-100.3123540362446	12.96
1599	1	2026-05-18 23:05:52.690147	25.66403972899622	-100.3124553575833	13.49
1600	1	2026-05-18 23:05:52.966682	25.66405368305849	-100.3125550669313	11.35
1601	1	2026-05-18 23:05:53.225518	25.66406660201848	-100.3126511916268	17.33
1602	1	2026-05-18 23:05:53.52459	25.66408093147745	-100.3128155903337	18.33
1603	1	2026-05-18 23:05:53.801519	25.66408720286283	-100.3128791419742	17.22
1604	1	2026-05-18 23:05:54.088602	25.66409707745149	-100.3129747353714	17.9
1605	1	2026-05-18 23:05:54.379176	25.66411311313178	-100.3131191975595	15.94
1606	1	2026-05-18 23:05:54.659919	25.66416887747604	-100.3135972118757	8.88
1607	1	2026-05-18 23:05:54.991234	25.66418722551552	-100.3137075823464	11.57
1608	1	2026-05-18 23:05:55.26307	25.66421182751997	-100.3138683954092	9.56
1609	1	2026-05-18 23:05:55.55268	25.66425456174431	-100.3140005754311	12.44
1610	1	2026-05-18 23:05:55.840581	25.66428871198337	-100.3141770008544	10.01
1611	1	2026-05-18 23:05:56.138378	25.6643275106009	-100.3143252436182	8.86
1612	1	2026-05-18 23:05:56.42229	25.66438374407164	-100.3145985602476	9.52
1613	1	2026-05-18 23:05:56.724812	25.66441593679307	-100.3147552508192	8.72
1614	1	2026-05-18 23:05:57.001004	25.66445010274127	-100.3149204007288	8.85
1615	1	2026-05-18 23:05:57.284868	25.66448374220742	-100.3150856349798	12.84
1616	1	2026-05-18 23:05:57.583275	25.66451934311075	-100.3152572961767	15.05
1617	1	2026-05-18 23:05:57.848037	25.6646331077766	-100.3157978530458	9.77
1618	1	2026-05-18 23:05:58.119985	25.66465889201862	-100.3159647187556	8.71
1619	1	2026-05-18 23:05:58.410629	25.6646993630798	-100.316291972955	11.81
1620	1	2026-05-18 23:05:58.695248	25.66472984727656	-100.3164494105974	9.61
1621	1	2026-05-18 23:05:58.991949	25.66473281813721	-100.3166149220617	12.34
1622	1	2026-05-18 23:05:59.259176	25.66478832823483	-100.3167650000176	14.37
1623	1	2026-05-18 23:05:59.525275	25.66478323720332	-100.316939216719	10.6
1624	1	2026-05-18 23:05:59.807324	25.66481541528574	-100.3170863693752	9.15
1625	1	2026-05-18 23:06:00.092118	25.66483726006965	-100.3172530662831	8.47
1626	1	2026-05-18 23:06:00.382893	25.66488542731396	-100.317410020813	13.44
1627	1	2026-05-18 23:06:00.647091	25.66491540475668	-100.3175742247905	13.91
1628	1	2026-05-18 23:06:00.95287	25.66494891291316	-100.3177406574401	10.37
1629	1	2026-05-18 23:06:01.229206	25.66499113086549	-100.3178997680716	9.38
1630	1	2026-05-18 23:06:01.526125	25.66501886485255	-100.3180689258599	9.25
1631	1	2026-05-18 23:06:01.816607	25.66510771581631	-100.3184947627195	8.04
1632	1	2026-05-18 23:06:02.10688	25.66515402997781	-100.3186445243766	8.06
1633	1	2026-05-18 23:06:02.435038	25.66522614284871	-100.3188112661853	8.01
1634	1	2026-05-18 23:06:02.716931	25.66532398011291	-100.3190718045313	8.0
1635	1	2026-05-18 23:06:03.026381	25.66537352568075	-100.3192242618892	8.0
1636	1	2026-05-18 23:06:03.328599	25.66540364106576	-100.3193730314738	8.0
1637	1	2026-05-18 23:06:03.589707	25.66550787910368	-100.3198381969489	12.46
1638	1	2026-05-18 23:06:03.88085	25.66558046763694	-100.3201282555271	16.71
1639	1	2026-05-18 23:06:04.182964	25.66561295860425	-100.3203959282762	13.5
1640	1	2026-05-18 23:06:04.460381	25.66563390318315	-100.3206108590947	15.32
1641	1	2026-05-18 23:06:04.728067	25.66565307716966	-100.3207743028902	16.61
1642	1	2026-05-18 23:06:05.089441	25.66567391645555	-100.3209557794674	20.0
1643	1	2026-05-18 23:06:05.38379	25.66569356036138	-100.3211337715692	22.29
1644	1	2026-05-18 23:06:05.730628	25.66573555984263	-100.3213427712968	22.49
1645	1	2026-05-18 23:06:05.992779	25.665719508094	-100.3215315849506	26.6
1646	1	2026-05-18 23:06:06.309079	25.66571279553731	-100.3216537706584	27.9
1647	1	2026-05-18 23:06:06.580256	25.66575589230758	-100.3219814780935	21.99
1648	1	2026-05-18 23:06:06.847424	25.66578096654477	-100.3221489553886	21.84
1649	1	2026-05-18 23:06:07.159189	25.66579396744121	-100.3225237001954	26.32
1650	1	2026-05-18 23:06:26.46011	25.66581163429762	-100.3227275086068	26.15
1651	1	2026-05-18 23:06:26.737212	25.66583658393017	-100.3228952257349	21.18
1652	1	2026-05-18 23:06:27.056793	25.6658910995424	-100.3231198211091	20.89
1653	1	2026-05-18 23:06:27.341068	25.66591861057319	-100.3233293993896	23.53
1654	1	2026-05-18 23:06:27.689485	25.66597140897309	-100.3235794790636	25.04
1655	1	2026-05-18 23:06:28.044629	25.66602579158605	-100.3238401402126	24.43
1656	1	2026-05-18 23:06:28.38	25.66605388273658	-100.3240460933732	24.65
1657	1	2026-05-18 23:06:28.664058	25.66615495286317	-100.3245681434393	21.3
1658	1	2026-05-18 23:06:28.942208	25.66621355784724	-100.3247649352007	16.34
1659	1	2026-05-18 23:06:29.225898	25.66625910543262	-100.3250254272934	15.8
1660	1	2026-05-18 23:06:29.512009	25.66630057347926	-100.3252625881533	15.18
1661	1	2026-05-18 23:06:29.785118	25.66634418810725	-100.3255134631006	15.89
1662	1	2026-05-18 23:06:30.092316	25.66642141086549	-100.3259639291261	8.38
1663	1	2026-05-18 23:06:30.389582	25.66645894137803	-100.3261903607224	8.19
1664	1	2026-05-18 23:06:30.679813	25.66649610546513	-100.3264147392419	8.05
1665	1	2026-05-18 23:06:30.972221	25.66653389970999	-100.3266429223536	8.02
1666	1	2026-05-18 23:06:31.276162	25.66657646714489	-100.3268678688053	8.01
1667	1	2026-05-18 23:06:31.574167	25.6666232685109	-100.3270970533095	13.1
1668	1	2026-05-18 23:06:31.87312	25.66666085091392	-100.3273282489638	9.3
1669	1	2026-05-18 23:06:32.152628	25.66669979320729	-100.3275602066065	13.97
1670	1	2026-05-18 23:06:32.549938	25.66674121743952	-100.3278042832646	10.88
1671	1	2026-05-18 23:06:32.847203	25.66677898692177	-100.3280104083417	13.73
1672	1	2026-05-18 23:06:33.15463	25.66687080718632	-100.328507647023	12.82
1673	1	2026-05-18 23:06:33.459997	25.66694069459118	-100.3288861402614	13.26
1674	1	2026-05-18 23:06:33.74906	25.66698135454832	-100.3291067954302	19.06
1675	1	2026-05-18 23:06:34.045915	25.66702086195582	-100.3293097876333	15.91
1676	1	2026-05-18 23:06:34.346069	25.66703421772388	-100.3293779418946	13.04
1677	1	2026-05-18 23:06:34.678867	25.66706319718462	-100.3295258272399	10.01
1678	1	2026-05-18 23:06:34.968679	25.66709438294473	-100.3297090859052	8.73
1679	1	2026-05-18 23:06:35.224901	25.66714357946325	-100.3303140398758	10.31
1680	1	2026-05-18 23:06:35.553054	25.66717799110172	-100.3305094768826	8.77
1681	1	2026-05-18 23:12:20.868291	25.66721632772996	-100.330715070379	28.75
1682	1	2026-05-18 23:12:21.1079	25.66725278654317	-100.3309206817657	19.42
1683	1	2026-05-18 23:12:21.357003	25.66729666106654	-100.3311255816804	11.44
1684	1	2026-05-18 23:12:21.618054	25.66732983825954	-100.3313297859455	9.72
1685	1	2026-05-18 23:12:21.860337	25.66736638953144	-100.3315291231631	8.55
1686	1	2026-05-18 23:12:22.116546	25.66739614461809	-100.3317170532947	8.28
1687	1	2026-05-18 23:12:22.366062	25.6674702240689	-100.3321215547365	9.99
1688	1	2026-05-18 23:12:22.624045	25.66750679241894	-100.3323216894531	15.65
1689	1	2026-05-18 23:12:22.87385	25.6675795796415	-100.3327420897214	12.88
1690	1	2026-05-18 23:12:23.125511	25.66761762212069	-100.3329544225965	15.17
1691	1	2026-05-18 23:12:23.37868	25.66765580897973	-100.3331721170046	15.48
1692	1	2026-05-18 23:12:23.625291	25.66769258530841	-100.3333796292796	11.74
1693	1	2026-05-18 23:12:23.906173	25.66772594770275	-100.3335908397492	18.67
1694	1	2026-05-18 23:12:24.160962	25.66776303203113	-100.3338039964396	13.33
1695	1	2026-05-18 23:12:24.419112	25.6678000170492	-100.3340247190041	9.5
1696	1	2026-05-18 23:12:24.678456	25.66786569377036	-100.334476707331	8.2
1697	1	2026-05-18 23:12:24.927304	25.66794243548708	-100.3347065324165	8.1
1698	1	2026-05-18 23:12:25.189006	25.66798376983617	-100.334941057347	8.02
1699	1	2026-05-18 23:12:25.448052	25.66802810464073	-100.335196375201	8.01
1700	1	2026-05-18 23:12:25.702717	25.66811476780045	-100.3356986640732	9.19
1701	1	2026-05-18 23:12:25.937174	25.66816034685892	-100.3359621181408	8.22
1702	1	2026-05-18 23:12:26.179975	25.66820483194521	-100.3362192488803	8.11
1703	1	2026-05-18 23:12:26.411922	25.6683013231498	-100.3367580793146	8.01
1704	1	2026-05-18 23:12:26.668591	25.66834898024888	-100.3370238155486	13.22
1705	1	2026-05-18 23:12:26.914334	25.66839765269876	-100.3372881400442	12.24
1706	1	2026-05-18 23:12:27.170776	25.66844745345317	-100.3375530100018	20.79
1707	1	2026-05-18 23:12:27.441299	25.66849742944272	-100.3378165597805	17.59
1708	1	2026-05-18 23:12:27.698478	25.66854678805731	-100.338076300535	14.36
1709	1	2026-05-18 23:12:27.972894	25.66859518206541	-100.3383359288365	12.17
1710	1	2026-05-18 23:12:28.222866	25.66864487508938	-100.338605311887	13.92
1711	1	2026-05-18 23:12:28.495353	25.66870029431016	-100.3388691377612	10.96
1712	1	2026-05-18 23:12:28.752368	25.66878160539134	-100.3393327018999	8.35
1713	1	2026-05-18 23:12:29.013149	25.66884418257281	-100.339560682279	17.23
1714	1	2026-05-18 23:12:29.26204	25.66889030205856	-100.3398099198662	16.54
1715	1	2026-05-18 23:12:29.523565	25.66894687681246	-100.3400402298572	9.97
1716	1	2026-05-18 23:12:29.789075	25.6689977948783	-100.340280196126	8.98
1717	1	2026-05-18 23:12:30.066436	25.66918809546959	-100.3409685469814	19.36
1718	1	2026-05-18 23:12:30.322901	25.66923343847879	-100.341183863462	27.77
1719	1	2026-05-18 23:12:30.598421	25.66936063555967	-100.3416166167115	15.57
1720	1	2026-05-18 23:12:30.884896	25.66940170659365	-100.3418532989669	19.95
1721	1	2026-05-18 23:12:31.13784	25.66943755921423	-100.3420349947528	13.97
1722	1	2026-05-18 23:12:31.398009	25.66949426550441	-100.3422548073146	9.54
1723	1	2026-05-18 23:12:31.648896	25.66955445896005	-100.3424691710302	9.69
1724	1	2026-05-18 23:12:31.922291	25.66968675743611	-100.3428648848903	8.48
1725	1	2026-05-18 23:12:32.182849	25.66974367647839	-100.3430779426297	13.41
1726	1	2026-05-18 23:12:32.434724	25.66980456482333	-100.3432876798608	10.7
1727	1	2026-05-18 23:12:32.7076	25.66987058611164	-100.343500373818	8.7
1728	1	2026-05-18 23:12:32.966208	25.66999993508758	-100.3439246719463	16.56
1729	1	2026-05-18 23:12:33.229974	25.67006356725506	-100.3441442146396	22.31
1730	1	2026-05-18 23:12:33.497633	25.67012882853227	-100.3443542175203	16.49
1731	1	2026-05-18 23:12:33.74726	25.67019309421779	-100.3445556114428	25.46
1732	1	2026-05-18 23:12:33.993912	25.67026719192222	-100.3447348950124	18.44
1733	1	2026-05-18 23:12:34.264998	25.67032265392355	-100.3449288190058	19.06
1734	1	2026-05-18 23:12:34.523882	25.67046546948218	-100.3453752548589	19.23
1735	1	2026-05-18 23:12:34.785395	25.67051361696063	-100.3455624174918	36.6
1736	1	2026-05-18 23:12:35.039047	25.67059403356775	-100.3458994736059	13.45
1737	1	2026-05-18 23:12:35.300662	25.67063104337329	-100.3460543947321	11.9
1738	1	2026-05-18 23:12:35.550407	25.67068450830023	-100.3462154962834	13.33
1739	1	2026-05-18 23:12:35.812408	25.67079824410475	-100.3465180428248	15.53
1740	1	2026-05-18 23:12:36.072052	25.67084956492371	-100.3466701154511	11.11
1741	1	2026-05-18 23:12:36.317054	25.67088744913852	-100.3468120236588	22.39
1742	1	2026-05-18 23:12:36.561464	25.67093806822172	-100.3469658443593	17.59
1743	1	2026-05-18 23:12:36.822983	25.67098866066117	-100.3471124940668	15.66
1744	1	2026-05-18 23:12:37.10944	25.67104913382789	-100.3472626137198	14.83
1745	1	2026-05-18 23:12:37.356465	25.67117488110406	-100.3475616381662	17.45
1746	1	2026-05-18 23:12:37.621264	25.67122269909562	-100.3477036272423	18.82
1747	1	2026-05-18 23:12:37.886293	25.67124971000442	-100.3477021116387	15.09
1748	1	2026-05-18 23:12:38.143906	25.67137027741196	-100.3481544412489	8.41
1749	1	2026-05-18 23:12:38.423202	25.67140360657805	-100.3482682037671	9.78
1750	1	2026-05-18 23:12:38.673047	25.67143630735589	-100.3483800239715	21.46
1751	1	2026-05-18 23:12:38.926691	25.67151151566913	-100.3487349160016	9.9
1752	1	2026-05-18 23:12:39.186923	25.67152056511208	-100.348874848789	10.82
1753	1	2026-05-18 23:12:39.439852	25.67154372559004	-100.3489981804116	9.45
1754	1	2026-05-18 23:12:39.689626	25.6715905164767	-100.3492327489343	9.9
1755	1	2026-05-18 23:12:39.947101	25.67160374104473	-100.349347770965	9.0
1756	1	2026-05-18 23:12:40.208815	25.67162536818827	-100.3494626647703	8.53
1757	1	2026-05-18 23:12:40.492293	25.67163560629658	-100.3495737512637	11.17
1758	1	2026-05-18 23:12:40.738958	25.67164374343212	-100.3496842835427	12.56
1759	1	2026-05-18 23:12:41.00042	25.67165385173146	-100.3499173446906	13.96
1760	1	2026-05-18 23:14:20.91292	25.6716569280471	-100.3500373537389	15.86
1761	1	2026-05-18 23:14:21.218311	25.67166160369043	-100.3501611645356	18.14
1762	1	2026-05-18 23:14:21.485887	25.67185859198279	-100.3507496976297	18.67
1763	1	2026-05-18 23:14:21.766118	25.67184338401002	-100.3511331729717	9.7
1764	1	2026-05-18 23:14:22.020736	25.67192054355098	-100.3512409257891	8.82
1765	1	2026-05-18 23:14:22.308672	25.67192686638358	-100.3513521137688	8.44
1766	1	2026-05-18 23:14:22.593079	25.67195019210535	-100.3516109318292	5.18
1767	1	2026-05-18 23:14:22.845011	25.67204522000615	-100.3519548319711	3.56
1768	1	2026-05-18 23:14:23.115879	25.67207802491336	-100.352071998715	4.2
1769	1	2026-05-18 23:14:23.36404	25.67214947963667	-100.3522994974936	5.61
1770	1	2026-05-18 23:14:23.606337	25.67218428872862	-100.3524083903274	6.22
1771	1	2026-05-18 23:14:23.844876	25.67223162008075	-100.3525258336183	5.39
1772	1	2026-05-18 23:14:24.101827	25.67227447488842	-100.3526406791236	5.74
1773	1	2026-05-18 23:14:24.337816	25.67234087071201	-100.3528300282873	7.54
1774	1	2026-05-18 23:14:24.587279	25.67237022771848	-100.3529188747189	8.58
1775	1	2026-05-18 23:14:24.863245	25.67239763242591	-100.3529986932485	9.84
1776	1	2026-05-18 23:14:25.10368	25.67242245524626	-100.353070429969	11.39
1777	1	2026-05-18 23:14:25.354331	25.67244498188981	-100.3531415414743	12.14
1778	1	2026-05-18 23:14:25.610083	25.67265483087457	-100.3536053282212	20.16
1779	1	2026-05-18 23:14:25.847767	25.67267668289636	-100.3536525103229	20.16
1780	1	2026-05-18 23:14:26.102343	25.67271229590385	-100.3535875021386	7.2
1781	1	2026-05-18 23:14:26.339628	25.67274438834687	-100.3535720945365	6.46
1782	1	2026-05-18 23:15:20.893495	25.67276932827039	-100.3535588239561	6.67
1783	1	2026-05-18 23:15:21.143427	25.67279253086264	-100.3535465006862	6.92
1784	1	2026-05-18 23:15:21.404022	25.67283655639662	-100.3535134728941	7.66
1785	1	2026-05-18 23:15:21.659463	25.67283326473413	-100.3534789548964	8.78
1786	1	2026-05-18 23:17:20.892271	25.6728458744164	-100.3534591277185	9.77
1787	1	2026-05-18 23:17:21.137548	25.672847883737	-100.3534445662332	8.64
1788	1	2026-05-18 23:17:21.391132	25.67286839540693	-100.3534267533045	9.37
1789	1	2026-05-18 23:17:21.6654	25.67285454606406	-100.3534055058571	10.64
1790	1	2026-05-18 23:17:21.9103	25.67284013949079	-100.3533398132068	13.27
1791	1	2026-05-18 23:17:22.153108	25.67282575744751	-100.3533088523575	14.72
1792	1	2026-05-18 23:17:22.40194	25.67275331164333	-100.3531828759431	14.18
1793	1	2026-05-18 23:17:22.647475	25.67275001578507	-100.3531783471786	15.68
1794	1	2026-05-18 23:17:22.891067	25.67272860296511	-100.3531584270263	17.13
1795	1	2026-05-18 23:17:23.127841	25.67272038294372	-100.3531461154108	17.16
1796	1	2026-05-18 23:17:23.367704	25.67266718442411	-100.3530631984997	18.43
1797	1	2026-05-18 23:17:23.63342	25.67259408541061	-100.3529775744612	20.63
1798	1	2026-05-18 23:17:23.875186	25.67222833110715	-100.3530204273242	19.92
1799	1	2026-05-18 23:17:24.127102	25.6720358037332	-100.3530293217847	18.5
1800	1	2026-05-18 23:17:24.395826	25.67180385795865	-100.3531956035652	14.26
1801	1	2026-05-18 23:17:24.631832	25.67173709314205	-100.3532535878211	14.02
1802	1	2026-05-18 23:17:24.895936	25.67155280425565	-100.3532367124535	14.82
1803	1	2026-05-18 23:17:25.139014	25.67136677354349	-100.3532916841396	6.68
1804	1	2026-05-18 23:17:25.402563	25.67123634134041	-100.3533377812037	6.87
1805	1	2026-05-18 23:17:25.657907	25.67118248920201	-100.3533581615815	5.12
1806	1	2026-05-18 23:17:25.901591	25.67107457874214	-100.3534080441004	5.76
1807	1	2026-05-18 23:17:26.149893	25.67101387391568	-100.3534339483933	6.72
1808	1	2026-05-18 23:17:26.398467	25.67096027036277	-100.3534564899148	7.82
1809	1	2026-05-18 23:17:26.657481	25.67100098929224	-100.3536274419578	9.9
1810	1	2026-05-18 23:17:26.916128	25.67102121191908	-100.3537106243403	9.89
1811	1	2026-05-18 23:17:27.155475	25.67103476807783	-100.3537941578663	7.63
1812	1	2026-05-18 23:17:27.40431	25.67104143493843	-100.353896073436	8.18
1813	1	2026-05-18 23:17:27.660624	25.67108986700783	-100.3539749261641	8.75
1814	1	2026-05-18 23:17:27.89511	25.67111983972811	-100.3540479299594	9.13
1815	1	2026-05-18 23:17:28.136622	25.67117120130812	-100.3541161154329	9.91
1816	1	2026-05-18 23:17:28.392621	25.6713430601416	-100.3544969967023	11.35
1817	1	2026-05-18 23:17:28.645229	25.67140404090259	-100.3545923779117	9.64
1818	1	2026-05-18 23:17:28.893586	25.67145383305207	-100.3546975852987	10.16
1819	1	2026-05-18 23:17:29.135961	25.67157142288176	-100.3550216866567	8.81
1820	1	2026-05-18 23:17:29.399826	25.67165990746198	-100.3553416765707	9.72
1821	1	2026-05-18 23:17:29.665762	25.67169572840783	-100.3554709465705	10.78
1822	1	2026-05-18 23:17:29.916414	25.67172561478113	-100.3555900011846	11.79
1823	1	2026-05-18 23:17:30.163455	25.67174549528364	-100.3556770175508	12.51
1824	1	2026-05-18 23:17:30.41579	25.67176848888821	-100.3557983075213	12.01
1825	1	2026-05-18 23:17:30.685187	25.67178564038652	-100.3558976335748	11.95
1826	1	2026-05-18 23:17:30.933413	25.67178096938655	-100.3558535230814	6.19
1827	1	2026-05-18 23:17:31.174666	25.67181850128054	-100.3559834911344	9.02
1828	1	2026-05-18 23:17:31.428855	25.67185057407621	-100.3561135380772	7.04
1829	1	2026-05-18 23:17:31.693334	25.67186600926695	-100.3562583546309	7.8
1830	1	2026-05-18 23:17:31.933487	25.67189756045958	-100.3563982905304	7.4
1831	1	2026-05-18 23:17:32.1618	25.67197815614277	-100.3566878708791	11.67
1832	1	2026-05-18 23:17:32.402603	25.67202910980223	-100.3569800352302	10.89
1833	1	2026-05-18 23:17:32.640833	25.6720738469455	-100.3571317904726	11.56
1834	1	2026-05-18 23:17:32.886853	25.67209981141449	-100.3571916967613	7.85
1835	1	2026-05-18 23:17:33.124499	25.67215476759353	-100.3575283812588	7.31
1836	1	2026-05-18 23:17:33.368326	25.67225568847287	-100.3578328557724	7.71
1837	1	2026-05-18 23:17:33.609973	25.67236247318676	-100.3581550227282	9.44
1838	1	2026-05-18 23:17:33.858552	25.67241902797115	-100.3583232354367	9.28
1839	1	2026-05-18 23:17:34.109772	25.67253234086721	-100.358730470743	6.16
1840	1	2026-05-18 23:17:34.39105	25.67261501296443	-100.3589345861596	4.74
1841	1	2026-05-18 23:17:34.663208	25.67267439891727	-100.35911853873	4.45
1842	1	2026-05-18 23:17:34.895981	25.67274149007044	-100.359491843898	4.69
1843	1	2026-05-18 23:17:35.128857	25.67275918114366	-100.3596774474788	6.88
1844	1	2026-05-18 23:17:35.380692	25.67276915726189	-100.3598709036478	6.64
1845	1	2026-05-18 23:17:35.638781	25.67277365110102	-100.360104146374	4.84
1846	1	2026-05-18 23:17:35.898345	25.67276397749958	-100.3603140211218	5.13
1847	1	2026-05-18 23:17:36.133352	25.67273969829522	-100.3605375585069	5.39
1848	1	2026-05-18 23:17:36.379964	25.67270728758056	-100.360739689126	6.11
1849	1	2026-05-18 23:17:36.628296	25.67266812179698	-100.3609341234613	7.0
1850	1	2026-05-18 23:17:36.885021	25.67254656021525	-100.3613204123863	9.01
1851	1	2026-05-18 23:17:37.13593	25.67247564262702	-100.3615073770893	9.97
1852	1	2026-05-18 23:17:37.377896	25.67239573538041	-100.3616930528236	11.18
1853	1	2026-05-18 23:17:37.625903	25.67231177670948	-100.3618671735971	12.21
1854	1	2026-05-18 23:17:37.889643	25.67221110720101	-100.3620585570284	12.98
1855	1	2026-05-18 23:17:38.124614	25.67209595167906	-100.3622475571076	12.57
1856	1	2026-05-18 23:17:38.364842	25.67193790228069	-100.3624778053236	8.2
1857	1	2026-05-18 23:17:38.60266	25.67152795394837	-100.3629785667759	5.68
1858	1	2026-05-18 23:17:38.84351	25.67138016331437	-100.3631335384256	5.33
1859	1	2026-05-18 23:17:39.100051	25.67107948661782	-100.3634177815466	5.09
1860	1	2026-05-18 23:17:39.347391	25.67093702908606	-100.3635609258851	4.8
1861	1	2026-05-18 23:17:39.595373	25.67063920478017	-100.3638071605978	5.43
1862	1	2026-05-18 23:17:39.890353	25.67048728225686	-100.3639078854685	5.86
1863	1	2026-05-18 23:17:40.201181	25.67018788821659	-100.3641548202275	5.9
1864	1	2026-05-18 23:17:40.438686	25.67004668763079	-100.3642786712626	6.75
1865	1	2026-05-18 23:17:40.692196	25.66975690855393	-100.3645706573069	6.86
1866	1	2026-05-18 23:17:40.961655	25.6693529630663	-100.3649898670317	9.28
1867	1	2026-05-18 23:18:32.221435	25.66922245231233	-100.3651314568857	10.27
1868	1	2026-05-18 23:18:32.483155	25.6690998058238	-100.3652723516727	11.3
1869	1	2026-05-18 23:18:32.733351	25.66897689108326	-100.3654197316342	12.02
1870	1	2026-05-18 23:18:32.982848	25.66884691151965	-100.3655569748426	12.59
1871	1	2026-05-18 23:18:33.257137	25.66873693045642	-100.3657109246597	13.94
1872	1	2026-05-18 23:18:33.527076	25.6686333593498	-100.3658690484634	15.02
1873	1	2026-05-18 23:18:33.786359	25.66853547521609	-100.3660374078078	16.34
1874	1	2026-05-18 23:18:34.048539	25.66841675243087	-100.366202800369	17.65
1875	1	2026-05-18 23:18:34.312966	25.66832078836741	-100.3663947232303	18.62
1876	1	2026-05-18 23:18:34.572774	25.6682445116184	-100.36660481252	18.78
1877	1	2026-05-18 23:18:34.838903	25.66819519811538	-100.3668230651144	19.33
1878	1	2026-05-18 23:18:35.095043	25.66813914273654	-100.3670950047481	28.6
1879	1	2026-05-18 23:18:35.342441	25.66812785109668	-100.3674947324058	28.11
1880	1	2026-05-18 23:18:35.605396	25.66812457785048	-100.3676927427548	28.91
1881	1	2026-05-18 23:18:35.894811	25.66811238044518	-100.3679584888842	29.83
1882	1	2026-05-18 23:20:20.90451	25.66811750060422	-100.3682217326653	31.53
1883	1	2026-05-18 23:20:21.158113	25.66811707746186	-100.3686036206598	29.69
1884	1	2026-05-18 23:20:21.426129	25.66813257717835	-100.3686309689482	18.36
1885	1	2026-05-18 23:20:21.694638	25.66819851727027	-100.3688786043758	18.42
1886	1	2026-05-18 23:20:21.972425	25.66823304310504	-100.3691390652481	17.98
1887	1	2026-05-18 23:20:22.244811	25.66825583483148	-100.3696540750086	22.48
1888	1	2026-05-18 23:20:22.499303	25.66812568659314	-100.3702087188351	16.58
1889	1	2026-05-18 23:20:22.756191	25.66812644889213	-100.3707465365138	15.22
1890	1	2026-05-18 23:20:23.015283	25.66812644889167	-100.371011418114	15.33
1891	1	2026-05-18 23:20:23.27162	25.66813523743142	-100.371307195233	15.26
1892	1	2026-05-18 23:20:23.539919	25.66809967580235	-100.3716005423451	15.13
1893	1	2026-05-18 23:20:23.789544	25.66807807776231	-100.3718487869374	15.69
1894	1	2026-05-18 23:20:24.055913	25.66803884357745	-100.3723994375378	16.18
1895	1	2026-05-18 23:20:24.316101	25.66801817233452	-100.3726446256337	16.33
1896	1	2026-05-18 23:20:24.836215	25.6679933005903	-100.3729145021681	16.5
1897	1	2026-05-18 23:20:25.090718	25.66796939038622	-100.3731603498367	16.87
1898	1	2026-05-18 23:20:25.349599	25.66794105497379	-100.3734516981313	16.71
1899	1	2026-05-18 23:20:25.617435	25.66791530897055	-100.3737315006967	17.03
1900	1	2026-05-18 23:20:25.888224	25.66789138378037	-100.374023997857	17.12
1901	1	2026-05-18 23:20:26.140348	25.66787282240386	-100.3743086193033	17.23
1902	1	2026-05-18 23:20:26.400003	25.66786307476786	-100.3746031393811	17.17
1903	1	2026-05-18 23:20:26.664894	25.66786159660452	-100.3751766456899	16.31
1904	1	2026-05-18 23:20:26.941627	25.66785210805489	-100.3757315221774	15.46
1905	1	2026-05-18 23:20:27.199413	25.6678510511152	-100.376030374453	15.42
1906	1	2026-05-18 23:20:27.455289	25.66785011508719	-100.3762869052526	14.71
1907	1	2026-05-18 23:20:27.709534	25.66785024793768	-100.37677723509	14.2
1908	1	2026-05-18 23:20:28.009613	25.66785494320188	-100.3770560332297	14.28
1909	1	2026-05-18 23:21:20.886277	25.66786102571232	-100.377561949665	14.51
1910	1	2026-05-18 23:21:21.135836	25.66780788935748	-100.3780925064918	17.93
1911	1	2026-05-18 23:21:51.644156	25.667794968484	-100.3784253576798	11.01
1912	1	2026-05-18 23:21:51.917725	25.66780588371288	-100.3786903687209	9.26
1913	1	2026-05-18 23:21:52.1595	25.66782036358963	-100.3789558852708	9.63
1914	1	2026-05-18 23:21:52.423693	25.66781798797817	-100.3792104381589	10.04
1915	1	2026-05-18 23:21:52.683268	25.66782389239748	-100.3794688497354	10.84
1916	1	2026-05-18 23:21:52.938783	25.66782429370615	-100.3799276098244	12.15
1917	1	2026-05-18 23:21:53.199208	25.66785129816374	-100.3803822842152	13.03
1918	1	2026-05-18 23:21:53.462728	25.66795188236324	-100.3805768771457	14.06
1919	1	2026-05-18 23:21:53.74723	25.66799311761863	-100.3807913521779	15.49
1920	1	2026-05-18 23:21:54.17926	25.66807721085359	-100.381205383702	18.41
1921	1	2026-05-18 23:21:56.650449	25.66816394712381	-100.3815249019985	20.11
1922	1	2026-05-18 23:21:56.905731	25.66822721306017	-100.3817364187027	21.18
1923	1	2026-05-18 23:21:57.151986	25.6682844197474	-100.3819207306404	21.76
1924	1	2026-05-18 23:21:57.403244	25.66840446231091	-100.3822742256484	23.63
1925	1	2026-05-18 23:21:57.65518	25.66847993608152	-100.3824476593487	25.01
1926	1	2026-05-18 23:21:57.903813	25.66856867382669	-100.3826238620351	26.38
1927	1	2026-05-18 23:21:58.144517	25.66837974528381	-100.3828620089428	26.58
1928	1	2026-05-18 23:21:58.384598	25.66842803497486	-100.3828762960734	24.9
1929	1	2026-05-18 23:21:58.647556	25.66852720961837	-100.3827637031928	14.21
1930	1	2026-05-18 23:21:58.890094	25.66859925325956	-100.3828646497689	10.1
1931	1	2026-05-18 23:21:59.153442	25.6688572954711	-100.3830573367485	10.8
1932	1	2026-05-18 23:21:59.395423	25.66920585287837	-100.3835637020656	12.73
1933	1	2026-05-18 23:21:59.659033	25.66929605561539	-100.3837100347452	13.56
1934	1	2026-05-18 23:21:59.910302	25.66941655457343	-100.3840592059529	15.83
1935	1	2026-05-18 23:22:00.16826	25.6694286511312	-100.3842533861497	16.15
1936	1	2026-05-18 23:22:00.457513	25.66942633079745	-100.3843113679891	13.15
1937	1	2026-05-18 23:22:00.707137	25.6693723192848	-100.3846463413954	7.21
1938	1	2026-05-18 23:22:00.96038	25.6693433555621	-100.384829041327	7.27
1939	1	2026-05-18 23:22:01.228859	25.6692843646462	-100.3852357113678	7.53
1940	1	2026-05-18 23:22:01.486249	25.66927083757791	-100.3854367459348	8.37
1941	1	2026-05-18 23:22:01.737422	25.66924233832233	-100.3858356734987	9.88
1942	1	2026-05-18 23:22:01.979091	25.66925989235074	-100.3862066234659	11.8
1943	1	2026-05-18 23:22:02.23776	25.6693197599788	-100.3864089825345	16.04
1944	1	2026-05-18 23:22:02.505161	25.6693868968998	-100.3865828510655	16.04
1945	1	2026-05-18 23:22:02.922361	25.66956079716527	-100.3869407852018	18.74
1946	1	2026-05-18 23:22:03.173899	25.66972773397187	-100.3872388399335	24.5
1947	1	2026-05-18 23:22:03.418739	25.66980559618339	-100.3873828485658	26.28
1948	1	2026-05-18 23:22:03.690878	25.66989000257021	-100.3875457778384	26.14
1949	1	2026-05-18 23:22:03.956479	25.66999583960518	-100.3877637055128	23.62
1950	1	2026-05-18 23:22:04.260407	25.67011510443943	-100.3879966673461	20.25
1951	1	2026-05-18 23:22:04.523596	25.67018317583783	-100.388136691031	16.55
1952	1	2026-05-18 23:22:04.779498	25.67027727285013	-100.3883297734512	14.66
1953	1	2026-05-18 23:22:05.030305	25.67037772829435	-100.3885349091747	14.25
1954	1	2026-05-18 23:22:05.286329	25.67047083480152	-100.3887256286887	15.74
1955	1	2026-05-18 23:22:05.558732	25.67057037882691	-100.3889295348917	15.46
1956	1	2026-05-18 23:22:05.807835	25.67066789594911	-100.3891284660291	15.08
1957	1	2026-05-18 23:22:06.052505	25.67084678911062	-100.3894921534292	13.82
1958	1	2026-05-18 23:22:06.29683	25.67094931493878	-100.3896980898213	13.27
1959	1	2026-05-18 23:22:06.552167	25.67103312838065	-100.3898687975154	12.82
1960	1	2026-05-18 23:22:06.803133	25.6711097085361	-100.39007582519	13.81
1961	1	2026-05-18 23:22:07.082715	25.67119223618896	-100.3902760645243	13.97
1962	1	2026-05-18 23:22:07.327078	25.67132955771671	-100.3906835278827	16.74
1963	1	2026-05-18 23:22:07.585608	25.67134462627313	-100.3909014739182	14.09
1964	1	2026-05-18 23:22:07.836018	25.67138328398157	-100.3910850321951	14.72
1965	1	2026-05-18 23:22:08.088846	25.67143497305736	-100.3913139346061	12.7
1966	1	2026-05-18 23:22:08.33617	25.67148343643441	-100.3915444137989	12.93
1967	1	2026-05-18 23:22:08.579177	25.67154177185264	-100.3921627055719	15.09
1968	1	2026-05-18 23:22:08.825562	25.67146556298731	-100.3925572348229	18.63
1969	1	2026-05-18 23:22:09.061536	25.6713781453319	-100.3928208086668	16.46
1970	1	2026-05-18 23:22:31.617079	25.67130482693309	-100.3930277988408	16.33
1971	1	2026-05-18 23:22:31.860363	25.67116678888883	-100.3934381952703	12.98
1972	1	2026-05-18 23:22:32.12858	25.67109748638753	-100.3936563570122	8.83
1973	1	2026-05-18 23:22:32.376427	25.67102905546672	-100.3938400449983	9.37
1974	1	2026-05-18 23:22:32.611871	25.67097136197546	-100.3940285566493	9.83
1975	1	2026-05-18 23:22:32.849049	25.67092579881893	-100.3942075328914	10.15
1976	1	2026-05-18 23:22:33.094302	25.6709033302292	-100.3943889742538	10.53
1977	1	2026-05-18 23:22:33.341544	25.67091086371074	-100.3945145162645	10.08
1978	1	2026-05-18 23:22:33.57584	25.67093142034227	-100.3946634129005	5.54
1979	1	2026-05-18 23:22:33.827133	25.67101755352676	-100.3949882965529	4.13
1980	1	2026-05-18 23:22:34.076927	25.67109610100002	-100.3951458087314	3.27
1981	1	2026-05-18 23:22:34.338516	25.67114079427838	-100.395304633231	3.93
1982	1	2026-05-18 23:22:34.592415	25.67116269533619	-100.3954664342655	7.43
1983	1	2026-05-18 23:22:34.857289	25.67116142785771	-100.3956475680271	7.04
1984	1	2026-05-18 23:22:35.119436	25.67115311913077	-100.3958233033533	10.37
1985	1	2026-05-18 23:22:35.370078	25.67114855066025	-100.3960338808628	6.93
1986	1	2026-05-18 23:22:35.625254	25.67116574897896	-100.3962370486705	4.7
1987	1	2026-05-18 23:22:35.877828	25.67116471064846	-100.3964397480492	9.98
1988	1	2026-05-18 23:22:36.140991	25.67114443932624	-100.3968371643404	9.01
1989	1	2026-05-18 23:22:36.375622	25.67110087637249	-100.3972812067497	13.69
1990	1	2026-05-18 23:22:36.617812	25.67107503563016	-100.397497337	12.09
1991	1	2026-05-18 23:22:36.843231	25.6710742780777	-100.3976523194844	12.29
1992	1	2026-05-18 23:22:37.089177	25.67109430635092	-100.3977930926816	5.81
1993	1	2026-05-18 23:22:37.34178	25.67116994806042	-100.3980388628657	3.8
1994	1	2026-05-18 23:22:37.585156	25.67120957606155	-100.3981594005418	3.3
1995	1	2026-05-18 23:22:37.834621	25.67123561091555	-100.3983064393729	3.49
1996	1	2026-05-18 23:22:38.082641	25.67127934142892	-100.3985843435601	4.67
1997	1	2026-05-18 23:22:38.323457	25.67127193859564	-100.3987582525945	5.12
1998	1	2026-05-18 23:22:38.56936	25.67121444564538	-100.3989147807361	5.86
1999	1	2026-05-18 23:22:38.830737	25.67120595573411	-100.3990920334328	5.74
2000	1	2026-05-18 23:22:39.076113	25.67118493898166	-100.3992789570888	6.63
2001	1	2026-05-18 23:22:39.31783	25.67116108049314	-100.3994722413741	5.52
2002	1	2026-05-18 23:22:39.55744	25.67114250005358	-100.3996709818813	6.43
2003	1	2026-05-18 23:22:39.794135	25.67106850487848	-100.400063710626	8.21
2004	1	2026-05-18 23:22:40.043014	25.67102174939338	-100.40027077878	9.28
2005	1	2026-05-18 23:22:40.294886	25.67095874944788	-100.4004688810779	10.82
2006	1	2026-05-18 23:22:40.543882	25.67086121654219	-100.4008911384219	13.39
2007	1	2026-05-18 23:22:40.790116	25.67080578692674	-100.4011307975412	14.57
2008	1	2026-05-18 23:22:41.035819	25.67075829337472	-100.4013745853773	16.16
2009	1	2026-05-18 23:22:41.291327	25.67068866314036	-100.4015799254258	17.65
2010	1	2026-05-18 23:22:41.532313	25.67061404242923	-100.4021039777994	17.88
2011	1	2026-05-18 23:24:31.663471	25.67046993227511	-100.4022480824714	9.32
2012	1	2026-05-18 23:24:31.915609	25.67032116536224	-100.402616974955	6.17
2013	1	2026-05-18 23:24:32.166042	25.67014484136824	-100.4029734253964	4.88
2014	1	2026-05-18 23:24:32.42261	25.67004313199615	-100.403145302488	4.22
2015	1	2026-05-18 23:24:32.697665	25.66993844654616	-100.4033345087094	3.9
2016	1	2026-05-18 23:24:32.960111	25.66982956161982	-100.4035187037949	3.73
2017	1	2026-05-18 23:24:33.212691	25.66971900057404	-100.4037063452731	3.75
2018	1	2026-05-18 23:24:33.472216	25.66960399918999	-100.4038770591178	3.43
2019	1	2026-05-18 23:24:33.726608	25.66937540397867	-100.4042346422698	3.35
2020	1	2026-05-18 23:24:33.977466	25.66925537427893	-100.4044226178561	3.54
2021	1	2026-05-18 23:24:34.249909	25.66914589358667	-100.4046154416791	3.61
2022	1	2026-05-18 23:24:34.497304	25.66902898417015	-100.4048029873834	3.99
2023	1	2026-05-18 23:24:34.757496	25.66890877357695	-100.404986587368	4.6
2024	1	2026-05-18 23:24:35.009073	25.66879090186342	-100.4051668254803	5.13
2025	1	2026-05-18 23:24:35.27553	25.66867025893436	-100.4053507676539	5.37
2026	1	2026-05-18 23:24:35.525424	25.66854452722599	-100.4055376883695	4.72
2027	1	2026-05-18 23:24:35.773931	25.66843281003708	-100.4057225947416	5.55
2028	1	2026-05-18 23:24:36.018783	25.66831765101688	-100.4059117518733	6.32
2029	1	2026-05-18 23:24:36.262559	25.66820508699548	-100.4061058799007	7.35
2030	1	2026-05-18 23:24:36.519972	25.66808775178407	-100.4063003656268	8.26
2031	1	2026-05-18 23:24:36.764039	25.66795500490027	-100.4064661728579	6.25
2032	1	2026-05-18 23:24:37.029813	25.66772043368722	-100.4068383611324	5.23
2033	1	2026-05-18 23:24:37.2601	25.66759906714897	-100.4070215667487	5.35
2034	1	2026-05-18 23:24:37.50981	25.66748594230654	-100.4071986008824	5.67
2035	1	2026-05-18 23:24:37.838347	25.6672782479047	-100.4075557721485	5.71
2036	1	2026-05-18 23:24:38.074104	25.66718689681294	-100.4077409273565	5.45
2037	1	2026-05-18 23:24:38.323255	25.66708984388307	-100.4079330894588	5.22
2038	1	2026-05-18 23:24:38.583171	25.66700200028905	-100.4081302764683	4.97
2039	1	2026-05-18 23:24:38.827383	25.66692642064312	-100.4083158620899	4.82
2040	1	2026-05-18 23:24:39.092004	25.66679410117906	-100.4087007326049	4.49
2041	1	2026-05-18 23:24:39.333167	25.66674598007141	-100.4088899836985	4.52
2042	1	2026-05-18 23:24:39.578215	25.66669222492225	-100.4090969074501	4.4
2043	1	2026-05-18 23:24:39.844498	25.66665959872692	-100.4093167237666	4.87
2044	1	2026-05-18 23:24:40.086942	25.6666102672727	-100.4095377713494	5.08
2045	1	2026-05-18 23:24:40.340175	25.66653748697852	-100.4100179312902	5.06
2046	1	2026-05-18 23:24:40.598304	25.66651187949019	-100.4102643074285	5.69
2047	1	2026-05-18 23:24:40.855513	25.66647487147784	-100.4105024046945	6.16
2048	1	2026-05-18 23:24:41.108655	25.66643080422907	-100.4107365239981	5.74
2049	1	2026-05-18 23:24:41.358838	25.66638637744168	-100.410965146004	5.27
2050	1	2026-05-18 23:24:41.593278	25.6663643766224	-100.4112050143753	5.05
2051	1	2026-05-18 23:24:41.828897	25.66632718499157	-100.4114426912375	6.72
2052	1	2026-05-18 23:24:42.083576	25.66629068681452	-100.411677365707	8.74
2053	1	2026-05-18 23:24:42.332923	25.66625641882533	-100.4119144902697	11.24
2054	1	2026-05-18 23:24:42.586082	25.66622543709493	-100.4121450971696	6.4
2055	1	2026-05-18 23:24:42.863787	25.666189401001	-100.4123867259071	4.66
2056	1	2026-05-18 23:24:43.11811	25.66616807234343	-100.4126261268011	4.06
2057	1	2026-05-18 23:24:43.36757	25.66613730502405	-100.412865226736	4.5
2058	1	2026-05-18 23:24:43.619454	25.66610619277712	-100.4131020717345	5.6
2059	1	2026-05-18 23:24:43.864134	25.66602704968564	-100.4135631501436	8.4
2060	1	2026-05-18 23:24:44.126237	25.66592064978651	-100.4142462434305	15.01
2061	1	2026-05-18 23:24:44.388434	25.66589558305558	-100.4144703209323	17.31
2062	1	2026-05-18 23:24:44.655675	25.66586847044403	-100.4146999117537	20.64
2063	1	2026-05-18 23:24:44.914491	25.66586775045735	-100.4149302969646	22.5
2064	1	2026-05-18 23:24:45.175247	25.66585752495266	-100.415161257084	22.08
2065	1	2026-05-18 23:24:45.441561	25.66584387418551	-100.4153950767962	23.54
2066	1	2026-05-18 23:24:45.697975	25.66584917148405	-100.4156361192821	23.33
2067	1	2026-05-18 23:24:45.953657	25.66585367081827	-100.4157570509993	21.57
2068	1	2026-05-18 23:24:46.219277	25.66587852222334	-100.4160757139291	21.57
2069	1	2026-05-18 23:24:46.489983	25.66586761399671	-100.4163114502196	20.81
2070	1	2026-05-18 23:25:20.526478	25.66588019585607	-100.4164950312102	21.16
2071	1	2026-05-18 23:25:20.776224	25.66589540140354	-100.4167175851434	19.96
2072	1	2026-05-18 23:25:21.024647	25.66590468490366	-100.4169428183762	20.2
2073	1	2026-05-18 23:25:21.271512	25.66590989119878	-100.4171098064859	19.26
2074	1	2026-05-18 23:25:21.529524	25.66592113295616	-100.4173199604615	19.73
2075	1	2026-05-18 23:25:21.790056	25.66595107124218	-100.4174711429267	13.43
2076	1	2026-05-18 23:25:22.034881	25.66596658021896	-100.4178358701069	5.18
2077	1	2026-05-18 23:25:22.286651	25.66596854883655	-100.4180207480713	4.71
2078	1	2026-05-18 23:25:22.53114	25.66596435849073	-100.4182031062041	4.58
2079	1	2026-05-18 23:25:22.795679	25.66595673617953	-100.4183717765826	4.83
2080	1	2026-05-18 23:25:23.044143	25.66594779581938	-100.4185400817313	5.33
2081	1	2026-05-18 23:25:23.297464	25.66599804490271	-100.4187252960384	5.65
2082	1	2026-05-18 23:25:23.549509	25.66596376643285	-100.4190751424904	5.76
2083	1	2026-05-18 23:25:23.806876	25.6659326166268	-100.4192114526928	5.47
2084	1	2026-05-18 23:25:24.059435	25.66590259757113	-100.4193553223768	5.12
2085	1	2026-05-18 23:25:24.343956	25.66587527374899	-100.4194946113346	4.93
2086	1	2026-05-18 23:25:24.600649	25.66585970293555	-100.4196517702553	4.69
2087	1	2026-05-18 23:25:24.868012	25.66584289328643	-100.4199572121799	4.63
2088	1	2026-05-18 23:25:25.137591	25.66583446296961	-100.4201068804853	4.77
2089	1	2026-05-18 23:25:25.390865	25.66581964277319	-100.4202436898386	4.87
2090	1	2026-05-18 23:25:25.668913	25.66581005694825	-100.4203829347784	5.09
2091	1	2026-05-18 23:25:25.91716	25.66580924550674	-100.4205186790401	4.96
2092	1	2026-05-18 23:25:26.18889	25.66577979689454	-100.4206483715122	4.45
2093	1	2026-05-18 23:25:26.444105	25.66576680657814	-100.4207629794113	4.36
2094	1	2026-05-18 23:25:26.693168	25.6657609905154	-100.4208501038641	4.36
2095	1	2026-05-18 23:25:26.943941	25.66575178177187	-100.4209752872516	4.73
2096	1	2026-05-18 23:25:27.200065	25.66574814222217	-100.4210110873174	4.96
2097	1	2026-05-18 23:25:27.452453	25.66576261835939	-100.4210102232854	4.56
2098	1	2026-05-18 23:25:27.71117	25.66576389511149	-100.4210192299234	4.83
2099	1	2026-05-18 23:25:27.972195	25.66576639007038	-100.4210236765541	4.94
2100	1	2026-05-18 23:25:28.226328	25.66576425992722	-100.42101728038	5.1
2101	1	2026-05-18 23:25:28.486293	25.66576300618805	-100.4210140643482	4.47
2102	1	2026-05-18 23:25:28.742837	25.66576388131152	-100.4210184843608	4.61
2103	1	2026-05-18 23:25:28.996136	25.66574625353082	-100.4210299082863	4.56
2104	1	2026-05-18 23:25:29.247651	25.66573666743462	-100.4210537753442	4.82
2105	1	2026-05-18 23:25:29.503239	25.66572264895885	-100.4210999982702	4.44
2106	1	2026-05-18 23:25:29.736844	25.66572800340079	-100.421151470773	4.68
2107	1	2026-05-18 23:25:29.982623	25.66571791784621	-100.421189059487	4.94
2108	1	2026-05-18 23:25:30.227856	25.66570645643297	-100.421238672592	4.99
2109	1	2026-05-18 23:25:30.475837	25.66570057270026	-100.4213009109469	5.51
2110	1	2026-05-18 23:25:30.720096	25.66567687764667	-100.421542144853	6.33
2111	1	2026-05-18 23:25:30.979669	25.66566853442512	-100.4216152398246	6.3
2112	1	2026-05-18 23:25:31.234721	25.66554934219644	-100.4216627590354	7.8
2113	1	2026-05-18 23:27:20.64136	25.66550460695671	-100.4216569263689	10.16
2114	1	2026-05-18 23:27:20.912921	25.66544307959015	-100.4216771500557	17.34
2115	1	2026-05-18 23:27:21.151762	25.66541849445829	-100.421673679185	20.71
2116	1	2026-05-18 23:27:21.428464	25.66542077064092	-100.4216664329945	13.35
2117	1	2026-05-18 23:27:21.675185	25.66540946479206	-100.4216792161865	11.13
2118	1	2026-05-18 23:27:21.941047	25.66539725703712	-100.4216814106677	11.17
2119	1	2026-05-18 23:27:22.219262	25.66537735981617	-100.4216558038827	9.76
2120	1	2026-05-18 23:27:22.484878	25.66524240075396	-100.4216875540257	14.07
2121	1	2026-05-18 23:27:22.757191	25.66514480853137	-100.4217231706732	14.21
2122	1	2026-05-18 23:27:23.022855	25.66509892654758	-100.4217532170022	16.73
2123	1	2026-05-18 23:27:23.282217	25.6650130760103	-100.4218336850442	17.03
2124	1	2026-05-18 23:27:23.537482	25.66493288090522	-100.4218594131435	3.83
2125	1	2026-05-18 23:27:23.79327	25.66487946667383	-100.4219108043401	3.25
2126	1	2026-05-18 23:27:24.052517	25.66465471330006	-100.4221107838367	6.62
2127	1	2026-05-18 23:27:24.321372	25.66457469501356	-100.4221811766737	8.71
2128	1	2026-05-18 23:27:24.57736	25.66440622216098	-100.4223207928911	12.73
2129	1	2026-05-18 23:27:24.847472	25.66432733137022	-100.4223962230631	14.96
2130	1	2026-05-18 23:27:25.108033	25.66416520892546	-100.4225533664106	19.65
2131	1	2026-05-18 23:27:25.349183	25.66408894990514	-100.4226128263144	21.8
2132	1	2026-05-18 23:27:25.603598	25.66391544677188	-100.422757031237	10.38
2133	1	2026-05-18 23:27:25.850209	25.66373098240195	-100.4228937171178	6.83
2134	1	2026-05-18 23:27:26.122383	25.66361620697815	-100.4229564417928	6.7
2135	1	2026-05-18 23:27:26.38426	25.66328310189127	-100.4230926950487	6.17
2136	1	2026-05-18 23:27:26.626101	25.66278351278829	-100.4231993932498	10.62
2137	1	2026-05-18 23:27:26.880397	25.66266805157722	-100.4232147156672	11.22
2138	1	2026-05-18 23:27:27.146962	25.6625610705081	-100.423233700336	12.54
2139	1	2026-05-18 23:27:27.415725	25.66237300485818	-100.4232760029234	14.97
2140	1	2026-05-18 23:27:27.676306	25.66229773714118	-100.4232928672392	15.73
2141	1	2026-05-18 23:27:27.957868	25.66227088258952	-100.4232779080214	17.03
2142	1	2026-05-18 23:27:28.21203	25.66222944033407	-100.4232872536807	18.16
2143	1	2026-05-18 23:27:28.457246	25.66222101000763	-100.4232750299498	19.28
2144	1	2026-05-18 23:27:28.702781	25.66219737475086	-100.4232795203616	19.99
2145	1	2026-05-18 23:27:28.963107	25.66215154743739	-100.4233004290943	19.3
2146	1	2026-05-18 23:27:29.215817	25.66201767582799	-100.4233238355878	10.96
2147	1	2026-05-18 23:27:29.472924	25.66197832351756	-100.4233043197744	9.48
2148	1	2026-05-18 23:27:29.736794	25.66194258075367	-100.4233151091887	8.31
2149	1	2026-05-18 23:27:29.993719	25.66189371148799	-100.4233181940364	7.6
2150	1	2026-05-18 23:27:30.248825	25.66182582988962	-100.4233439712937	6.87
2151	1	2026-05-18 23:27:30.508654	25.66174188506357	-100.4233799500147	6.3
2152	1	2026-05-18 23:27:30.751425	25.66159185981186	-100.4234040869644	5.69
2153	1	2026-05-18 23:27:31.001919	25.66149477137843	-100.4234221987466	7.35
2154	1	2026-05-18 23:27:31.235834	25.66132884739494	-100.4234499238282	5.9
2155	1	2026-05-18 23:27:31.468293	25.66113224757042	-100.4234830225274	6.62
2156	1	2026-05-18 23:27:31.718565	25.66093931043873	-100.4235199650131	5.18
2157	1	2026-05-18 23:27:31.958807	25.66084993557876	-100.4235403479314	4.79
2158	1	2026-05-18 23:27:32.209981	25.66075426589891	-100.4235582822294	4.67
2159	1	2026-05-18 23:27:32.471862	25.66064579841126	-100.4235894892338	4.88
2160	1	2026-05-18 23:27:32.726777	25.66031913096914	-100.4236368779674	4.32
2161	1	2026-05-18 23:27:32.975918	25.66021415573127	-100.4236634122779	6.09
2162	1	2026-05-18 23:27:33.223271	25.66011482077046	-100.4236822708149	7.53
2163	1	2026-05-18 23:27:33.473716	25.66000238894935	-100.4236806372571	5.27
2164	1	2026-05-18 23:27:33.722587	25.65991672483394	-100.4236894681623	4.25
2165	1	2026-05-18 23:27:33.951018	25.65983312006598	-100.4237082740473	3.56
2166	1	2026-05-18 23:27:34.180107	25.65969515304513	-100.423746309977	4.43
2167	1	2026-05-18 23:27:34.414603	25.65966606093843	-100.4237748032986	4.95
2168	1	2026-05-18 23:27:34.653579	25.65962586662308	-100.4238210389138	4.45
2169	1	2026-05-18 23:27:34.919615	25.65956506657395	-100.4238558576369	4.36
2170	1	2026-05-18 23:55:27.546913	25.65951119217933	-100.4239156053371	3.94
2171	1	2026-05-18 23:55:27.81892	25.6594848147636	-100.4240280266424	3.97
2172	1	2026-05-18 23:55:28.064188	25.6593557442488	-100.4242041536714	6.47
2173	1	2026-05-18 23:55:28.296864	25.65929194997896	-100.4242189052909	6.1
2174	1	2026-05-18 23:55:28.522938	25.65923036229339	-100.4242044124887	7.41
2175	1	2026-05-18 23:55:28.766221	25.65910258014619	-100.4241152151332	8.31
2176	1	2026-05-18 23:55:29.033918	25.65902454135731	-100.4240604290315	7.9
2177	1	2026-05-18 23:55:29.301221	25.65895661880258	-100.4239856815673	8.02
2178	1	2026-05-18 23:55:29.558807	25.65887803556883	-100.4239245265247	7.52
2179	1	2026-05-18 23:55:29.809297	25.65881624337015	-100.423821244551	5.22
2180	1	2026-05-18 23:55:30.06109	25.65865123198513	-100.4236625083685	5.14
2181	1	2026-05-18 23:55:30.300234	25.65854143386382	-100.4236148904802	5.63
2182	1	2026-05-18 23:55:30.563524	25.65843299027947	-100.4235871009851	6.44
2183	1	2026-05-18 23:55:30.837619	25.65818852009326	-100.4235339438183	11.81
2184	1	2026-05-18 23:55:31.116572	25.65795083281897	-100.4234364076023	16.47
2185	1	2026-05-18 23:55:31.36028	25.65782128809655	-100.4234052805	15.05
2186	1	2026-05-18 23:55:31.597994	25.65768463742147	-100.4233694766789	23.64
2187	1	2026-05-18 23:55:31.850333	25.65755015742142	-100.4233428208244	15.79
2188	1	2026-05-18 23:55:32.096337	25.65731733096715	-100.4232975214377	28.55
2189	1	2026-05-18 23:55:32.352789	25.65719422559127	-100.4232677916642	22.66
2190	1	2026-05-18 23:55:32.609929	25.65705149026566	-100.4232246998465	20.03
2191	1	2026-05-18 23:55:32.945954	25.656710807217	-100.4231684964477	15.96
2192	1	2026-05-18 23:55:33.281597	25.65660158806848	-100.4231228270262	18.05
2193	1	2026-05-18 23:55:33.536917	25.65648073919155	-100.4230934350518	18.66
2194	1	2026-05-18 23:55:33.812553	25.6563683375143	-100.4230767973388	27.17
2195	1	2026-05-18 23:55:34.057416	25.65624826042903	-100.4230490254117	24.52
2196	1	2026-05-18 23:55:34.309429	25.65593462019705	-100.4229626431954	19.22
2197	1	2026-05-18 23:55:34.547193	25.6557919827633	-100.4229213501879	9.47
2198	1	2026-05-18 23:55:34.78342	25.65572449131911	-100.4229075749786	7.65
2199	1	2026-05-18 23:55:35.036731	25.65565378912313	-100.4228912081223	6.16
2200	1	2026-05-18 23:55:35.291726	25.65558613610376	-100.4228888107986	6.72
2201	1	2026-05-18 23:55:35.536476	25.65555319268618	-100.4228941012254	6.21
2202	1	2026-05-18 23:55:35.79335	25.65552208312303	-100.4229061504342	6.36
2203	1	2026-05-18 23:55:36.03736	25.65550119769975	-100.4229103119207	5.63
2204	1	2026-05-18 23:55:36.282061	25.6554838925521	-100.4228996755854	5.12
2205	1	2026-05-18 23:55:36.563718	25.65544498059666	-100.4227270534921	5.14
2206	1	2026-05-18 23:55:36.821548	25.65545777675901	-100.4226835083773	5.25
2207	1	2026-05-18 23:55:37.065883	25.6554896122769	-100.4226524170081	5.45
2208	1	2026-05-18 23:55:37.311177	25.65551947070873	-100.4226342928076	5.93
2209	1	2026-05-18 23:55:37.575431	25.65551962276444	-100.4226342230675	6.99
2210	1	2026-05-18 23:55:37.843292	25.65551858321393	-100.4226346998982	8.02
2211	1	2026-05-18 23:55:38.090727	25.65577484262371	-100.4227181008192	7.63
2212	1	2026-05-18 23:55:38.332963	25.65589976448882	-100.4228100561493	5.73
2213	1	2026-05-18 23:55:38.575682	25.65609569228561	-100.4228666618615	5.77
2214	1	2026-05-18 23:55:38.826349	25.65617878374975	-100.4229001643086	8.31
2215	1	2026-05-18 23:55:39.067522	25.65627485730919	-100.4229299903933	7.46
2216	1	2026-05-18 23:55:39.334205	25.65633492212014	-100.4229475128345	7.51
2217	1	2026-05-18 23:55:39.584978	25.65640803952946	-100.4229189544371	7.34
2218	1	2026-05-18 23:55:39.8259	25.65650076147835	-100.4228620891469	8.13
2219	1	2026-05-18 23:55:40.073272	25.6565310286257	-100.4228480275708	8.35
2220	1	2026-05-18 23:55:40.326818	25.65656863235944	-100.4228346017873	8.45
2221	1	2026-05-18 23:55:40.567383	25.65673137492387	-100.4227767963361	13.04
2222	1	2026-05-18 23:55:40.81498	25.65678024274376	-100.422729771459	12.51
2223	1	2026-05-18 23:55:41.058235	25.6568266311946	-100.4227392579479	12.7
2224	1	2026-05-18 23:55:41.301397	25.65687516182762	-100.4227255610926	14.23
2225	1	2026-05-18 23:55:41.535889	25.65691494945286	-100.422721801527	13.67
2226	1	2026-05-18 23:55:41.855794	25.65694138602609	-100.4227416941659	13.79
2227	1	2026-05-18 23:55:42.11797	25.65695906161618	-100.4227540866925	14.62
2228	1	2026-05-18 23:55:42.355725	25.65695435639972	-100.4227541146601	14.87
2229	1	2026-05-18 23:55:42.61139	25.65697292831052	-100.4227683337111	14.58
2230	1	2026-05-18 23:55:42.8478	25.65696957894688	-100.4227677519107	15.34
2231	1	2026-05-18 23:55:43.093383	25.65697835634812	-100.4227700145645	15.95
2232	1	2026-05-18 23:55:43.34871	25.65697677241656	-100.4227460868605	15.73
2233	1	2026-05-18 23:55:43.589394	25.65696748979953	-100.4227455279637	15.45
2234	1	2026-05-18 23:55:43.820975	25.65697364117363	-100.4227450193396	15.74
2235	1	2026-05-18 23:55:44.057173	25.65697364117363	-100.4227450193396	15.4
2236	1	2026-05-18 23:55:44.305405	25.65697364117363	-100.4227450193396	14.58
2237	1	2026-05-18 23:55:44.602155	25.65697364117363	-100.4227450193396	13.42
2238	1	2026-05-18 23:55:44.842044	25.65697681595731	-100.4227496876598	13.29
2239	1	2026-05-18 23:55:45.086884	25.6569746684703	-100.4227475298179	13.43
2240	1	2026-05-18 23:55:45.324508	25.65698344410962	-100.4227502560252	13.7
2241	1	2026-05-18 23:55:45.570457	25.65700101345019	-100.4227578958336	13.53
2242	1	2026-05-18 23:55:45.820571	25.65703615353865	-100.4227418979751	13.35
2243	1	2026-05-18 23:55:46.069645	25.65705416982659	-100.4227539573022	13.35
2244	1	2026-05-18 23:55:46.315391	25.65707364992778	-100.4227497655286	13.61
2245	1	2026-05-18 23:55:46.562709	25.65709066758911	-100.4227586504155	14.31
2246	1	2026-05-18 23:55:46.80505	25.65710930677256	-100.4227536969701	15.56
2247	1	2026-05-18 23:55:47.051907	25.65717594445536	-100.4227904002178	16.86
2248	1	2026-05-18 23:55:47.299348	25.65717364411921	-100.4227868865667	16.61
2249	1	2026-05-18 23:55:47.551777	25.65717495895325	-100.4227932116137	16.64
2250	1	2026-05-18 23:55:47.79113	25.65717423381647	-100.4227894954494	17.15
2251	1	2026-05-18 23:55:48.036934	25.65718815308173	-100.4227952719763	17.24
2252	1	2026-05-18 23:55:48.312173	25.65717811795566	-100.4227750516842	17.07
2253	1	2026-05-18 23:55:48.545713	25.65714181453536	-100.4227635761969	17.43
2254	1	2026-05-18 23:55:48.789362	25.65712642769459	-100.4227638555535	17.19
2255	1	2026-05-18 23:55:49.031046	25.65712687390412	-100.4227666964824	16.96
2256	1	2026-05-18 23:55:49.275949	25.6571357782293	-100.4227671543622	16.64
2257	1	2026-05-18 23:55:49.516429	25.65714166326478	-100.4227595606843	16.63
2258	1	2026-05-18 23:55:49.754457	25.65714795291332	-100.4227677438538	16.42
2259	1	2026-05-18 23:55:49.998059	25.65714656589513	-100.4227645131802	16.4
2260	1	2026-05-18 23:55:50.247732	25.65714723771547	-100.422765922598	16.38
2261	1	2026-05-18 23:55:50.488919	25.65714980973932	-100.4227704459318	16.58
2262	1	2026-05-18 23:55:50.724442	25.65715466213891	-100.4227821928494	16.47
2263	1	2026-05-18 23:55:50.967549	25.65717130012929	-100.4227637777526	17.05
2264	1	2026-05-18 23:55:51.206399	25.657208333477	-100.4227802911154	17.02
2265	1	2026-05-18 23:55:51.441062	25.65723488643165	-100.4228090643221	16.89
2266	1	2026-05-18 23:55:51.745013	25.6572885359791	-100.4228257439938	16.39
2267	1	2026-05-18 23:55:51.988557	25.65731374513975	-100.4228512388098	16.47
2268	1	2026-05-18 23:55:52.296715	25.65734259688253	-100.4228852151437	16.33
2269	1	2026-05-18 23:55:52.541987	25.65737527263183	-100.4229074812604	16.45
2270	1	2026-05-18 23:58:20.548072	25.65743797918592	-100.4229843602811	16.21
2271	1	2026-05-18 23:58:20.794073	25.65746827466757	-100.423067589756	14.6
2272	1	2026-05-18 23:58:21.052403	25.65750612548214	-100.4231035533429	13.82
2273	1	2026-05-18 23:58:21.295833	25.65748796760795	-100.4231779082938	14.92
2274	1	2026-05-18 23:58:21.544563	25.65755405511625	-100.4232681027639	16.71
2275	1	2026-05-18 23:58:21.799116	25.65763941294793	-100.4232844946594	16.1
2276	1	2026-05-18 23:58:22.214012	25.6577864652374	-100.4233195876503	16.31
2277	1	2026-05-18 23:58:22.469873	25.65789478503714	-100.4233318681285	12.78
2278	1	2026-05-18 23:58:22.725086	25.65801288718661	-100.423348948089	10.36
2279	1	2026-05-18 23:58:22.977579	25.65832357998654	-100.423443492041	14.23
2280	1	2026-05-18 23:58:23.226452	25.65850511347723	-100.4234780034897	12.66
2281	1	2026-05-18 23:58:23.484981	25.6587405267714	-100.4234559726563	15.77
2282	1	2026-05-18 23:58:23.738596	25.65882144258865	-100.4234149216189	22.04
2283	1	2026-05-18 23:58:23.991111	25.65882405370109	-100.423411839612	21.19
2284	1	2026-05-18 23:58:24.235992	25.65883854083589	-100.4234042806989	21.44
2285	1	2026-05-18 23:58:24.492399	25.65887998102657	-100.4233805372361	22.03
2286	1	2026-05-19 00:00:20.663424	25.65889637833633	-100.4233693094454	22.66
2287	1	2026-05-19 00:00:20.927595	25.65884884708142	-100.4231567857551	22.57
2288	1	2026-05-19 00:00:21.201266	25.65886431412984	-100.4230971615448	22.17
2289	1	2026-05-19 00:00:21.457151	25.65887750183337	-100.4230165284861	23.87
2290	1	2026-05-19 00:00:21.731961	25.65888933598233	-100.4229263198361	23.88
2291	1	2026-05-19 00:00:21.991231	25.65889298691085	-100.422850759911	26.6
2292	1	2026-05-19 00:00:22.251332	25.65889400646004	-100.4227891701697	21.84
2293	1	2026-05-19 00:00:22.515542	25.65890830784879	-100.4226910500937	20.37
2294	1	2026-05-19 00:00:22.788613	25.65892928306415	-100.4225326480093	19.28
2295	1	2026-05-19 00:00:23.046303	25.65897206979739	-100.4219981066074	19.73
2296	1	2026-05-19 00:00:23.310859	25.65899464315924	-100.4217273741477	15.84
2297	1	2026-05-19 00:00:23.655149	25.6590036697813	-100.4215967132126	18.21
2298	1	2026-05-19 00:00:23.904906	25.65900702440022	-100.4214652212497	20.65
2299	1	2026-05-19 00:00:24.177626	25.65904267440088	-100.4209445442129	28.73
2300	1	2026-05-19 00:00:24.43035	25.65905180457889	-100.420790081417	30.56
2301	1	2026-05-19 00:00:24.716779	25.65906395902416	-100.4206378548475	32.79
2302	1	2026-05-19 00:00:24.969081	25.65907344746487	-100.420484287658	35.42
2303	1	2026-05-19 00:00:25.215794	25.65908312305685	-100.420327917109	39.05
2304	1	2026-05-19 00:00:25.463795	25.65911960790461	-100.4188793991696	47.63
2305	1	2026-05-19 00:00:25.714561	25.65913314624519	-100.4186768917259	47.63
2306	1	2026-05-19 00:00:25.989289	25.65912578660286	-100.4184215458646	45.83
2307	1	2026-05-19 00:00:26.247243	25.65917584629126	-100.4183215958043	32.53
2308	1	2026-05-19 00:00:26.507215	25.65924078052664	-100.4178967089041	21.04
2309	1	2026-05-19 00:00:26.762021	25.6592516754629	-100.4177177479422	18.41
2310	1	2026-05-19 00:00:27.016486	25.65928835507975	-100.4171270383129	15.42
2311	1	2026-05-19 00:00:27.264998	25.659240595895	-100.4165999286649	22.39
2312	1	2026-05-19 00:00:27.522559	25.65919817760501	-100.4163403811376	23.85
2313	1	2026-05-19 00:00:27.769106	25.65920952226996	-100.4162002273614	22.43
2314	1	2026-05-19 00:00:28.03258	25.65913503807421	-100.416072007304	23.35
2315	1	2026-05-19 00:00:28.298724	25.65913654235967	-100.415920691232	19.88
2316	1	2026-05-19 00:00:28.551411	25.6590215427996	-100.4156177232144	17.56
2317	1	2026-05-19 00:00:28.794243	25.65898582688291	-100.4155328226291	14.45
2318	1	2026-05-19 00:00:29.048586	25.65895195453367	-100.4154010380028	13.62
2319	1	2026-05-19 00:00:29.293766	25.6588771766645	-100.4152635075903	13.3
2320	1	2026-05-19 00:00:29.535774	25.65879635500599	-100.4149980207803	12.81
2321	1	2026-05-19 00:00:29.778035	25.65862955039747	-100.4147219326154	11.99
2322	1	2026-05-19 00:00:30.022792	25.65868646243214	-100.4147020456653	11.07
2323	1	2026-05-19 00:00:30.285123	25.65866164000809	-100.4146077203072	11.34
2324	1	2026-05-19 00:00:30.536507	25.65865189310719	-100.4145355155486	10.85
2325	1	2026-05-19 00:00:30.790129	25.65865757309641	-100.4144858914463	11.7
2326	1	2026-05-19 00:00:31.039579	25.65867416278569	-100.4144763555751	12.91
2327	1	2026-05-19 00:00:31.286932	25.65861997931381	-100.4145586940736	11.17
2328	1	2026-05-19 00:00:31.531391	25.65860485213377	-100.4145452469133	11.22
2329	1	2026-05-19 00:00:31.774125	25.65851541051561	-100.4145009124787	15.24
2330	1	2026-05-19 00:00:32.029496	25.65845286518054	-100.414514009997	18.44
2331	1	2026-05-19 00:00:32.287831	25.65838078634486	-100.4145140266335	23.48
2332	1	2026-05-19 00:00:32.5577	25.65834624035847	-100.4145139868384	26.38
2333	1	2026-05-19 00:00:32.795798	25.65832755316215	-100.4145079921481	28.0
2334	1	2026-05-19 00:00:33.03752	25.6588077869032	-100.4147991706856	29.5
2335	1	2026-05-19 00:00:33.293054	25.65885150275249	-100.4149055679725	32.28
2336	1	2026-05-19 00:00:33.540974	25.65885553716722	-100.4150095104962	45.11
2337	1	2026-05-19 00:00:33.792468	25.65888730653352	-100.4151121552924	27.04
2338	1	2026-05-19 00:00:34.044947	25.65890560405161	-100.4152135201833	20.56
2339	1	2026-05-19 00:00:34.301545	25.6590994166647	-100.4153304740957	22.11
2340	1	2026-05-19 00:00:34.555894	25.65912767937577	-100.4154218195047	19.98
2341	1	2026-05-19 00:00:34.813779	25.6591617316497	-100.4155338791264	20.37
2342	1	2026-05-19 00:00:35.059737	25.659217378145	-100.4157185927225	19.68
2343	1	2026-05-19 00:00:35.322865	25.65923528279765	-100.4157903512776	25.27
2344	1	2026-05-19 00:00:35.578101	25.65929612273688	-100.41591297516	22.0
2345	1	2026-05-19 00:00:35.832596	25.65931607263118	-100.4159771693186	25.58
2346	1	2026-05-19 00:00:36.094127	25.65938253253868	-100.4163157289508	22.25
2347	1	2026-05-19 00:00:36.341177	25.65940172729017	-100.4164117235771	23.15
2348	1	2026-05-19 00:00:36.584988	25.65942633486331	-100.4165261370517	22.19
2349	1	2026-05-19 00:00:36.827675	25.65946367115303	-100.416657795323	21.69
2350	1	2026-05-19 00:00:37.087197	25.65950330241191	-100.4169271532815	19.62
2351	1	2026-05-19 00:00:37.362417	25.65950725903657	-100.4170767178065	24.41
2352	1	2026-05-19 00:00:37.611342	25.65951415164141	-100.4172254120063	25.15
2353	1	2026-05-19 00:00:37.861973	25.65949059197634	-100.4173574380028	30.02
2354	1	2026-05-19 00:00:38.116948	25.65949761688326	-100.4175233392681	36.7
2355	1	2026-05-19 00:00:38.37156	25.65948846949637	-100.4176879759926	29.51
2356	1	2026-05-19 00:00:38.612627	25.65948137312123	-100.4178194561399	28.01
2357	1	2026-05-19 00:00:38.856865	25.65946584446991	-100.4180415250087	13.39
2358	1	2026-05-19 00:00:39.121256	25.65946989123479	-100.4181642639583	9.95
2359	1	2026-05-19 00:00:39.37083	25.65947075487529	-100.4182839111134	10.26
2360	1	2026-05-19 00:00:39.624931	25.6594560874938	-100.4183802243326	10.66
2361	1	2026-05-19 00:00:39.874551	25.6594856127632	-100.4185983401448	10.45
2362	1	2026-05-19 00:00:40.123892	25.65949290026839	-100.4188078318008	9.08
2363	1	2026-05-19 00:00:40.368231	25.65949142231075	-100.4188886525221	9.75
2364	1	2026-05-19 00:00:40.607668	25.65948343871917	-100.4189191453226	9.09
2365	1	2026-05-19 00:00:40.856662	25.65949663951106	-100.4189495228038	9.47
2366	1	2026-05-19 00:00:41.117295	25.65952987302617	-100.4189565258851	9.72
2367	1	2026-05-19 00:00:41.371596	25.6595375837316	-100.4189725158648	10.11
2368	1	2026-05-19 00:00:41.637902	25.65964353303092	-100.4189372220576	10.35
2369	1	2026-05-19 00:00:41.896655	25.65979888449968	-100.4189008744761	10.3
2370	1	2026-05-19 00:03:20.55369	25.65991795650618	-100.4188646594221	4.66
2371	1	2026-05-19 00:03:20.823095	25.65997766609865	-100.4188368209138	4.1
2372	1	2026-05-19 00:03:21.075882	25.6600358793882	-100.4188162215518	4.9
2373	1	2026-05-19 00:03:21.327861	25.66008015360281	-100.418799286468	6.09
2374	1	2026-05-19 00:03:21.592964	25.66011074942163	-100.4187910216322	6.87
2375	1	2026-05-19 00:03:21.841379	25.66020509893349	-100.4187850873443	6.8
2376	1	2026-05-19 00:03:22.091985	25.66026859892644	-100.4187731358887	7.72
2377	1	2026-05-19 00:03:22.334265	25.66034095589155	-100.4187613003714	9.37
2378	1	2026-05-19 00:03:22.586423	25.66041056316888	-100.4187497853382	30.08
2379	1	2026-05-19 00:03:22.8497	25.66047339841608	-100.4187433888859	31.93
2380	1	2026-05-19 00:03:23.102833	25.6605312803154	-100.4187350216515	27.81
2381	1	2026-05-19 00:03:23.345224	25.66057809153081	-100.4187280585461	26.69
2382	1	2026-05-19 00:03:23.603723	25.66064639258312	-100.418720618224	21.28
2383	1	2026-05-19 00:03:23.865109	25.66075907156187	-100.4187055858398	15.6
2384	1	2026-05-19 00:03:24.115799	25.66074292795619	-100.41871326918	12.3
2385	1	2026-05-19 00:03:24.365885	25.66077305942301	-100.4187068536387	14.01
2386	1	2026-05-19 00:03:24.614228	25.66082991326582	-100.4186838737574	17.07
2387	1	2026-05-19 00:03:24.865211	25.66081073425775	-100.4185695854359	13.77
2388	1	2026-05-19 00:03:25.10912	25.66080508577376	-100.4185261815535	20.19
2389	1	2026-05-19 00:03:25.384975	25.66082412340014	-100.4184422915769	16.56
2390	1	2026-05-19 00:03:25.639986	25.66087371634181	-100.4183811498238	17.21
2391	1	2026-05-19 00:03:25.884988	25.66090494017116	-100.4183243047926	16.61
2392	1	2026-05-19 00:03:26.138563	25.66109180308784	-100.4182037206558	14.85
2393	1	2026-05-19 00:05:20.648855	25.66130723280443	-100.4182376565854	21.02
2394	1	2026-05-19 00:05:20.902119	25.66136818450124	-100.4182269271758	35.39
2395	1	2026-05-19 00:05:21.158051	25.66154820838383	-100.4182914618675	25.76
2396	1	2026-05-19 00:05:21.418549	25.66168749204385	-100.4183139103852	23.18
2397	1	2026-05-19 00:05:21.670876	25.66176592703484	-100.4183264682696	43.73
2398	1	2026-05-19 00:05:21.921154	25.66192217844794	-100.4183643941603	31.73
2399	1	2026-05-19 00:05:22.170251	25.66194077648046	-100.4183691620339	34.58
2400	1	2026-05-19 00:05:22.414456	25.66196297308275	-100.4183807419127	30.64
2401	1	2026-05-19 00:05:22.667026	25.66199832962486	-100.4184003526201	28.9
2402	1	2026-05-19 00:05:22.920053	25.66198754410797	-100.4183892396367	29.36
2403	1	2026-05-19 00:05:23.167731	25.66198670998964	-100.41840551778	32.13
2404	1	2026-05-19 00:05:23.413697	25.66195885165216	-100.4183944206994	30.25
2405	1	2026-05-19 00:05:23.662283	25.66199372762537	-100.4184083131828	32.17
2406	1	2026-05-19 00:05:23.91818	25.66197820131558	-100.418402128439	30.77
2407	1	2026-05-19 00:05:24.16489	25.66198847803335	-100.4184243968798	31.39
2408	1	2026-05-19 00:05:24.428551	25.66200123185245	-100.418435946106	30.83
2409	1	2026-05-19 00:05:24.687365	25.66190294183564	-100.4186993045017	29.44
2410	1	2026-05-19 00:05:25.026547	25.66190201370783	-100.4187033850709	29.13
2411	1	2026-05-19 00:05:25.294823	25.66194536289163	-100.4187460895097	29.62
2412	1	2026-05-19 00:05:25.547079	25.66197222641633	-100.4188059352311	29.0
2413	1	2026-05-19 00:05:25.818926	25.66196130663752	-100.4188602467471	29.54
2414	1	2026-05-19 00:05:26.076316	25.66197593632915	-100.4190534844163	30.07
2415	1	2026-05-19 00:05:26.351113	25.66197720577005	-100.419148719589	31.24
2416	1	2026-05-19 00:05:26.597602	25.66195879227751	-100.4191473082372	32.16
2417	1	2026-05-19 00:05:26.851983	25.66191336959347	-100.4191459553778	31.45
2418	1	2026-05-19 00:05:27.112094	25.66180583625476	-100.4191555846617	38.38
2419	1	2026-05-19 00:05:27.365021	25.66173481906666	-100.4190848673323	34.48
2420	1	2026-05-19 00:05:27.61262	25.66173607134065	-100.4189575706323	30.39
2421	1	2026-05-19 00:05:27.864241	25.6617685780569	-100.4189345433902	29.24
2422	1	2026-05-19 00:05:28.113773	25.66180169083182	-100.4189270151908	27.73
2423	1	2026-05-19 00:05:28.376014	25.66181985563923	-100.4189212401104	27.26
2424	1	2026-05-19 00:05:28.617154	25.66183834646568	-100.4189365707693	22.75
2425	1	2026-05-19 00:05:28.867693	25.66182138560027	-100.4189469673575	21.63
2426	1	2026-05-19 00:05:29.113392	25.66180728413129	-100.4189636862638	18.86
2427	1	2026-05-19 00:05:29.357828	25.66182304499841	-100.4189325431386	35.53
2428	1	2026-05-19 00:05:29.605326	25.66178619945335	-100.4189664823515	11.05
2429	1	2026-05-19 00:05:29.857957	25.661788746018	-100.4189628439059	11.71
2430	1	2026-05-19 00:05:30.104647	25.66180008952239	-100.4189543699824	11.32
2431	1	2026-05-19 00:05:30.352541	25.66180276765564	-100.4189524048653	11.92
2432	1	2026-05-19 00:05:30.601317	25.66181404276371	-100.4189440377171	11.5
2433	1	2026-05-19 00:05:30.852023	25.66182019420149	-100.4189392276171	11.18
2434	1	2026-05-19 00:05:31.102576	25.66178684992148	-100.4189326319523	32.45
2435	1	2026-05-19 00:05:31.364281	25.66178694266938	-100.4189326028586	32.5
2436	1	2026-05-19 00:05:31.609456	25.66179245307487	-100.418930874321	31.41
2437	1	2026-05-19 00:05:31.855039	25.66176169731694	-100.418913101367	12.85
2438	1	2026-05-19 00:05:32.109689	25.66176218785123	-100.4189130892001	12.92
2439	1	2026-05-19 00:05:32.364189	25.66176278056109	-100.4189130744989	12.93
2440	1	2026-05-19 00:05:32.637588	25.66176301716021	-100.4189130686304	13.01
2441	1	2026-05-19 00:05:32.885889	25.66175852681171	-100.4189303941069	13.05
2442	1	2026-05-19 00:05:33.136055	25.66175968052287	-100.4189301630229	12.99
2443	1	2026-05-19 00:05:33.386938	25.66177862627797	-100.4189263682588	11.73
2444	1	2026-05-19 00:05:33.635127	25.66179079122492	-100.4189239316653	10.86
2445	1	2026-05-19 00:05:33.887718	25.66179090894782	-100.4189239080859	10.94
2446	1	2026-05-19 00:05:34.149341	25.66179143080313	-100.4189238035603	10.99
2447	1	2026-05-19 00:05:34.404709	25.66180037159967	-100.418922012752	10.22
2448	1	2026-05-19 00:05:34.662278	25.66177973591151	-100.4189212539311	10.18
2449	1	2026-05-19 00:05:34.909322	25.66178032388038	-100.4189211735766	10.15
2450	1	2026-05-19 00:05:35.158375	25.6617814819094	-100.4189210153153	10.16
2451	1	2026-05-19 00:05:35.422877	25.66179216736399	-100.4189195549935	9.5
2452	1	2026-05-19 00:05:35.680586	25.66179972318197	-100.4189152158	9.1
2453	1	2026-05-19 00:05:35.94664	25.6617998618947	-100.4189152049047	9.16
2454	1	2026-05-19 00:05:36.192022	25.66180064953991	-100.4189151430385	9.16
2455	1	2026-05-19 00:05:36.440815	25.66180103979149	-100.4189151031824	9.87
2456	1	2026-05-19 00:05:36.689068	25.66179662148965	-100.4189123397564	9.38
2457	1	2026-05-19 00:05:36.937893	25.6617971116088	-100.4189123262811	10.1
2458	1	2026-05-19 00:05:37.203613	25.66179748404975	-100.4189123160413	10.76
2459	1	2026-05-19 00:05:37.45679	25.66185656338262	-100.4189106917239	25.56
2460	1	2026-05-19 00:05:37.705029	25.66185656338262	-100.4189106917239	24.84
2461	1	2026-05-19 00:05:37.950449	25.66185656338262	-100.4189106917239	25.29
2462	1	2026-05-19 00:05:38.195175	25.66185656338262	-100.4189106917239	25.7
2463	1	2026-05-19 00:05:38.438302	25.66185656338262	-100.4189106917239	25.87
2464	1	2026-05-19 00:05:38.677731	25.66185209396448	-100.4189222254506	26.47
2465	1	2026-05-19 00:05:38.923835	25.66185209396448	-100.4189222254506	25.92
2466	1	2026-05-19 00:05:39.184813	25.66185209396448	-100.4189222254506	25.45
2467	1	2026-05-19 00:05:39.432786	25.66185209396448	-100.4189222254506	25.59
2468	1	2026-05-19 00:05:39.691102	25.66185209396448	-100.4189222254506	24.49
2469	1	2026-05-19 00:08:20.583618	25.66185209396448	-100.4189222254506	24.96
2470	1	2026-05-19 00:08:20.842937	25.66185209396448	-100.4189222254506	24.33
2471	1	2026-05-19 00:08:21.136877	25.66185209396448	-100.4189222254506	24.71
2472	1	2026-05-19 00:08:21.386419	25.66185209396448	-100.4189222254506	24.96
2473	1	2026-05-19 00:08:21.644545	25.66185209396448	-100.4189222254506	24.71
2474	1	2026-05-19 00:08:21.890983	25.66185209396448	-100.4189222254506	24.66
2475	1	2026-05-19 00:08:22.155789	25.66185209396448	-100.4189222254506	24.21
2476	1	2026-05-19 00:08:22.4105	25.66185209396448	-100.4189222254506	24.86
2477	1	2026-05-19 00:08:22.664396	25.66185209396448	-100.4189222254506	26.35
2478	1	2026-05-19 00:08:22.915814	25.66185209396448	-100.4189222254506	25.34
2479	1	2026-05-19 00:08:23.16558	25.66184379112005	-100.418914953097	24.38
2480	1	2026-05-19 00:08:23.426071	25.66181450004822	-100.4188889779808	24.03
2481	1	2026-05-19 00:08:23.676561	25.6618124874774	-100.4189010453868	23.19
2482	1	2026-05-19 00:08:23.946469	25.66180544622493	-100.4189028581282	22.75
2483	1	2026-05-19 00:08:24.200367	25.66180515990964	-100.4189035406751	24.49
2484	1	2026-05-19 00:08:24.448718	25.66180515990964	-100.4189035406751	24.24
2485	1	2026-05-19 00:08:24.699904	25.66180515990964	-100.4189035406751	25.26
2486	1	2026-05-19 00:08:24.961924	25.66180515990964	-100.4189035406751	25.28
2487	1	2026-05-19 00:08:25.210948	25.66181421180497	-100.4188950845508	25.34
2488	1	2026-05-19 00:08:25.463193	25.66181643669559	-100.4188869125641	25.51
2489	1	2026-05-19 00:08:25.717882	25.66181981079208	-100.4188907614977	24.9
2490	1	2026-05-19 00:08:25.968276	25.66182830361779	-100.4188711232943	24.96
2491	1	2026-05-19 00:08:26.253616	25.66182561450859	-100.4188780827085	24.24
2492	1	2026-05-19 00:08:26.501444	25.66182512282673	-100.4188780246643	23.73
2493	1	2026-05-19 00:08:26.747342	25.66182512282673	-100.4188780246643	22.66
2494	1	2026-05-19 00:08:26.993483	25.66182512282673	-100.4188780246643	22.07
2495	1	2026-05-19 00:08:27.246589	25.66182512282673	-100.4188780246643	20.75
2496	1	2026-05-19 00:08:27.501544	25.66181654092215	-100.4188926776473	21.21
2497	1	2026-05-19 00:08:27.749563	25.66181654092215	-100.4188926776473	21.45
2498	1	2026-05-19 00:08:27.997738	25.66181654092215	-100.4188926776473	21.44
2499	1	2026-05-19 00:08:28.233279	25.66181654092215	-100.4188926776473	21.44
2500	1	2026-05-19 00:10:20.553285	25.66181654092215	-100.4188926776473	21.23
2501	1	2026-05-19 00:10:20.808009	25.66181951982864	-100.4188806796964	21.7
2502	1	2026-05-19 00:10:21.057326	25.66181600765524	-100.4188825613812	21.98
2503	1	2026-05-19 00:10:21.328984	25.66181707653648	-100.4188898378441	21.71
2504	1	2026-05-19 00:10:21.571651	25.66181439208633	-100.4188849913456	21.58
2505	1	2026-05-19 00:10:21.816226	25.66180428800346	-100.4188948757445	21.31
2506	1	2026-05-19 00:10:22.060228	25.66180611406051	-100.4188854200404	19.71
2507	1	2026-05-19 00:10:22.314596	25.66179035541445	-100.4188851503813	19.63
2508	1	2026-05-19 00:10:22.565553	25.66179732826983	-100.4188802574391	18.78
2509	1	2026-05-19 00:10:22.812863	25.66181277187611	-100.4188793593767	18.32
2510	1	2026-05-19 00:10:23.060689	25.66180768096763	-100.4188700479576	17.95
2511	1	2026-05-19 00:10:23.31379	25.66180249420148	-100.4188333954922	17.71
2512	1	2026-05-19 00:10:23.555795	25.66179520011605	-100.4188370699672	17.88
2513	1	2026-05-19 00:10:23.811763	25.66178088701695	-100.4188518608256	17.72
2514	1	2026-05-19 00:10:24.067049	25.66177844695493	-100.4188315999499	17.43
2515	1	2026-05-19 00:10:24.331166	25.66178396145891	-100.4188457062967	17.1
2516	1	2026-05-19 00:10:24.577776	25.66178324351947	-100.4188495627522	16.83
2517	1	2026-05-19 00:10:24.825487	25.66178915710545	-100.4188650854085	16.34
2518	1	2026-05-19 00:10:25.08279	25.66178623007557	-100.4188565660763	16.61
2519	1	2026-05-19 00:10:25.337726	25.66178530552748	-100.4188472966228	16.52
2520	1	2026-05-19 00:10:25.592049	25.66178511002795	-100.4188498393559	16.46
2521	1	2026-05-19 00:10:25.8506	25.66179010913285	-100.4188548683994	16.56
2522	1	2026-05-19 00:10:26.097268	25.66179515892892	-100.4188606135991	16.2
2523	1	2026-05-19 00:10:26.349073	25.66179780252413	-100.4188573763155	16.02
2524	1	2026-05-19 00:10:26.62201	25.66180388033861	-100.4188584294723	15.46
2525	1	2026-05-19 00:10:26.882887	25.66180689082911	-100.4188651646202	15.26
2526	1	2026-05-19 00:10:27.131594	25.66180505282323	-100.4188685748236	14.95
2527	1	2026-05-19 00:10:27.385812	25.66180436917683	-100.4188584504849	14.41
2528	1	2026-05-19 00:10:27.642068	25.6617958401977	-100.4188600312555	13.43
2529	1	2026-05-19 00:10:27.897251	25.66179512021328	-100.4188684132385	13.14
2530	1	2026-05-19 00:10:28.15678	25.66179682006931	-100.4188700126531	14.18
2531	1	2026-05-19 00:10:28.406114	25.66180340388593	-100.4188762642803	14.25
2532	1	2026-05-19 00:10:28.667269	25.66180848533057	-100.4189009960316	14.35
2533	1	2026-05-19 00:10:28.930914	25.66180735524165	-100.4189074872599	13.96
2534	1	2026-05-19 00:10:29.187665	25.66181106730614	-100.4189081456924	13.65
2535	1	2026-05-19 00:10:29.457765	25.66179684255455	-100.4189640044855	13.29
2536	1	2026-05-19 00:10:29.706021	25.66179318922683	-100.4189704892811	12.97
2537	1	2026-05-19 00:10:29.964932	25.66179930414371	-100.4189871758854	12.82
2538	1	2026-05-19 00:10:30.212831	25.66180340351799	-100.4189929424763	12.77
2539	1	2026-05-19 00:10:30.499077	25.66179639767882	-100.4190036930321	12.29
2540	1	2026-05-19 00:10:30.767685	25.66180308235524	-100.4190080056376	12.38
2541	1	2026-05-19 00:10:31.02209	25.66179635821232	-100.4190123065933	11.91
2542	1	2026-05-19 00:10:31.281033	25.66180167669862	-100.4190248298166	11.28
2543	1	2026-05-19 00:10:31.539738	25.66179995676102	-100.4190207093686	11.0
2544	1	2026-05-19 00:10:31.793914	25.66180357504069	-100.4190326698741	10.74
2545	1	2026-05-19 00:10:32.048008	25.66180120863008	-100.4190441499301	10.42
2546	1	2026-05-19 00:10:32.296204	25.66178055931003	-100.4190629037454	10.03
2547	1	2026-05-19 00:10:32.556188	25.66179492394554	-100.4190727021405	9.73
2548	1	2026-05-19 00:10:32.810505	25.6617820949459	-100.4190946062048	9.04
2549	1	2026-05-19 00:10:33.072498	25.66177344987545	-100.4190956202573	8.82
2550	1	2026-05-19 00:10:33.333365	25.66173959255577	-100.4191529130865	7.64
2551	1	2026-05-19 00:10:33.587466	25.66174433122409	-100.4191981654254	7.33
2552	1	2026-05-19 00:10:33.843079	25.6617496374117	-100.419225249072	7.24
2553	1	2026-05-19 00:10:34.098897	25.66174699513811	-100.4192329826662	7.35
2554	1	2026-05-19 00:10:34.358888	25.66175110897782	-100.4192222352975	7.41
2555	1	2026-05-19 00:10:34.625857	25.66174537032759	-100.4192039448274	7.9
2556	1	2026-05-19 00:10:34.889137	25.66174574225264	-100.4192332537215	7.88
2557	1	2026-05-19 00:10:35.153246	25.66176011691751	-100.4192504033542	7.71
2558	1	2026-05-19 00:10:35.407033	25.66174649437987	-100.4193284791881	8.05
2559	1	2026-05-19 00:10:35.652034	25.66174922696796	-100.4193463381773	8.5
2560	1	2026-05-19 00:10:36.101948	25.66175109841362	-100.4193623314724	8.4
2561	1	2026-05-19 00:10:36.559395	25.66175981962883	-100.4193785672187	9.0
2562	1	2026-05-19 00:10:36.884034	25.66176545321512	-100.4193609623469	10.02
2563	1	2026-05-19 00:10:37.348152	25.66176356295901	-100.4193581054488	9.76
2564	1	2026-05-19 00:10:37.653065	25.66176141130951	-100.4193676627435	9.73
2565	1	2026-05-19 00:10:37.951692	25.66176619418707	-100.4193685079122	9.71
2566	1	2026-05-19 00:10:38.245811	25.66177437552975	-100.4193691173364	9.73
2567	1	2026-05-19 00:10:38.545038	25.66178383512394	-100.4193827204559	15.27
2568	1	2026-05-19 00:10:38.854954	25.66184207177124	-100.4193687963234	17.63
2569	1	2026-05-19 00:10:39.191074	25.66185948103014	-100.4193698438307	20.61
2570	1	2026-05-19 00:10:39.495305	25.66186174907961	-100.4193724348611	23.89
2571	1	2026-05-19 00:10:39.830571	25.66187621164777	-100.4193873049291	32.02
2572	1	2026-05-19 00:13:20.533213	25.66188216428486	-100.4193903235509	37.07
2573	1	2026-05-19 00:13:20.787833	25.66189894484599	-100.4194064712003	47.42
2574	1	2026-05-19 00:13:21.037014	25.66191271236874	-100.4194243005293	51.94
2575	1	2026-05-19 00:13:21.284395	25.6618968279927	-100.419393453116	56.88
2576	1	2026-05-19 00:13:21.52599	25.66176795074061	-100.4195875979575	41.59
2577	1	2026-05-19 00:13:21.768064	25.66170597275239	-100.4196727096139	42.0
2578	1	2026-05-19 00:13:22.032645	25.66181187532184	-100.4196711101404	22.31
2579	1	2026-05-19 00:13:22.286804	25.66180452556697	-100.4196752927233	20.24
2580	1	2026-05-19 00:13:22.542069	25.66180952126082	-100.4196590280636	22.36
2581	1	2026-05-19 00:13:22.788417	25.66171025771018	-100.4197391595505	22.57
2582	1	2026-05-19 00:13:23.043643	25.66165779965509	-100.4197262767527	23.37
2583	1	2026-05-19 00:13:23.292364	25.66167963313925	-100.4197873544207	24.62
2584	1	2026-05-19 00:13:23.53967	25.66174513789678	-100.4198266849145	25.21
2585	1	2026-05-19 00:13:23.795164	25.66178811730773	-100.419828092874	28.16
2586	1	2026-05-19 00:13:24.041091	25.66179081553181	-100.419817188093	29.01
2587	1	2026-05-19 00:13:24.287108	25.66186481892898	-100.419834090992	23.67
2588	1	2026-05-19 00:13:24.544535	25.66187678412804	-100.4198429225178	24.58
2589	1	2026-05-19 00:13:24.794843	25.66185058053231	-100.4197667391749	25.04
2590	1	2026-05-19 00:13:25.045996	25.66178539912052	-100.4198218814952	29.73
2591	1	2026-05-19 00:13:25.294529	25.66178245018867	-100.4198204866854	32.24
2592	1	2026-05-19 00:13:25.551908	25.66165177568869	-100.4198383772893	21.38
2593	1	2026-05-19 00:13:25.816929	25.66174032892501	-100.4198220096422	19.42
2594	1	2026-05-19 00:13:26.059294	25.66173394773341	-100.4198256595884	19.15
2595	1	2026-05-19 00:13:26.309184	25.66168781408466	-100.4198232698336	19.95
2596	1	2026-05-19 00:13:26.56274	25.66178453328295	-100.4198216529869	20.54
2597	1	2026-05-19 00:13:26.812054	25.66178193957025	-100.4198052450703	22.94
2598	1	2026-05-19 00:13:27.059296	25.66179265170897	-100.4198437903285	25.92
2599	1	2026-05-19 00:13:27.30574	25.66180924390523	-100.4198554029655	42.15
2600	1	2026-05-19 00:13:27.558876	25.66184815333873	-100.4198763819265	47.39
2601	1	2026-05-19 00:13:27.806246	25.66186561709467	-100.419889336001	52.83
2602	1	2026-05-19 00:13:28.052551	25.66187649952885	-100.41989398026	58.06
2603	1	2026-05-19 00:13:28.297595	25.66189289425152	-100.4199013543296	64.84
2604	1	2026-05-19 00:13:28.546334	25.66191410745467	-100.4199155917982	71.44
2605	1	2026-05-19 00:13:28.792042	25.66192759331357	-100.4199271123468	74.19
2606	1	2026-05-19 00:13:29.057783	25.66171590240297	-100.4200077709746	36.9
2607	1	2026-05-19 00:15:20.584604	25.66192782510612	-100.4197561184	32.89
2608	1	2026-05-19 00:15:20.894163	25.66194299299396	-100.4197427775282	34.59
2609	1	2026-05-19 00:15:21.166233	25.6618426931093	-100.4201366601203	6.81
2610	1	2026-05-19 00:15:21.428239	25.66183997771515	-100.4201427315935	6.83
2611	1	2026-05-19 00:15:21.698932	25.66183977202589	-100.4201481834042	6.28
2612	1	2026-05-19 00:15:21.989465	25.66188706914345	-100.4201471334563	6.51
2613	1	2026-05-19 00:15:22.277763	25.66185943412571	-100.4201773993842	7.29
2614	1	2026-05-19 00:15:22.563431	25.66189813871983	-100.4201772733763	6.74
2615	1	2026-05-19 00:15:22.838663	25.66190944719225	-100.4201751711236	8.91
2616	1	2026-05-19 00:15:23.113591	25.66190649492398	-100.4201762878876	10.28
2617	1	2026-05-19 00:15:23.361669	25.66191565867337	-100.4201861327055	14.89
2618	1	2026-05-19 00:15:23.618132	25.66192126701138	-100.4201984030962	24.5
2619	1	2026-05-19 00:15:23.864208	25.66191555629889	-100.4201999187794	27.84
2620	1	2026-05-19 00:15:24.106087	25.66189358892323	-100.420281128606	25.1
2621	1	2026-05-19 00:15:24.358405	25.66193470220698	-100.4202776694296	26.51
2622	1	2026-05-19 00:15:24.688584	25.66188744720672	-100.4202254985311	23.26
2623	1	2026-05-19 00:15:24.94413	25.66191563452011	-100.4202542888665	21.53
2624	1	2026-05-19 00:15:25.18407	25.6620512080086	-100.4203547886205	21.94
2625	1	2026-05-19 00:15:25.439104	25.66207969477285	-100.4203488443014	23.9
2626	1	2026-05-19 00:15:25.69471	25.66210774813437	-100.4203708540574	26.14
2627	1	2026-05-19 00:15:25.934228	25.66211046318168	-100.420376961329	28.34
2628	1	2026-05-19 00:15:26.189675	25.66209926256897	-100.420329346598	29.51
2629	1	2026-05-19 00:15:26.454684	25.66212748722258	-100.4203686159939	35.67
2630	1	2026-05-19 00:15:26.705717	25.66222117357442	-100.4203674210069	38.46
2631	1	2026-05-19 00:15:26.958685	25.66222292320798	-100.4204976425548	39.95
2632	1	2026-05-19 00:15:27.212078	25.66215361303906	-100.4205027940248	35.66
2633	1	2026-05-19 00:15:27.471997	25.6620977444324	-100.4204935891463	36.79
2634	1	2026-05-19 00:15:27.71045	25.6621132389266	-100.4204902233621	39.25
2635	1	2026-05-19 00:15:27.962777	25.66211474661008	-100.4205026092719	49.27
2636	1	2026-05-19 00:15:28.205657	25.66210285012323	-100.4204736579548	11.0
2637	1	2026-05-19 00:15:28.458508	25.662054390061	-100.4205073867214	48.87
2638	1	2026-05-19 00:15:28.728183	25.66198743415622	-100.4204339907509	19.77
2639	1	2026-05-19 00:15:28.983053	25.66191436439843	-100.4205089976221	39.58
2640	1	2026-05-19 00:15:29.227058	25.66191409623219	-100.4205075160028	29.66
2641	1	2026-05-19 00:15:29.485476	25.66192235714703	-100.4204894217068	28.04
2642	1	2026-05-19 00:15:29.72631	25.66193944668009	-100.4205196670064	28.47
2643	1	2026-05-19 00:15:30.012655	25.66186534460027	-100.4204417720414	20.65
2644	1	2026-05-19 00:15:30.258442	25.66184431228023	-100.4204578904647	16.35
2645	1	2026-05-19 00:15:30.509448	25.66182803958492	-100.4204319434048	14.02
2646	1	2026-05-19 00:15:30.768638	25.66183339280026	-100.4204425809751	14.56
2647	1	2026-05-19 00:15:31.01252	25.66187693260546	-100.4204167995081	14.98
2648	1	2026-05-19 00:15:31.273992	25.66190091744137	-100.4204199892108	13.78
2649	1	2026-05-19 00:15:31.518336	25.66188788082336	-100.4204342041906	9.0
2650	1	2026-05-19 00:15:31.767039	25.66190146680063	-100.4204299213807	9.63
2651	1	2026-05-19 00:15:32.021031	25.6618739868689	-100.4204748674282	9.76
2652	1	2026-05-19 00:15:32.270781	25.66186389738057	-100.4204834526759	15.99
2653	1	2026-05-19 00:15:32.543204	25.661863470583	-100.4204914066206	20.37
2654	1	2026-05-19 00:15:32.797696	25.66185707085103	-100.4204604283582	17.55
2655	1	2026-05-19 00:15:33.059445	25.6618499090107	-100.4204633821386	21.76
2656	1	2026-05-19 00:15:33.314625	25.66185871306459	-100.4204551563021	29.05
2657	1	2026-05-19 00:15:33.55764	25.66181447641618	-100.4204902690386	26.59
2658	1	2026-05-19 00:15:34.063872	25.66181558985156	-100.4205104046406	26.66
2659	1	2026-05-19 00:15:34.31436	25.66182608330077	-100.4204825548181	12.02
2660	1	2026-05-19 00:15:34.579402	25.66183264994022	-100.4204636242318	7.92
2661	1	2026-05-19 00:15:34.822487	25.66190001419184	-100.4204759779883	12.07
2662	1	2026-05-19 00:15:35.069916	25.66187411594889	-100.420493014435	13.45
2663	1	2026-05-19 00:15:35.316181	25.66188726085145	-100.4204992681541	18.8
2664	1	2026-05-19 00:15:35.560703	25.66189678483726	-100.4205006882702	22.42
2665	1	2026-05-19 00:15:35.810847	25.66189764179589	-100.4205031467379	25.96
2666	1	2026-05-19 00:15:36.055566	25.66193715491156	-100.4204981604948	27.87
2667	1	2026-05-19 00:15:36.313916	25.66192267455237	-100.4204793531157	25.25
2668	1	2026-05-19 00:15:36.56571	25.66190687986894	-100.4204205330688	25.72
2669	1	2026-05-19 00:15:36.815805	25.66185953311486	-100.4204206845987	23.04
2670	1	2026-05-19 00:15:37.065468	25.66186127050376	-100.4203835621715	21.8
2671	1	2026-05-19 00:15:37.324418	25.66186603596853	-100.4203794790019	19.86
2672	1	2026-05-19 00:18:20.565185	25.66185355993163	-100.4203657346513	15.4
2673	1	2026-05-19 00:18:20.818257	25.66180271005717	-100.4203180985297	12.91
2674	1	2026-05-19 00:18:21.06817	25.66182053265057	-100.4203889498352	9.76
2675	1	2026-05-19 00:18:21.316699	25.66182521882697	-100.4203897942	10.57
2676	1	2026-05-19 00:18:21.568345	25.66179041432892	-100.4204075329885	12.64
2677	1	2026-05-19 00:18:21.810764	25.66179777974181	-100.4204136340549	13.12
2678	1	2026-05-19 00:18:22.061565	25.66182245291451	-100.4204446871353	11.37
2679	1	2026-05-19 00:18:22.306877	25.66181985223054	-100.4204570819403	11.54
2680	1	2026-05-19 00:18:22.564125	25.66181974596129	-100.4204571516647	10.66
2681	1	2026-05-19 00:18:22.804542	25.66181974596129	-100.4204571516647	10.24
2682	1	2026-05-19 00:18:23.046814	25.66184233090457	-100.4205117607002	12.24
2683	1	2026-05-19 00:18:23.299569	25.66183918775932	-100.4205151070844	12.94
2684	1	2026-05-19 00:18:23.548	25.66183016645933	-100.420533124012	15.75
2685	1	2026-05-19 00:18:23.80249	25.66184769315541	-100.4205434434192	15.4
2686	1	2026-05-19 00:18:24.071005	25.66186023178328	-100.420539801832	15.67
2687	1	2026-05-19 00:18:24.317354	25.66189912878962	-100.4205454042729	16.83
2688	1	2026-05-19 00:18:24.58524	25.66188841689815	-100.4204867864065	17.9
2689	1	2026-05-19 00:18:24.827031	25.66187774028163	-100.4204663468726	16.62
2690	1	2026-05-19 00:18:25.072362	25.66187806106133	-100.4204619456401	17.49
2691	1	2026-05-19 00:18:25.343768	25.66188148124848	-100.420466117148	20.81
2692	1	2026-05-19 00:18:25.615728	25.66189057718141	-100.4204555460197	23.17
2693	1	2026-05-19 00:18:25.87299	25.66190342592945	-100.420446965011	28.92
2694	1	2026-05-19 00:18:26.12267	25.66191782499753	-100.420440291009	38.17
2695	1	2026-05-19 00:18:26.368739	25.66191686123663	-100.4204281546249	42.74
2696	1	2026-05-19 00:18:26.623618	25.66181225238895	-100.4207229987722	51.35
2697	1	2026-05-19 00:18:26.873882	25.66187282165771	-100.4206611969937	17.11
2698	1	2026-05-19 00:18:27.1259	25.66186270068777	-100.4206536367035	16.98
2699	1	2026-05-19 00:18:27.376919	25.66186976668381	-100.4206324338483	21.46
2700	1	2026-05-19 00:18:27.624605	25.66185555257616	-100.4205631640768	28.06
2701	1	2026-05-19 00:18:27.870656	25.66183542944739	-100.420576232011	31.49
2702	1	2026-05-19 00:18:28.133122	25.66182375202909	-100.4205728520774	45.51
2703	1	2026-05-19 00:18:28.378064	25.66185856239495	-100.4206901417118	24.36
2704	1	2026-05-19 00:18:28.62126	25.66187264399226	-100.4206951708537	31.31
2705	1	2026-05-19 00:18:28.882572	25.6616700114831	-100.4209119268697	39.73
2706	1	2026-05-19 00:18:29.136056	25.66164293276456	-100.4209523303625	43.69
2707	1	2026-05-19 00:18:29.384097	25.66163013252701	-100.4210305810482	51.52
2708	1	2026-05-19 00:18:29.626234	25.66157716744591	-100.4211283636036	65.47
2709	1	2026-05-19 00:18:29.878604	25.66155939780728	-100.4211585384569	69.04
2710	1	2026-05-19 00:18:30.128544	25.66158821878216	-100.4207785133963	19.15
2711	1	2026-05-19 00:18:30.395414	25.6616641652633	-100.4207616370228	8.82
2712	1	2026-05-19 00:20:20.748797	25.66168516113619	-100.4207879857113	9.31
2713	1	2026-05-19 00:20:20.991595	25.66171410987285	-100.4208022914346	9.24
2714	1	2026-05-19 00:20:21.238966	25.66166070608384	-100.4208206709549	8.4
2715	1	2026-05-19 00:20:21.485599	25.66165504533674	-100.4208165929258	9.64
2716	1	2026-05-19 00:20:21.734349	25.66171193610671	-100.4207874511549	9.08
2717	1	2026-05-19 00:20:21.974801	25.66171788575923	-100.4208650802884	8.84
2718	1	2026-05-19 00:20:22.218474	25.66168733889334	-100.4208301660886	7.69
2719	1	2026-05-19 00:20:22.489418	25.66166778462886	-100.4207913930913	6.92
2720	1	2026-05-19 00:20:22.735779	25.66162469421403	-100.4208143253116	5.56
2721	1	2026-05-19 00:20:22.995521	25.6615732567481	-100.4208254707754	5.45
2722	1	2026-05-19 00:20:23.248186	25.66156226121252	-100.4208319791131	5.18
2723	1	2026-05-19 00:20:23.494493	25.66156703641334	-100.4208161274096	7.83
2724	1	2026-05-19 00:20:23.742994	25.66157459603572	-100.4208086204099	8.68
2725	1	2026-05-19 00:20:23.98893	25.66158013901028	-100.4207679017761	8.12
2726	1	2026-05-19 00:20:24.251218	25.66152175319655	-100.4207990165388	6.07
2727	1	2026-05-19 00:20:24.488406	25.66150730206357	-100.420795094863	5.67
2728	1	2026-05-19 00:20:24.737619	25.66153806069338	-100.4208370186154	5.82
2729	1	2026-05-19 00:20:24.987232	25.6615634061621	-100.4208017548254	6.15
2730	1	2026-05-19 00:20:25.230841	25.66158485425535	-100.4207869724519	6.19
2731	1	2026-05-19 00:20:25.473211	25.6615926192218	-100.4208053599814	5.64
2732	1	2026-05-19 00:20:25.715904	25.66158752158109	-100.4208152929226	5.47
2733	1	2026-05-19 00:20:25.964872	25.66160017720264	-100.4208036088506	5.34
2734	1	2026-05-19 00:20:26.211546	25.66161791162081	-100.4208284380211	6.03
2735	1	2026-05-19 00:20:26.462622	25.66160256510589	-100.4208582882369	5.8
2736	1	2026-05-19 00:20:26.743409	25.66158772811801	-100.4208660038157	5.63
2737	1	2026-05-19 00:20:27.005557	25.66159588216881	-100.4208624995391	6.07
2738	1	2026-05-19 00:20:27.255217	25.66161619913343	-100.4208251735164	5.8
2739	1	2026-05-19 00:20:27.50934	25.66162278918337	-100.4208235504421	6.11
2740	1	2026-05-19 00:20:27.764686	25.66163775473627	-100.4208206968991	6.56
2741	1	2026-05-19 00:20:28.019799	25.66162151745229	-100.4208204656931	7.15
2742	1	2026-05-19 00:20:28.276248	25.66159332051437	-100.4208144389952	7.71
2743	1	2026-05-19 00:20:28.525536	25.66161617515905	-100.4208074227678	8.01
2744	1	2026-05-19 00:20:28.768819	25.66160873032404	-100.4208056374508	8.11
2745	1	2026-05-19 00:20:29.016041	25.66161203281709	-100.4208159906933	8.23
2746	1	2026-05-19 00:20:29.260301	25.66159820915273	-100.42084756965	8.8
2747	1	2026-05-19 00:20:29.537294	25.66159204256876	-100.4208588349024	9.61
2748	1	2026-05-19 00:20:29.789015	25.66159204256876	-100.4208588349024	9.42
2749	1	2026-05-19 00:20:30.042975	25.66159204256876	-100.4208588349024	9.26
2750	1	2026-05-19 00:20:30.296486	25.66165461311811	-100.4208095131668	13.58
2751	1	2026-05-19 00:20:30.558166	25.66165943003944	-100.4208223410727	13.24
2752	1	2026-05-19 00:20:30.819106	25.66165175365058	-100.4208314175971	14.08
2753	1	2026-05-19 00:20:31.066098	25.66164935865084	-100.4208510462487	13.48
2754	1	2026-05-19 00:20:31.311005	25.66165153921587	-100.4208156948907	13.51
2755	1	2026-05-19 00:20:31.565872	25.66171568606258	-100.4208049994219	14.42
2756	1	2026-05-19 00:20:31.814425	25.66167034699555	-100.4208354150232	14.33
2757	1	2026-05-19 00:20:32.071029	25.66165683129218	-100.4208461733065	13.89
2758	1	2026-05-19 00:20:32.315934	25.66165867603921	-100.4208429727261	13.88
2759	1	2026-05-19 00:20:32.567368	25.66166971709456	-100.4208220383916	15.98
2760	1	2026-05-19 00:20:32.817272	25.66167249475087	-100.4208313832596	16.27
2761	1	2026-05-19 00:20:33.06461	25.66167354944169	-100.420839143218	15.89
2762	1	2026-05-19 00:20:33.342113	25.6616580829429	-100.420859505148	15.43
2763	1	2026-05-19 00:20:33.595492	25.6616580829429	-100.420859505148	15.47
2764	1	2026-05-19 00:20:33.846664	25.6616580829429	-100.420859505148	15.4
2765	1	2026-05-19 00:20:34.102717	25.6616580829429	-100.420859505148	15.23
2766	1	2026-05-19 00:20:34.359262	25.66164689680422	-100.4208404529408	14.64
2767	1	2026-05-19 00:20:34.629475	25.66164689680422	-100.4208404529408	17.37
2768	1	2026-05-19 00:20:34.876924	25.66163178043674	-100.4208405924904	16.78
2769	1	2026-05-19 00:20:35.132627	25.66163178043674	-100.4208405924904	16.53
2770	1	2026-05-19 00:20:35.386462	25.66163431305509	-100.4208391390346	16.05
2771	1	2026-05-19 00:23:20.52978	25.66163431305509	-100.4208391390346	15.89
2772	1	2026-05-19 00:23:20.770842	25.66163431305509	-100.4208391390346	15.4
2773	1	2026-05-19 00:23:21.029988	25.66163431305509	-100.4208391390346	16.33
2774	1	2026-05-19 00:23:21.289148	25.66165561689404	-100.4208486463845	16.11
2775	1	2026-05-19 00:23:21.539121	25.66166508795573	-100.4208452047306	15.54
2776	1	2026-05-19 00:23:21.791115	25.66166659400704	-100.4208030756183	15.09
2777	1	2026-05-19 00:23:22.044776	25.66165235503181	-100.42080720873	14.76
2778	1	2026-05-19 00:23:22.310918	25.66164627915511	-100.4207849041307	13.91
2779	1	2026-05-19 00:23:22.558506	25.66164692171438	-100.4207838715757	13.69
2780	1	2026-05-19 00:23:22.803055	25.66164691221944	-100.4207785882782	15.4
2781	1	2026-05-19 00:23:23.046327	25.66164691221944	-100.4207785882782	15.52
2782	1	2026-05-19 00:23:23.30027	25.66164691221944	-100.4207785882782	15.86
2783	1	2026-05-19 00:23:23.558427	25.66164691221944	-100.4207785882782	16.3
2784	1	2026-05-19 00:23:23.807029	25.66164691221944	-100.4207785882782	18.94
2785	1	2026-05-19 00:23:24.056729	25.66164691221944	-100.4207785882782	18.7
2786	1	2026-05-19 00:23:24.302718	25.66164691221944	-100.4207785882782	18.71
2787	1	2026-05-19 00:23:24.558183	25.66164691221944	-100.4207785882782	18.97
2788	1	2026-05-19 00:23:24.820583	25.66164788873285	-100.4207936686632	19.45
2789	1	2026-05-19 00:23:25.064476	25.66164709566286	-100.4207926757131	19.29
2790	1	2026-05-19 00:23:25.313251	25.66164709566286	-100.4207926757131	19.34
2791	1	2026-05-19 00:23:25.56104	25.66164709566286	-100.4207926757131	19.13
2792	1	2026-05-19 00:23:25.831347	25.66166015906138	-100.420780955685	22.04
2793	1	2026-05-19 00:23:26.096023	25.66169353392735	-100.4207791431809	22.39
2794	1	2026-05-19 00:23:26.359389	25.66167547146127	-100.4207780033991	20.39
2795	1	2026-05-19 00:23:26.657184	25.66166287333632	-100.4208005215492	20.97
2796	1	2026-05-19 00:23:26.927804	25.66166287333632	-100.4208005215492	20.74
2797	1	2026-05-19 00:23:27.197832	25.66166287333632	-100.4208005215492	20.97
2798	1	2026-05-19 00:23:27.475673	25.66166885987774	-100.4208008114277	20.64
2799	1	2026-05-19 00:23:27.749645	25.66166899531624	-100.4208005399877	21.83
2800	1	2026-05-19 00:23:28.003539	25.66166899531624	-100.4208005399877	22.1
2801	1	2026-05-19 00:23:28.338138	25.66166899531624	-100.4208005399877	22.16
2802	1	2026-05-19 00:23:28.601506	25.66166899531624	-100.4208005399877	21.43
2803	1	2026-05-19 00:23:28.874793	25.66166899531624	-100.4208005399877	21.23
2804	1	2026-05-19 00:23:29.143138	25.66166899531624	-100.4208005399877	19.95
2805	1	2026-05-19 00:23:29.404547	25.66166012917942	-100.4208305509796	20.24
2806	1	2026-05-19 00:23:29.659395	25.66165997668148	-100.4208304915255	19.55
2807	1	2026-05-19 00:23:29.912996	25.66165997668148	-100.4208304915255	19.81
2808	1	2026-05-19 00:23:30.154722	25.66165997668148	-100.4208304915255	18.86
2809	1	2026-05-19 00:23:30.403096	25.66165997668148	-100.4208304915255	18.61
2810	1	2026-05-19 00:23:30.653552	25.66165997668148	-100.4208304915255	16.17
2811	1	2026-05-19 00:23:30.88996	25.66165997668148	-100.4208304915255	16.28
2812	1	2026-05-19 00:23:31.13735	25.66165997668148	-100.4208304915255	15.97
2813	1	2026-05-19 00:23:31.396067	25.66165997668148	-100.4208304915255	15.55
2814	1	2026-05-19 00:23:31.637574	25.66165997668148	-100.4208304915255	14.99
2815	1	2026-05-19 00:23:31.888245	25.66165997668148	-100.4208304915255	16.17
2816	1	2026-05-19 00:23:32.132981	25.66165997668148	-100.4208304915255	15.92
2817	1	2026-05-19 00:23:32.386064	25.66170610320314	-100.4208501816926	15.42
2818	1	2026-05-19 00:23:32.629932	25.66170753656221	-100.4208488865531	15.31
2819	1	2026-05-19 00:23:32.885431	25.66170753656221	-100.4208488865531	15.0
2820	1	2026-05-19 00:23:33.129891	25.66170753656221	-100.4208488865531	15.34
2821	1	2026-05-19 00:25:20.571604	25.66170753656221	-100.4208488865531	15.24
2822	1	2026-05-19 00:25:20.83124	25.66163597380009	-100.4208438988925	13.9
2823	1	2026-05-19 00:25:21.096737	25.66163299464013	-100.4208427938219	14.71
2824	1	2026-05-19 00:25:21.354323	25.66161264793352	-100.4208290750455	15.39
2825	1	2026-05-19 00:25:21.612788	25.66160237554574	-100.4208046271859	16.69
2826	1	2026-05-19 00:25:21.90591	25.66160237554574	-100.4208046271859	16.16
2827	1	2026-05-19 00:25:22.152963	25.66160237554574	-100.4208046271859	15.93
2828	1	2026-05-19 00:25:22.400196	25.66162056851444	-100.4207772067456	16.78
2829	1	2026-05-19 00:25:22.655165	25.66162320569391	-100.4207804554898	17.3
2830	1	2026-05-19 00:25:22.898943	25.66161981933682	-100.4207922339898	16.48
2831	1	2026-05-19 00:25:23.153363	25.66163609853144	-100.4207921602545	16.37
2832	1	2026-05-19 00:25:23.409682	25.66163609853144	-100.4207921602545	15.4
2833	1	2026-05-19 00:25:23.666778	25.661622509576	-100.4208002646825	15.88
2834	1	2026-05-19 00:25:23.939227	25.66164975771849	-100.4207812857496	17.37
2835	1	2026-05-19 00:25:24.189461	25.6616508674882	-100.4207738754616	17.76
2836	1	2026-05-19 00:25:24.441682	25.66164377049987	-100.4207440988269	21.96
2837	1	2026-05-19 00:25:24.702633	25.66164489249671	-100.4207438480894	23.35
2838	1	2026-05-19 00:25:24.9563	25.66164489249671	-100.4207438480894	22.49
2839	1	2026-05-19 00:25:25.224715	25.66163363139517	-100.4207493096092	22.91
2840	1	2026-05-19 00:25:25.474606	25.66163517148745	-100.4207490550759	21.13
2841	1	2026-05-19 00:25:25.710135	25.66163517148745	-100.4207490550759	22.19
2842	1	2026-05-19 00:25:25.959818	25.66165556419671	-100.4207677798951	23.33
2843	1	2026-05-19 00:25:26.203524	25.66165430316439	-100.4207715057489	22.4
2844	1	2026-05-19 00:25:26.48665	25.66168811989083	-100.4207482604133	26.13
2845	1	2026-05-19 00:25:26.741625	25.6616872076529	-100.4207485246134	25.06
2846	1	2026-05-19 00:25:26.99107	25.66168695785647	-100.4207724744884	22.27
2847	1	2026-05-19 00:25:27.241895	25.66167736237625	-100.4207680251172	20.52
2848	1	2026-05-19 00:25:27.487885	25.66164868986508	-100.4207549124961	20.1
2849	1	2026-05-19 00:25:27.7551	25.66164551944057	-100.4207603323049	19.88
2850	1	2026-05-19 00:25:28.020629	25.6616485025141	-100.4207623693854	21.95
2851	1	2026-05-19 00:25:28.273205	25.66164823893931	-100.4207625421937	22.56
2852	1	2026-05-19 00:25:28.523827	25.66165235802142	-100.420770895765	23.87
2853	1	2026-05-19 00:25:28.770084	25.66165235802142	-100.420770895765	23.83
2854	1	2026-05-19 00:25:29.033427	25.66165235802142	-100.420770895765	27.14
2855	1	2026-05-19 00:25:29.280216	25.66165235802142	-100.420770895765	26.65
2856	1	2026-05-19 00:25:29.524302	25.66165235802142	-100.420770895765	25.85
2857	1	2026-05-19 00:25:29.763834	25.66164960309687	-100.4207934095688	25.6
2858	1	2026-05-19 00:25:30.01323	25.66164960309687	-100.4207934095688	25.15
2859	1	2026-05-19 00:25:30.265441	25.66164960309687	-100.4207934095688	24.87
2860	1	2026-05-19 00:25:30.516795	25.66164013333232	-100.420783743152	24.7
2861	1	2026-05-19 00:25:30.765921	25.66163832082632	-100.4207891598255	24.36
2862	1	2026-05-19 00:25:31.021241	25.66163832082632	-100.4207891598255	24.6
2863	1	2026-05-19 00:25:31.25708	25.66163832082632	-100.4207891598255	24.68
2864	1	2026-05-19 00:25:31.491772	25.66163832082632	-100.4207891598255	23.86
2865	1	2026-05-19 00:25:31.750307	25.66163832082632	-100.4207891598255	22.72
2866	1	2026-05-19 00:25:32.002142	25.66163832082632	-100.4207891598255	23.71
2867	1	2026-05-19 00:25:32.256256	25.66163832082632	-100.4207891598255	23.18
2868	1	2026-05-19 00:25:32.566475	25.66163832082632	-100.4207891598255	23.42
2869	1	2026-05-19 00:25:32.825555	25.66163832082632	-100.4207891598255	25.31
2870	1	2026-05-19 00:25:33.069788	25.66163832082632	-100.4207891598255	24.76
2871	1	2026-05-19 00:25:33.310085	25.66163832082632	-100.4207891598255	24.93
2872	1	2026-05-19 00:25:33.564097	25.66163832082632	-100.4207891598255	25.62
2873	1	2026-05-19 00:59:19.161859	25.66163832082632	-100.4207891598255	25.64
2874	1	2026-05-19 00:59:19.430372	25.66163832082632	-100.4207891598255	26.05
2875	1	2026-05-19 00:59:19.684222	25.66163832082632	-100.4207891598255	25.28
2876	1	2026-05-19 00:59:19.938596	25.66163832082632	-100.4207891598255	25.2
2877	1	2026-05-19 00:59:20.177512	25.66163832082632	-100.4207891598255	25.34
2878	1	2026-05-19 00:59:20.443171	25.66163832082632	-100.4207891598255	26.32
2879	1	2026-05-19 00:59:20.689311	25.66163832082632	-100.4207891598255	26.19
2880	1	2026-05-19 00:59:20.942399	25.66163832082632	-100.4207891598255	25.73
2881	1	2026-05-19 00:59:21.198255	25.66163832082632	-100.4207891598255	25.53
2882	1	2026-05-19 00:59:21.453141	25.66163832082632	-100.4207891598255	24.74
2883	1	2026-05-19 00:59:21.712854	25.66163832082632	-100.4207891598255	24.5
2884	1	2026-05-19 00:59:21.974077	25.66163832082632	-100.4207891598255	25.06
2885	1	2026-05-19 00:59:22.22605	25.66163832082632	-100.4207891598255	25.76
2886	1	2026-05-19 00:59:22.470958	25.66163832082632	-100.4207891598255	26.07
2887	1	2026-05-19 00:59:22.712731	25.66170946905849	-100.4207533307663	26.66
2888	1	2026-05-19 00:59:22.956169	25.66170891645857	-100.4207548592371	23.13
2889	1	2026-05-19 00:59:23.204788	25.66170891645857	-100.4207548592371	23.52
2890	1	2026-05-19 00:59:23.450994	25.66170891645857	-100.4207548592371	23.08
2891	1	2026-05-19 00:59:23.697959	25.66170891645857	-100.4207548592371	21.87
2892	1	2026-05-19 00:59:23.946891	25.66170891645857	-100.4207548592371	22.69
2893	1	2026-05-19 00:59:24.227783	25.66170891645857	-100.4207548592371	22.98
2894	1	2026-05-19 00:59:24.679366	25.66170891645857	-100.4207548592371	22.72
2895	1	2026-05-19 00:59:24.939045	25.66170891645857	-100.4207548592371	22.37
2896	1	2026-05-19 00:59:25.210918	25.66170891645857	-100.4207548592371	22.29
2897	1	2026-05-19 00:59:25.46064	25.66170891645857	-100.4207548592371	22.89
2898	1	2026-05-19 00:59:25.893054	25.66170891645857	-100.4207548592371	22.66
2899	1	2026-05-19 00:59:26.142763	25.66170891645857	-100.4207548592371	22.65
2900	1	2026-05-19 00:59:26.384396	25.66170891645857	-100.4207548592371	24.2
2901	1	2026-05-19 00:59:26.606039	25.66170891645857	-100.4207548592371	24.21
2902	1	2026-05-19 00:59:26.858061	25.66170891645857	-100.4207548592371	23.65
2903	1	2026-05-19 00:59:27.100791	25.66170891645857	-100.4207548592371	23.6
2904	1	2026-05-19 00:59:27.350467	25.66170891645857	-100.4207548592371	22.71
2905	1	2026-05-19 00:59:27.607441	25.66170891645857	-100.4207548592371	25.04
2906	1	2026-05-19 00:59:27.857657	25.66167630608723	-100.4207892654231	26.46
2907	1	2026-05-19 00:59:28.113996	25.66165781541848	-100.4207933239289	25.62
2908	1	2026-05-19 00:59:28.361381	25.66162313641659	-100.4208051820152	25.31
2909	1	2026-05-19 00:59:28.600738	25.66159850843625	-100.4207927176264	25.05
2910	1	2026-05-19 00:59:28.841952	25.66164514841713	-100.4207684139504	23.29
2911	1	2026-05-19 00:59:29.096653	25.66164915634892	-100.4207582989793	23.44
2912	1	2026-05-19 00:59:29.347871	25.66164899974981	-100.4207546570503	23.36
2913	1	2026-05-19 00:59:29.594774	25.66165134307849	-100.4207473349682	22.89
2914	1	2026-05-19 00:59:29.845817	25.66165496395838	-100.4207477017466	22.31
2915	1	2026-05-19 00:59:30.086611	25.66166282750197	-100.420739734454	21.62
2916	1	2026-05-19 00:59:30.338781	25.66165563704786	-100.4207449032267	21.55
2917	1	2026-05-19 00:59:30.58526	25.66165501312413	-100.4207430827616	20.84
2918	1	2026-05-19 00:59:30.828273	25.66165501312413	-100.4207430827616	22.1
2919	1	2026-05-19 00:59:31.081228	25.66166913287103	-100.4207553002629	22.31
2920	1	2026-05-19 00:59:31.31671	25.66166913287103	-100.4207553002629	23.3
2921	1	2026-05-19 00:59:31.575828	25.66167797005415	-100.4207677938583	23.22
2922	1	2026-05-19 00:59:31.847602	25.66167882089992	-100.4207617445774	23.53
2923	1	2026-05-19 00:59:32.095035	25.66167395260945	-100.4207750293344	23.97
2924	1	2026-05-19 00:59:32.337641	25.66167395260945	-100.4207750293344	23.46
2925	1	2026-05-19 00:59:32.578229	25.6616694252772	-100.4207789062645	23.7
2926	1	2026-05-19 00:59:32.818901	25.6616694252772	-100.4207789062645	24.15
2927	1	2026-05-19 00:59:33.062561	25.6616694252772	-100.4207789062645	23.59
2928	1	2026-05-19 00:59:33.309632	25.6616685110194	-100.4207656218763	23.62
2929	1	2026-05-19 00:59:33.546922	25.66166689345795	-100.4207668756067	24.13
2930	1	2026-05-19 00:59:33.796799	25.66166450089564	-100.4207694392654	23.79
2931	1	2026-05-19 00:59:34.079094	25.66166450089564	-100.4207694392654	23.15
2932	1	2026-05-19 00:59:34.318644	25.66166450089564	-100.4207694392654	21.43
2933	1	2026-05-19 00:59:34.560369	25.66166858040779	-100.4207755161459	20.91
2934	1	2026-05-19 00:59:34.815668	25.66164277881004	-100.4207584887191	21.02
2935	1	2026-05-19 00:59:35.052871	25.66163216290242	-100.4207462106148	20.2
2936	1	2026-05-19 00:59:35.295554	25.66165226838612	-100.4207381760925	19.49
2937	1	2026-05-19 00:59:35.56685	25.66162253089202	-100.4207377744912	20.23
2938	1	2026-05-19 00:59:35.812283	25.66166483739662	-100.4207533277208	19.67
2939	1	2026-05-19 00:59:36.136898	25.66166231397856	-100.4207554118817	19.01
2940	1	2026-05-19 00:59:36.387142	25.66166095143377	-100.4207516156415	20.01
2941	1	2026-05-19 00:59:36.624314	25.66165987553438	-100.420751536153	19.3
2942	1	2026-05-19 00:59:36.959329	25.66164578464773	-100.4207482510956	19.38
2943	1	2026-05-19 00:59:37.221045	25.661645503095	-100.4207479944592	19.54
2944	1	2026-05-19 00:59:37.481187	25.661645503095	-100.4207479944592	19.45
2945	1	2026-05-19 00:59:37.729798	25.661645503095	-100.4207479944592	17.78
2946	1	2026-05-19 00:59:37.959453	25.66165768958803	-100.4207528039599	17.39
2947	1	2026-05-19 00:59:38.241365	25.66166204380371	-100.4207564609449	16.71
2948	1	2026-05-19 00:59:38.553631	25.66166506078759	-100.4207647610436	16.59
2949	1	2026-05-19 00:59:38.807572	25.66166506078759	-100.4207647610436	16.0
2950	1	2026-05-19 00:59:39.217432	25.66166157974459	-100.4207614550106	15.37
2951	1	2026-05-19 00:59:39.464406	25.66165657597029	-100.4207619839563	16.13
2952	1	2026-05-19 00:59:39.70012	25.66165890351495	-100.4207746865323	15.62
2953	1	2026-05-19 00:59:39.937373	25.66165763743164	-100.4207746112076	15.87
2954	1	2026-05-19 00:59:40.175185	25.66165786806958	-100.4207764825577	16.01
2955	1	2026-05-19 00:59:40.440819	25.66165327993896	-100.4207771422489	15.55
2956	1	2026-05-19 00:59:40.686312	25.66165943300825	-100.4207748962445	16.73
2957	1	2026-05-19 00:59:40.934161	25.66165675192697	-100.420763946441	17.79
2958	1	2026-05-19 00:59:41.17617	25.66165636820013	-100.4207550317184	17.42
2959	1	2026-05-19 00:59:41.431366	25.66168581821944	-100.4207573126024	16.18
2960	1	2026-05-19 00:59:41.677725	25.66173205146402	-100.4208454940487	16.24
2961	1	2026-05-19 00:59:41.92453	25.66176124422781	-100.4208380486309	17.67
2962	1	2026-05-19 00:59:42.165504	25.66175052788583	-100.420828508539	17.89
2963	1	2026-05-19 00:59:42.406721	25.66174411377247	-100.4208405864503	18.22
2964	1	2026-05-19 00:59:42.654157	25.66177319901626	-100.4208447652548	17.02
2965	1	2026-05-19 00:59:42.907083	25.66175184732204	-100.4208359503868	17.69
2966	1	2026-05-19 00:59:43.188909	25.66174332832566	-100.420850093355	18.73
2967	1	2026-05-19 00:59:43.427364	25.66174332832566	-100.420850093355	18.68
2968	1	2026-05-19 00:59:43.676298	25.66172493511026	-100.4208785056929	21.95
2969	1	2026-05-19 00:59:43.927252	25.66171983235106	-100.4208891112238	22.09
2970	1	2026-05-19 00:59:44.192376	25.66171544959646	-100.4208657367126	20.91
2971	1	2026-05-19 00:59:44.439182	25.66173806376172	-100.4208747991753	20.81
2972	1	2026-05-19 01:02:20.538515	25.66172726007165	-100.4208816456944	20.51
2973	1	2026-05-19 01:02:20.811695	25.66172726007165	-100.4208816456944	20.61
2974	1	2026-05-19 01:02:21.063471	25.66172726007165	-100.4208816456944	20.25
2975	1	2026-05-19 01:02:21.320985	25.66168303792981	-100.4208513130879	19.23
2976	1	2026-05-19 01:02:21.762347	25.66167762612805	-100.4208512988395	19.46
2977	1	2026-05-19 01:02:22.098016	25.66167759549958	-100.4208512662749	18.96
2978	1	2026-05-19 01:02:22.550305	25.66166771836319	-100.4208574612239	18.9
2979	1	2026-05-19 01:02:22.801438	25.66165208631649	-100.4208570030732	18.7
2980	1	2026-05-19 01:02:23.058923	25.66163276959259	-100.4208614075107	18.65
2981	1	2026-05-19 01:02:23.39109	25.66164412308642	-100.420851807462	18.09
2982	1	2026-05-19 01:02:23.643096	25.66165035422916	-100.4208668305814	20.34
2983	1	2026-05-19 01:02:23.903234	25.661627228719	-100.4208745829514	20.34
2984	1	2026-05-19 01:02:24.165874	25.66163161356141	-100.4208749974861	19.32
2985	1	2026-05-19 01:02:24.433631	25.66159200693252	-100.4208477275396	20.21
2986	1	2026-05-19 01:02:24.677407	25.66159200693252	-100.4208477275396	20.5
2987	1	2026-05-19 01:02:24.923266	25.66159200693252	-100.4208477275396	20.54
2988	1	2026-05-19 01:02:25.181686	25.66159200693252	-100.4208477275396	20.61
2989	1	2026-05-19 01:02:25.433219	25.66152588026537	-100.4208285130783	19.96
2990	1	2026-05-19 01:02:25.692111	25.66151646593492	-100.4208373537621	18.25
2991	1	2026-05-19 01:02:25.941	25.66149243436016	-100.4208436727062	19.06
2992	1	2026-05-19 01:03:20.614686	25.66149305044938	-100.4208477971076	19.59
2993	1	2026-05-19 01:03:21.047814	25.6615030052014	-100.420869736882	23.67
2994	1	2026-05-19 01:03:21.304948	25.6615030052014	-100.420869736882	23.67
2995	1	2026-05-19 01:03:21.556908	25.6615030052014	-100.420869736882	23.2
2996	1	2026-05-19 01:03:21.787707	25.6615030052014	-100.420869736882	22.9
2997	1	2026-05-19 01:03:21.998305	25.6615087245301	-100.4208367548407	22.14
2998	1	2026-05-19 01:03:22.238035	25.6615087245301	-100.4208367548407	21.37
2999	1	2026-05-19 01:03:22.497664	25.6615087245301	-100.4208367548407	21.73
3000	1	2026-05-19 01:03:22.754299	25.66144664682763	-100.4208031611559	19.97
3001	1	2026-05-19 01:03:23.006166	25.66144629791047	-100.4208031127018	19.84
3002	1	2026-05-19 01:03:23.460028	25.66144629791047	-100.4208031127018	19.36
3003	1	2026-05-19 01:03:23.711023	25.66144629791047	-100.4208031127018	19.09
3004	1	2026-05-19 01:03:23.957573	25.66144629791047	-100.4208031127018	18.79
3005	1	2026-05-19 01:03:24.200489	25.66144629791047	-100.4208031127018	20.14
3006	1	2026-05-19 01:03:24.467201	25.66144629791047	-100.4208031127018	19.36
3007	1	2026-05-19 01:03:24.728033	25.66144629791047	-100.4208031127018	19.33
3008	1	2026-05-19 01:03:24.978023	25.66144629791047	-100.4208031127018	19.13
3009	1	2026-05-19 01:03:25.23843	25.66144629791047	-100.4208031127018	18.72
3010	1	2026-05-19 01:04:20.5331	25.66144629791047	-100.4208031127018	18.87
3011	1	2026-05-19 01:04:20.8022	25.66144629791047	-100.4208031127018	19.66
3012	1	2026-05-19 01:04:21.052218	25.66148912476913	-100.4208279646136	18.79
3013	1	2026-05-19 01:04:21.300343	25.66148912476913	-100.4208279646136	18.31
3014	1	2026-05-19 01:04:21.578218	25.66148912476913	-100.4208279646136	17.11
3015	1	2026-05-19 01:04:21.848487	25.66148912476913	-100.4208279646136	18.05
3016	1	2026-05-19 01:04:22.106845	25.66148912476913	-100.4208279646136	26.52
3017	1	2026-05-19 01:04:22.443877	25.66152254748991	-100.4208334171741	26.07
3018	1	2026-05-19 01:04:22.700922	25.66152249854595	-100.4208334004506	25.6
3019	1	2026-05-19 01:04:22.954128	25.66153350854218	-100.4208367971354	28.78
3020	1	2026-05-19 01:04:23.239278	25.6615364789269	-100.4208299337605	28.96
3021	1	2026-05-19 01:04:23.808168	25.6615431314099	-100.4208368670127	30.78
3022	1	2026-05-19 01:04:24.060256	25.66153596504232	-100.4208461282917	29.11
3023	1	2026-05-19 01:04:24.301648	25.66153758885744	-100.4208488814808	28.4
3024	1	2026-05-19 01:04:24.542628	25.66153758885744	-100.4208488814808	29.36
3025	1	2026-05-19 01:04:24.806203	25.66153758885744	-100.4208488814808	29.65
3026	1	2026-05-19 01:04:25.070351	25.66153758885744	-100.4208488814808	27.06
3027	1	2026-05-19 01:04:25.335029	25.66153758885744	-100.4208488814808	25.09
3028	1	2026-05-19 01:04:25.588365	25.66153758885744	-100.4208488814808	24.12
3029	1	2026-05-19 01:04:25.848434	25.66153758885744	-100.4208488814808	23.48
3030	1	2026-05-19 01:04:26.100524	25.66153758885744	-100.4208488814808	22.76
3031	1	2026-05-19 01:04:26.354759	25.66153758885744	-100.4208488814808	21.73
3032	1	2026-05-19 01:04:26.604014	25.66153758885744	-100.4208488814808	21.19
3033	1	2026-05-19 01:04:26.882902	25.66158545255494	-100.4208327782872	21.3
3034	1	2026-05-19 01:04:27.145778	25.66158545255494	-100.4208327782872	24.04
3035	1	2026-05-19 01:04:27.403609	25.66158545255494	-100.4208327782872	23.53
3036	1	2026-05-19 01:04:27.669226	25.66160385631071	-100.4208231982432	23.96
3037	1	2026-05-19 01:04:27.922388	25.66160381579688	-100.4208264955428	23.16
3038	1	2026-05-19 01:04:28.365293	25.66160381579688	-100.4208264955428	24.62
3039	1	2026-05-19 01:04:28.642849	25.66160381579688	-100.4208264955428	24.0
3040	1	2026-05-19 01:04:28.955898	25.6616166090715	-100.4208380821183	24.7
3041	1	2026-05-19 01:04:29.21872	25.66161551051492	-100.4208379295613	24.03
3042	1	2026-05-19 01:04:29.466293	25.66161551051492	-100.4208379295613	24.6
3043	1	2026-05-19 01:04:29.715772	25.66161551051492	-100.4208379295613	23.72
3044	1	2026-05-19 01:04:29.984907	25.66161551051492	-100.4208379295613	23.92
3045	1	2026-05-19 01:04:30.29389	25.66161551051492	-100.4208379295613	23.87
3046	1	2026-05-19 01:04:30.557187	25.66161551051492	-100.4208379295613	23.47
3047	1	2026-05-19 01:04:30.806327	25.66161551051492	-100.4208379295613	22.78
3048	1	2026-05-19 01:04:31.061676	25.66161551051492	-100.4208379295613	22.52
3049	1	2026-05-19 01:04:31.344348	25.66161551051492	-100.4208379295613	22.03
3050	1	2026-05-19 01:04:31.597038	25.66161551051492	-100.4208379295613	22.42
3051	1	2026-05-19 01:04:31.844497	25.66161551051492	-100.4208379295613	22.7
3052	1	2026-05-19 01:04:32.09757	25.66161551051492	-100.4208379295613	23.61
3053	1	2026-05-19 01:04:32.352774	25.66161551051492	-100.4208379295613	22.84
3054	1	2026-05-19 01:04:32.620716	25.66161551051492	-100.4208379295613	22.3
3055	1	2026-05-19 01:04:32.879827	25.66161551051492	-100.4208379295613	23.36
3056	1	2026-05-19 01:04:33.132609	25.66161551051492	-100.4208379295613	23.63
3057	1	2026-05-19 01:04:33.393524	25.66161551051492	-100.4208379295613	22.92
3058	1	2026-05-19 01:04:33.645794	25.66161551051492	-100.4208379295613	22.17
3059	1	2026-05-19 01:04:33.930637	25.66161551051492	-100.4208379295613	20.46
3060	1	2026-05-19 01:04:34.195042	25.66161551051492	-100.4208379295613	20.48
3061	1	2026-05-19 01:04:34.445043	25.66161551051492	-100.4208379295613	19.94
3062	1	2026-05-19 01:04:34.708349	25.66161551051492	-100.4208379295613	21.24
3063	1	2026-05-19 01:04:34.9661	25.66161551051492	-100.4208379295613	21.08
3064	1	2026-05-19 01:04:35.218614	25.66161551051492	-100.4208379295613	19.89
3065	1	2026-05-19 01:04:35.466068	25.661678470391	-100.4208961981949	19.38
3066	1	2026-05-19 01:04:35.724418	25.66165703056942	-100.4208787949895	19.88
3067	1	2026-05-19 01:04:35.977093	25.66165038886688	-100.4208801175298	21.24
3068	1	2026-05-19 01:04:36.471338	25.66162756991153	-100.4208711048497	20.06
3069	1	2026-05-19 01:04:36.735454	25.66161320353979	-100.4208447152215	18.63
3070	1	2026-05-19 01:04:36.997951	25.66161320353979	-100.4208447152215	18.54
3071	1	2026-05-19 01:04:37.26893	25.66161320353979	-100.4208447152215	18.23
3072	1	2026-05-19 01:04:37.526019	25.66161320353979	-100.4208447152215	18.11
3073	1	2026-05-19 01:06:20.564543	25.66161320353979	-100.4208447152215	18.13
3074	1	2026-05-19 01:06:20.818429	25.66161320353979	-100.4208447152215	18.07
3075	1	2026-05-19 01:06:21.075999	25.66161320353979	-100.4208447152215	17.9
3076	1	2026-05-19 01:07:20.500422	25.66161320353979	-100.4208447152215	17.98
3077	1	2026-05-19 01:07:20.753807	25.66161320353979	-100.4208447152215	17.67
3078	1	2026-05-19 01:07:21.013451	25.66161320353979	-100.4208447152215	17.31
3079	1	2026-05-19 01:07:21.258794	25.66161320353979	-100.4208447152215	16.78
3080	1	2026-05-19 01:07:21.517313	25.66161320353979	-100.4208447152215	16.53
3081	1	2026-05-19 01:07:21.772288	25.66161320353979	-100.4208447152215	16.43
3082	1	2026-05-19 01:07:22.022205	25.66161320353979	-100.4208447152215	16.16
3083	1	2026-05-19 01:07:22.278047	25.66161320353979	-100.4208447152215	15.63
3084	1	2026-05-19 01:07:22.535676	25.66162779497221	-100.4208022584372	15.29
3085	1	2026-05-19 01:07:22.78215	25.66163061388438	-100.4208040839892	15.16
3086	1	2026-05-19 01:07:23.043859	25.66164004241703	-100.4207976387015	14.84
3087	1	2026-05-19 01:07:23.305186	25.66163212333421	-100.4208218211699	14.46
3088	1	2026-05-19 01:07:23.569527	25.66162917127625	-100.4208169620179	14.7
3089	1	2026-05-19 01:07:23.827318	25.66166922944456	-100.4207885167252	13.92
3090	1	2026-05-19 01:07:24.083868	25.66164136387013	-100.4208271070627	13.62
3091	1	2026-05-19 01:07:24.339331	25.66164151549904	-100.4208281410283	13.43
3092	1	2026-05-19 01:07:24.595023	25.66164397253058	-100.4208274424189	13.25
3093	1	2026-05-19 01:07:24.848492	25.66163797246037	-100.4208331371638	13.64
3094	1	2026-05-19 01:07:25.11007	25.66165403197208	-100.4208550965503	13.54
3095	1	2026-05-19 01:07:25.374253	25.66165881192254	-100.4208339219817	13.12
3096	1	2026-05-19 01:07:25.627714	25.66164594995801	-100.4208326838076	13.12
3097	1	2026-05-19 01:07:25.880266	25.66164195113404	-100.4208207419399	13.16
3098	1	2026-05-19 01:07:26.133593	25.66162888861271	-100.4208296012426	13.4
3099	1	2026-05-19 01:07:26.383388	25.66163212108595	-100.4208252789059	13.55
3100	1	2026-05-19 01:07:26.73105	25.66164364312413	-100.4208261921906	13.98
3101	1	2026-05-19 01:07:26.995839	25.66164364312413	-100.4208261921906	13.99
3102	1	2026-05-19 01:07:27.281484	25.66164364312413	-100.4208261921906	14.04
3103	1	2026-05-19 01:07:27.5362	25.66164382875271	-100.4208170347715	14.24
3104	1	2026-05-19 01:07:27.790257	25.66164347435608	-100.4208162009868	14.23
3105	1	2026-05-19 01:07:28.046632	25.66164347435608	-100.4208162009868	14.08
3106	1	2026-05-19 01:07:28.303122	25.66164347435608	-100.4208162009868	14.02
3107	1	2026-05-19 01:07:28.793975	25.66164347435608	-100.4208162009868	13.92
3108	1	2026-05-19 01:07:29.047926	25.66165715889898	-100.4208298200986	14.08
3109	1	2026-05-19 01:07:29.302069	25.66167180906291	-100.4208294799325	14.19
3110	1	2026-05-19 01:07:29.563797	25.66167937574949	-100.420824859811	13.89
3111	1	2026-05-19 01:07:29.818798	25.66167908831656	-100.4208237336596	13.77
3112	1	2026-05-19 01:07:30.090241	25.66167908831656	-100.4208237336596	13.5
3113	1	2026-05-19 01:07:30.349627	25.66167908831656	-100.4208237336596	13.3
3114	1	2026-05-19 01:09:20.633503	25.66166252404602	-100.4208214319499	13.3
3115	1	2026-05-19 01:09:20.88999	25.66167090378441	-100.4208245338095	13.44
3116	1	2026-05-19 01:09:21.141068	25.66167090378441	-100.4208245338095	13.4
3117	1	2026-05-19 01:09:21.407434	25.66167090378441	-100.4208245338095	14.88
3118	1	2026-05-19 01:09:21.667133	25.66167090378441	-100.4208245338095	16.24
3119	1	2026-05-19 01:09:21.927633	25.66167090378441	-100.4208245338095	16.96
3120	1	2026-05-19 01:09:22.189636	25.66167090378441	-100.4208245338095	17.07
3121	1	2026-05-19 01:09:22.456642	25.6616382466595	-100.4208009269137	17.9
3122	1	2026-05-19 01:09:22.705298	25.66162248695081	-100.4208153909952	19.34
3123	1	2026-05-19 01:09:22.950112	25.66160076236331	-100.4208089027366	18.99
3124	1	2026-05-19 01:09:23.21393	25.66163668040954	-100.4207811589284	18.11
3125	1	2026-05-19 01:09:23.482703	25.661672629311	-100.4207537823322	17.76
3126	1	2026-05-19 01:09:23.732068	25.66167902649927	-100.4207652035132	18.63
3127	1	2026-05-19 01:09:23.987095	25.66165777449517	-100.4207692871965	19.23
3128	1	2026-05-19 01:09:24.24427	25.66165777449517	-100.4207692871965	20.55
3129	1	2026-05-19 01:09:24.500217	25.66172965220458	-100.4206231786865	14.73
3130	1	2026-05-19 01:09:24.755831	25.66173958361587	-100.4205841430736	13.89
3131	1	2026-05-19 01:09:25.017821	25.66176022723225	-100.4205385145628	14.66
3132	1	2026-05-19 01:09:25.269657	25.66175417058648	-100.4205430220511	15.67
3133	1	2026-05-19 01:09:25.525799	25.66175417058648	-100.4205430220511	16.15
3134	1	2026-05-19 01:09:25.781335	25.66175417058648	-100.4205430220511	15.85
3135	1	2026-05-19 01:09:26.036425	25.66175417058648	-100.4205430220511	15.88
3136	1	2026-05-19 01:09:26.292898	25.66175417058648	-100.4205430220511	18.18
3137	1	2026-05-19 01:09:26.543549	25.66175417058648	-100.4205430220511	18.45
3138	1	2026-05-19 01:09:26.796469	25.66175417058648	-100.4205430220511	18.97
3139	1	2026-05-19 01:09:27.055127	25.66175417058648	-100.4205430220511	19.21
3140	1	2026-05-19 01:09:27.313001	25.66175417058648	-100.4205430220511	19.06
3141	1	2026-05-19 01:09:27.57424	25.66175417058648	-100.4205430220511	18.28
3142	1	2026-05-19 01:09:27.835834	25.66175417058648	-100.4205430220511	18.59
3143	1	2026-05-19 01:09:28.085874	25.66175417058648	-100.4205430220511	20.63
3144	1	2026-05-19 01:09:28.334057	25.66175417058648	-100.4205430220511	24.29
3145	1	2026-05-19 01:09:28.592954	25.66175417058648	-100.4205430220511	24.18
3146	1	2026-05-19 01:09:28.849514	25.66175417058648	-100.4205430220511	24.12
3147	1	2026-05-19 01:09:29.114115	25.66175417058648	-100.4205430220511	24.93
3148	1	2026-05-19 01:09:29.371046	25.66167670306051	-100.4206580367436	12.4
3149	1	2026-05-19 01:09:29.703819	25.66166738895387	-100.4206544928135	28.37
3150	1	2026-05-19 01:09:29.956314	25.66166277231563	-100.4206714428492	28.58
3151	1	2026-05-19 01:09:30.22238	25.66164747412301	-100.4206802942423	26.68
3152	1	2026-05-19 01:09:30.471537	25.66164747412301	-100.4206802942423	22.69
3153	1	2026-05-19 01:09:30.726376	25.66164747412301	-100.4206802942423	22.09
3154	1	2026-05-19 01:09:30.99556	25.66164747412301	-100.4206802942423	22.39
3155	1	2026-05-19 01:09:31.256144	25.66158059031563	-100.4207093424719	22.89
3156	1	2026-05-19 01:09:31.513195	25.66156456066809	-100.420702523632	22.03
3157	1	2026-05-19 01:09:31.763818	25.66156022630205	-100.4206993709749	24.85
3158	1	2026-05-19 01:09:32.038834	25.66157173851709	-100.4206723953377	23.03
3159	1	2026-05-19 01:09:32.313502	25.66156265866108	-100.4206632815214	20.91
3160	1	2026-05-19 01:09:32.565272	25.66155714753743	-100.4206521311694	20.05
3161	1	2026-05-19 01:09:32.829733	25.6615522418916	-100.4206516979119	18.74
3162	1	2026-05-19 01:09:33.076616	25.66154654246925	-100.4206508097526	17.78
3163	1	2026-05-19 01:09:33.335639	25.66154652000017	-100.4206508298092	16.68
3164	1	2026-05-19 01:09:33.595455	25.66156878584543	-100.420654323462	15.09
3165	1	2026-05-19 01:09:33.847879	25.66156878584543	-100.420654323462	14.72
3166	1	2026-05-19 01:09:34.112191	25.66156878584543	-100.420654323462	14.24
3167	1	2026-05-19 01:09:34.375456	25.66156878584543	-100.420654323462	13.76
3168	1	2026-05-19 01:09:34.627624	25.66156878584543	-100.420654323462	14.32
3169	1	2026-05-19 01:09:34.884212	25.66157201163277	-100.4206859550396	13.85
3170	1	2026-05-19 01:09:35.137066	25.66157201163277	-100.4206859550396	13.6
3171	1	2026-05-19 01:09:35.385316	25.66157236915223	-100.4206744946146	13.34
3172	1	2026-05-19 01:11:20.659116	25.66157548343295	-100.4206619900951	13.16
3173	1	2026-05-19 01:11:20.919064	25.66156862416924	-100.4206681633163	13.01
3174	1	2026-05-19 01:11:21.182718	25.66156872283925	-100.4206681757747	13.56
3175	1	2026-05-19 01:11:21.46183	25.66156872283925	-100.4206681757747	14.55
3176	1	2026-05-19 01:11:21.790646	25.66158194138153	-100.4206758819816	16.22
3177	1	2026-05-19 01:11:22.080172	25.66159033158569	-100.4206819096396	16.36
3178	1	2026-05-19 01:11:22.536232	25.66157727220723	-100.4206842843184	15.73
3179	1	2026-05-19 01:11:22.834016	25.66157347232048	-100.4206763415729	16.39
3180	1	2026-05-19 01:11:23.095644	25.66157296193408	-100.4206767971606	17.28
3181	1	2026-05-19 01:11:23.338019	25.66156615138069	-100.4206827306398	16.99
3182	1	2026-05-19 01:11:23.597707	25.66156614816694	-100.4206829231697	16.69
3183	1	2026-05-19 01:11:23.91833	25.66156614816694	-100.4206829231697	15.37
3184	1	2026-05-19 01:11:24.166898	25.66156614816694	-100.4206829231697	15.23
3185	1	2026-05-19 01:11:24.403686	25.66156614816694	-100.4206829231697	14.79
3186	1	2026-05-19 01:11:24.657134	25.66156614816694	-100.4206829231697	14.55
3187	1	2026-05-19 01:11:24.928536	25.66156514531299	-100.42070615466	16.08
3188	1	2026-05-19 01:11:25.174442	25.66156014474933	-100.4207048254904	15.99
3189	1	2026-05-19 01:11:25.440842	25.66155519935085	-100.4206957361294	17.58
3190	1	2026-05-19 01:11:25.68569	25.66155453458076	-100.4206916388554	17.9
3191	1	2026-05-19 01:11:26.038346	25.66155422157739	-100.4206832352549	17.49
3192	1	2026-05-19 01:11:26.329228	25.66152815442167	-100.4206802968324	18.26
3193	1	2026-05-19 01:11:26.596096	25.66154000352505	-100.4206884023053	17.85
3194	1	2026-05-19 01:11:26.887677	25.66152725662189	-100.4207263589985	17.48
3195	1	2026-05-19 01:11:27.155505	25.66159293509492	-100.4207396356343	16.96
3196	1	2026-05-19 01:11:27.45289	25.66159178576452	-100.4207395293402	16.8
3197	1	2026-05-19 01:11:27.81078	25.66162475747057	-100.4207464536852	17.3
3198	1	2026-05-19 01:11:28.08368	25.66162475747057	-100.4207464536852	17.07
3199	1	2026-05-19 01:11:28.361107	25.66162475747057	-100.4207464536852	16.38
3200	1	2026-05-19 01:11:28.656663	25.66162475747057	-100.4207464536852	16.95
3201	1	2026-05-19 01:11:28.921151	25.66162475747057	-100.4207464536852	16.65
3202	1	2026-05-19 01:11:29.201561	25.66162475747057	-100.4207464536852	16.31
3203	1	2026-05-19 01:11:29.461868	25.66162475747057	-100.4207464536852	15.85
3204	1	2026-05-19 01:11:29.71596	25.66162475747057	-100.4207464536852	15.59
3205	1	2026-05-19 01:11:29.958786	25.66162475747057	-100.4207464536852	15.08
3206	1	2026-05-19 01:11:30.219236	25.66162475747057	-100.4207464536852	14.81
3207	1	2026-05-19 01:11:30.471384	25.66160348295019	-100.4207660186713	14.66
3208	1	2026-05-19 01:11:30.730821	25.66160743714479	-100.420788980869	15.26
3209	1	2026-05-19 01:11:30.999585	25.66160971532768	-100.420786656405	15.62
3210	1	2026-05-19 01:11:31.273101	25.66159591583701	-100.4207787516588	15.27
3211	1	2026-05-19 01:11:31.531571	25.66159711290087	-100.4207782723096	15.36
3212	1	2026-05-19 01:11:31.803707	25.66158336253797	-100.4207641213149	14.75
3213	1	2026-05-19 01:11:32.05761	25.66158336253797	-100.4207641213149	14.03
3214	1	2026-05-19 01:11:32.304973	25.66158336253797	-100.4207641213149	13.84
3215	1	2026-05-19 01:11:32.558915	25.66158336253797	-100.4207641213149	14.11
3216	1	2026-05-19 01:11:32.852619	25.66159152272026	-100.42077145486	13.82
3217	1	2026-05-19 01:11:33.10806	25.66159238410495	-100.4207839583643	13.65
3218	1	2026-05-19 01:11:33.368181	25.66160547097861	-100.4207923935	13.56
3219	1	2026-05-19 01:14:20.499673	25.66160102896987	-100.4207936926223	13.69
3220	1	2026-05-19 01:14:20.742266	25.66160402997725	-100.4207821649975	13.85
3221	1	2026-05-19 01:14:20.996206	25.66160402997725	-100.4207821649975	14.12
3222	1	2026-05-19 01:14:21.264432	25.66160402997725	-100.4207821649975	14.68
3223	1	2026-05-19 01:14:21.518707	25.66161069229721	-100.4207879883886	14.76
3224	1	2026-05-19 01:14:21.775194	25.6616100745912	-100.4207887262616	14.71
3225	1	2026-05-19 01:14:22.027625	25.6616100745912	-100.4207887262616	14.57
3226	1	2026-05-19 01:14:22.275695	25.66161786594707	-100.4207783458704	14.96
3227	1	2026-05-19 01:14:22.533893	25.66161786594707	-100.4207783458704	15.04
3228	1	2026-05-19 01:14:22.788316	25.66162461355223	-100.4207647511073	14.88
3229	1	2026-05-19 01:14:23.040919	25.66162449308268	-100.4207651194558	15.0
3230	1	2026-05-19 01:14:23.286907	25.66162449308268	-100.4207651194558	15.21
3231	1	2026-05-19 01:14:23.537336	25.66163127629198	-100.4207556298288	15.61
3232	1	2026-05-19 01:14:23.787549	25.66163575957754	-100.4207557168902	17.54
3233	1	2026-05-19 01:14:24.04463	25.66163554342727	-100.4207559773551	18.15
3234	1	2026-05-19 01:14:24.300612	25.66163554342727	-100.4207559773551	19.29
3235	1	2026-05-19 01:14:24.539725	25.66163554342727	-100.4207559773551	19.55
3236	1	2026-05-19 01:14:24.786208	25.66163554342727	-100.4207559773551	19.64
3237	1	2026-05-19 01:14:25.036179	25.66163554342727	-100.4207559773551	20.06
3238	1	2026-05-19 01:14:25.297142	25.66163554342727	-100.4207559773551	21.25
3239	1	2026-05-19 01:14:25.542889	25.66163554342727	-100.4207559773551	21.61
3240	1	2026-05-19 01:14:25.787	25.66163554342727	-100.4207559773551	23.53
3241	1	2026-05-19 01:14:26.03858	25.66163554342727	-100.4207559773551	23.08
3242	1	2026-05-19 01:14:26.283921	25.66164374166408	-100.4207830730862	22.78
3243	1	2026-05-19 01:14:26.525391	25.66164879115066	-100.4207812684449	22.35
3244	1	2026-05-19 01:14:26.783274	25.6616550838069	-100.4207857166468	22.04
3245	1	2026-05-19 01:14:27.033089	25.66167863470779	-100.420780456459	21.6
3246	1	2026-05-19 01:14:27.275191	25.6616804642901	-100.4207873982344	22.06
3247	1	2026-05-19 01:14:27.526154	25.6616804642901	-100.4207873982344	22.61
3248	1	2026-05-19 01:14:27.762254	25.66170399505571	-100.4207868848616	22.38
3249	1	2026-05-19 01:14:28.055082	25.66170399505571	-100.4207868848616	21.59
3250	1	2026-05-19 01:14:28.296075	25.66170399505571	-100.4207868848616	21.32
3251	1	2026-05-19 01:14:28.545135	25.66170399505571	-100.4207868848616	20.85
3252	1	2026-05-19 01:14:28.795571	25.66170399505571	-100.4207868848616	20.51
3253	1	2026-05-19 01:14:29.040999	25.66170399505571	-100.4207868848616	19.86
3254	1	2026-05-19 01:14:29.290714	25.66170399505571	-100.4207868848616	19.69
3255	1	2026-05-19 01:14:29.546868	25.66170399505571	-100.4207868848616	19.55
3256	1	2026-05-19 01:14:29.808325	25.66170399505571	-100.4207868848616	19.26
3257	1	2026-05-19 01:15:20.541471	25.66168686763575	-100.4208240352661	18.96
3258	1	2026-05-19 01:15:20.800307	25.6616756853292	-100.4208260023102	19.69
3259	1	2026-05-19 01:15:21.044779	25.66166180707895	-100.4207820816403	22.01
3260	1	2026-05-19 01:15:21.566443	25.66166268275791	-100.4207849607298	20.33
3261	1	2026-05-19 01:15:21.819308	25.66166268275791	-100.4207849607298	19.55
3262	1	2026-05-19 01:15:22.059122	25.66166268275791	-100.4207849607298	18.11
3263	1	2026-05-19 01:15:22.310521	25.66166268275791	-100.4207849607298	16.2
3264	1	2026-05-19 01:15:22.567288	25.66166268275791	-100.4207849607298	16.62
3265	1	2026-05-19 01:15:22.801566	25.66166268275791	-100.4207849607298	17.49
3266	1	2026-05-19 01:15:23.110426	25.66166268275791	-100.4207849607298	20.2
3267	1	2026-05-19 01:15:23.356653	25.66166268275791	-100.4207849607298	19.71
3268	1	2026-05-19 01:15:23.699406	25.66166268275791	-100.4207849607298	18.97
3269	1	2026-05-19 01:15:23.974556	25.66166268275791	-100.4207849607298	16.94
3270	1	2026-05-19 01:15:24.238073	25.66166268275791	-100.4207849607298	16.79
3271	1	2026-05-19 01:15:24.486168	25.66166268275791	-100.4207849607298	17.62
3272	1	2026-05-19 01:15:24.732545	25.66166268275791	-100.4207849607298	17.96
3273	1	2026-05-19 01:15:24.974513	25.66166268275791	-100.4207849607298	18.55
3274	1	2026-05-19 01:15:25.231184	25.66166268275791	-100.4207849607298	18.43
3275	1	2026-05-19 01:15:25.474957	25.66166268275791	-100.4207849607298	20.62
3276	1	2026-05-19 01:15:25.71866	25.66162493793209	-100.4208276261961	21.56
3277	1	2026-05-19 01:15:25.973087	25.66162344064529	-100.4208310028157	20.76
3278	1	2026-05-19 01:15:26.221992	25.66162640817848	-100.4208257103358	19.2
3279	1	2026-05-19 01:15:26.47663	25.66163540819371	-100.4208204766571	21.99
3280	1	2026-05-19 01:15:26.739323	25.66161752322445	-100.4208277990871	20.31
3281	1	2026-05-19 01:15:26.990232	25.66161752322445	-100.4208277990871	16.19
3282	1	2026-05-19 01:15:27.244798	25.66161752322445	-100.4208277990871	15.62
3283	1	2026-05-19 01:15:27.487825	25.66161752322445	-100.4208277990871	16.03
3284	1	2026-05-19 01:15:27.728674	25.66162955904346	-100.4208199260612	15.46
3285	1	2026-05-19 01:15:27.996074	25.66161295193703	-100.4208386852021	15.0
3286	1	2026-05-19 01:15:28.24955	25.66161316407915	-100.4208442118569	15.79
3287	1	2026-05-19 01:15:28.510116	25.66162185709292	-100.42084326448	15.64
3288	1	2026-05-19 01:15:28.758058	25.66162185709292	-100.42084326448	15.55
3289	1	2026-05-19 01:15:29.00747	25.66162185709292	-100.42084326448	16.6
3290	1	2026-05-19 01:15:29.266875	25.66162185709292	-100.42084326448	15.41
3291	1	2026-05-19 01:15:29.519444	25.66164995082403	-100.4208374021613	15.59
3292	1	2026-05-19 01:15:29.767636	25.66165330690453	-100.4208203201347	15.16
3293	1	2026-05-19 01:15:30.283231	25.66165714799665	-100.4208160600015	14.42
3294	1	2026-05-19 01:15:30.524768	25.66163928692059	-100.4208116764736	13.82
3295	1	2026-05-19 01:15:30.774356	25.66166788583956	-100.420821223987	13.69
3296	1	2026-05-19 01:15:31.022095	25.66165576792007	-100.420845223344	13.84
3297	1	2026-05-19 01:15:31.273685	25.66168623017445	-100.4208528023044	12.28
3298	1	2026-05-19 01:15:31.526158	25.66168623017445	-100.4208528023044	12.14
3299	1	2026-05-19 01:15:31.78767	25.66165276391182	-100.4208481238765	16.24
3300	1	2026-05-19 01:15:32.038064	25.66164927044709	-100.4208415942256	15.19
3301	1	2026-05-19 01:15:32.29264	25.66166909816726	-100.4208459541195	15.71
3302	1	2026-05-19 01:15:32.537571	25.66167343279387	-100.4208300837333	15.48
3303	1	2026-05-19 01:15:32.784032	25.66167938787012	-100.4208262764119	15.42
3304	1	2026-05-19 01:15:33.040223	25.66167969847259	-100.4208445931192	15.85
3305	1	2026-05-19 01:15:33.288715	25.66167631626409	-100.4208478626099	15.78
3306	1	2026-05-19 01:15:33.516688	25.66167631626409	-100.4208478626099	15.69
3307	1	2026-05-19 01:15:33.751889	25.66167631626409	-100.4208478626099	15.62
3308	1	2026-05-19 01:15:34.039654	25.66167631626409	-100.4208478626099	16.02
3309	1	2026-05-19 01:15:34.294534	25.66167631626409	-100.4208478626099	15.75
3310	1	2026-05-19 01:15:34.560891	25.66167469416732	-100.4208393608175	15.51
3311	1	2026-05-19 01:15:34.804384	25.661671786076	-100.4208372504463	17.28
3312	1	2026-05-19 01:15:35.044709	25.66166257337361	-100.4208383840942	17.41
3313	1	2026-05-19 01:15:35.292007	25.66164136508169	-100.4208155859534	17.21
3314	1	2026-05-19 01:15:35.533638	25.66163292391875	-100.420808237237	17.46
3315	1	2026-05-19 01:15:35.778044	25.66162877661159	-100.4207944334306	17.92
3316	1	2026-05-19 01:15:36.025952	25.66163893270148	-100.4207248669846	19.43
3317	1	2026-05-19 01:17:20.531762	25.66161563011132	-100.4207183826753	19.38
3318	1	2026-05-19 01:18:20.60891	25.66159527954802	-100.4207270778199	18.18
3319	1	2026-05-19 01:18:20.873949	25.66159664298463	-100.4207403794181	17.94
3320	1	2026-05-19 01:18:21.124065	25.66159763574074	-100.4207397963537	17.01
3321	1	2026-05-19 01:18:21.376573	25.66159786439289	-100.4207304553599	17.09
3322	1	2026-05-19 01:18:21.637288	25.66160002086864	-100.4207411880716	17.73
3323	1	2026-05-19 01:18:21.87899	25.66157764717363	-100.420752353562	19.08
3324	1	2026-05-19 01:18:22.135962	25.66156816322599	-100.4207412513759	19.56
3325	1	2026-05-19 01:18:22.391089	25.66156518581461	-100.4207317298522	18.82
3326	1	2026-05-19 01:18:22.636481	25.66156489188941	-100.4207339267342	18.11
3327	1	2026-05-19 01:18:22.886569	25.66156489188941	-100.4207339267342	17.44
3328	1	2026-05-19 01:18:23.135607	25.66156489188941	-100.4207339267342	16.81
3329	1	2026-05-19 01:18:23.391782	25.6615610757311	-100.4207224784874	18.67
3330	1	2026-05-19 01:18:23.647047	25.66153428585147	-100.4207323217193	18.49
3331	1	2026-05-19 01:18:23.988243	25.66153378404762	-100.4207341975686	21.25
3332	1	2026-05-19 01:18:24.234174	25.66153304156287	-100.4207377517888	20.42
3333	1	2026-05-19 01:18:24.494406	25.66155957997912	-100.4207901255377	19.5
3334	1	2026-05-19 01:18:24.741023	25.66153759945388	-100.4207859486764	19.22
3335	1	2026-05-19 01:18:24.979108	25.66156525926717	-100.420799412462	19.17
3336	1	2026-05-19 01:18:25.266687	25.66155662353844	-100.4208063098708	18.41
3337	1	2026-05-19 01:18:25.53073	25.66155662353844	-100.4208063098708	17.18
3338	1	2026-05-19 01:18:25.784231	25.66155662353844	-100.4208063098708	16.56
3339	1	2026-05-19 01:18:26.051869	25.66153604572963	-100.420806516415	16.4
3340	1	2026-05-19 01:18:26.288949	25.66152728969792	-100.4208000353298	16.09
3341	1	2026-05-19 01:18:26.540085	25.66152734828228	-100.4208003985916	15.59
3342	1	2026-05-19 01:18:26.77463	25.66152734828228	-100.4208003985916	15.22
3343	1	2026-05-19 01:18:27.032687	25.6615399808725	-100.4208105660104	14.66
3344	1	2026-05-19 01:18:27.279282	25.6615399808725	-100.4208105660104	13.59
3345	1	2026-05-19 01:18:27.532686	25.66153280411682	-100.4208088157892	13.07
3346	1	2026-05-19 01:18:27.786967	25.66153996683033	-100.4208151692168	12.62
3347	1	2026-05-19 01:18:28.038266	25.66153605275493	-100.420821466444	12.41
3348	1	2026-05-19 01:18:28.290608	25.66153605275493	-100.420821466444	12.06
3349	1	2026-05-19 01:18:28.526672	25.66153605275493	-100.420821466444	12.28
3350	1	2026-05-19 01:18:28.769288	25.66153605275493	-100.420821466444	12.12
3351	1	2026-05-19 01:18:29.019969	25.66153605275493	-100.420821466444	12.23
3352	1	2026-05-19 01:18:29.285199	25.6615588695496	-100.4208256302672	12.43
3353	1	2026-05-19 01:18:29.543124	25.66155618309049	-100.420820150238	12.67
3354	1	2026-05-19 01:18:29.786104	25.66155850968913	-100.4208246620249	12.78
3355	1	2026-05-19 01:18:30.031194	25.66154322954986	-100.4208238121765	12.74
3356	1	2026-05-19 01:18:30.271848	25.66155761515011	-100.4208345669249	12.62
3357	1	2026-05-19 01:18:30.520735	25.66155761515011	-100.4208345669249	12.09
3358	1	2026-05-19 01:20:20.500603	25.66154755840832	-100.4208372620977	11.56
3359	1	2026-05-19 01:20:20.752882	25.66154643066512	-100.4208516021708	12.27
3360	1	2026-05-19 01:20:20.998915	25.66154643066512	-100.4208516021708	12.52
3361	1	2026-05-19 01:20:21.255123	25.66154643066512	-100.4208516021708	12.84
3362	1	2026-05-19 01:20:21.5057	25.66154643066512	-100.4208516021708	13.14
3363	1	2026-05-19 01:20:21.764824	25.66157155964467	-100.4208592596095	12.86
3364	1	2026-05-19 01:20:22.04216	25.66156123652518	-100.4208636287497	13.48
3365	1	2026-05-19 01:20:22.285922	25.6615980879884	-100.4208789495671	16.78
3366	1	2026-05-19 01:20:22.52488	25.66158290870559	-100.4208801511188	16.59
3367	1	2026-05-19 01:20:22.775414	25.66155589628169	-100.4208654936556	18.28
3368	1	2026-05-19 01:20:23.019655	25.66154800422571	-100.4208545758522	19.42
3369	1	2026-05-19 01:20:23.265299	25.66153519188194	-100.4208604298179	19.47
3370	1	2026-05-19 01:20:24.237139	25.66153020448393	-100.4208638587531	20.99
3371	1	2026-05-19 01:20:24.488664	25.66153020448393	-100.4208638587531	22.36
3372	1	2026-05-19 01:20:24.740167	25.66153020448393	-100.4208638587531	23.43
3373	1	2026-05-19 01:20:24.98816	25.66153181210105	-100.420856146723	23.85
3374	1	2026-05-19 01:20:25.251119	25.66153181210105	-100.420856146723	22.34
3375	1	2026-05-19 01:20:25.49561	25.66153181210105	-100.420856146723	22.04
3376	1	2026-05-19 01:20:25.740362	25.66153181210105	-100.420856146723	21.37
3377	1	2026-05-19 01:20:25.977498	25.66153181210105	-100.420856146723	22.07
3378	1	2026-05-19 01:20:26.243447	25.66153181210105	-100.420856146723	22.27
3379	1	2026-05-19 01:20:26.484204	25.66153181210105	-100.420856146723	22.1
3380	1	2026-05-19 01:20:26.723174	25.66149780687076	-100.4208379008201	24.12
3381	1	2026-05-19 01:20:26.966996	25.66149742093543	-100.420837901812	24.15
3382	1	2026-05-19 01:20:27.219771	25.66149742093543	-100.420837901812	24.83
3383	1	2026-05-19 01:20:27.464313	25.66149742093543	-100.420837901812	28.43
3384	1	2026-05-19 01:20:27.70447	25.66149742093543	-100.420837901812	32.49
3385	1	2026-05-19 01:20:27.943568	25.66149742093543	-100.420837901812	37.56
3386	1	2026-05-19 01:20:28.191328	25.66149742093543	-100.420837901812	36.9
3387	1	2026-05-19 01:20:28.46266	25.66149742093543	-100.420837901812	38.55
3388	1	2026-05-19 01:20:28.708076	25.66149742093543	-100.420837901812	39.86
3389	1	2026-05-19 01:20:29.142197	25.66149694849672	-100.4207977916373	40.33
3390	1	2026-05-19 01:20:29.395572	25.66149694849672	-100.4207977916373	42.6
3391	1	2026-05-19 01:20:29.634329	25.66149694849672	-100.4207977916373	44.04
3392	1	2026-05-19 01:20:29.884087	25.66149694849672	-100.4207977916373	42.44
3393	1	2026-05-19 01:20:30.1496	25.66149694849672	-100.4207977916373	41.52
3394	1	2026-05-19 01:20:30.392512	25.66149694849672	-100.4207977916373	42.8
3395	1	2026-05-19 01:20:30.645474	25.66149694849672	-100.4207977916373	41.42
3396	1	2026-05-19 01:20:30.889085	25.66150327616522	-100.4208342479519	41.22
3397	1	2026-05-19 01:20:31.126482	25.66150327616522	-100.4208342479519	36.84
3398	1	2026-05-19 01:20:31.381827	25.66150327616522	-100.4208342479519	35.34
3399	1	2026-05-19 01:20:31.633077	25.66150327616522	-100.4208342479519	33.37
3400	1	2026-05-19 01:20:31.865416	25.66153809043824	-100.4208942638808	32.13
3401	1	2026-05-19 01:20:32.109	25.66152941375721	-100.4208834009789	29.44
3402	1	2026-05-19 01:20:32.343108	25.66152809598515	-100.4208858430931	27.51
3403	1	2026-05-19 01:20:32.591191	25.66152809598515	-100.4208858430931	32.17
3404	1	2026-05-19 01:20:32.83773	25.66152809598515	-100.4208858430931	31.63
3405	1	2026-05-19 01:20:33.362042	25.66152809598515	-100.4208858430931	31.98
3406	1	2026-05-19 01:20:33.607295	25.66152809598515	-100.4208858430931	31.36
3407	1	2026-05-19 01:20:33.848072	25.66150878995725	-100.4208769358758	30.42
3408	1	2026-05-19 01:20:34.090257	25.66150853003375	-100.4208767795422	29.14
3409	1	2026-05-19 01:20:34.325854	25.66151109452229	-100.4208715258926	28.35
3410	1	2026-05-19 01:20:34.567871	25.66151955185082	-100.4208714466732	27.17
3411	1	2026-05-19 01:20:34.811166	25.66151884317865	-100.4208699096131	24.98
3412	1	2026-05-19 01:20:35.108376	25.66151834754914	-100.4208700857407	23.97
3413	1	2026-05-19 01:20:35.353563	25.66151834754914	-100.4208700857407	25.46
3414	1	2026-05-19 01:20:35.627509	25.66151834754914	-100.4208700857407	24.42
3415	1	2026-05-19 01:20:35.876936	25.66150920123834	-100.4208669902573	25.0
3416	1	2026-05-19 01:20:36.120324	25.66150920123834	-100.4208669902573	24.14
3417	1	2026-05-19 01:23:20.487112	25.66150920123834	-100.4208669902573	22.81
3418	1	2026-05-19 01:23:20.747266	25.66152205938413	-100.4209031509598	21.24
3419	1	2026-05-19 01:23:21.00007	25.66151956884851	-100.4209033910981	21.55
3420	1	2026-05-19 01:23:21.269661	25.66151918904362	-100.4209029500478	22.58
3421	1	2026-05-19 01:23:21.526507	25.66151918904362	-100.4209029500478	22.14
3422	1	2026-05-19 01:23:21.789624	25.66151518250567	-100.4208930524424	22.17
3423	1	2026-05-19 01:23:22.058601	25.66153035526716	-100.4208919050019	23.67
3424	1	2026-05-19 01:23:22.297622	25.66153215598942	-100.4208969883124	26.22
3425	1	2026-05-19 01:23:22.541555	25.66153215598942	-100.4208969883124	28.23
3426	1	2026-05-19 01:23:22.826917	25.66153215598942	-100.4208969883124	28.59
3427	1	2026-05-19 01:23:23.104258	25.66153215598942	-100.4208969883124	30.08
3428	1	2026-05-19 01:23:23.371726	25.66153215598942	-100.4208969883124	29.01
3429	1	2026-05-19 01:23:23.677019	25.66153215598942	-100.4208969883124	26.65
3430	1	2026-05-19 01:23:23.933472	25.66153215598942	-100.4208969883124	27.56
3431	1	2026-05-19 01:23:24.209283	25.66153215598942	-100.4208969883124	26.93
3432	1	2026-05-19 01:23:24.454149	25.66153215598942	-100.4208969883124	27.65
3433	1	2026-05-19 01:23:24.742992	25.66153215598942	-100.4208969883124	26.51
3434	1	2026-05-19 01:23:25.002024	25.66153215598942	-100.4208969883124	27.83
3435	1	2026-05-19 01:23:25.268807	25.66153215598942	-100.4208969883124	28.05
3436	1	2026-05-19 01:23:25.534275	25.66153215598942	-100.4208969883124	27.37
3437	1	2026-05-19 01:23:25.808675	25.66153215598942	-100.4208969883124	27.33
3438	1	2026-05-19 01:23:26.06538	25.66152390009624	-100.4208712765948	29.61
3439	1	2026-05-19 01:23:26.396856	25.66152674369117	-100.4208691838118	33.62
3440	1	2026-05-19 01:23:26.650706	25.66152924897208	-100.4208613576481	32.58
3441	1	2026-05-19 01:23:26.908348	25.66155455910472	-100.4208603402169	33.64
3442	1	2026-05-19 01:23:27.173196	25.66155254166716	-100.4208627597925	33.61
3443	1	2026-05-19 01:23:27.437613	25.66155254166716	-100.4208627597925	36.83
3444	1	2026-05-19 01:23:27.717504	25.66155254166716	-100.4208627597925	35.66
3445	1	2026-05-19 01:23:27.97302	25.66152739628165	-100.4208733984175	34.79
3446	1	2026-05-19 01:23:28.225795	25.66152739628165	-100.4208733984175	33.61
3447	1	2026-05-19 01:23:28.494879	25.66152739628165	-100.4208733984175	35.98
3448	1	2026-05-19 01:23:28.746371	25.66152739628165	-100.4208733984175	35.92
3449	1	2026-05-19 01:23:28.995309	25.66152739628165	-100.4208733984175	35.16
3450	1	2026-05-19 01:23:29.254913	25.66152739628165	-100.4208733984175	33.87
3451	1	2026-05-19 01:23:29.517439	25.66152301854524	-100.4208683656537	32.78
3452	1	2026-05-19 01:23:29.858523	25.66152301854524	-100.4208683656537	32.56
3453	1	2026-05-19 01:23:30.107416	25.66152772550681	-100.4208723897695	32.24
3454	1	2026-05-19 01:23:30.368715	25.66152821549907	-100.4208757284269	32.85
3455	1	2026-05-19 01:23:30.640908	25.661608762553	-100.4208099458271	29.92
3456	1	2026-05-19 01:23:30.907081	25.66156111162653	-100.4208040426742	31.47
3457	1	2026-05-19 01:23:31.153686	25.66156111162653	-100.4208040426742	32.04
3458	1	2026-05-19 01:23:31.395839	25.66156111162653	-100.4208040426742	32.84
3459	1	2026-05-19 01:25:20.548469	25.66156111162653	-100.4208040426742	33.05
3460	1	2026-05-19 01:25:20.834945	25.66156111162653	-100.4208040426742	34.79
3461	1	2026-05-19 01:25:21.119564	25.66156111162653	-100.4208040426742	34.18
3462	1	2026-05-19 01:25:21.830786	25.66156111162653	-100.4208040426742	35.58
3463	1	2026-05-19 01:25:22.774471	25.66156111162653	-100.4208040426742	34.49
3464	1	2026-05-19 01:25:23.436643	25.66156111162653	-100.4208040426742	33.18
3465	1	2026-05-19 01:25:24.40673	25.66161098955988	-100.4208307617828	31.44
3466	1	2026-05-19 01:25:24.635441	25.66162012775082	-100.4208258212586	31.16
3467	1	2026-05-19 01:25:25.347449	25.66161710192143	-100.4208263065356	30.12
3468	1	2026-05-19 01:25:25.612475	25.66159497313986	-100.4208369404257	26.5
3469	1	2026-05-19 01:25:25.840806	25.66158557226919	-100.4208473150591	25.41
3470	1	2026-05-19 01:25:26.065691	25.66157727720531	-100.4208518974214	24.38
3471	1	2026-05-19 01:25:26.3129	25.66157677826597	-100.4208557286183	24.47
3472	1	2026-05-19 01:25:26.77391	25.66157677826597	-100.4208557286183	24.24
3473	1	2026-05-19 01:25:26.999787	25.66157677826597	-100.4208557286183	23.26
3474	1	2026-05-19 01:25:27.257343	25.66157677826597	-100.4208557286183	22.92
3475	1	2026-05-19 01:25:27.485234	25.66157677826597	-100.4208557286183	24.91
3476	1	2026-05-19 01:25:27.939115	25.66157677826597	-100.4208557286183	26.99
3477	1	2026-05-19 01:25:28.167639	25.66157677826597	-100.4208557286183	27.9
3478	1	2026-05-19 01:25:28.661604	25.66157677826597	-100.4208557286183	27.74
3479	1	2026-05-19 01:25:29.557034	25.66157677826597	-100.4208557286183	30.75
3480	1	2026-05-19 01:25:29.821629	25.66157677826597	-100.4208557286183	30.6
3481	1	2026-05-19 01:25:30.551665	25.66157677826597	-100.4208557286183	31.69
3482	1	2026-05-19 01:25:30.808505	25.66157677826597	-100.4208557286183	31.88
3483	1	2026-05-19 01:25:31.045443	25.66157677826597	-100.4208557286183	33.18
3484	1	2026-05-19 01:25:31.824685	25.66157677826597	-100.4208557286183	33.91
3485	1	2026-05-19 01:25:32.375249	25.66157677826597	-100.4208557286183	33.85
3486	1	2026-05-19 01:25:32.672015	25.66157677826597	-100.4208557286183	32.54
3487	1	2026-05-19 01:25:33.227292	25.66157677826597	-100.4208557286183	32.53
3488	1	2026-05-19 01:25:33.467119	25.66157677826597	-100.4208557286183	33.16
3489	1	2026-05-19 01:25:33.750951	25.66157677826597	-100.4208557286183	32.39
3490	1	2026-05-19 01:25:34.031485	25.66157677826597	-100.4208557286183	32.82
3491	1	2026-05-19 01:25:34.619085	25.66157677826597	-100.4208557286183	32.82
3492	1	2026-05-19 01:25:34.879216	25.66157677826597	-100.4208557286183	32.82
3493	1	2026-05-19 01:25:35.115533	25.66157677826597	-100.4208557286183	32.82
3494	1	2026-05-19 01:25:35.352845	25.66157677826597	-100.4208557286183	32.82
3495	1	2026-05-19 01:25:35.658784	25.66157677826597	-100.4208557286183	32.82
3496	1	2026-05-19 01:25:35.900586	25.66157677826597	-100.4208557286183	32.82
3497	1	2026-05-19 01:25:36.159315	25.66157677826597	-100.4208557286183	32.82
3498	1	2026-05-19 01:25:36.409057	25.66157677826597	-100.4208557286183	32.82
3499	1	2026-05-19 01:25:36.659716	25.66157677826597	-100.4208557286183	32.82
3500	1	2026-05-19 01:25:36.904849	25.66157677826597	-100.4208557286183	32.82
3501	1	2026-05-19 01:25:37.149576	25.66157677826597	-100.4208557286183	32.82
3502	1	2026-05-19 01:25:37.372959	25.66157677826597	-100.4208557286183	32.82
3503	1	2026-05-19 01:25:37.627021	25.66157677826597	-100.4208557286183	32.82
3504	1	2026-05-19 01:25:37.882948	25.66157677826597	-100.4208557286183	32.82
3505	1	2026-05-19 01:25:38.138769	25.66157677826597	-100.4208557286183	32.82
3506	1	2026-05-19 01:25:38.778555	25.66157677826597	-100.4208557286183	32.82
3507	1	2026-05-19 01:25:39.024876	25.66157677826597	-100.4208557286183	32.82
3508	1	2026-05-19 01:25:39.265721	25.66157677826597	-100.4208557286183	32.82
3509	1	2026-05-19 01:25:39.511044	25.66157677826597	-100.4208557286183	32.82
3510	1	2026-05-19 01:25:40.143963	25.66157677826597	-100.4208557286183	32.82
3511	1	2026-05-19 01:25:40.403574	25.66157677826597	-100.4208557286183	32.82
3512	1	2026-05-19 01:25:40.654198	25.66157677826597	-100.4208557286183	32.82
3513	1	2026-05-19 01:25:40.892234	25.66157677826597	-100.4208557286183	32.82
3514	1	2026-05-19 01:25:41.161328	25.66157677826597	-100.4208557286183	32.82
3515	1	2026-05-19 01:25:41.488522	25.66157677826597	-100.4208557286183	32.82
3516	1	2026-05-19 01:25:41.711472	25.66157677826597	-100.4208557286183	32.82
3517	1	2026-05-19 01:25:42.002431	25.66157677826597	-100.4208557286183	32.82
3518	1	2026-05-19 01:25:42.333242	25.66157677826597	-100.4208557286183	32.82
3519	1	2026-05-19 01:25:42.573176	25.66157677826597	-100.4208557286183	32.82
3520	1	2026-05-19 01:25:42.819598	25.66157677826597	-100.4208557286183	32.82
3521	1	2026-05-19 01:25:43.078571	25.66157677826597	-100.4208557286183	32.82
3522	1	2026-05-19 01:25:43.338343	25.66157677826597	-100.4208557286183	32.82
3523	1	2026-05-19 01:25:43.591433	25.66157677826597	-100.4208557286183	32.82
3524	1	2026-05-19 01:28:20.493543	25.66157677826597	-100.4208557286183	32.82
3525	1	2026-05-19 01:28:20.749084	25.66157677826597	-100.4208557286183	32.82
3526	1	2026-05-19 01:28:20.995275	25.66157677826597	-100.4208557286183	32.82
3527	1	2026-05-19 01:28:21.259274	25.66157677826597	-100.4208557286183	32.82
3528	1	2026-05-19 01:28:21.50325	25.66157677826597	-100.4208557286183	32.82
3529	1	2026-05-19 01:28:21.770336	25.66157677826597	-100.4208557286183	32.82
3530	1	2026-05-19 01:28:22.017759	25.66157677826597	-100.4208557286183	32.82
3531	1	2026-05-19 01:28:22.268057	25.66157677826597	-100.4208557286183	32.82
3532	1	2026-05-19 01:28:22.535216	25.66157677826597	-100.4208557286183	32.82
3533	1	2026-05-19 01:28:22.784898	25.66157677826597	-100.4208557286183	32.82
3534	1	2026-05-19 01:28:23.034395	25.66157677826597	-100.4208557286183	32.82
3535	1	2026-05-19 01:28:23.274171	25.66157677826597	-100.4208557286183	32.82
3536	1	2026-05-19 01:28:23.524824	25.66157677826597	-100.4208557286183	32.82
3537	1	2026-05-19 01:28:23.761028	25.66157677826597	-100.4208557286183	32.82
3538	1	2026-05-19 01:28:24.013489	25.66157677826597	-100.4208557286183	32.82
3539	1	2026-05-19 01:28:24.269893	25.66157677826597	-100.4208557286183	32.82
3540	1	2026-05-19 01:28:24.721091	25.66157677826597	-100.4208557286183	32.82
3541	1	2026-05-19 01:28:24.995965	25.66157677826597	-100.4208557286183	32.82
3542	1	2026-05-19 01:28:25.24949	25.66157677826597	-100.4208557286183	32.82
3543	1	2026-05-19 01:28:25.497005	25.66157677826597	-100.4208557286183	32.82
3544	1	2026-05-19 01:28:25.757467	25.66157677826597	-100.4208557286183	32.82
3545	1	2026-05-19 01:28:26.012248	25.66157677826597	-100.4208557286183	32.82
3546	1	2026-05-19 01:28:26.268154	25.66157677826597	-100.4208557286183	32.82
3547	1	2026-05-19 01:28:26.515932	25.66157677826597	-100.4208557286183	32.82
3548	1	2026-05-19 01:28:26.766801	25.66157677826597	-100.4208557286183	32.82
3549	1	2026-05-19 01:28:27.268139	25.66157677826597	-100.4208557286183	32.82
3550	1	2026-05-19 01:28:27.528436	25.66157677826597	-100.4208557286183	32.82
3551	1	2026-05-19 01:28:27.821397	25.66157677826597	-100.4208557286183	32.82
3552	1	2026-05-19 01:28:28.073488	25.66157677826597	-100.4208557286183	32.82
3553	1	2026-05-19 01:28:28.317057	25.66157677826597	-100.4208557286183	32.82
3554	1	2026-05-19 01:28:28.566046	25.66157677826597	-100.4208557286183	32.82
3555	1	2026-05-19 01:28:28.830202	25.66157677826597	-100.4208557286183	32.82
3556	1	2026-05-19 01:28:29.076692	25.66157677826597	-100.4208557286183	32.82
3557	1	2026-05-19 01:28:29.334933	25.66157677826597	-100.4208557286183	32.82
3558	1	2026-05-19 01:28:29.593691	25.66157677826597	-100.4208557286183	32.82
3559	1	2026-05-19 01:28:29.850796	25.66157677826597	-100.4208557286183	32.82
3560	1	2026-05-19 01:28:30.108203	25.66157677826597	-100.4208557286183	32.82
3561	1	2026-05-19 01:28:30.366176	25.66157677826597	-100.4208557286183	32.82
3562	1	2026-05-19 01:28:30.609694	25.66157677826597	-100.4208557286183	32.82
3563	1	2026-05-19 01:30:20.510134	25.66157677826597	-100.4208557286183	32.82
3564	1	2026-05-19 01:30:20.783068	25.66157677826597	-100.4208557286183	32.82
3565	1	2026-05-19 01:30:21.050769	25.66157677826597	-100.4208557286183	32.82
3566	1	2026-05-19 01:30:21.317644	25.66157677826597	-100.4208557286183	32.82
3567	1	2026-05-19 01:30:21.585307	25.66157677826597	-100.4208557286183	32.82
3568	1	2026-05-19 01:30:21.830308	25.66157677826597	-100.4208557286183	32.82
3569	1	2026-05-19 01:30:22.08868	25.66157677826597	-100.4208557286183	32.82
3570	1	2026-05-19 01:30:22.354464	25.66157677826597	-100.4208557286183	32.82
3571	1	2026-05-19 01:30:22.637132	25.66157677826597	-100.4208557286183	32.82
3572	1	2026-05-19 01:30:22.906636	25.66157677826597	-100.4208557286183	32.82
3573	1	2026-05-19 01:30:23.162835	25.66157677826597	-100.4208557286183	32.82
3574	1	2026-05-19 01:30:23.660836	25.66157677826597	-100.4208557286183	32.82
3575	1	2026-05-19 01:30:23.937659	25.66157677826597	-100.4208557286183	32.82
3576	1	2026-05-19 01:30:24.207357	25.66157677826597	-100.4208557286183	32.82
3577	1	2026-05-19 01:30:24.492559	25.66157677826597	-100.4208557286183	32.82
3578	1	2026-05-19 01:30:24.754651	25.66208381154174	-100.4208663464846	19.6
3579	1	2026-05-19 01:30:25.011059	25.66208381154174	-100.4208663464846	19.6
3580	1	2026-05-19 01:30:25.288852	25.66208381154174	-100.4208663464846	19.6
3581	1	2026-05-19 01:30:25.542772	25.66208381154174	-100.4208663464846	19.6
3582	1	2026-05-19 01:30:25.786066	25.66208381154174	-100.4208663464846	19.6
3583	1	2026-05-19 01:30:26.025425	25.66208381154174	-100.4208663464846	19.6
3584	1	2026-05-19 01:30:26.278069	25.66208381154174	-100.4208663464846	19.6
3585	1	2026-05-19 01:30:26.567062	25.66208381154174	-100.4208663464846	19.6
3586	1	2026-05-19 01:30:26.826003	25.66208381154174	-100.4208663464846	19.6
3587	1	2026-05-19 01:30:27.101058	25.66208381154174	-100.4208663464846	19.6
3588	1	2026-05-19 01:30:27.359321	25.66208381154174	-100.4208663464846	19.6
3589	1	2026-05-19 01:30:27.622397	25.66208381154174	-100.4208663464846	19.6
3590	1	2026-05-19 01:30:27.877907	25.66208381154174	-100.4208663464846	19.6
3591	1	2026-05-19 01:30:28.23844	25.66208381154174	-100.4208663464846	19.6
3592	1	2026-05-19 01:30:28.483357	25.66208381154174	-100.4208663464846	19.6
3593	1	2026-05-19 01:30:28.762291	25.66208381154174	-100.4208663464846	19.6
3594	1	2026-05-19 01:30:29.018063	25.66208381154174	-100.4208663464846	19.6
3595	1	2026-05-19 01:30:29.259968	25.66208381154174	-100.4208663464846	19.6
3596	1	2026-05-19 01:30:29.494509	25.66208381154174	-100.4208663464846	19.6
3597	1	2026-05-19 01:30:29.939811	25.66208381154174	-100.4208663464846	19.6
3598	1	2026-05-19 01:30:30.191118	25.66208381154174	-100.4208663464846	19.6
3599	1	2026-05-19 01:30:30.642265	25.66208381154174	-100.4208663464846	19.6
3600	1	2026-05-19 01:30:30.895905	25.66208381154174	-100.4208663464846	19.6
3601	1	2026-05-19 01:30:31.134727	25.66206353733666	-100.420891849656	14.94
3602	1	2026-05-19 01:30:31.41797	25.66206353733666	-100.420891849656	14.94
3603	1	2026-05-19 01:30:31.691521	25.66206353733666	-100.420891849656	14.94
3604	1	2026-05-19 01:30:31.989911	25.66206353733666	-100.420891849656	14.94
3605	1	2026-05-19 01:31:20.542342	25.66206353733666	-100.420891849656	14.94
3606	1	2026-05-19 01:31:20.825814	25.66206353733666	-100.420891849656	14.94
3607	1	2026-05-19 01:31:21.074516	25.66206353733666	-100.420891849656	14.94
3608	1	2026-05-19 01:31:21.634187	25.66206353733666	-100.420891849656	14.94
3609	1	2026-05-19 01:31:21.883759	25.66206353733666	-100.420891849656	14.94
3610	1	2026-05-19 01:31:22.181795	25.66206353733666	-100.420891849656	14.94
3611	1	2026-05-19 01:31:22.443981	25.66206353733666	-100.420891849656	14.94
3612	1	2026-05-19 01:31:22.702699	25.66206353733666	-100.420891849656	14.94
3613	1	2026-05-19 01:31:22.986113	25.66206353733666	-100.420891849656	14.94
3614	1	2026-05-19 01:31:23.299072	25.66206353733666	-100.420891849656	14.94
3615	1	2026-05-19 01:31:23.571381	25.66206353733666	-100.420891849656	14.94
3616	1	2026-05-19 01:31:23.832602	25.66206353733666	-100.420891849656	14.94
3617	1	2026-05-19 01:31:24.111179	25.66206353733666	-100.420891849656	14.94
3618	1	2026-05-19 01:31:24.388393	25.66206353733666	-100.420891849656	14.94
3619	1	2026-05-19 01:31:24.645012	25.66206353733666	-100.420891849656	14.94
3620	1	2026-05-19 01:31:24.918228	25.66206353733666	-100.420891849656	14.94
3621	1	2026-05-19 01:31:25.208803	25.66206353733666	-100.420891849656	14.94
3622	1	2026-05-19 01:32:20.746146	25.66206353733666	-100.420891849656	14.94
3623	1	2026-05-19 01:32:21.001584	25.66206353733666	-100.420891849656	14.94
3624	1	2026-05-19 01:32:21.263234	25.66206353733666	-100.420891849656	14.94
3625	1	2026-05-19 01:32:21.520662	25.66206353733666	-100.420891849656	14.94
3626	1	2026-05-19 01:32:21.804985	25.66206353733666	-100.420891849656	14.94
3627	1	2026-05-19 01:32:22.06269	25.66206353733666	-100.420891849656	14.94
3628	1	2026-05-19 01:32:22.313879	25.66206353733666	-100.420891849656	14.94
3629	1	2026-05-19 01:32:22.573663	25.66206353733666	-100.420891849656	14.94
3630	1	2026-05-19 01:32:22.83912	25.66206353733666	-100.420891849656	14.94
3631	1	2026-05-19 01:32:23.105254	25.66206353733666	-100.420891849656	14.94
3632	1	2026-05-19 01:32:23.373526	25.66206353733666	-100.420891849656	14.94
3633	1	2026-05-19 01:32:23.64246	25.66206353733666	-100.420891849656	14.94
3634	1	2026-05-19 01:32:23.896859	25.66206353733666	-100.420891849656	14.94
3635	1	2026-05-19 01:32:24.14904	25.66206353733666	-100.420891849656	14.94
3636	1	2026-05-19 01:32:24.43272	25.66206353733666	-100.420891849656	14.94
3637	1	2026-05-19 01:32:24.691417	25.66206353733666	-100.420891849656	14.94
3638	1	2026-05-19 01:32:24.955987	25.66206353733666	-100.420891849656	14.94
3639	1	2026-05-19 01:32:25.204119	25.66206353733666	-100.420891849656	14.94
3640	1	2026-05-19 01:32:25.462567	25.66206353733666	-100.420891849656	14.94
3641	1	2026-05-19 01:32:25.726723	25.66206353733666	-100.420891849656	14.94
3642	1	2026-05-19 01:32:25.993331	25.66206353733666	-100.420891849656	14.94
3643	1	2026-05-19 01:32:26.247674	25.66206353733666	-100.420891849656	14.94
3644	1	2026-05-19 01:32:26.516727	25.66206353733666	-100.420891849656	14.94
3645	1	2026-05-19 01:32:26.812505	25.66206353733666	-100.420891849656	14.94
3646	1	2026-05-19 01:32:27.071041	25.66206353733666	-100.420891849656	14.94
3647	1	2026-05-19 01:32:27.327115	25.66206353733666	-100.420891849656	14.94
3648	1	2026-05-19 01:32:27.588821	25.66206353733666	-100.420891849656	14.94
3649	1	2026-05-19 01:33:20.585991	25.66206353733666	-100.420891849656	14.94
3650	1	2026-05-19 01:33:20.835919	25.66206353733666	-100.420891849656	14.94
3651	1	2026-05-19 01:33:21.086883	25.66206353733666	-100.420891849656	14.94
3652	1	2026-05-19 01:33:21.335792	25.66206353733666	-100.420891849656	14.94
3653	1	2026-05-19 01:33:21.586817	25.66206154532378	-100.4208897798704	5.35
3654	1	2026-05-19 01:33:21.844188	25.66206154532378	-100.4208897798704	5.35
3655	1	2026-05-19 01:33:22.102048	25.66206154532378	-100.4208897798704	5.35
3656	1	2026-05-19 01:33:22.353311	25.66206154532378	-100.4208897798704	5.35
3657	1	2026-05-19 01:33:22.604646	25.66206154532378	-100.4208897798704	5.35
3658	1	2026-05-19 01:33:22.857792	25.66206154532378	-100.4208897798704	5.35
3659	1	2026-05-19 01:33:23.110144	25.66206154532378	-100.4208897798704	5.35
3660	1	2026-05-19 01:33:23.377434	25.66206154532378	-100.4208897798704	5.35
3661	1	2026-05-19 01:33:23.630772	25.66206154532378	-100.4208897798704	5.35
3662	1	2026-05-19 01:33:23.892285	25.66206154532378	-100.4208897798704	5.35
3663	1	2026-05-19 01:33:24.144444	25.66202385598297	-100.4208896299536	5.47
3664	1	2026-05-19 01:33:24.39956	25.66202385598297	-100.4208896299536	5.47
3665	1	2026-05-19 01:33:24.650428	25.66202385598297	-100.4208896299536	5.47
3666	1	2026-05-19 01:35:20.630667	25.66202385598297	-100.4208896299536	5.47
3667	1	2026-05-19 01:35:20.903053	25.66202385598297	-100.4208896299536	5.47
3668	1	2026-05-19 01:35:21.159828	25.66202385598297	-100.4208896299536	5.47
3669	1	2026-05-19 01:35:21.457131	25.66202385598297	-100.4208896299536	5.47
3670	1	2026-05-19 01:35:21.846036	25.66202385598297	-100.4208896299536	5.47
3671	1	2026-05-19 01:35:22.101182	25.66202385598297	-100.4208896299536	5.47
3672	1	2026-05-19 01:35:22.345639	25.66202385598297	-100.4208896299536	5.47
3673	1	2026-05-19 01:35:22.630871	25.66202385598297	-100.4208896299536	5.47
3674	1	2026-05-19 01:35:22.879066	25.66202385598297	-100.4208896299536	5.47
3675	1	2026-05-19 01:35:23.20388	25.66202385598297	-100.4208896299536	5.47
3676	1	2026-05-19 01:35:23.446311	25.66202385598297	-100.4208896299536	5.47
3677	1	2026-05-19 01:35:23.7119	25.66202385598297	-100.4208896299536	5.47
3678	1	2026-05-19 01:35:23.948941	25.66202385598297	-100.4208896299536	5.47
3679	1	2026-05-19 01:35:24.354793	25.66202385598297	-100.4208896299536	5.47
3680	1	2026-05-19 01:35:24.617892	25.66202385598297	-100.4208896299536	5.47
3681	1	2026-05-19 01:35:24.859507	25.66202385598297	-100.4208896299536	5.47
3682	1	2026-05-19 01:35:25.106603	25.66202385598297	-100.4208896299536	5.47
3683	1	2026-05-19 01:35:25.355343	25.66202385598297	-100.4208896299536	5.47
3684	1	2026-05-19 01:35:25.630874	25.66202385598297	-100.4208896299536	5.47
3685	1	2026-05-19 01:35:25.886648	25.66202385598297	-100.4208896299536	5.47
3686	1	2026-05-19 01:35:26.139032	25.66202385598297	-100.4208896299536	5.47
3687	1	2026-05-19 01:35:26.387975	25.66202385598297	-100.4208896299536	5.47
3688	1	2026-05-19 01:35:26.64095	25.66202385598297	-100.4208896299536	5.47
3689	1	2026-05-19 01:35:26.894003	25.66202385598297	-100.4208896299536	5.47
3690	1	2026-05-19 01:35:27.14211	25.66202385598297	-100.4208896299536	5.47
3691	1	2026-05-19 01:35:27.408691	25.66202385598297	-100.4208896299536	5.47
3692	1	2026-05-19 01:35:27.643732	25.66202385598297	-100.4208896299536	5.47
3693	1	2026-05-19 01:37:10.597911	25.66202385598297	-100.4208896299536	5.47
3694	1	2026-05-19 01:37:10.836231	25.66202385598297	-100.4208896299536	5.47
3695	1	2026-05-19 01:37:11.087887	25.66202385598297	-100.4208896299536	5.47
3696	1	2026-05-19 01:37:11.337821	25.66202385598297	-100.4208896299536	5.47
3697	1	2026-05-19 01:37:11.601449	25.66202385598297	-100.4208896299536	5.47
3698	1	2026-05-19 01:37:11.856523	25.66202385598297	-100.4208896299536	5.47
3699	1	2026-05-19 01:37:12.107513	25.66202385598297	-100.4208896299536	5.47
3700	1	2026-05-19 01:37:12.358608	25.66202385598297	-100.4208896299536	5.47
3701	1	2026-05-19 01:37:12.600603	25.66202385598297	-100.4208896299536	5.47
3702	1	2026-05-19 01:37:12.845353	25.66202385598297	-100.4208896299536	5.47
3703	1	2026-05-19 01:37:13.114349	25.66202385598297	-100.4208896299536	5.47
3704	1	2026-05-19 01:37:13.374428	25.66202385598297	-100.4208896299536	5.47
3705	1	2026-05-19 01:37:13.664038	25.66202385598297	-100.4208896299536	5.47
3706	1	2026-05-19 01:37:13.917898	25.66202385598297	-100.4208896299536	5.47
3707	1	2026-05-19 01:37:14.161295	25.66202385598297	-100.4208896299536	5.47
3708	1	2026-05-19 01:37:14.397697	25.66202385598297	-100.4208896299536	5.47
3709	1	2026-05-19 01:37:14.649804	25.66202385598297	-100.4208896299536	5.47
3710	1	2026-05-19 01:37:14.91622	25.66202385598297	-100.4208896299536	5.47
3711	1	2026-05-19 01:37:15.169267	25.66202385598297	-100.4208896299536	5.47
3712	1	2026-05-19 01:37:15.413512	25.66202385598297	-100.4208896299536	5.47
3713	1	2026-05-19 01:37:15.657167	25.66202385598297	-100.4208896299536	5.47
3714	1	2026-05-19 01:37:15.899276	25.66202385598297	-100.4208896299536	5.47
3715	1	2026-05-19 01:37:16.139094	25.66202385598297	-100.4208896299536	5.47
3716	1	2026-05-19 01:37:16.388848	25.66202937744419	-100.4208750815002	5.02
3717	1	2026-05-19 01:37:16.630291	25.66202937744419	-100.4208750815002	5.02
3718	1	2026-05-19 01:37:16.868968	25.66202937744419	-100.4208750815002	5.02
3719	1	2026-05-19 01:37:17.118358	25.66202937744419	-100.4208750815002	5.02
3720	1	2026-05-19 01:37:17.35924	25.66202937744419	-100.4208750815002	5.02
3721	1	2026-05-19 01:37:17.624444	25.66202937744419	-100.4208750815002	5.02
3722	1	2026-05-19 01:37:17.873874	25.66202937744419	-100.4208750815002	5.02
3723	1	2026-05-19 01:37:18.123325	25.66202937744419	-100.4208750815002	5.02
3724	1	2026-05-19 01:37:18.374067	25.66202937744419	-100.4208750815002	5.02
3725	1	2026-05-19 01:37:18.61911	25.66202937744419	-100.4208750815002	5.02
3726	1	2026-05-19 01:37:18.894367	25.66202937744419	-100.4208750815002	5.02
3727	1	2026-05-19 01:37:19.153259	25.66202937744419	-100.4208750815002	5.02
3728	1	2026-05-19 01:37:19.395083	25.66202937744419	-100.4208750815002	5.02
3729	1	2026-05-19 01:37:19.651876	25.66202937744419	-100.4208750815002	5.02
3730	1	2026-05-19 01:37:19.898625	25.66202598980384	-100.420861670133	5.62
3731	1	2026-05-19 01:37:20.141537	25.66202598980384	-100.420861670133	5.62
3732	1	2026-05-19 01:37:20.386826	25.66202598980384	-100.420861670133	5.62
3733	1	2026-05-19 01:37:20.607793	25.66202598980384	-100.420861670133	5.62
3734	1	2026-05-19 01:37:20.854289	25.66202598980384	-100.420861670133	5.62
3735	1	2026-05-19 01:37:21.099098	25.66202598980384	-100.420861670133	5.62
3736	1	2026-05-19 01:37:21.34383	25.66202598980384	-100.420861670133	5.62
3737	1	2026-05-19 01:37:21.589431	25.66204826869279	-100.4208638753181	4.69
3738	1	2026-05-19 01:37:21.837583	25.66204826869279	-100.4208638753181	4.69
3739	1	2026-05-19 01:37:22.079229	25.66205315257997	-100.4208810403808	4.96
3740	1	2026-05-19 01:37:22.316094	25.66205315257997	-100.4208810403808	4.96
3741	1	2026-05-19 01:37:22.574584	25.66205315257997	-100.4208810403808	4.96
3742	1	2026-05-19 01:37:22.815552	25.66205315257997	-100.4208810403808	4.96
3743	1	2026-05-19 01:37:23.056042	25.66205315257997	-100.4208810403808	4.96
3744	1	2026-05-19 01:37:23.294111	25.66205315257997	-100.4208810403808	4.96
3745	1	2026-05-19 01:37:23.526644	25.66205315257997	-100.4208810403808	4.96
3746	1	2026-05-19 01:37:23.758287	25.66205315257997	-100.4208810403808	4.96
3747	1	2026-05-19 01:37:23.993297	25.66205315257997	-100.4208810403808	4.96
3748	1	2026-05-19 01:37:24.226374	25.66205315257997	-100.4208810403808	4.96
3749	1	2026-05-19 01:37:24.465335	25.66208261942413	-100.4208911693537	7.93
3750	1	2026-05-19 01:37:24.70883	25.66208261942413	-100.4208911693537	7.93
3751	1	2026-05-19 01:37:24.947871	25.66208261942413	-100.4208911693537	7.93
3752	1	2026-05-19 01:37:25.200082	25.66208261942413	-100.4208911693537	7.93
3753	1	2026-05-19 01:37:25.439718	25.66202018756359	-100.4208717725797	5.76
3754	1	2026-05-19 01:37:25.696991	25.66181795229787	-100.4202234158085	7.0
3755	1	2026-05-19 01:37:25.94259	25.66181265028968	-100.4188928607645	6.81
3756	1	2026-05-19 01:37:26.196102	25.66181528115684	-100.4189029267125	6.61
3757	1	2026-05-19 01:37:26.437884	25.66181261022076	-100.4189109811087	6.51
3758	1	2026-05-19 01:37:26.688477	25.6618117325897	-100.4189244170629	6.38
3759	1	2026-05-19 01:37:26.941271	25.66182265867761	-100.418910868128	5.84
3760	1	2026-05-19 01:37:27.207051	25.6618261556636	-100.4189046893935	5.77
3761	1	2026-05-19 01:37:27.453627	25.66182815041893	-100.4188903601834	5.68
3762	1	2026-05-19 01:37:27.718105	25.6618354639011	-100.4189125552942	5.59
3763	1	2026-05-19 01:37:27.968694	25.66183335908885	-100.4189107470295	5.75
3764	1	2026-05-19 01:37:28.218358	25.66184159703692	-100.4189073621508	6.0
3765	1	2026-05-19 01:37:28.462091	25.66183747926368	-100.4189044306346	6.12
3766	1	2026-05-19 01:37:28.707222	25.66184073103965	-100.4189063495895	7.49
3767	1	2026-05-19 01:37:28.977178	25.66183724067094	-100.4188934664374	10.23
3768	1	2026-05-19 01:37:29.223796	25.6618344805361	-100.4188919079334	11.24
3769	1	2026-05-19 01:37:29.464846	25.66175816211043	-100.4188760388073	23.18
3770	1	2026-05-19 01:37:29.698613	25.66176331404475	-100.418868238453	23.13
3771	1	2026-05-19 01:37:29.940797	25.66175576757402	-100.4188695341533	22.39
3772	1	2026-05-19 01:37:30.188704	25.66173369062543	-100.4188695648151	22.53
3773	1	2026-05-19 01:37:30.442357	25.66174694000441	-100.4188451566436	22.38
3774	1	2026-05-19 01:37:30.70867	25.66176201343762	-100.4188479495218	22.59
3775	1	2026-05-19 01:37:30.95971	25.6617764588307	-100.418849278757	23.2
3776	1	2026-05-19 01:37:31.211476	25.66177572019416	-100.4188623833444	22.41
3777	1	2026-05-19 01:37:31.453826	25.66178587892629	-100.418876089956	22.64
3778	1	2026-05-19 01:37:31.697108	25.66177845214807	-100.418893201676	21.3
3779	1	2026-05-19 01:37:31.939533	25.66177373255247	-100.4189326043324	21.31
3780	1	2026-05-19 01:37:32.18251	25.66178019077815	-100.4189830987743	20.83
3781	1	2026-05-19 01:37:32.421898	25.6617658204331	-100.4190862790118	22.09
3782	1	2026-05-19 01:37:32.667184	25.66174895041292	-100.4190679031972	22.74
3783	1	2026-05-19 01:37:32.911147	25.66176113976034	-100.4190440779807	21.71
3784	1	2026-05-19 01:37:33.160384	25.66176638326323	-100.4190252917124	21.17
3785	1	2026-05-19 01:37:33.399646	25.66177618218355	-100.419024076853	20.33
3786	1	2026-05-19 01:37:33.652713	25.66177618218355	-100.419024076853	19.71
3787	1	2026-05-19 01:37:33.892197	25.66177832903922	-100.4190104337898	18.73
3788	1	2026-05-19 01:37:34.138516	25.66177832903922	-100.4190104337898	18.08
3789	1	2026-05-19 01:37:34.385069	25.66177832903922	-100.4190104337898	17.58
3790	1	2026-05-19 01:37:34.623052	25.66170562079284	-100.4190480751538	12.43
3791	1	2026-05-19 01:37:34.901948	25.66171002263985	-100.4190482389833	12.61
3792	1	2026-05-19 01:39:20.534291	25.66171183745392	-100.4190498773491	12.95
3793	1	2026-05-19 01:39:20.7828	25.66171634174239	-100.4190514257607	13.05
3794	1	2026-05-19 01:39:21.027041	25.66172037548823	-100.4190814545352	12.52
3795	1	2026-05-19 01:39:21.278156	25.6617704919329	-100.4190820339697	9.99
3796	1	2026-05-19 01:39:21.52634	25.66178408030065	-100.4190782186179	10.46
3797	1	2026-05-19 01:39:21.779669	25.66181093995505	-100.4190776429962	10.81
3798	1	2026-05-19 01:40:20.505488	25.66185140266344	-100.4190408070981	10.98
3799	1	2026-05-19 01:40:20.760941	25.66186920242272	-100.4185400266547	10.84
3800	1	2026-05-19 01:40:21.019061	25.66190804046907	-100.418495032083	16.69
3801	1	2026-05-19 01:40:21.26916	25.66190807109184	-100.4184854485201	16.1
3802	1	2026-05-19 01:40:21.520553	25.66192575557208	-100.418434857701	14.88
3803	1	2026-05-19 01:41:20.520941	25.6618648765402	-100.418383187201	13.92
3804	1	2026-05-19 01:41:20.801902	25.66174910420381	-100.4183501413489	12.84
3805	1	2026-05-19 01:41:21.067896	25.66154820096871	-100.418325313228	10.92
3806	1	2026-05-19 01:41:21.335857	25.66148407188611	-100.418319129423	9.86
3807	1	2026-05-19 01:41:21.589731	25.6613563580724	-100.41831958871	7.41
3808	1	2026-05-19 01:41:21.848883	25.66114911830226	-100.4183450233529	5.65
3809	1	2026-05-19 01:41:22.105778	25.66103286588946	-100.4184068613924	4.23
3810	1	2026-05-19 01:41:22.355011	25.66098853524407	-100.4184562958325	4.33
3811	1	2026-05-19 01:41:22.604867	25.66094890006899	-100.4185137263292	4.99
3812	1	2026-05-19 01:41:22.860053	25.66092379589004	-100.4185830351569	4.53
3813	1	2026-05-19 01:41:23.115491	25.66091341852584	-100.4186646086837	5.01
3814	1	2026-05-19 01:41:23.379005	25.66091795169433	-100.4187407576307	5.1
3815	1	2026-05-19 01:41:23.63028	25.66093065460378	-100.4188235584176	4.88
3816	1	2026-05-19 01:41:23.884209	25.66094480905189	-100.4189956526185	5.78
3817	1	2026-05-19 01:41:24.13043	25.66093224155524	-100.4191520937729	5.22
3818	1	2026-05-19 01:41:24.380086	25.66084960692897	-100.4192463626612	6.5
3819	1	2026-05-19 01:41:24.623614	25.66070214885791	-100.4192737361571	5.76
3820	1	2026-05-19 01:41:24.872697	25.66054474833117	-100.4192990207465	5.14
3821	1	2026-05-19 01:41:25.118565	25.66046565791038	-100.4193157033624	4.83
3822	1	2026-05-19 01:41:25.369639	25.66022317932086	-100.4193472379142	3.64
3823	1	2026-05-19 01:41:25.633955	25.66004764290879	-100.4193684553608	3.54
3824	1	2026-05-19 01:41:25.881205	25.65996603026568	-100.4193769026629	3.71
3825	1	2026-05-19 01:41:26.137604	25.65980798955996	-100.4193884716483	3.57
3826	1	2026-05-19 01:41:26.386928	25.6596605813306	-100.4194109196896	4.34
3827	1	2026-05-19 01:41:26.626769	25.65958145334998	-100.4194220957219	4.59
3828	1	2026-05-19 01:41:26.876951	25.65950780260356	-100.4194466361527	4.15
3829	1	2026-05-19 01:41:27.13422	25.6594175271302	-100.4195634054507	3.18
3830	1	2026-05-19 01:41:27.379398	25.65940175353558	-100.4196549362863	4.12
3831	1	2026-05-19 01:41:27.636331	25.65940616068385	-100.4198501281406	3.83
3832	1	2026-05-19 01:41:27.892151	25.65940384879146	-100.4199525808188	3.73
3833	1	2026-05-19 01:41:28.148711	25.65939727779371	-100.4201406679666	3.36
3834	1	2026-05-19 01:41:28.419939	25.6593892517333	-100.4202017906121	3.95
3835	1	2026-05-19 01:41:28.667123	25.6593325610284	-100.4202951980534	3.83
3836	1	2026-05-19 01:41:28.916727	25.65926897519568	-100.4203209867334	3.87
3837	1	2026-05-19 01:41:29.169449	25.65917339068217	-100.4203234118211	3.95
3838	1	2026-05-19 01:41:29.424493	25.65908008361345	-100.4203425882638	4.08
3839	1	2026-05-19 01:41:29.66408	25.65904435007719	-100.4203425882645	4.04
3840	1	2026-05-19 01:41:29.914631	25.65901172517044	-100.4203425882647	4.05
3841	1	2026-05-19 01:41:30.166531	25.65895862019886	-100.42026985197	3.96
3842	1	2026-05-19 01:41:30.418008	25.65893322845677	-100.4202342664024	4.0
3843	1	2026-05-19 01:41:30.667118	25.65892783359219	-100.4201617724042	4.03
3844	1	2026-05-19 01:41:30.941274	25.65893898065173	-100.4201004620687	4.0
3845	1	2026-05-19 01:41:31.192182	25.65893554958744	-100.4200202719286	4.06
3846	1	2026-05-19 01:41:31.452014	25.65894167688639	-100.4199310969056	3.93
3847	1	2026-05-19 01:41:31.726558	25.65896296074743	-100.4198302498918	3.82
3848	1	2026-05-19 01:41:31.989115	25.65899796054705	-100.4196315987103	2.91
3849	1	2026-05-19 01:41:32.258735	25.65901275193686	-100.4195490214776	2.88
3850	1	2026-05-19 01:41:32.508911	25.65902381703355	-100.4194572490112	3.07
3851	1	2026-05-19 01:41:32.761695	25.65903051111582	-100.4193643169719	3.02
3852	1	2026-05-19 01:41:33.01973	25.6590452105597	-100.419280172244	4.71
3853	1	2026-05-19 01:41:33.269562	25.65905209127598	-100.4191930786066	4.33
3854	1	2026-05-19 01:41:33.543385	25.65906082173605	-100.4191123551569	5.54
3855	1	2026-05-19 01:41:33.798581	25.65906870417502	-100.4190273003521	4.81
3856	1	2026-05-19 01:41:34.044363	25.65908086307314	-100.4189464305057	5.47
3857	1	2026-05-19 01:41:34.299206	25.65908287493544	-100.418867994451	4.96
3858	1	2026-05-19 01:41:34.549534	25.65909124538344	-100.4187815466611	5.02
3859	1	2026-05-19 01:41:34.822312	25.65910028371987	-100.4186805062988	5.09
3860	1	2026-05-19 01:41:35.074038	25.65913905882936	-100.4183495649212	4.59
3861	1	2026-05-19 01:41:35.319215	25.65916127320299	-100.4182298641355	3.88
3862	1	2026-05-19 01:41:35.567341	25.65923565036286	-100.418011625719	3.9
3863	1	2026-05-19 01:41:35.824026	25.65924725381864	-100.4179087290727	4.87
3864	1	2026-05-19 01:41:36.09588	25.65926164910266	-100.4178007557539	4.2
3865	1	2026-05-19 01:41:36.341661	25.65926666929441	-100.4176863961339	5.57
3866	1	2026-05-19 01:41:36.59242	25.6592702361317	-100.4175733156824	5.87
3867	1	2026-05-19 01:41:36.840237	25.65926143630247	-100.4173381142209	4.32
3868	1	2026-05-19 01:41:37.095852	25.65922809447524	-100.4170741044555	4.66
3869	1	2026-05-19 01:41:37.343538	25.65920184387506	-100.4168070855315	6.04
3870	1	2026-05-19 01:41:37.600709	25.65916970554441	-100.4165334477647	5.2
3871	1	2026-05-19 01:41:37.855162	25.65915836899072	-100.4164183374261	6.27
3872	1	2026-05-19 01:41:38.117739	25.65906771655124	-100.4159714426211	3.63
3873	1	2026-05-19 01:41:38.376903	25.65902915012208	-100.4158651791969	4.04
3874	1	2026-05-19 01:41:38.62618	25.65899367468904	-100.4157685272554	3.14
3875	1	2026-05-19 01:41:38.876807	25.65893059554375	-100.4155441307859	3.3
3876	1	2026-05-19 01:41:39.12295	25.65889701942653	-100.4154245632718	4.07
3877	1	2026-05-19 01:41:39.374463	25.65885852505179	-100.415319197238	3.46
3878	1	2026-05-19 01:41:39.634523	25.65882295010098	-100.4152131976538	3.82
3879	1	2026-05-19 01:41:39.889175	25.65878906149301	-100.4151099813398	3.88
3880	1	2026-05-19 01:41:40.139584	25.65875820508772	-100.4150190293064	4.26
3881	1	2026-05-19 01:41:40.389955	25.65873020623573	-100.4149365385224	3.48
3882	1	2026-05-19 01:41:40.633199	25.65868332704865	-100.4147757982405	3.96
3883	1	2026-05-19 01:41:40.878671	25.65865884196782	-100.4146968611666	4.17
3884	1	2026-05-19 01:41:41.139961	25.65865003037787	-100.4146306091332	4.04
3885	1	2026-05-19 01:41:41.384629	25.65864846657164	-100.4145767663059	4.97
3886	1	2026-05-19 01:41:41.634288	25.65862995924504	-100.4145443374848	4.69
3887	1	2026-05-19 01:41:41.874874	25.65862346113233	-100.4145225705283	4.75
3888	1	2026-05-19 01:41:42.132027	25.65862253276595	-100.4145032656251	4.74
3889	1	2026-05-19 01:41:42.376588	25.65862420417043	-100.4144826086533	5.4
3890	1	2026-05-19 01:41:42.62662	25.65862313950288	-100.4144834842492	5.95
3891	1	2026-05-19 01:43:20.717219	25.65862107194489	-100.4144752841046	6.65
3892	1	2026-05-19 01:43:20.98748	25.65863787277821	-100.4144500550552	8.11
3893	1	2026-05-19 01:43:21.493513	25.65865930825258	-100.4144232999082	8.87
3894	1	2026-05-19 01:43:21.820484	25.65870661805283	-100.4144216087422	11.35
3895	1	2026-05-19 01:43:22.07256	25.65873883961427	-100.4144139351233	11.61
3896	1	2026-05-19 01:43:22.344608	25.65875661297122	-100.414409207835	12.46
3897	1	2026-05-19 01:43:22.593231	25.6586893523235	-100.4144883311143	18.49
3898	1	2026-05-19 01:43:22.839761	25.65884601961397	-100.4144093427465	20.83
3899	1	2026-05-19 01:43:23.095963	25.65892827910649	-100.4146831258797	4.51
3900	1	2026-05-19 01:46:51.079414	25.6589540434848	-100.4147786151975	4.07
3901	1	2026-05-19 01:46:51.351848	25.65899087888078	-100.4148777369431	3.82
3902	1	2026-05-19 01:46:51.619849	25.65901612689125	-100.4149850469283	3.77
3903	1	2026-05-19 01:46:51.875096	25.65915006438635	-100.4154479417472	3.63
3904	1	2026-05-19 01:46:52.137779	25.65918836066595	-100.4155729312644	3.54
3905	1	2026-05-19 01:46:52.384641	25.65922072542968	-100.4157024458483	3.48
3906	1	2026-05-19 01:46:52.637384	25.65925311102699	-100.4158271317176	4.02
3907	1	2026-05-19 01:46:52.887472	25.65929236269802	-100.4159507755899	3.26
3908	1	2026-05-19 01:46:53.136901	25.65932870060964	-100.416083170986	3.19
3909	1	2026-05-19 01:46:53.377526	25.65936584736902	-100.41621622662	4.63
3910	1	2026-05-19 01:46:53.6277	25.65942487610569	-100.41649341135	4.65
3911	1	2026-05-19 01:46:53.871458	25.65946422243314	-100.4167989885714	4.2
3912	1	2026-05-19 01:46:54.112666	25.65947572482104	-100.4169593942052	3.64
3913	1	2026-05-19 01:46:54.363036	25.65947774476222	-100.417123617821	2.7
3914	1	2026-05-19 01:46:54.61061	25.65946092521441	-100.4176908741617	5.12
3915	1	2026-05-19 01:46:54.867028	25.65945399408476	-100.41805703223	2.69
3916	1	2026-05-19 01:46:55.107062	25.65942181939693	-100.4182095080355	3.63
3917	1	2026-05-19 01:46:55.348995	25.65940924453126	-100.4183354227307	4.9
3918	1	2026-05-19 01:46:55.598395	25.65939074440405	-100.4185805634603	5.39
3919	1	2026-05-19 01:46:55.841861	25.65938046366811	-100.4188287184621	5.63
3920	1	2026-05-19 01:46:56.102926	25.65936706050984	-100.4189718442314	6.28
3921	1	2026-05-19 01:46:56.364339	25.65934756020474	-100.4191192831728	8.33
3922	1	2026-05-19 01:46:56.598817	25.65933219523942	-100.4192842686971	5.19
3923	1	2026-05-19 01:46:56.855878	25.65931752144073	-100.4194395219155	6.57
3924	1	2026-05-19 01:46:57.091457	25.6592926986959	-100.4197559534873	8.55
3925	1	2026-05-19 01:46:57.340129	25.65928235681934	-100.4199116291622	8.88
3926	1	2026-05-19 01:46:57.58134	25.6592727673214	-100.4200762091123	8.88
3927	1	2026-05-19 01:46:57.833176	25.65925969462599	-100.4202417470444	8.88
3928	1	2026-05-19 01:46:58.083637	25.65924641619907	-100.4204126626302	8.88
3929	1	2026-05-19 01:46:58.326466	25.65923243937009	-100.4205829370661	8.88
3930	1	2026-05-19 01:46:58.586237	25.65921880949847	-100.4207510085031	8.88
3931	1	2026-05-19 01:46:58.841875	25.6591737549991	-100.4223261215728	15.31
3932	1	2026-05-19 01:46:59.088968	25.659169876075	-100.4224655767039	15.31
3933	1	2026-05-19 01:46:59.365054	25.65919885677548	-100.422552101529	10.2
3934	1	2026-05-19 01:46:59.624094	25.6592210662346	-100.4228683672535	8.88
3935	1	2026-05-19 01:46:59.882076	25.65921335088791	-100.42292181144	8.88
3936	1	2026-05-19 01:47:00.128164	25.65922508259732	-100.4229791712344	3.76
3937	1	2026-05-19 01:47:00.379733	25.65924106275344	-100.4230599941819	3.85
3938	1	2026-05-19 01:47:00.61577	25.65926079644591	-100.4231118129193	4.94
3939	1	2026-05-19 01:47:00.864916	25.65927017070903	-100.4231322029809	5.19
3940	1	2026-05-19 01:47:01.115192	25.65928007841064	-100.4231850401173	5.27
3941	1	2026-05-19 01:47:01.362929	25.659293406308	-100.4232413266249	5.3
3942	1	2026-05-19 01:47:01.609936	25.65936571553002	-100.4233979023768	4.63
3943	1	2026-05-19 01:47:01.842233	25.6594148045956	-100.4234720887892	3.79
3944	1	2026-05-19 01:47:02.09498	25.65962954380861	-100.4234923215737	3.85
3945	1	2026-05-19 01:47:02.334885	25.65972317485091	-100.4234985721147	4.51
3946	1	2026-05-19 01:47:02.575938	25.65981422707992	-100.4234936000342	4.23
3947	1	2026-05-19 01:47:02.816903	25.65996973251753	-100.4234737782696	4.65
3948	1	2026-05-19 01:47:03.054	25.66006306315986	-100.4234531768325	5.33
3949	1	2026-05-19 01:47:03.303459	25.66016727346539	-100.4234359705016	4.32
3950	1	2026-05-19 01:47:03.541945	25.66028434661713	-100.4234140572358	3.92
3951	1	2026-05-19 01:47:03.787022	25.66040405728132	-100.4233948838213	4.35
3952	1	2026-05-19 01:47:04.026794	25.6606660939056	-100.4233532963692	4.86
3953	1	2026-05-19 01:47:04.281422	25.66079987906689	-100.4233376496207	5.79
3954	1	2026-05-19 01:47:04.521264	25.66105131406935	-100.4232875401875	5.32
3955	1	2026-05-19 01:47:05.066634	25.66117308038296	-100.4232630049948	4.26
3956	1	2026-05-19 01:47:05.3093	25.66128033802023	-100.4232463569291	4.03
3957	1	2026-05-19 01:47:05.568828	25.66139120997568	-100.4232274177771	5.27
3958	1	2026-05-19 01:47:05.827069	25.66150215751301	-100.4232085314254	4.03
3959	1	2026-05-19 01:47:06.08518	25.66161118295347	-100.4231876931536	4.18
3960	1	2026-05-19 01:47:06.339573	25.66172127950485	-100.4231780423679	6.06
3961	1	2026-05-19 01:47:06.577672	25.66181926915746	-100.4231596684484	5.84
3962	1	2026-05-19 01:47:06.818057	25.66190930267733	-100.4231412478742	5.74
3963	1	2026-05-19 01:47:07.057371	25.66199585215705	-100.4231056534779	5.33
3964	1	2026-05-19 01:47:07.296126	25.6621031531815	-100.4230853629216	3.8
3965	1	2026-05-19 01:47:07.546736	25.66220974670431	-100.4230664564925	4.25
3966	1	2026-05-19 01:47:07.788844	25.66232425246918	-100.4230460896708	3.68
3967	1	2026-05-19 01:47:08.038605	25.6624395350803	-100.4230262578475	3.45
3968	1	2026-05-19 01:47:08.280397	25.66254245208664	-100.423010388244	4.59
3969	1	2026-05-19 01:47:08.523684	25.66263758277251	-100.4229958859529	5.3
3970	1	2026-05-19 01:47:08.76857	25.66270758843034	-100.4229851585776	3.95
3971	1	2026-05-19 01:47:09.018641	25.66275762401257	-100.4229776085147	3.71
3972	1	2026-05-19 01:47:09.274414	25.66279585543338	-100.4229785647515	3.28
3973	1	2026-05-19 01:47:09.528588	25.66297522173863	-100.4229464333608	3.2
3974	1	2026-05-19 01:47:09.775697	25.66305781682797	-100.4229280810049	3.53
3975	1	2026-05-19 01:47:10.033911	25.6631495894281	-100.4229055946579	3.09
3976	1	2026-05-19 01:47:10.298079	25.66323163337717	-100.4228740657257	3.03
3977	1	2026-05-19 01:47:10.542477	25.66334984788898	-100.4228436890197	3.6
3978	1	2026-05-19 01:47:10.774125	25.66345682040301	-100.4228015030414	2.99
3979	1	2026-05-19 01:47:11.042853	25.66356122304851	-100.4227511727572	4.7
3980	1	2026-05-19 01:47:11.291828	25.66377730003017	-100.422607105815	2.65
3981	1	2026-05-19 01:47:11.536851	25.66388374389192	-100.422517398036	2.56
3982	1	2026-05-19 01:47:11.791709	25.66398938513867	-100.4224217396957	4.02
3983	1	2026-05-19 01:47:12.039791	25.66420619513969	-100.4222241527576	3.08
3984	1	2026-05-19 01:47:12.289482	25.66461212054828	-100.4218677781292	4.01
3985	1	2026-05-19 01:47:12.53972	25.66475415962314	-100.4217479277359	3.81
3986	1	2026-05-19 01:47:12.78825	25.66494013278194	-100.4215765145116	3.98
3987	1	2026-05-19 01:47:13.045023	25.66502061446612	-100.421499061715	4.26
3988	1	2026-05-19 01:47:13.286071	25.66510531870173	-100.4214221137337	3.47
3989	1	2026-05-19 01:47:13.535033	25.66520427766872	-100.4213779258715	3.67
3990	1	2026-05-19 01:47:13.783268	25.66526866490464	-100.4212702832422	4.18
3991	1	2026-05-19 01:47:14.029813	25.66538550794321	-100.4211191947575	3.37
3992	1	2026-05-19 01:47:14.270859	25.66540859720945	-100.4210217460563	3.52
3993	1	2026-05-19 01:47:14.513127	25.66542930387908	-100.4209121905631	4.61
3994	1	2026-05-19 01:47:14.767546	25.66546803292504	-100.4206481810148	3.94
3995	1	2026-05-19 01:47:15.022263	25.66548558375595	-100.4205022071743	3.06
3996	1	2026-05-19 01:47:15.323113	25.6655033687731	-100.4203506097506	3.06
3997	1	2026-05-19 01:47:15.586842	25.66556796365045	-100.4198487705518	4.28
3998	1	2026-05-19 01:47:15.860546	25.66563193983936	-100.4194975438621	3.33
3999	1	2026-05-19 01:49:20.476527	25.66565633147853	-100.4193220371226	3.32
4000	1	2026-05-19 01:49:20.759116	25.66570580081548	-100.418973360405	4.95
4001	1	2026-05-19 01:49:21.013576	25.6657300361934	-100.4187917212889	4.45
4002	1	2026-05-19 01:49:21.270415	25.66575040667438	-100.4186133932207	3.32
4003	1	2026-05-19 01:51:20.56505	25.66575365412528	-100.4184274287442	3.14
4004	1	2026-05-19 01:51:21.029445	25.66577125965935	-100.4182453495783	4.39
4005	1	2026-05-19 01:51:21.307396	25.66580184124538	-100.417878812912	3.18
4006	1	2026-05-19 01:51:21.582473	25.66579624280085	-100.4176926577056	3.13
4007	1	2026-05-19 01:51:21.834257	25.66579015164621	-100.4175095476663	3.68
4008	1	2026-05-19 01:51:22.093965	25.66578279414526	-100.4173277666995	2.99
4009	1	2026-05-19 01:51:22.346674	25.66578251942001	-100.4171609970402	3.88
4010	1	2026-05-19 01:51:22.597382	25.66579048870678	-100.4169981639729	4.25
4011	1	2026-05-19 01:51:22.848074	25.66579157877788	-100.4168344610603	3.81
4012	1	2026-05-19 01:51:23.115528	25.66579308875592	-100.4166656236432	3.96
4013	1	2026-05-19 01:51:23.361362	25.66579263321873	-100.4164745064505	3.8
4014	1	2026-05-19 01:51:23.637733	25.66576480517713	-100.4159174889506	3.66
4015	1	2026-05-19 01:51:23.895242	25.66575485375306	-100.4157195800565	4.63
4016	1	2026-05-19 01:51:24.185301	25.66574828239921	-100.4155099806018	4.42
4017	1	2026-05-19 01:51:24.425794	25.66574460914748	-100.4152927818622	4.35
4018	1	2026-05-19 01:51:24.658545	25.66574762217551	-100.4150784216901	3.76
4019	1	2026-05-19 01:51:24.915582	25.66575401610877	-100.4148701889203	3.64
4020	1	2026-05-19 01:51:25.188918	25.66577006746854	-100.4146579216297	4.58
4021	1	2026-05-19 01:51:25.434109	25.66579124937084	-100.4144376170262	3.45
4022	1	2026-05-19 01:51:25.67866	25.66582351332217	-100.4142159019869	3.47
4023	1	2026-05-19 01:51:25.932834	25.66585884593493	-100.4140090307598	4.76
4024	1	2026-05-19 01:51:26.185213	25.66592689580335	-100.4135613470317	4.38
4025	1	2026-05-19 01:51:26.437637	25.66595834545116	-100.4133324240117	4.1
4026	1	2026-05-19 01:51:26.687333	25.66599667500638	-100.4131046675692	3.94
4027	1	2026-05-19 01:51:26.938904	25.6660722789426	-100.4126379350804	4.59
4028	1	2026-05-19 01:51:27.182056	25.66610753334204	-100.4124040654945	3.4
4029	1	2026-05-19 01:51:27.419588	25.66614912949215	-100.4121626842425	5.33
4030	1	2026-05-19 01:51:27.671854	25.66618629985493	-100.4119213917016	5.42
4031	1	2026-05-19 01:51:28.001238	25.66625115765897	-100.4114389425216	3.33
4032	1	2026-05-19 01:51:28.246394	25.6662858046932	-100.4111932674659	3.22
4033	1	2026-05-19 01:51:28.488692	25.66636858532515	-100.4106983571907	3.1
4034	1	2026-05-19 01:51:28.752031	25.66640454429857	-100.4104430881448	3.11
4035	1	2026-05-19 01:51:29.011301	25.66645147311005	-100.410184708026	3.22
4036	1	2026-05-19 01:51:29.261447	25.66648847351016	-100.4099276452216	3.26
4037	1	2026-05-19 01:51:29.512226	25.66652489803607	-100.4096744000365	3.33
4038	1	2026-05-19 01:51:29.763629	25.66655928828164	-100.4094175992656	3.32
4039	1	2026-05-19 01:51:30.030099	25.66661172116704	-100.4091697901057	3.25
4040	1	2026-05-19 01:51:30.285206	25.66666498023322	-100.4089244456908	3.17
4041	1	2026-05-19 01:51:30.533643	25.66673438646774	-100.4086806706058	3.11
4042	1	2026-05-19 01:51:30.787057	25.66690032955545	-100.4082058022387	2.97
4043	1	2026-05-19 01:51:31.037039	25.66709602145678	-100.4077479921102	3.16
4044	1	2026-05-19 01:51:31.315905	25.6672123615542	-100.4075296103206	3.23
4045	1	2026-05-19 01:51:31.566014	25.66734016380515	-100.4073248527257	3.29
4046	1	2026-05-19 01:51:31.831127	25.6674705014053	-100.407114584417	3.29
4047	1	2026-05-19 01:51:32.07228	25.66760833859437	-100.406896797045	3.16
4048	1	2026-05-19 01:51:32.315791	25.66787908000118	-100.4064509193495	3.82
4049	1	2026-05-19 01:51:32.561847	25.66801899098095	-100.4062186475275	3.12
4050	1	2026-05-19 01:51:32.801711	25.66816360670522	-100.4059832693749	3.08
4051	1	2026-05-19 01:51:33.041605	25.66830909163186	-100.4057533998636	3.06
4052	1	2026-05-19 01:51:33.2893	25.66844941547916	-100.4055234819692	3.03
4053	1	2026-05-19 01:51:33.536718	25.66872117380408	-100.4050552712763	3.13
4054	1	2026-05-19 01:51:33.790067	25.6688893021634	-100.4048479284684	3.28
4055	1	2026-05-19 01:51:34.039235	25.66903136171713	-100.40462151599	3.45
4056	1	2026-05-19 01:51:34.287634	25.66917836111798	-100.4043917528077	4.42
4057	1	2026-05-19 01:51:34.544103	25.66932876438462	-100.4041504257946	3.94
4058	1	2026-05-19 01:51:34.799295	25.66947837085842	-100.4039166671596	3.28
4059	1	2026-05-19 01:51:35.044301	25.66962683835693	-100.4036749169521	3.48
4060	1	2026-05-19 01:51:35.289723	25.66992764077101	-100.4032055990988	3.88
4061	1	2026-05-19 01:51:35.535767	25.67007062131054	-100.4029747535978	4.33
4062	1	2026-05-19 01:51:35.791317	25.67019190563488	-100.4027566235419	4.6
4063	1	2026-05-19 01:51:36.041287	25.6703015009654	-100.4025403964594	3.35
4064	1	2026-05-19 01:51:36.287257	25.67039414894223	-100.4023217097894	3.76
4065	1	2026-05-19 01:51:36.530245	25.67047616549456	-100.402099584708	3.4
4066	1	2026-05-19 01:51:36.781495	25.67054743795677	-100.4018729667378	3.28
4067	1	2026-05-19 01:51:37.026561	25.6706818219357	-100.4014227149819	4.14
4068	1	2026-05-19 01:51:37.266875	25.67074001012364	-100.4011832282308	3.47
4069	1	2026-05-19 01:51:37.503625	25.67085705258476	-100.4007058086359	3.72
4070	1	2026-05-19 01:51:37.764688	25.6709210925008	-100.4004861736043	3.19
4071	1	2026-05-19 01:51:38.024116	25.6709738852898	-100.400254256032	3.16
4072	1	2026-05-19 01:51:38.26866	25.67102991125799	-100.400020845666	3.58
4073	1	2026-05-19 01:51:38.504571	25.67107601447047	-100.3997896421388	3.01
4074	1	2026-05-19 01:51:38.760298	25.67115608368778	-100.3993208084382	3.33
4075	1	2026-05-19 01:51:39.015926	25.67118227638635	-100.3990994706289	4.31
4076	1	2026-05-19 01:51:39.264238	25.67120645852782	-100.3988930241491	5.24
4077	1	2026-05-19 01:51:39.507027	25.67120534470663	-100.3987058290916	4.35
4078	1	2026-05-19 01:51:39.75806	25.6712031200508	-100.3984084357546	4.26
4079	1	2026-05-19 01:51:40.00945	25.67115560260477	-100.398189397342	3.0
4080	1	2026-05-19 01:51:40.274689	25.67110978969162	-100.3980606694535	3.14
4081	1	2026-05-19 01:51:40.523989	25.67108184806339	-100.3979305786978	3.31
4082	1	2026-05-19 01:51:40.779967	25.67104301476785	-100.3978069914043	3.95
4083	1	2026-05-19 01:51:41.025216	25.67102609671354	-100.3976717230726	3.17
4084	1	2026-05-19 01:51:41.276446	25.67102672346013	-100.3975320145051	3.17
4085	1	2026-05-19 01:51:41.548475	25.6710379933023	-100.397228490413	3.39
4086	1	2026-05-19 01:51:41.791097	25.67106760103388	-100.3970679560701	3.23
4087	1	2026-05-19 01:51:42.034465	25.67110559482697	-100.3965486146107	3.01
4088	1	2026-05-19 01:51:42.273899	25.67110894287859	-100.3963678924831	2.99
4089	1	2026-05-19 01:51:42.524893	25.67110920541641	-100.3961815548824	3.0
4090	1	2026-05-19 01:51:42.782214	25.67110437283753	-100.3959908148564	3.63
4091	1	2026-05-19 01:51:43.036484	25.67110501798519	-100.3957986958959	3.13
4092	1	2026-05-19 01:51:43.276544	25.67110345688214	-100.3956126816313	3.14
4093	1	2026-05-19 01:51:43.523352	25.6710966808728	-100.3954350807677	3.18
4094	1	2026-05-19 01:51:43.771022	25.67099651601662	-100.3950978922607	3.46
4095	1	2026-05-19 01:51:44.04194	25.67095633555415	-100.394928067192	3.31
4096	1	2026-05-19 01:51:44.431112	25.67088025645201	-100.3947679529993	4.15
4097	1	2026-05-19 01:51:44.822543	25.67082976043624	-100.3944403243136	3.12
4098	1	2026-05-19 01:54:20.510356	25.67083978544197	-100.3942686318535	2.73
4099	1	2026-05-19 01:54:20.764795	25.6708765209622	-100.394101783196	2.77
4100	1	2026-05-19 01:54:21.016306	25.67092335248103	-100.3939310344613	2.4
4101	1	2026-05-19 01:54:21.258714	25.67097862766547	-100.3937581870006	2.37
4102	1	2026-05-19 01:54:21.50098	25.67110439440995	-100.3933819316775	3.16
4103	1	2026-05-19 01:54:21.746994	25.67123034195711	-100.3929887177572	2.37
4104	1	2026-05-19 01:54:21.997171	25.67129143072097	-100.3927845039731	2.88
4105	1	2026-05-19 01:54:22.295049	25.67135937607058	-100.3925925062856	2.44
4106	1	2026-05-19 01:54:22.539763	25.67141993801525	-100.3924036331149	2.2
4107	1	2026-05-19 01:54:22.776948	25.67146256652455	-100.3922146650423	2.45
4108	1	2026-05-19 01:54:23.023402	25.67147835247842	-100.3920199665015	3.46
4109	1	2026-05-19 01:56:20.467231	25.67146872332544	-100.3918218344923	4.28
4110	1	2026-05-19 01:56:20.693188	25.67143986956365	-100.3916261371438	3.13
4111	1	2026-05-19 01:56:20.920886	25.67135750210872	-100.3912163419235	3.36
4112	1	2026-05-19 01:56:21.151374	25.67130843765825	-100.3910074498237	2.94
4113	1	2026-05-19 01:56:21.380739	25.67125902557026	-100.3907930078493	3.46
4114	1	2026-05-19 01:56:21.610563	25.67121144847805	-100.3905894690058	2.77
4115	1	2026-05-19 01:56:21.842892	25.67116471099922	-100.3903894226648	2.96
4116	1	2026-05-19 01:56:22.069567	25.67110319293151	-100.3902093147835	4.48
4117	1	2026-05-19 01:56:22.306441	25.67102401119469	-100.3900176723551	3.48
4118	1	2026-05-19 01:56:22.526764	25.67093631030358	-100.3898321862519	3.25
4119	1	2026-05-19 01:56:22.760121	25.67085079592106	-100.3896488907011	2.87
4120	1	2026-05-19 01:56:22.993456	25.67075515609038	-100.389461925297	2.63
4121	1	2026-05-19 01:56:23.226632	25.67065910159018	-100.3892644355972	2.26
4122	1	2026-05-19 01:56:23.467015	25.67055782470163	-100.3890688247074	3.44
4123	1	2026-05-19 01:56:23.701973	25.6704564973731	-100.3888688720008	2.69
4124	1	2026-05-19 01:56:23.935651	25.67036063198234	-100.3886656897172	2.91
4125	1	2026-05-19 01:56:24.164647	25.67015920784725	-100.388267490934	3.66
4126	1	2026-05-19 01:56:24.395585	25.67006410191923	-100.3880653382556	2.44
4127	1	2026-05-19 01:56:24.625023	25.66996528611363	-100.3878672823318	2.22
4128	1	2026-05-19 01:56:24.865604	25.66986736381604	-100.3876665918967	3.21
4129	1	2026-05-19 01:56:25.091349	25.66976517292144	-100.387476587887	2.61
4130	1	2026-05-19 01:56:25.326586	25.66966615125798	-100.3872879554907	3.93
4131	1	2026-05-19 01:56:25.555316	25.66956766960721	-100.3871069683003	3.53
4132	1	2026-05-19 01:56:25.792613	25.6694800533797	-100.3869311657719	3.44
4133	1	2026-05-19 01:56:26.034646	25.66932349080281	-100.3865935954874	2.81
4134	1	2026-05-19 01:56:26.258362	25.66925828558575	-100.3864291887035	2.49
4135	1	2026-05-19 01:56:26.500171	25.66920471347697	-100.3862648638557	2.43
4136	1	2026-05-19 01:56:26.759651	25.66919023945974	-100.3860837257583	6.66
4137	1	2026-05-19 01:56:27.011018	25.66919291546071	-100.3858946619975	3.75
4138	1	2026-05-19 01:56:27.300023	25.6692224900935	-100.3855087840053	4.79
4139	1	2026-05-19 01:56:27.553417	25.66923426991531	-100.3853036261521	4.26
4140	1	2026-05-19 01:56:27.802526	25.66927733849054	-100.384924176015	2.94
4141	1	2026-05-19 01:56:28.047393	25.6693015167669	-100.3847516741522	3.09
4142	1	2026-05-19 01:56:28.295038	25.66936391140527	-100.3844511005321	6.11
4143	1	2026-05-19 01:56:28.546915	25.66937905936278	-100.3841499207755	3.82
4144	1	2026-05-19 01:56:28.787126	25.66930741547182	-100.383840187301	3.32
4145	1	2026-05-19 01:56:29.037738	25.66924827130082	-100.3837155584068	3.05
4146	1	2026-05-19 01:56:29.291443	25.66915854306137	-100.3835882101088	2.73
4147	1	2026-05-19 01:56:29.553878	25.66907908380314	-100.383447216384	3.02
4148	1	2026-05-19 01:56:29.815503	25.66898289076355	-100.3833245317946	2.58
4149	1	2026-05-19 01:56:30.065347	25.66888905014045	-100.3831981018885	4.04
4150	1	2026-05-19 01:56:30.318052	25.66879748940407	-100.3830661351803	2.83
4151	1	2026-05-19 01:56:30.564038	25.66855051218572	-100.3826886653821	5.07
4152	1	2026-05-19 01:56:30.835862	25.66847767893989	-100.3825475773947	3.3
4153	1	2026-05-19 01:56:31.085776	25.66841527273342	-100.3823961312649	2.55
4154	1	2026-05-19 01:56:31.338353	25.66827650101643	-100.3820970284841	4.28
4155	1	2026-05-19 01:56:31.603121	25.66819069188504	-100.381946019032	3.97
4156	1	2026-05-19 01:56:31.858714	25.66806257858972	-100.3816309321268	2.41
4157	1	2026-05-19 01:56:32.12012	25.66792473736204	-100.3812979807491	4.22
4158	1	2026-05-19 01:56:32.37351	25.66789818002214	-100.3811151694451	3.39
4159	1	2026-05-19 01:56:32.612412	25.6678502844346	-100.3809338928466	4.78
4160	1	2026-05-19 01:56:32.859344	25.66781075694012	-100.3807452955452	4.51
4161	1	2026-05-19 01:56:33.1086	25.66778173460844	-100.3805552390173	3.5
4162	1	2026-05-19 01:56:33.36244	25.66770795121207	-100.3801945131013	5.76
4163	1	2026-05-19 01:56:33.604616	25.66769720015775	-100.3800194639069	8.18
4164	1	2026-05-19 01:56:33.846636	25.66769343726832	-100.3798476763555	7.21
4165	1	2026-05-19 01:56:34.111295	25.66769055052871	-100.3795055574777	6.61
4166	1	2026-05-19 01:56:34.364894	25.66769081614072	-100.3792971043627	4.48
4167	1	2026-05-19 01:56:34.677655	25.66769393261752	-100.3791008140575	5.13
4168	1	2026-05-19 01:56:34.926552	25.66769773159469	-100.3789024681614	5.37
4169	1	2026-05-19 01:56:35.182508	25.66769853637981	-100.3785331580318	5.13
4170	1	2026-05-19 01:56:35.442804	25.6677131853891	-100.3783549564603	4.96
4171	1	2026-05-19 01:56:35.695678	25.66772313689365	-100.377817496	4.94
4172	1	2026-05-19 01:56:35.95654	25.66773604656765	-100.3774320748427	3.86
4173	1	2026-05-19 01:56:36.21006	25.66772472383226	-100.3772338679914	3.62
4174	1	2026-05-19 01:56:36.458465	25.66772782332925	-100.3770250487949	3.77
4175	1	2026-05-19 01:56:36.702164	25.66773114890015	-100.3768150296676	5.32
4176	1	2026-05-19 01:56:36.957136	25.66773445522736	-100.3766062259928	4.58
4177	1	2026-05-19 01:56:37.207179	25.66775472672082	-100.3763990183429	4.61
4178	1	2026-05-19 01:56:37.459453	25.6677512346014	-100.3761842056959	4.39
4179	1	2026-05-19 01:56:37.716132	25.66775020224541	-100.3759700604671	3.9
4180	1	2026-05-19 01:56:37.993394	25.66773840445191	-100.3757600189722	4.45
4181	1	2026-05-19 01:56:38.296901	25.66772368514722	-100.3755301480063	5.34
4182	1	2026-05-19 01:56:38.568563	25.66771000651778	-100.375310877327	3.7
4183	1	2026-05-19 01:56:38.818038	25.66768120602216	-100.3748749953402	3.01
4184	1	2026-05-19 01:56:39.083463	25.6676662197906	-100.3746524486302	3.2
4185	1	2026-05-19 01:56:39.336408	25.66766425834783	-100.3744382702231	2.97
4186	1	2026-05-19 01:56:39.583105	25.66766641650344	-100.3742238950293	3.09
4187	1	2026-05-19 01:56:39.852871	25.66768445248439	-100.3740078333291	3.91
4188	1	2026-05-19 01:56:40.102709	25.66771091891483	-100.3737923478687	3.32
4189	1	2026-05-19 01:56:40.353343	25.66773818339973	-100.3735785256711	4.18
4190	1	2026-05-19 01:56:40.602453	25.66775226578492	-100.3733724221348	3.38
4191	1	2026-05-19 01:56:40.849291	25.66779768709183	-100.3731675469533	2.81
4192	1	2026-05-19 01:56:41.106718	25.66784715121398	-100.3727831405321	5.73
4193	1	2026-05-19 01:56:41.346999	25.66792253051398	-100.3722159564948	4.82
4194	1	2026-05-19 01:56:41.601779	25.66793186701386	-100.3720210146457	4.24
4195	1	2026-05-19 01:56:41.855449	25.66795261654952	-100.3718298713275	3.26
4196	1	2026-05-19 01:56:42.101633	25.66796928512585	-100.3716556994936	3.61
4197	1	2026-05-19 01:56:42.355101	25.66799369977167	-100.371464317195	5.19
4198	1	2026-05-19 01:59:20.536113	25.66799806517088	-100.3712850696739	4.79
4199	1	2026-05-19 01:59:20.806423	25.6679980940605	-100.3710994970073	5.01
4200	1	2026-05-19 01:59:21.093906	25.66799914842693	-100.3709140210414	3.12
4201	1	2026-05-19 01:59:21.367676	25.66799773394123	-100.3707223683461	3.82
4202	1	2026-05-19 01:59:21.636022	25.667994497817	-100.3705245290546	4.49
4203	1	2026-05-19 01:59:21.896129	25.66798843877593	-100.3703324895599	6.96
4204	1	2026-05-19 01:59:22.165074	25.6679729399519	-100.3699588332086	6.62
4205	1	2026-05-19 01:59:22.434979	25.66796968053164	-100.3697810034329	4.02
4206	1	2026-05-19 01:59:22.693357	25.66795848917423	-100.3696047904267	5.08
4207	1	2026-05-19 01:59:22.948548	25.66795024644729	-100.3694533509853	5.85
4208	1	2026-05-19 01:59:23.214077	25.66793483481158	-100.3692945596282	7.79
4209	1	2026-05-19 01:59:23.488426	25.6679240074535	-100.3691248585666	4.76
4210	1	2026-05-19 01:59:23.755718	25.66790418996529	-100.3687857767779	3.66
4211	1	2026-05-19 01:59:24.015009	25.66790061823288	-100.3686221521759	3.74
4212	1	2026-05-19 02:00:20.662377	25.66786800664969	-100.3684373507597	3.28
4213	1	2026-05-19 02:00:20.904789	25.66785689477132	-100.3682546817776	4.82
4214	1	2026-05-19 02:00:21.26784	25.66785149472278	-100.3678786982173	5.29
4215	1	2026-05-19 02:00:21.505907	25.66786065848773	-100.3676915276667	9.72
4216	1	2026-05-19 02:00:21.764255	25.66791181331408	-100.3673157737475	4.6
4217	1	2026-05-19 02:01:20.547276	25.66793444725168	-100.3671268238085	6.19
4218	1	2026-05-19 02:01:20.801541	25.66795883909306	-100.3669490730129	5.5
4219	1	2026-05-19 02:01:21.040962	25.66800368119467	-100.3665608043388	3.66
4220	1	2026-05-19 02:01:21.291508	25.66803286757802	-100.3663859680723	3.47
4221	1	2026-05-19 02:01:21.539151	25.66807720457138	-100.3662286521056	5.77
4222	1	2026-05-19 02:01:21.795516	25.66813304631523	-100.3660796996885	5.44
4223	1	2026-05-19 02:01:22.03909	25.66821155442756	-100.3659450868743	3.73
4224	1	2026-05-19 02:01:22.287486	25.66831009473693	-100.3658210793471	4.28
4225	1	2026-05-19 02:01:22.530612	25.66840654354504	-100.3657027905313	5.55
4226	1	2026-05-19 02:01:22.772897	25.66849718275713	-100.3655776606711	3.95
4227	1	2026-05-19 02:01:23.014811	25.66878369161157	-100.3653227077564	3.35
4228	1	2026-05-19 02:01:23.265679	25.66890137969657	-100.3652698744757	3.87
4229	1	2026-05-19 02:01:23.514611	25.66913500578714	-100.3651155135802	2.93
4230	1	2026-05-19 02:01:23.759929	25.66924481841417	-100.3650122091658	3.36
4231	1	2026-05-19 02:01:24.014136	25.66935208492178	-100.3649005953002	2.6
4232	1	2026-05-19 02:01:24.26916	25.66946842201498	-100.3647801562663	3.25
4233	1	2026-05-19 02:01:24.516901	25.66971661864036	-100.3645279782203	3.49
4234	1	2026-05-19 02:01:24.758182	25.66984378333745	-100.3643978424789	2.55
4235	1	2026-05-19 02:01:25.011632	25.66997845994002	-100.3642611329506	2.69
4236	1	2026-05-19 02:01:25.256234	25.67012323006096	-100.3641318278087	2.23
4237	1	2026-05-19 02:01:25.504374	25.67027611215185	-100.3640028391771	2.14
4238	1	2026-05-19 02:01:25.755816	25.67043347870469	-100.3638722955523	5.4
4239	1	2026-05-19 02:01:26.01018	25.67058855345005	-100.3637438392843	4.53
4240	1	2026-05-19 02:01:26.262777	25.67074365472136	-100.363621768941	3.0
4241	1	2026-05-19 02:01:26.533321	25.67104019717168	-100.3633539165723	2.6
4242	1	2026-05-19 02:01:26.790553	25.67130571063149	-100.3630717985689	2.34
4243	1	2026-05-19 02:01:27.043307	25.67143537874551	-100.3629396195212	2.56
4244	1	2026-05-19 02:01:27.300117	25.67156035362915	-100.3628072515597	2.75
4245	1	2026-05-19 02:01:27.549489	25.67167867801933	-100.3626758447894	3.73
4246	1	2026-05-19 02:01:27.819291	25.67178661082531	-100.3625472843473	3.86
4247	1	2026-05-19 02:01:28.07064	25.67206863357612	-100.3621499561252	3.33
4248	1	2026-05-19 02:01:28.322855	25.672278532875	-100.3617049642166	3.75
4249	1	2026-05-19 02:01:28.571041	25.67245149996551	-100.3612388863309	3.04
4250	1	2026-05-19 02:01:28.816276	25.67249685126092	-100.3611022639222	2.97
4251	1	2026-05-19 02:01:29.088075	25.67256488648544	-100.3608095189899	3.38
4252	1	2026-05-19 02:01:29.340718	25.67258744720043	-100.3606629677856	2.72
4253	1	2026-05-19 02:01:29.587398	25.67260532069999	-100.360525581123	2.33
4254	1	2026-05-19 02:01:29.851265	25.67263646955495	-100.3602521075197	3.97
4255	1	2026-05-19 02:01:30.176667	25.67264017465443	-100.3601148495367	3.7
4256	1	2026-05-19 02:01:30.456069	25.67262140298318	-100.3599744593982	3.47
4257	1	2026-05-19 02:01:30.707815	25.67261715627689	-100.3598579001006	3.42
4258	1	2026-05-19 02:01:30.953111	25.67261214481906	-100.3597560012904	3.78
4259	1	2026-05-19 02:01:31.20218	25.67260390860734	-100.3596900726503	4.04
4260	1	2026-05-19 02:01:31.445696	25.67260231584826	-100.3596407165841	3.15
4261	1	2026-05-19 02:01:31.691773	25.67260179351867	-100.3596397357732	3.05
4262	1	2026-05-19 02:01:31.937976	25.67260118679758	-100.3596478083405	3.05
4263	1	2026-05-19 02:01:32.186867	25.67260109865123	-100.3596503204633	3.34
4264	1	2026-05-19 02:01:32.424492	25.67260109865123	-100.3596503204633	3.29
4265	1	2026-05-19 02:01:32.666533	25.67260109865123	-100.3596503204633	3.63
4266	1	2026-05-19 02:01:32.923792	25.67260109865123	-100.3596503204633	3.59
4267	1	2026-05-19 02:01:33.169887	25.67260109865123	-100.3596503204633	3.47
4268	1	2026-05-19 02:01:33.411665	25.67260109865123	-100.3596503204633	3.36
4269	1	2026-05-19 02:01:33.657071	25.67260109865123	-100.3596503204633	3.37
4270	1	2026-05-19 02:01:33.903319	25.67260109865123	-100.3596503204633	3.38
4271	1	2026-05-19 02:01:34.163892	25.67260109865123	-100.3596503204633	3.29
4272	1	2026-05-19 02:01:34.410967	25.67260109865123	-100.3596503204633	3.18
4273	1	2026-05-19 02:01:34.662842	25.67260109865123	-100.3596503204633	3.25
4274	1	2026-05-19 02:01:34.908898	25.67260109865123	-100.3596503204633	3.31
4275	1	2026-05-19 02:01:35.158784	25.67260109865123	-100.3596503204633	3.34
4276	1	2026-05-19 02:01:35.432989	25.67260109865123	-100.3596503204633	3.25
4277	1	2026-05-19 02:01:35.694938	25.67260109865123	-100.3596503204633	3.19
4278	1	2026-05-19 02:01:35.94934	25.67260109865123	-100.3596503204633	3.13
4279	1	2026-05-19 02:01:36.20116	25.67260109865123	-100.3596503204633	3.07
4280	1	2026-05-19 02:01:36.457026	25.67260109865123	-100.3596503204633	3.04
4281	1	2026-05-19 02:01:36.706503	25.67260109865123	-100.3596503204633	2.99
4282	1	2026-05-19 02:01:36.966331	25.6726049926486	-100.3596677696127	3.05
4283	1	2026-05-19 02:01:37.216682	25.6726049653306	-100.3596672248213	3.0
4284	1	2026-05-19 02:01:37.466685	25.6726049653306	-100.3596672248213	2.93
4285	1	2026-05-19 02:01:37.724283	25.6726049653306	-100.3596672248213	3.01
4286	1	2026-05-19 02:01:37.989764	25.6726049653306	-100.3596672248213	3.02
4287	1	2026-05-19 02:01:38.240509	25.6726049653306	-100.3596672248213	3.0
4288	1	2026-05-19 02:01:38.486558	25.6726049653306	-100.3596672248213	3.0
4289	1	2026-05-19 02:01:38.732398	25.6726049653306	-100.3596672248213	2.95
4290	1	2026-05-19 02:01:38.98618	25.6726049653306	-100.3596672248213	2.94
4291	1	2026-05-19 02:01:39.26193	25.6726049653306	-100.3596672248213	2.94
4292	1	2026-05-19 02:01:39.510347	25.6726049653306	-100.3596672248213	2.96
4293	1	2026-05-19 02:01:39.757372	25.6726049653306	-100.3596672248213	2.97
4294	1	2026-05-19 02:01:40.009792	25.6726049653306	-100.3596672248213	2.99
4295	1	2026-05-19 02:01:40.264209	25.67260774855803	-100.359657646027	2.95
4296	1	2026-05-19 02:01:40.526089	25.6726043496766	-100.3596273979248	2.91
4297	1	2026-05-19 02:01:40.784216	25.67259841532265	-100.3595815712548	2.89
4298	1	2026-05-19 02:04:20.489118	25.67259347501295	-100.3595110847016	2.84
4299	1	2026-05-19 02:04:20.735862	25.67258441070139	-100.359430313782	2.8
4300	1	2026-05-19 02:04:20.982645	25.67255886289453	-100.3593337309092	2.83
4301	1	2026-05-19 02:04:21.234801	25.67254007708405	-100.3592351559752	2.87
4302	1	2026-05-19 02:04:21.487205	25.67246803575009	-100.3590132148982	2.99
4303	1	2026-05-19 02:04:21.725403	25.67238350628353	-100.3587557532088	4.65
4304	1	2026-05-19 02:04:21.965897	25.67233664859753	-100.3585975405359	4.8
4305	1	2026-05-19 02:04:22.210921	25.67227573529109	-100.3584528771279	3.65
4306	1	2026-05-19 02:04:22.457458	25.67213524633909	-100.357979119158	4.45
4307	1	2026-05-19 02:04:22.713118	25.67208199869373	-100.3578042973565	3.89
4308	1	2026-05-19 02:04:22.977322	25.67203693631973	-100.35764221732	3.56
4309	1	2026-05-19 02:04:23.264242	25.67192357908483	-100.3572859977217	3.41
4310	1	2026-05-19 02:04:23.506852	25.6718662800563	-100.3571165964514	3.83
4311	1	2026-05-19 02:04:23.756504	25.67180945874028	-100.3569470836556	4.79
4312	1	2026-05-19 02:04:24.019625	25.67175372235755	-100.3567879224154	3.96
4313	1	2026-05-19 02:04:24.267576	25.67169502246546	-100.3566332633727	4.17
4314	1	2026-05-19 02:04:24.539194	25.67165023519849	-100.3564703770283	3.71
4315	1	2026-05-19 02:04:24.792231	25.67161249139652	-100.3563084307221	4.14
4316	1	2026-05-19 02:04:25.043886	25.67157591685162	-100.3561497076086	4.53
4317	1	2026-05-19 02:04:25.30326	25.67152697207364	-100.3558515789113	3.67
4318	1	2026-05-19 02:04:25.545935	25.67153001928719	-100.3557028456054	6.05
4319	1	2026-05-19 02:04:25.798145	25.67155420098833	-100.3555350109922	6.01
4320	1	2026-05-19 02:04:26.044534	25.67157426789717	-100.3553574664519	4.11
4321	1	2026-05-19 02:04:26.282465	25.67159180203956	-100.3551732747541	7.16
4322	1	2026-05-19 02:04:26.705625	25.67166602608457	-100.354592840094	3.64
4323	1	2026-05-19 02:04:26.962783	25.67162861354024	-100.3542025495654	3.0
4324	1	2026-05-19 02:04:27.21381	25.67160323427101	-100.3540066409718	2.84
4325	1	2026-05-19 02:06:20.536116	25.67147501325761	-100.3534184821247	5.25
4326	1	2026-05-19 02:06:20.789285	25.67142770471938	-100.3532228556484	9.55
4327	1	2026-05-19 02:06:21.115374	25.67132749076419	-100.3528900203109	8.56
4328	1	2026-05-19 02:06:21.362191	25.67126312953409	-100.3527425448892	6.35
4329	1	2026-05-19 02:06:21.609305	25.67119010518522	-100.3526132166382	5.14
4330	1	2026-05-19 02:06:21.853328	25.67106560454517	-100.3524419468832	3.76
4331	1	2026-05-19 02:06:22.103462	25.67096024225805	-100.3523046639596	4.31
4332	1	2026-05-19 02:06:22.360467	25.67087337967499	-100.3521623867822	4.86
4333	1	2026-05-19 02:06:22.607648	25.67079246609942	-100.3520064555991	6.85
4334	1	2026-05-19 02:06:22.859467	25.67068736625808	-100.3518737311373	4.98
4335	1	2026-05-19 02:06:23.103417	25.67059189879369	-100.3517381987515	4.34
4336	1	2026-05-19 02:06:23.368113	25.67050360303118	-100.3515893280683	5.06
4337	1	2026-05-19 02:06:23.61801	25.67041735629936	-100.351444514447	3.21
4338	1	2026-05-19 02:06:23.871328	25.67032995640913	-100.3512983748207	3.51
4339	1	2026-05-19 02:06:24.127584	25.67024478776648	-100.3511356583571	3.11
4340	1	2026-05-19 02:06:24.385787	25.6701724231525	-100.3509775731194	3.61
4341	1	2026-05-19 02:06:24.638043	25.67009272307359	-100.3508175036528	3.45
4342	1	2026-05-19 02:06:24.889278	25.67004765654082	-100.3506416679514	4.38
4343	1	2026-05-19 02:06:25.193488	25.66989503550449	-100.350126775656	5.68
4344	1	2026-05-19 02:06:25.450828	25.66984729649091	-100.3499533423419	5.28
4345	1	2026-05-19 02:06:25.711193	25.66974358100365	-100.3495930077811	3.16
4346	1	2026-05-19 02:06:25.996688	25.66969636421024	-100.3494170662818	4.41
4347	1	2026-05-19 02:06:26.256921	25.66965184196558	-100.3492503900677	6.62
4348	1	2026-05-19 02:06:26.512168	25.66960146068886	-100.3490860632041	7.46
4349	1	2026-05-19 02:06:26.770463	25.66953505807161	-100.3489230081725	7.8
4350	1	2026-05-19 02:06:27.038053	25.66948043415754	-100.3487578163053	7.92
4351	1	2026-05-19 02:06:27.279618	25.6694274044822	-100.3485972619513	8.69
4352	1	2026-05-19 02:06:27.522776	25.66938804693521	-100.3484408155551	8.28
4353	1	2026-05-19 02:06:27.772005	25.66934323053072	-100.3482863604223	8.11
4354	1	2026-05-19 02:06:28.027811	25.66929325038976	-100.3481419855976	8.05
4355	1	2026-05-19 02:06:28.28049	25.6692542347119	-100.3480030006447	8.02
4356	1	2026-05-19 02:06:28.553898	25.66920548393669	-100.3478904568461	8.44
4357	1	2026-05-19 02:06:28.80304	25.66917053098995	-100.3477823014318	8.22
4358	1	2026-05-19 02:06:29.056833	25.66914568568297	-100.3476926392065	8.12
4359	1	2026-05-19 02:06:29.298454	25.66912527354429	-100.3476233134411	8.07
4360	1	2026-05-19 02:06:29.54892	25.66910507296972	-100.3475660385486	9.2
4361	1	2026-05-19 02:06:29.809053	25.66908882275053	-100.3475180136534	9.59
4362	1	2026-05-19 02:06:30.070791	25.669062080547	-100.3474352974023	9.06
4363	1	2026-05-19 02:06:30.3196	25.66903668630119	-100.3473551562217	8.79
4364	1	2026-05-19 02:06:30.574546	25.66902399899048	-100.3473144085558	8.7
4365	1	2026-05-19 02:06:30.832698	25.66901168369568	-100.3472738972457	8.63
4366	1	2026-05-19 02:06:31.110218	25.66900170111343	-100.3472430704861	8.58
4367	1	2026-05-19 02:06:31.360822	25.66899140176604	-100.3472085272284	8.53
4368	1	2026-05-19 02:06:31.612102	25.66898081412698	-100.3471721854186	8.49
4369	1	2026-05-19 02:06:31.861974	25.66896961209887	-100.3471371960854	8.45
4370	1	2026-05-19 02:06:32.112462	25.66895750926901	-100.3471006730944	8.42
4371	1	2026-05-19 02:06:32.364936	25.66894504136433	-100.3470622937242	8.4
4372	1	2026-05-19 02:06:32.613083	25.66893571826861	-100.3470305728028	8.37
4373	1	2026-05-19 02:06:32.866639	25.66893072567909	-100.3470122385891	8.35
4374	1	2026-05-19 02:06:33.115297	25.66892423683768	-100.3469915186234	8.34
4375	1	2026-05-19 02:06:33.366538	25.66892257086448	-100.3469860714171	8.33
4376	1	2026-05-19 02:06:33.634449	25.66892058155315	-100.3469794060447	8.38
4377	1	2026-05-19 02:06:34.160088	25.66891803658557	-100.3469708506975	8.36
4378	1	2026-05-19 02:06:34.406874	25.66891229237859	-100.346953620402	8.33
4379	1	2026-05-19 02:06:34.662074	25.66891148611849	-100.3469492617933	8.32
4380	1	2026-05-19 02:06:34.935865	25.66890959845779	-100.3469435407865	8.3
4381	1	2026-05-19 02:06:35.185607	25.66890756205731	-100.346937229653	8.29
4382	1	2026-05-19 02:06:35.435262	25.66890750915825	-100.3469379275671	8.27
4383	1	2026-05-19 02:06:35.67613	25.66890347566109	-100.3469245943261	8.26
4384	1	2026-05-19 02:06:35.93526	25.66889997157854	-100.3469108080749	8.25
4385	1	2026-05-19 02:06:36.210915	25.66890086328114	-100.3469118618499	8.45
4386	1	2026-05-19 02:06:36.457148	25.66889881681907	-100.3469044473337	8.43
4387	1	2026-05-19 02:06:36.703222	25.66889457151733	-100.3468924343502	8.38
4388	1	2026-05-19 02:06:37.121782	25.66889204105908	-100.3468824993837	8.43
4389	1	2026-05-19 02:06:37.371887	25.66888833149947	-100.3468699812199	8.41
4390	1	2026-05-19 02:06:37.622871	25.66888568996426	-100.3468611465677	8.39
4391	1	2026-05-19 02:06:37.950148	25.66888254481216	-100.3468508413588	8.37
4392	1	2026-05-19 02:06:38.226322	25.66888175805776	-100.3468490217223	8.35
4393	1	2026-05-19 02:06:38.496056	25.66888162470685	-100.3468468551966	8.34
4394	1	2026-05-19 02:06:38.769418	25.66888156745146	-100.3468471191347	8.32
4395	1	2026-05-19 02:06:39.03338	25.66888155204411	-100.346847163003	8.3
4396	1	2026-05-19 02:06:39.287439	25.66888155204411	-100.346847163003	8.29
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
21	12	2026-05-17 12:39:59.550822	1
22	12	2026-05-17 12:59:35.968938	1
23	12	2026-05-17 13:06:14.486825	1
24	12	2026-05-17 13:07:15.780725	1
25	12	2026-05-17 13:08:06.281659	1
26	12	2026-05-17 13:08:08.78919	1
27	12	2026-05-17 13:08:10.643449	1
28	12	2026-05-17 13:14:03.028161	1
29	12	2026-05-17 13:14:10.668848	1
30	12	2026-05-17 14:04:02.066532	1
31	12	2026-05-17 14:06:22.532207	1
32	12	2026-05-17 14:09:07.979438	1
33	12	2026-05-17 14:16:49.970858	1
34	12	2026-05-17 14:17:51.270267	1
35	12	2026-05-17 14:18:20.898344	1
36	12	2026-05-17 14:27:51.481176	1
37	12	2026-05-17 14:32:12.668904	1
38	12	2026-05-17 14:32:39.16097	1
39	12	2026-05-18 13:35:22.135414	1
40	12	2026-05-18 13:38:19.612724	1
41	12	2026-05-18 21:27:24.417452	1
42	12	2026-05-18 21:27:39.098911	1
43	12	2026-05-18 21:42:49.908078	1
44	12	2026-05-18 21:42:59.548367	1
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
22	21	9	2026-05-17 14:16:57.62747	2026-05-17 14:27:55.36769	3	1	5	\N
23	21	9	2026-05-17 14:32:22.070984	2026-05-17 14:32:45.154803	3	1	5	\N
24	21	9	2026-05-18 13:38:14.89184	2026-05-18 13:38:43.643232	3	1	5	\N
25	21	7	2026-05-18 21:27:32.336796	2026-05-18 21:28:07.954203	3	2	5	\N
26	21	7	2026-05-18 21:42:53.285023	2026-05-18 21:43:01.797136	3	2	5	\N
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

SELECT pg_catalog.setval('public.auditoria_id_auditoria_seq', 163, true);


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

SELECT pg_catalog.setval('public.evento_beacon_id_evento_beacon_seq', 33, true);


--
-- Name: evento_gps_id_evento_gps_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evento_gps_id_evento_gps_seq', 4396, true);


--
-- Name: evento_nfc_id_evento_nfc_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.evento_nfc_id_evento_nfc_seq', 44, true);


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

SELECT pg_catalog.setval('public.uso_clinico_equipo_id_uso_clinico_seq', 26, true);


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
-- Name: PROCEDURE sp_cerrar_traslado(IN p_id_traslado integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.sp_cerrar_traslado(IN p_id_traslado integer) TO hospital_user;


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
-- Name: TABLE v_ambulancias_gps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_ambulancias_gps TO hospital_user;


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
-- Name: TABLE v_traslados_activos; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_traslados_activos TO hospital_user;


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

\unrestrict FrQF3yEITzUTB6UUzyeG2wCh50eGHKfTSSHirfOgQM2lNfZKEBPoGXmXrLo1310

