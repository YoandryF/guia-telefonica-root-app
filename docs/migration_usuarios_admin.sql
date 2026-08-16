-- ============================================
-- Gestión de usuarios verificados + restricciones
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- ============================================
-- 1. Tabla restricciones_usuario
-- ============================================
CREATE TABLE IF NOT EXISTS restricciones_usuario (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  telegram_user_id text NOT NULL,
  funcionalidad   text NOT NULL CHECK (funcionalidad IN (
                    'reportar', 'avalar', 'reclamar', 'registrar', 'ban_total'
                  )),
  motivo          text NOT NULL,
  creado_por      text NOT NULL,
  fecha_inicio    timestamptz DEFAULT now(),
  fecha_fin       timestamptz DEFAULT NULL, -- NULL = indefinido
  activo          boolean DEFAULT true,
  UNIQUE (telegram_user_id, funcionalidad)  -- una restricción activa por funcionalidad
);

CREATE INDEX IF NOT EXISTS idx_restricciones_user
  ON restricciones_usuario (telegram_user_id)
  WHERE activo = true;

CREATE INDEX IF NOT EXISTS idx_restricciones_func
  ON restricciones_usuario (funcionalidad)
  WHERE activo = true;

-- ============================================
-- 2. Función helper: verificar restricción
-- ============================================
CREATE OR REPLACE FUNCTION tiene_restriccion(
  p_telegram_user_id text,
  p_funcionalidad    text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM restricciones_usuario
    WHERE telegram_user_id = p_telegram_user_id
      AND activo = true
      AND (funcionalidad = p_funcionalidad OR funcionalidad = 'ban_total')
      AND (fecha_fin IS NULL OR fecha_fin > now())
  );
$$;

