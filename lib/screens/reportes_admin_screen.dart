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
  List<Map<String, dynamic>> _resueltos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final pendientes = await _supabase.getReportesPendientes();
      final resueltos = await _supabase.getReportesResueltos();
      setState(() {
        _pendientes = pendientes;
        _resueltos = resueltos;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _desestimar(String reporteId) async {
    await _supabase.desestimarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Reporte desestimado')));
    _cargar();
  }

  Future<void> _eliminarReporte(String reporteId) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar reporte?'),
        content: const Text('El reporte se eliminará permanentemente. Útil si fue aprobado por error.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await _supabase.eliminarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Reporte eliminado')));
    _cargar();
  }

  Future<void> _reactivarReporte(String reporteId) async {
    await _supabase.reactivarReporte(reporteId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('♻️ Reporte reactivado')));
    _cargar();
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
            Tab(text: 'Resueltos (${_resueltos.length})'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildLista(_pendientes, esPendiente: true),
                _buildLista(_resueltos, esPendiente: false),
              ],
            ),
    );
  }

  Widget _buildLista(List<Map<String, dynamic>> reportes, {required bool esPendiente}) {
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
                      if (esPendiente) ...[
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
                      if (!esPendiente) ...[
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
