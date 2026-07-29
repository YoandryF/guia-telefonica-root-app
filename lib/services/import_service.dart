import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../services/supabase_service.dart';

class ImportResult {
  final int procesados;
  final int nuevos;
  final int duplicados;
  final int errores;
  final String? errorDetalle;

  ImportResult({this.procesados = 0, this.nuevos = 0, this.duplicados = 0, this.errores = 0, this.errorDetalle});
}

class ImportService {
  final _supabase = SupabaseService();

  /// Seleccionar archivo CSV o JSON
  Future<PlatformFile?> seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    return result?.files.first;
  }

  /// Leer preview de un archivo (primeros 5 registros)
  Future<List<Map<String, String>>> preview(PlatformFile file) async {
    final contenido = await File(file.path!).readAsString();

    if (file.extension == 'csv') {
      return _parsearCSV(contenido).take(5).toList();
    } else if (file.extension == 'json') {
      return _parsearJSON(contenido).take(5).toList();
    }
    return [];
  }

  /// Importar archivo completo (los contactos quedan como pendientes)
  Future<ImportResult> importar(PlatformFile file) async {
    final contenido = await File(file.path!).readAsString();
    List<Map<String, String>> contactos;

    if (file.extension == 'csv') {
      contactos = _parsearCSV(contenido);
    } else if (file.extension == 'json') {
      contactos = _parsearJSON(contenido);
    } else {
      return ImportResult(errorDetalle: 'Formato no soportado');
    }

    int nuevos = 0, duplicados = 0, errores = 0;

    for (final c in contactos) {
      final nombre = c['nombre'] ?? '';
      final apellido = c['apellido'] ?? '';
      final telefono = c['telefono'] ?? '';

      if (nombre.length < 2 || apellido.length < 2 || telefono.length < 5) {
        errores++;
        continue;
      }

      final resultado = await _supabase.registrarContacto(
        nombre: nombre,
        apellido: apellido,
        telefono: telefono,
        direccion: c['direccion'],
        ci: c['ci'],
      );

      if (resultado['error'] != null) {
        final error = resultado['error'].toString();
        if (error.contains('duplicate') || error.contains('unique')) {
          duplicados++;
        } else {
          errores++;
        }
      } else {
        nuevos++;
      }
    }

    return ImportResult(
      procesados: contactos.length,
      nuevos: nuevos,
      duplicados: duplicados,
      errores: errores,
    );
  }

  List<Map<String, String>> _parsearCSV(String contenido) {
    final rows = const CsvToListConverter().convert(contenido);
    if (rows.length < 2) return [];

    final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
    final contactos = <Map<String, String>>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      final map = <String, String>{};
      for (var j = 0; j < headers.length && j < row.length; j++) {
        map[headers[j]] = row[j].toString().trim();
      }
      if (map['nombre'] != null && map['telefono'] != null) {
        contactos.add(map);
      }
    }
    return contactos;
  }

  List<Map<String, String>> _parsearJSON(String contenido) {
    final data = json.decode(contenido);
    List items;

    if (data is Map && data.containsKey('contactos')) {
      items = data['contactos'] as List;
    } else if (data is List) {
      items = data;
    } else {
      return [];
    }

    return items.map((item) {
      final map = <String, String>{};
      (item as Map).forEach((key, value) {
        if (value != null) map[key.toString()] = value.toString();
      });
      return map;
    }).where((m) => m['nombre'] != null && m['telefono'] != null).toList();
  }
}
