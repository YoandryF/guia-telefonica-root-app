import 'package:flutter/services.dart';
import '../models/contacto.dart';

/// Servicio para sincronizar contactos con la agenda nativa del teléfono
class ContactsSyncService {
  static const _channel = MethodChannel('guia_telefonica/contacts');

  /// Sincronizar una lista de contactos con la agenda
  /// Retorna: {created: X, updated: X, exists: X}
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
