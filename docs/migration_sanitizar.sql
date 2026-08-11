-- ============================================
-- Purga de caracteres erráticos en BD
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- Función para sanitizar un texto (equivalente al Dart Sanitizer)
CREATE OR REPLACE FUNCTION sanitizar_texto(input text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  result text;
BEGIN
  IF input IS NULL OR input = '' THEN
    RETURN input;
  END IF;

  result := input;

  -- Eliminar BOM y zero-width characters
  result := regexp_replace(result, E'[\u200B\u200C\u200D\u200E\u200F\uFEFF\u2060]', '', 'g');

  -- Reemplazar non-breaking spaces y otros space-like por espacio normal
  result := regexp_replace(result, E'[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]', ' ', 'g');

  -- Eliminar caracteres de control (sin \x00, PostgreSQL no lo permite)
  result := regexp_replace(result, E'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]', '', 'g');

  -- Reemplazar tabs y saltos de línea por espacio
  result := regexp_replace(result, E'[\t\r\n]', ' ', 'g');

  -- Colapsar múltiples espacios en uno
  result := regexp_replace(result, ' {2,}', ' ', 'g');

  -- Trim
  result := trim(result);

  RETURN result;
END;
$$;

-- Función para sanitizar teléfono (solo dígitos, +, -, espacio)
CREATE OR REPLACE FUNCTION sanitizar_telefono(input text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  result text;
BEGIN
  IF input IS NULL OR input = '' THEN
    RETURN input;
  END IF;

  -- Primero limpiar invisibles
  result := sanitizar_texto(input);

  -- Solo dejar dígitos, +, -, (, ), espacio
  result := regexp_replace(result, '[^\d+\-() ]', '', 'g');

  -- Trim
  result := trim(result);

  RETURN result;
END;
$$;

-- ============================================
-- RPC: Purgar toda la BD (ejecutar una vez o periódicamente)
-- ============================================
CREATE OR REPLACE FUNCTION purgar_caracteres_erraticos()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actualizados INT := 0;
  v_contacto RECORD;
  v_nombre_limpio TEXT;
  v_apellido_limpio TEXT;
  v_telefono_limpio TEXT;
  v_direccion_limpia TEXT;
  v_ci_limpio TEXT;
  v_provincia_limpia TEXT;
  v_municipio_limpio TEXT;
  v_cambio BOOLEAN;
BEGIN
  FOR v_contacto IN SELECT id, nombre, apellido, telefono, direccion, ci, provincia, municipio FROM contactos
  LOOP
    v_cambio := false;
    v_nombre_limpio := sanitizar_texto(v_contacto.nombre);
    v_apellido_limpio := sanitizar_texto(v_contacto.apellido);
    v_telefono_limpio := sanitizar_telefono(v_contacto.telefono);
    v_direccion_limpia := sanitizar_texto(v_contacto.direccion);
    v_ci_limpio := CASE WHEN v_contacto.ci IS NOT NULL THEN regexp_replace(v_contacto.ci, '[^\d]', '', 'g') ELSE NULL END;
    v_provincia_limpia := sanitizar_texto(v_contacto.provincia);
    v_municipio_limpio := sanitizar_texto(v_contacto.municipio);

    IF v_nombre_limpio IS DISTINCT FROM v_contacto.nombre
       OR v_apellido_limpio IS DISTINCT FROM v_contacto.apellido
       OR v_telefono_limpio IS DISTINCT FROM v_contacto.telefono
       OR v_direccion_limpia IS DISTINCT FROM v_contacto.direccion
       OR v_ci_limpio IS DISTINCT FROM v_contacto.ci
       OR v_provincia_limpia IS DISTINCT FROM v_contacto.provincia
       OR v_municipio_limpio IS DISTINCT FROM v_contacto.municipio
    THEN
      UPDATE contactos SET
        nombre = v_nombre_limpio,
        apellido = v_apellido_limpio,
        telefono = v_telefono_limpio,
        direccion = v_direccion_limpia,
        ci = v_ci_limpio,
        provincia = v_provincia_limpia,
        municipio = v_municipio_limpio
      WHERE id = v_contacto.id;
      v_actualizados := v_actualizados + 1;
    END IF;
  END LOOP;

  RETURN json_build_object('actualizados', v_actualizados);
END;
$$;

-- ============================================
-- Trigger: sanitizar automáticamente al insertar/actualizar
-- ============================================
CREATE OR REPLACE FUNCTION trigger_sanitizar_contacto()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.nombre := sanitizar_texto(NEW.nombre);
  NEW.apellido := sanitizar_texto(NEW.apellido);
  NEW.telefono := sanitizar_telefono(NEW.telefono);
  NEW.direccion := sanitizar_texto(NEW.direccion);
  NEW.ci := CASE WHEN NEW.ci IS NOT NULL THEN regexp_replace(NEW.ci, '[^\d]', '', 'g') ELSE NULL END;
  NEW.provincia := sanitizar_texto(NEW.provincia);
  NEW.municipio := sanitizar_texto(NEW.municipio);
  RETURN NEW;
END;
$$;

-- Aplicar trigger (INSERT y UPDATE)
DROP TRIGGER IF EXISTS sanitizar_contacto_trigger ON contactos;
CREATE TRIGGER sanitizar_contacto_trigger
  BEFORE INSERT OR UPDATE ON contactos
  FOR EACH ROW
  EXECUTE FUNCTION trigger_sanitizar_contacto();
