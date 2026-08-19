import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import 'contacto_detalle_screen.dart';

class EscanearAgendaScreen extends StatefulWidget {
  const EscanearAgendaScreen({super.key});
  @override
  State<EscanearAgendaScreen> createState() => _EscanearAgendaScreenState();
}

class _EscanearAgendaScreenState extends State<EscanearAgendaScreen> {
  static const _channel = MethodChannel('guia_telefonica/contacts');
  final _localDb = LocalDatabaseService();

  bool _escaneando = false;
  List<Map<String, dynamic>> _riesgosos = [];
  int _totalEscaneados = 0;
  int _procesados = 0;
  bool _escaneado = false;
  String _statusMsg = '';

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

    setState(() { _escaneando = true; _riesgosos = []; _escaneado = false; _procesados = 0; _statusMsg = 'Leyendo agenda...'; });

    try {
      // Leer teléfonos de la agenda
      final result = await _channel.invokeMethod('getPhoneContacts');
      final agendaContactos = List<Map<dynamic, dynamic>>.from(result);

      setState(() {
        _totalEscaneados = agendaContactos.length;
        _statusMsg = 'Cargando base de datos local...';
      });

      // Obtener teléfonos reportados de nuestra BD local
      final reportados = await _localDb.getTelefonosReportados();
      // NO cargar todos los contactos — buscar solo los que coincidan con la agenda
      final reportadosNorm = reportados.map(_normalizar).toSet();

      setState(() => _statusMsg = 'Comparando ${agendaContactos.length} contactos...');

      // Comparar con progreso
      final encontrados = <Map<String, dynamic>>[];
      for (var i = 0; i < agendaContactos.length; i++) {
        final contacto = agendaContactos[i];
        final tel = _normalizar(contacto['phone']?.toString() ?? '');
        if (tel.isNotEmpty && reportadosNorm.contains(tel)) {
          // Buscar el contacto local solo cuando hay coincidencia (pocos casos)
          final local = await _localDb.buscarPorTelefono(tel);
          encontrados.add({
            'nombre': contacto['name']?.toString() ?? 'Desconocido',
            'telefono': contacto['phone']?.toString() ?? '',
            'contacto_local': local,
          });
        }

        // Actualizar progreso cada 50
        if (i % 50 == 0 || i == agendaContactos.length - 1) {
          setState(() => _procesados = i + 1);
        }
      }

      setState(() {
        _riesgosos = encontrados;
        _escaneando = false;
        _escaneado = true;
      });
    } catch (e) {
      setState(() { _escaneando = false; _statusMsg = ''; });
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

            if (_escaneando) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _totalEscaneados > 0 ? _procesados / _totalEscaneados : null,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _totalEscaneados > 0
                    ? '$_procesados / $_totalEscaneados — $_statusMsg'
                    : _statusMsg,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],

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
                      final contactoLocal = c['contacto_local'] as Contacto?;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.warning, color: Colors.white, size: 20)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text('📱 ${c['telefono']}', style: const TextStyle(fontSize: 12)),
                                    ],
                                  )),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (contactoLocal != null)
                                    Expanded(child: OutlinedButton.icon(
                                      onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: contactoLocal))),
                                      icon: const Icon(Icons.info_outline, size: 16),
                                      label: const Text('Ver detalles', style: TextStyle(fontSize: 11)),
                                    )),
                                  const SizedBox(width: 8),
                                  Expanded(child: OutlinedButton.icon(
                                    onPressed: () => _channel.invokeMethod('openContact', {'phone': c['telefono']}),
                                    icon: const Icon(Icons.contacts, size: 16),
                                    label: const Text('Abrir en agenda', style: TextStyle(fontSize: 11)),
                                  )),
                                ],
                              ),
                            ],
                          ),
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
