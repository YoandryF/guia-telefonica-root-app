import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/telegram_evidence_service.dart';

class ReportesAdminScreen extends StatefulWidget {
  const ReportesAdminScreen({super.key});
  @override
  State<ReportesAdminScreen> createState() => _ReportesAdminScreenState();
}

class _ReportesAdminScreenState extends State<ReportesAdminScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _agrupados = [];
  bool _cargando = true;
  String _filtro = 'todos';
  String _orden = 'mas_reportes';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await _supabase.getReportesAgrupados(filtro: _filtro, orden: _orden);
      setState(() { _agrupados = data; _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.report_problem, color: Colors.orange, size: 20), SizedBox(width: 8), Text('Reportes')])),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtro,
                    decoration: const InputDecoration(labelText: 'Filtro', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'sin_marcar', child: Text('Sin marcar')),
                      DropdownMenuItem(value: 'marcados', child: Text('Marcados')),
                    ],
                    onChanged: (v) { setState(() => _filtro = v!); _cargar(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _orden,
                    decoration: const InputDecoration(labelText: 'Orden', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'mas_reportes', child: Text('Más reportes')),
                      DropdownMenuItem(value: 'menos_reportes', child: Text('Menos reportes')),
                      DropdownMenuItem(value: 'mas_reciente', child: Text('Más reciente')),
                    ],
                    onChanged: (v) { setState(() => _orden = v!); _cargar(); },
                  ),
                ),
              ],
            ),
          ),

          // Lista agrupada
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _agrupados.isEmpty
                    ? const Center(child: Text('No hay contactos reportados'))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          itemCount: _agrupados.length,
                          itemBuilder: (ctx, i) {
                            final item = _agrupados[i];
                            final aprobados = (item['aprobados'] as num?)?.toInt() ?? 0;
                            final pendientes = (item['pendientes'] as num?)?.toInt() ?? 0;
                            final total = (item['total_reportes'] as num?)?.toInt() ?? 0;
                            final marcado = aprobados > 0;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: marcado ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                  child: Icon(marcado ? Icons.dangerous : Icons.warning_amber,
                                      color: marcado ? Colors.red : Colors.orange, size: 20),
                                ),
                                title: Text('${item['nombre']} ${item['apellido']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('📱 ${item['telefono']}'),
                                    Text('⚠️ $total reportes ($aprobados aprobados, $pendientes pendientes)',
                                        style: const TextStyle(fontSize: 12)),
                                    Text(marcado ? '🔴 Marcado' : '🟡 Sin marcar',
                                        style: TextStyle(fontSize: 11, color: marcado ? Colors.red : Colors.orange)),
                                  ],
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                isThreeLine: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => _ReportesContactoScreen(
                                    contactoId: item['contact_id'],
                                    nombre: '${item['nombre']} ${item['apellido']}',
                                  )),
                                ).then((_) => _cargar()),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// Pantalla de reportes individuales de un contacto
class _ReportesContactoScreen extends StatefulWidget {
  final String contactoId;
  final String nombre;
  const _ReportesContactoScreen({required this.contactoId, required this.nombre});
  @override
  State<_ReportesContactoScreen> createState() => _ReportesContactoScreenState();
}

