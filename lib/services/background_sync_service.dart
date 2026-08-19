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
///
/// El ForegroundService nativo Kotlin (SyncForegroundService.kt) mantiene
/// el proceso Android vivo con pantalla apagada.
/// La lógica de descarga y el estado corren completamente en Dart/Riverpod.
/// No hay Isolate separado — mismo proceso, acceso directo al estado.
class BackgroundSyncService {
  static const _syncChannel = MethodChannel('guia_telefonica/sync');

  // Referencia al notifier — se asigna desde SyncServiceListener al init
  static SyncNotifier? _notifier;

  // Flag de cancelación — se activa desde el botón cancelar
  static bool _cancelRequested = false;

  // Indica si hay una sync en curso
  static bool _running = false;

  static void _bindNotifier(SyncNotifier notifier) {
    _notifier = notifier;
  }

  // ─── API pública ──────────────────────────────────────────
  static Future<void> iniciarSync() async {
    if (_running) return;
    _cancelRequested = false;
    _running = true;

    // Arrancar ForegroundService nativo (mantiene proceso vivo)
    try {
      await _syncChannel.invokeMethod('startSync');
    } catch (e) {
      debugPrint('ForegroundService no disponible: $e');
      // Continuar igual — la sync funciona sin él, solo no sobrevive con pantalla apagada
    }

    // Ejecutar sync en Dart (mismo proceso — acceso directo a Riverpod)
    await _ejecutarSync();
  }

  static void cancelarSync() {
    _cancelRequested = true;
    // Detener ForegroundService nativo
    _syncChannel.invokeMethod('cancelSync').catchError((_) {});
  }

  // ─── Lógica de descarga ───────────────────────────────────
  static Future<void> _ejecutarSync() async {
    final notifier = _notifier;
    if (notifier == null) return;

    final supabase = SupabaseService();
    final localDb  = LocalDatabaseService();

    void actualizar(String estado, int desc, int total, {String? error}) {
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
      actualizar('preparando', 0, 0);

      final total = await supabase.contarContactosAprobados();
      actualizar('descargando', 0, total);

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

        actualizar('descargando', descargados, total);
      }

      if (_cancelRequested) {
        actualizar('cancelado', descargados, total);
      } else {
        actualizar('guardando', descargados, total);
        try {
          final ids = await supabase.getContactosConReportes();
          await localDb.actualizarReportesEficiente(ids);
          await localDb.guardarUltimaSincronizacion(DateTime.now());
        } catch (_) {}
        actualizar('completado', descargados, total);
      }
    } catch (e) {
      actualizar('error', 0, 0, error: e.toString());
    } finally {
      _running = false;
      _cancelRequested = false;
      _syncChannel.invokeMethod('cancelSync').catchError((_) {});
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Widget raíz: registra el notifier en el servicio y escucha
// el estado para recargar contactos al completar.
// ─────────────────────────────────────────────────────────────
class SyncServiceListener extends ConsumerStatefulWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  ConsumerState<SyncServiceListener> createState() =>
      _SyncServiceListenerState();
}

class _SyncServiceListenerState extends ConsumerState<SyncServiceListener> {
  @override
  void initState() {
    super.initState();
    // Registrar el notifier para que el servicio pueda actualizar el estado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BackgroundSyncService._bindNotifier(ref.read(syncProvider.notifier));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
