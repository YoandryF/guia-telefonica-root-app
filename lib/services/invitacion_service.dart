import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestiona códigos de invitación y referidos.
class InvitacionService {
  static final _client = Supabase.instance.client;

  /// Genera o devuelve el código de invitación del usuario actual.
  /// Requiere que el usuario esté verificado en Telegram.
  static Future<String?> obtenerMiCodigo(String telegramUserId) async {
    try {
      final r = await _client.rpc(
        'generar_codigo_invitacion',
        params: {'p_telegram_user_id': telegramUserId},
      );
      return r as String?;
    } catch (e) {
      return null;
    }
  }

  /// Registra que el usuario actual fue referido por [codigo].
  /// Llamar justo después de completar la verificación Telegram.
  static Future<Map<String, dynamic>> registrarReferido({
    required String codigo,
    required String referidoId,
  }) async {
    try {
      final r = await _client.rpc(
        'registrar_referido',
        params: {
          'p_codigo': codigo,
          'p_referido_id': referidoId,
        },
      );
      return Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// Devuelve el resumen de referidos del usuario.
  static Future<Map<String, dynamic>> getMisReferidos(String telegramUserId) async {
    try {
      final r = await _client.rpc(
        'get_mis_referidos',
        params: {'p_telegram_user_id': telegramUserId},
      );
      return Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return {'codigo': '', 'total': 0, 'referidos': []};
    }
  }

  /// Verifica si hay un código de invitación pendiente en SharedPreferences
  /// (guardado por DeepLinkRouter al abrir guia://invitacion/CODIGO).
  static Future<String?> consumirCodigoPendiente() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getString('pending_codigo_invitacion');
    if (codigo != null) await prefs.remove('pending_codigo_invitacion');
    return codigo;
  }
}
