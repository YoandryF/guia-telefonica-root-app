import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class ReportesAdminScreen extends StatefulWidget {
  const ReportesAdminScreen({super.key});

  @override
  State<ReportesAdminScreen> createState() => _ReportesAdminScreenState();
}

class _ReportesAdminScreenState extends State<ReportesAdminScreen> with SingleTickerProviderStateMixin {
  final _supabase = SupabaseService();
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _aprobados = [];
  List<Map<String, dynamic>> _desestimados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final pendientes = await _supabase.getReportesPendientes();
      final aprobados = await _supabase.getReportesPorEstado('revisado');
      final desestimados = await _supabase.getReportesResueltos();
      setState(() {
        _pendientes = pendientes;
        _aprobados = aprobados;
        _desestimados = desestimados;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _desestimar(String reporteId) async {
    final confirmar = await _confirmarAccion(
      '✅ ¿Desestimar reporte?',
      'El reporte se marcará como inválido y no contará para la advertencia del contacto.',
    );
    if (!confirmar) return;
    await _supabase.desestimarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Reporte desestimado')));
    _cargar();
  }

  Future<void> _aprobarReporte(String reporteId) async {
    final confirmar = await _confirmarAccion(
      '⚠️ ¿Aprobar reporte?',
      'El reporte se marcará como válido. El contacto mantendrá la advertencia visible para todos los usuarios.',
    );
    if (!confirmar) return;
    await _supabase.aprobarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Reporte aprobado — contacto mantiene advertencia')));
    _cargar();
  }

  Future<void> _eliminarReporte(String reporteId) async {
    final confirmar = await _confirmarAccion(
      '🗑️ ¿Eliminar reporte?',
      'El reporte se eliminará permanentemente. Esta acción no se puede deshacer.',
      destructiva: true,
    );
    if (!confirmar) return;
    await _supabase.eliminarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Reporte eliminado')));
    _cargar();
  }

  Future<void> _reactivarReporte(String reporteId) async {
    final confirmar = await _confirmarAccion(
      '♻️ ¿Reactivar reporte?',
      'El reporte volverá a estado pendiente y contará para la advertencia del contacto.',
    );
    if (!confirmar) return;
    await _supabase.reactivarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('♻️ Reporte reactivado')));
    _cargar();
  }

  Future<bool> _confirmarAccion(String titulo, String mensaje, {bool destructiva = false}) async {
    final result = await showDialog<bool>(
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
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚠️ Reportes'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: 'Pendientes (${_pendientes.length})'),
            Tab(text: 'Aprobados (${_aprobados.length})'),
            Tab(text: 'Desestimados (${_desestimados.length})'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildLista(_pendientes, tipo: 'pendiente'),
                _buildLista(_aprobados, tipo: 'aprobado'),
                _buildLista(_desestimados, tipo: 'desestimado'),
              ],
            ),
    );
  }

  Widget _buildLista(List<Map<String, dynamic>> reportes, {required String tipo}) {
    if (reportes.isEmpty) {
      return const Center(child: Text('No hay reportes'));
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        itemCount: reportes.length,
        itemBuilder: (ctx, i) {
          final r = reportes[i];
          final contacto = r['contactos'] as Map<String, dynamic>?;
          final nombre = contacto != null ? '${contacto['nombre']} ${contacto['apellido']}' : 'Desconocido';
          final telefono = contacto?['telefono'] ?? '';

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
                        child: Text(nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Chip(
                        label: Text(_motivoLabel(r['motivo'] ?? ''), style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _motivoColor(r['motivo'] ?? ''),
                      ),
                    ],
                  ),
                  Text('📱 $telefono', style: const TextStyle(fontSize: 13)),
                  if (r['descripcion'] != null && r['descripcion'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('💬 ${r['descripcion']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  Text('📅 ${_formatFecha(r['fecha_reporte'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (tipo == 'pendiente') ...[
                        TextButton.icon(
                          onPressed: () => _aprobarReporte(r['id']),
                          icon: const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                          label: const Text('Aprobar', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ),
                        TextButton.icon(
                          onPressed: () => _desestimar(r['id']),
                          icon: const Icon(Icons.check, size: 16, color: Colors.green),
                          label: const Text('Desestimar', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () => _eliminarReporte(r['id']),
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          label: const Text('Eliminar', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ],
                      if (tipo == 'aprobado') ...[
                        TextButton.icon(
                          onPressed: () => _reactivarReporte(r['id']),
                          icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
                          label: const Text('Reactivar', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () => _eliminarReporte(r['id']),
                          icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red),
                          label: const Text('Eliminar', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ],
                      if (tipo == 'desestimado') ...[
                        TextButton.icon(
                          onPressed: () => _reactivarReporte(r['id']),
                          icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
                          label: const Text('Reactivar', style: TextStyle(fontSize: 12)),
                        ),
                        TextButton.icon(
                          onPressed: () => _eliminarReporte(r['id']),
                          icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red),
                          label: const Text('Eliminar', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ],
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

  String _motivoLabel(String motivo) {
    switch (motivo) {
      case 'numero_incorrecto': return '📞 Incorrecto';
      case 'no_existe': return '❌ No existe';
      case 'spam': return '📢 Spam';
      case 'duplicado': return '🔄 Duplicado';
      default: return '📋 Otro';
    }
  }

  Color _motivoColor(String motivo) {
    switch (motivo) {
      case 'spam': return Colors.red.withOpacity(0.1);
      case 'numero_incorrecto': return Colors.orange.withOpacity(0.1);
      default: return Colors.grey.withOpacity(0.1);
    }
  }

  String _formatFecha(String? fecha) {
    if (fecha == null) return '';
    final dt = DateTime.tryParse(fecha);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }
}
