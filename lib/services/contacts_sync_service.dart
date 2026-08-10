import 'package:flutter/services.dart';
import '../models/contacto.dart';

/// Resultado progresivo de sincronización
class SyncProgress {
  final int total;
  final int procesados;
  final int created;
  final int updated;
  final int exists;
  final int errors;
  final String? contactoActual;
  final bool completado;

  SyncProgress({
    required this.total,
    required this.procesados,
    this.created = 0,
    this.updated = 0,
    this.exists = 0,
    this.errors = 0,
    this.contactoActual,
    this.completado = false,
  });

  double get progreso => total > 0 ? procesados / total : 0;
}

/// Servicio para sincronizar contactos con la agenda nativa del teléfono
class ContactsSyncService {
  static const _channel = MethodChannel('guia_telefonica/contacts');

  /// Sincronizar con progreso (Stream)
  Stream<SyncProgress> syncContactosStream(List<Contacto> contactos, {Map<String, int>? reportes}) async* {
    int created = 0, updated = 0, exists = 0, errors = 0;
    final total = contactos.length;

    for (var i = 0; i < contactos.length; i++) {
      final c = contactos[i];
      final reporteCount = reportes?[c.id] ?? 0;

      try {
        final result = await _channel.invokeMethod('syncContact', {
          'nombre': c.nombre,
          'apellido': c.apellido,
          'telefono': c.telefono,
          'reportado': reporteCount >= 3,
        });

        switch (result) {
          case 'created':
            created++;
            break;
          case 'updated':
            updated++;
            break;
          case 'exists':
            exists++;
            break;
        }
      } catch (_) {
        errors++;
      }

      // Emitir progreso cada 5 contactos o al final
      if (i % 5 == 0 || i == contactos.length - 1) {
        yield SyncProgress(
          total: total,
          procesados: i + 1,
          created: created,
          updated: updated,
          exists: exists,
          errors: errors,
          contactoActual: '${c.nombre} ${c.apellido}',
          completado: i == contactos.length - 1,
        );
      }
    }
  }

  /// Sincronizar sin progreso (retrocompatible)
  Future<Map<String, int>> syncContactos(List<Contacto> contactos, {Map<String, int>? reportes}) async {
    int created = 0, updated = 0, exists = 0;

    for (final c in contactos) {
      final reporteCount = reportes?[c.id] ?? 0;
      try {
        final result = await _channel.invokeMethod('syncContact', {
          'nombre': c.nombre,
          'apellido': c.apellido,
          'telefono': c.telefono,
          'reportado': reporteCount >= 3,
        });

        switch (result) {
          case 'created':
            created++;
            break;
          case 'updated':
            updated++;
            break;
          case 'exists':
            exists++;
            break;
        }
      } catch (_) {}
    }

    return {'created': created, 'updated': updated, 'exists': exists};
  }

  /// Eliminar todos los contactos de "Guía Telefónica" de la agenda
  Future<int> removeAll() async {
    try {
      final count = await _channel.invokeMethod('removeGuiaContacts');
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
