import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/local_database_service.dart';

class EscanearAgendaScreen extends StatefulWidget {
  const EscanearAgendaScreen({super.key});
  @override
  State<EscanearAgendaScreen> createState() => _EscanearAgendaScreenState();
}

class _EscanearAgendaScreenState extends State<EscanearAgendaScreen> {
  static const _channel = MethodChannel('guia_telefonica/contacts');
  final _localDb = LocalDatabaseService();

  bool _escaneando = false;
  List<Map<String, String>> _riesgosos = [];
  int _totalEscaneados = 0;
  bool _escaneado = false;

  Future<void> _escanear() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Se necesita permiso de contactos'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() { _escaneando = true; _riesgosos = []; _escaneado = false; });

    try {
      // Leer teléfonos de la agenda
      final result = await _channel.invokeMethod('getPhoneContacts');
      final agendaContactos = List<Map<dynamic, dynamic>>.from(result);

      // Obtener teléfonos reportados de nuestra BD local
      final reportados = await _localDb.getTelefonosReportados();

      // Normalizar para comparar
      final reportadosNorm = reportados.map(_normalizar).toSet();

      // Comparar
      final encontrados = <Map<String, String>>[];
      for (final contacto in agendaContactos) {
        final tel = _normalizar(contacto['phone']?.toString() ?? '');
        if (tel.isNotEmpty && reportadosNorm.contains(tel)) {
          encontrados.add({
            'nombre': contacto['name']?.toString() ?? 'Desconocido',
            'telefono': contacto['phone']?.toString() ?? '',
          });
        }
      }

      setState(() {
        _riesgosos = encontrados;
        _totalEscaneados = agendaContactos.length;
        _escaneando = false;
        _escaneado = true;
      });
    } catch (e) {
      setState(() => _escaneando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _normalizar(String tel) {
    return tel.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔍 Escanear agenda')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.security, size: 48, color: Color(0xFF0284C7)),
                    SizedBox(height: 12),
                    Text('Compara los contactos de tu agenda con nuestra base de datos de reportes.',
                        textAlign: TextAlign.center),
                    SizedBox(height: 8),
                    Text('Tu agenda no se envía a ningún servidor. La comparación es 100% local.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            FilledButton.icon(
              onPressed: _escaneando ? null : _escanear,
              icon: _escaneando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_escaneando ? 'Escaneando...' : 'ESCANEAR MI AGENDA'),
            ),

            if (_escaneado) ...[
              const SizedBox(height: 16),

              if (_riesgosos.isEmpty)
                Card(
                  color: Colors.green.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 40),
                        const SizedBox(height: 8),
                        const Text('✅ Tu agenda está limpia', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('$_totalEscaneados contactos escaneados — ninguno de riesgo',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  color: Colors.red.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('⚠️ ${_riesgosos.length} contacto(s) de riesgo encontrado(s)',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _riesgosos.length,
                    itemBuilder: (ctx, i) {
                      final c = _riesgosos[i];
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.red,
                            child: Icon(Icons.warning, color: Colors.white, size: 20),
                          ),
                          title: Text(c['nombre'] ?? ''),
                          subtitle: Text('📱 ${c['telefono']}'),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('$_totalEscaneados contactos escaneados',
                      style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
