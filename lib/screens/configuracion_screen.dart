import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});
  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  List<Map<String, dynamic>> _config = [];
  bool _cargando = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await Supabase.instance.client.from('configuracion').select().order('clave');
      setState(() { _config = List<Map<String, dynamic>>.from(r); _cargando = false; });
    } catch (e) { setState(() => _cargando = false); }
  }

  Future<void> _editar(Map<String, dynamic> item) async {
    final ctrl = TextEditingController(text: item['valor']);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(item['clave']),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (item['descripcion'] != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(item['descripcion'], style: const TextStyle(fontSize: 12, color: Colors.grey))),
        TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Valor', border: OutlineInputBorder()), autofocus: true),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar'))],
    ));
    if (result == null) return;
    await Supabase.instance.client.from('configuracion').update({'valor': result}).eq('clave', item['clave']);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Actualizado')));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ Configuración')),
      body: _cargando ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _config.length,
        itemBuilder: (ctx, i) {
          final item = _config[i];
          return ListTile(
            title: Text(item['clave'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Text(item['descripcion'] ?? '', style: const TextStyle(fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(item['valor'], style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            ),
            onTap: () => _editar(item),
          );
        },
      ),
    );
  }
}
