import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
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
  final _searchCtrl = TextEditingController();

  List<Contacto> _contactos = [];
  List<Contacto> _filtrados = [];
  Set<String> _seleccionados = {};
  bool _cargando = true;
  bool _sincronizando = false;
  bool _seleccionTodos = false;
  SyncProgress? _progreso;
  String _modo = 'inicio'; // inicio, seleccion, sincronizando, eliminando, completado, completado_eliminar
  String _accionPendiente = 'sync'; // sync o eliminar

  @override
  void initState() {
    super.initState();
    _cargarContactos();
  }

  Future<void> _cargarContactos() async {
    final contactos = await _localDb.getAllContactos();
    setState(() {
      _contactos = contactos;
      _filtrados = contactos;
      _cargando = false;
    });
  }

  void _filtrar(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtrados = _contactos;
      } else {
        final q = query.toLowerCase();
        _filtrados = _contactos.where((c) =>
          c.nombre.toLowerCase().contains(q) ||
          c.apellido.toLowerCase().contains(q) ||
          c.telefono.contains(q)
        ).toList();
      }
    });
  }

  void _toggleSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) {
        _seleccionados.remove(id);
      } else {
        _seleccionados.add(id);
      }
    });
  }

  void _toggleTodos() {
    setState(() {
      if (_seleccionTodos) {
        _seleccionados.clear();
      } else {
        _seleccionados = _filtrados.map((c) => c.id).toSet();
      }
      _seleccionTodos = !_seleccionTodos;
    });
  }

  Future<bool> _pedirPermiso() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Se necesita permiso de contactos'), backgroundColor: Colors.orange),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _sincronizarTodos() async {
    if (!await _pedirPermiso()) return;
    _iniciarSync(_contactos);
  }

  Future<void> _sincronizarSeleccionados() async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Selecciona al menos un contacto')),
      );
      return;
    }
    if (!await _pedirPermiso()) return;

    final seleccionados = _contactos.where((c) => _seleccionados.contains(c.id)).toList();

    if (_accionPendiente == 'eliminar') {
      _iniciarEliminacion(seleccionados);
    } else {
      _iniciarSync(seleccionados);
    }
  }

  void _iniciarSync(List<Contacto> contactos) {
    setState(() {
      _sincronizando = true;
      _progreso = null;
      _modo = 'sincronizando';
    });

    _syncService.syncContactosStream(contactos).listen(
      (progress) {
        if (mounted) {
          setState(() => _progreso = progress);
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _sincronizando = false;
            _modo = 'completado';
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _sincronizando = false;
            _modo = 'completado';
          });
        }
      },
    );
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar contactos de la agenda?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Se eliminarán los contactos de "Guía Telefónica" de tu agenda. Tus contactos personales no se tocan.'),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx, null), // null = elegir
              child: const Text('Elegir cuáles'),
            )),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Todos'),
            )),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ],
      ),
    );

    if (confirmar == false) return;

    if (!await _pedirPermiso()) return;

    if (confirmar == null) {
      // Modo selección para eliminar
      setState(() {
        _modo = 'seleccion';
        _accionPendiente = 'eliminar';
      });
      return;
    }

    // Eliminar todos con progreso
    _iniciarEliminacion(_contactos);
  }

  void _iniciarEliminacion(List<Contacto> contactos) {
    setState(() {
      _sincronizando = true;
      _progreso = null;
      _modo = 'eliminando';
    });

    _syncService.removeContactosStream(contactos).listen(
      (progress) {
        if (mounted) setState(() => _progreso = progress);
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _sincronizando = false;
            _modo = 'completado_eliminar';
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() {
            _sincronizando = false;
            _modo = 'completado_eliminar';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📇 Sincronizar agenda'),
        actions: [
          if (_modo == 'seleccion')
            TextButton(
              onPressed: _toggleTodos,
              child: Text(_seleccionTodos ? 'Ninguno' : 'Todos'),
            ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    switch (_modo) {
      case 'sincronizando':
        return _buildProgreso(eliminando: false);
      case 'eliminando':
        return _buildProgreso(eliminando: true);
      case 'completado':
        return _buildResultado(eliminando: false);
      case 'completado_eliminar':
        return _buildResultado(eliminando: true);
      case 'seleccion':
        return _buildSeleccion();
      default:
        return _buildInicio();
    }
  }

  Widget _buildInicio() {
    return SingleChildScrollView(
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
                  Text(
                    'Sincroniza los contactos de la guía con tu agenda para identificar llamadas y SMS automáticamente.',
                    textAlign: TextAlign.center,
                  ),
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
            onPressed: _sincronizarTodos,
            icon: const Icon(Icons.sync),
            label: Text('Sincronizar todos (${_contactos.length})'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _modo = 'seleccion'),
            icon: const Icon(Icons.checklist),
            label: const Text('Elegir contactos específicos'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _eliminar,
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text('Eliminar de la agenda', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSeleccion() {
    return Column(
      children: [
        // Barra de búsqueda
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filtrar,
            decoration: InputDecoration(
              hintText: 'Buscar contacto...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _filtrar('');
                      },
                    )
                  : null,
            ),
          ),
        ),

        // Contador
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${_seleccionados.length} seleccionados de ${_filtrados.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleTodos,
                icon: Icon(_seleccionTodos ? Icons.deselect : Icons.select_all, size: 16),
                label: Text(_seleccionTodos ? 'Ninguno' : 'Todos', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Lista
        Expanded(
          child: ListView.builder(
            itemCount: _filtrados.length,
            itemBuilder: (ctx, i) {
              final c = _filtrados[i];
              final seleccionado = _seleccionados.contains(c.id);
              return CheckboxListTile(
                value: seleccionado,
                onChanged: (_) => _toggleSeleccion(c.id),
                title: Text('${c.nombre} ${c.apellido}', style: const TextStyle(fontSize: 14)),
                subtitle: Text(c.telefono, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                secondary: CircleAvatar(
                  backgroundColor: seleccionado ? Colors.blue : Colors.grey[200],
                  child: Text(
                    c.nombre.isNotEmpty ? c.nombre[0].toUpperCase() : '?',
                    style: TextStyle(color: seleccionado ? Colors.white : Colors.grey[700]),
                  ),
                ),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgreso({required bool eliminando}) {
    final p = _progreso;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(eliminando ? Icons.delete_sweep : Icons.sync, size: 64, color: eliminando ? Colors.red : const Color(0xFF0284C7)),
          const SizedBox(height: 24),
          Text(
            eliminando ? 'Eliminando de tu agenda...' : 'Sincronizando con tu agenda...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: p?.progreso ?? 0,
              minHeight: 14,
              backgroundColor: Colors.grey[200],
              color: eliminando ? Colors.red : null,
            ),
          ),
          const SizedBox(height: 12),

          // Porcentaje y conteo
          Text(
            '${((p?.progreso ?? 0) * 100).toStringAsFixed(0)}%  —  ${p?.procesados ?? 0} / ${p?.total ?? 0}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),

          // Contacto actual
          if (p?.contactoActual != null)
            Text(
              p!.contactoActual!,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              overflow: TextOverflow.ellipsis,
            ),

          const SizedBox(height: 24),

          // Stats en tiempo real
          if (p != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: eliminando
                  ? [
                      _statChip('🗑️ ${p.created}', 'eliminados', Colors.red),
                      if (p.errors > 0) _statChip('❌ ${p.errors}', 'errores', Colors.orange),
                    ]
                  : [
                      _statChip('🆕 ${p.created}', 'nuevos', Colors.green),
                      _statChip('📝 ${p.updated}', 'actualizados', Colors.blue),
                      _statChip('✓ ${p.exists}', 'existentes', Colors.grey),
                      if (p.errors > 0) _statChip('❌ ${p.errors}', 'errores', Colors.red),
                    ],
            ),

          const SizedBox(height: 24),
          Text(
            '⚠️ No salgas de esta pantalla',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildResultado({required bool eliminando}) {
    final p = _progreso;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            eliminando ? Icons.delete_forever : Icons.check_circle,
            size: 64,
            color: eliminando ? Colors.red : Colors.green,
          ),
          const SizedBox(height: 16),
          Text(
            eliminando ? '🗑️ Eliminación completada' : '✅ Sincronización completada',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          if (p != null)
            Card(
              color: (eliminando ? Colors.red : Colors.green).withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: eliminando
                      ? [
                          _resultRow('🗑️ Eliminados', p.created),
                          if (p.errors > 0) _resultRow('❌ Errores', p.errors),
                          const Divider(),
                          _resultRow('📊 Total procesados', p.procesados),
                        ]
                      : [
                          _resultRow('🆕 Nuevos en agenda', p.created),
                          _resultRow('📝 Actualizados', p.updated),
                          _resultRow('✓ Ya existían', p.exists),
                          if (p.errors > 0) _resultRow('❌ Errores', p.errors),
                          const Divider(),
                          _resultRow('📊 Total procesados', p.procesados),
                        ],
                ),
              ),
            ),

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => setState(() {
              _modo = 'inicio';
              _progreso = null;
              _seleccionados.clear();
              _accionPendiente = 'sync';
            }),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar() {
    if (_modo != 'seleccion' || _sincronizando) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _modo = 'inicio';
                  _seleccionados.clear();
                  _searchCtrl.clear();
                  _filtrar('');
                  _accionPendiente = 'sync';
                }),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _seleccionados.isEmpty ? null : _sincronizarSeleccionados,
                icon: Icon(_accionPendiente == 'eliminar' ? Icons.delete : Icons.sync),
                label: Text('${_accionPendiente == 'eliminar' ? 'Eliminar' : 'Sincronizar'} (${_seleccionados.length})'),
                style: _accionPendiente == 'eliminar'
                    ? FilledButton.styleFrom(backgroundColor: Colors.red)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('$value $label', style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
    );
  }

  Widget _resultRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text('$value', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
