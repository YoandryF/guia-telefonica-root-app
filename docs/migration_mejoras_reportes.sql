-- ============================================
-- Mejoras reportes: nota_admin + notificaciones
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Nota del admin al resolver
ALTER TABLE reportes ADD COLUMN IF NOT EXISTS nota_admin text;

-- RPC: obtener reportes del usuario (para "Mis Reportes")
CREATE OR REPLACE FUNCTION get_mis_reportes(p_telegram_user_id text)
RETURNS TABLE (
  id uuid,
  contacto_id uuid,
  motivo text,
  descripcion text,
  estado text,
  fecha_reporte timestamptz,
  nota_admin text,
  evidencia_msg_id bigint,
  contacto_nombre text,
  contacto_telefono text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.id, r.contacto_id, r.motivo, r.descripcion, r.estado,
    r.fecha_reporte, r.nota_admin, r.evidencia_msg_id,
    c.nombre || ' ' || c.apellido as contacto_nombre,
    c.telefono as contacto_telefono
  FROM reportes r
  JOIN contactos c ON c.id = r.contacto_id
  WHERE r.reportado_por = p_telegram_user_id
  ORDER BY r.fecha_reporte DESC;
END;
$$;

-- RPC: stats del reportador (para panel admin)
CREATE OR REPLACE FUNCTION get_stats_reportador(p_identificador text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total INT;
  v_aprobados INT;
  v_desestimados INT;
  v_pendientes INT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM reportes WHERE reportado_por = p_identificador;
  SELECT COUNT(*) INTO v_aprobados FROM reportes WHERE reportado_por = p_identificador AND estado = 'revisado';
  SELECT COUNT(*) INTO v_desestimados FROM reportes WHERE reportado_por = p_identificador AND estado = 'resuelto';
  SELECT COUNT(*) INTO v_pendientes FROM reportes WHERE reportado_por = p_identificador AND estado = 'pendiente';

  RETURN json_build_object(
    'total', v_total,
    'aprobados', v_aprobados,
    'desestimados', v_desestimados,
    'pendientes', v_pendientes,
    'tasa_aprobacion', CASE WHEN (v_aprobados + v_desestimados) > 0
      THEN round((v_aprobados::float / (v_aprobados + v_desestimados) * 100)::numeric, 0)
      ELSE 0 END
  );
END;
$$;

-- RPC: contar pendientes (para alerta admin)
CREATE OR REPLACE FUNCTION contar_reportes_pendientes()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT COUNT(*)::int FROM reportes WHERE estado = 'pendiente';
$$;
