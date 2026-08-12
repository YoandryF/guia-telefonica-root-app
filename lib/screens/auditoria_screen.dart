import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});
  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  List<Map<String, dynamic>> _historial = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final response = await Supabase.instance.client
          .from('historial')
          .select('*, contactos(nombre, apellido)')
          .order('fecha', ascending: false)
          .limit(50);
      setState(() { _historial = List<Map<String, dynamic>>.from(response); _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.history, color: Colors.purple, size: 20), SizedBox(width: 8), Text('Auditoría')])),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _historial.isEmpty
              ? const Center(child: Text('No hay registros'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    itemCount: _historial.length,
                    itemBuilder: (ctx, i) {
                      final h = _historial[i];
                      final contacto = h['contactos'] as Map<String, dynamic>?;
                      final nombre = contacto != null ? '${contacto['nombre']} ${contacto['apellido']}' : 'Desconocido';
                      final accion = h['accion'] ?? '';
                      final fecha = _formatFecha(h['fecha']);

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: _colorAccion(accion),
                          child: Icon(_iconAccion(accion), size: 16, color: Colors.white),
                        ),
                        title: Text('$nombre — ${accion.toUpperCase()}', style: const TextStyle(fontSize: 13)),
                        subtitle: Text('$fecha • Por: ${h['realizado_por'] ?? 'sistema'}', style: const TextStyle(fontSize: 11)),
                        dense: true,
                      );
                    },
                  ),
                ),
    );
  }

  Color _colorAccion(String accion) {
    switch (accion) {
      case 'aprobado': return Colors.green;
      case 'rechazado': return Colors.red;
      case 'eliminado': return Colors.grey;
      case 'editado': return Colors.blue;
      case 'creado': return Colors.teal;
      default: return Colors.grey;
    }
  }

  IconData _iconAccion(String accion) {
    switch (accion) {
      case 'aprobado': return Icons.check;
      case 'rechazado': return Icons.close;
      case 'eliminado': return Icons.delete;
      case 'editado': return Icons.edit;
      case 'creado': return Icons.add;
      default: return Icons.info;
    }
  }

  String _formatFecha(String? fecha) {
    if (fecha == null) return '';
    final dt = DateTime.tryParse(fecha);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
