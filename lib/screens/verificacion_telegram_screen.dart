import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/invitacion_service.dart';
import '../services/telegram_verification_service.dart';

/// Muestra el modal de verificación por Telegram.
/// Retorna el TelegramIdentity si la verificación fue exitosa, null si canceló.
Future<TelegramIdentity?> mostrarVerificacionTelegram(BuildContext context) async {
  return showModalBottomSheet<TelegramIdentity>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _VerificacionTelegramSheet(),
  );
}

/// Verifica si el usuario está verificado. Si no, muestra el modal.
/// Retorna el TelegramIdentity o null si no se verificó.
Future<TelegramIdentity?> requiereVerificacion(BuildContext context) async {
  final service = TelegramVerificationService();

  // 1. Verificar local
  final local = await service.getIdentidadVerificada();
  if (local != null) return local;

  // 2. Verificar remoto (por si se verificó en otro momento)
  final dispositivoId = await _getDispositivoId();
  final remoto = await service.verificarEnRemoto(dispositivoId);
  if (remoto != null) return remoto;

  // 3. No verificado → mostrar modal
  if (!context.mounted) return null;
  return mostrarVerificacionTelegram(context);
}

Future<String> _getDispositivoId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('dispositivo_id');
  if (id == null || id.isEmpty) {
    id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
    await prefs.setString('dispositivo_id', id);
  }
  return id;
}

class _VerificacionTelegramSheet extends StatefulWidget {
  const _VerificacionTelegramSheet();

  @override
  State<_VerificacionTelegramSheet> createState() => _VerificacionTelegramSheetState();
}

class _VerificacionTelegramSheetState extends State<_VerificacionTelegramSheet> {
  final _service = TelegramVerificationService();
  String? _codigo;
  _Estado _estado = _Estado.generando;
  String? _errorMsg;
  StreamSubscription? _pollSub;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _pollSub?.cancel();
    super.dispose();
  }

  Future<void> _iniciar() async {
    setState(() => _estado = _Estado.generando);

    final dispositivoId = await _getDispositivoId();
    final codigo = await _service.generarCodigo(dispositivoId);

    if (codigo == null) {
      setState(() {
        _estado = _Estado.error;
        _errorMsg = 'No se pudo generar el código. Verifica tu conexión.';
      });
      return;
    }

    setState(() {
      _codigo = codigo;
      _estado = _Estado.listo;
    });
  }

  Future<void> _abrirTelegram() async {
    if (_codigo == null) return;

    final ok = await _service.abrirTelegramVerificacion(_codigo!);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ No se pudo abrir Telegram. ¿Está instalado?')),
        );
      }
      return;
    }

    // Iniciar polling
    setState(() => _estado = _Estado.esperando);

    _pollSub = _service.pollVerificacion(_codigo!).listen((status) {
      if (!mounted) return;
      switch (status.state) {
        case VerificationState.verificado:
          setState(() => _estado = _Estado.verificado);
          // Hook referidos: si hay un código de invitación pendiente, registrar
          _registrarReferidoSiAplica(status.identity!.userId);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) Navigator.pop(context, status.identity);
          });
          break;
        case VerificationState.expirado:
          setState(() {
            _estado = _Estado.error;
            _errorMsg = 'El código expiró. Genera uno nuevo.';
          });
          break;
        case VerificationState.error:
          setState(() {
            _estado = _Estado.error;
            _errorMsg = status.errorMsg ?? 'Error desconocido';
          });
          break;
        case VerificationState.pendiente:
          // Seguir esperando
          break;
      }
    });
  }

  /// Si hay un código de invitación pendiente (guardado por DeepLinkRouter),
  /// lo registra en BD vinculando al nuevo usuario con su referidor.
  Future<void> _registrarReferidoSiAplica(String referidoId) async {
    final codigo = await InvitacionService.consumirCodigoPendiente();
    if (codigo == null || codigo.isEmpty) return;
    await InvitacionService.registrarReferido(
      codigo: codigo,
      referidoId: referidoId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Ícono
          Icon(
            _estado == _Estado.verificado ? Icons.check_circle : Icons.telegram,
            size: 56,
            color: _estado == _Estado.verificado ? Colors.green : Colors.blue,
          ),
          const SizedBox(height: 16),

          // Título
          Text(
            _getTitulo(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Descripción
          Text(
            _getDescripcion(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Código
          if (_codigo != null && _estado != _Estado.verificado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Text(
                _codigo!,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Botón principal
          if (_estado == _Estado.listo)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _abrirTelegram,
                icon: const Icon(Icons.telegram),
                label: const Text('Abrir Telegram'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue,
                ),
              ),
            ),

          if (_estado == _Estado.esperando) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Esperando verificación...\nToca "Iniciar" en el bot de Telegram.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],

          if (_estado == _Estado.verificado)
            const Text('✅ ¡Verificado!', style: TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),

          if (_estado == _Estado.generando)
            const CircularProgressIndicator(),

          if (_estado == _Estado.error) ...[
            Text(_errorMsg ?? 'Error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _iniciar, child: const Text('Reintentar')),
          ],

          const SizedBox(height: 16),

          // Botón cancelar
          if (_estado != _Estado.verificado)
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
        ],
      ),
    );
  }

  String _getTitulo() {
    switch (_estado) {
      case _Estado.generando: return 'Preparando...';
      case _Estado.listo: return 'Verificación por Telegram';
      case _Estado.esperando: return 'Verificando...';
      case _Estado.verificado: return '¡Listo!';
      case _Estado.error: return 'Error';
    }
  }

  String _getDescripcion() {
    switch (_estado) {
      case _Estado.generando: return 'Generando código de verificación...';
      case _Estado.listo: return 'Para reportar, avalar o reclamar necesitas verificar tu identidad.\nToca el botón y envía "Iniciar" al bot.';
      case _Estado.esperando: return 'Abre el bot en Telegram y toca "Iniciar"';
      case _Estado.verificado: return 'Tu cuenta de Telegram fue vinculada exitosamente.';
      case _Estado.error: return '';
    }
  }
}

enum _Estado { generando, listo, esperando, verificado, error }
