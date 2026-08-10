import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImportResult {
  final int procesados;
  final int nuevos;
  final int duplicados;
  final int errores;
  final String? errorDetalle;
  final bool completado;
  final int chunkActual;
  final int totalChunks;

  ImportResult({this.procesados = 0, this.nuevos = 0, this.duplicados = 0, this.errores = 0, this.errorDetalle, this.completado = true, this.chunkActual = 0, this.totalChunks = 0});
}

class ImportService {
  static const _chunkSize = 100;
  static const _prefKey = 'import_progress';

  Future<PlatformFile?> seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'json']);
    return result?.files.first;
  }

  Future<List<Map<String, String>>> preview(PlatformFile file) async {
    final contenido = await File(file.path!).readAsString();
    if (file.extension == 'csv') return _parsearCSV(contenido).take(5).toList();
    if (file.extension == 'json') return _parsearJSON(contenido).take(5).toList();
    return [];
  }

  Future<int> contarRegistros(PlatformFile file) async {
    final contenido = await File(file.path!).readAsString();
    if (file.extension == 'csv') return _parsearCSV(contenido).length;
    if (file.extension == 'json') return _parsearJSON(contenido).length;
    return 0;
  }

  /// Importar con batch, progreso y capacidad de reintentar
  Stream<ImportResult> importarStream(PlatformFile file, {int desdeChunk = 0}) async* {
    final contenido = await File(file.path!).readAsString();
    List<Map<String, String>> contactos;

    if (file.extension == 'csv') {
      contactos = _parsearCSV(contenido);
    } else if (file.extension == 'json') {
      contactos = _parsearJSON(contenido);
    } else {
      yield ImportResult(errorDetalle: 'Formato no soportado', completado: false);
      return;
    }

    final chunks = <List<Map<String, String>>>[];
    for (var i = 0; i < contactos.length; i += _chunkSize) {
      chunks.add(contactos.sublist(i, i + _chunkSize > contactos.length ? contactos.length : i + _chunkSize));
    }

    int nuevos = 0, duplicados = 0, errores = 0;
    final client = Supabase.instance.client;

    // Si reiniciamos, sumar lo anterior
    if (desdeChunk > 0) {
      final prefs = await SharedPreferences.getInstance();
      nuevos = prefs.getInt('import_nuevos') ?? 0;
      duplicados = prefs.getInt('import_duplicados') ?? 0;
      errores = prefs.getInt('import_errores') ?? 0;
    }

    for (var i = desdeChunk; i < chunks.length; i++) {
      final chunk = chunks[i];

      // Preparar batch
      final batch = chunk.where((c) =>
        (c['nombre'] ?? '').length >= 2 &&
        (c['apellido'] ?? '').length >= 2 &&
        (c['telefono'] ?? '').length >= 5
      ).map((c) => {
        'nombre': c['nombre']!,
        'apellido': c['apellido']!,
        'telefono': c['telefono']!,
        'direccion': c['direccion']?.isNotEmpty == true ? c['direccion'] : null,
        'ci': c['ci']?.isNotEmpty == true ? c['ci'] : null,
        'estado': 'pendiente',
        'creado_desde': 'app',
      }).toList();

      errores += chunk.length - batch.length;

      try {
        // Intentar batch primero (rápido)
        final response = await client.from('contactos').insert(batch).select();
        nuevos += response.length;
      } catch (batchErr) {
        // Si falla batch (duplicados), procesar individualmente
        for (final item in batch) {
          try {
            await client.from('contactos').insert(item).select();
            nuevos++;
          } catch (insertErr) {
            final errStr = insertErr.toString();
            if (errStr.contains('duplicate') || errStr.contains('unique') || errStr.contains('23505')) {
              final telefono = item['telefono'] as String?;
              List existentes = [];
              if (telefono != null) {
                existentes = await client.from('contactos').select().eq('telefono', telefono);
              }
              if (existentes.isNotEmpty) {
                final existente = existentes.first as Map<String, dynamic>;
                final hayDiferencia = (item['nombre'] != existente['nombre']) ||
                    (item['apellido'] != existente['apellido']) ||
                    (item['direccion'] != existente['direccion']) ||
                    (item['ci'] != existente['ci']);
                if (hayDiferencia) {
                  final prefs = await SharedPreferences.getInstance();
                  final conflictos = prefs.getStringList('import_conflictos') ?? [];
                  conflictos.add('\${item["telefono"]}|\${item["nombre"]}|\${item["apellido"]}|\${item["direccion"] ?? ""}');
                  await prefs.setStringList('import_conflictos', conflictos);
                }
              }
              duplicados++;
            } else {
              errores++;
            }
          }
        }
      }
      } catch (e) {
        // Error de conexión — guardar progreso y parar
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('import_chunk', i);
        await prefs.setInt('import_nuevos', nuevos);
        await prefs.setInt('import_duplicados', duplicados);
        await prefs.setInt('import_errores', errores);
        await prefs.setString('import_file', file.path!);

        yield ImportResult(
          procesados: i * _chunkSize,
          nuevos: nuevos,
          duplicados: duplicados,
          errores: errores,
          errorDetalle: 'Error en chunk ${i + 1}/${chunks.length}: $e',
          completado: false,
          chunkActual: i,
          totalChunks: chunks.length,
        );
        return;
      }

      // Emitir progreso
      yield ImportResult(
        procesados: (i + 1) * _chunkSize > contactos.length ? contactos.length : (i + 1) * _chunkSize,
        nuevos: nuevos,
        duplicados: duplicados,
        errores: errores,
        completado: i == chunks.length - 1,
        chunkActual: i + 1,
        totalChunks: chunks.length,
      );
    }

    // Limpiar progreso guardado
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('import_chunk');
    await prefs.remove('import_nuevos');
    await prefs.remove('import_duplicados');
    await prefs.remove('import_errores');
    await prefs.remove('import_file');
  }

  /// Verificar si hay importación pendiente de reintentar
  Future<Map<String, dynamic>?> getImportPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    final chunk = prefs.getInt('import_chunk');
    if (chunk == null) return null;
    return {
      'chunk': chunk,
      'file': prefs.getString('import_file'),
      'nuevos': prefs.getInt('import_nuevos') ?? 0,
      'duplicados': prefs.getInt('import_duplicados') ?? 0,
      'errores': prefs.getInt('import_errores') ?? 0,
    };
  }

  Future<void> cancelarImportPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('import_chunk');
    await prefs.remove('import_nuevos');
    await prefs.remove('import_duplicados');
    await prefs.remove('import_errores');
    await prefs.remove('import_file');
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
      if (map['nombre'] != null && map['telefono'] != null) contactos.add(map);
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