-- ============================================
-- 3. Update insertar_reporte:
--    - Requiere telegram_user_id verificado
--    - Verifica restricciones antes de procesar
-- ============================================
CREATE OR REPLACE FUNCTION insertar_reporte(
  p_contacto_id      uuid,
  p_motivo           text,
  p_descripcion      text DEFAULT NULL,
  p_reportado_por    text DEFAULT NULL,
  p_reportado_desde  text DEFAULT 'app',
  p_dispositivo_id   text DEFAULT NULL,
  p_telegram_user_id text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  reportes_hoy        INT;
  reportes_5min       INT;
  reportes_duplicados INT;
  desestimados_total  INT;
  limite              INT;
  max_5min            INT;
  max_mismo_contacto  INT;
  cooldown_dias       INT;
  detectar_cruzados   BOOLEAN;
  trust               FLOAT;
  trust_auto          FLOAT;
  identificador       TEXT;
  ultimo_reporte_fecha TIMESTAMPTZ;
BEGIN
  identificador := COALESCE(p_telegram_user_id, p_dispositivo_id, p_reportado_por, 'unknown');

  -- =====================
  -- REQUIERE VERIFICACIÓN TELEGRAM
  -- =====================
  IF p_telegram_user_id IS NULL THEN
    RETURN 'NO_VERIFICADO';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM verificaciones_app
    WHERE telegram_user_id = p_telegram_user_id::bigint
      AND verificado = true
  ) THEN
    RETURN 'NO_VERIFICADO';
  END IF;

  -- =====================
  -- VERIFICAR RESTRICCIONES
  -- =====================
  IF tiene_restriccion(p_telegram_user_id, 'reportar') THEN
    RETURN 'RESTRINGIDO';
  END IF;

  -- =====================
  -- VERIFICAR BAN
  -- =====================
  IF EXISTS (SELECT 1 FROM usuarios_baneados
    WHERE identificador = COALESCE(p_telegram_user_id, p_dispositivo_id, p_reportado_por)) THEN
    RETURN 'BANEADO';
  END IF;

  -- =====================
  -- LEER CONFIGURACIÓN
  -- =====================
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='reportes_dia_normal'), 3) INTO limite;
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='max_reportes_5min'), 3) INTO max_5min;
  SELECT COALESCE((SELECT valor::float FROM configuracion WHERE clave='trust_auto_aprobar'), 0.8) INTO trust_auto;
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='max_reportes_mismo_contacto'), 1) INTO max_mismo_contacto;
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='cooldown_reporte_dias'), 0) INTO cooldown_dias;
  SELECT COALESCE((SELECT valor::boolean FROM configuracion WHERE clave='detectar_reportes_cruzados'), true) INTO detectar_cruzados;

  -- =====================
  -- REGLA: NO DUPLICAR
  -- =====================
  SELECT COUNT(*) INTO reportes_duplicados FROM reportes
    WHERE contacto_id = p_contacto_id
      AND (reportado_por = identificador OR dispositivo_id = p_dispositivo_id)
      AND estado IN ('pendiente', 'revisado');
  IF reportes_duplicados >= max_mismo_contacto THEN
    RETURN 'YA_REPORTADO';
  END IF;

  -- =====================
  -- COOLDOWN
  -- =====================
  IF cooldown_dias > 0 THEN
    SELECT MAX(fecha_reporte) INTO ultimo_reporte_fecha FROM reportes
      WHERE contacto_id = p_contacto_id
        AND (reportado_por = identificador OR dispositivo_id = p_dispositivo_id);
    IF ultimo_reporte_fecha IS NOT NULL
       AND ultimo_reporte_fecha > NOW() - (cooldown_dias || ' days')::interval THEN
      RETURN 'COOLDOWN';
    END IF;
  END IF;

  -- =====================
  -- DETECCIÓN ATAQUE 5min
  -- =====================
  SELECT COUNT(*) INTO reportes_5min FROM reportes
    WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
      AND fecha_reporte > NOW() - INTERVAL '5 minutes';
  IF reportes_5min >= max_5min THEN
    RETURN 'ATAQUE';
  END IF;

  -- =====================
  -- FLAG ABUSADOR
  -- =====================
  SELECT COUNT(*) INTO desestimados_total FROM reportes
    WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
      AND estado = 'resuelto';
  IF desestimados_total > COALESCE((SELECT valor::int FROM configuracion WHERE clave='umbral_abusador'), 5) THEN
    limite := COALESCE((SELECT valor::int FROM configuracion WHERE clave='reportes_dia_abusador'), 1);
  END IF;

  -- =====================
  -- RATE LIMIT DIARIO
  -- =====================
  SELECT COUNT(*) INTO reportes_hoy FROM reportes
    WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
      AND fecha_reporte > NOW() - INTERVAL '24 hours';
  IF reportes_hoy >= limite THEN
    RETURN 'LIMITE';
  END IF;

  -- =====================
  -- TRUST SCORE
  -- =====================
  DECLARE
    aprobados_user INT;
    total_user     INT;
  BEGIN
    SELECT COUNT(*) INTO aprobados_user FROM reportes
      WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
        AND estado = 'revisado';
    SELECT COUNT(*) INTO total_user FROM reportes
      WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
        AND estado IN ('revisado', 'resuelto');
    trust := CASE WHEN total_user > 0 THEN aprobados_user::float / total_user ELSE 0.5 END;
  END;

  -- =====================
  -- INSERTAR
  -- =====================
  IF trust >= trust_auto THEN
    INSERT INTO reportes (contacto_id, motivo, descripcion, reportado_por, reportado_desde, dispositivo_id, estado)
    VALUES (p_contacto_id, p_motivo, p_descripcion, identificador, p_reportado_desde, p_dispositivo_id, 'revisado');
    PERFORM actualizar_score_riesgo(p_contacto_id);
    RETURN 'AUTO_APROBADO';
  ELSE
    INSERT INTO reportes (contacto_id, motivo, descripcion, reportado_por, reportado_desde, dispositivo_id)
    VALUES (p_contacto_id, p_motivo, p_descripcion, identificador, p_reportado_desde, p_dispositivo_id);
    PERFORM actualizar_score_riesgo(p_contacto_id);
    RETURN 'OK';
  END IF;
