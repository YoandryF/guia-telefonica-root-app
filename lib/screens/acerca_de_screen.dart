import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AcercaDeScreen extends StatefulWidget {
  const AcercaDeScreen({super.key});
  @override
  State<AcercaDeScreen> createState() => _AcercaDeScreenState();
}

class _AcercaDeScreenState extends State<AcercaDeScreen> {
  String _version = '';
  List<Map<String, dynamic>> _releases = [];
  bool _cargando = true;
  String? _errorMsg;

  static const _cacheKey    = 'acerca_releases_cache';
  static const _cacheTimeKey = 'acerca_releases_ts';
  static const _cacheTtl    = Duration(hours: 6);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() { _cargando = true; _errorMsg = null; });

    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = info.version);

    // 1. Intentar desde caché local primero
    if (!forzar) {
      final cached = await _leerCache();
      if (cached != null) {
        if (mounted) setState(() { _releases = cached; _cargando = false; });
        return;
      }
    }

    // 2. Fetch desde GitHub
    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/YoandryF/guia-telefonica-root-app/releases?per_page=30'),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'GuiaTelefonicaApp/1.0',
        },
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as List;
        final releases = data.map((r) => {
          'tag':   r['tag_name']    ?? '',
          'fecha': r['published_at'] ?? '',
          'body':  r['body']        ?? '',
          'name':  r['name']        ?? '',
        }).toList().cast<Map<String, dynamic>>();

        await _guardarCache(releases);
        if (mounted) setState(() { _releases = releases; _cargando = false; });
      } else if (resp.statusCode == 403 || resp.statusCode == 429) {
        // Rate limit de GitHub — usar caché aunque esté vencida
        final cached = await _leerCache(ignorarTtl: true);
        if (mounted) setState(() {
          _releases  = cached ?? [];
          _cargando  = false;
          _errorMsg  = cached != null
              ? 'Datos desde caché (límite GitHub alcanzado)'
              : 'Límite de consultas de GitHub alcanzado. Intenta más tarde.';
        });
      } else {
        throw Exception('HTTP ${resp.statusCode}');
      }
    } catch (e) {
      // Red caída — intentar caché vencida
      final cached = await _leerCache(ignorarTtl: true);
      if (mounted) setState(() {
        _releases = cached ?? [];
        _cargando = false;
        _errorMsg = cached != null
            ? 'Sin conexión — mostrando último historial guardado'
            : 'Sin conexión y sin historial guardado';
      });
    }
  }

  Future<List<Map<String, dynamic>>?> _leerCache({bool ignorarTtl = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    final ts  = prefs.getInt(_cacheTimeKey) ?? 0;
    if (raw == null) return null;
    final edad = DateTime.now().millisecondsSinceEpoch - ts;
    if (!ignorarTtl && edad > _cacheTtl.inMilliseconds) return null;
    try {
      final list = json.decode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardarCache(List<Map<String, dynamic>> releases) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, json.encode(releases));
    await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acerca de'),
        actions: [
          if (!_cargando)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar historial',
              onPressed: () => _cargar(forzar: true),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.1),
              ),
              child: Column(
                children: [
                  SizedBox(width: 80, height: 80, child: CustomPaint(painter: _LogoPainter())),
                  const SizedBox(height: 16),
                  Text('Guía Telefónica', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('v$_version', style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('ROOT Ecosystem', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _infoRow(Icons.person, 'Creado por', 'Yoandry Freire'),
                      const Divider(),
                      _infoRow(Icons.telegram, 'Bot', '@GuiaTelefonicaRootBot'),
                      const Divider(),
                      _infoRowTap(Icons.code, 'GitHub', 'YoandryF', () => _abrirUrl('https://github.com/YoandryF')),
                      const Divider(),
                      _infoRow(Icons.category, 'Ecosistema', 'ROOT'),
                    ],
                  ),
                ),
              ),
            ),

            // Historial de cambios
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('📋 Historial de cambios', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_errorMsg!, style: const TextStyle(fontSize: 11, color: Colors.orange))),
                  ],
                ),
              ),

            if (_cargando)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
            else if (_releases.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('No se pudo cargar el historial', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _cargar(forzar: true),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
            else
              ..._releases.take(20).map((r) => _ReleaseCard(release: r)),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _infoRowTap(IconData icon, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.grey)),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF0284C7))),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 14, color: Color(0xFF0284C7)),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ReleaseCard extends StatelessWidget {
  final Map<String, dynamic> release;
  const _ReleaseCard({required this.release});

  @override
  Widget build(BuildContext context) {
    final tag  = release['tag']  as String? ?? '';
    final name = release['name'] as String? ?? '';
    final body = release['body'] as String? ?? '';
    final fecha = _formatFecha(release['fecha'] as String? ?? '');
    final titulo = name.isNotEmpty && name != tag ? name : tag;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(tag, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7))),
                  ),
                  const SizedBox(width: 8),
                  if (titulo != tag)
                    Expanded(child: Text(titulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                  const Spacer(),
                  Text(fecha, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(body, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatFecha(String fecha) {
    final dt = DateTime.tryParse(fecha);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()..color = const Color(0xFF0284C7).withOpacity(0.4)..strokeWidth = 2.5;
    canvas.drawLine(Offset(w * 0.5, h * 0.25), Offset(w * 0.25, h * 0.55), line);
    canvas.drawLine(Offset(w * 0.5, h * 0.25), Offset(w * 0.75, h * 0.55), line);
    canvas.drawLine(Offset(w * 0.25, h * 0.55), Offset(w * 0.12, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.25, h * 0.55), Offset(w * 0.38, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.75, h * 0.55), Offset(w * 0.62, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.75, h * 0.55), Offset(w * 0.88, h * 0.82), line);
    canvas.drawCircle(Offset(w * 0.5, h * 0.2), w * 0.1, Paint()..color = const Color(0xFF0284C7));
    canvas.drawCircle(Offset(w * 0.25, h * 0.55), w * 0.07, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawCircle(Offset(w * 0.75, h * 0.55), w * 0.07, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawCircle(Offset(w * 0.12, h * 0.82), w * 0.05, Paint()..color = const Color(0xFFBAE6FD));
    canvas.drawCircle(Offset(w * 0.38, h * 0.82), w * 0.05, Paint()..color = const Color(0xFFBAE6FD));
    canvas.drawCircle(Offset(w * 0.62, h * 0.82), w * 0.05, Paint()..color = const Color(0xFFBAE6FD));
    canvas.drawCircle(Offset(w * 0.88, h * 0.82), w * 0.05, Paint()..color = const Color(0xFFBAE6FD));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
