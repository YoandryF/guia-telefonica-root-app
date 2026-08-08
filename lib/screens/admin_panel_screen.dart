import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/supabase_service.dart';
import 'admins_screen.dart';
import 'auditoria_screen.dart';
import 'categorias_admin_screen.dart';
import 'configuracion_screen.dart';
import 'contactos_list_screen.dart';
import 'dashboard_screen.dart';
import 'dashboard_screen.dart';
import 'exportar_screen.dart';
import 'importar_screen.dart';
import 'reportes_admin_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _supabase = SupabaseService();
  List<Contacto> _pendientes = [];
  Map<String, int> _stats = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final pendientes = await _supabase.getContactosPendientes();
      final stats = await _supabase.getEstadisticas();
      setState(() {
        _pendientes = pendientes;
        _stats = stats;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _aprobar(Contacto contacto) async {
    await _supabase.aprobarContacto(contacto.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${contacto.nombreCompleto} aprobado')),
      );
    }
    _cargarDatos();
  }

  Future<void> _rechazar(Contacto contacto) async {
    final controller = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Motivo de rechazo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Ej: Número incorrecto'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Rechazar')),
        ],
      ),
    );

    if (motivo == null || motivo.isEmpty) return;

    await _supabase.rechazarContacto(contacto.id, motivo);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${contacto.nombreCompleto} rechazado')),
      );
    }
    _cargarDatos();
  }

  void _irALista(String estado, String titulo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactosListScreen(estado: estado, titulo: titulo),
      ),
    ).then((_) => _cargarDatos());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔐 Panel Admin'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.logoutAdmin();
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats clickeables
                  Row(
                    children: [
                      _StatCard(
                        emoji: '✅',
                        count: _stats['aprobados'] ?? 0,
                        label: 'Aprobados',
                        color: Colors.green,
                        onTap: () => _irALista('aprobado', '✅ Aprobados'),
                      ),
                      _StatCard(
                        emoji: '⏳',
                        count: _stats['pendientes'] ?? 0,
                        label: 'Pendientes',
                        color: Colors.orange,
                        onTap: () => _irALista('pendiente', '⏳ Pendientes'),
                      ),
                      _StatCard(
                        emoji: '❌',
                        count: _stats['rechazados'] ?? 0,
                        label: 'Rechazados',
                        color: Colors.red,
                        onTap: () => _irALista('rechazado', '❌ Rechazados'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Exportar / Importar / Categorías
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportarScreen())),
                          icon: const Icon(Icons.file_download),
                          label: const Text('Exportar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarScreen())),
                          icon: const Icon(Icons.file_upload),
                          label: const Text('Importar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriasAdminScreen())),
                    icon: const Icon(Icons.category),
                    label: const Text('Gestionar categorías'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportesAdminScreen())),
                    icon: const Icon(Icons.warning_amber, color: Colors.orange),
                    label: const Text('Gestionar reportes'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminsScreen())),
                    icon: const Icon(Icons.people, color: Colors.blue),
                    label: const Text('Gestionar admins'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditoriaScreen())),
                    icon: const Icon(Icons.history, color: Colors.purple),
                    label: const Text('Auditoría'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfiguracionScreen())),
                    icon: const Icon(Icons.settings, color: Colors.grey),
                    label: const Text('Configuración (Owner)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
                    icon: const Icon(Icons.bar_chart, color: Colors.indigo),
                    label: const Text('Dashboard métricas'),
                  ),

                  const SizedBox(height: 24),

                  // Pendientes rápidos
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pendientes (${_pendientes.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_pendientes.length > 5)
                        TextButton(
                          onPressed: () => _irALista('pendiente', '⏳ Pendientes'),
                          child: const Text('Ver todos →'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_pendientes.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('✅ No hay pendientes')),
                      ),
                    )
                  else
                    ..._pendientes.take(5).map((c) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nombreCompleto,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text('📱 ${c.telefono}'),
                                if (c.direccion != null) Text('📍 ${c.direccion}'),
                                if (c.ci != null) Text('🆔 ${c.ci}'),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _rechazar(c),
                                      icon: const Icon(Icons.close, color: Colors.red, size: 18),
                                      label: const Text('Rechazar', style: TextStyle(fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed: () => _aprobar(c),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Aprobar', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StatCard({
    required this.emoji,
    required this.count,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
