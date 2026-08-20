-- ============================================================
-- RPC: get_contactos_sync — Keyset pagination sin OFFSET
-- Elimina el timeout en sync masiva de 900k contactos.
--
-- Problema anterior:
--   .range(offset, offset+499) → Postgres escanea y descarta
--   los primeros N filas → O(N) → timeout al 8000-9000 reg.
--
-- Solución keyset:
--   WHERE (nombre, id) > (cursor_nombre, cursor_id)
--   ORDER BY nombre, id
--   LIMIT page_size
--   → Postgres usa idx_contactos_nombre directamente → O(log N)
--   → Tiempo constante sin importar la página
-- ============================================================

CREATE OR REPLACE FUNCTION get_contactos_sync(
  p_cursor_nombre text    DEFAULT NULL,
  p_cursor_id     uuid    DEFAULT NULL,
  p_page_size     integer DEFAULT 500
)
RETURNS TABLE (
  id              uuid,
  nombre          text,
  apellido        text,
  telefono        text,
  direccion       text,
  ci              text,
  estado          text,
  categoria_id    uuid,
  verificado      boolean,
  score_riesgo    double precision,
  tiene_reportes  boolean,
  pais            text,
  provincia       text,
  municipio       text,
  fecha_creacion  timestamp,
  fecha_aprobacion timestamp
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_cursor_nombre IS NULL THEN
    -- Primera página: sin cursor
    RETURN QUERY
      SELECT
        c.id, c.nombre, c.apellido, c.telefono, c.direccion, c.ci,
        c.estado, c.categoria_id, c.verificado, c.score_riesgo,
        c.tiene_reportes, c.pais, c.provincia, c.municipio,
        c.fecha_creacion, c.fecha_aprobacion
      FROM contactos c
      WHERE c.estado = 'aprobado'
        AND c.deleted_at IS NULL
      ORDER BY c.nombre ASC, c.id ASC
      LIMIT p_page_size;
  ELSE
    -- Páginas siguientes: cursor compuesto (nombre, id)
    -- Usa el índice idx_contactos_estado_activo sin escanear filas anteriores
    RETURN QUERY
      SELECT
        c.id, c.nombre, c.apellido, c.telefono, c.direccion, c.ci,
        c.estado, c.categoria_id, c.verificado, c.score_riesgo,
        c.tiene_reportes, c.pais, c.provincia, c.municipio,
        c.fecha_creacion, c.fecha_aprobacion
      FROM contactos c
      WHERE c.estado = 'aprobado'
        AND c.deleted_at IS NULL
        AND (c.nombre, c.id) > (p_cursor_nombre, p_cursor_id)
      ORDER BY c.nombre ASC, c.id ASC
      LIMIT p_page_size;
  END IF;
END;
$$;
