-- =======================
-- 1. Inserciones Válidas

  --Prueba 1
  BEGIN;
  INSERT INTO public.persona (id_persona, nombre_persona, apellido_persona, correo_persona)
  VALUES (200, 'Laura', 'Mendoza', 'l.mendoza@hospital.com');
  ROLLBACK;

  --Prueba 2
  BEGIN;
  INSERT INTO public.equipo (
      id_equipo, codigo_interno, nombre_equipo,
      id_modelo, numero_serie, id_tipo_equipo,
      id_criticidad_equipo, id_estado_equipo,
      id_ubicacion_administrativa_actual, activo_equipo
  )   
  VALUES (200, 'EQ-200', 'Bomba de Prueba', 2, 'SN-TEST-2026-200', 2, 2, 1, 1, true);
  ROLLBACK;

-- ==================

 --2. Violaciones de FK

  --Prueba 3
  BEGIN;
  INSERT INTO public.equipo (
      id_equipo, codigo_interno, nombre_equipo,
      id_modelo, numero_serie, id_tipo_equipo,
      id_criticidad_equipo, id_estado_equipo,
      id_ubicacion_administrativa_actual, activo_equipo
  )   
  VALUES (201, 'EQ-201', 'Equipo Fantasma', 999, 'SN-TEST-FK-001', 1, 1, 1, 1, true);
  ROLLBACK;

  --Prueba 4
  BEGIN;
  INSERT INTO public.dispositivo_nfc (id_nfc, codigo_uid_nfc, id_equipo, activo_nfc)
  VALUES (200, 'NFC-UID-FAKE-001', 999, true);
  ROLLBACK;

-- =======================
-- 3. Violaciones de CHECK

  --Prueba 5
  BEGIN;
  INSERT INTO public.dispositivo_beacon (id_beacon, uuid_beacon, major_beacon, minor_beacon, activo_beacon, id_zona_beacon)
  VALUES (200, 'BEACON-UUID-TEST-NEG', -1, 5, true, 1);
  ROLLBACK;

  --Prueba 6
  BEGIN;
  INSERT INTO public.asignacion_equipo (
      id_asignacion, id_equipo, id_persona_responsable,
      id_ubicacion, fecha_inicio_asignacion, fecha_fin_asignacion, id_estado_asignacion
  )
  VALUES (200, 6, 3, 2, '2026-06-01 08:00:00', '2026-05-01 08:00:00', 2);
  ROLLBACK;


-- ==============
4. Validaciones de UNIQUE

 -- Prueba 7
  BEGIN;
  INSERT INTO public.persona (id_persona, nombre_persona, apellido_persona, correo_persona)
  VALUES (201, 'Copia', 'Admin', 'admin@hospital.com');
  ROLLBACK;
  
  -- Prueba 8
  BEGIN;
  INSERT INTO public.ambulancia (id_ambulancia, codigo_ambulancia, placa, id_estado_ambulancia, activo_ambulancia)
  VALUES (200, 'AMB-001', 'NLE-999-Z', 1, true);
  ROLLBACK;




