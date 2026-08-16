import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../screens/contacto_detalle_screen.dart';

/// Pantalla admin: todos los avales pendientes de revisión.
class AvalesPendientesScreen extends StatefulWidget {
  const AvalesPendientesScreen({super.key});

  @override
  State<AvalesPendientesScreen> createState() => _AvalesPendientesScreenState();
}

class _AvalesPendientesScreenState extends State<AvalesPendientesScreen> {
  List<Map<String, dynamic>> _avales = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Supabase.instance.client
          .from('avales')
          .select('*, contactos(nombre, apellido, telefono)')
          .eq('estado', 'pendiente')
          .order('fecha');
      setState(() {
        _avales = List<Map<String, dynamic>>.from(r);
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _resolver(String avalId, String nuevoEstado) async {
    try {
      await Supabase.instance.client.from('avales').update({
        'estado': nuevoEstado,
        'revisado_por': Supabase.instance.client.auth.currentUser?.email ?? 'admin',
        'fecha_revision': DateTime.now().toIso8601String(),
      }).eq('id', avalId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nuevoEstado == 'aprobado' ? '✅ Aval aprobado' : '❌ Aval rechazado'),
        ));
        _cargar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('👍 Avales pendientes${_cargando ? '' : ' (${_avales.length})'}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _avales.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.thumb_up, size: 56, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text('No hay avales pendientes',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _avales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (ctx, i) => _avalCard(ctx, _avales[i]),
                  ),
                ),
    );
  }

  Widget _avalCard(BuildContext ctx, Map<String, dynamic> a) {
    final contacto = a['contactos'] as Map? ?? {};
    final nombre   = '${contacto['nombre'] ?? ''} ${contacto['apellido'] ?? ''}'.trim();
    final telefono = contacto['telefono']?.toString() ?? '';
    final avaladoPor = a['avalado_por']?.toString() ?? '—';
    final fecha    = (a['fecha']?.toString() ?? '').split('T').first;
    final avalId   = a['id']?.toString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contacto avalado
            Row(
              children: [
                const Icon(Icons.person, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nombre.isNotEmpty ? nombre : telefono,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                // Botón ver contacto
                if (telefono.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 16),
                    tooltip: 'Ver contacto',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _abrirContacto(ctx, telefono),
                  ),
              ],
            ),
            if (telefono.isNotEmpty)
              Text('📱 $telefono', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            // Quien avaló
            Row(
              children: [
                const Icon(Icons.telegram, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text('Avalado por: $avaladoPor',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                const Spacer(),
                Text(fecha, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 10),
            // Botones acción
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _resolver(avalId, 'rechazado'),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text('Rechazar', style: TextStyle(color: Colors.red, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _resolver(avalId, 'aprobado'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprobar', style: TextStyle(fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirContacto(BuildContext ctx, String telefono) async {
    final data = await Supabase.instance.client
        .from('contactos')
        .select('*, categorias(nombre, icono)')
        .eq('telefono', telefono)
        .maybeSingle();
    if (data == null || !ctx.mounted) return;
    Navigator.push(ctx, MaterialPageRoute(
      builder: (_) => ContactoDetalleScreen(contacto: Contacto.fromJson(data)),
    ));
  }
}
