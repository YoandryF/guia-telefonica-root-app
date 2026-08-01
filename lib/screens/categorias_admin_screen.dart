import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class CategoriasAdminScreen extends StatefulWidget {
  const CategoriasAdminScreen({super.key});

  @override
  State<CategoriasAdminScreen> createState() => _CategoriasAdminScreenState();
}

class _CategoriasAdminScreenState extends State<CategoriasAdminScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _categorias = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final cats = await _supabase.getCategorias();
    setState(() {
      _categorias = cats;
      _cargando = false;
    });
  }

  Future<void> _crear() async {
    final nombreCtrl = TextEditingController();
    final iconoCtrl = TextEditingController();
    final colorCtrl = TextEditingController(text: '#3b82f6');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej: Médicos / Salud')),
            const SizedBox(height: 8),
            TextField(controller: iconoCtrl, decoration: const InputDecoration(labelText: 'Emoji/Ícono', hintText: 'Ej: 🏥')),
            const SizedBox(height: 8),
            TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Color (hex)', hintText: '#3b82f6')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );

    if (result != true || nombreCtrl.text.isEmpty) return;

    await _supabase.crearCategoria(
      nombre: nombreCtrl.text.trim(),
      icono: iconoCtrl.text.trim().isNotEmpty ? iconoCtrl.text.trim() : '📋',
      color: colorCtrl.text.trim(),
    );

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Categoría creada')));
    _cargar();
  }

  Future<void> _editar(Map<String, dynamic> cat) async {
    final nombreCtrl = TextEditingController(text: cat['nombre']);
    final iconoCtrl = TextEditingController(text: cat['icono'] ?? '');
    final colorCtrl = TextEditingController(text: cat['color'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar categoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 8),
            TextField(controller: iconoCtrl, decoration: const InputDecoration(labelText: 'Emoji/Ícono')),
            const SizedBox(height: 8),
            TextField(controller: colorCtrl, decoration: const InputDecoration(labelText: 'Color (hex)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (result != true) return;

    await _supabase.editarCategoria(
      id: cat['id'],
      nombre: nombreCtrl.text.trim(),
      icono: iconoCtrl.text.trim(),
      color: colorCtrl.text.trim(),
    );

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✏️ Categoría actualizada')));
    _cargar();
  }

  Future<void> _desactivar(Map<String, dynamic> cat) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desactivar categoría?'),
        content: Text('La categoría "${cat['nombre']}" no se eliminará pero dejará de aparecer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await _supabase.desactivarCategoria(cat['id']);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Categoría desactivada')));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📂 Categorías'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _crear, tooltip: 'Nueva categoría'),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _categorias.isEmpty
              ? const Center(child: Text('No hay categorías'))
              : ListView.builder(
                  itemCount: _categorias.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categorias[i];
                    return ListTile(
                      leading: Text(cat['icono'] ?? '📋', style: const TextStyle(fontSize: 24)),
                      title: Text(cat['nombre'] ?? ''),
                      subtitle: Text(cat['color'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editar(cat)),
                          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _desactivar(cat)),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crear,
        child: const Icon(Icons.add),
      ),
    );
  }
}
