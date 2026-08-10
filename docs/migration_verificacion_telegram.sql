-- ============================================
-- Verificación por Telegram para la app
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Tabla de verificaciones
CREATE TABLE IF NOT EXISTS verificaciones_app (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo text UNIQUE NOT NULL,
  telegram_user_id bigint,
  telegram_username text,
  dispositivo_id text NOT NULL,
  verificado boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '10 minutes')
);

-- Índices
CREATE INDEX idx_verificaciones_codigo ON verificaciones_app(codigo);
CREATE INDEX idx_verificaciones_dispositivo ON verificaciones_app(dispositivo_id);
CREATE INDEX idx_verificaciones_telegram ON verificaciones_app(telegram_user_id);

-- RLS: permitir acceso público para crear y consultar verificaciones
ALTER TABLE verificaciones_app ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Público puede crear verificaciones"
  ON verificaciones_app FOR INSERT TO anon
  WITH CHECK (true);

CREATE POLICY "Público puede consultar sus verificaciones"
  ON verificaciones_app FOR SELECT TO anon
  USING (true);

CREATE POLICY "Público puede actualizar verificaciones (bot)"
  ON verificaciones_app FOR UPDATE TO anon
  USING (true)
  WITH CHECK (true);

-- ============================================
-- RPC: Crear código de verificación
-- Llamada desde la app Flutter
-- ============================================
CREATE OR REPLACE FUNCTION crear_verificacion(p_dispositivo_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_codigo text;
BEGIN
  -- Generar código aleatorio de 6 chars (letras+números)
  v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  
  -- Limpiar verificaciones expiradas del mismo dispositivo
  DELETE FROM verificaciones_app 
  WHERE dispositivo_id = p_dispositivo_id AND (verificado = false OR expires_at < now());
  
  -- Insertar nueva verificación
  INSERT INTO verificaciones_app (codigo, dispositivo_id, expires_at)
  VALUES (v_codigo, p_dispositivo_id, now() + interval '10 minutes');
  
  RETURN v_codigo;
END;
$$;

-- ============================================
-- RPC: Verificar código (llamada desde el bot)
-- ============================================
CREATE OR REPLACE FUNCTION verificar_codigo_telegram(
  p_codigo text,
  p_telegram_user_id bigint,
  p_telegram_username text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_record verificaciones_app%ROWTYPE;
BEGIN
  -- Buscar código válido (no expirado, no verificado)
  SELECT * INTO v_record 
  FROM verificaciones_app 
  WHERE codigo = upper(p_codigo) 
    AND verificado = false 
    AND expires_at > now();
  
  IF NOT FOUND THEN
    RETURN 'CODIGO_INVALIDO';
  END IF;
  
  -- Marcar como verificado
  UPDATE verificaciones_app 
  SET verificado = true, 
      telegram_user_id = p_telegram_user_id,
      telegram_username = p_telegram_username
  WHERE id = v_record.id;
  
  RETURN 'OK';
END;
$$;

-- ============================================
-- RPC: Consultar si un código fue verificado (polling desde la app)
-- ============================================
CREATE OR REPLACE FUNCTION consultar_verificacion(p_codigo text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_record verificaciones_app%ROWTYPE;
BEGIN
  SELECT * INTO v_record 
  FROM verificaciones_app 
  WHERE codigo = upper(p_codigo);
  
  IF NOT FOUND THEN
    RETURN json_build_object('estado', 'NO_ENCONTRADO');
  END IF;
  
  IF v_record.expires_at < now() AND NOT v_record.verificado THEN
    RETURN json_build_object('estado', 'EXPIRADO');
  END IF;
  
  IF v_record.verificado THEN
    RETURN json_build_object(
      'estado', 'VERIFICADO',
      'telegram_user_id', v_record.telegram_user_id,
      'telegram_username', v_record.telegram_username
    );
  END IF;
  
  RETURN json_build_object('estado', 'PENDIENTE');
END;
$$;

-- ============================================
-- RPC: Obtener verificación activa de un dispositivo
-- (para saber si ya está verificado sin re-verificar)
-- ============================================
CREATE OR REPLACE FUNCTION obtener_verificacion_activa(p_dispositivo_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_record verificaciones_app%ROWTYPE;
BEGIN
  SELECT * INTO v_record 
  FROM verificaciones_app 
  WHERE dispositivo_id = p_dispositivo_id 
    AND verificado = true
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF NOT FOUND THEN
    RETURN json_build_object('verificado', false);
  END IF;
  
  RETURN json_build_object(
    'verificado', true,
    'telegram_user_id', v_record.telegram_user_id,
    'telegram_username', v_record.telegram_username
  );
END;
$$;