class _ReportesContactoScreenState extends State<_ReportesContactoScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _reportes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final response = await _supabase.getReportesPorEstado('pendiente');
    // Filtrar por contacto + también traer aprobados
    final todos = await _supabase.getReportesDeContacto(widget.contactoId);
    setState(() { _reportes = todos; _cargando = false; });
  }

  Future<bool> _confirmar(String titulo, String mensaje, {bool destructiva = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructiva ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _aprobar(String id) async {
    if (!await _confirmar('⚠️ ¿Aprobar reporte?', 'El contacto se marcará como riesgoso.')) return;
    await _supabase.aprobarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Aprobado')));
    _cargar();
  }

  Future<void> _desestimar(String id) async {
    if (!await _confirmar('✅ ¿Desestimar?', 'No contará para la advertencia.')) return;
    await _supabase.desestimarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Desestimado')));
    _cargar();
  }

  Future<void> _eliminar(String id) async {
    if (!await _confirmar('🗑️ ¿Eliminar?', 'Se borra permanentemente.', destructiva: true)) return;
    await _supabase.eliminarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Eliminado')));
    _cargar();
  }

  Future<void> _reactivar(String id) async {
    if (!await _confirmar('♻️ ¿Reactivar?', 'Vuelve a pendiente.')) return;
    await _supabase.reactivarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('♻️ Reactivado')));
    _cargar();
  }

  Future<void> _abrirEvidencia(dynamic msgId, String? fileId) async {
    if (fileId != null && fileId.toString().isNotEmpty) {
      // Mostrar imagen inline
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('📎 Evidencia'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              FutureBuilder<String?>(
                future: TelegramEvidenceService().getEvidenciaUrl(fileId.toString()),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 300,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.data == null) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: Text('❌ No se pudo cargar la imagen')),
                    );
                  }
                  return InteractiveViewer(
                    child: Image.network(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return SizedBox(
                          height: 300,
                          child: Center(
                            child: CircularProgressIndicator(
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (ctx, _, __) => const SizedBox(
                        height: 200,
                        child: Center(child: Text('❌ Error cargando imagen')),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else {
      // Fallback: abrir en Telegram
      final chatId = TelegramEvidenceConfig.evidenceGroupId;
      if (chatId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Grupo de evidencias no configurado')),
        );
        return;
      }
      final uri = Uri.parse('https://t.me/c/${chatId.replaceFirst('-100', '')}/$msgId');
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('📎 Evidencia: mensaje #$msgId en el grupo')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _reportes.isEmpty
              ? const Center(child: Text('No hay reportes'))
              : ListView.builder(
                  itemCount: _reportes.length,
                  itemBuilder: (ctx, i) {
                    final r = _reportes[i];
                    final estado = r['estado'] ?? '';
                    final estadoIcon = estado == 'revisado' ? '🔴' : estado == 'resuelto' ? '✅' : '🟡';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('$estadoIcon ${_motivoLabel(r['motivo'] ?? '')}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (r['evidencia_msg_id'] != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('📎 Evidencia', style: TextStyle(fontSize: 10, color: Colors.blue)),
                                  ),
                                ],
                                const Spacer(),
                                Text(_formatFecha(r['fecha_reporte']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            if (r['descripcion'] != null && r['descripcion'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('💬 ${r['descripcion']}', style: const TextStyle(fontSize: 12)),
                              ),
                            if (r['evidencia_msg_id'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: () => _abrirEvidencia(r['evidencia_msg_id'], r['evidencia_file_id']),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.image, size: 14, color: Colors.blue),
                                      SizedBox(width: 4),
                                      Text('Ver evidencia en Telegram', style: TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (estado == 'pendiente') ...[
                                  _actionBtn(Icons.warning_amber, 'Aprobar', Colors.orange, () => _aprobar(r['id'])),
                                  _actionBtn(Icons.check, 'Desestimar', Colors.green, () => _desestimar(r['id'])),
                                ],
                                if (estado == 'revisado' || estado == 'resuelto')
                                  _actionBtn(Icons.undo, 'Reactivar', Colors.orange, () => _reactivar(r['id'])),
                                _actionBtn(Icons.delete, 'Eliminar', Colors.red, () => _eliminar(r['id'])),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  String _motivoLabel(String motivo) {
    switch (motivo) {
      case 'numero_incorrecto': return '📞 Número incorrecto';
      case 'no_existe': return '❌ No existe';
      case 'spam': return '📢 Spam';
      case 'duplicado': return '🔄 Duplicado';
      default: return '📋 Otro';
    }
  }

  String _formatFecha(String? fecha) {
    if (fecha == null) return '';
    final dt = DateTime.tryParse(fecha);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
