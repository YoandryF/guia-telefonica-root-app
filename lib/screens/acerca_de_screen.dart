import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
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

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _version = info.version);

    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/YoandryF/guia-telefonica-root-app/releases'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as List;
        setState(() {
          _releases = data.map((r) => {
            'tag': r['tag_name'] ?? '',
            'fecha': r['published_at'] ?? '',
            'body': r['body'] ?? '',
          }).toList().cast<Map<String, dynamic>>();
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
      }
    } catch (_) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
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

            if (_cargando)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
            else if (_releases.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Text('No se pudo cargar el historial'))
            else
              ..._releases.take(15).map((r) => _ReleaseCard(release: r)),

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
    final tag = release['tag'] ?? '';
    final body = release['body'] ?? '';
    final fecha = _formatFecha(release['fecha'] ?? '');

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
