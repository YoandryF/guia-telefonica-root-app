-- ============================================
-- Analytics para admin
-- Ejecutar en Supabase SQL Editor
-- ============================================

CREATE OR REPLACE FUNCTION get_analytics_admin()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_top_reportadores json;
  v_top_reportados    json;
  v_top_fallas        json;
  v_top_avaladores    json;
  v_top_trust         json;
  v_peor_trust        json;
BEGIN

  -- Top 10 usuarios que más reportan (aprobados + pendientes)
  SELECT json_agg(r) INTO v_top_reportadores FROM (
    SELECT
      reportado_por AS identificador,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE estado = 'revisado') AS aprobados,
      COUNT(*) FILTER (WHERE estado = 'pendiente') AS pendientes
    FROM reportes
    WHERE reportado_por IS NOT NULL
    GROUP BY reportado_por
    ORDER BY total DESC
    LIMIT 10
  ) r;

  -- Top 10 números más reportados (por score_riesgo)
  SELECT json_agg(r) INTO v_top_reportados FROM (
    SELECT
      c.telefono,
      c.nombre || ' ' || c.apellido AS nombre,
      c.score_riesgo,
      c.verificado,
      COUNT(rep.id) AS total_reportes,
      COUNT(rep.id) FILTER (WHERE rep.estado = 'revisado') AS aprobados
    FROM contactos c
    LEFT JOIN reportes rep ON rep.contacto_id = c.id
    WHERE c.tiene_reportes = true AND c.estado = 'aprobado'
    GROUP BY c.id, c.telefono, c.nombre, c.apellido, c.score_riesgo, c.verificado
    ORDER BY c.score_riesgo DESC, total_reportes DESC
    LIMIT 10
  ) r;

  -- Top 10 usuarios con más fallas (reportes desestimados)
  SELECT json_agg(r) INTO v_top_fallas FROM (
    SELECT
      reportado_por AS identificador,
      COUNT(*) AS desestimados,
      COUNT(*) FILTER (WHERE estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE estado = 'resuelto')::numeric /
        NULLIF(COUNT(*), 0) * 100, 1
      ) AS pct_fallas
    FROM reportes
    WHERE reportado_por IS NOT NULL
      AND estado IN ('revisado', 'resuelto')
    GROUP BY reportado_por
    HAVING COUNT(*) FILTER (WHERE estado = 'resuelto') > 0
    ORDER BY desestimados DESC, pct_fallas DESC
    LIMIT 10
  ) r;

  -- Top 10 usuarios con más avales enviados
  SELECT json_agg(r) INTO v_top_avaladores FROM (
    SELECT
      avalado_por AS identificador,
      COUNT(*) AS total_avales,
      COUNT(*) FILTER (WHERE estado = 'aprobado') AS aprobados,
      COUNT(*) FILTER (WHERE estado = 'pendiente') AS pendientes,
      COUNT(*) FILTER (WHERE estado = 'rechazado') AS rechazados
    FROM avales
    WHERE avalado_por IS NOT NULL
    GROUP BY avalado_por
    ORDER BY total_avales DESC
    LIMIT 10
  ) r;

  -- Top 10 usuarios con mejor trust score
  SELECT json_agg(r) INTO v_top_trust FROM (
    SELECT
      reportado_por AS identificador,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE estado = 'revisado')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE estado IN ('revisado','resuelto')), 0) * 100, 1
      ) AS trust_pct
    FROM reportes
    WHERE reportado_por IS NOT NULL
    GROUP BY reportado_por
    HAVING COUNT(*) FILTER (WHERE estado IN ('revisado','resuelto')) >= 3
    ORDER BY trust_pct DESC, aprobados DESC
    LIMIT 10
  ) r;

  -- Top 10 usuarios con peor trust score
  SELECT json_agg(r) INTO v_peor_trust FROM (
    SELECT
      reportado_por AS identificador,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE estado = 'revisado')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE estado IN ('revisado','resuelto')), 0) * 100, 1
      ) AS trust_pct
    FROM reportes
    WHERE reportado_por IS NOT NULL
    GROUP BY reportado_por
    HAVING COUNT(*) FILTER (WHERE estado IN ('revisado','resuelto')) >= 3
    ORDER BY trust_pct ASC, total DESC
    LIMIT 10
  ) r;

  RETURN json_build_object(
    'top_reportadores', COALESCE(v_top_reportadores, '[]'::json),
    'top_reportados',   COALESCE(v_top_reportados,   '[]'::json),
    'top_fallas',       COALESCE(v_top_fallas,        '[]'::json),
    'top_avaladores',   COALESCE(v_top_avaladores,    '[]'::json),
    'top_trust',        COALESCE(v_top_trust,         '[]'::json),
    'peor_trust',       COALESCE(v_peor_trust,        '[]'::json)
  );
END;
$$;
