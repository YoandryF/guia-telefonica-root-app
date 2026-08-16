-- Fix: cambiar formato de código de GT-XXXXXXXX a GT_XXXXXXXX
-- Telegram solo acepta [A-Za-z0-9_] en el parámetro start
-- El guión (-) hace que Telegram trunque el parámetro

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

  -- Generar nuevo código único: GT_{8 chars alfanuméricos en mayúsculas}
  -- Sin guión — Telegram solo acepta [A-Za-z0-9_] en parámetro start
  LOOP
    v_codigo := 'GT_' || upper(substr(
      replace(replace(encode(gen_random_bytes(6), 'base64'), '/', 'X'), '+', 'Y'),
      1, 8
    ));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM codigos_invitacion WHERE codigo = v_codigo);
  END LOOP;

  INSERT INTO codigos_invitacion (telegram_user_id, codigo)
  VALUES (p_telegram_user_id, v_codigo);

  RETURN v_codigo;
END;
$$;

-- Actualizar códigos existentes que tengan guión
-- (migrar GT-XXXXXXXX -> GT_XXXXXXXX)
UPDATE codigos_invitacion
SET codigo = replace(codigo, '-', '_')
WHERE codigo LIKE 'GT-%';
