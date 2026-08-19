import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../providers/sync_provider.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';

class BackgroundSyncService {
  static const _syncChannel = MethodChannel('guia_telefonica/sync');
  static bool _cancelRequested = false;
  static bool _running = false;

  static bool get isRunning => _running;

  // ─── Arrancar sync (opcionalmente desde un offset guardado) ───────────
  static Future<void> iniciarSync(WidgetRef ref, {int desdeOffset = 0}) async {
    if (_running) return;
    _cancelRequested = false;
    _running = true;
    debugPrint('BGSYNC: iniciando desde offset=$desdeOffset');
    try {
      // Parar cualquier instancia previa del servicio antes de arrancar
      await _syncChannel.invokeMethod('cancelSync');
      await Future.delayed(const Duration(milliseconds: 300));
      await _syncChannel.invokeMethod('startSync');
    } catch (e) {
      debugPrint('BGSYNC: ForegroundService no disponible: $e');
    }
    await _ejecutarSync(ref, desdeOffset: desdeOffset);
  }

  static void cancelarSync() {
    _cancelRequested = true;
    _syncChannel.invokeMethod('cancelSync').catchError((_) {});
  }

  // ─── Lógica principal ─────────────────────────────────────────────────
  static Future<void> _ejecutarSync(WidgetRef ref, {int desdeOffset = 0}) async {
    final notifier = ref.read(syncProvider.notifier);
    final supabase  = SupabaseService();
    final localDb   = LocalDatabaseService();
    int offsetActual = desdeOffset;

    void update(String estado, int desc, int total, {String? error}) {
      switch (estado) {
        case 'preparando':  notifier.setPreparando();
        case 'descargando': notifier.setDescargando(desc, total);
        case 'guardando':   notifier.setGuardando();
        case 'completado':  notifier.setCompletado(desc);
        case 'cancelado':   notifier.setCancelado();
        case 'error':
          notifier.setError(error ?? 'desconocido',
              offsetGuardado: offsetActual);
      }
      final texto = total > 0 ? '$desc de $total contactos' : estado;
      _syncChannel.invokeMethod('updateNotification', {'texto': texto})
          .catchError((_) {});
    }

    try {
      update('preparando', 0, 0);

      final total = await supabase.contarContactosAprobados();
      // Si continuamos desde offset guardado, los ya descargados son el offset
      int descargados = desdeOffset;
      update('descargando', descargados, total);

      int  offset  = desdeOffset;
      bool hayMas  = true;
      const pageSize = 500;

      while (hayMas && !_cancelRequested) {
        offsetActual = offset; // guardar por si falla aquí
        List? lista;

        // Reintentar una vez si hay timeout de statement
        for (int intento = 0; intento < 2; intento++) {
          try {
            final response = await Supabase.instance.client
                .from('contactos')
                .select(
                  'id, nombre, apellido, telefono, direccion, ci, estado, '
                  'categoria_id, verificado, score_riesgo, tiene_reportes, '
                  'pais, provincia, municipio, fecha_creacion, fecha_aprobacion',
                )
                .eq('estado', 'aprobado')
                .isFilter('deleted_at', null)
                .order('nombre')
                .range(offset, offset + pageSize - 1);
            lista = response as List;
            break;
          } catch (e) {
            if (intento == 0 && e.toString().contains('canceling')) {
              debugPrint('BGSYNC: timeout offset=$offset, reintentando en 3s...');
              await Future.delayed(const Duration(seconds: 3));
            } else {
              rethrow;
            }
          }
        }

        if (lista == null || lista.isEmpty) break;

        final pagina = lista
            .map((j) => Contacto.fromJson(j as Map<String, dynamic>))
            .toList();
        await localDb.sincronizarBatch(pagina);

        descargados  += pagina.length;
        offset       += pageSize;
        offsetActual  = offset;
        hayMas        = lista.length == pageSize;

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

// ─── Widget raíz ─────────────────────────────────────────────────────────
class SyncServiceListener extends ConsumerWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
