import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../screens/contacto_detalle_screen.dart';
import '../screens/verificacion_telegram_screen.dart';

/// Maneja los deep links con scheme guia://
///
/// Rutas soportadas:
///   guia://contacto/{telefono}   → abre detalle del contacto
///   guia://verificar/{codigo}    → abre verificación Telegram
///   guia://invitacion/{codigo}   → guarda referido (se usa en #11)
class DeepLinkRouter {
  /// Clave en SharedPreferences para el código de invitación pendiente
  static const kCodigoInvitacion = 'pending_codigo_invitacion';

  /// Parsea y ejecuta la navegación correspondiente al URI recibido.
  static Future<void> handle(Uri uri, BuildContext context) async {
    if (uri.scheme != 'guia') return;

    final host = uri.host;
    final param = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';

    switch (host) {
      case 'contacto':
        await _abrirContacto(param, context);
      case 'verificar':
        if (context.mounted) mostrarVerificacionTelegram(context);
      case 'invitacion':
        await _guardarInvitacion(param, context);
    }
  }

  // ── guia://contacto/{telefono} ────────────────────────────
  static Future<void> _abrirContacto(String telefono, BuildContext context) async {
    if (telefono.isEmpty) return;

    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('contactos')
          .select('*, categorias(nombre, icono)')
          .eq('telefono', telefono)
          .eq('estado', 'aprobado')
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (!context.mounted) return;

      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se encontró el número $telefono')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContactoDetalleScreen(contacto: Contacto.fromJson(data)),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al buscar el contacto')),
        );
      }
    }
  }

  // ── guia://invitacion/{codigo} ────────────────────────────
  static Future<void> _guardarInvitacion(String codigo, BuildContext context) async {
    if (codigo.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCodigoInvitacion, codigo);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎉 Invitación registrada')),
      );
    }
  }

  /// Obtiene el código de invitación pendiente y lo limpia.
  /// Llamar al registrar un nuevo usuario para asociar el referido.
  static Future<String?> consumirCodigoInvitacion() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getString(kCodigoInvitacion);
    if (codigo != null) await prefs.remove(kCodigoInvitacion);
    return codigo;
  }
}
