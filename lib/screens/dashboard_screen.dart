import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'contactos_list_screen.dart';
import 'reportes_admin_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _supabase = SupabaseService();
  Map<String, dynamic> _stats = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await _supabase.getDashboardStats();
    setState(() {
      _stats = data;
      _cargando = false;
    });
  }

  int _s(String key) => (_stats[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bar_chart, color: Colors.indigo, size: 20),
            SizedBox(width: 8),
            Text('Dashboard'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // === CONTACTOS ===
                  const _SeccionTitulo('📇 Contactos'),
                  Row(children: [
                    _MetricCard(
                      label: 'Total',
                      valor: '${_s('contactos_total')}',
                      icon: Icons.contacts,
                      color: Colors.blue,
                    ),
                    _MetricCard(
                      label: 'Aprobados',
                      valor: '${_s('contactos_aprobados')}',
                      icon: Icons.check_circle,
                      color: Colors.green,
                    ),
                    _MetricCard(
                      label: 'Pendientes',
                      valor: '${_s('contactos_pendientes')}',
                      icon: Icons.pending,
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ContactosListScreen(
                          estado: 'pendiente', titulo: '⏳ Pendientes',
                        )),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // === REPORTES ===
                  const _SeccionTitulo('📣 Reportes'),
                  Row(children: [
                    _MetricCard(
                      label: 'Total',
                      valor: '${_s('reportes_total')}',
                      icon: Icons.warning,
                      color: Colors.red,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportesAdminScreen()),
                      ),
                    ),
                    _MetricCard(
                      label: 'Aprobados',
                      valor: '${_s('reportes_aprobados')}',
                      icon: Icons.gavel,
                      color: Colors.deepOrange,
                    ),
                    _MetricCard(
                      label: 'Pendientes',
                      valor: '${_s('reportes_pendientes')}',
                      icon: Icons.hourglass_top,
                      color: Colors.orange,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportesAdminScreen()),
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '${_s('reportes_pct_aprobados')}% tasa de aprobación',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // === COMUNIDAD ===
                  const _SeccionTitulo('👥 Comunidad'),
                  Row(children: [
                    _MetricCard(
                      label: 'Usuarios TG',
                      valor: '${_s('usuarios_telegram')}',
                      icon: Icons.people,
                      color: Colors.teal,
                    ),
                    _MetricCard(
                      label: 'Avales pend.',
                      valor: '${_s('avales_pendientes')}',
                      icon: Icons.thumb_up,
                      color: Colors.green,
                    ),
                    _MetricCard(
                      label: 'Reclamos pend.',
                      valor: '${_s('reclamos_pendientes')}',
                      icon: Icons.gavel,
                      color: Colors.blue,
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // === SEGURIDAD ===
                  const _SeccionTitulo('🔒 Seguridad'),
                  Row(children: [
                    _MetricCard(
                      label: 'Con restricción',
                      valor: '${_s('usuarios_con_restriccion')}',
                      icon: Icons.block,
                      color: Colors.red,
                    ),
                    const Expanded(child: SizedBox()),
                    const Expanded(child: SizedBox()),
                  ]),
                  const SizedBox(height: 16),

                  // === ACTIVIDAD ===
                  const _SeccionTitulo('📈 Actividad'),
                  Row(children: [
                    _MetricCard(
                      label: 'Nuevos (semana)',
                      valor: '${_s('nuevos_esta_semana')}',
                      icon: Icons.fiber_new,
                      color: Colors.purple,
                    ),
                    const Expanded(child: SizedBox()),
                    const Expanded(child: SizedBox()),
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
  final VoidCallback? onTap;
  const _MetricCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: onTap != null ? 2 : 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10)),
            if (onTap != null)
              Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey[400]),
          ]),
        ),
      ),
    ),
  );
}
