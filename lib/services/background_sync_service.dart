import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../providers/sync_provider.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';

/// Servicio de sincronización en background.
/// Usa keyset pagination (cursor compuesto nombre+id) en vez de OFFSET.
/// Elimina el timeout en tablas de 900k+ filas — O(log N) por página.
class BackgroundSyncService {
  static const _syncChannel = MethodChannel('guia_telefonica/sync');
  static bool _cancelRequested = false;
  static bool _running = false;

  static bool get isRunning => _running;

  static Future<void> iniciarSync(WidgetRef ref, {
    String? desdeNombre,
    String? desdeId,
  }) async {
    if (_running) return;
    _cancelRequested = false;
    _running = true;
    debugPrint('BGSYNC: iniciando keyset sync desde nombre=${desdeNombre ?? "inicio"}');
    try {
      await _syncChannel.invokeMethod('cancelSync');
      await Future.delayed(const Duration(milliseconds: 200));
      await _syncChannel.invokeMethod('startSync');
    } catch (e) {
      debugPrint('BGSYNC: ForegroundService no disponible: $e');
    }
    await _ejecutarSync(ref, desdeNombre: desdeNombre, desdeId: desdeId);
  }

  static void cancelarSync() {
    _cancelRequested = true;
    _syncChannel.invokeMethod('cancelSync').catchError((_) {});
  }

  static Future<void> _ejecutarSync(WidgetRef ref, {
    String? desdeNombre,
    String? desdeId,
  }) async {
    final notifier = ref.read(syncProvider.notifier);
    final supabase  = SupabaseService();
    final localDb   = LocalDatabaseService();

    // Cursor actual — se actualiza con cada página
    String? cursorNombre = desdeNombre;
    String? cursorId     = desdeId;

    void update(String estado, int desc, int total, {String? error}) {
      switch (estado) {
        case 'preparando':  notifier.setPreparando();
        case 'descargando': notifier.setDescargando(desc, total);
        case 'guardando':   notifier.setGuardando();
        case 'completado':  notifier.setCompletado(desc);
        case 'cancelado':   notifier.setCancelado();
        case 'error':
          notifier.setError(
            error ?? 'desconocido',
            cursorNombre: cursorNombre,
            cursorId:     cursorId,
          );
      }
      final texto = total > 0 ? 'Sincronizando $desc de $total' : estado;
      _syncChannel.invokeMethod('updateNotification', {'texto': texto})
          .catchError((_) {});
    }

    try {
      update('preparando', 0, 0);

      final total = await supabase.contarContactosAprobados();
      // Si venimos de cursor, los ya descargados son los que hay en local
      int descargados = desdeNombre != null
          ? await localDb.countContactos()
          : 0;
      update('descargando', descargados, total);

      bool hayMas  = true;
      // Con keyset pagination el tiempo por página es O(log N) — constante.
      // Subimos a 2000 para reducir el número de requests de 1800 a 450.
      const pageSize = 2000;

      while (hayMas && !_cancelRequested) {
        List<dynamic>? lista;

        // Reintentar una vez si hay error — verificar cancelación en el delay
        for (int intento = 0; intento < 2; intento++) {
          if (_cancelRequested) break;
          try {
            // Timeout por página de 20s — si tarda más, pasar al siguiente intento
            final params = <String, dynamic>{'p_page_size': pageSize};
            if (cursorNombre != null) {
              params['p_cursor_nombre'] = cursorNombre;
              params['p_cursor_id']     = cursorId;
            }
            final response = await Supabase.instance.client
                .rpc('get_contactos_sync', params: params)
                .timeout(const Duration(seconds: 20));
            lista = response as List<dynamic>;
            break;
          } catch (e) {
            if (_cancelRequested) break;
            if (intento == 0) {
              debugPrint('BGSYNC: error página cursor=$cursorNombre, reintentando en 3s... $e');
              // Delay interrompible: verificar cancelación cada 500ms
              for (int ms = 0; ms < 6 && !_cancelRequested; ms++) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
            } else {
              rethrow;
            }
          }
        }

        if (_cancelRequested) break;
        if (lista == null || lista.isEmpty) break;

        final pagina = lista
            .map((j) => Contacto.fromJson(j as Map<String, dynamic>))
            .toList();
        await localDb.sincronizarBatch(pagina);

        descargados += pagina.length;
        hayMas       = pagina.length == pageSize;

        // Actualizar cursor con el último registro de la página
        if (pagina.isNotEmpty) {
          cursorNombre = pagina.last.nombre;
          cursorId     = pagina.last.id;
        }

        update('descargando', descargados, total);
      }

      if (_cancelRequested) {
        update('cancelado', descargados, total);
      } else {
        update('guardando', descargados, total);
        try {
          final ids = await supabase.getContactosConReportes();
          await localDb.actualizarReportesEficiente(ids);
          await localDb.guardarUltimaSincronizacion(DateTime.now());
        } catch (_) {}
        update('completado', descargados, total);
      }
    } catch (e) {
      debugPrint('BGSYNC error: $e');
      update('error', 0, 0, error: e.toString());
    } finally {
      _running = false;
      _cancelRequested = false;
      _syncChannel.invokeMethod('cancelSync').catchError((_) {});
    }
  }
}

class SyncServiceListener extends ConsumerWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
