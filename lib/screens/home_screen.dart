import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import 'agregar_contacto_screen.dart';
import 'login_admin_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _localDb = LocalDatabaseService();
  final _supabaseService = SupabaseService();

  List<Contacto> _contactos = [];
  List<Contacto> _filtrados = [];
  bool _cargando = true;
  DateTime? _ultimaSync;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
    _sincronizar();
    _verificarActualizacion();
  }

  Future<void> _verificarActualizacion() async {
    final updateService = UpdateService();
    final update = await updateService.checkForUpdate();
    if (update != null && mounted) {
      UpdateService.showUpdateDialog(context, update);
    }
  }

  Future<void> _cargarContactos() async {
    setState(() => _cargando = true);
    final contactos = await _localDb.getAllContactos();
    _ultimaSync = await _localDb.getUltimaSincronizacion();
    setState(() {
      _contactos = contactos;
      _filtrados = contactos;
      _cargando = false;
    });
  }

  Future<void> _sincronizar() async {
    try {
      final ultimaSync = await _localDb.getUltimaSincronizacion();
      final nuevos = await _supabaseService.getContactosAprobadosDesde(ultimaSync);

      if (nuevos.isNotEmpty) {
        await _localDb.sincronizarBatch(nuevos);
      }

      // Eliminar los que fueron borrados en la nube
      if (ultimaSync != null) {
        final eliminados = await _supabaseService.getContactosEliminadosDesde(ultimaSync);
        for (final id in eliminados) {
          await _localDb.eliminarContacto(id);
        }
      }

      await _localDb.guardarUltimaSincronizacion(DateTime.now());
      await _cargarContactos();
    } catch (e) {
      // Sin conexión — usar datos locales
      debugPrint('Sync error: $e');
    }
  }

  void _filtrar(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtrados = _contactos;
      } else {
        _filtrados = _contactos.where((c) {
          final q = query.toLowerCase();
          return c.nombre.toLowerCase().contains(q) ||
              c.apellido.toLowerCase().contains(q) ||
              c.telefono.contains(q) ||
              (c.ci?.contains(q) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _llamar(String telefono) async {
    final uri = Uri.parse('tel:$telefono');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Guía Telefónica'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar',
            onPressed: _sincronizar,
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'Admin',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginAdminScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar contacto...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrar('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onChanged: _filtrar,
            ),
          ),

          // Info de sincronización
          if (_ultimaSync != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Última sync: ${_formatearFecha(_ultimaSync!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          // Lista de contactos
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _filtrados.isEmpty
                    ? const Center(
                        child: Text('No se encontraron contactos'),
                      )
                    : RefreshIndicator(
                        onRefresh: _sincronizar,
                        child: ListView.builder(
                          itemCount: _filtrados.length,
                          itemBuilder: (context, index) {
                            return _ContactoCard(
                              contacto: _filtrados[index],
                              onLlamar: _llamar,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AgregarContactoScreen()),
          );
          if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Contacto enviado para aprobación')),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }
}

class _ContactoCard extends StatelessWidget {
  final Contacto contacto;
  final Function(String) onLlamar;

  const _ContactoCard({required this.contacto, required this.onLlamar});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            contacto.nombre[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(contacto.nombreCompleto),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📱 ${contacto.telefono}'),
            if (contacto.direccion != null)
              Text('📍 ${contacto.direccion}', style: Theme.of(context).textTheme.bodySmall),
            if (contacto.categoriaNombre != null)
              Text('${contacto.categoriaIcono ?? "📂"} ${contacto.categoriaNombre}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.phone, color: Colors.green),
          onPressed: () => onLlamar(contacto.telefono),
        ),
        isThreeLine: true,
      ),
    );
  }
}
