import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import 'agregar_contacto_screen.dart';
import 'acerca_de_screen.dart';
import 'caller_id_screen.dart';
import 'contacto_detalle_screen.dart';
import 'escanear_agenda_screen.dart';
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
  List<Contacto> _favoritos = [];
  List<Map<String, dynamic>> _categorias = [];
  String? _categoriaFiltro;
  bool _cargando = true;
  DateTime? _ultimaSync;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
    _cargarCategorias();
    _sincronizar();
    _verificarActualizacion();
  }

  Future<void> _verificarActualizacion() async {
    _buscarActualizacion(manual: false);
  }

  Future<void> _buscarActualizacion({bool manual = false}) async {
    final updateService = UpdateService();
    final update = await updateService.checkForUpdate();
    if (!mounted) return;

    if (update != null) {
      UpdateService.showUpdateDialog(context, update);
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Ya tienes la última versión')),
      );
    }
  }

  Future<void> _cargarContactos() async {
    setState(() => _cargando = true);
    final contactos = await _localDb.getAllContactos();
    _ultimaSync = await _localDb.getUltimaSincronizacion();
    final favIds = await _localDb.getFavoritosIds();
    final favoritos = contactos.where((c) => favIds.contains(c.id)).toList();
    setState(() {
      _contactos = contactos;
      _filtrados = contactos;
      _favoritos = favoritos;
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
      // Actualizar campo tiene_reportes
      try {
        final idsReportados = await _supabaseService.getContactosConReportes();
        final contactos = await _localDb.getAllContactos();
        final reportesMap = <String, bool>{};
        for (final c in contactos) {
          reportesMap[c.id] = idsReportados.contains(c.id);
        }
        await _localDb.actualizarReportes(reportesMap);
      } catch (_) {}
      await _cargarContactos();
    } catch (e) {
      // Sin conexión — usar datos locales
      debugPrint('Sync error: $e');
    }
  }

  Future<void> _cargarCategorias() async {
    try {
      // Intentar desde Supabase
      final cats = await _supabaseService.getCategorias();
      setState(() => _categorias = cats);
      // Guardar en local para offline
      await _localDb.guardarCategorias(cats);
    } catch (_) {
      // Sin conexión: cargar desde SQLite local
      final catsLocal = await _localDb.getCategoriasLocal();
      setState(() => _categorias = catsLocal);
    }
  }


  void _filtrar(String query) {
    setState(() {
      var resultado = _contactos.toList();

      // Filtro por categoría
      if (_categoriaFiltro != null) {
        resultado = resultado.where((c) => c.categoriaId == _categoriaFiltro).toList();
      }

      // Filtro por texto
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        resultado = resultado.where((c) =>
            c.nombre.toLowerCase().contains(q) ||
            c.apellido.toLowerCase().contains(q) ||
            c.telefono.contains(q) ||
            (c.ci?.contains(q) ?? false)).toList();
      }

      _filtrados = resultado;
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
            tooltip: 'Sincronizar contactos',
            onPressed: _sincronizar,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'admin':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginAdminScreen()));
                  break;
                case 'update':
                  _buscarActualizacion(manual: true);
                  break;
                case 'callerid':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CallerIdScreen()));
                  break;
                case 'scan':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EscanearAgendaScreen()));
                  break;
                case 'about':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AcercaDeScreen()));
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'callerid', child: ListTile(leading: Icon(Icons.phone_callback), title: Text('Identificador de llamadas'), dense: true)),
              const PopupMenuItem(value: 'scan', child: ListTile(leading: Icon(Icons.security), title: Text('Escanear agenda'), dense: true)),
              const PopupMenuItem(value: 'update', child: ListTile(leading: Icon(Icons.system_update), title: Text('Buscar actualización'), dense: true)),
              const PopupMenuItem(value: 'admin', child: ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Panel Admin'), dense: true)),
              const PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Acerca de'), dense: true)),
            ],
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


          // Filtro por categoría
          if (_categorias.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: const Text('Todos'),
                      selected: _categoriaFiltro == null,
                      onSelected: (_) {
                        setState(() => _categoriaFiltro = null);
                        _filtrar(_searchController.text);
                      },
                    ),
                  ),
                  ..._categorias.map((cat) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: Text(cat['icono'] ?? '📋', style: const TextStyle(fontSize: 12)),
                      label: Text(cat['nombre'] ?? '', style: const TextStyle(fontSize: 11)),
                      selected: _categoriaFiltro == cat['id'],
                      onSelected: (_) {
                        setState(() => _categoriaFiltro = _categoriaFiltro == cat['id'] ? null : cat['id']);
                        _filtrar(_searchController.text);
                      },
                    ),
                  )),
                ],
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

          // Favoritos
          if (_favoritos.isNotEmpty && _searchController.text.isEmpty && _categoriaFiltro == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('⭐ Favoritos', style: Theme.of(context).textTheme.titleSmall),
                ),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _favoritos.length,
                    itemBuilder: (ctx, i) {
                      final c = _favoritos[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: c))),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(c.nombreCompleto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text('📱 ${c.telefono}', style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
              ],
            ),

          // Favoritos
          if (_favoritos.isNotEmpty && _searchController.text.isEmpty && _categoriaFiltro == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('⭐ Favoritos', style: Theme.of(context).textTheme.titleSmall),
                ),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _favoritos.length,
                    itemBuilder: (ctx, i) {
                      final c = _favoritos[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: c))).then((_) => _cargarContactos()),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(c.nombreCompleto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(c.telefono, style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
              ],
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
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: contacto)),
        ),
        leading: CircleAvatar(
          backgroundColor: contacto.tieneReportes ? Colors.red.withOpacity(0.2) : null,
          child: contacto.tieneReportes
              ? const Icon(Icons.warning_amber, color: Colors.red, size: 20)
              : Text(
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
