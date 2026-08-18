import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla de edición en caliente de registros que fallaron en la importación.
/// Solo accesible desde el flujo de importación (admin).
/// Los registros confirmados se guardan directamente como 'aprobado'.
class ErroresImportScreen extends StatefulWidget {
  final List<Map<String, String>> errores;

  const ErroresImportScreen({super.key, required this.errores});

  @override
  State<ErroresImportScreen> createState() => _ErroresImportScreenState();
}

class _ErroresImportScreenState extends State<ErroresImportScreen> {
  // Lista mutable de registros editables
  late List<_RegistroEditable> _registros;

  // Control de selección
  final Set<int> _seleccionados = {};
  bool _todoSeleccionado = false;

  // Estado de guardado
  bool _guardando = false;
  int _guardados = 0;

  @override
  void initState() {
    super.initState();
    _registros = widget.errores
        .map((e) => _RegistroEditable.fromMap(e))
        .toList();
  }

  void _toggleSeleccion(int index) {
    setState(() {
      if (_seleccionados.contains(index)) {
        _seleccionados.remove(index);
      } else {
        _seleccionados.add(index);
      }
      _todoSeleccionado = _seleccionados.length == _registros.length;
    });
  }

  void _toggleTodos() {
    setState(() {
      if (_todoSeleccionado) {
        _seleccionados.clear();
        _todoSeleccionado = false;
      } else {
        _seleccionados.addAll(List.generate(_registros.length, (i) => i));
        _todoSeleccionado = true;
      }
    });
  }

  Future<void> _editarRegistro(int index) async {
    final reg = _registros[index];
    final result = await showModalBottomSheet<_RegistroEditable>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditorRegistro(registro: reg),
    );
    if (result != null) {
      setState(() {
        _registros[index] = result;
        // Auto-seleccionar al editar
        _seleccionados.add(index);
      });
    }
  }

  Future<void> _registrarSeleccionados() async {
    if (_seleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un registro')),
      );
      return;
    }

    // Validar que los seleccionados tienen datos mínimos
    final invalidos = _seleccionados.where((i) {
      final r = _registros[i];
      return r.nombre.trim().length < 2 ||
          r.apellido.trim().length < 2 ||
          r.telefono.trim().length < 5;
    }).toList();

    if (invalidos.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${invalidos.length} registro(s) aún tienen datos incompletos. Edítalos primero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final client = Supabase.instance.client;
      final batch = _seleccionados.map((i) {
        final r = _registros[i];
        return {
          'nombre':               r.nombre.trim().toUpperCase(),
          'apellido':             r.apellido.trim().toUpperCase(),
          'telefono':             r.telefono.trim(),
          'direccion':            r.direccion.trim().isEmpty ? null : r.direccion.trim(),
          'ci':                   r.ci.trim().isEmpty ? null : r.ci.trim(),
          'provincia':            r.provincia.trim().isEmpty ? null : r.provincia.trim(),
          'municipio':            r.municipio.trim().isEmpty ? null : r.municipio.trim().toUpperCase(),
          'estado':               'aprobado',
          'creado_desde':         'app',
          'fecha_aprobacion':     DateTime.now().toIso8601String(),
          'ultima_modificacion':  DateTime.now().toIso8601String(),
        };
      }).toList();

      await client
          .from('contactos')
          .upsert(batch, onConflict: 'telefono');

      _guardados = _seleccionados.length;

      // Eliminar los guardados de la lista
      final indices = _seleccionados.toList()..sort((a, b) => b.compareTo(a));
      for (final i in indices) {
        _registros.removeAt(i);
      }
      _seleccionados.clear();
      _todoSeleccionado = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $_guardados contactos registrados como aprobados'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _guardando = false);

        if (_registros.isEmpty) {
          Navigator.pop(context, _guardados);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportarErrores() async {
    try {
      final rows = [
        ['nombre', 'apellido', 'telefono', 'direccion', 'ci', 'provincia', 'municipio', 'motivo_error'],
        ..._registros.map((r) => [
          r.nombre, r.apellido, r.telefono,
          r.direccion, r.ci, r.provincia, r.municipio,
          r.motivo,
        ]),
      ];
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/errores_importacion_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Errores de importación — ${_registros.length} registros',
        text: 'Corrige los datos y reimporta el archivo.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exportando: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final haySeleccion = _seleccionados.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('⚠️ Errores (${_registros.length})'),
        actions: [
          // Exportar CSV
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar errores CSV',
            onPressed: _registros.isEmpty ? null : _exportarErrores,
          ),
          // Seleccionar todos
          IconButton(
            icon: Icon(_todoSeleccionado
                ? Icons.check_box
                : Icons.check_box_outline_blank),
            tooltip: _todoSeleccionado ? 'Deseleccionar todos' : 'Seleccionar todos',
            onPressed: _registros.isEmpty ? null : _toggleTodos,
          ),
        ],
      ),
      body: _registros.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 12),
                  Text('Todos los errores resueltos',
                      style: TextStyle(fontSize: 16, color: Colors.green)),
                ],
              ),
            )
          : Column(
              children: [
                // Info header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: Colors.orange.withOpacity(0.1),
                  child: Text(
                    '${_registros.length} registros no se importaron. '
                    'Toca ✏️ para editar, selecciona los que quieras guardar y confirma.',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
                // Lista
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _registros.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = _registros[i];
                      final seleccionado = _seleccionados.contains(i);
                      final valido = r.nombre.trim().length >= 2 &&
                          r.apellido.trim().length >= 2 &&
                          r.telefono.trim().length >= 5;

                      return ListTile(
                        leading: Checkbox(
                          value: seleccionado,
                          onChanged: (_) => _toggleSeleccion(i),
                          activeColor: Colors.green,
                        ),
                        title: Text(
                          '${r.nombre} ${r.apellido}'.trim().isNotEmpty
                              ? '${r.nombre} ${r.apellido}'.trim()
                              : '(sin nombre)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: valido ? null : Colors.red,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.telefono.isNotEmpty ? '📱 ${r.telefono}' : '📱 (sin teléfono)',
                              style: TextStyle(
                                fontSize: 11,
                                color: r.telefono.length >= 5 ? Colors.grey : Colors.red,
                              ),
                            ),
                            Text(
                              r.motivo,
                              style: const TextStyle(fontSize: 10, color: Colors.red),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                          tooltip: 'Editar',
                          onPressed: () => _editarRegistro(i),
                        ),
                        onTap: () => _toggleSeleccion(i),
                      );
                    },
                  ),
                ),
              ],
            ),

      // FAB de confirmación
      floatingActionButton: haySeleccion
          ? FloatingActionButton.extended(
              onPressed: _guardando ? null : _registrarSeleccionados,
              icon: _guardando
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _guardando
                    ? 'Guardando...'
                    : 'Aprobar ${_seleccionados.length} seleccionados',
              ),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Modelo editable en memoria