END;
$$;

-- ============================================
-- 4. RPC get_analytics_admin — con nombres TG
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
  -- Top 10 reportadores con nombre TG
  SELECT json_agg(r) INTO v_top_reportadores FROM (
    SELECT
      rep.reportado_por AS identificador,
      COALESCE(
        NULLIF(TRIM(COALESCE(ut.primer_nombre,'') || ' ' || COALESCE(ut.ultimo_nombre,'')), ''),
        ut.nombre_usuario,
        rep.reportado_por
      ) AS nombre_display,
      ut.nombre_usuario AS username,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE rep.estado = 'revisado') AS aprobados,
      COUNT(*) FILTER (WHERE rep.estado = 'pendiente') AS pendientes
    FROM reportes rep
    LEFT JOIN usuarios_telegram ut ON ut.chat_id = rep.reportado_por
    WHERE rep.reportado_por IS NOT NULL
    GROUP BY rep.reportado_por, ut.primer_nombre, ut.ultimo_nombre, ut.nombre_usuario
    ORDER BY total DESC
    LIMIT 10
  ) r;

  -- Top 10 reportados
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

  -- Top 10 fallas con nombre TG
  SELECT json_agg(r) INTO v_top_fallas FROM (
    SELECT
      rep.reportado_por AS identificador,
      COALESCE(
        NULLIF(TRIM(COALESCE(ut.primer_nombre,'') || ' ' || COALESCE(ut.ultimo_nombre,'')), ''),
        ut.nombre_usuario,
        rep.reportado_por
      ) AS nombre_display,
      ut.nombre_usuario AS username,
      COUNT(*) FILTER (WHERE rep.estado = 'resuelto') AS desestimados,
      COUNT(*) FILTER (WHERE rep.estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE rep.estado = 'resuelto')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE rep.estado IN ('revisado','resuelto')), 0) * 100, 1
      ) AS pct_fallas
    FROM reportes rep
    LEFT JOIN usuarios_telegram ut ON ut.chat_id = rep.reportado_por
    WHERE rep.reportado_por IS NOT NULL
      AND rep.estado IN ('revisado', 'resuelto')
    GROUP BY rep.reportado_por, ut.primer_nombre, ut.ultimo_nombre, ut.nombre_usuario
    HAVING COUNT(*) FILTER (WHERE rep.estado = 'resuelto') > 0
    ORDER BY desestimados DESC
    LIMIT 10
  ) r;

  -- Top 10 avaladores con nombre TG
  SELECT json_agg(r) INTO v_top_avaladores FROM (
    SELECT
      av.avalado_por AS identificador,
      COALESCE(
        NULLIF(TRIM(COALESCE(ut.primer_nombre,'') || ' ' || COALESCE(ut.ultimo_nombre,'')), ''),
        ut.nombre_usuario,
        av.avalado_por
      ) AS nombre_display,
      ut.nombre_usuario AS username,
      COUNT(*) AS total_avales,
      COUNT(*) FILTER (WHERE av.estado = 'aprobado') AS aprobados,
      COUNT(*) FILTER (WHERE av.estado = 'pendiente') AS pendientes,
      COUNT(*) FILTER (WHERE av.estado = 'rechazado') AS rechazados
    FROM avales av
    LEFT JOIN usuarios_telegram ut ON ut.chat_id = av.avalado_por
    WHERE av.avalado_por IS NOT NULL
    GROUP BY av.avalado_por, ut.primer_nombre, ut.ultimo_nombre, ut.nombre_usuario
    ORDER BY total_avales DESC
    LIMIT 10
  ) r;

  -- Top trust
  SELECT json_agg(r) INTO v_top_trust FROM (
    SELECT
      rep.reportado_por AS identificador,
      COALESCE(
        NULLIF(TRIM(COALESCE(ut.primer_nombre,'') || ' ' || COALESCE(ut.ultimo_nombre,'')), ''),
        ut.nombre_usuario,
        rep.reportado_por
      ) AS nombre_display,
      ut.nombre_usuario AS username,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE rep.estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE rep.estado = 'revisado')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE rep.estado IN ('revisado','resuelto')), 0) * 100, 1
      ) AS trust_pct
    FROM reportes rep
    LEFT JOIN usuarios_telegram ut ON ut.chat_id = rep.reportado_por
    WHERE rep.reportado_por IS NOT NULL
    GROUP BY rep.reportado_por, ut.primer_nombre, ut.ultimo_nombre, ut.nombre_usuario
    HAVING COUNT(*) FILTER (WHERE rep.estado IN ('revisado','resuelto')) >= 3
    ORDER BY trust_pct DESC, aprobados DESC
    LIMIT 10
  ) r;

  -- Peor trust
  SELECT json_agg(r) INTO v_peor_trust FROM (
    SELECT
      rep.reportado_por AS identificador,
      COALESCE(
        NULLIF(TRIM(COALESCE(ut.primer_nombre,'') || ' ' || COALESCE(ut.ultimo_nombre,'')), ''),
        ut.nombre_usuario,
        rep.reportado_por
      ) AS nombre_display,
      ut.nombre_usuario AS username,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE rep.estado = 'revisado') AS aprobados,
      ROUND(
        COUNT(*) FILTER (WHERE rep.estado = 'revisado')::numeric /
        NULLIF(COUNT(*) FILTER (WHERE rep.estado IN ('revisado','resuelto')), 0) * 100, 1
      ) AS trust_pct
    FROM reportes rep
    LEFT JOIN usuarios_telegram ut ON ut.chat_id = rep.reportado_por
    WHERE rep.reportado_por IS NOT NULL
    GROUP BY rep.reportado_por, ut.primer_nombre, ut.ultimo_nombre, ut.nombre_usuario
    HAVING COUNT(*) FILTER (WHERE rep.estado IN ('revisado','resuelto')) >= 3
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

