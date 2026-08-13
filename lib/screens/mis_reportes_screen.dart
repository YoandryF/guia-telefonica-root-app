import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/telegram_verification_service.dart';

class MisReportesScreen extends StatefulWidget {
  const MisReportesScreen({super.key});
  @override
  State<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends State<MisReportesScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _reportes = [];
  bool _cargando = true;
  String? _telegramId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final identity = await TelegramVerificationService().getIdentidadVerificada();
    if (identity == null) {
      setState(() => _cargando = false);
      return;
    }
    _telegramId = identity.userId;
    final reportes = await _supabase.getMisReportes(identity.userId);
    setState(() { _reportes = reportes; _cargando = false; });
  }

  Future<void> _cancelar(String reporteId) async {
    if (_telegramId == null) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar reporte?'),
        content: const Text('El reporte se eliminará. Solo se puede cancelar si está pendiente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancelar reporte'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final ok = await _supabase.cancelarMiReporte(reporteId, _telegramId!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '✅ Reporte cancelado' : '⚠️ Solo puedes cancelar reportes pendientes')),
      );
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.flag, size: 20), SizedBox(width: 8), Text('Mis Reportes')]),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _telegramId == null
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Verifica tu cuenta de Telegram para ver tus reportes.', textAlign: TextAlign.center),
                ))
              : _reportes.isEmpty
                  ? const Center(child: Text('No has hecho ningún reporte'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        itemCount: _reportes.length,
                        itemBuilder: (ctx, i) {
                          final r = _reportes[i];
                          final estado = r['estado'] ?? '';
                          final Color estadoColor;
                          final String estadoLabel;
                          switch (estado) {
                            case 'revisado':
                              estadoColor = Colors.orange;
                              estadoLabel = '🔴 Aprobado — señalado como riesgo';
                              break;
                            case 'resuelto':
                              estadoColor = Colors.green;
                              estadoLabel = '✅ Desestimado';
                              break;
                            default:
                              estadoColor = Colors.grey;
                              estadoLabel = '🟡 Pendiente de revisión';
                          }
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(r['contacto_nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: estadoColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(estado.toUpperCase(),
                                            style: TextStyle(fontSize: 10, color: estadoColor, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('📱 ${r['contacto_telefono'] ?? ''}', style: const TextStyle(fontSize: 12)),
                                  Text('📋 ${_motivoLabel(r['motivo'] ?? '')}', style: const TextStyle(fontSize: 12)),
                                  if (r['descripcion'] != null && r['descripcion'].toString().isNotEmpty)
                                    Text('💬 ${r['descripcion']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Text(estadoLabel, style: TextStyle(fontSize: 11, color: estadoColor)),
                                  if (r['nota_admin'] != null && r['nota_admin'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('📝 Nota del admin: ${r['nota_admin']}',
                                          style: const TextStyle(fontSize: 11)),
                                    ),
                                  ],
                                  if (estado == 'pendiente') ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () => _cancelar(r['id']),
                                        icon: const Icon(Icons.cancel, size: 14, color: Colors.red),
                                        label: const Text('Cancelar reporte', style: TextStyle(fontSize: 12, color: Colors.red)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  String _motivoLabel(String motivo) {
    switch (motivo) {
      case 'numero_incorrecto': return 'Número incorrecto';
      case 'no_existe': return 'Ya no existe';
      case 'spam': return 'Spam / Acoso';
      case 'duplicado': return 'Duplicado';
      default: return 'Otro';
    }
  }
}
