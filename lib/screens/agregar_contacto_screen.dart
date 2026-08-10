import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/ubicacion_service.dart';

class AgregarContactoScreen extends StatefulWidget {
  const AgregarContactoScreen({super.key});

  @override
  State<AgregarContactoScreen> createState() => _AgregarContactoScreenState();
}

class _AgregarContactoScreenState extends State<AgregarContactoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _ciCtrl = TextEditingController();
  final _supabase = SupabaseService();

  bool _enviando = false;
  List<Map<String, dynamic>> _categorias = [];
  String? _categoriaSeleccionada;
  String? _provinciaSeleccionada;
  String? _municipioSeleccionado;
  List<String> _municipiosDisponibles = [];

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    UbicacionService.init();
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await _supabase.getCategorias();
      setState(() => _categorias = cats);
    } catch (_) {}
  }

  void _onProvinciaChanged(String? provincia) {
    setState(() {
      _provinciaSeleccionada = provincia;
      _municipioSeleccionado = null;
      _municipiosDisponibles = provincia != null
          ? UbicacionService.getMunicipios(provincia)
          : [];
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);

    final resultado = await _supabase.registrarContacto(
      nombre: _nombreCtrl.text.trim(),
      apellido: _apellidoCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim().isNotEmpty ? _direccionCtrl.text.trim() : null,
      ci: _ciCtrl.text.trim().isNotEmpty ? _ciCtrl.text.trim() : null,
      categoriaId: _categoriaSeleccionada,
      provincia: _provinciaSeleccionada,
      municipio: _municipioSeleccionado,
    );

    setState(() => _enviando = false);

    if (!mounted) return;

    if (resultado['error'] != null) {
      final error = resultado['error'].toString();
      String mensaje = 'Error al registrar contacto';
      if (error.contains('duplicate') || error.contains('unique')) {
        mensaje = 'Ese teléfono o CI ya está registrado';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $mensaje'), backgroundColor: Colors.red),
      );
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provincias = UbicacionService.getProvincias();

    return Scaffold(
      appBar: AppBar(title: const Text('✏️ Nuevo Contacto')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().length < 2
                    ? 'Mínimo 2 caracteres'
                    : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _apellidoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Apellido *',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().length < 2
                    ? 'Mínimo 2 caracteres'
                    : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _telefonoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Teléfono *',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.trim().length < 5
                    ? 'Mínimo 5 dígitos'
                    : null,
              ),
              const SizedBox(height: 12),

              // === UBICACIÓN ===
              DropdownButtonFormField<String>(
                value: _provinciaSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Provincia',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
                items: provincias.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p));
                }).toList(),
                onChanged: _onProvinciaChanged,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _municipioSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  prefixIcon: Icon(Icons.location_city),
                  border: OutlineInputBorder(),
                ),
                items: _municipiosDisponibles.map((m) {
                  return DropdownMenuItem(value: m, child: Text(m));
                }).toList(),
                onChanged: (v) => setState(() => _municipioSeleccionado = v),
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _ciCtrl,
                decoration: const InputDecoration(
                  labelText: 'CI (Carnet de Identidad)',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              if (_categorias.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _categoriaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  items: _categorias.map((cat) {
                    return DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Text('${cat['icono'] ?? "📋"} ${cat['nombre']}'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _categoriaSeleccionada = v),
                ),

              const SizedBox(height: 24),

              FilledButton.icon(
                onPressed: _enviando ? null : _guardar,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_enviando ? 'Enviando...' : 'GUARDAR'),
              ),

              const SizedBox(height: 16),
              const Text(
                'ℹ️ El registro será enviado para aprobación del administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _ciCtrl.dispose();
    super.dispose();
  }
}
