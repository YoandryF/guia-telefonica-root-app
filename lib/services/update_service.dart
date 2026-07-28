import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String description;
  final String downloadUrl;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrl,
  });
}

class UpdateService {
  static const String _owner = 'YoandryF';
  static const String _repo = 'guia-telefonica-root-app';
  static const _channel = MethodChannel('guia_telefonica/installer');

  /// Verificar si hay una nueva versión disponible
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] ?? '') as String;
      final latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (latestVersion.isEmpty) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (!_isNewer(latestVersion, currentVersion)) return null;

      // Buscar APK en assets
      String downloadUrl = '';
      final assets = data['assets'] as List? ?? [];
      for (final asset in assets) {
        if ((asset['name'] ?? '').toString().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] ?? '';
          break;
        }
      }

      if (downloadUrl.isEmpty) return null;

      return UpdateInfo(
        version: latestVersion,
        description: data['body'] as String? ?? 'Nueva versión disponible',
        downloadUrl: downloadUrl,
      );
    } catch (e) {
      debugPrint('Error verificando actualización: $e');
      return null;
    }
  }

  /// Descargar APK con progreso
  static Future<String?> downloadApk(String downloadUrl, void Function(double) onProgress) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        client.close();
        return null;
      }

      final contentLength = response.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/guia-telefonica-update.apk';
      final file = File(filePath);
      final sink = file.openWrite();

      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) onProgress(received / contentLength);
      }
      await sink.close();
      client.close();
      return filePath;
    } catch (_) {
      return null;
    }
  }

  /// Verificar si puede instalar APKs
  static Future<bool> canInstallApk() async {
    try {
      final result = await _channel.invokeMethod('canInstallApk');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Solicitar permiso de instalación
  static Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod('requestInstallPermission');
    } catch (_) {}
  }

  /// Instalar APK
  static Future<bool> installApk(String filePath) async {
    try {
      final result = await _channel.invokeMethod('installApk', {'path': filePath});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Mostrar diálogo de actualización completo (descarga + instala)
  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }

  bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final a = i < latestParts.length ? latestParts[i] : 0;
      final b = i < currentParts.length ? currentParts[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    // Verificar permiso de instalación
    final canInstall = await UpdateService.canInstallApk();
    if (!canInstall) {
      if (!mounted) return;
      final grant = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.security, size: 48, color: Colors.orange),
          title: const Text('Permiso requerido'),
          content: const Text(
            'Para instalar actualizaciones, necesitas permitir la instalación desde esta app.\n\n'
            'Se abrirá la configuración de Android. Activa "Permitir desde esta fuente" y vuelve aquí.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir configuración')),
          ],
        ),
      );
      if (grant == true) {
        await UpdateService.requestInstallPermission();
      }
      return;
    }

    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    final path = await UpdateService.downloadApk(
      widget.info.downloadUrl,
      (p) => setState(() => _progress = p),
    );

    if (path == null) {
      setState(() {
        _downloading = false;
        _error = 'Error al descargar. Verifica tu conexión.';
      });
      return;
    }

    // Instalar
    final installed = await UpdateService.installApk(path);
    if (!installed && mounted) {
      setState(() {
        _downloading = false;
        _error = 'No se pudo abrir el instalador.';
      });
    } else {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 48, color: Color(0xFF0284C7)),
      title: const Text('Nueva versión disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'v${widget.info.version}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.info.description,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          if (_downloading) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _progress, minHeight: 8),
            ),
            const SizedBox(height: 6),
            Text('Descargando... ${(_progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red), textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Después')),
        if (!_downloading)
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Actualizar'),
          ),
      ],
    );
  }
}
