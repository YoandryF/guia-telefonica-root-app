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
/// ForegroundService nativo Kotlin mantiene el proceso vivo en Android.
/// La lógica de descarga corre en Dart (mismo proceso, sin isolate separado).
/// El progreso se comunica via StreamController interno → Riverpod.
class BackgroundSyncService {
  static const _syncChannel = MethodChannel('guia_telefonica/sync');

  // StreamController interno — Dart produce, SyncServiceListener consume
  static final _progressController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get _progreso =>
      _progressController.stream;

  // ─── No-op: la init la hace MainActivity ────────────────────────────
  static Future<void> initializeService() async {}

  // ─── Arrancar sync ────────────────────────────────────────────────────
  static Future<void> iniciarSync() async {
    try {
      final running = await _syncChannel.invokeMethod<bool>('isRunning') ?? false;
      if (!running) {
        // 1. Arrancar ForegroundService nativo (mantiene el proceso vivo)
        await _syncChannel.invokeMethod('startSync');
        // 2. Ejecutar lógica de descarga en Dart
        _ejecutarSync();
      }
    } catch (e) {
      debugPrint('iniciarSync error: $e');
    }
  }

  // ─── Cancelar sync ────────────────────────────────────────────────────
  static Future<void> cancelarSync() async {
    try {
      await _syncChannel.invokeMethod('cancelSync');
    } catch (e) {
      debugPrint('cancelarSync error: $e');
    }
  }

  // ─── Stream de progreso para SyncServiceListener ─────────────────────
  static Stream<Map<String, dynamic>> escucharProgreso() => _progreso;

  // ─── Lógica de descarga (Dart, proceso mantenido por ForegroundService) ─
  static Future<void> _ejecutarSync() async {
    final supabase = SupabaseService();
    final localDb  = LocalDatabaseService();

    void emit(String estado, int desc, int total, {String? error}) {
      final data = <String, dynamic>{
        'estado':      estado,
        'descargados': desc,
        'total':       total,
        if (error != null) 'error': error,
      };
      _progressController.add(data);
      // Actualizar notificación Android
      final texto = total > 0 ? '$desc de $total contactos' : estado;
      _syncChannel.invokeMethod('updateNotification', {'texto': texto})
          .catchError((_) {});
    }

    bool cancelado = false;

    try {
      emit('preparando', 0, 0);

      final total = await supabase.contarContactosAprobados();
      emit('descargando', 0, total);

      int  descargados = 0;
      int  offset      = 0;
      bool hayMas      = true;
      const pageSize   = 1000;

      while (hayMas) {
        // Verificar si Android canceló el servicio
        final running =
            await _syncChannel.invokeMethod<bool>('isRunning') ?? false;
        if (!running) {
          cancelado = true;
          break;
        }

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

        emit('descargando', descargados, total);
      }

      if (!cancelado) {
        emit('guardando', descargados, total);
        try {
          final ids = await supabase.getContactosConReportes();
          await localDb.actualizarReportesEficiente(ids);
          await localDb.guardarUltimaSincronizacion(DateTime.now());
        } catch (_) {}
        emit('completado', descargados, total);
      } else {
        emit('cancelado', descargados, total);
      }
    } catch (e) {
      emit('error', 0, 0, error: e.toString());
    } finally {
      // Detener el ForegroundService nativo
      _syncChannel.invokeMethod('cancelSync').catchError((_) {});
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Widget raíz — conecta el stream de progreso con el SyncNotifier Riverpod.
// ─────────────────────────────────────────────────────────────────────────
class SyncServiceListener extends ConsumerStatefulWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  ConsumerState<SyncServiceListener> createState() =>
      _SyncServiceListenerState();
}

class _SyncServiceListenerState extends ConsumerState<SyncServiceListener> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = BackgroundSyncService.escucharProgreso().listen((data) {
      final notifier = ref.read(syncProvider.notifier);
      final estado   = data['estado'] as String? ?? '';
      final desc     = (data['descargados'] as num?)?.toInt() ?? 0;
      final total    = (data['total']       as num?)?.toInt() ?? 0;

      switch (estado) {
        case 'preparando':  notifier.setPreparando();
        case 'descargando': notifier.setDescargando(desc, total);
        case 'guardando':   notifier.setGuardando();
        case 'completado':
          notifier.setCompletado(desc);
          // Recargar la lista local al completar
          _onSyncCompletado();
        case 'cancelado':   notifier.setCancelado();
        case 'error':
          notifier.setError(data['error']?.toString() ?? 'desconocido');
      }
    });
  }

  Future<void> _onSyncCompletado() async {
    // La home_screen escucha syncProvider y puede reaccionar al estado completado
    // No necesitamos hacer nada aquí — el SyncBanner muestra "completado"
    // y el usuario puede refrescar manualmente o navegar
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