-- ============================================
-- 5. RPC get_dashboard_stats — una sola llamada
-- ============================================
CREATE OR REPLACE FUNCTION get_dashboard_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_contactos_total      INT;
  v_contactos_aprobados  INT;
  v_contactos_pendientes INT;
  v_reportes_total       INT;
  v_reportes_aprobados   INT;
  v_reportes_pendientes  INT;
  v_usuarios_total       INT;
  v_avales_total         INT;
  v_avales_pendientes    INT;
  v_reclamos_pendientes  INT;
  v_con_restriccion      INT;
  v_nuevos_semana        INT;
BEGIN
  SELECT COUNT(*) INTO v_contactos_total     FROM contactos WHERE deleted_at IS NULL;
  SELECT COUNT(*) INTO v_contactos_aprobados FROM contactos WHERE estado='aprobado' AND deleted_at IS NULL;
  SELECT COUNT(*) INTO v_contactos_pendientes FROM contactos WHERE estado='pendiente' AND deleted_at IS NULL;

  SELECT COUNT(*) INTO v_reportes_total     FROM reportes;
  SELECT COUNT(*) INTO v_reportes_aprobados FROM reportes WHERE estado='revisado';
  SELECT COUNT(*) INTO v_reportes_pendientes FROM reportes WHERE estado='pendiente';

  SELECT COUNT(*) INTO v_usuarios_total FROM usuarios_telegram;

  SELECT COUNT(*) INTO v_avales_total    FROM avales;
  SELECT COUNT(*) INTO v_avales_pendientes FROM avales WHERE estado='pendiente';

  SELECT COUNT(*) INTO v_reclamos_pendientes FROM reclamos WHERE estado='pendiente';

  SELECT COUNT(DISTINCT telegram_user_id) INTO v_con_restriccion
    FROM restricciones_usuario WHERE activo=true AND (fecha_fin IS NULL OR fecha_fin > now());

  SELECT COUNT(*) INTO v_nuevos_semana
    FROM contactos WHERE fecha_creacion > now() - INTERVAL '7 days' AND deleted_at IS NULL;

  RETURN json_build_object(
    'contactos_total',       v_contactos_total,
    'contactos_aprobados',   v_contactos_aprobados,
    'contactos_pendientes',  v_contactos_pendientes,
    'reportes_total',        v_reportes_total,
    'reportes_aprobados',    v_reportes_aprobados,
    'reportes_pendientes',   v_reportes_pendientes,
    'usuarios_total',        v_usuarios_total,
    'avales_total',          v_avales_total,
    'avales_pendientes',     v_avales_pendientes,
    'reclamos_pendientes',   v_reclamos_pendientes,
    'con_restriccion',       v_con_restriccion,
    'nuevos_semana',         v_nuevos_semana,
    'pct_reportes_aprobados', CASE WHEN v_reportes_total > 0
      THEN ROUND(v_reportes_aprobados::numeric / v_reportes_total * 100, 1)
      ELSE 0 END
  );
