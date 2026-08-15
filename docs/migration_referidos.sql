-- ============================================
-- Sistema de referidos / códigos de invitación
-- Ejecutar en Supabase SQL Editor
-- Propósito: rastrear quién invitó a quién para
--   futuras funcionalidades premium o monetización.
-- ============================================

-- ============================================
-- 1. Tabla de códigos de invitación
--    Un usuario tiene UN código permanente.
--    Múltiples personas pueden usarlo.
-- ============================================
CREATE TABLE IF NOT EXISTS codigos_invitacion (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_user_id text UNIQUE NOT NULL,  -- dueño del código
  codigo          text UNIQUE NOT NULL,    -- e.g. "GT-A1B2C3D4"
  creado_en       timestamptz DEFAULT now(),
  activo          boolean DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_codigos_invitacion_codigo
  ON codigos_invitacion (codigo);

CREATE INDEX IF NOT EXISTS idx_codigos_invitacion_user
  ON codigos_invitacion (telegram_user_id);

-- ============================================
-- 2. Tabla de referidos
--    Registro de cada usuario que se unió
--    usando el código de alguien.
-- ============================================
CREATE TABLE IF NOT EXISTS referidos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo          text NOT NULL,           -- código que usó el referido
  referidor_id    text NOT NULL,           -- telegram_user_id de quien invitó
  referido_id     text NOT NULL,           -- telegram_user_id del nuevo usuario
  fecha_registro  timestamptz DEFAULT now(),
  activo          boolean DEFAULT true,
  metadata        jsonb DEFAULT '{}',      -- para futuro: plan, eventos, etc.
  UNIQUE (referido_id)                     -- un usuario solo puede ser referido una vez
);

CREATE INDEX IF NOT EXISTS idx_referidos_referidor
  ON referidos (referidor_id);

CREATE INDEX IF NOT EXISTS idx_referidos_referido
  ON referidos (referido_id);

CREATE INDEX IF NOT EXISTS idx_referidos_codigo
  ON referidos (codigo);

-- ============================================
-- 3. RPC: generar_codigo_invitacion
--    Crea o devuelve el código existente del usuario.
--    Idempotente: llamar N veces devuelve siempre el mismo.
-- ============================================
CREATE OR REPLACE FUNCTION generar_codigo_invitacion(p_telegram_user_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_codigo text;
BEGIN
  -- Si ya tiene código, devolverlo
  SELECT codigo INTO v_codigo
  FROM codigos_invitacion
  WHERE telegram_user_id = p_telegram_user_id AND activo = true;

  IF v_codigo IS NOT NULL THEN
    RETURN v_codigo;
  END IF;

  -- Generar nuevo código único: GT-{8 chars aleatorios en mayúsculas}
  LOOP
    v_codigo := 'GT-' || upper(substr(
      replace(encode(gen_random_bytes(6), 'base64'), '/', 'X'),
      1, 8
    ));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM codigos_invitacion WHERE codigo = v_codigo);
  END LOOP;

  INSERT INTO codigos_invitacion (telegram_user_id, codigo)
  VALUES (p_telegram_user_id, v_codigo);

  RETURN v_codigo;
END;
$$;

-- ============================================
-- 4. RPC: registrar_referido
--    Vincula un referido a su referidor.
--    Se llama al completar la verificación TG.
--    Idempotente: si el referido ya existe, no falla.
-- ============================================
CREATE OR REPLACE FUNCTION registrar_referido(
  p_codigo        text,
  p_referido_id   text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referidor_id text;
  v_ya_referido  boolean;
BEGIN
  -- Verificar que el código existe y está activo
  SELECT telegram_user_id INTO v_referidor_id
  FROM codigos_invitacion
  WHERE codigo = p_codigo AND activo = true;

  IF v_referidor_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'CODIGO_INVALIDO');
  END IF;

  -- No puede referirse a sí mismo
  IF v_referidor_id = p_referido_id THEN
    RETURN json_build_object('ok', false, 'error', 'AUTOREFERIDO');
  END IF;

  -- Verificar si ya fue referido por alguien
  SELECT EXISTS (
    SELECT 1 FROM referidos WHERE referido_id = p_referido_id
  ) INTO v_ya_referido;

  IF v_ya_referido THEN
    RETURN json_build_object('ok', false, 'error', 'YA_REFERIDO');
  END IF;

  -- Registrar referido
  INSERT INTO referidos (codigo, referidor_id, referido_id)
  VALUES (p_codigo, v_referidor_id, p_referido_id);

  RETURN json_build_object(
    'ok', true,
    'referidor_id', v_referidor_id
  );
END;
$$;

-- ============================================
-- 5. RPC: get_mis_referidos
--    Devuelve los referidos de un usuario
--    con fecha y estado de actividad.
-- ============================================
CREATE OR REPLACE FUNCTION get_mis_referidos(p_telegram_user_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_codigo    text;
  v_referidos json;
  v_total     int;
BEGIN
  -- Obtener código del usuario
  SELECT codigo INTO v_codigo
  FROM codigos_invitacion
  WHERE telegram_user_id = p_telegram_user_id;

  -- Contar y listar referidos
  SELECT
    COUNT(*)::int,
    json_agg(json_build_object(
      'referido_id', referido_id,
      'fecha', fecha_registro,
      'activo', activo
    ) ORDER BY fecha_registro DESC)
  INTO v_total, v_referidos
  FROM referidos
  WHERE referidor_id = p_telegram_user_id;

  RETURN json_build_object(
    'codigo',    COALESCE(v_codigo, ''),
    'total',     COALESCE(v_total, 0),
    'referidos', COALESCE(v_referidos, '[]'::json)
  );
END;
$$;
