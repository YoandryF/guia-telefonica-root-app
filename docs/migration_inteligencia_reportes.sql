-- ============================================
-- Mejoras de inteligencia y anti-abuso en reportes
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- ============================================
-- 1. Configuración por defecto (nuevas claves)
-- ============================================
INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('max_reportes_mismo_contacto', '1', 'Máximo de reportes que un usuario puede hacer al mismo contacto (pendientes+aprobados)')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('cooldown_reporte_dias', '0', 'Días mínimos entre reportes al mismo contacto por mismo usuario (0=desactivado)')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('detectar_reportes_cruzados', 'true', 'Detectar si A reporta a B y B reporta a A (venganza)')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('dias_reportador_senior', '30', 'Días desde verificación para considerar reportador senior')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('peso_senior', '2', 'Multiplicador de peso para reportadores senior')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('umbral_reportes_negocio', '5', 'Reportes necesarios para marcar un contacto de categoría negocio')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('umbral_reportes_normal', '3', 'Reportes necesarios para marcar un contacto normal')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('patron_prefijo_min', '5', 'Mínimo de contactos con mismo prefijo reportados para alertar')
ON CONFLICT (clave) DO NOTHING;

INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('patron_prefijo_dias', '7', 'Ventana de días para detectar patrones de prefijo')
ON CONFLICT (clave) DO NOTHING;

-- ============================================
-- 2. Tabla de alertas de patrones (para admin)
-- ============================================
CREATE TABLE IF NOT EXISTS alertas_patrones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo text NOT NULL, -- 'prefijo', 'cruzado'
  descripcion text NOT NULL,
  datos jsonb DEFAULT '{}',
  estado text DEFAULT 'pendiente', -- pendiente, revisado
  created_at timestamptz DEFAULT now()
);

-- ============================================
-- 3. Campo score_riesgo en contactos (solo admin)
-- ============================================
ALTER TABLE contactos ADD COLUMN IF NOT EXISTS score_riesgo float DEFAULT 0;

