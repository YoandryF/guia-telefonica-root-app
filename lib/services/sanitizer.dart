/// Utilidad para sanitizar texto — elimina caracteres invisibles,
/// normaliza espacios, limpia campos de contactos.

class Sanitizer {
  /// Caracteres "space-like" que parecen espacio pero no lo son
  static final _spaceLike = RegExp(
    '[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]',
  );

  /// Caracteres de ancho cero (invisibles)
  static final _zeroWidth = RegExp(
    '[\u200B\u200C\u200D\u200E\u200F\uFEFF\u2060\u2061-\u2064]',
  );

  /// Múltiples espacios seguidos
  static final _multiSpace = RegExp(r' {2,}');

  /// Caracteres de control (excepto newline para campos multilinea)
  static final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  /// Sanitizar texto genérico (nombre, apellido, dirección)
  static String texto(String? input) {
    if (input == null || input.isEmpty) return '';
    var result = input;

    // 1. Eliminar BOM y zero-width
    result = result.replaceAll(_zeroWidth, '');

    // 2. Reemplazar space-like por espacio normal
    result = result.replaceAll(_spaceLike, ' ');

    // 3. Eliminar caracteres de control
    result = result.replaceAll(_controlChars, '');

    // 4. Reemplazar tabs y saltos de línea por espacio
    result = result.replaceAll(RegExp(r'[\t\r\n]'), ' ');

    // 5. Colapsar múltiples espacios en uno
    result = result.replaceAll(_multiSpace, ' ');

    // 6. Trim
    result = result.trim();

    return result;
  }

  /// Sanitizar teléfono — solo dígitos, +, guión, espacio
  static String telefono(String? input) {
    if (input == null || input.isEmpty) return '';
    var result = input;

    // Eliminar todo lo invisible primero
    result = result.replaceAll(_zeroWidth, '');
    result = result.replaceAll(_spaceLike, ' ');
    result = result.replaceAll(_controlChars, '');
    result = result.replaceAll(RegExp(r'[\t\r\n]'), '');

    // Solo dejar: dígitos, +, -, (, ), espacio
    result = result.replaceAll(RegExp(r'[^\d+\-() ]'), '');

    // Colapsar espacios y trim
    result = result.replaceAll(_multiSpace, ' ').trim();

    return result;
  }

  /// Sanitizar CI (carné identidad) — solo dígitos
  static String ci(String? input) {
    if (input == null || input.isEmpty) return '';
    return input.replaceAll(RegExp(r'[^\d]'), '').trim();
  }

  /// Sanitizar un mapa completo de contacto (para import/registro)
  static Map<String, String> contacto(Map<String, String> raw) {
    return {
      if (raw['nombre'] != null) 'nombre': texto(raw['nombre']),
      if (raw['apellido'] != null) 'apellido': texto(raw['apellido']),
      if (raw['telefono'] != null) 'telefono': telefono(raw['telefono']),
      if (raw['direccion'] != null) 'direccion': texto(raw['direccion']),
      if (raw['ci'] != null) 'ci': ci(raw['ci']),
      if (raw['provincia'] != null) 'provincia': texto(raw['provincia']),
      if (raw['municipio'] != null) 'municipio': texto(raw['municipio']),
      if (raw['pais'] != null) 'pais': texto(raw['pais']),
      // Pasar el resto sin modificar
      ...Map.fromEntries(
        raw.entries.where((e) => !['nombre', 'apellido', 'telefono', 'direccion', 'ci', 'provincia', 'municipio', 'pais'].contains(e.key)),
      ),
    };
  }
}
