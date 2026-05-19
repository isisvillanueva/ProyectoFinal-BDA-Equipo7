-- =====================================================================
-- STORED PROCEDURES - hospital_db
-- Extraídos de: hospital_db__3_.sql
-- Total: 21 procedimientos
-- =====================================================================

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