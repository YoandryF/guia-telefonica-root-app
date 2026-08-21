import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sanitizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImportResult {
  final int procesados;
  final int nuevos;
  final int duplicados;
  final int errores;
  final int actualizados;
  final String? errorDetalle;
  final bool completado;
  final int chunkActual;
  final int totalChunks;
  final List<Map<String, String>> registrosConError; // ← nuevo

  ImportResult({
    this.procesados = 0,
    this.nuevos = 0,
    this.duplicados = 0,
    this.errores = 0,
    this.actualizados = 0,
    this.errorDetalle,
    this.completado = true,
    this.chunkActual = 0,
    this.totalChunks = 0,
    this.registrosConError = const [],
  });
}

class ImportService {
  static const _chunkSize = 500;
  static const _estadosValidos = ['pendiente', 'aprobado', 'rechazado'];

  Future<PlatformFile?> seleccionarArchivo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'json']);
    return result?.files.first;
  }

  /// Lee el contenido de un archivo detectando el encoding automáticamente.
  /// Intenta UTF-8 primero. Si detecta caracteres de reemplazo (U+FFFD, que
  /// aparecen como ??? cuando se muestra), reintenta con Latin-1/ISO-8859-1
  /// que es el encoding común de CSVs exportados desde Excel en Windows.
  Future<String> _leerConEncodingDetectado(String path) async {
    final bytes = await File(path).readAsBytes();

    // Intentar UTF-8 estricto primero
    try {
      final texto = utf8.decode(bytes, allowMalformed: false);
      // Verificar que no haya caracteres de reemplazo U+FFFD (indica encoding incorrecto)
      if (!texto.contains('\uFFFD')) return texto;
    } catch (_) {
      // UTF-8 falló — continuar con Latin-1
    }

    // Fallback: Latin-1 / ISO-8859-1 (cada byte es un codepoint directo)
    // Esto cubre Windows-1252 para los caracteres comunes del español
    return String.fromCharCodes(bytes);
  }

  Future<List<Map<String, String>>> preview(PlatformFile file) async {
    final contenido = await _leerConEncodingDetectado(file.path!);
    if (file.extension == 'csv') return _parsearCSV(contenido).take(5).toList();
    if (file.extension == 'json') return _parsearJSON(contenido).take(5).toList();
    return [];
  }

  Future<int> contarRegistros(PlatformFile file) async {
    final contenido = await _leerConEncodingDetectado(file.path!);
    if (file.extension == 'csv') return _parsearCSV(contenido).length;
    if (file.extension == 'json') return _parsearJSON(contenido).length;
    return 0;
  }

  Stream<ImportResult> importarStream(PlatformFile file, {int desdeChunk = 0}) async* {
    final contenido = await _leerConEncodingDetectado(file.path!);
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

    int nuevos = 0, duplicados = 0, errores = 0, actualizados = 0;
    final client = Supabase.instance.client;
    final List<Map<String, String>> registrosConError = []; // ← acumula errores

    if (desdeChunk > 0) {
      final prefs = await SharedPreferences.getInstance();
      nuevos = prefs.getInt('import_nuevos') ?? 0;
      duplicados = prefs.getInt('import_duplicados') ?? 0;
      errores = prefs.getInt('import_errores') ?? 0;
      actualizados = prefs.getInt('import_actualizados') ?? 0;
    }

    for (var i = desdeChunk; i < chunks.length; i++) {
      final chunk = chunks[i];
      final batch = chunk.map((c) => Sanitizer.contacto(c)).where((c) {
        final nombre   = c['nombre']   ?? '';
        final apellido = c['apellido'] ?? '';
        final telefono = c['telefono'] ?? '';
        if (nombre.length < 2) {
          registrosConError.add({...c, '_motivo': 'Nombre muy corto: "$nombre"'});
          return false;
        }
        if (apellido.length < 2) {
          registrosConError.add({...c, '_motivo': 'Apellido muy corto: "$apellido"'});
          return false;
        }
        if (telefono.length < 5) {
          registrosConError.add({...c, '_motivo': 'Teléfono inválido: "$telefono"'});
          return false;
        }
        // Rechazar datos con encoding corrupto (???) antes de subir a Supabase
        if (nombre.contains('?') || apellido.contains('?') || nombre.contains('\uFFFD') || apellido.contains('\uFFFD')) {
          registrosConError.add({...c, '_motivo': 'Encoding corrupto — revisar archivo CSV (usar UTF-8)'});
          return false;
        }
        // Rechazar sin ubicación
        final provincia = c['provincia'] ?? '';
        final municipio = c['municipio'] ?? '';
        if (provincia.trim().isEmpty || municipio.trim().isEmpty) {
          registrosConError.add({...c, '_motivo': 'Falta provincia y/o municipio — campo obligatorio'});
          return false;
        }
        return true;
      }).map((c) {
        final estadoArchivo = c['estado']?.toLowerCase().trim();
        final estado = _estadosValidos.contains(estadoArchivo) ? estadoArchivo! : 'pendiente';

        final item = <String, dynamic>{
          'nombre': c['nombre']!,
          'apellido': c['apellido']!,
          'telefono': c['telefono']!,
          'direccion': c['direccion']?.isNotEmpty == true ? c['direccion'] : null,
          'ci': c['ci']?.isNotEmpty == true ? c['ci'] : null,
          'provincia': c['provincia']?.isNotEmpty == true ? c['provincia'] : null,
          'municipio': c['municipio']?.isNotEmpty == true ? c['municipio'] : null,
          'pais': c['pais']?.isNotEmpty == true ? c['pais'] : null,
          'estado': estado,
          'creado_desde': 'app',
          'ultima_modificacion': DateTime.now().toIso8601String(),
        };

        if (estado == 'aprobado') {
          final fechaArchivo = c['fecha_aprobacion'];
          if (fechaArchivo != null && fechaArchivo.isNotEmpty) {
            item['fecha_aprobacion'] = fechaArchivo;
          } else {
            item['fecha_aprobacion'] = DateTime.now().toIso8601String();
          }
        }

        return item;
      }).toList();

      errores += chunk.length - batch.length;

      if (batch.isEmpty) {
        yield ImportResult(
          procesados: (i + 1) * _chunkSize > contactos.length ? contactos.length : (i + 1) * _chunkSize,
          nuevos: nuevos, duplicados: duplicados, errores: errores, actualizados: actualizados,
          completado: i == chunks.length - 1, chunkActual: i + 1, totalChunks: chunks.length,
          registrosConError: List.from(registrosConError),
        );
        continue;
      }

      try {
        // Primero: consultar cuáles teléfonos ya existen para distinguir nuevos vs actualizados
        final telefonos = batch.map((b) => b['telefono'] as String).toList();
        final existentes = await client.from('contactos')
            .select('telefono, nombre, apellido')
            .inFilter('telefono', telefonos);
        
        final existentesMap = <String, Map<String, dynamic>>{};
        for (final e in existentes) {
          existentesMap[e['telefono'] as String] = e;
        }

        final realmente_nuevos = <Map<String, dynamic>>[];
        final para_actualizar = <Map<String, dynamic>>[];

        for (final item in batch) {
          final tel = item['telefono'] as String;
          if (existentesMap.containsKey(tel)) {
            para_actualizar.add(item);
          } else {
            realmente_nuevos.add(item);
          }
        }

        // Insertar los nuevos
        if (realmente_nuevos.isNotEmpty) {
          await client.from('contactos').upsert(realmente_nuevos, onConflict: 'telefono');
          nuevos += realmente_nuevos.length;
        }

        // Actualizar los existentes
        if (para_actualizar.isNotEmpty) {
          await client.from('contactos').upsert(para_actualizar, onConflict: 'telefono');
          actualizados += para_actualizar.length;
        }

      } catch (e) {
        final errStr = e.toString();
        
        if (errStr.contains('duplicate') || errStr.contains('unique') || errStr.contains('23505')) {
          // Conflicto de CI (no teléfono) — hacer upsert sin CI
          try {
            final batchSinCi = batch.map((item) {
              final copy = Map<String, dynamic>.from(item);
              copy.remove('ci');
              return copy;
            }).toList();
            
            await client.from('contactos').upsert(batchSinCi, onConflict: 'telefono');
            actualizados += batch.length;
          } catch (_) {
            // Último recurso: insertar uno por uno
            for (final item in batch) {
              try {
                await client.from('contactos').upsert([item], onConflict: 'telefono');
                actualizados++;
              } catch (_) {
                duplicados++;
              }
            }
          }
        } else if (errStr.contains('timeout') || errStr.contains('SocketException') || errStr.contains('Connection')) {
          // Error de red — guardar progreso para reintentar
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('import_chunk', i);
          await prefs.setInt('import_nuevos', nuevos);
          await prefs.setInt('import_duplicados', duplicados);
          await prefs.setInt('import_errores', errores);
          await prefs.setInt('import_actualizados', actualizados);
          await prefs.setString('import_file', file.path!);

          yield ImportResult(
            procesados: i * _chunkSize,
            nuevos: nuevos, duplicados: duplicados, errores: errores, actualizados: actualizados,
            errorDetalle: 'Error de conexión en chunk ${i + 1}/${chunks.length}. Puedes reintentar.',
            completado: false, chunkActual: i, totalChunks: chunks.length,
            registrosConError: List.from(registrosConError),
          );
          return;
        } else {
          // Error desconocido — loguear y continuar
          errores += batch.length;
          // Registrar cada item del batch como error con el motivo
          for (final item in batch) {
            registrosConError.add({
              'nombre':   item['nombre']?.toString() ?? '',
              'apellido': item['apellido']?.toString() ?? '',
              'telefono': item['telefono']?.toString() ?? '',
              '_motivo':  'Error BD: ${errStr.length > 100 ? errStr.substring(0, 100) : errStr}',
            });
          }
        }
      }

      // Guardar progreso periódicamente
      if (i % 5 == 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('import_chunk', i);
        await prefs.setInt('import_nuevos', nuevos);
        await prefs.setInt('import_duplicados', duplicados);
        await prefs.setInt('import_errores', errores);
        await prefs.setInt('import_actualizados', actualizados);
        await prefs.setString('import_file', file.path!);
      }

      yield ImportResult(
        procesados: (i + 1) * _chunkSize > contactos.length ? contactos.length : (i + 1) * _chunkSize,
        nuevos: nuevos,
        duplicados: duplicados,
        errores: errores,
        actualizados: actualizados,
        completado: i == chunks.length - 1,
        chunkActual: i + 1,
        totalChunks: chunks.length,
        registrosConError: List.from(registrosConError),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('import_chunk');
    await prefs.remove('import_nuevos');
    await prefs.remove('import_duplicados');
    await prefs.remove('import_errores');
    await prefs.remove('import_actualizados');
    await prefs.remove('import_file');
  }

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
      'actualizados': prefs.getInt('import_actualizados') ?? 0,
    };
  }

  Future<void> cancelarImportPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('import_chunk');
    await prefs.remove('import_nuevos');
    await prefs.remove('import_duplicados');
    await prefs.remove('import_errores');
    await prefs.remove('import_actualizados');
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
