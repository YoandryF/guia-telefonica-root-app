import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../services/ubicacion_service.dart';
import 'agregar_contacto_screen.dart';
import 'acerca_de_screen.dart';
import 'caller_id_screen.dart';
import 'contacto_detalle_screen.dart';
import 'escanear_agenda_screen.dart';
import 'lista_negra_screen.dart';
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
  List<Contacto> _visibles = [];
  List<Contacto> _favoritos = [];
  List<Map<String, dynamic>> _categorias = [];
  String? _categoriaFiltro;
  String? _provinciaFiltro;
  String? _municipioFiltro;
  bool _cargando = true;
  bool _online = true;
  bool _escuchando = false;
  bool _vozDisponible = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  DateTime? _ultimaSync;
  int _filtrosActivos = 0;
  static const _pageSize = 50;
  int _paginaActual = 1;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
    _cargarCategorias();
    _sincronizar();
    _verificarActualizacion();
    _initVoz();
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _online = result != ConnectivityResult.none);
      if (_online) _sincronizar();
    });
  }

  Future<void> _initVoz() async {
    // Solo verificar si el permiso ya fue concedido previamente
    // Si no, se pedirá cuando el usuario toque el botón de voz
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      _vozDisponible = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _escuchando = false);
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _escuchando = false);
          }
        },
      );
    }
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
    _aplicarFiltros();
  }

  Future<void> _sincronizar() async {
    try {
      final ultimaSync = await _localDb.getUltimaSincronizacion();
      final nuevos = await _supabaseService.getContactosAprobadosDesde(ultimaSync);

      if (nuevos.isNotEmpty) {
        await _localDb.sincronizarBatch(nuevos);
      }

      if (ultimaSync != null) {
        final eliminados = await _supabaseService.getContactosEliminadosDesde(ultimaSync);
        for (final id in eliminados) {
          await _localDb.eliminarContacto(id);
        }
      }

      await _localDb.guardarUltimaSincronizacion(DateTime.now());
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
      debugPrint('Sync error: $e');
    }
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await _supabaseService.getCategorias();
      setState(() => _categorias = cats);
      await _localDb.guardarCategorias(cats);
    } catch (_) {
      final catsLocal = await _localDb.getCategoriasLocal();
      setState(() => _categorias = catsLocal);
    }
  }

  void _aplicarFiltros() {
    setState(() {
      var resultado = _contactos.toList();
      final query = _searchController.text;

      // Filtro por categoría
      if (_categoriaFiltro == '_reportados') {
        resultado = resultado.where((c) => c.tieneReportes).toList();
      } else if (_categoriaFiltro != null) {
        resultado = resultado.where((c) => c.categoriaId == _categoriaFiltro).toList();
      }

      // Filtro por provincia
      if (_provinciaFiltro != null) {
        resultado = resultado.where((c) => c.provincia == _provinciaFiltro).toList();
      }

      // Filtro por municipio
      if (_municipioFiltro != null) {
        resultado = resultado.where((c) => c.municipio == _municipioFiltro).toList();
      }

      // Filtro por texto
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        resultado = resultado.where((c) =>
            c.nombre.toLowerCase().contains(q) ||
            c.apellido.toLowerCase().contains(q) ||
            c.telefono.contains(q) ||
            (c.ci?.contains(q) ?? false) ||
            (c.provincia?.toLowerCase().contains(q) ?? false) ||
            (c.municipio?.toLowerCase().contains(q) ?? false)).toList();
      }

      _filtrados = resultado;
      _paginaActual = 1;
      _visibles = resultado.take(_pageSize).toList();
      _filtrosActivos = (_categoriaFiltro != null ? 1 : 0) +
          (_provinciaFiltro != null ? 1 : 0) +
          (_municipioFiltro != null ? 1 : 0);
    });
  }

  void _cargarMas() {
    setState(() {
      _paginaActual++;
      _visibles = _filtrados.take(_paginaActual * _pageSize).toList();
    });
  }

  bool get _hayMas => _visibles.length < _filtrados.length;

  void _filtrar(String query) {
    _aplicarFiltros();
  }

  Future<void> _toggleVoz() async {
    if (_escuchando) {
      await _speech.stop();
      setState(() => _escuchando = false);
      return;
    }

    // Pedir permiso de micrófono explícitamente
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Permiso de micrófono denegado. Actívalo en ajustes.')),
        );
      }
      return;
    }

    if (!_vozDisponible) {
      _vozDisponible = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _escuchando = false);
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _escuchando = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${error.errorMsg}')),
            );
          }
        },
      );
      if (!_vozDisponible) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Reconocimiento de voz no disponible en este dispositivo')),
          );
        }
        return;
      }
    }

    setState(() => _escuchando = true);

    await _speech.listen(
      localeId: 'es_ES',
      listenMode: stt.ListenMode.search,
      cancelOnError: true,
      listenFor: const Duration(seconds: 10),
      onResult: (result) {
        if (mounted) {
          _searchController.text = result.recognizedWords;
          _aplicarFiltros();
          if (result.finalResult) {
            setState(() => _escuchando = false);
          }
        }
      },
    );
  }

  void _mostrarFiltros() {
    final provincias = UbicacionService.getProvincias();
    String? tempProvincia = _provinciaFiltro;
    String? tempMunicipio = _municipioFiltro;
    String? tempCategoria = _categoriaFiltro;
    List<String> municipiosDisponibles = tempProvincia != null
        ? UbicacionService.getMunicipios(tempProvincia)
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (ctx, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollController,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          tempCategoria = null;
                          tempProvincia = null;
                          tempMunicipio = null;
                          municipiosDisponibles = [];
                        });
                      },
                      child: const Text('Limpiar todo'),
                    ),
                  ],
                ),
                const Divider(),

                // Categoría
                const SizedBox(height: 8),
                Text('Categoría', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempCategoria,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todas las categorías',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    const DropdownMenuItem(value: '_reportados', child: Text('⚠️ Reportados')),
                    ..._categorias.map((cat) => DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Text('${cat['icono'] ?? "📋"} ${cat['nombre']}'),
                    )),
                  ],
                  onChanged: (v) => setSheetState(() => tempCategoria = v),
                ),

                // Provincia
                const SizedBox(height: 16),
                Text('Provincia', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempProvincia,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todas las provincias',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ...provincias.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                  ],
                  onChanged: (v) {
                    setSheetState(() {
                      tempProvincia = v;
                      tempMunicipio = null;
                      municipiosDisponibles = v != null ? UbicacionService.getMunicipios(v) : [];
                    });
                  },
                ),

                // Municipio
                const SizedBox(height: 16),
                Text('Municipio', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempMunicipio,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todos los municipios',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...municipiosDisponibles.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                  ],
                  onChanged: (v) => setSheetState(() => tempMunicipio = v),
                ),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _categoriaFiltro = tempCategoria;
                      _provinciaFiltro = tempProvincia;
                      _municipioFiltro = tempMunicipio;
                    });
                    _aplicarFiltros();
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('APLICAR FILTROS'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
            icon: Badge(
              isLabelVisible: _filtrosActivos > 0,
              label: Text('$_filtrosActivos'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filtros',
            onPressed: _mostrarFiltros,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar',
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
                case 'listanegra':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaNegraScreen()));
                  break;
                case 'about':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AcercaDeScreen()));
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'callerid', child: ListTile(leading: Icon(Icons.phone_callback), title: Text('Identificador de llamadas'), dense: true)),
              const PopupMenuItem(value: 'scan', child: ListTile(leading: Icon(Icons.security), title: Text('Escanear agenda'), dense: true)),
              const PopupMenuItem(value: 'listanegra', child: ListTile(leading: Icon(Icons.warning_amber, color: Colors.red), title: Text('Lista Negra'), dense: true)),
              const PopupMenuItem(value: 'update', child: ListTile(leading: Icon(Icons.system_update), title: Text('Buscar actualización'), dense: true)),
              const PopupMenuItem(value: 'admin', child: ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Panel Admin'), dense: true)),
              const PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Acerca de'), dense: true)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner offline
          if (!_online)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade700,
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Sin conexión — mostrando datos locales', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),

          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar contacto...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _aplicarFiltros();
                        },
                      ),
                    IconButton(
                      icon: Icon(
                        _escuchando ? Icons.mic : Icons.mic_none,
                        color: _escuchando ? Colors.red : null,
                      ),
                      onPressed: _toggleVoz,
                    ),
                  ],
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: _filtrar,
            ),
          ),

          // Indicador de escucha
          if (_escuchando)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                  ),
                  const SizedBox(width: 8),
                  const Text('Escuchando...', style: TextStyle(color: Colors.red, fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: _toggleVoz,
                    child: const Text('Detener', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Chips de filtros activos
          if (_filtrosActivos > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  if (_categoriaFiltro == '_reportados')
                    Chip(
                      label: const Text('⚠️ Reportados', style: TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _categoriaFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    )
                  else if (_categoriaFiltro != null)
                    Chip(
                      label: Text(_categorias.firstWhere((c) => c['id'] == _categoriaFiltro, orElse: () => {'nombre': '?'})['nombre'] ?? '?', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _categoriaFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_provinciaFiltro != null)
                    Chip(
                      label: Text('🗺 $_provinciaFiltro', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() { _provinciaFiltro = null; _municipioFiltro = null; }); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_municipioFiltro != null)
                    Chip(
                      label: Text('🏘 $_municipioFiltro', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _municipioFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),

          // Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text('${_visibles.length} de ${_filtrados.length} contactos', style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                if (_ultimaSync != null)
                  Text('Sync: ${_formatearFecha(_ultimaSync!)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),

          // Favoritos
          if (_favoritos.isNotEmpty && _searchController.text.isEmpty && _filtrosActivos == 0)
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
                    ? const Center(child: Text('No se encontraron contactos'))
                    : RefreshIndicator(
                        onRefresh: _sincronizar,
                        child: ListView.builder(
                          itemCount: _visibles.length + (_hayMas ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _visibles.length) {
                              // Botón "Cargar más"
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                child: OutlinedButton.icon(
                                  onPressed: _cargarMas,
                                  icon: const Icon(Icons.expand_more),
                                  label: Text('Cargar más (${_filtrados.length - _visibles.length} restantes)'),
                                ),
                              );
                            }
                            return _ContactoCard(
                              contacto: _visibles[index],
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
        leading: Hero(
          tag: 'avatar_${contacto.id}',
          child: CircleAvatar(
            backgroundColor: contacto.tieneReportes
                ? (contacto.reporteConfirmado ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2))
                : null,
            child: contacto.tieneReportes
                ? Icon(Icons.warning_amber, color: contacto.reporteConfirmado ? Colors.red : Colors.orange, size: 20)
                : Text(
                    contacto.nombre[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        title: Text(contacto.nombreCompleto),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📱 ${contacto.telefono}'),
            if (contacto.ubicacionCompleta != null)
              Text('📍 ${contacto.ubicacionCompleta}', style: Theme.of(context).textTheme.bodySmall),
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