// ─────────────────────────────────────────────────────────────
class _RegistroEditable {
  String nombre;
  String apellido;
  String telefono;
  String direccion;
  String ci;
  String provincia;
  String municipio;
  String motivo;

  _RegistroEditable({
    required this.nombre,
    required this.apellido,
    required this.telefono,
    required this.direccion,
    required this.ci,
    required this.provincia,
    required this.municipio,
    required this.motivo,
  });

  factory _RegistroEditable.fromMap(Map<String, String> m) => _RegistroEditable(
    nombre:    m['nombre']    ?? '',
    apellido:  m['apellido']  ?? '',
    telefono:  m['telefono']  ?? '',
    direccion: m['direccion'] ?? '',
    ci:        m['ci']        ?? '',
    provincia: m['provincia'] ?? '',
    municipio: m['municipio'] ?? '',
    motivo:    m['_motivo']   ?? 'Error desconocido',
  );

  _RegistroEditable copyWith({
    String? nombre, String? apellido, String? telefono,
    String? direccion, String? ci, String? provincia, String? municipio,
  }) => _RegistroEditable(
    nombre:    nombre    ?? this.nombre,
    apellido:  apellido  ?? this.apellido,
    telefono:  telefono  ?? this.telefono,
    direccion: direccion ?? this.direccion,
    ci:        ci        ?? this.ci,
    provincia: provincia ?? this.provincia,
    municipio: municipio ?? this.municipio,
    motivo:    motivo,
  );
}

// ─────────────────────────────────────────────────────────────
// Bottom sheet de edición inline
// ─────────────────────────────────────────────────────────────
class _EditorRegistro extends StatefulWidget {
  final _RegistroEditable registro;
  const _EditorRegistro({required this.registro});

  @override
  State<_EditorRegistro> createState() => _EditorRegistroState();
}

class _EditorRegistroState extends State<_EditorRegistro> {
  late final TextEditingController _nombre;
  late final TextEditingController _apellido;
  late final TextEditingController _telefono;
  late final TextEditingController _direccion;
  late final TextEditingController _ci;
  late final TextEditingController _provincia;
  late final TextEditingController _municipio;

  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    _nombre    = TextEditingController(text: r.nombre);
    _apellido  = TextEditingController(text: r.apellido);
    _telefono  = TextEditingController(text: r.telefono);
    _direccion = TextEditingController(text: r.direccion);
    _ci        = TextEditingController(text: r.ci);
    _provincia = TextEditingController(text: r.provincia);
    _municipio = TextEditingController(text: r.municipio);
  }

  @override
  void dispose() {
    for (final c in [_nombre, _apellido, _telefono, _direccion, _ci, _provincia, _municipio]) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirmar() {
    Navigator.pop(
      context,
      widget.registro.copyWith(
        nombre:    _nombre.text,
        apellido:  _apellido.text,
        telefono:  _telefono.text,
        direccion: _direccion.text,
        ci:        _ci.text,
        provincia: _provincia.text,
        municipio: _municipio.text,
      ),
    );
  }

  Widget _campo(String label, TextEditingController ctrl, {bool requerido = false, TextInputType? tipo}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: tipo,
        decoration: InputDecoration(
          labelText: requerido ? '$label *' : label,
          isDense: true,
          border: const OutlineInputBorder(),
          errorText: requerido && ctrl.text.trim().length < 2 ? 'Requerido' : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valido = _nombre.text.trim().length >= 2 &&
        _apellido.text.trim().length >= 2 &&
        _telefono.text.trim().length >= 5;

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Motivo del error
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⚠️ ${widget.registro.motivo}',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
            const SizedBox(height: 12),
            _campo('Nombre', _nombre, requerido: true),
            _campo('Apellido', _apellido, requerido: true),
            _campo('Teléfono', _telefono, requerido: true, tipo: TextInputType.phone),
            _campo('Dirección', _direccion),
            _campo('CI', _ci),
            _campo('Provincia', _provincia),
            _campo('Municipio', _municipio),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: valido ? _confirmar : null,
              icon: const Icon(Icons.check),
              label: const Text('Aplicar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}
