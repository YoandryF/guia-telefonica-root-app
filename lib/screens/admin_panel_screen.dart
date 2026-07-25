import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/supabase_service.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ ${contacto.nombreCompleto} aprobado')),
    );
    _cargarDatos();
  }

  Future<void> _rechazar(Contacto contacto) async {
    final motivo = await _mostrarDialogoRechazo();
    if (motivo == null) return;

    await _supabase.rechazarContacto(contacto.id, motivo);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${contacto.nombreCompleto} rechazado')),
      );
    }
    _cargarDatos();
  }

  Future<String?> _mostrarDialogoRechazo() async {
    final controller = TextEditingController();
    return showDialog<String>(
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔐 Panel Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
          ),
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
                  // Estadísticas
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatChip('✅', _stats['aprobados'] ?? 0, 'Aprobados'),
                          _StatChip('⏳', _stats['pendientes'] ?? 0, 'Pendientes'),
                          _StatChip('❌', _stats['rechazados'] ?? 0, 'Rechazados'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Pendientes
                  Text(
                    'Pendientes de aprobación (${_pendientes.length})',
                    style: Theme.of(context).textTheme.titleMedium,
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
                    ..._pendientes.map((c) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.nombreCompleto,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                      icon: const Icon(Icons.close, color: Colors.red),
                                      label: const Text('Rechazar'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      onPressed: () => _aprobar(c),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Aprobar'),
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

class _StatChip extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;

  const _StatChip(this.emoji, this.count, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        Text('$count', style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
