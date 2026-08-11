-- ============================================
-- Evidencias en reportes (grupo privado Telegram)
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Campos para referenciar la evidencia en Telegram
ALTER TABLE reportes ADD COLUMN IF NOT EXISTS evidencia_msg_id bigint;
ALTER TABLE reportes ADD COLUMN IF NOT EXISTS evidencia_chat_id bigint;
ALTER TABLE reportes ADD COLUMN IF NOT EXISTS evidencia_file_id text;

-- Índice para el cron de limpieza
CREATE INDEX IF NOT EXISTS idx_reportes_evidencia ON reportes(evidencia_msg_id) WHERE evidencia_msg_id IS NOT NULL;