-- ============================================
-- 4. RPC insertar_reporte ACTUALIZADO
--    (reemplaza la versión anterior)
-- ============================================
CREATE OR REPLACE FUNCTION insertar_reporte(
  p_contacto_id uuid,
  p_motivo text,
  p_descripcion text DEFAULT NULL,
  p_reportado_por text DEFAULT NULL,
  p_reportado_desde text DEFAULT 'app',
  p_dispositivo_id text DEFAULT NULL,
  p_telegram_user_id text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    reportes_hoy INT;
    reportes_5min INT;
    reportes_duplicados INT;
    desestimados_total INT;
    limite INT;
    max_5min INT;
    max_mismo_contacto INT;
    cooldown_dias INT;
    detectar_cruzados BOOLEAN;
    trust FLOAT;
    trust_auto FLOAT;
    identificador TEXT;
    ultimo_reporte_fecha TIMESTAMPTZ;
BEGIN
    -- Identificador principal: telegram > dispositivo > reportado_por
    identificador := COALESCE(p_telegram_user_id, p_dispositivo_id, p_reportado_por, 'unknown');

    -- =====================
    -- VERIFICAR BAN
    -- =====================
    IF EXISTS (SELECT 1 FROM usuarios_baneados WHERE identificador = COALESCE(p_telegram_user_id, p_dispositivo_id, p_reportado_por)) THEN
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
    -- REGLA: NO DUPLICAR REPORTE AL MISMO CONTACTO
    -- =====================
    SELECT COUNT(*) INTO reportes_duplicados FROM reportes
      WHERE contacto_id = p_contacto_id
        AND (reportado_por = identificador OR dispositivo_id = p_dispositivo_id)
        AND estado IN ('pendiente', 'revisado');
    IF reportes_duplicados >= max_mismo_contacto THEN
      RETURN 'YA_REPORTADO';
    END IF;

    -- =====================
    -- REGLA: COOLDOWN (si está activo)
    -- =====================
    IF cooldown_dias > 0 THEN
      SELECT MAX(fecha_reporte) INTO ultimo_reporte_fecha FROM reportes
        WHERE contacto_id = p_contacto_id
          AND (reportado_por = identificador OR dispositivo_id = p_dispositivo_id);
      IF ultimo_reporte_fecha IS NOT NULL AND ultimo_reporte_fecha > NOW() - (cooldown_dias || ' days')::interval THEN
        RETURN 'COOLDOWN';
      END IF;
    END IF;

    -- =====================
    -- DETECCIÓN DE ATAQUE (5 min)
    -- =====================
    SELECT COUNT(*) INTO reportes_5min FROM reportes
      WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador)
            AND fecha_reporte > NOW() - INTERVAL '5 minutes';
    IF reportes_5min >= max_5min THEN
      RETURN 'ATAQUE';
    END IF;

    -- =====================
    -- FLAG ABUSADOR (desestimados)
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
    -- DETECCIÓN REPORTES CRUZADOS (venganza)
    -- =====================
    IF detectar_cruzados AND p_telegram_user_id IS NOT NULL THEN
      -- Buscar si el dueño del contacto reportado tiene un reporte CONTRA el reportador actual
      DECLARE
        telefono_reportador TEXT;
        contacto_reportador UUID;
      BEGIN
        -- Buscar si el reportador tiene un contacto registrado
        SELECT id INTO contacto_reportador FROM contactos
          WHERE telefono IN (
            SELECT DISTINCT c.telefono FROM contactos c
            JOIN reportes r ON r.contacto_id = c.id
            WHERE r.reportado_por = (
              SELECT reportado_por FROM reportes
              WHERE contacto_id = p_contacto_id AND estado IN ('pendiente', 'revisado')
              LIMIT 1
            )
          )
          LIMIT 1;

        -- Si el contacto reportado ha reportado al reportador → flag
        IF contacto_reportador IS NOT NULL THEN
          IF EXISTS (
            SELECT 1 FROM reportes
            WHERE contacto_id = contacto_reportador
              AND reportado_por = identificador
              AND estado IN ('pendiente', 'revisado')
          ) THEN
            -- Registrar alerta de patrón cruzado
            INSERT INTO alertas_patrones (tipo, descripcion, datos)
            VALUES ('cruzado', 'Reporte cruzado detectado', jsonb_build_object(
              'reportador', identificador,
              'contacto_reportado', p_contacto_id,
              'contacto_inverso', contacto_reportador
            ));
          END IF;
        END IF;
      END;
    END IF;

    -- =====================
    -- CALCULAR TRUST DEL REPORTADOR
    -- =====================
    DECLARE
      aprobados_user INT;
      total_user INT;
    BEGIN
      SELECT COUNT(*) INTO aprobados_user FROM reportes WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador) AND estado = 'revisado';
      SELECT COUNT(*) INTO total_user FROM reportes WHERE (dispositivo_id = p_dispositivo_id OR reportado_por = identificador) AND estado IN ('revisado', 'resuelto');
      IF total_user > 0 THEN
        trust := aprobados_user::float / total_user;
      ELSE
        trust := 0.5;
      END IF;
    END;

    -- =====================
    -- INSERTAR REPORTE
    -- =====================
    IF trust >= trust_auto THEN
      INSERT INTO reportes (contacto_id, motivo, descripcion, reportado_por, reportado_desde, dispositivo_id, estado)
                VALUES (p_contacto_id, p_motivo, p_descripcion, identificador, p_reportado_desde, p_dispositivo_id, 'revisado');
      -- Actualizar score de riesgo del contacto
      PERFORM actualizar_score_riesgo(p_contacto_id);
      RETURN 'AUTO_APROBADO';
    ELSE
      INSERT INTO reportes (contacto_id, motivo, descripcion, reportado_por, reportado_desde, dispositivo_id)
                VALUES (p_contacto_id, p_motivo, p_descripcion, identificador, p_reportado_desde, p_dispositivo_id);
      -- Actualizar score de riesgo del contacto
      PERFORM actualizar_score_riesgo(p_contacto_id);
      RETURN 'OK';
    END IF;
