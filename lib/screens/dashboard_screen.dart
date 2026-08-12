import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _stats = {};
  bool _cargando = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final client = Supabase.instance.client;
    try {
      final totalContactos = await client.from('contactos').select().isFilter('deleted_at', null).count(CountOption.exact);
      final aprobados = await client.from('contactos').select().eq('estado', 'aprobado').isFilter('deleted_at', null).count(CountOption.exact);
      final pendientes = await client.from('contactos').select().eq('estado', 'pendiente').isFilter('deleted_at', null).count(CountOption.exact);
      final totalReportes = await client.from('reportes').select().count(CountOption.exact);
      final reportesAprobados = await client.from('reportes').select().eq('estado', 'revisado').count(CountOption.exact);
      final reportesDesestimados = await client.from('reportes').select().eq('estado', 'resuelto').count(CountOption.exact);
      final usuarios = await client.from('usuarios_telegram').select().count(CountOption.exact);
      final avales = await client.from('avales').select().count(CountOption.exact);
      final reclamos = await client.from('reclamos').select().eq('estado', 'pendiente').count(CountOption.exact);

      final pctAprobados = totalReportes.count > 0 ? (reportesAprobados.count * 100 / totalReportes.count).round() : 0;

      setState(() {
        _stats = {
          'contactos': totalContactos.count,
          'aprobados': aprobados.count,
          'pendientes': pendientes.count,
          'reportes_total': totalReportes.count,
          'reportes_aprobados': reportesAprobados.count,
          'reportes_desestimados': reportesDesestimados.count,
          'pct_aprobados': pctAprobados,
          'usuarios_telegram': usuarios.count,
          'avales': avales.count,
          'reclamos_pendientes': reclamos.count,
        };
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.bar_chart, color: Colors.indigo, size: 20), SizedBox(width: 8), Text('Dashboard')])),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SeccionTitulo('Contactos'),
                  Row(children: [
                    _MetricCard('Total', '${_stats['contactos']}', Icons.contacts, Colors.blue),
                    _MetricCard('Aprobados', '${_stats['aprobados']}', Icons.check_circle, Colors.green),
                    _MetricCard('Pendientes', '${_stats['pendientes']}', Icons.pending, Colors.orange),
                  ]),
                  const SizedBox(height: 16),
                  _SeccionTitulo('Reportes'),
                  Row(children: [
                    _MetricCard('Total', '${_stats['reportes_total']}', Icons.warning, Colors.red),
                    _MetricCard('Aprobados', '${_stats['reportes_aprobados']}', Icons.gavel, Colors.deepOrange),
                    _MetricCard('% Aprob.', '${_stats['pct_aprobados']}%', Icons.pie_chart, Colors.purple),
                  ]),
                  const SizedBox(height: 16),
                  _SeccionTitulo('Comunidad'),
                  Row(children: [
                    _MetricCard('Usuarios', '${_stats['usuarios_telegram']}', Icons.people, Colors.teal),
                    _MetricCard('Avales', '${_stats['avales']}', Icons.thumb_up, Colors.green),
                    _MetricCard('Reclamos', '${_stats['reclamos_pendientes']}', Icons.gavel, Colors.blue),
                  ]),
                ],
              ),
            ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String titulo;
  const _SeccionTitulo(this.titulo);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String valor;
  final IconData icon;
  final Color color;
  const _MetricCard(this.label, this.valor, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10)),
        ]),
      ),
    ),
  );
}
