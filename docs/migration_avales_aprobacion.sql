-- ============================================
-- Avales con aprobación admin
-- Ejecutar en Supabase SQL Editor
-- Contexto: avales sin revisión admin afectaban
--   el score_riesgo sin validación, permitiendo
--   manipulación del score a la baja.
-- ============================================

-- ============================================
-- 1. Agregar campo estado a avales
-- ============================================
ALTER TABLE avales
  ADD COLUMN IF NOT EXISTS estado text NOT NULL DEFAULT 'pendiente'
  CHECK (estado IN ('pendiente', 'aprobado', 'rechazado'));

ALTER TABLE avales
  ADD COLUMN IF NOT EXISTS revisado_por text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS fecha_revision timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS nota text DEFAULT NULL;

-- ============================================
-- 2. Índices para el panel admin
-- ============================================
CREATE INDEX IF NOT EXISTS idx_avales_contacto_id
  ON avales (contacto_id);

CREATE INDEX IF NOT EXISTS idx_avales_estado
  ON avales (estado)
  WHERE estado = 'pendiente';

-- ============================================
-- 3. Actualizar actualizar_score_riesgo
--    para contar solo avales aprobados
-- ============================================
CREATE OR REPLACE FUNCTION actualizar_score_riesgo(p_contacto_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reportes_pendientes INT;
  v_reportes_aprobados  INT;
  v_avales_aprobados    INT;
  v_es_negocio          BOOLEAN;
  v_score               FLOAT;
  peso_reporte_aprobado FLOAT := 3.0;
  peso_reporte_pendiente FLOAT := 1.0;
  peso_aval              FLOAT := -2.0;
BEGIN
  SELECT COUNT(*) INTO v_reportes_pendientes
    FROM reportes WHERE contacto_id = p_contacto_id AND estado = 'pendiente';

  SELECT COUNT(*) INTO v_reportes_aprobados
    FROM reportes WHERE contacto_id = p_contacto_id AND estado = 'revisado';

  -- Solo avales aprobados por el admin afectan el score
  SELECT COUNT(*) INTO v_avales_aprobados
    FROM avales WHERE contacto_id = p_contacto_id AND estado = 'aprobado';

  SELECT EXISTS(
    SELECT 1 FROM contactos WHERE id = p_contacto_id AND categoria_id IS NOT NULL
  ) INTO v_es_negocio;

  v_score := (v_reportes_aprobados  * peso_reporte_aprobado)
           + (v_reportes_pendientes * peso_reporte_pendiente)
           + (v_avales_aprobados    * peso_aval);

  v_score := GREATEST(0, LEAST(100, v_score * 10));

  IF v_es_negocio THEN
    v_score := v_score * 0.7;
  END IF;

  UPDATE contactos SET score_riesgo = v_score WHERE id = p_contacto_id;
END;
$$;

-- ============================================
-- 4. Trigger: recalcular score al aprobar/rechazar aval
-- ============================================
CREATE OR REPLACE FUNCTION trg_recalcular_score_aval()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.estado = NEW.estado THEN
    RETURN NEW;
  END IF;
  PERFORM actualizar_score_riesgo(NEW.contacto_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_score_riesgo_aval ON avales;
CREATE TRIGGER trg_score_riesgo_aval
  AFTER UPDATE OF estado
  ON avales
  FOR EACH ROW
  EXECUTE FUNCTION trg_recalcular_score_aval();

-- ============================================
-- 5. Backfill — recalcular score de todos los
--    contactos afectados (avales existentes
--    quedan en 'pendiente', no afectan score)
-- ============================================
DO $$
DECLARE v_id uuid;
BEGIN
  FOR v_id IN
    SELECT DISTINCT contacto_id FROM avales
  LOOP
    PERFORM actualizar_score_riesgo(v_id);
  END LOOP;
END;
$$;
