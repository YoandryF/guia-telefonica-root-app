-- ============================================
-- Performance & Escalabilidad — 2026-08-15
-- Ejecutar en Supabase SQL Editor
-- Contexto: preparar BD para escalar a 11M+ contactos
-- ============================================

-- ============================================
-- 1. Columna desnormalizada tiene_reportes
--    Evita JOINs costosos en la lista negra
-- ============================================
ALTER TABLE contactos
  ADD COLUMN IF NOT EXISTS tiene_reportes boolean NOT NULL DEFAULT false;

-- ============================================
-- 2. Índice parcial para lista negra
--    O(log n) — solo indexa contactos reportados
--    Query: WHERE tiene_reportes=true AND estado='aprobado' AND deleted_at IS NULL
-- ============================================
CREATE INDEX IF NOT EXISTS idx_contactos_lista_negra
  ON contactos (score_riesgo DESC)
  WHERE tiene_reportes = true
    AND estado = 'aprobado'
    AND deleted_at IS NULL;

-- ============================================
-- 3. Función del trigger sync_tiene_reportes
--    Mantiene tiene_reportes sincronizado
--    automáticamente al INSERT/UPDATE/DELETE en reportes
-- ============================================
CREATE OR REPLACE FUNCTION sync_tiene_reportes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE contactos
    SET tiene_reportes = EXISTS (
      SELECT 1 FROM reportes
      WHERE contacto_id = OLD.contacto_id
        AND estado IN ('pendiente', 'revisado')
    )
    WHERE id = OLD.contacto_id;
    RETURN OLD;
  ELSE
    UPDATE contactos
    SET tiene_reportes = EXISTS (
      SELECT 1 FROM reportes
      WHERE contacto_id = NEW.contacto_id
        AND estado IN ('pendiente', 'revisado')
    )
    WHERE id = NEW.contacto_id;
    RETURN NEW;
  END IF;
END;
$$;

-- ============================================
-- 4. Trigger en tabla reportes
-- ============================================
DROP TRIGGER IF EXISTS trg_sync_tiene_reportes ON reportes;
CREATE TRIGGER trg_sync_tiene_reportes
  AFTER INSERT OR UPDATE OF estado OR DELETE
  ON reportes
  FOR EACH ROW
  EXECUTE FUNCTION sync_tiene_reportes();

-- ============================================
-- 5. Backfill — sincronizar registros existentes
--    Ejecutar UNA sola vez después de crear el trigger
-- ============================================
UPDATE contactos c
SET tiene_reportes = EXISTS (
  SELECT 1 FROM reportes r
  WHERE r.contacto_id = c.id
    AND r.estado IN ('pendiente', 'revisado')
);

-- ============================================
-- 6. Índices generales de performance
-- ============================================

-- Eliminar índice redundante (telefono ya tiene UNIQUE constraint)
DROP INDEX IF EXISTS public.idx_contactos_telefono;

-- Índice parcial para queries frecuentes del bot:
-- .eq("estado","aprobado").is_("deleted_at",None).order("nombre")
CREATE INDEX IF NOT EXISTS idx_contactos_estado_activo
  ON public.contactos (nombre ASC)
  WHERE estado = 'aprobado' AND deleted_at IS NULL;

-- Índice para get_contactos_por_creador
CREATE INDEX IF NOT EXISTS idx_contactos_creado_por
  ON public.contactos (creado_por, fecha_creacion DESC)
  WHERE deleted_at IS NULL;

-- Índice compuesto para get_reportes_agrupados (GROUP BY + WHERE estado)
CREATE INDEX IF NOT EXISTS idx_reportes_contacto_estado
  ON public.reportes (contacto_id, estado);

-- Índices en reclamos (sin índices previos)
CREATE INDEX IF NOT EXISTS idx_reclamos_contacto_id
  ON public.reclamos (contacto_id);

CREATE INDEX IF NOT EXISTS idx_reclamos_estado
  ON public.reclamos (estado)
  WHERE estado = 'pendiente';

-- Índice en alertas_patrones
CREATE INDEX IF NOT EXISTS idx_alertas_estado
  ON public.alertas_patrones (estado)
  WHERE estado = 'pendiente';
