-- ============================================
-- Trigger: actualizar_score_riesgo automático
-- Ejecutar en Supabase SQL Editor
-- Contexto: score_riesgo quedaba en 0 porque
--   actualizar_score_riesgo() solo se llamaba
--   desde insertar_reporte (app). Al aprobar/
--   desestimar desde el panel admin o el bot,
--   el score no se recalculaba.
-- ============================================

-- ============================================
-- 1. Función del trigger
-- ============================================
CREATE OR REPLACE FUNCTION trg_recalcular_score()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Solo actuar cuando el estado cambia (no en cada UPDATE trivial)
  IF TG_OP = 'UPDATE' AND OLD.estado = NEW.estado THEN
    RETURN NEW;
  END IF;

  -- Recalcular score del contacto afectado
  PERFORM actualizar_score_riesgo(NEW.contacto_id);

  RETURN NEW;
END;
$$;

-- ============================================
-- 2. Trigger en tabla reportes
--    Dispara al aprobar (revisado), desestimar
--    (resuelto) o cualquier cambio de estado
-- ============================================
DROP TRIGGER IF EXISTS trg_score_riesgo ON reportes;
CREATE TRIGGER trg_score_riesgo
  AFTER UPDATE OF estado
  ON reportes
  FOR EACH ROW
  EXECUTE FUNCTION trg_recalcular_score();

-- ============================================
-- 3. Backfill — recalcular score de todos los
--    contactos que tienen reportes activos
-- ============================================
DO $$
DECLARE
  v_contacto_id uuid;
BEGIN
  FOR v_contacto_id IN
    SELECT DISTINCT contacto_id FROM reportes
    WHERE estado IN ('pendiente', 'revisado')
  LOOP
    PERFORM actualizar_score_riesgo(v_contacto_id);
  END LOOP;
END;
$$;
