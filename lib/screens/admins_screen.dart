import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});
  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _admins = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final response = await _supabase.getAdmins();
      setState(() { _admins = response; _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  Future<void> _crearAdmin() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            const SizedBox(height: 8),
            TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );

    if (result != true || emailCtrl.text.isEmpty) return;

    try {
      await _supabase.crearAdmin(email: emailCtrl.text.trim(), password: passCtrl.text, nombre: nombreCtrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Admin creado')));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _desactivar(Map<String, dynamic> admin) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desactivar admin?'),
        content: Text('${admin['nombre_admin'] ?? admin['email']} ya no podrá moderar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Desactivar')),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _supabase.desactivarAdmin(admin['email']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Admin desactivado')));
      _cargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.manage_accounts, color: Colors.blue, size: 20), SizedBox(width: 8), Text('Administradores')])),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _admins.isEmpty
              ? const Center(child: Text('No hay admins'))
              : ListView.builder(
                  itemCount: _admins.length,
                  itemBuilder: (ctx, i) {
                    final a = _admins[i];
                    final activo = a['activo'] == true;
                    final rol = a['rol'] ?? 'admin';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: rol == 'owner' ? Colors.amber : (activo ? Colors.green : Colors.grey),
                        child: Icon(rol == 'owner' ? Icons.star : Icons.admin_panel_settings, color: Colors.white, size: 20),
                      ),
                      title: Text(a['nombre_admin'] ?? a['email'] ?? ''),
                      subtitle: Text('${a['email']} • ${rol.toUpperCase()}${activo ? '' : ' (inactivo)'}'),
                      trailing: rol != 'owner' && activo
                          ? IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => _desactivar(a))
                          : null,
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(onPressed: _crearAdmin, child: const Icon(Icons.person_add)),
    );
  }
}
