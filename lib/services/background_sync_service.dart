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
/// El ref de Riverpod se pasa directamente — sin referencias estáticas frágiles.
class BackgroundSyncService {
  static const _syncChannel = MethodChannel('guia_telefonica/sync');
  static bool _cancelRequested = false;
  static bool _running = false;

  static bool get isRunning => _running;

  // ─── Arrancar sync — recibe ref para actualizar Riverpod directamente ─
  static Future<void> iniciarSync(WidgetRef ref) async {
    if (_running) {
      debugPrint('BGSYNC: ya corriendo, ignorando');
      return;
    }
    _cancelRequested = false;
    _running = true;
    debugPrint('BGSYNC: iniciando sync...');

    try {
      await _syncChannel.invokeMethod('startSync');
      debugPrint('BGSYNC: ForegroundService arrancado');
    } catch (e) {
      debugPrint('BGSYNC: ForegroundService no disponible: $e');
    }

    await _ejecutarSync(ref);
  }

  // ─── Cancelar ─────────────────────────────────────────────
  static void cancelarSync() {
    _cancelRequested = true;
    _syncChannel.invokeMethod('cancelSync').catchError((_) {});
  }

  // ─── Lógica principal ─────────────────────────────────────
  static Future<void> _ejecutarSync(WidgetRef ref) async {
    final notifier = ref.read(syncProvider.notifier);
    final supabase  = SupabaseService();
    final localDb   = LocalDatabaseService();

    void update(String estado, int desc, int total, {String? error}) {
      switch (estado) {
        case 'preparando':  notifier.setPreparando();
        case 'descargando': notifier.setDescargando(desc, total);
        case 'guardando':   notifier.setGuardando();
        case 'completado':  notifier.setCompletado(desc);
        case 'cancelado':   notifier.setCancelado();
        case 'error':       notifier.setError(error ?? 'desconocido');
      }
      // Actualizar notificación Android
      final texto = total > 0 ? '$desc de $total contactos' : estado;
      _syncChannel.invokeMethod('updateNotification', {'texto': texto})
          .catchError((_) {});
    }

    try {
      update('preparando', 0, 0);

      final total = await supabase.contarContactosAprobados();
      update('descargando', 0, total);

      int  descargados = 0;
      int  offset      = 0;
      bool hayMas      = true;
      const pageSize   = 1000;

      while (hayMas && !_cancelRequested) {
        final response = await Supabase.instance.client
            .from('contactos')
            .select('*, categorias(nombre, icono)')
            .eq('estado', 'aprobado')
            .isFilter('deleted_at', null)
            .order('nombre')
            .range(offset, offset + pageSize - 1);

        final lista = response as List;
        if (lista.isEmpty) break;

        final pagina = lista.map((j) => Contacto.fromJson(j)).toList();
        await localDb.sincronizarBatch(pagina);

        descargados += pagina.length;
        offset      += pageSize;
        hayMas       = lista.length == pageSize;

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
      update('error', 0, 0, error: e.toString());
    } finally {
      _running = false;
      _cancelRequested = false;
      _syncChannel.invokeMethod('cancelSync').catchError((_) {});
    }
  }
}

// ─── Widget raíz — solo existe para mantener la API consistente ──────────
class SyncServiceListener extends ConsumerWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) => child;
}
