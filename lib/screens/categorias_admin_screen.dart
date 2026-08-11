import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

// Paleta de colores predefinida
const _colores = <String, Color>{
  '#ef4444': Color(0xFFef4444), // Rojo
  '#f97316': Color(0xFFf97316), // Naranja
  '#f59e0b': Color(0xFFf59e0b), // Ámbar
  '#eab308': Color(0xFFeab308), // Amarillo
  '#84cc16': Color(0xFF84cc16), // Lima
  '#22c55e': Color(0xFF22c55e), // Verde
  '#10b981': Color(0xFF10b981), // Esmeralda
  '#14b8a6': Color(0xFF14b8a6), // Teal
  '#06b6d4': Color(0xFF06b6d4), // Cyan
  '#0ea5e9': Color(0xFF0ea5e9), // Sky
  '#3b82f6': Color(0xFF3b82f6), // Azul
  '#6366f1': Color(0xFF6366f1), // Indigo
  '#8b5cf6': Color(0xFF8b5cf6), // Violeta
  '#a855f7': Color(0xFFa855f7), // Púrpura
  '#d946ef': Color(0xFFd946ef), // Fucsia
  '#ec4899': Color(0xFFec4899), // Rosa
  '#78716c': Color(0xFF78716c), // Gris
  '#1e293b': Color(0xFF1e293b), // Oscuro
};

// Paleta de íconos/emojis por categoría
const _iconos = [
  '📋', '📁', '📂', '📌', '⭐',
  '🏥', '🏠', '🏢', '🏪', '🏫',
  '🚗', '🚕', '🚌', '✈️', '🚲',
  '🍽️', '🍕', '☕', '🛒', '🎂',
  '💼', '👔', '🔧', '🔨', '⚡',
  '📱', '💻', '🖥️', '📡', '🔌',
  '🎓', '📚', '✏️', '🎨', '🎵',
  '⚽', '🏋️', '🎮', '🎬', '🎤',
  '💊', '🩺', '🦷', '👁️', '💉',
  '🏦', '💰', '💳', '📊', '📈',
  '👮', '🚒', '🚑', '⚖️', '🔒',
  '🐶', '🐱', '🌿', '🌸', '🌍',
  '❤️', '🤝', '👥', '👨‍👩‍👧', '🎁',
  '🔔', '📞', '📧', '💬', '📝',
];

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

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF3b82f6);
    try {
      return Color(int.parse(hex.replaceFirst('#', ''), radix: 16) + 0xFF000000);
    } catch (_) {
      return const Color(0xFF3b82f6);
    }
  }

  Future<void> _crear() async {
    final result = await _mostrarEditor(nombre: '', icono: '📋', color: '#3b82f6');
    if (result == null) return;

    await _supabase.crearCategoria(
      nombre: result['nombre']!,
      icono: result['icono']!,
      color: result['color']!,
    );

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Categoría creada')));
    _cargar();
  }

  Future<void> _editar(Map<String, dynamic> cat) async {
    final result = await _mostrarEditor(
      nombre: cat['nombre'] ?? '',
      icono: cat['icono'] ?? '📋',
      color: cat['color'] ?? '#3b82f6',
    );
    if (result == null) return;

    await _supabase.editarCategoria(
      id: cat['id'],
      nombre: result['nombre']!,
      icono: result['icono']!,
      color: result['color']!,
    );

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✏️ Categoría actualizada')));
    _cargar();
  }

  Future<Map<String, String>?> _mostrarEditor({
    required String nombre,
    required String icono,
    required String color,
  }) async {
    final nombreCtrl = TextEditingController(text: nombre);
    String selectedIcono = icono;
    String selectedColor = color;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _parseColor(selectedColor).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(selectedIcono, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(nombre.isEmpty ? 'Nueva categoría' : 'Editar categoría')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      hintText: 'Ej: Médicos / Salud',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selector de ícono
                  const Text('Ícono', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: _iconos.length,
                      itemBuilder: (_, i) {
                        final ico = _iconos[i];
                        final selected = ico == selectedIcono;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedIcono = ico),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected ? _parseColor(selectedColor).withOpacity(0.2) : null,
                              borderRadius: BorderRadius.circular(6),
                              border: selected ? Border.all(color: _parseColor(selectedColor), width: 2) : null,
                            ),
                            child: Center(child: Text(ico, style: const TextStyle(fontSize: 18))),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selector de color
                  const Text('Color', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colores.entries.map((e) {
                      final isSelected = e.key == selectedColor;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = e.key),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 3)
                                : Border.all(color: Colors.grey.shade300),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 16)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, {
                  'nombre': nombreCtrl.text.trim(),
                  'icono': selectedIcono,
                  'color': selectedColor,
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
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
                    final color = _parseColor(cat['color']);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(cat['icono'] ?? '📋', style: const TextStyle(fontSize: 22))),
                        ),
                        title: Text(cat['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Row(
                          children: [
                            Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(cat['color'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editar(cat)),
                            IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _desactivar(cat)),
                          ],
                        ),
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
