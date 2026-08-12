import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';

class CallerIdScreen extends StatefulWidget {
  const CallerIdScreen({super.key});

  @override
  State<CallerIdScreen> createState() => _CallerIdScreenState();
}

class _CallerIdScreenState extends State<CallerIdScreen> {
  static const _channel = MethodChannel('guia_telefonica/contacts');
  final _localDb = LocalDatabaseService();
  final _searchCtrl = TextEditingController();

  // Contactos de la guía que YA están en la agenda
  List<Map<String, String>> _enAgenda = [];
  // Contactos de la guía disponibles para sincronizar (NO están en agenda)
  List<Contacto> _disponibles = [];

  Set<String> _seleccionados = {};
  bool _cargando = true;
  bool _procesando = false;
  int _procesados = 0;
  int _total = 0;
  String _statusMsg = '';
  String _modo = 'inicio'; // inicio, verAgenda, seleccionarSync, seleccionarEliminar, procesando, resultado
  String _resultadoTitulo = '';
  String _resultadoMsg = '';
  bool _resultadoOk = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<bool> _pedirPermiso() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Se necesita permiso de contactos'), backgroundColor: Colors.orange),
      );
      return false;
    }
    return true;
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    if (!await _pedirPermiso()) {
      setState(() => _cargando = false);
      return;
    }

    try {
      // Obtener contactos de nuestra cuenta en la agenda
      final result = await _channel.invokeMethod('getGuiaContactsInAgenda');
      final enAgenda = List<Map<dynamic, dynamic>>.from(result)
          .map((m) => {'name': m['name']?.toString() ?? '', 'phone': m['phone']?.toString() ?? ''})
          .toList();

      // Obtener todos los contactos de la BD local
      final todos = await _localDb.getAllContactos();

      // Determinar cuáles NO están en la agenda (disponibles para sync)
      final telefonosEnAgenda = enAgenda.map((c) => _normalizar(c['phone'] ?? '')).toSet();
      final disponibles = todos.where((c) => !telefonosEnAgenda.contains(_normalizar(c.telefono))).toList();

      setState(() {
        _enAgenda = enAgenda;
        _disponibles = disponibles;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _normalizar(String tel) => tel.replaceAll(RegExp(r'[^0-9]'), '');

  // =============== SINCRONIZAR ===============

  Future<void> _sincronizarTodos() async {
    _iniciarSync(_disponibles);
  }

  Future<void> _sincronizarSeleccionados() async {
    if (_seleccionados.isEmpty) return;
    final seleccionados = _disponibles.where((c) => _seleccionados.contains(c.id)).toList();
    _iniciarSync(seleccionados);
  }

  Future<void> _iniciarSync(List<Contacto> contactos) async {
    setState(() {
      _procesando = true;
      _procesados = 0;
      _total = contactos.length;
      _modo = 'procesando';
      _statusMsg = 'Sincronizando...';
    });

    int created = 0, updated = 0, exists = 0, errors = 0;

    for (var i = 0; i < contactos.length; i++) {
      final c = contactos[i];
      try {
        final result = await _channel.invokeMethod('syncContact', {
          'nombre': c.nombre,
          'apellido': c.apellido,
          'telefono': c.telefono,
          'reportado': c.tieneReportes,
        });
        switch (result) {
          case 'created': created++; break;
          case 'updated': updated++; break;
          case 'exists': exists++; break;
        }
      } catch (_) { errors++; }

      if (i % 3 == 0 || i == contactos.length - 1) {
        setState(() {
          _procesados = i + 1;
          _statusMsg = '${c.nombre} ${c.apellido}';
        });
      }
    }

    setState(() {
      _procesando = false;
      _modo = 'resultado';
      _resultadoOk = true;
      _resultadoTitulo = '✅ Sincronización completada';
      _resultadoMsg = '🆕 $created nuevos\n📝 $updated actualizados\n✓ $exists ya existían${errors > 0 ? '\n❌ $errors errores' : ''}';
    });

    _cargarDatos();
  }

  // =============== ELIMINAR ===============

  Future<void> _eliminarTodos() async {
    final confirmar = await _confirmarDialog(
      '¿Eliminar todos?',
      'Se eliminarán los ${_enAgenda.length} contactos de la Guía Telefónica de tu agenda.',
    );
    if (!confirmar) return;

    setState(() {
      _procesando = true;
      _procesados = 0;
      _total = _enAgenda.length;
      _modo = 'procesando';
      _statusMsg = 'Eliminando...';
    });

    int eliminados = 0, errors = 0;

    for (var i = 0; i < _enAgenda.length; i++) {
      final c = _enAgenda[i];
      try {
        final result = await _channel.invokeMethod('removeContact', {'telefono': c['phone']});
        if (result == true) eliminados++;
        else errors++;
      } catch (_) { errors++; }

      if (i % 3 == 0 || i == _enAgenda.length - 1) {
        setState(() {
          _procesados = i + 1;
          _statusMsg = c['name'] ?? '';
        });
      }
    }

    setState(() {
      _procesando = false;
      _modo = 'resultado';
      _resultadoOk = true;
      _resultadoTitulo = '🗑️ Eliminación completada';
      _resultadoMsg = '🗑️ $eliminados eliminados${errors > 0 ? '\n❌ $errors errores' : ''}';
    });

    _cargarDatos();
  }

  Future<void> _eliminarSeleccionados() async {
    if (_seleccionados.isEmpty) return;
    final seleccionados = _enAgenda.where((c) => _seleccionados.contains(c['phone'])).toList();

    setState(() {
      _procesando = true;
      _procesados = 0;
      _total = seleccionados.length;
      _modo = 'procesando';
      _statusMsg = 'Eliminando...';
    });

    int eliminados = 0, errors = 0;

    for (var i = 0; i < seleccionados.length; i++) {
      final c = seleccionados[i];
      try {
        final result = await _channel.invokeMethod('removeContact', {'telefono': c['phone']});
        if (result == true) eliminados++;
        else errors++;
      } catch (_) { errors++; }

      if (i % 3 == 0 || i == seleccionados.length - 1) {
        setState(() {
          _procesados = i + 1;
          _statusMsg = c['name'] ?? '';
        });
      }
    }

    setState(() {
      _procesando = false;
      _modo = 'resultado';
      _resultadoOk = true;
      _resultadoTitulo = '🗑️ Eliminación completada';
      _resultadoMsg = '🗑️ $eliminados eliminados${errors > 0 ? '\n❌ $errors errores' : ''}';
    });

    _cargarDatos();
  }

  Future<bool> _confirmarDialog(String titulo, String mensaje) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
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
    return r ?? false;
  }

  // =============== UI ===============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📇 Sincronizar agenda'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      bottomNavigationBar: _buildBottom(),
    );
  }

  Widget _buildBody() {
    switch (_modo) {
      case 'procesando': return _buildProcesando();
      case 'resultado': return _buildResultado();
      case 'verAgenda': return _buildListaEnAgenda();
      case 'seleccionarSync': return _buildSeleccion(_disponibles.map((c) => {'id': c.id, 'name': '${c.nombre} ${c.apellido}', 'phone': c.telefono}).toList());
      case 'seleccionarEliminar': return _buildSeleccion(_enAgenda.map((c) => {'id': c['phone']!, 'name': c['name']!, 'phone': c['phone']!}).toList());
      default: return _buildInicio();
    }
  }

  Widget _buildInicio() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Estado actual
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.phone_callback, size: 48, color: Color(0xFF0284C7)),
                  const SizedBox(height: 12),
                  Text(
                    '${_enAgenda.length} contactos de la guía en tu agenda',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_disponibles.length} disponibles para sincronizar',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Ver en agenda
          if (_enAgenda.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => setState(() => _modo = 'verAgenda'),
              icon: const Icon(Icons.list),
              label: Text('Ver contactos en agenda (${_enAgenda.length})'),
            ),
          const SizedBox(height: 12),

          // Sincronizar
          if (_disponibles.isNotEmpty) ...[
            FilledButton.icon(
              onPressed: _sincronizarTodos,
              icon: const Icon(Icons.sync),
              label: Text('Sincronizar todos (${_disponibles.length})'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() { _modo = 'seleccionarSync'; _seleccionados.clear(); }),
              icon: const Icon(Icons.checklist),
              label: const Text('Elegir cuáles sincronizar'),
            ),
          ] else
            const Card(
              color: Color(0xFFe8f5e9),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('✅ Todos los contactos ya están en tu agenda', textAlign: TextAlign.center),
              ),
            ),

          const SizedBox(height: 20),

          // Eliminar
          if (_enAgenda.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _eliminarTodos,
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text('Eliminar todos de la agenda (${_enAgenda.length})', style: const TextStyle(color: Colors.red)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() { _modo = 'seleccionarEliminar'; _seleccionados.clear(); }),
              icon: const Icon(Icons.checklist, color: Colors.red),
              label: const Text('Elegir cuáles eliminar', style: TextStyle(color: Colors.red)),
            ),
          ],

          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Cómo funciona?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('• Solo gestiona contactos de "Guía Telefónica"', style: TextStyle(fontSize: 11)),
                  Text('• Tus contactos personales NO se tocan', style: TextStyle(fontSize: 11)),
                  Text('• Los reportados se marcan con ⚠️', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaEnAgenda() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${_enAgenda.length} contactos de la guía en tu agenda',
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _enAgenda.length,
            itemBuilder: (ctx, i) {
              final c = _enAgenda[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person, size: 20)),
                title: Text(c['name'] ?? '', style: const TextStyle(fontSize: 14)),
                subtitle: Text(c['phone'] ?? '', style: const TextStyle(fontSize: 12)),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeleccion(List<Map<String, String>> items) {
    final filtrados = _searchCtrl.text.isEmpty
        ? items
        : items.where((c) {
            final q = _searchCtrl.text.toLowerCase();
            return (c['name'] ?? '').toLowerCase().contains(q) || (c['phone'] ?? '').contains(q);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() {}); })
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${_seleccionados.length} seleccionados', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  if (_seleccionados.length == items.length) {
                    _seleccionados.clear();
                  } else {
                    _seleccionados = items.map((c) => c['id']!).toSet();
                  }
                }),
                child: Text(_seleccionados.length == items.length ? 'Ninguno' : 'Todos', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtrados.length,
            itemBuilder: (ctx, i) {
              final c = filtrados[i];
              final sel = _seleccionados.contains(c['id']);
              return CheckboxListTile(
                value: sel,
                onChanged: (_) => setState(() {
                  if (sel) _seleccionados.remove(c['id']);
                  else _seleccionados.add(c['id']!);
                }),
                title: Text(c['name'] ?? '', style: const TextStyle(fontSize: 14)),
                subtitle: Text(c['phone'] ?? '', style: const TextStyle(fontSize: 12)),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProcesando() {
    final progreso = _total > 0 ? _procesados / _total : 0.0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _statusMsg.contains('Eliminando') ? Icons.delete_sweep : Icons.sync,
            size: 64,
            color: _statusMsg.contains('Eliminando') ? Colors.red : const Color(0xFF0284C7),
          ),
          const SizedBox(height: 24),
          Text(
            '$_procesados / $_total',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progreso,
              minHeight: 14,
              backgroundColor: Colors.grey[200],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progreso * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(_statusMsg, style: TextStyle(fontSize: 12, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 24),
          Text('⚠️ No salgas de esta pantalla', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildResultado() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _resultadoOk ? Icons.check_circle : Icons.error,
            size: 64,
            color: _resultadoOk ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 16),
          Text(_resultadoTitulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(_resultadoMsg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => setState(() { _modo = 'inicio'; _seleccionados.clear(); }),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottom() {
    if (_modo == 'verAgenda') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: () => setState(() => _modo = 'inicio'),
            child: const Text('Volver'),
          ),
        ),
      );
    }

    if (_modo == 'seleccionarSync') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() { _modo = 'inicio'; _seleccionados.clear(); _searchCtrl.clear(); }),
                child: const Text('Cancelar'),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _seleccionados.isEmpty ? null : _sincronizarSeleccionados,
                icon: const Icon(Icons.sync),
                label: Text('Sincronizar (${_seleccionados.length})'),
              )),
            ],
          ),
        ),
      );
    }

    if (_modo == 'seleccionarEliminar') {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() { _modo = 'inicio'; _seleccionados.clear(); _searchCtrl.clear(); }),
                child: const Text('Cancelar'),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _seleccionados.isEmpty ? null : _eliminarSeleccionados,
                icon: const Icon(Icons.delete),
                label: Text('Eliminar (${_seleccionados.length})'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              )),
            ],
          ),
        ),
      );
    }

    return null;
  }
}