END;
$$;

-- ============================================
-- 6. RPC get_usuarios_admin — listado paginado
-- ============================================
CREATE OR REPLACE FUNCTION get_usuarios_admin(
  p_query  text DEFAULT '',
  p_offset int  DEFAULT 0,
  p_limit  int  DEFAULT 20
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_usuarios json;
  v_total    int;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM usuarios_telegram ut
  WHERE p_query = ''
     OR ut.primer_nombre ILIKE '%' || p_query || '%'
     OR ut.ultimo_nombre  ILIKE '%' || p_query || '%'
     OR ut.nombre_usuario ILIKE '%' || p_query || '%'
     OR ut.chat_id        ILIKE '%' || p_query || '%';

  SELECT json_agg(r) INTO v_usuarios FROM (
    SELECT
      ut.chat_id,
      ut.nombre_usuario,
      ut.primer_nombre,
      ut.ultimo_nombre,
      ut.fecha_registro,
      ut.ultima_interaccion,
      -- Actividad
      (SELECT COUNT(*) FROM reportes  WHERE reportado_por = ut.chat_id) AS total_reportes,
      (SELECT COUNT(*) FROM avales    WHERE avalado_por   = ut.chat_id) AS total_avales,
      (SELECT COUNT(*) FROM contactos WHERE creado_por    = ut.chat_id AND deleted_at IS NULL) AS total_contactos,
      -- Trust score
      ROUND(
        (SELECT COUNT(*) FROM reportes WHERE reportado_por = ut.chat_id AND estado='revisado')::numeric /
        NULLIF((SELECT COUNT(*) FROM reportes WHERE reportado_por = ut.chat_id AND estado IN ('revisado','resuelto')), 0) * 100,
      1) AS trust_pct,
      -- Restricciones activas
      (SELECT COUNT(*) FROM restricciones_usuario
        WHERE telegram_user_id = ut.chat_id AND activo = true
          AND (fecha_fin IS NULL OR fecha_fin > now())) AS restricciones_activas,
      -- Está baneado
      EXISTS(SELECT 1 FROM usuarios_baneados WHERE identificador = ut.chat_id) AS baneado
    FROM usuarios_telegram ut
    WHERE p_query = ''
       OR ut.primer_nombre ILIKE '%' || p_query || '%'
       OR ut.ultimo_nombre  ILIKE '%' || p_query || '%'
       OR ut.nombre_usuario ILIKE '%' || p_query || '%'
       OR ut.chat_id        ILIKE '%' || p_query || '%'
    ORDER BY ut.ultima_interaccion DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset
  ) r;

  RETURN json_build_object(
    'total',    v_total,
    'usuarios', COALESCE(v_usuarios, '[]'::json)
  );
END;
$$;

-- ============================================
-- 7. RPC get_usuario_360 — perfil completo
-- ============================================
CREATE OR REPLACE FUNCTION get_usuario_360(p_telegram_user_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_usuario     json;
  v_reportes    json;
  v_avales      json;
  v_contactos   json;
  v_restricciones json;
BEGIN
  -- Info base
  SELECT row_to_json(u) INTO v_usuario FROM (
    SELECT chat_id, nombre_usuario, primer_nombre, ultimo_nombre,
           fecha_registro, ultima_interaccion
    FROM usuarios_telegram WHERE chat_id = p_telegram_user_id
  ) u;

  -- Últimos 10 reportes
  SELECT json_agg(r) INTO v_reportes FROM (
    SELECT r.id, r.motivo, r.estado, r.fecha_reporte, r.nota_admin,
           c.nombre || ' ' || c.apellido AS contacto_nombre,
           c.telefono AS contacto_telefono
    FROM reportes r
    JOIN contactos c ON c.id = r.contacto_id
    WHERE r.reportado_por = p_telegram_user_id
    ORDER BY r.fecha_reporte DESC
    LIMIT 10
  ) r;

  -- Últimos 10 avales
  SELECT json_agg(a) INTO v_avales FROM (
    SELECT av.id, av.estado, av.fecha,
           c.nombre || ' ' || c.apellido AS contacto_nombre,
           c.telefono AS contacto_telefono
    FROM avales av
    JOIN contactos c ON c.id = av.contacto_id
    WHERE av.avalado_por = p_telegram_user_id
    ORDER BY av.fecha DESC
    LIMIT 10
  ) a;

  -- Últimos 10 contactos registrados
  SELECT json_agg(ct) INTO v_contactos FROM (
    SELECT id, nombre, apellido, telefono, estado, fecha_creacion
    FROM contactos
    WHERE creado_por = p_telegram_user_id AND deleted_at IS NULL
    ORDER BY fecha_creacion DESC
    LIMIT 10
  ) ct;

  -- Restricciones activas
  SELECT json_agg(res) INTO v_restricciones FROM (
    SELECT id, funcionalidad, motivo, creado_por, fecha_inicio, fecha_fin, activo
    FROM restricciones_usuario
    WHERE telegram_user_id = p_telegram_user_id
    ORDER BY fecha_inicio DESC
  ) res;

  RETURN json_build_object(
    'usuario',       v_usuario,
    'reportes',      COALESCE(v_reportes,      '[]'::json),
    'avales',        COALESCE(v_avales,         '[]'::json),
    'contactos',     COALESCE(v_contactos,      '[]'::json),
    'restricciones', COALESCE(v_restricciones,  '[]'::json),
    'stats', json_build_object(
      'total_reportes',
        (SELECT COUNT(*) FROM reportes WHERE reportado_por = p_telegram_user_id),
      'reportes_aprobados',
        (SELECT COUNT(*) FROM reportes WHERE reportado_por = p_telegram_user_id AND estado='revisado'),
      'reportes_desestimados',
        (SELECT COUNT(*) FROM reportes WHERE reportado_por = p_telegram_user_id AND estado='resuelto'),
      'total_avales',
        (SELECT COUNT(*) FROM avales WHERE avalado_por = p_telegram_user_id),
      'avales_aprobados',
        (SELECT COUNT(*) FROM avales WHERE avalado_por = p_telegram_user_id AND estado='aprobado'),
      'total_contactos',
        (SELECT COUNT(*) FROM contactos WHERE creado_por = p_telegram_user_id AND deleted_at IS NULL),
      'trust_pct', ROUND(
        (SELECT COUNT(*) FROM reportes WHERE reportado_por = p_telegram_user_id AND estado='revisado')::numeric /
        NULLIF((SELECT COUNT(*) FROM reportes WHERE reportado_por = p_telegram_user_id
                AND estado IN ('revisado','resuelto')), 0) * 100, 1),
      'baneado',
        EXISTS(SELECT 1 FROM usuarios_baneados WHERE identificador = p_telegram_user_id)
    )
  );
END;
$$;
