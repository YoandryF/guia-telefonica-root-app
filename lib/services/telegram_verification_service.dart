import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Servicio de verificación vía Telegram.
/// Genera un código, abre el bot con deep link, y hace polling
/// hasta que el bot confirme la verificación.
class TelegramVerificationService {
  static const _keyTelegramUserId = 'telegram_user_id';
  static const _keyTelegramUsername = 'telegram_username';
  static const _botUsername = 'GuiaTelefonicaRootBot';

  final _client = Supabase.instance.client;

  /// Verifica si el dispositivo ya está verificado (local + remoto)
  Future<TelegramIdentity?> getIdentidadVerificada() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyTelegramUserId);
    if (userId != null && userId.isNotEmpty) {
      return TelegramIdentity(
        userId: userId,
        username: prefs.getString(_keyTelegramUsername),
      );
    }
    return null;
  }

  /// Verifica contra Supabase si el dispositivo tiene verificación activa
  Future<TelegramIdentity?> verificarEnRemoto(String dispositivoId) async {
    try {
      final result = await _client.rpc('obtener_verificacion_activa', params: {
        'p_dispositivo_id': dispositivoId,
      });
      
      if (result is Map && result['verificado'] == true) {
        final identity = TelegramIdentity(
          userId: result['telegram_user_id'].toString(),
          username: result['telegram_username'] as String?,
        );
        // Guardar localmente
        await _guardarLocal(identity);
        return identity;
      }
    } catch (e) {
      debugPrint('Error verificar remoto: $e');
    }
    return null;
  }

  /// Genera un código de verificación y retorna el código generado
  Future<String?> generarCodigo(String dispositivoId) async {
    try {
      final result = await _client.rpc('crear_verificacion', params: {
        'p_dispositivo_id': dispositivoId,
      });
      return result as String?;
    } catch (e) {
      debugPrint('Error generar código: $e');
      return null;
    }
  }

  /// Abre Telegram con el deep link para verificar
  Future<bool> abrirTelegramVerificacion(String codigo) async {
    final uri = Uri.parse('https://t.me/$_botUsername?start=verify_$codigo');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error abriendo Telegram: $e');
      return false;
    }
  }

  /// Hace polling al RPC para saber si el código fue verificado.
  /// Retorna un Stream que emite el estado cada 2 segundos.
  /// Se detiene automáticamente cuando se verifica o expira.
  Stream<VerificationStatus> pollVerificacion(String codigo) async* {
    const maxIntentos = 150; // 5 minutos (150 * 2s)
    
    for (var i = 0; i < maxIntentos; i++) {
      await Future.delayed(const Duration(seconds: 2));
      
      try {
        final result = await _client.rpc('consultar_verificacion', params: {
          'p_codigo': codigo,
        });
        
        if (result is Map) {
          final estado = result['estado'] as String?;
          
          if (estado == 'VERIFICADO') {
            final identity = TelegramIdentity(
              userId: result['telegram_user_id'].toString(),
              username: result['telegram_username'] as String?,
            );
            await _guardarLocal(identity);
            yield VerificationStatus.verificado(identity);
            return;
          } else if (estado == 'EXPIRADO') {
            yield VerificationStatus.expirado();
            return;
          } else if (estado == 'NO_ENCONTRADO') {
            yield VerificationStatus.error('Código no encontrado');
            return;
          }
          // PENDIENTE → seguir polling
          yield VerificationStatus.pendiente();
        }
      } catch (e) {
        yield VerificationStatus.error(e.toString());
        return;
      }
    }
    
    yield VerificationStatus.expirado();
  }

  /// Limpiar verificación local (para testing/logout)
  Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTelegramUserId);
    await prefs.remove(_keyTelegramUsername);
  }

  /// Obtener identidad guardada localmente (método estático conveniente)
  static Future<TelegramIdentity?> getIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyTelegramUserId);
    if (userId == null || userId.isEmpty) return null;
    return TelegramIdentity(
      userId: userId,
      username: prefs.getString(_keyTelegramUsername),
    );
  }

  Future<void> _guardarLocal(TelegramIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTelegramUserId, identity.userId);
    if (identity.username != null) {
      await prefs.setString(_keyTelegramUsername, identity.username!);
    }
  }
}

/// Identidad de Telegram del usuario verificado
class TelegramIdentity {
  final String userId;
  final String? username;

  TelegramIdentity({required this.userId, this.username});
}

/// Estado de la verificación durante el polling
class VerificationStatus {
  final VerificationState state;
  final TelegramIdentity? identity;
  final String? errorMsg;

  VerificationStatus._({required this.state, this.identity, this.errorMsg});

  factory VerificationStatus.pendiente() => VerificationStatus._(state: VerificationState.pendiente);
  factory VerificationStatus.verificado(TelegramIdentity id) => VerificationStatus._(state: VerificationState.verificado, identity: id);
  factory VerificationStatus.expirado() => VerificationStatus._(state: VerificationState.expirado);
  factory VerificationStatus.error(String msg) => VerificationStatus._(state: VerificationState.error, errorMsg: msg);
}

enum VerificationState { pendiente, verificado, expirado, error }