END;
$$;

-- ============================================
-- 5. RPC: Score de riesgo del contacto
-- ============================================
CREATE OR REPLACE FUNCTION actualizar_score_riesgo(p_contacto_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reportes_pendientes INT;
  v_reportes_aprobados INT;
  v_avales INT;
  v_es_negocio BOOLEAN;
  v_score FLOAT;
  peso_reporte_aprobado FLOAT := 3.0;
  peso_reporte_pendiente FLOAT := 1.0;
  peso_aval FLOAT := -2.0;
BEGIN
  SELECT COUNT(*) INTO v_reportes_pendientes FROM reportes
    WHERE contacto_id = p_contacto_id AND estado = 'pendiente';
  SELECT COUNT(*) INTO v_reportes_aprobados FROM reportes
    WHERE contacto_id = p_contacto_id AND estado = 'revisado';
  SELECT COUNT(*) INTO v_avales FROM avales
    WHERE contacto_id = p_contacto_id;

  -- Verificar si es negocio (tiene categoría)
  SELECT EXISTS(SELECT 1 FROM contactos WHERE id = p_contacto_id AND categoria_id IS NOT NULL) INTO v_es_negocio;

  -- Calcular score
  v_score := (v_reportes_aprobados * peso_reporte_aprobado)
           + (v_reportes_pendientes * peso_reporte_pendiente)
           + (v_avales * peso_aval);

  -- Normalizar a 0-100
  v_score := GREATEST(0, LEAST(100, v_score * 10));

  -- Si es negocio, reducir score (más tolerancia)
  IF v_es_negocio THEN
    v_score := v_score * 0.7;
  END IF;

  UPDATE contactos SET score_riesgo = v_score WHERE id = p_contacto_id;
END;
$$;

-- ============================================
-- 6. RPC: Detectar patrones de prefijo
--    (llamar desde cron diario)
-- ============================================
CREATE OR REPLACE FUNCTION detectar_patrones_prefijo()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_min INT;
  v_dias INT;
  v_prefijo RECORD;
  v_alertas INT := 0;
BEGIN
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='patron_prefijo_min'), 5) INTO v_min;
  SELECT COALESCE((SELECT valor::int FROM configuracion WHERE clave='patron_prefijo_dias'), 7) INTO v_dias;

  FOR v_prefijo IN
    SELECT LEFT(c.telefono, 3) as prefijo, COUNT(DISTINCT c.id) as total
    FROM reportes r
    JOIN contactos c ON c.id = r.contacto_id
    WHERE r.fecha_reporte > NOW() - (v_dias || ' days')::interval
      AND r.estado IN ('pendiente', 'revisado')
    GROUP BY LEFT(c.telefono, 3)
    HAVING COUNT(DISTINCT c.id) >= v_min
  LOOP
    -- Solo alertar si no hay alerta reciente del mismo prefijo
    IF NOT EXISTS (
      SELECT 1 FROM alertas_patrones
      WHERE tipo = 'prefijo'
        AND datos->>'prefijo' = v_prefijo.prefijo
        AND created_at > NOW() - INTERVAL '7 days'
    ) THEN
      INSERT INTO alertas_patrones (tipo, descripcion, datos)
      VALUES ('prefijo', 'Patrón detectado: ' || v_prefijo.total || ' contactos con prefijo ' || v_prefijo.prefijo || ' reportados en ' || v_dias || ' días',
        jsonb_build_object('prefijo', v_prefijo.prefijo, 'total', v_prefijo.total));
      v_alertas := v_alertas + 1;
    END IF;
  END LOOP;

  RETURN v_alertas;
END;
$$;
