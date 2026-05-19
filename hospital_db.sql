--
-- PostgreSQL database dump
--

\restrict tVxEyvwVndcvrzOne1YKvbjBt1guK8mhVmMnScHKngXJAG7f8ruoxgOegGZWd2c

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

SELECT pg_catalog.setval('public.evento_gps_id_evento_gps_seq', 1451, true);


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

\unrestrict tVxEyvwVndcvrzOne1YKvbjBt1guK8mhVmMnScHKngXJAG7f8ruoxgOegGZWd2c

