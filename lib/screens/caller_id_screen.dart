import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/contacts_sync_service.dart';
import '../services/local_database_service.dart';

class CallerIdScreen extends StatefulWidget {
  const CallerIdScreen({super.key});

  @override
  State<CallerIdScreen> createState() => _CallerIdScreenState();
}

class _CallerIdScreenState extends State<CallerIdScreen> {
  final _syncService = ContactsSyncService();
  final _localDb = LocalDatabaseService();
  bool _sincronizando = false;
  Map<String, int>? _resultado;

  Future<void> _sincronizar() async {
    // Pedir permiso de contactos
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Se necesita permiso de contactos'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() {
      _sincronizando = true;
      _resultado = null;
    });

    final contactos = await _localDb.getAllContactos();

    final resultado = await _syncService.syncContactos(contactos);

    setState(() {
      _sincronizando = false;
      _resultado = resultado;
    });
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar contactos sincronizados?'),
        content: const Text('Se eliminarán todos los contactos de "Guía Telefónica" de tu agenda. Tus contactos personales no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    final count = await _syncService.removeAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ $count contactos eliminados de la agenda')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📇 Identificador de llamadas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.phone_callback, size: 48, color: Color(0xFF0284C7)),
                    SizedBox(height: 12),
                    Text('Sincroniza los contactos de la guía con tu agenda para identificar llamadas y SMS automáticamente.',
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('¿Cómo funciona?', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('• Si el contacto NO está en tu agenda → se crea nuevo'),
                    Text('• Si el contacto YA existe (mismo nombre) → se agrega el número'),
                    Text('• Si el contacto está reportado → se marca con ⚠️'),
                    Text('• Tus contactos personales NO se modifican'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _sincronizando ? null : _sincronizar,
              icon: _sincronizando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(_sincronizando ? 'Sincronizando...' : 'Sincronizar con agenda'),
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _eliminar,
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('Eliminar de la agenda', style: TextStyle(color: Colors.red)),
            ),

            if (_resultado != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('✅ Sincronización completada', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('🆕 Nuevos: ${_resultado!['created']}'),
                      Text('📝 Actualizados: ${_resultado!['updated']}'),
                      Text('✓ Ya existían: ${_resultado!['exists']}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
