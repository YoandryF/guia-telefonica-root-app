import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';

/// Progreso de sincronización emitido por [SyncRepository.syncStream].
class SyncProgress {
  final int descargados;
  final int total;
  final String? cursorNombre;
  final String? cursorId;
  final bool completado;
  final String? error;

  const SyncProgress({
    required this.descargados,
    required this.total,
    this.cursorNombre,
    this.cursorId,
    this.completado = false,
    this.error,
  });
}

/// Repositorio de sincronización — encapsula la lógica de keyset pagination
/// que antes vivía en BackgroundSyncService, delegando I/O a los servicios.
class SyncRepository {
  final LocalDatabaseService _local;
  final SupabaseService _remote;

  SyncRepository({LocalDatabaseService? local, SupabaseService? remote})
      : _local = local ?? LocalDatabaseService(),
        _remote = remote ?? SupabaseService();

  Future<int> contarRemoto() {
    return _remote.contarContactosAprobados();
  }

  Future<int> contarLocal() {
    return _local.countContactos();
  }

  Future<DateTime?> getUltimaSync() {
    return _local.getUltimaSincronizacion();
  }

  Future<void> guardarUltimaSync(DateTime fecha) {
    return _local.guardarUltimaSincronizacion(fecha);
  }

  /// Keyset pagination sync — emite [SyncProgress] por cada página descargada.
  /// La lógica replica el while-loop de BackgroundSyncService pero como Stream puro,
  /// desacoplado de WidgetRef y MethodChannel.
  Stream<SyncProgress> syncStream({
    String? desdeNombre,
    String? desdeId,
    int pageSize = 2000,
  }) async* {
    String? cursorNombre = desdeNombre;
    String? cursorId = desdeId;

    final total = await _remote.contarContactosAprobados();
    int descargados = desdeNombre != null ? await _local.countContactos() : 0;

    yield SyncProgress(descargados: descargados, total: total);

    bool hayMas = true;

    while (hayMas) {
      List<dynamic>? lista;

      for (int intento = 0; intento < 2; intento++) {
        try {
          final params = <String, dynamic>{'p_page_size': pageSize};
          if (cursorNombre != null) {
            params['p_cursor_nombre'] = cursorNombre;
            params['p_cursor_id'] = cursorId;
          }
          final response = await Supabase.instance.client
              .rpc('get_contactos_sync', params: params)
              .timeout(const Duration(seconds: 20));
          lista = response as List<dynamic>;
          break;
        } catch (e) {
          if (intento == 0) {
            debugPrint('SyncRepository: error página cursor=$cursorNombre, reintentando...');
            await Future.delayed(const Duration(seconds: 3));
          } else {
            yield SyncProgress(
              descargados: descargados,
              total: total,
              cursorNombre: cursorNombre,
              cursorId: cursorId,
              error: e.toString(),
            );
            return;
          }
        }
      }

      if (lista == null || lista.isEmpty) break;

      final pagina = lista
          .map((j) => Contacto.fromJson(j as Map<String, dynamic>))
          .toList();
      await _local.sincronizarBatch(pagina);

      descargados += pagina.length;
      hayMas = pagina.length == pageSize;

      if (pagina.isNotEmpty) {
        cursorNombre = pagina.last.nombre;
        cursorId = pagina.last.id;
      }

      yield SyncProgress(
        descargados: descargados,
        total: total,
        cursorNombre: cursorNombre,
        cursorId: cursorId,
      );
    }

    yield SyncProgress(
      descargados: descargados,
      total: total,
      cursorNombre: cursorNombre,
      cursorId: cursorId,
      completado: true,
    );
  }

  /// Actualiza flags de reportes en SQLite: limpia todos y activa los reportados.
  Future<void> actualizarFlags() async {
    final ids = await _remote.getContactosConReportes();
    await _local.actualizarReportesEficiente(ids);
  }

  Future<List<Contacto>> getIncrementalDesde(DateTime fecha) {
    return _remote.getContactosAprobadosDesde(fecha);
  }

  Future<List<String>> getEliminadosDesde(DateTime fecha) {
    return _remote.getContactosEliminadosDesde(fecha);
  }
}
