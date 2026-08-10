import 'dart:async';
import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/supabase_service.dart';
import '../services/ubicacion_service.dart';

class ContactosListScreen extends StatefulWidget {
  final String estado;
  final String titulo;

  const ContactosListScreen({
    super.key,
    required this.estado,
    required this.titulo,
  });

  @override
  State<ContactosListScreen> createState() => _ContactosListScreenState();
}

class _ContactosListScreenState extends State<ContactosListScreen> {
  final _supabase = SupabaseService();
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();

  List<Contacto> _contactos = [];
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = true;
  int _page = 0;
  String? _query;
  Timer? _debounce;

  // Selección en lote
  final Set<String> _seleccionados = {};
  bool _modoSeleccion = false;

  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 0;
        _contactos = [];
        _cargando = true;
        _hayMas = true;
        _seleccionados.clear();
        _modoSeleccion = false;
      });
    }

    try {
      final resultados = await _supabase.getContactosPorEstado(
        widget.estado,
        page: _page,
        limit: _limit,
        query: _query,
      );

      setState(() {
        _contactos.addAll(resultados);
        _hayMas = resultados.length == _limit;
        _cargando = false;
        _cargandoMas = false;
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _cargandoMas = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;
    setState(() {
      _cargandoMas = true;
      _page++;
    });
    await _cargar(reset: false);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (value.length >= 3 || value.isEmpty) {
        setState(() => _query = value.isEmpty ? null : value);
        _cargar();
      }
    });
  }

  // === ACCIONES INDIVIDUALES ===

  Future<void> _aprobar(Contacto contacto) async {
    await _supabase.aprobarContacto(contacto.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${contacto.nombreCompleto} aprobado')),
      );
    }
    _cargar();
  }

  Future<void> _rechazar(Contacto contacto) async {
    final motivo = await _mostrarDialogo('Motivo de rechazo', 'Ej: Número incorrecto');
    if (motivo == null || motivo.isEmpty) return;

    await _supabase.rechazarContacto(contacto.id, motivo);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${contacto.nombreCompleto} rechazado')),
      );
    }
    _cargar();
  }

  Future<void> _eliminar(Contacto contacto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar contacto?'),
        content: Text('Se eliminará "${contacto.nombreCompleto}" permanentemente.'),
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

    await _supabase.eliminarContacto(contacto.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ ${contacto.nombreCompleto} eliminado')),
      );
    }
    _cargar();
  }

  Future<void> _editar(Contacto contacto, {bool aprobarAlGuardar = false}) async {
    final nombreCtrl = TextEditingController(text: contacto.nombre);
    final apellidoCtrl = TextEditingController(text: contacto.apellido);
    final telefonoCtrl = TextEditingController(text: contacto.telefono);
    final direccionCtrl = TextEditingController(text: contacto.direccion ?? '');
    final ciCtrl = TextEditingController(text: contacto.ci ?? '');
    String? provinciaSeleccionada = contacto.provincia;
    String? municipioSeleccionado = contacto.municipio;
    List<String> municipiosDisponibles = provinciaSeleccionada != null
        ? UbicacionService.getMunicipios(provinciaSeleccionada)
        : [];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final provincias = UbicacionService.getProvincias();
          return AlertDialog(
            title: Text(aprobarAlGuardar ? 'Editar y Aprobar' : 'Editar contacto'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                  TextField(controller: apellidoCtrl, decoration: const InputDecoration(labelText: 'Apellido')),
                  TextField(controller: telefonoCtrl, decoration: const InputDecoration(labelText: 'Teléfono'), keyboardType: TextInputType.phone),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: provinciaSeleccionada,
                    decoration: const InputDecoration(labelText: 'Provincia'),
                    isExpanded: true,
                    items: provincias.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        provinciaSeleccionada = v;
                        municipioSeleccionado = null;
                        municipiosDisponibles = v != null ? UbicacionService.getMunicipios(v) : [];
                      });
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: municipioSeleccionado,
                    decoration: const InputDecoration(labelText: 'Municipio'),
                    isExpanded: true,
                    items: municipiosDisponibles.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setDialogState(() => municipioSeleccionado = v),
                  ),
                  TextField(controller: direccionCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
                  TextField(controller: ciCtrl, decoration: const InputDecoration(labelText: 'CI')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: aprobarAlGuardar ? FilledButton.styleFrom(backgroundColor: Colors.green) : null,
                child: Text(aprobarAlGuardar ? 'Guardar y Aprobar' : 'Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final datos = <String, dynamic>{
      'nombre': nombreCtrl.text.trim(),
      'apellido': apellidoCtrl.text.trim(),
      'telefono': telefonoCtrl.text.trim(),
      'direccion': direccionCtrl.text.trim().isNotEmpty ? direccionCtrl.text.trim() : null,
      'ci': ciCtrl.text.trim().isNotEmpty ? ciCtrl.text.trim() : null,
      'provincia': provinciaSeleccionada,
      'municipio': municipioSeleccionado,
    };

    if (aprobarAlGuardar) {
      datos['estado'] = 'aprobado';
      datos['fecha_aprobacion'] = DateTime.now().toIso8601String();
    }

    await _supabase.editarContacto(contacto.id, datos);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aprobarAlGuardar
            ? '✅ ${nombreCtrl.text} editado y aprobado'
            : '✏️ Contacto actualizado')),
      );
    }
    _cargar();
  }

  // === ACCIONES EN LOTE ===

  void _toggleSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) {
        _seleccionados.remove(id);
        if (_seleccionados.isEmpty) _modoSeleccion = false;
      } else {
        _seleccionados.add(id);
        _modoSeleccion = true;
      }
    });
  }

  void _seleccionarTodos() {
    setState(() {
      if (_seleccionados.length == _contactos.length) {
        _seleccionados.clear();
        _modoSeleccion = false;
      } else {
        _seleccionados.addAll(_contactos.map((c) => c.id));
        _modoSeleccion = true;
      }
    });
  }

  Future<void> _aprobarLote() async {
    if (_seleccionados.isEmpty) return;
    final count = _seleccionados.length;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprobar en lote'),
        content: Text('¿Aprobar $count contactos seleccionados?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Aprobar todos'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    for (final id in _seleccionados) {
      await _supabase.aprobarContacto(id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $count contactos aprobados')),
      );
    }
    _cargar();
  }

  Future<void> _rechazarLote() async {
    if (_seleccionados.isEmpty) return;
    final count = _seleccionados.length;
    final motivo = await _mostrarDialogo('Motivo de rechazo (lote)', 'Se aplicará a los $count seleccionados');
    if (motivo == null || motivo.isEmpty) return;

    for (final id in _seleccionados) {
      await _supabase.rechazarContacto(id, motivo);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $count contactos rechazados')),
      );
    }
    _cargar();
  }

  Future<String?> _mostrarDialogo(String titulo, String hint) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        actions: [
          if (_contactos.isNotEmpty && widget.estado == 'pendiente')
            IconButton(
              icon: Icon(_seleccionados.length == _contactos.length ? Icons.deselect : Icons.select_all),
              onPressed: _seleccionarTodos,
              tooltip: 'Seleccionar todos',
            ),
        ],
      ),
      // Barra de acciones en lote
      bottomNavigationBar: _modoSeleccion
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Text('${_seleccionados.length} seleccionados',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (widget.estado == 'pendiente') ...[
                      OutlinedButton.icon(
                        onPressed: _rechazarLote,
                        icon: const Icon(Icons.close, color: Colors.red, size: 18),
                        label: const Text('Rechazar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _aprobarLote,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Aprobar'),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          // Búsqueda
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar (mínimo 3 caracteres)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Contador
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${_contactos.length} contactos${_hayMas ? " (hay más)" : ""}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          // Lista
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _contactos.isEmpty
                    ? const Center(child: Text('No se encontraron contactos'))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _contactos.length + (_hayMas ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _contactos.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _cargandoMas
                                    ? const CircularProgressIndicator()
                                    : OutlinedButton(
                                        onPressed: _cargarMas,
                                        child: const Text('Cargar más'),
                                      ),
                              ),
                            );
                          }

                          final contacto = _contactos[index];
                          final seleccionado = _seleccionados.contains(contacto.id);

                          return _ContactoAdminCard(
                            contacto: contacto,
                            estado: widget.estado,
                            seleccionado: seleccionado,
                            modoSeleccion: _modoSeleccion,
                            onTap: _modoSeleccion ? () => _toggleSeleccion(contacto.id) : null,
                            onLongPress: () => _toggleSeleccion(contacto.id),
                            onAprobar: () => _aprobar(contacto),
                            onRechazar: () => _rechazar(contacto),
                            onEditar: () => _editar(contacto),
                            onEditarYAprobar: () => _editar(contacto, aprobarAlGuardar: true),
                            onEliminar: () => _eliminar(contacto),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}

class _ContactoAdminCard extends StatelessWidget {
  final Contacto contacto;
  final String estado;
  final bool seleccionado;
  final bool modoSeleccion;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;
  final VoidCallback onEditar;
  final VoidCallback onEditarYAprobar;
  final VoidCallback onEliminar;

  const _ContactoAdminCard({
    required this.contacto,
    required this.estado,
    required this.seleccionado,
    required this.modoSeleccion,
    this.onTap,
    required this.onLongPress,
    required this.onAprobar,
    required this.onRechazar,
    required this.onEditar,
    required this.onEditarYAprobar,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: seleccionado ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (modoSeleccion)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        seleccionado ? Icons.check_circle : Icons.circle_outlined,
                        color: seleccionado ? Theme.of(context).colorScheme.primary : Colors.grey,
                        size: 22,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      contacto.nombreCompleto,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  if (contacto.creadoDesde != null)
                    Chip(
                      label: Text(contacto.creadoDesde!, style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('📱 ${contacto.telefono}'),
              if (contacto.provincia != null || contacto.municipio != null)
                Text('📍 ${contacto.ubicacionCompleta ?? ""}'),
              if (contacto.direccion != null) Text('🏠 ${contacto.direccion}'),
              if (contacto.ci != null) Text('🆔 ${contacto.ci}'),
              if (contacto.motivoRechazo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '💬 Motivo: ${contacto.motivoRechazo}',
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                ),
              if (!modoSeleccion) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (estado == 'pendiente') ...[
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEditar, tooltip: 'Editar'),
                      IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: onRechazar, tooltip: 'Rechazar'),
                      IconButton(icon: const Icon(Icons.check, color: Colors.green, size: 20), onPressed: onAprobar, tooltip: 'Aprobar'),
                      IconButton(
                        icon: const Icon(Icons.edit_note, color: Colors.teal, size: 20),
                        onPressed: onEditarYAprobar,
                        tooltip: 'Editar y Aprobar',
                      ),
                    ],
                    if (estado == 'aprobado') ...[
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEditar, tooltip: 'Editar'),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: onEliminar, tooltip: 'Eliminar'),
                    ],
                    if (estado == 'rechazado') ...[
                      IconButton(icon: const Icon(Icons.check, color: Colors.green, size: 20), onPressed: onAprobar, tooltip: 'Re-aprobar'),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: onEliminar, tooltip: 'Eliminar'),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
