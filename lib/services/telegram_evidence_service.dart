import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Configuración del bot de Telegram para evidencias
class TelegramEvidenceConfig {
  static const String botToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
    defaultValue: '', // Se setea en el build: --dart-define=TELEGRAM_BOT_TOKEN=xxx
  );

  static const String evidenceGroupId = String.fromEnvironment(
    'TELEGRAM_EVIDENCE_GROUP',
    defaultValue: '', // chat_id del grupo privado de evidencias
  );
}

/// Resultado de subir evidencia
class EvidenceResult {
  final bool success;
  final int? messageId;
  final String? chatId;
  final String? error;

  EvidenceResult({required this.success, this.messageId, this.chatId, this.error});
}

/// Servicio para gestionar evidencias de reportes via Telegram
class TelegramEvidenceService {
  final _picker = ImagePicker();

  /// Seleccionar imagen desde cámara o galería
  Future<File?> pickImage({required ImageSource source}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 70, // Compresión 70% calidad → ~100-200KB
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Enviar foto al grupo privado de evidencias en Telegram
  /// Retorna el message_id para guardarlo como referencia
  Future<EvidenceResult> enviarEvidencia({
    required File imagen,
    required String contactoNombre,
    required String contactoTelefono,
    required String motivo,
    required String reportadorUsername,
  }) async {
    final token = TelegramEvidenceConfig.botToken;
    final chatId = TelegramEvidenceConfig.evidenceGroupId;

    if (token.isEmpty || chatId.isEmpty) {
      return EvidenceResult(success: false, error: 'Configuración de evidencias no disponible');
    }

    // Caption con contexto del reporte
    final caption = '⚠️ *EVIDENCIA DE REPORTE*\n\n'
        '👤 Contacto: $contactoNombre\n'
        '📱 Teléfono: `$contactoTelefono`\n'
        '📋 Motivo: $motivo\n'
        '🔍 Reportado por: @$reportadorUsername\n'
        '📅 Fecha: ${DateTime.now().toIso8601String().substring(0, 16)}';

    try {
      final uri = Uri.parse('https://api.telegram.org/bot$token/sendPhoto');
      final request = http.MultipartRequest('POST', uri)
        ..fields['chat_id'] = chatId
        ..fields['caption'] = caption
        ..fields['parse_mode'] = 'Markdown'
        ..files.add(await http.MultipartFile.fromPath('photo', imagen.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body);

      if (json['ok'] == true) {
        final msgId = json['result']['message_id'] as int;
        return EvidenceResult(
          success: true,
          messageId: msgId,
          chatId: chatId,
        );
      } else {
        return EvidenceResult(success: false, error: json['description'] ?? 'Error desconocido');
      }
    } catch (e) {
      debugPrint('Error enviando evidencia: $e');
      return EvidenceResult(success: false, error: e.toString());
    }
  }

  /// Verificar si el sistema de evidencias está configurado
  bool get isConfigured =>
      TelegramEvidenceConfig.botToken.isNotEmpty &&
      TelegramEvidenceConfig.evidenceGroupId.isNotEmpty;
}
