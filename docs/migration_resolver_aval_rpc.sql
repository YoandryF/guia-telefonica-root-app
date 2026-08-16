-- RPC para aprobar/rechazar avales (admin)
-- SECURITY DEFINER bypasea RLS
CREATE OR REPLACE FUNCTION resolver_aval(
  p_aval_id      uuid,
  p_estado       text,  -- 'aprobado' | 'rechazado'
  p_revisado_por text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_estado NOT IN ('aprobado', 'rechazado') THEN
    RETURN json_build_object('ok', false, 'error', 'Estado inválido');
  END IF;

  UPDATE avales SET
    estado         = p_estado,
    revisado_por   = p_revisado_por,
    fecha_revision = now()
  WHERE id = p_aval_id;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'Aval no encontrado');
  END IF;

  RETURN json_build_object('ok', true);
END;
$$;
