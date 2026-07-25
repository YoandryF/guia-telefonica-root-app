import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Servicio de auto-actualización via GitHub Releases
class UpdateService {
  static const String _owner = 'YoandryF';
  static const String _repo = 'guia-telefonica-root-app';
  static const String _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Verificar si hay una nueva versión disponible
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final latestVersion = _parseVersion(data['tag_name'] as String);
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = _parseVersion(packageInfo.version);

      if (_isNewer(latestVersion, currentVersion)) {
        // Buscar el APK en los assets
        String? downloadUrl;
        final assets = data['assets'] as List;
        for (final asset in assets) {
          final name = asset['name'] as String;
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String;
            break;
          }
        }

        return UpdateInfo(
          version: data['tag_name'] as String,
          description: data['body'] as String? ?? 'Nueva versión disponible',
          downloadUrl: downloadUrl ?? data['html_url'] as String,
          publishedAt: DateTime.tryParse(data['published_at'] as String? ?? ''),
        );
      }

      return null; // No hay actualización
    } catch (e) {
      debugPrint('Error verificando actualización: $e');
      return null;
    }
  }

  /// Mostrar diálogo de actualización
  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🆕 Nueva versión disponible'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión: ${info.version}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(info.description, maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Después'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );

    if (result == true) {
      final uri = Uri.parse(info.downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  List<int> _parseVersion(String version) {
    final clean = version.replaceAll(RegExp(r'[^0-9.]'), '');
    return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  bool _isNewer(List<int> latest, List<int> current) {
    for (var i = 0; i < latest.length && i < current.length; i++) {
      if (latest[i] > current[i]) return true;
      if (latest[i] < current[i]) return false;
    }
    return latest.length > current.length;
  }
}

class UpdateInfo {
  final String version;
  final String description;
  final String downloadUrl;
  final DateTime? publishedAt;

  UpdateInfo({
    required this.version,
    required this.description,
    required this.downloadUrl,
    this.publishedAt,
  });
}
