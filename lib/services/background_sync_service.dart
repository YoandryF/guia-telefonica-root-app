import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../providers/sync_provider.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';

/// Servicio de sincronización en background.
/// API: flutter_background_service v0.2.8
/// Corre en ForegroundService de Android — sobrevive con pantalla apagada.
class BackgroundSyncService {
  // Claves para comunicación UI ↔ Service
  static const _keyProgress = 'syncProgress';
  static const _keyCancel   = 'cancelSync';

  // ─── Inicializar (llamar en main() antes de runApp) ───────
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:             _onStart,
        autoStart:           false,
        isForegroundMode:    true,
        foregroundServiceNotificationTitle:   'Guía Telefónica',
        foregroundServiceNotificationContent: 'Sincronización lista',
      ),
      iosConfiguration: IosConfiguration(
        autoStart:    false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  // ─── Arrancar sync ────────────────────────────────────────
  static Future<void> iniciarSync() async {
    final service = FlutterBackgroundService();
    final running = await service.isServiceRunning();
    if (!running) {
      service.start();
    }
  }

  // ─── Cancelar sync ────────────────────────────────────────
  static void cancelarSync() {
    FlutterBackgroundService().sendData({_keyCancel: true});
  }

  // ─── Stream de progreso (escuchar desde la UI) ────────────
  static Stream<Map<String, dynamic>?> escucharProgreso() {
    return FlutterBackgroundService().onDataReceived
        .where((data) => data != null && data.containsKey(_keyProgress))
        .map((data) => data![_keyProgress] as Map<String, dynamic>?);
  }

  // ─── Lógica que corre en el proceso background ────────────
  @pragma('vm:entry-point')
  static void _onStart() {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    _runSync();
  }

  static Future<void> _runSync() async {
    final service   = FlutterBackgroundService();
    bool  cancelado = false;

    // Escuchar señal de cancelación desde la UI
    final cancelSub = service.onDataReceived.listen((data) {
      if (data != null && data[_keyCancel] == true) {
        cancelado = true;
      }
    });

    void enviar(String estado, int desc, int total, {String? error}) {
      service.sendData({
        _keyProgress: {
          'estado':      estado,
          'descargados': desc,
          'total':       total,
          if (error != null) 'error': error,
        },
      });
      // Actualizar notificación Android
      service.setNotificationInfo(
        title: 'Guía Telefónica — Sincronizando',
        content: total > 0 ? '$desc de $total contactos' : estado,
      );
    }

    try {
      enviar('preparando', 0, 0);

      final supabase = SupabaseService();
      final localDb  = LocalDatabaseService();

      final total = await supabase.contarContactosAprobados();
      enviar('descargando', 0, total);

      int  descargados = 0;
      int  offset      = 0;
      bool hayMas      = true;
      const pageSize   = 1000;

      while (hayMas && !cancelado) {
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

        enviar('descargando', descargados, total);
      }

      if (cancelado) {
        enviar('cancelado', descargados, total);
      } else {
        enviar('guardando', descargados, total);
        try {
          final idsReportados = await supabase.getContactosConReportes();
          await localDb.actualizarReportesEficiente(idsReportados);
          await localDb.guardarUltimaSincronizacion(DateTime.now());
        } catch (_) {}
        enviar('completado', descargados, total);
      }
    } catch (e) {
      service.sendData({
        _keyProgress: {
          'estado': 'error',
          'error':  e.toString(),
          'descargados': 0,
          'total': 0,
        },
      });
      service.setNotificationInfo(
        title: 'Guía Telefónica',
        content: 'Error en sincronización',
      );
    } finally {
      await cancelSub.cancel();
      await Future.delayed(const Duration(seconds: 2));
      service.stopBackgroundService();
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}

// ─────────────────────────────────────────────────────────────
// Widget que conecta el stream del servicio con Riverpod.
// Envuelve toda la app — se inicializa una sola vez.
// ─────────────────────────────────────────────────────────────
class SyncServiceListener extends ConsumerStatefulWidget {
  final Widget child;
  const SyncServiceListener({super.key, required this.child});

  @override
  ConsumerState<SyncServiceListener> createState() => _SyncServiceListenerState();
}

class _SyncServiceListenerState extends ConsumerState<SyncServiceListener> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = BackgroundSyncService.escucharProgreso().listen((data) {
      if (data == null) return;
      final notifier = ref.read(syncProvider.notifier);
      final estado   = data['estado'] as String? ?? '';
      final desc     = (data['descargados'] as num?)?.toInt() ?? 0;
      final total    = (data['total']       as num?)?.toInt() ?? 0;

      switch (estado) {
        case 'preparando':  notifier.setPreparando();
        case 'descargando': notifier.setDescargando(desc, total);
        case 'guardando':   notifier.setGuardando();
        case 'completado':  notifier.setCompletado(desc);
        case 'cancelado':   notifier.setCancelado();
        case 'error':
          notifier.setError(data['error']?.toString() ?? 'desconocido');
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
